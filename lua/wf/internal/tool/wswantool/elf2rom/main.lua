-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local log = require('wf.internal.log')
local path = require('pl.path')
local stringx = require('pl.stringx')
local tablex = require('pl.tablex')
local utils = require('pl.utils')
local toml = require('wf.internal.toml')
local wfelf = require('wf.internal.elf')
local wfmath = require('wf.internal.math')
local wfnative = require('wf.internal.native')
local wfpath = require('wf.internal.path')
local wfutil = require('wf.internal.util')
local wswan = require('wf.internal.platform.wswan')

local wfallocator = require('wf.internal.tool.wswantool.elf2rom.allocator')
local wfsymbol = require('wf.internal.tool.wswantool.elf2rom.symbol')

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
        log.fatal("unsupported allocator type: " .. entry.type)
    end
end

local function vma_entry_plus_offset(entry, offset)
    local logical_address = entry_plus_offset(entry, offset)
    if entry.type >= -2 and entry.bank ~= nil then
        logical_address = logical_address | ((entry.bank & 0xFFF) << 20)
        if entry.type >= 0 then -- ROM address
            logical_address = logical_address | 0x80000000
        end
    end
    return logical_address
end

local function get_linear_address(symbol)
    if symbol.value ~= nil then
        -- symbol is hardcoded address
        return symbol.value
    elseif symbol.elf == nil then
        -- symbol points to section
        return entry_plus_offset(symbol.section, 0)
    elseif symbol.elf.shndx >= wfelf.SHN_ABS then
        -- handle special sections
        if symbol.elf.shndx == wfelf.SHN_ABS then
            return symbol.elf.value
        else
            log.error("unsupported ELF section index: 0x%04X", symbol.elf.shndx)
        end
    elseif symbol.section == nil then
        -- symbol has no section, value only
        return symbol.elf.value
    else
        -- symbol has section + value
        return entry_plus_offset(symbol.section, symbol.elf.value)
    end
end

local function get_vma_address(symbol)
    if symbol.value ~= nil then
        return symbol.value
    elseif symbol.elf == nil then
        return vma_entry_plus_offset(symbol.section, 0)
    elseif symbol.elf.shndx >= wfelf.SHN_ABS then
        if symbol.elf.shndx == wfelf.SHN_ABS then
            return symbol.elf.value
        else
            log.error("unsupported ELF section index: 0x%04X", symbol.elf.shndx)
        end
    elseif symbol.section == nil then
        return symbol.elf.value
    else
        return vma_entry_plus_offset(symbol.section, symbol.elf.value)
    end
end

local function get_linear_logical_address(symbol, offset)
    offset = offset or 0
    local linear = get_linear_address(symbol)
    local segment
    if symbol.section ~= nil and symbol.section.segment ~= nil and symbol.section.segment.type ~= wfallocator.IRAM then
        segment = entry_plus_offset(symbol.section.segment, 0)
    elseif symbol.section ~= nil and (symbol.section.type == 2 or symbol.section.type == -1) then
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
    spot = string.char(spot & 0xFF, (spot >> 8) & 0xFF)
    return wfnative.replace(data, spot, offset)
end

local function relocate32le(data, offset, f)
    local spot = (data:byte(offset) & 0xFF) | ((data:byte(offset + 1) & 0xFF) << 8) | ((data:byte(offset + 2) & 0xFF) << 16) | ((data:byte(offset + 3) & 0xFF) << 24)
    spot = f(spot)
    spot = string.char(spot & 0xFF, (spot >> 8) & 0xFF, (spot >> 16) & 0xFF, (spot >> 24) & 0xFF)
    return wfnative.replace(data, spot, offset)
end

local function emit_raw_symbol(symbols, name, value, section)
    symbols[name] = wfsymbol.Symbol({
        section=section,
        value=value,
        name=name
    })
end

local function emit_symbol(symbols, name, value, segment, section)
    emit_raw_symbol(symbols, name, value, section)
    emit_raw_symbol(symbols, name .. "!", segment or 0, section)
    emit_raw_symbol(symbols, name .. "&", value, section)
end

local function apply_section_name_to_entry(entry, rom_banks)
    rom_banks = rom_banks or 0
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

                -- Wrap bank index around the number of available ROM banks.
                if rom_banks > 0 then
                    if stype == 2 then
                        rom_banks = (rom_banks + 15) >> 4
                    end
                    bank = (bank % rom_banks) + 0x10000 - rom_banks
                end

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
                    if iram_mode == "C" and entry.offset[2] >= 0x4000 then
                        entry.offset[1] = math.max(0x4000, entry.offset[1])
                    elseif iram_mode ~= "c" and entry.offset[1] < 0x4000 then
                        entry.offset[2] = math.min(0x3FFF, entry.offset[2])
                    end
                end
            end
        end
        entry.type = stype
        if sempty ~= nil then entry.empty = sempty end
        return true, stype < 0
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
local function build_iram_data_push(data, joined_entry, platform)
    if joined_entry == nil then return data end
    if platform.mode == "bfb" and (not joined_entry.empty) then return data end

    local length = #joined_entry.data
    local offset = joined_entry.offset
    local flags = 0
    if joined_entry.empty > 0 then flags = flags | 0x8000 end

    data = data .. string.char(length & 0xFF, (length >> 8) & 0xFF)
    data = data .. string.char(offset & 0xFF, (offset >> 8) & 0xFF)
    if platform.mode ~= "bfb" then
        data = data .. string.char(flags & 0xFF, (flags >> 8) & 0xFF)
    end
    if joined_entry.empty <= 0 then data = data .. joined_entry.data end
    return data
end

local function build_iram_data(iram, platform)
    local data = ""
    local joined_entry = nil

    for i, v in pairs(iram.entries) do
        if #v.data > 0 and v.empty ~= EMPTY_DONTCARE then
            if joined_entry == nil then
                joined_entry = tablex.copy(v)
            else
                local je_end_offset = joined_entry.offset + #joined_entry.data
                if v.offset == je_end_offset and v.empty ~= nil and joined_entry.empty ~= nil and (v.empty > 0) == (joined_entry.empty > 0) then
                    joined_entry.data = joined_entry.data .. v.data
                else
                    data = build_iram_data_push(data, joined_entry, platform)
                    joined_entry = tablex.copy(v)
                end
            end
        end
    end

    data = build_iram_data_push(data, joined_entry, platform)
    data = data .. string.char(0, 0)
    if #data > 0xFFF0 then
        log.error("IRAM data block too large")
    end
    return data
end

local function run_linker(args, platform)
    log.verbose = log.verbose or args.verbose

    local config = {}
    local config_filename = args.config or "wfconfig.toml"
    if (args.config ~= nil) or path.exists(config_filename) then
        config = toml.decodeFromFile(config_filename)
    end
    if config.cartridge == nil then
        config.cartridge = {}
    end

    local gc_enabled = not args.disable_gc
    local allocator = wfallocator.Allocator()
    local allocator_config = {
        ["iram_size"] = 65536,
        ["sram_size"] = 0,
        ["rom_banks"] = 0,
        ["bootrom_area_reserved"] = config.cartridge.rom_reserve_bootrom_area or false
    }

    local elf_file <close> = io.open(args.input, "rb")
    if elf_file == nil then
        log.error("could not open '" .. args.input .. "' for reading")
        log.exit_if_fatal()
    end

    local elf = wfelf.ELF(elf_file, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_386, wfelf.ET_REL)

    local default_alloc_type = nil
    local default_alloc_bank = nil
    local default_alloc_offset = nil
    local far_sections_supported = false
    local rom_header = nil

    if platform.mode == "cartridge" then
        allocator_config.rom_banks = config.cartridge.rom_banks
        allocator_config.rom_last_bank = config.cartridge.rom_last_bank or 65535
       
        local save_type = wswan.get_save_type(config.cartridge)
        if save_type ~= nil then
            allocator_config.sram_size = wswan.SRAM_SIZE_BY_TYPE[save_type] or 0
        end
        
        rom_header = {
            ["name"] = "(wf) ROM header",
            ["type"] = 0,
            ["bank"] = allocator_config.rom_last_bank,
            ["offset"] = 0xFFF0,
            ["data"] = string.char(0):rep(16)
        }
        allocator:add(rom_header)

        default_alloc_type = 2
        default_alloc_bank = allocator_config.rom_last_bank >> 4
        far_sections_supported = true
    elseif platform.mode == "bfb" then
        default_alloc_type = wfallocator.IRAM
        default_alloc_bank = 1
        default_alloc_offset = {0x6800, 0xFDFF}
        far_sections_supported = true
    elseif platform.mode == "wgate" then
        allocator_config.sram_size = 65536

        local sram_padding = {
            ["name"] = "(wf) SRAM padding",
            ["type"] = wfallocator.SRAM,
            ["bank"] = 0,
            ["offset"] = 0,
            ["data"] = string.char(0):rep(0x10)
        }
        allocator:add(sram_padding)

        default_alloc_type = wfallocator.SRAM
        default_alloc_bank = 0

        -- TODO: Set to false once near_section supports garbage collection
        far_sections_supported = true
    else
        log.error("unsupported platform: " .. platform.mode)
    end

    log.exit_if_fatal()

    local near_section = {
        ["name"] = "(wf) near section",
        ["type"] = default_alloc_type,
        ["bank"] = default_alloc_bank,
        ["offset"] = default_alloc_offset,
        ["data"] = "",
        ["align"] = 16
    }

    local irq_vectors = {
        ["type"] = wfallocator.IRAM,
        ["offset"] = 0x0000,
        ["data"] = string.char(0):rep(64),
        ["empty"] = EMPTY_DONTCARE
    }
    allocator:add(irq_vectors)

    -- Parse ELF.
    if #elf.phdr > 0 then
        log.error("unsupported ELF PHDRs")
    end

    log.exit_if_fatal()

    -- Allocate sections.
    local sections = {}
    local sections_by_name = {}
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
                local is_custom_section_name, is_force_retain = apply_section_name_to_entry(section_entry, allocator_config.rom_banks)
                if not is_custom_section_name then
                    if stringx.startswith(section_name, ".fartext")
                    or stringx.startswith(section_name, ".farrodata")
                    or (stringx.startswith(section_name, ".fardata") and (near_section.type == wfallocator.SRAM or near_section.type == wfallocator.IRAM)) then
                        if far_sections_supported then
                            section_entry.type = default_alloc_type
                            section_entry.bank = default_alloc_bank
                            section_entry.offset = default_alloc_offset
                        else
                            section_entry.segment = near_section
                            section_entry.segment_offset = #near_section.data
                            near_section.data = near_section.data .. data
                        end
                    elseif section_name == ".start" then
                        -- append at beginning
                        section_entry.segment = near_section
                        section_entry.segment_offset = 0
                        near_section.data = data .. near_section.data
                        for i,v in pairs(sections) do
                            if v.segment == near_section then
                                v.segment_offset = v.segment_offset + #data
                            end
                        end
                    elseif stringx.startswith(section_name, ".stext")
                    or stringx.startswith(section_name, ".srodata")
                    or stringx.startswith(section_name, ".sdata")
                    or stringx.startswith(section_name, ".sbss")
                    or stringx.startswith(section_name, ".snoinit") then
                        section_entry.type = wfallocator.IRAM
                    elseif stringx.startswith(section_name, ".text")
                    or (platform.mode == "bfb" and section_entry.input_alloc and data_empty == 0) then
                        -- append at end
                        section_entry.segment = near_section
                        section_entry.segment_offset = #near_section.data
                        near_section.data = near_section.data .. data
                    elseif args.ds_sram then
                        section_entry.type = wfallocator.SRAM
                    else
                        section_entry.type = wfallocator.IRAM
                    end
                elseif is_force_retain then
                    retained_sections[section_entry.input_index] = true
                end
                if (shdr.flags & wfelf.SHF_GNU_RETAIN) ~= 0 then
                    retained_sections[section_entry.input_index] = true
                end
                if #data > 0xFFF1 then
                    -- ensure memory cell ((offset & 15) + #data - 1) is always reachable via alignment
                    section_entry.align = wfmath.next_power_of_two(#data - 0xFFF0)
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

    log.exit_if_fatal()

    -- Parse symbol table.
    local symbols_elf_idx = {}
    local symbols = {} 
    local symtab_count = symtab.size / symtab.entsize
    for i=1,symtab_count do
        local sym = {}
        elf_file:seek("set", symtab.offset + ((i - 1) * symtab.entsize))
        sym.name, sym.value, sym.size, sym.info, sym.other, sym.shndx = string.unpack(
            "<I4I4I4BBI2", elf_file:read(symtab.entsize)
        )
        if sym.shndx == wfelf.SHN_XINDEX then
            log.error("unsupported ELF SHN_XINDEX (as a workaround, disable -ffunction-sections, -fdata-sections, or both)")
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
            local symbol = wfsymbol.Symbol({section=section, elf=sym, name=symbol_name})
            symbols_elf_idx[i] = symbol
            symbols[symbol_name] = symbol
        end
    end

    -- Parse relocation table.
    local relocations = {}

    for i=1,#elf.shdr do
        local shdr = elf.shdr[i]
        if shdr.type == wfelf.SHT_REL then
            local target_section = sections[shdr.info + 1]
            if target_section == nil then
                log.error("could not find target for relocation section " .. wfelf.read_string(elf_file, shstrtab, elf.shdr[i].name))
            end
            if target_section.empty > 0 then
                target_section.empty = 0
            end
            local count = shdr.size / shdr.entsize
            for i=1,count do
                elf_file:seek("set", shdr.offset + ((i - 1) * shdr.entsize))
                local r_offset, r_type, r_sym = string.unpack(
                    "<I4BI3", elf_file:read(shdr.entsize)
                )
                local symbol = symbols_elf_idx[r_sym + 1]
                table.insert(relocations, {
                    ["offset"] = r_offset,
                    ["type"] = r_type,
                    ["section"] = target_section,
                    ["symbol"] = symbol
                })
            end
        elseif shdr.type == wfelf.SHT_RELA then
            log.error("'rela' relocation sections not implemented")
        end
    end

    log.exit_if_fatal()

    local start_symbol = symbols["_start"]
    if start_symbol == nil then
        log.error("could not find symbol: _start")
    else
        retained_sections[start_symbol.section.input_index] = true
    end
 
    log.exit_if_fatal()

    if gc_enabled then
        -- Perform garbage collection by using relocation tables as a section usage map.
        local section_children = {} -- section: {sections...}

        for i, relocation in pairs(relocations) do
            local target_section = relocation.section
            local symbol = relocation.symbol
            
            if symbol.section ~= nil then
                -- the symbol in this section...
                local child_id = symbol.section.input_index
                -- ... is relocated in this section.
                local parent_id = target_section.input_index
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
            for i, _ in pairs(new_retained_sections) do
                retained_sections[i] = true

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
                    log.info("gc: removing section " .. v.name)
                end
            end
        end
    else
        for i, v in pairs(sections) do
            if v.data ~= nil and #v.data > 0 and v.input_index == i - 1 and v.input_alloc then
                allocated_sections[i] = v
            end
        end
    end
    
    for _, v in pairs(allocated_sections) do
        if v.segment == nil then
            allocator:add(v)
        end
    end
    if #near_section.data > 0 then
        allocator:add(near_section)
    end
    allocator:allocate(allocator_config, false)

    for _, v in pairs(sections) do
        if v.segment ~= nil then
            v.type = v.segment.type
            v.bank = v.segment.bank
            v.offset = v.segment.offset + v.segment_offset
        end
    end

    local iram = allocator.banks[wfallocator.IRAM][1]
    if args.ds_sram then
        iram = allocator.banks[wfallocator.SRAM][0]
    end

    local iram_entry = {
        ["name"] = "(wf) ROM -> IRAM copy",
        ["type"] = default_alloc_type,
        ["bank"] = default_alloc_bank,
        ["offset"] = default_alloc_offset,
        ["align"] = 2
    }
    if args.ds_sram or platform.mode == "bfb" then
        iram_entry.align = 1
    end
    iram_entry.data = build_iram_data(iram, platform)
    allocator:add(iram_entry)
    allocator:allocate(allocator_config, false)

    local heap_start, heap_length
    if args.ds_sram then
        heap_start, heap_length = iram:find_gap(0, 0xFFFE, true)
    elseif platform.mode == "bfb" then
        heap_start, heap_length = iram:find_gap(0, 0xFE00, true)
    else
        heap_start, heap_length = iram:find_gap(0, 0x4000, true)
    end
    emit_symbol(symbols, "__wf_heap_start", heap_start)
    emit_symbol(symbols, "__wf_heap_top", heap_start + heap_length)
    emit_symbol(symbols, "__wf_data_block", entry_plus_offset(iram_entry, 0), entry_plus_offset(iram_entry, 0) & 0xFFFF0, iram_entry)

    emit_raw_symbol(symbols, ".debug_frame!", 0)

    -- Apply relocations.
    local symbols_not_found = {}
    for _, relocation in pairs(relocations) do
        local r_offset = relocation.offset
        local r_type = relocation.type
        local target_section = relocation.section
        local symbol = relocation.symbol

        local symbol_found = symbol:is_defined()
        if not symbol_found then
            -- We may have added the symbol to symbols manually.
            if symbols[symbol.name] ~= nil then
                symbol = symbols[symbol.name]
                local symbol_key = symbol.name
                symbol_found = symbol ~= nil and symbol:is_defined()
                if not symbol_found then
                    if stringx.startswith(symbol.name, "__bank_") then
                        -- __bank handling: Dynamically create a faux-symbol.
                        symbol_key = symbol.name:sub(8)
                        if symbols[symbol_key] ~= nil then
                            symbol = symbols[symbol_key]
                            if symbol ~= nil and symbol.section ~= nil then
                                symbol = wfsymbol.Symbol({value=symbol.section.bank or 0, name=symbol_key})
                                symbols[symbol_key] = symbol
                                symbol_found = true
                            end
                        end
                    end
                end
            end

            if not symbol_found then
                if symbols_not_found[symbol.name] == nil then
                    symbols_not_found[symbol.name] = true
                    log.error("could not locate symbol: " .. symbol.name)
                end
            end
        end

        if symbol_found then
            local linear, segment, _ = get_linear_logical_address(symbol)
            if r_type == wfelf.R_386_OZSEG16 then
                target_section.data = relocate16le(target_section.data, r_offset + 1, function(v) return v + segment end)
            else
                local value = linear
                if stringx.endswith(symbol.name, "!") then
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
                    log.error("unsupported relocation type " .. r_type)
                end
            end
        end
    end

    log.exit_if_fatal()

    -- Copy IRAM data to ROM.
    iram_entry.data = build_iram_data(iram, platform)
    -- Check if no data is attmepted to be written in SRAM (DS == IRAM).
    if platform.mode == "cartridge" and not args.ds_sram then
        for i, bank in pairs(allocator.banks[wfallocator.SRAM]) do
            for j, entry in pairs(bank.entries) do
                if entry.empty == 0 then
                    log.error("unsupported: symbol " .. (entry.name or "???") .. " in SRAM contains data")
                end
            end
        end
    end
    -- Check if no data is attmepted to be written in IRAM (DS == SRAM).
    if platform.mode == "cartridge" and args.ds_sram then
        for i, bank in pairs(allocator.banks[wfallocator.IRAM]) do
            for j, entry in pairs(bank.entries) do
                if entry.empty == 0 then
                    log.error("unsupported: symbol " .. (entry.name or "???") .. " in IRAM contains data")
                end
            end
        end
    end

    log.exit_if_fatal()

    -- Finalize allocation.
    for i, v in pairs(sections) do
        if v.segment ~= nil then
            v.segment.data = wfnative.replace(v.segment.data, v.data, v.segment_offset + 1)
        end
    end
    allocator:allocate(allocator_config, true)

    -- Build data.
    if platform.mode == "cartridge" then
        local allocated_rom_bank_count = allocator.bank_sizes[0].count or 0
        local allocated_rom_bank_offset = 0
        if allocator.bank_sizes[0].first ~= nil then
            allocated_rom_bank_offset = allocator.banks[0][allocator.bank_sizes[0].first]:allocation_start()
        end
        local rom_bank_type, rom_bank_count = romlink_calc_rom_size(config.cartridge.rom_banks or allocator.bank_sizes[0].count or 0)
        local rom_bank_first = allocator_config.rom_last_bank + 1 - rom_bank_count
        local rom_size_bytes = rom_bank_count * 0x10000

        -- ELF output checks.
        if args.output_elf ~= nil then
            -- Limit ELF address space to 2048 banks = 128 MB. As the 2003 mapper
            -- only goes up to 64 MB, it is unlikely for ROMs to go much bigger.
            -- We can deal with this when it becomes a problem.
            if rom_bank_first < (((allocator_config.rom_last_bank + 0x800) & (~0x7FF)) - 0x800) then
                log.error("rom file too large to create ELF")
            end
        end

        log.exit_if_fatal()

        local _, segment, offset = get_linear_logical_address(start_symbol)
        config.cartridge.start_segment = segment
        config.cartridge.start_offset = offset
        config.cartridge.rom_size = rom_bank_type

        local rom_pad_byte = 0xFF
        local rom_pad_char = string.char(rom_pad_byte)
        
        -- Calculate checksum.
        local checksum = 0
        local bytes_read = 0
        for _, bank in pairs(allocator.banks[0]) do
            for _, entry in pairs(bank.entries) do
                checksum = wswan.calculate_rom_checksum(checksum, entry.data)
                bytes_read = bytes_read + #entry.data
            end
        end
        checksum = wswan.calculate_rom_checksum(checksum, wswan.calculate_rom_padding_checksum(rom_pad_byte, rom_size_bytes - bytes_read))
        rom_header.data = wswan.create_rom_header(checksum, config.cartridge)

        -- Build ROM.
        local rom_file <close> = io.open(args.output, "wb")
        if rom_file == nil then
            log.error("could not open '" .. args.output .. "' for writing")
            log.exit_if_fatal()
        end
        local min_position = 0
        if args.trim then
            min_position = (rom_bank_count - allocated_rom_bank_count) * 0x10000 + allocated_rom_bank_offset
        end
        rom_file:write(rom_pad_char:rep(rom_size_bytes - min_position))
        for i, bank in pairs(allocator.banks[0]) do
            for j, entry in pairs(bank.entries) do
                local offset = ((entry.bank - rom_bank_first) * 0x10000 + entry.offset) - min_position
                rom_file:seek("set", offset)
                rom_file:write(entry.data)
            end
        end
    elseif platform.mode == "wgate" then
        -- Build binary.
        local rom_file <close> = io.open(args.output, "wb")
        for i, entry in pairs(allocator.banks[wfallocator.SRAM][0].entries) do
            local offset = entry.offset - 0x10
            rom_file:seek("set", offset)
            rom_file:write(entry.data)
        end
    elseif platform.mode == "bfb" then
        local _, segment, offset = get_linear_logical_address(start_symbol)
        if segment ~= 0x0000 then
            log.error("unsupported: non-zero .bfb start segment [%04X:%04X]", segment, offset)
        end

        log.exit_if_fatal()

        local rom_file <close> = io.open(args.output, "wb")
        rom_file:write("bF")
        rom_file:write(string.char(offset & 0xFF, offset >> 8))
        for _, entry in pairs(allocator.banks[wfallocator.IRAM][1].entries) do
            local offset = entry.offset - offset
            local is_empty = is_string_empty(entry.data)
            if offset < 0 and not is_empty then
                log.error("unsupported: non-empty entry outside of data region")
            end
            if not is_empty then
                rom_file:seek("set", offset + 4)
                rom_file:write(entry.data)
            end
        end
    else
        log.error("unsupported mode: " .. platform.mode)
    end

    log.exit_if_fatal()

    -- Build relocated ELF.
    -- This should be done last, as it destroys "elf".
    if args.output_elf ~= nil then
        local out_file <close> = io.open(args.output_elf, "wb")
        local offset = elf:get_header_size()

        -- Edit ELF contents.
        elf.type = wfelf.ET_EXEC
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
            if shdr.type == wfelf.SHT_PROGBITS or shdr.type == wfelf.SHT_NOBITS or shdr.type == wfelf.SHT_NULL then
                local section = sections[i]
                if section ~= nil and section.input_alloc then
                    local section_name = wfelf.read_string(elf_file, shstrtab, shdr.name)
                    local section_symbol = wfsymbol.Symbol({section=section, name=""})

                    local address = get_vma_address(section_symbol)
                    if stringx.endswith(section_name, "!") then
                        local _, segment, _ = get_linear_logical_address(section_symbol)
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

                for _, symbol in pairs(symbols_elf_idx) do
                    local shndx = wfelf.SHN_ABS
                    if symbol.elf ~= nil then
                        if symbol.elf.shndx ~= nil then
                            shndx = symbol.elf.shndx
                            if shndx < 0xFFF0 then
                                local map = shdr_mapping[shndx + 1]
                                if map ~= nil then
                                    shndx = map - 1
                                end
                            end
                        end

                        out_file:write(string.pack(symtab_pack,
                            symbol.elf.name, symbol.elf.value, symbol.elf.size, symbol.elf.info, symbol.elf.other,
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

    log.exit_if_fatal()
end

local args_doc = [[
    -c,--config   (optional string)  Configuration file name;
                                     wfconfig.toml is used by default.
    -o,--output   (string)           Output file name.
    --output-elf  (optional string)  Output ELF file name; stored on request.
    --disable-gc                     Disable section garbage collection.
    -v,--verbose                     Enable verbose logging.
    <input>       (string)           Input ELF file.
]]

return {
    ["bfb"] = {
        ["arguments"] = [[
[args...] <input>: convert a wswan ELF file to a BootFriend executable
]] .. args_doc,
        ["description"] = "convert a wswan ELF file to a BootFriend executable",
        ["run"] = function(args)
            return run_linker(args, {
                ["mode"] = "bfb"
            })
        end
    },
    ["rom"] = {
        ["arguments"] = [[
[args...] <input>: convert a wswan ELF file to a ROM
    --ds-sram                        Place the default data segment in SRAM.
    --trim                           Trim the assembled ROM by removing unused
                                     space from the beginning of the file.
]] .. args_doc,
        ["description"] = "convert a wswan ELF file to a ROM",
        ["run"] = function(args)
            return run_linker(args, {
                ["mode"] = "cartridge"
            })
        end
    },
    ["wgate"] = {
        ["arguments"] = [[
[args...] <input>: convert a wswan ELF file to a WGate executable
]] .. args_doc,
        ["description"] = "convert a wswan ELF file to a WGate executable",
        ["run"] = function(args)
            return run_linker(args, {
                ["mode"] = "wgate"
            })
        end
    }
}
