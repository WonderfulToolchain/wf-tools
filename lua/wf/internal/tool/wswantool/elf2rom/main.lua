-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local path = require('pl.path')
local stringx = require('pl.stringx')
local tablex = require('pl.tablex')
local utils = require('pl.utils')
local toml = require('toml')
local wfelf = require('wf.internal.elf')
local wfmath = require('wf.internal.math')
local wfpath = require('wf.internal.path')
local wfutil = require('wf.internal.util')
local wswan = require('wf.internal.platform.wswan')

local wfallocator = require('wf.internal.tool.wswantool.elf2rom.allocator')

local function romlink_calc_rom_size(rom_bank_count)
    local rom_size_id, rom_size_value
    for k, v in pairs(wswan.ROM_BANK_COUNT_TO_HEADER_SIZE) do
        if (k >= rom_bank_count) and ((rom_size_id == nil) or (k < rom_size_value)) then
            rom_size_id = v
            rom_size_value = k
        end
    end
    return rom_size_id, rom_size_value
end

local function clean_section_name(name)
    return name:gsub("[%!%&%^%$]+$", "")
end

local function entry_plus_offset(entry, offset)
    offset = offset + (entry.offset or 0)
    if entry.type == 2 then
        -- linear banks
        return ((entry.bank & 0xF) << 16) + offset
    elseif (entry.type == 0) or (entry.type == -1) then
        -- bank 0
        return 0x20000 + offset
    elseif entry.type == 1 then
        -- bank 1
        return 0x30000 + offset
    elseif entry.type == -3 then
        -- IRAM
        return 0x00000 + offset
    elseif entry.type == -2 then
        -- SRAM
        return 0x10000 + offset
    else
        error("unsupported allocator type: " .. entry.type)
    end
end

local function get_linear_address(symbol)
    if symbol[2].shndx >= wfelf.SHN_ABS then
        if symbol[2].shndx == wfelf.SHN_ABS then
            return symbol[2].value
        else
            error(string.format("unsupported ELF section index 0x%04X", symbol[2].shndx))
        end
    elseif symbol[1] == nil then
        return symbol[2].value
    else
        return entry_plus_offset(symbol[1], symbol[2].value)
    end
end

local function get_linear_logical_address(symbol, offset)
    offset = offset or 0
    local linear = get_linear_address(symbol)
    if symbol[1] ~= nil and (symbol[1].type == 2 or symbol[1].type == -1) then
        return linear + offset, (linear >> 4), offset + (linear & 0xF)
    else
        linear = linear + offset
        return linear, (linear & 0xF0000) >> 4, (linear & 0xFFFF)
    end
end

local function relocate16le(data, offset, f)
    local spot = (data:byte(offset) & 0xFF) | ((data:byte(offset + 1) & 0xFF) << 8)
    spot = f(spot)
    -- TODO: This is slow :(
    return data:sub(1, offset - 1) .. string.char(spot & 0xFF) .. string.char((spot >> 8) & 0xFF) .. data:sub(offset + 2)
end

local function emit_symbol(symbols_by_name, name, value, segment)
    symbols_by_name[name] = {
        nil,
        {
            ["value"] = value,
            ["size"] = 0,
            ["info"] = wfelf.STT_NOTYPE,
            ["other"] = 0,
            ["shndx"] = wfelf.SHN_ABS
        },
        name
    }
    symbols_by_name[name .. "!"] = {
        nil,
        {
            ["value"] = segment or 0,
            ["size"] = 0,
            ["info"] = wfelf.STT_NOTYPE,
            ["other"] = 0,
            ["shndx"] = wfelf.SHN_ABS
        },
        name .. "!"
    }
    symbols_by_name[name .. "&"] = {
        nil,
        {
            ["value"] = value,
            ["size"] = 0,
            ["info"] = wfelf.STT_NOTYPE,
            ["other"] = 0,
            ["shndx"] = wfelf.SHN_ABS
        },
        name .. "&"
    }
end

local function apply_section_name_to_entry(entry)
    local stype = nil
    if entry.name:find("^.iram[_.]") then
        stype = wfallocator.IRAM
    elseif entry.name:find("^.sram[_.]") then
        stype = wfallocator.SRAM
    elseif entry.name:find("^.rom[01L][_.]") then
        stype = 0
    end
    if stype ~= nil then
        local parts = stringx.split(stringx.split(entry.name, ".")[2], "_")
        if stype == 0 then
            if parts[1] == "rom1" then
                stype = 1
            elseif parts[1] == "romL" then
                stype = 2
            end
            if #parts >= 2 then
                local bank = (0xFFFF << (#parts[2] * 4)) & 0xFFFF
                bank = bank + tonumber(parts[2], 16)
                entry.bank = bank
            end
            if #parts >= 3 then
                entry.offset = tonumber(parts[3], 16)
            end
        elseif stype == wfallocator.SRAM then
            if #parts >= 2 then
                entry.bank = tonumber(parts[2], 16)
            end
            if #parts >= 3 then
                entry.offset = tonumber(parts[3], 16)
            end
        elseif stype == wfallocator.IRAM then
            if #parts >= 2 then
                if parts[2] == "tile" then
                    entry.offset = 0x2000
                elseif parts[2] == "tile4bpp" then
                    entry.offset = 0x4000
                else
                    entry.offset = tonumber(parts[2], 16)
                end
            end
        end
        entry.type = stype
        return true
    else
        return false
    end
end

local function romlink_run(args, linker_args)
    local gc_enabled = not args.disable_gc
    local config = toml.decodeFromFile(args.config or "wfconfig.toml")
    local allocator = wfallocator.Allocator()
    -- TODO: Valid iram_size/sram_size values.
    local allocator_config = {
        ["iram_size"] = 16384,
        ["sram_size"] = 0,
        ["rom_banks"] = config.cartridge.rom_banks
    }

    local elf_file <close> = io.open(args.input, "rb")
    local elf_file_root, elf_file_ext = path.splitext(args.input)
    local elf = wfelf.parse(elf_file, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_386)

    local rom_header = {
        ["type"] = 0,
        ["bank"] = 0xFFFF,
        ["offset"] = 0xFFF0,
        ["data"] = string.char(0):rep(16)
    }
    allocator:add(rom_header)

    local irq_vectors = {
        ["type"] = wfallocator.IRAM,
        ["offset"] = 0x0000,
        ["data"] = string.char(0):rep(64)
    }
    allocator:add(irq_vectors)

    -- Parse ELF.
    if #elf.phdr > 0 then
        error("PHDRs unsupported")
    end

    -- Allocate sections.
    local sections = {}
    local sections_by_name = {}
    local symbols = {} -- {section, offset}
    local shstrtab = elf.shdr[elf.shstrndx + 1]
    local strtab, symtab

    local retained_sections = {}

    for i=1,#elf.shdr do
        local shdr = elf.shdr[i]
        if shdr.type == wfelf.SHT_SYMTAB then
            symtab = shdr
            strtab = elf.shdr[shdr.link + 1]
        elseif ((shdr.flags & wfelf.SHF_ALLOC) ~= 0) and (shdr.size > 0) then
            local section_name = wfelf.read_string(elf_file, shstrtab, shdr.name)
            local data
            if shdr.type == wfelf.SHT_PROGBITS then
                elf_file:seek("set", shdr.offset)
                data = elf_file:read(shdr.size)
            elseif shdr.type == wfelf.SHT_NOBITS then
                data = string.char(0):rep(shdr.size)
            else
                data = nil
            end
            if data ~= nil then
                local section_entry = {
                    ["input_index"] = i - 1,
                    ["name"] = clean_section_name(section_name),
                    ["data"] = data
                }
                if shdr.addralign >= 1 then
                    section_entry.align = shdr.addralign
                elseif #data >= 2 then
                    section_entry.align = 2
                end
                if not apply_section_name_to_entry(section_entry) then
                    if stringx.startswith(section_name, ".fartext")
                    or section_name == ".text"
                    or section_name == ".start"
                    or stringx.startswith(section_name, ".farrodata") then
                        section_entry.type = 2
                        section_entry.bank = 0xFFF
                    else
                        section_entry.type = wfallocator.IRAM
                    end
                    if (shdr.flags & wfelf.SHF_GNU_RETAIN) ~= 0 then
                        retained_sections[section_entry.input_index] = true
                    end
                else
                    retained_sections[section_entry.input_index] = true
                end
                if #data > 0xFFF0 then
                    section_entry.align = 16
                end
                sections_by_name[section_entry.name] = section_entry
                sections[i] = section_entry
            end
        end
    end
    -- Link segelf symbols ("symbol!", etc.) by name to their regular variants.
    -- This allows tracking their allocated segment/offset.
    for i=1,#elf.shdr do
        if sections[i] == nil then
            local shdr = elf.shdr[i]
            local section_name = clean_section_name(wfelf.read_string(elf_file, shstrtab, shdr.name))
            if sections_by_name[section_name] ~= nil then
                sections[i] = sections_by_name[section_name]
            end
        end
    end

    -- Parse symbol table.
    local symbols = {}
    local symbols_by_name = {} 
    local symtab_count = symtab.size / symtab.entsize
    for i=1,symtab_count do
        local sym = {}
        elf_file:seek("set", symtab.offset + ((i - 1) * symtab.entsize))
        sym.name, sym.value, sym.size, sym.info, sym.other, sym.shndx = string.unpack(
            "<I4I4I4BBI2", elf_file:read(symtab.entsize)
        )
        local symbol_type = sym.info & 0xF
        local symbol_name
        if symbol_type == wfelf.STT_SECTION then
            symbol_name = wfelf.read_string(elf_file, shstrtab, elf.shdr[sym.shndx + 1].name)
        else
            symbol_name = wfelf.read_string(elf_file, strtab, sym.name)
        end
        if #symbol_name > 0 then
            local section = sections[sym.shndx + 1]
            local symbol_entry = {section, sym, symbol_name}
            symbols[i] = symbol_entry
            symbols_by_name[symbol_name] = symbol_entry
        end
    end

    -- Parse relocation table.
    local relocations = {}

    for i=1,#elf.shdr do
        local shdr = elf.shdr[i]
        if shdr.type == wfelf.SHT_REL then
            local target_section = sections[shdr.info + 1]
            if target_section == nil then
                error("could not find target for relocation section " .. wfelf.read_string(elf_file, shstrtab, elf.shdr[i].name))
            end
            local count = shdr.size / shdr.entsize
            for i=1,count do
                elf_file:seek("set", shdr.offset + ((i - 1) * shdr.entsize))
                local r_offset, r_type, r_sym = string.unpack(
                    "<I4BI3", elf_file:read(shdr.entsize)
                )
                local symbol = symbols[r_sym + 1]
                table.insert(relocations, {
                    ["offset"] = r_offset,
                    ["type"] = r_type,
                    ["section"] = target_section,
                    ["symbol"] = symbol
                })
            end
        elseif shdr.type == wfelf.SHT_RELA then
            error("'rela' relocation sections not implemented")
        end
    end

    local start_symbol = symbols_by_name["_start"]
    if start_symbol == nil then
        error("could not find symbol: _start")
    end
    retained_sections[start_symbol[1].input_index] = true
    
    if gc_enabled then
        -- Perform garbage collection by using relocation tables as a section usage map.
        local section_children = {} -- section: {sections...}

        for i, relocation in pairs(relocations) do
            local r_offset = relocation.offset
            local r_type = relocation.type
            local target_section = relocation.section
            local symbol = relocation.symbol
            
            if relocation.symbol[1] ~= nil then
                -- the symbol in this section...
                local child_id = relocation.symbol[1].input_index
                -- ... is relocated in this section.
                local parent_id = relocation.section.input_index
                if parent_id ~= nil and child_id ~= nil then
                    if section_children[parent_id] == nil then
                        section_children[parent_id] = {}
                    end
                    section_children[parent_id][child_id] = true
                end
            end
        end

        local new_retained_sections = retained_sections
        retained_sections = {}
        while next(new_retained_sections) ~= nil do
            local next_retained_sections = {}
            for i,v in pairs(new_retained_sections) do
                retained_sections[i] = true
            end
            for i,v in pairs(new_retained_sections) do
                if section_children[i] ~= nil then
                    for i2,v2 in pairs(section_children[i]) do
                        if retained_sections[i2] ~= true then
                            next_retained_sections[i2] = true
                        end
                    end
                end
            end
            new_retained_sections = next_retained_sections
        end

        for i, v in pairs(sections) do
            if #v.data > 0 and v.input_index == i - 1 then
                if retained_sections[v.input_index] then
                    allocator:add(v)
                    print("keeping " .. v.name)
                else
                    print("garbage collecting " .. v.name)
                end
            end
        end
    else
        for i, v in pairs(sections) do
            allocator:add(v)
        end
    end

    allocator:allocate(allocator_config, false)

    -- At this point, we know how big the IRAM allocation is. Copy it to ROM and emit required symbols.
    -- TODO: Implement .bss
    local iram = allocator.banks[wfallocator.IRAM][1]
    local iram_start = iram:allocation_start()
    local iram_length = ((iram:allocation_end() - iram_start + 1) + 1) & 0xFFFE
    local iram_entry = {
        ["name"] = "(wf) ROM -> IRAM copy",
        ["data"] = string.char(0):rep(iram_length),
        ["type"] = 2,
        ["bank"] = 0xFFF,
        ["align"] = 2
    }
    allocator:add(iram_entry)
    allocator:allocate(allocator_config, false)

    local heap_start, heap_length = iram:largest_gap()
    emit_symbol(symbols_by_name, "__sheap", heap_start)
    emit_symbol(symbols_by_name, "__eheap", heap_start + heap_length)
    emit_symbol(symbols_by_name, "__erom", entry_plus_offset(iram_entry, 0), entry_plus_offset(iram_entry, 0) & 0xFFFF0)
    emit_symbol(symbols_by_name, "__sdata", iram_start)
    emit_symbol(symbols_by_name, "__ldata", iram_length)
    emit_symbol(symbols_by_name, "__lwdata", iram_length >> 1)
    emit_symbol(symbols_by_name, "__edata", 0)
    emit_symbol(symbols_by_name, "__lwbss", 1)

    -- Apply relocations.
    for i, relocation in pairs(relocations) do
        local r_offset = relocation.offset
        local r_type = relocation.type
        local target_section = relocation.section
        local symbol = relocation.symbol
        if symbol[2].shndx == wfelf.SHN_UNDEF then
            -- We may have added the symbol to symbols_by_name manually.
            symbol = symbols_by_name[symbol[3]]
            if symbol == nil or symbol[2].shndx == wfelf.SHN_UNDEF then
                if stringx.startswith(symbol[3], "__bank_") then
                    -- __bank handling: Dynamically create a faux-symbol.
                    local key = symbol[3]:sub(8)
                    symbol = symbols_by_name[key]
                    if symbol == nil or symbol[1] == nil then
                        error("could not locate symbol: " .. symbol[3])
                    end
                    symbol = {nil, symbol[1].bank or 0, key}
                    symbols_by_name[key] = symbol
                else
                    error("could not locate symbol: " .. symbol[3])
                end
            end
        end

        local linear, segment, offset = get_linear_logical_address(symbol)
        if r_type == wfelf.R_386_OZSEG16 then
            target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return v + segment end)
        else
            local value = linear
            if stringx.endswith(symbol[3], "!") then
                value = segment << 4
            end
            if r_type == wfelf.R_386_16 then
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return v + value end)
            elseif r_type == wfelf.R_386_SUB16 then
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return v - value end)
            elseif r_type == wfelf.R_386_SEG16 then
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return ((v << 4) + value) >> 4 end)
            else
                error("unsupported relocation type " .. r_type)
            end
        end
    end

    -- Copy IRAM data to ROM.
    for j, entry in pairs(iram.entries) do
        local offset = entry.offset - iram_start + 1
        local length = #entry.data
        iram_entry.data = iram_entry.data:sub(1, offset - 1) .. entry.data .. iram_entry.data:sub(offset + length)
    end

    local linear, segment, offset = get_linear_logical_address(start_symbol)
    config.cartridge.start_segment = segment
    config.cartridge.start_offset = offset

    -- Final ROM allocation, calculate size.
    allocator:allocate(allocator_config, true)
    local allocated_rom_bank_count = allocator.bank_sizes[0].count
    local allocated_rom_bank_offset = allocator.banks[0][allocator.bank_sizes[0].first]:allocation_start()
    local rom_bank_type, rom_bank_count = romlink_calc_rom_size(config.cartridge.rom_banks or allocator.bank_sizes[0].count)
    local rom_bank_first = 65536 - rom_bank_count
    local rom_size_bytes = rom_bank_count * 0x10000
    config.cartridge.rom_size = rom_bank_type

    local rom_pad_byte = 0xFF
    local rom_pad_char = string.char(rom_pad_byte)
    
    -- Calculate checksum.
    local checksum = 0
    local bytes_read = 0
    for i, bank in pairs(allocator.banks[0]) do
        for j, entry in pairs(bank.entries) do
            checksum = wswan.calculate_rom_checksum(checksum, entry.data)
            bytes_read = bytes_read + #entry.data
        end
    end
    checksum = wswan.calculate_rom_checksum(checksum, wswan.calculate_rom_padding_checksum(rom_pad_byte, rom_size_bytes - bytes_read))
    rom_header.data = wswan.create_rom_header(checksum, config.cartridge)

    -- Build ROM.
    local rom_file <close> = io.open(args.output, "wb")
    local min_position = 0
    if args.trim then
        min_position = (rom_bank_count - allocated_rom_bank_count) * 0x10000 + allocated_rom_bank_offset
    end
    for i=1,(rom_size_bytes - min_position) do
        rom_file:write(rom_pad_char)
    end
    for i, bank in pairs(allocator.banks[0]) do
        for j, entry in pairs(bank.entries) do
            local offset = ((entry.bank - rom_bank_first) * 0x10000 + entry.offset) - min_position
            rom_file:seek("set", offset)
            rom_file:write(entry.data)
        end
    end

    for i, bank in pairs(allocator.banks[wfallocator.IRAM]) do
        for j, entry in pairs(bank.entries) do
            print((entry.name or "") .. " " .. entry.bank .. " " .. entry.offset)
        end
    end

    -- Build relocated ELF.
    if args.output_elf ~= nil then
        -- TODO
    end
end

return {
    ["arguments"] = [[
[args...] <input>: convert an ELF file to a wswan ROM
  -c,--config   (optional string)  Configuration file name;
                                   wfconfig.toml is used by default.
  -o,--output   (string)           Output ROM file name.
  --output-elf  (optional string)  Output ELF file name; stored on request.
  --disable-gc                     Disable section garbage collection.
  --trim                           Trim the assembled ROM by removing unused
                                   space from the beginning of the file.
  -v,--verbose                     Enable verbose logging.
  <input>       (string)           Input ELF file.
]],
    ["description"] = "convert an ELF file to a wswan ROM",
    ["run"] = romlink_run
}
