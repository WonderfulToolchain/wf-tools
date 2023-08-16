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

local EMPTY_YES = 1
local EMPTY_DONTCARE = 2

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

local function vma_entry_plus_offset(entry, offset)
    local logical_address = entry_plus_offset(entry, offset)
    if entry.type >= -2 then
        logical_address = logical_address | ((entry.bank & 0xFFF) << 20)
    end
    return logical_address
end

local function get_linear_address(symbol)
    if symbol[2] == nil then
        return entry_plus_offset(symbol[1], 0)
    elseif type(symbol[2]) == "number" then
        return symbol[2]
    elseif symbol[2].shndx >= wfelf.SHN_ABS then
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

local function get_vma_address(symbol)
    if symbol[2] == nil then
        return vma_entry_plus_offset(symbol[1], 0)
    elseif type(symbol[2]) == "number" then
        return symbol[2]
    elseif symbol[2].shndx >= wfelf.SHN_ABS then
        if symbol[2].shndx == wfelf.SHN_ABS then
            return symbol[2].value
        else
            error(string.format("unsupported ELF section index 0x%04X", symbol[2].shndx))
        end
    elseif symbol[1] == nil then
        return symbol[2].value
    else
        return vma_entry_plus_offset(symbol[1], symbol[2].value)
    end
end

local function get_linear_logical_address(symbol, offset)
    offset = offset or 0
    local linear = get_linear_address(symbol)
    local segment
    if symbol[1] ~= nil and symbol[1].segment ~= nil then
        segment = entry_plus_offset(symbol[1].segment, 0)
    elseif symbol[1] ~= nil and (symbol[1].type == 2 or symbol[1].type == -1) then
        segment = (linear & 0xFFFF0)
    else
        linear = linear + offset
        offset = 0
        segment = (linear & 0xF0000)
    end
    linear = linear + offset
    return linear, segment >> 4, linear - segment
end

local function relocate16le(data, offset, f)
    local spot = (data:byte(offset) & 0xFF) | ((data:byte(offset + 1) & 0xFF) << 8)
    spot = f(spot)
    -- TODO: This is slow :(
    return data:sub(1, offset - 1) .. string.char(spot & 0xFF) .. string.char((spot >> 8) & 0xFF) .. data:sub(offset + 2)
end

local function relocate32le(data, offset, f)
    local spot = (data:byte(offset) & 0xFF) | ((data:byte(offset + 1) & 0xFF) << 8) | ((data:byte(offset + 2) & 0xFF) << 16) | ((data:byte(offset + 3) & 0xFF) << 24)
    spot = f(spot)
    -- TODO: This is slow :(
    return data:sub(1, offset - 1) .. string.char(spot & 0xFF) .. string.char((spot >> 8) & 0xFF) .. string.char((spot >> 16) & 0xFF) .. string.char((spot >> 24) & 0xFF) .. data:sub(offset + 4)
end

local function emit_raw_symbol(symbols_by_name, name, value, section)
    symbols_by_name[name] = {
        section,
        {
            ["value"] = value,
            ["size"] = 0,
            ["info"] = wfelf.STT_NOTYPE,
            ["other"] = 0,
            ["shndx"] = wfelf.SHN_ABS
        },
        name
    }
end

local function emit_symbol(symbols_by_name, name, value, segment, section)
    emit_raw_symbol(symbols_by_name, name, value, section)
    emit_raw_symbol(symbols_by_name, name .. "!", segment or 0, section)
    emit_raw_symbol(symbols_by_name, name .. "&", value, section)
end

local function apply_section_name_to_entry(entry)
    local stype = nil
    local sempty = nil
    local iram_mode = nil
    if entry.name:find("^.iram[cC]?[_.]") then
        stype = wfallocator.IRAM
        iram_mode = entry.name[6]
    elseif entry.name:find("^.iram[cC]?x[_.]") then
        stype = wfallocator.IRAM
        sempty = EMPTY_DONTCARE
        iram_mode = entry.name[6]
    elseif entry.name:find("^.iramx[_.]") then
        stype = wfallocator.IRAM
        sempty = EMPTY_DONTCARE
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
                local i = 2
                entry.offset = {0, 0xFFFF}
                if parts[2] == "screen" then
                    entry.align = math.max(entry.align or 0, 0x800)
                    entry.offset = {0, 0x7FFF}
                    i = i + 1
                elseif parts[2] == "sprite" or parts[2] == "sprites" then
                    entry.align = math.max(entry.align or 0, 0x200)
                    entry.offset = {0, 0x7FFF}
                    i = i + 1
                elseif parts[2] == "tile" or parts[2] == "2bpp" then
                    entry.align = math.max(entry.align or 0, 0x10)
                    entry.offset = {0x2000, 0x5FFF}
                    i = i + 1
                elseif parts[2] == "4bpp" then
                    iram_mode = "c"
                    entry.align = math.max(entry.align or 0, 0x20)
                    entry.offset = {0x4000, 0xBFFF}
                    i = i + 1
                elseif parts[2] == "wave" then
                    entry.align = math.max(entry.align or 0, 0x40)
                    entry.offset = {0x0000, 0x3FFF}
                    i = i + 1
                elseif parts[2] == "palette" then
                    entry.align = math.max(entry.align or 0, 0x20)
                    entry.offset = {0xFE00, 0xFFFF}
                    i = i + 1
                end
                if #parts >= i then
                    entry.offset = tonumber(parts[i], 16)
                else
                    if iram_mode == "C" then
                        entry.offset[1] = math.max(0x4000, entry.offset[1])
                    elseif iram_mode ~= "c" then
                        entry.offset[2] = math.min(0x3FFF, entry.offset[2])
                    end
                end
            end
        end
        entry.type = stype
        if sempty ~= nil then entry.empty = sempty end
        return true
    else
        return false
    end
end

local function is_string_empty(s)
    for i=1,#s do
        if string.byte(s, i) ~= 0 then
            return false
        end
    end
    return true
end

-- At this point, we know how big the IRAM allocation is. Copy it to ROM and emit required symbols.
-- Format:
-- - length: 2 bytes
-- - offset: 2 bytes
-- - flags: 2 bytes
--   - 0x8000: followed by data if true, not followed by data if false
-- Cap size at 65520 bytes.
local function build_iram_data_push(data, joined_entry)
    if joined_entry == nil then return data end

    local length = #joined_entry.data
    local offset = joined_entry.offset
    local flags = 0
    if joined_entry.empty then flags = flags | 0x8000 end

    data = data .. string.char(length & 0xFF) .. string.char((length >> 8) & 0xFF)
    data = data .. string.char(offset & 0xFF) .. string.char((offset >> 8) & 0xFF)
    data = data .. string.char(flags & 0xFF) .. string.char((flags >> 8) & 0xFF)
    if not joined_entry.empty then data = data .. joined_entry.data end
    return data
end

local function build_iram_data(iram)
    local data = ""
    local joined_entry = nil

    for i, v in pairs(iram.entries) do
        if #v.data > 0 and v.empty ~= EMPTY_DONTCARE then
            if joined_entry == nil then
                joined_entry = tablex.copy(v)
            else
                local je_end_offset = joined_entry.offset + #joined_entry.data
                if v.offset == je_end_offset and (v.empty == true) == (joined_entry.empty == true) then
                    joined_entry.data = joined_entry.data .. v.data
                else
                    data = build_iram_data_push(data, joined_entry)
                    joined_entry = tablex.copy(v)
                end
            end
        end
    end

    data = build_iram_data_push(data, joined_entry)
    data = data .. string.char(0) .. string.char(0)
    if #data > 65520 then
        error("IRAM data block too large")
    end
    return data
end

local function romlink_run(args, linker_args)
    local gc_enabled = not args.disable_gc
    local config = toml.decodeFromFile(args.config or "wfconfig.toml")
    local allocator = wfallocator.Allocator()
    -- TODO: Valid sram_size values.
    local allocator_config = {
        ["iram_size"] = 65536,
        ["sram_size"] = 0,
        ["rom_banks"] = config.cartridge.rom_banks
    }

    local elf_file <close> = io.open(args.input, "rb")
    local elf_file_root, elf_file_ext = path.splitext(args.input)
    local elf = wfelf.ELF(elf_file, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_386)

    local rom_header = {
        ["name"] = "(wf) ROM header",
        ["type"] = 0,
        ["bank"] = 0xFFFF,
        ["offset"] = 0xFFF0,
        ["data"] = string.char(0):rep(16)
    }
    allocator:add(rom_header)

    local irq_vectors = {
        ["type"] = wfallocator.IRAM,
        ["offset"] = 0x0000,
        ["data"] = string.char(0):rep(64),
        ["empty"] = EMPTY_DONTCARE
    }
    allocator:add(irq_vectors)

    local near_section = {
        ["name"] = "(wf) near ROM section",
        ["type"] = 2,
        ["bank"] = 0xFFF,
        ["data"] = "",
        ["align"] = 16
    }

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
    local allocated_sections = {}

    for i=1,#elf.shdr do
        local shdr = elf.shdr[i]
        if shdr.type == wfelf.SHT_SYMTAB then
            symtab = shdr
            strtab = elf.shdr[shdr.link + 1]
        elseif (shdr.size > 0) then
            local section_name = wfelf.read_string(elf_file, shstrtab, shdr.name)
            local data
            local data_empty = 0
            if shdr.type == wfelf.SHT_PROGBITS then
                elf_file:seek("set", shdr.offset)
                data = elf_file:read(shdr.size)
                if is_string_empty(data) then
                    data_empty = EMPTY_YES
                end
            elseif shdr.type == wfelf.SHT_NOBITS then
                data = string.char(0):rep(shdr.size)
                data_empty = EMPTY_YES
            else
                data = nil
            end
            local section_entry = {
                ["input_index"] = i - 1,
                ["input_alloc"] = ((shdr.flags & wfelf.SHF_ALLOC) ~= 0),
                ["name"] = clean_section_name(section_name),
                ["data"] = data,
                ["empty"] = data_empty
            }
            if data ~= nil then
                if shdr.addralign >= 1 then
                    section_entry.align = shdr.addralign
                elseif #data >= 2 then
                    section_entry.align = 2
                end
                if not apply_section_name_to_entry(section_entry) then
                    if stringx.startswith(section_name, ".fartext")
                    or stringx.startswith(section_name, ".farrodata") then
                        section_entry.type = 2
                        section_entry.bank = 0xFFF
                    elseif stringx.startswith(section_name, ".text")
                    or section_name == ".start" then
                        section_entry.segment = near_section
                        section_entry.segment_offset = #near_section.data
                        near_section.data = near_section.data .. data
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
            end
            sections_by_name[section_entry.name] = section_entry
            sections[i] = section_entry
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
        if sym.shndx == wfelf.SHN_XINDEX then
            error("TODO: handle SHN_XINDEX - workaround: disable -ffunction-sections, -fdata-sections, or both")
        end
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
            if v.data ~= nil and #v.data > 0 and v.input_index == i - 1 and v.input_alloc then
                if retained_sections[v.input_index] then
                    allocated_sections[i] = v
                else
                    if args.verbose then
                        print("[gc] removing section " .. v.name)
                    end
                end
            end
        end
    else
        for i, v in pairs(sections) do
            if v.input_alloc then
                allocated_sections[i] = v
            end
        end
    end
    
    for i, v in pairs(allocated_sections) do
        if v.segment == nil then
            allocator:add(v)
        end
    end
    if #near_section.data > 0 then
        allocator:add(near_section)
    end
    allocator:allocate(allocator_config, false)

    for i, v in pairs(sections) do
        if v.segment ~= nil then
            v.type = v.segment.type
            v.bank = v.segment.bank
            v.offset = v.segment.offset + v.segment_offset
        end
    end

    local iram = allocator.banks[wfallocator.IRAM][1]
    local iram_entry = {
        ["name"] = "(wf) ROM -> IRAM copy",
        ["type"] = 2,
        ["bank"] = 0xFFF,
        ["align"] = 2
    }
    iram_entry.data = build_iram_data(iram)
    allocator:add(iram_entry)
    allocator:allocate(allocator_config, false)

    local heap_start, heap_length = iram:largest_gap(0, 0x3FFF)
    emit_symbol(symbols_by_name, "__wf_heap_start", heap_start)
    emit_symbol(symbols_by_name, "__wf_heap_top", heap_start + heap_length)
    emit_symbol(symbols_by_name, "__wf_data_block", entry_plus_offset(iram_entry, 0), entry_plus_offset(iram_entry, 0) & 0xFFFF0, iram_entry)

    emit_raw_symbol(symbols_by_name, ".debug_frame!", 0)

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
            if r_type == wfelf.R_386_32 then
                -- debug section workaround: use ELF VMA address
                value = get_vma_address(symbol)
                target_section.data = relocate32le(target_section.data, r_offset + 1, function(v) return v + value end)
            elseif r_type == wfelf.R_386_16 then
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return v + value end)
            elseif r_type == wfelf.R_386_SUB16 then
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return v - value end)
            elseif r_type == wfelf.R_386_SUB32 then
                -- debug section workaround: skip this relocation
            elseif r_type == wfelf.R_386_SEG16 then
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return ((v << 4) + value) >> 4 end)
            elseif r_type == wfelf.R_386_PC16 then
                value = value - entry_plus_offset(target_section, r_offset)
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return v + value end)
            else
                error("unsupported relocation type " .. r_type)
            end
        end
    end

    -- Copy IRAM data to ROM.
    iram_entry.data = build_iram_data(iram)
    -- Check if no data is attmepted to be written in SRAM.
    for i, bank in pairs(allocator.banks[wfallocator.SRAM]) do
        for j, entry in pairs(bank.entries) do
            if not entry.empty then
                error("unsupported: symbol " .. (entry.name or "???") .. " in SRAM contains data")
            end
        end
    end

    local linear, segment, offset = get_linear_logical_address(start_symbol)
    config.cartridge.start_segment = segment
    config.cartridge.start_offset = offset

    for i, v in pairs(sections) do
        if v.segment ~= nil then
            v.segment.data =
                v.segment.data:sub(1, v.segment_offset)
                .. v.data
                .. v.segment.data:sub(v.segment_offset + #v.data + 1)
        end
    end

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

    -- Build relocated ELF.
    -- This should be done last, as it destroys "elf".
    if args.output_elf ~= nil then
        -- Limit ELFs to 2048 banks = 128 MB. As the 2003 mapper only goes up
        -- to 64 MB, it is unlikely for ROMs to go much bigger - we'll deal
        -- with this when it becomes a problem.
        if rom_bank_first < (65536 - 0x800) then
            error("rom file too large to create ELF")
        end
        
        local out_file <close> = io.open(args.output_elf, "wb")
        local offset = elf:get_header_size()

        -- Edit ELF contents.
        elf.entry = get_vma_address(start_symbol)
        elf.phdr = {}
        local old_shdr = elf.shdr
        local old_shstrndx = elf.shstrndx

        -- TODO: Emit new symbols.
        elf.shdr = {}
        local shdr_mapping = {} -- old -> new
        for i=1,#old_shdr do
            local shdr = old_shdr[i]
            local add_shdr = false
            if shdr.type == wfelf.SHT_PROGBITS or shdr.type == wfelf.SHT_NOBITS then
                local section = sections[i]
                if section ~= nil and section.input_alloc then
                    local section_name = wfelf.read_string(elf_file, shstrtab, shdr.name)
                    local section_symbol = {section, nil, ""}
                    
                    local address = get_vma_address(section_symbol)
                    if stringx.endswith(section_name, "!") then
                        local linear, segment, offset = get_linear_logical_address(section_symbol)
                        shdr.addr = (address & 0xFFF00000) | (segment << 4)
                    elseif stringx.endswith(section_name, "&") then
                        shdr.addr = (address & 0xFFF00000) | ((address + #section.data) & 0x000FFFFF)
                    else
                        shdr.addr = address
                    end
                end

                shdr.offset = offset
                if section == nil or (section.input_alloc and (not allocated_sections[i])) then
                    shdr.size = 0
                else
                    shdr.size = #section.data

                    out_file:seek("set", offset)
                    out_file:write(section.data)
                end
                add_shdr = true
            elseif shdr.type == wfelf.SHT_STRTAB then
                elf_file:seek("set", shdr.offset)
                shdr.offset = offset

                out_file:seek("set", offset)
                out_file:write(elf_file:read(shdr.size))
                add_shdr = true
            elseif shdr.type == wfelf.SHT_SYMTAB then
                -- Emit new symbol table
                local symtab_pack = "<I4I4I4BBI2"
                symtab.entsize = string.packsize(symtab_pack)
                symtab.size = 0
                symtab.offset = offset
                out_file:seek("set", offset)

                for i, sym in pairs(symbols) do
                    local shndx = wfelf.SHN_ABS
                    if sym[2] ~= nil then
                        if sym[2].shndx ~= nil then
                            shndx = sym[2].shndx
                            if shndx < 0xFFF0 then
                                local map = shdr_mapping[shndx + 1]
                                if map ~= nil then
                                    shndx = map - 1
                                end
                            end
                        end

                        out_file:write(string.pack(symtab_pack,
                            sym[2].name, sym[2].value, sym[2].size, sym[2].info, sym[2].other,
                            shndx
                        ))
                        symtab.size = symtab.size + symtab.entsize
                    end
                end

                offset = offset + symtab.size
                add_shdr = true
            end

            if add_shdr then
                offset = offset + shdr.size
                table.insert(elf.shdr, shdr)
                shdr_mapping[i] = #elf.shdr
            end
        end

        -- Fix shdr.link mappings.
        elf.shstrndx = shdr_mapping[elf.shstrndx + 1] - 1
        for i=1,#elf.shdr do
            local shdr = elf.shdr[i]
            if shdr_mapping[shdr.link + 1] then
                shdr.link = shdr_mapping[shdr.link + 1] - 1
            end
        end

        out_file:seek("set", 0)
        elf:write_header(out_file)
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
