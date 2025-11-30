-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local log = require('wf.internal.log')
local path = require('pl.path')
local stringx = require('pl.stringx')
local tablex = require('pl.tablex')
local toml = require('wf.internal.toml')
local wfelf = require('wf.internal.elf')
local wfnative = require('wf.internal.native')
local wfterm = require('wf.internal.term')
local Graph = require('wf.internal.tool.usage.graph')

local function sort_usage_ranges_for_deduplication(usage_ranges)
    table.sort(usage_ranges, function(a, b)
        if a[1] < b[1] then return true end
        if a[1] > b[1] then return false end
        return a[2] < b[2]
    end)
end

local function is_section_eligible(shdr)
    return (shdr.type == wfelf.SHT_PROGBITS or shdr.type == wfelf.SHT_NOBITS) and (shdr.flags & wfelf.SHF_ALLOC ~= 0) and shdr.size > 0
end

--- @param mark_area_used function (first_address, size).
local function iterate_used_areas_without_duplicates(bank, usage_ranges, mark_area_used)
    local range = {bank.range[1], bank.range[1] - 1}
    for _,next_range in pairs(usage_ranges) do
        if next_range[1] > range[1] then
            local range_diff = next_range[1] - range[1]
            local range_size = range[2] + 1 - range[1]

            if range_size > range_diff then range_size = range_diff end
            mark_area_used(range[1], range_size)
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
    mark_area_used(range[1], range[2] + 1 - range[1])
end

local function print_text_output(elf, target, banks, usage_ranges, args)
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

    local sections = {}
    table.insert(sections, {name="Section", width=sections_section_width+1})
    if not args.compact then table.insert(sections, {name="Range", width=max_address_width * 2 + 8 + 2, align="center"}) end
    if not args.compact then table.insert(sections, {name="Size", width=max_size_width + 1, align="right"}) end
    table.insert(sections, {name="Used", width=max_size_width + 1, align="right"})
    if not args.compact then table.insert(sections, {name="Used%", width=6, align="right"}) end
    table.insert(sections, {name="Free", width=max_size_width + 1, align="right"})
    table.insert(sections, {name="Free%", width=6, align="right"})

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
        local output = {}

        local s = ""
        -- add tree to name
        if bank.depth ~= nil and bank.depth > 0 then
            if args.depth ~= nil and bank.depth > args.depth then goto continue end

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

        local has_higher_depth_below = i < #banks and (banks[i+1].depth or 0) > (bank.depth or 0)

        local address_width = #string.format("%X", bank.mask)
        local addr_f = "%0" .. address_width .. "X"
        local bank_mask = bank.mask or -1

        local minigraph = Graph(32, 1, bank.size)
        local used_bytes = 0
        local mark_used = function(from, size)
            if size <= 0 then return end

            used_bytes = used_bytes + size
            if args.graph then minigraph:mark_area_used(from - bank.range[1], size) end
        end
        iterate_used_areas_without_duplicates(bank, usage_ranges, mark_used)

        if args.compact and used_bytes == 0 then goto continue end

        local free_bytes = bank.size - used_bytes
        local used_percentage = math.floor(used_bytes * 100 / bank.size)
        local free_percentage = 100 - used_percentage

        local color = nil
        local graph_colored_separately = false
        if args.color == "free" then
            if free_percentage == 0 then color = wfterm.fg.red()
            elseif free_percentage <= 1 then color = wfterm.fg.bright_red()
            elseif free_percentage <= 10 then color = wfterm.fg.bright_yellow()
            elseif free_percentage <= 25 then color = wfterm.fg.bright_green()
            end
        elseif args.color == "area" then
            color = bank.color
        end
        if color ~= nil then s = s .. color end

        table.insert(output, s .. bank.name)
        if not args.compact then
            table.insert(output, string.format("0x" .. addr_f .. " -> 0x" .. addr_f, bank.range[1] & bank_mask, bank.range[2] & bank_mask))
            table.insert(output, string.format("%d", bank.size))
        end

        table.insert(output, string.format("%d", used_bytes))
        if not args.compact then table.insert(output, string.format("%d%%", used_percentage)) end
        table.insert(output, string.format("%d", free_bytes))
        table.insert(output, string.format("%d%%", free_percentage))

        if args.graph then
            if graph_colored_separately then
                table.insert(output, wfterm.reset() .. "|" .. minigraph:generate_ascii_text() .. wfterm.reset() .. "|")
            else
                table.insert(output, "|" .. minigraph:generate_ascii_text() .. "|")
            end
        end

        print_section(output)

        if args.symbol_top ~= nil and args.symbol_top > 0 and not bank.duplicate then
            local symbols_by_size = {}
            for k=1,#elf.symbols do
                local sym = elf.symbols[k]
                local shdr = elf.shdr[sym.shndx + 1]
                if sym.size > 0 and is_section_eligible(shdr) then
                    local first = shdr.addr
                    if target.map_address ~= nil then first = target.map_address(first) end
                    if first ~= nil and first >= bank.range[1] and first <= bank.range[2] then
                        table.insert(symbols_by_size, {sym.name, sym.size})
                    end
                end
            end

            table.sort(symbols_by_size, function(a, b)
                if a[2] > b[2] then return true end
                if a[2] < b[2] then return false end
                return a[1] < b[1]
            end)

            local to_print = #symbols_by_size
            if to_print > args.symbol_top then to_print = args.symbol_top end
            if to_print > 0 then
                local max_symbol_width = 0
                for i=1,to_print do
                    symbols_by_size[i][1] = wfnative.cxa_demangle(symbols_by_size[i][1])
                    if #symbols_by_size[i][1] > max_symbol_width then max_symbol_width = #symbols_by_size[i][1] end
                end

                local empty_prefix = (" "):rep((bank.depth or 0) * 3) .. wfterm.fg.bright_black() ..  "|" .. wfterm.reset()
                local prefix = (" "):rep((bank.depth or 0) * 3) .. wfterm.fg.bright_black() ..  "+- " .. wfterm.reset()

                print(empty_prefix)
                for i=1,to_print do
                    local sym = symbols_by_size[i]
                    print(prefix .. stringx.ljust(sym[1], max_symbol_width) .. stringx.rjust(string.format("%d", sym[2]), 11))
                end
                if has_higher_depth_below then print(empty_prefix) end
            end
        end

        ::continue::
    end
end

local function print_text_graph_detailed(banks, usage_ranges, args)
    for i,bank in ipairs(banks) do
        if not bank.duplicate then
            local address_width = #string.format("%X", bank.mask)
            local addr_f = "%0" .. address_width .. "X"
            local bank_mask = bank.mask or -1

            local graph = Graph(64, 16, bank.size)
            local mark_used = function(from, size)
                graph:mark_area_used(from - bank.range[1], size)
            end
            iterate_used_areas_without_duplicates(bank, usage_ranges, mark_used)

            print(string.format("\n\nStart: %s  0x" .. addr_f .. " -> 0x" .. addr_f, bank.name, bank.range[1] & bank_mask, bank.range[2] & bank_mask))
            print(graph:generate_ascii_text())
            print(string.format("End: %s", bank.name))
        end
    end
end

return function(target_name)
    local target = require("wf.internal.tool.usage.target." .. target_name)

    local function run_usage(args)
        log.verbose = log.verbose or args.verbose

        local elf_file <close> = io.open(args.file, "rb")
        if elf_file == nil then
            log.fatal("could not open '" .. args.input .. "' for reading")
        end

        local load_elf_flags = wfelf.PARSE_SECTIONS
        if args.symbol_top ~= nil then
            load_elf_flags = load_elf_flags | wfelf.PARSE_SYMBOLS | wfelf.PARSE_STRTABS
        end
        local elf = target.load_elf(elf_file, load_elf_flags)
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
            if is_section_eligible(shdr) then
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

        sort_usage_ranges_for_deduplication(usage_ranges)

        local banks = target.address_ranges_to_banks(ranges, args, config)
        print_text_output(elf, target, banks, usage_ranges, args)

        if args.graph_detailed then
            print_text_graph_detailed(banks, usage_ranges, args)
        end
    end

    local function get_argument_string()
        local s = [[
<file> ...: analyze program memory usage
  <file>        (string)           File to analyze.
  --color       (optional string)  Use color to augment output:
                                   - area: Distinguish area types
                                   - free: Distinguish usage percent
  -C,--compact                     Compact display mode.
  -c,--config   (optional string)  Optional configuration file name;
                                   wfconfig.toml is used by default.
  -d,--depth    (optional number)  Maximum depth to display.
  -g,--graph                       Show text graph for each section.
  --graph-detailed                 Show detailed text graph for each
                                   section.
]]
        if target_name == "wswan" then
            s = s .. [[
  --hide-linear-banks              Hide the linear ROM bank grouping.
  --hide-separate-iram             Hide separate mono/color IRAM
                                   areas.
]]
        end
        s = s .. [[
  --symbol-top  (optional number)  Show the top N symbols for each
                                   bank.
  -v,--verbose                     Enable verbose logging.
]]
        return s
    end

    return {
        ["arguments"] = get_argument_string(),
        ["description"] = "analyze program memory usage",
        ["run"] = run_usage
    }
end
