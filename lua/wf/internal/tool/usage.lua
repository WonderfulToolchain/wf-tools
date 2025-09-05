-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local log = require('wf.internal.log')
local path = require('pl.path')
local stringx = require('pl.stringx')
local tablex = require('pl.tablex')
local toml = require('wf.internal.toml')
local wfelf = require('wf.internal.elf')
local wfterm = require('wf.internal.term')
local wfwswan = require('wf.internal.platform.wswan')

local targets = {}

targets.gba = {}
targets.gba.load_elf = function(file)
    return wfelf.ELF(file, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_ARM)
end

targets.gba.group_address_ranges = {
    {0x02000000, 0x0203ffff},
    {0x03000000, 0x03007fff},
    {0x06000000, 0x06017fff},
    {0x08000000, 0x09ffffff}
}

targets.gba.address_ranges_to_banks = function(ranges, config)
    local banks = {}
    table.insert(banks, {name="IWRAM", range={0x03000000, 0x03007fff}, size=32768, mask=0x7fff})
    table.insert(banks, {name="EWRAM", range={0x02000000, 0x0203ffff}, size=262144, mask=0x3ffff})
    if ranges[3] ~= nil then
        table.insert(banks, {name="VRAM", range={0x06000000, 0x06017fff}, size=96*1024, mask=0x1ffff})
    end
    if ranges[4] ~= nil then
        table.insert(banks, {name="ROM", range={0x08000000, 0x09ffffff}, size=32*1024*1024, mask=0x1ffffff})
    end
    return banks
end

-- IRAM
-- +- Mono
-- +- Color
-- SRAM
-- +- $00
-- Cartridge ROM
-- +- Bank $F0
-- +- Linear $Fx
--    +- Bank $FF

targets.wswan = {}
targets.wswan.load_elf = function(file)
    return wfelf.ELF(file, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_386)
end

targets.wswan.group_address_ranges = {
    {0x00000000, 0x0000ffff},
    {0x10000000, 0x1fffffff},
    {0x20000000, 0x2fffffff}
}

-- Map ELF addresses to:
-- 0x0000nnnn - IRAM
-- 0x1bbbnnnn - SRAM
-- 0x2bbbnnnn - ROM
targets.wswan.map_address = function(address)
    if address <= 0xffff then return address end
    if (address & 0xf0000) == 0x10000 then
        return 0x10000000 | ((address >> 4) & 0xfff0000) | (address & 0xffff)
    end
    if address >= 0x80000000 then
        return 0x20000000 | ((address >> 4) & 0xfff0000) | (address & 0xffff)
    end
    return nil
end

targets.wswan.address_ranges_to_banks = function(ranges, config)
    local banks = {}
    if ranges[1] ~= nil then
        local bank_iram = {name="IRAM", range={0x00000000, 0x00003fff}, size=16384, mask=0xFFFF}
        table.insert(banks, bank_iram)
        if ranges[1][2] >= 0x4000 then
            bank_iram.range[2] = 0x0000ffff
            bank_iram.size = 65536
            table.insert(banks, {name="Mono", depth=1, range={0x00000000, 0x00003fff}, size=16384, mask=0xFFFF})
            table.insert(banks, {name="Color", depth=1, range={0x00004000, 0x0000ffff}, size=49152, mask=0xFFFF})
        end
    end

    local sram_size = wfwswan.SRAM_SIZE_BY_TYPE[config.cartridge.save_type or "NONE"] or 0
    if sram_size == 0 and ranges[2] ~= nil then
        -- Estimate SRAM size
        sram_size = ((ranges[2][2] >> 16) - 0x1000) * 65536
    end
    if sram_size > 0 then
        local sram_last = 0x10000000 + sram_size - 1
        table.insert(banks, {name="SRAM", range={0x10000000, sram_last}, size=sram_size, mask=sram_last-0x10000000})
        for i=0,sram_size-1,65536 do
            local bank_size = sram_size - i
            if bank_size > 65536 then bank_size = 65536 end
            local sram_first = ((i & 0xFFFF0000) << 4) | 0x10000
            local sram_last = ((i & 0xFFFF0000) << 4) | 0x1ffff
            table.insert(banks, {name=string.format("$%02X", i >> 16), depth=1, range={sram_first, sram_last}, size=65536})
        end
    end

    if ranges[3] ~= nil then
        local rom_size = 0
        if config.cartridge.rom_banks then
            rom_size = config.cartridge.rom_banks * 65536
        end
        local elf_rom_size = ((ranges[3][2] >> 16) - (ranges[3][1] >> 16) + 1) * 65536
        if rom_size < elf_rom_size then rom_size = elf_rom_size end

        local banks_count = math.ceil(rom_size / 65536)
        local banks_width_small = math.ceil(math.log(banks_count, 2) / 4)
        if banks_width_small < 1 then banks_width_small = 1 end
        local banks_width = banks_width_small
        if banks_width < 2 then banks_width = 2 end
        local banks_elf_offset = (0x1000 - (1 << (4 * banks_width)))
        local banks_offset = (1 << (4 * banks_width)) - banks_count
        local banks_str = "Bank $%0" .. banks_width .. "X"
        local linear_banks_count = math.ceil(rom_size / 1048576)
        local linear_banks_width = 2
        local linear_banks_offset = (1 << (4 * linear_banks_width)) - linear_banks_count
        local linear_banks_str = "Linear $%0" .. linear_banks_width .. "X"
        local address_mask = (0x10000 << (banks_width_small * 4)) - 1

        table.insert(banks, {name="Cartridge ROM", range={(ranges[3][2] | 0xFFFF) - (banks_count * 65536) + 1, ranges[3][2] | 0xFFFF}, size=rom_size, mask=address_mask})

        local define_rom_bank = function(bank, depth)
            local range_from = ((banks_elf_offset + bank) << 16) + 0x20000000
            local range_to = range_from + 0xffff
            local size = 65536
            if (rom_size & 65535) ~= 0 and bank == banks_offset then
                size = (rom_size & 65535)
            end
            return {name=string.format(banks_str, bank), depth=depth, range={range_from, range_to}, size=size, mask=address_mask}
        end

        for i=0,linear_banks_count-1,1 do
            local linear_bank_idx = linear_banks_offset + i
            local bank_idx_offset = (linear_bank_idx & ((1 << (4 * (banks_width - 1))) - 1)) << 4
            local linear_range_from = ((banks_elf_offset + bank_idx_offset + 4) << 16) + 0x20000000
            local linear_range_to = linear_range_from + 0xbffff

            for i=0,3 do
                local idx = bank_idx_offset + i
                if idx >= banks_offset then
                    table.insert(banks, define_rom_bank(idx, 1))
                end
            end

            local linear_bank_count = 12
            if (bank_idx_offset + 4) < banks_offset then
                linear_bank_count = 16 - (banks_offset - bank_idx_offset)
            end
            local linear_size = linear_bank_count << 16

            local linear_bank = {name=string.format(linear_banks_str, linear_bank_idx), depth=1, range={linear_range_from, linear_range_to}, size=linear_size, mask=address_mask}
            table.insert(banks, linear_bank)

            for i=4,15 do
                local idx = bank_idx_offset + i
                if idx >= banks_offset then
                    table.insert(banks, define_rom_bank(idx, 2))
                end
            end
        end
    end

    return banks
end

return function(target_name)
    local target = targets[target_name]

    local function run_usage(args)
        log.verbose = log.verbose or args.verbose
    
        local elf_file <close> = io.open(args.file, "rb")
        if elf_file == nil then
            log.error("could not open '" .. args.input .. "' for reading")
            log.exit_if_fatal()
        end
        
        local elf = target.load_elf(elf_file)
        local config = {}
        local config_filename = args.config or "wfconfig.toml"
        if (args.config ~= nil) or path.exists(config_filename) then
            config = toml.decodeFromFile(config_filename)
        end
        if config.cartridge == nil then
            config.cartridge = {}
        end

        local ranges_template = tablex.deepcopy(target.group_address_ranges)
        local ranges = {}
        local usage_ranges = {}

        for i=1,#ranges_template do table.insert(ranges, nil) end
        for i=1,#elf.shdr do
            local shdr = elf.shdr[i]
            if (shdr.type == wfelf.SHT_PROGBITS or shdr.type == wfelf.SHT_NOBITS) and (shdr.flags & wfelf.SHF_ALLOC ~= 0) and shdr.size > 0 then
                local first = shdr.addr
                if target.map_address ~= nil then first = target.map_address(first) end
                if first ~= nil then
                    local last = first + shdr.size - 1
                    table.insert(usage_ranges, {first, last})
                    for i=1,#ranges_template do
                        local first_in_range = first >= ranges_template[i][1] and first <= ranges_template[i][2]
                        local last_in_range = last >= ranges_template[i][1] and last <= ranges_template[i][2]
                        if ranges[i] ~= nil then
                            local r = ranges[i]
                            if r[1] > first and first_in_range then r[1] = first end
                            if r[2] < last and last_in_range then r[2] = last end
                        elseif first_in_range and last_in_range then
                            ranges[i] = {first, last}
                        elseif first_in_range then
                            ranges[i] = {first, ranges_template[i][2]}
                        elseif last_in_range then
                            ranges[i] = {ranges_template[i][1], last}
                        end
                    end
                end
            end
        end

        if target_name == "wswan" then
            -- insert header usage range
            table.insert(usage_ranges, {0x2ffffff0, 0x2fffffff})
        end

        table.sort(usage_ranges, function(a, b)
            if a[1] < b[1] then return true end
            if a[1] > b[1] then return false end
            return a[2] < b[2]
        end)

        local banks = target.address_ranges_to_banks(ranges, config)
        local sections_section_width = 8
        local max_address_width = 4
        local max_size_width = 4

        for _,bank in pairs(banks) do
            if bank.name == nil then
                bank.name = "?"
            end

            local name_length = #bank.name
            if bank.depth ~= nil then
                name_length = name_length + 3 * bank.depth
            end
            if sections_section_width < name_length then sections_section_width = name_length end

            if bank.mask ~= nil then
                local address_width = #string.format("%X", bank.mask)
                if address_width > max_address_width then max_address_width = address_width end
            end

            if bank.size ~= nil then
                local size_width = #string.format("%d", bank.size)
                if size_width > max_size_width then max_size_width = size_width end
            end
        end

        local sections = {
            {name="Section", width=sections_section_width+1},
            {name="Range", width=max_address_width * 2 + 8 + 2, align="center"},
            {name="Size", width=max_size_width + 1, align="right"},
            {name="Used", width=max_size_width + 1, align="right"},
            {name="Used%", width=6, align="right"},
            {name="Free", width=max_size_width + 1, align="right"},
            {name="Free%", width=6, align="right"},
        }
        local print_section = function(data)
            for i,sec in ipairs(sections) do
                local s = data[i]
                if sec.align == "right" then
                    s = (" "):rep(sec.width - #wfterm.strip(s)) .. s
                elseif sec.align == "center" then
                    s = stringx.center(s, sec.width)
                else
                    s = s .. (" "):rep(sec.width - #wfterm.strip(s))
                end
                if i > 1 then io.stdout:write(" ") end
                io.stdout:write(s)
            end
            if #data > #sections then for i=#sections+1,#data do
                io.stdout:write(" ", data[i])
            end end
            print(wfterm.reset())
        end
        print_section(tablex.map(function(s) return s.name end, sections))
        print_section(tablex.map(function(s) return ("-"):rep(s.width) end, sections))

        for i,bank in ipairs(banks) do
            local output = {"","","","","","","",""}

            local s = ""
            -- add tree to name
            if bank.depth ~= nil and bank.depth > 0 then
                s = s .. wfterm.fg.bright_black()
                for d=1,bank.depth-1 do
                    local has_depth_below = false
                    for j=i+1,#banks do
                        if banks[j].depth == d then
                            has_depth_below = true
                            break
                        end
                    end
                    if has_depth_below then s = s .. "|   " else s = s .. "   " end
                end
                s = s .. "+- " .. wfterm.reset()
            end

            local address_width = #string.format("%X", bank.mask)
            local addr_f = "%0" .. address_width .. "X"
            local bank_mask = bank.mask or -1

            output[1] = s .. bank.name
            output[2] = string.format("0x" .. addr_f .. " -> 0x" .. addr_f, bank.range[1] & bank_mask, bank.range[2] & bank_mask)
            output[3] = string.format("%d", bank.size)

            local used_bytes = 0
            local mark_used = function(from, size)
                if size <= 0 then return end

                used_bytes = used_bytes + size
            end

            local range = {bank.range[1], bank.range[1] - 1}
            for _,next_range in pairs(usage_ranges) do
                if next_range[1] > range[1] then
                    local range_diff = next_range[1] - range[1]
                    local range_size = range[2] + 1 - range[1]

                    if range_size > range_diff then range_size = range_diff end
                    mark_used(range[1], range_size)
                    range[1] = next_range[1]
                    if range[1] > bank.range[2] then
                        range[2] = range[1] - 1
                        break
                    end
                end
                if next_range[2] > range[2] then
                    range[2] = next_range[2]
                    if range[2] > bank.range[2] then
                        range[2] = bank.range[2]
                    end
                end
            end
            mark_used(range[1], range[2] + 1 - range[1])

            local free_bytes = bank.size - used_bytes
            local used_percentage = math.floor(used_bytes * 100 / bank.size)
            local free_percentage = 100 - used_percentage

            output[4] = string.format("%d", used_bytes)
            output[5] = string.format("%d%%", used_percentage)
            output[6] = string.format("%d", free_bytes)
            output[7] = string.format("%d%%", free_percentage)

            print_section(output)
        end
    end

    return {
        ["arguments"] = [[
<file> ...: analyze ROM memory usage
  <file>        (string)           File to analyze.
  -c,--config   (optional string)  Optional configuration file name;
                                   wfconfig.toml is used by default.
  -v,--verbose                     Enable verbose logging.
]],
        ["description"] = "analyze ROM memory usage",
        ["run"] = run_usage
    }
end
