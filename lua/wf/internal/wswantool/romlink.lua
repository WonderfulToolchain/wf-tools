-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local path = require('pl.path')
local tablex = require('pl.tablex')
local utils = require('pl.utils')
local toml = require('toml')
local wfmath = require('wf.math')
local wfpath = require('wf.internal.path')
local wfutil = require('wf.internal.util')
local wswan = require('wf.internal.platform.wswan')

local function romlink_call_linker(linklayout, constants, linkscript_name, output_elf, output_file, rom_start, rom_length, linker_args)
    local linkscript_filename = temp_dir:path(linkscript_name)
    local linkscript_file = io.open(linkscript_filename, 'w')
    rom_write_linkscript(linkscript_file, linklayout, constants, rom_start, rom_length)
    linkscript_file:close()

    local success, code = execute_verbose(
        wfpath.executable('ia16-elf-gcc', 'toolchain/gcc-ia16-elf'),
        table.pack("-T", linkscript_filename, "-o", output_elf, linker_args)
    )
    if not success then
        error('ld exited with error code: ' .. code)
    end

    local success, code = execute_verbose(
        wfpath.executable('ia16-elf-objcopy', 'toolchain/gcc-ia16-elf'),
        table.pack("-O", "binary", output_elf, output_file)
    )
    if not success then
        error('objcopy exited with error code: ' .. code)
    end
end

local function romlink_measure_code_size(linklayout, constants, linker_args)
    local elf_path = temp_dir:path('stage1.elf')
    local bin_path = temp_dir:path('stage1.bin')
    romlink_call_linker(linklayout, constants, 'stage1.ld', elf_path, bin_path, 0x40000, 0xC0000, linker_args)
    local attrs = lfs.attributes(bin_path)
    return wfmath.pad_alignment_to(attrs.size, 16)
end

local function rom_layout_size(layout)
    local size = 0
    for k, v in pairs(layout) do
        local v_size = k + #v
        if size < v_size then
            size = v_size
        end
    end
    return size
end

local function rom_layout_start(layout)
    local start = nil
    for k, v in pairs(layout) do
        if (start == nil) or (k < start) then
            start = k
        end
    end
    return start or 0
end

local function rom_layout_add(layout, position, data, data_name)
    if position == nil then
        position = rom_layout_size(layout)
    end
    local position_end = position + #data - 1
    for r_start, r_v in pairs(layout) do
        local r_end = r_start + #r_v - 1
        if ((position >= r_start) and (position <= r_end)) or ((position_end >= r_start) and (position_end <= r_end)) then
            error(string.format("range overlap for ROM layout entry '%s' at 0x%X, length %d", data_name or "unknown", position, #data))
        end
    end
    print_verbose(string.format("romlink: placing '%s' in ROM layout at 0x%X, length %d", data_name or "unknown", position, #data))
    layout[position] = data
end

local function rom_layout_add_file(layout, position, file_path)
    local file_path_name, file_path_ext = path.splitext(path.basename(file_path))
    return rom_layout_add(layout, position, utils.readfile(file_path, true), file_path_name)
end

local function romlink_calc_rom_size(config, rom_layout, rom_load_offset)
    local rom_size
    if config.cartridge.rom_banks then
        rom_size = config.cartridge.rom_banks * 0x10000
    else
        rom_size = rom_layout_size(rom_layout) + (0x100000 - rom_load_offset)
    end
    local rom_size_id, rom_size_value
    for k, v in pairs(wswan.ROM_BANK_COUNT_TO_HEADER_SIZE) do
        local k_size = k * 0x10000
        if (k_size >= rom_size) and ((rom_size_id == nil) or (k_size < rom_size_value)) then
            rom_size_id = v
            rom_size_value = k_size
        end
    end
    return rom_size_id, rom_size_value
end

local function romlink_run(args, linker_args)
    local config = toml.decodeFromFile(args.config or "wfconfig.toml")
    local linklayout = rom_memory_to_linklayout(config.memory)
    local rom_layout = {}
    local constants = {}

    constants["__wf_rom_bank_offset"] = 0

    local rom_load_offset
    if config.cartridge.start_segment and config.cartridge.start_offset then
        rom_load_offset = (config.cartridge.start_segment * 16) + config.cartridge.start_offset
    else
        -- WSwan cartridges tend to be allocated from the top down, which
        -- is not well-supported by traditional linkers. As such, use a hack
        -- to calculate the required code size.
        local bin_size = romlink_measure_code_size(linklayout, constants, linker_args)
        rom_load_offset = 0x100000 - wswan.ROM_HEADER_SIZE - bin_size
        config.cartridge.start_segment = rom_load_offset >> 4
        config.cartridge.start_offset = 0
    end
    if (rom_load_offset < 0x40000) or (rom_load_offset >= 0xFFFF0) then
        error(string.format("ROM load offset outside of linear bank: 0x%05X", rom_load_offset))
    end
        
    -- Calculate ROM size.
    local rom_pad_byte = 0xFF
    local rom_pad_char = string.char(rom_pad_byte)
    local rom_size, rom_size_bytes = romlink_calc_rom_size(config, rom_layout, rom_load_offset)
    config.cartridge.rom_size = rom_size
    constants["__wf_rom_bank_offset"] = 0x10000 - (rom_size_bytes >> 16)

    -- Link code at the calculated ROM location.
    local code_bin_path = temp_dir:path('stage2.bin')
    romlink_call_linker(linklayout, constants, 'stage2.ld', args.output_elf or temp_dir:path('stage2.elf'), code_bin_path, rom_load_offset, 0x100000 - wswan.ROM_HEADER_SIZE - rom_load_offset, linker_args)
    local code_bin = utils.readfile(code_bin_path, true)

    if (rom_load_offset + #code_bin) > 0xFFFF0 then
        error(string.format("program size is %d bytes, too large to load at %04X:%04X", #code_bin, config.cartridge.start_segment, config.cartridge.start_offset))
    end

    -- Prepare ROM data.
    code_bin = wfmath.pad_alignment_to(code_bin, 16)
    print_verbose(string.format("romlink: program size is %d bytes, load at %04X:%04X", #code_bin, config.cartridge.start_segment, config.cartridge.start_offset))
    
    rom_layout[rom_size_bytes - (0x100000 - rom_load_offset)] = code_bin

    local checksum, bytes_read = wswan.calculate_rom_checksum(code_bin, tablex.values(rom_layout))
    checksum = wswan.calculate_rom_checksum(checksum, wswan.calculate_rom_padding_checksum(rom_pad_byte, rom_size_bytes - 16 - bytes_read))

    local rom_header = wswan.create_rom_header(checksum, config.cartridge)

    -- Build ROM.
    local rom_file <close> = io.open(args.output, "wb")
    local min_position = 0
    if args.trim then
        min_position = rom_layout_start(rom_layout)
    end
    for i=1,(rom_size_bytes - min_position) do
        rom_file:write(rom_pad_char)
    end
    for position, data in pairs(rom_layout) do
        rom_file:seek("set", position - min_position)
        rom_file:write(data)
    end
    rom_file:seek("set", rom_size_bytes - min_position - 16)
    rom_file:write(rom_header)
end

return {
    ["arguments"] = [[
[args...] -- <linker args...>: assemble a wswan target ROM
  -c,--config   (optional string)  Configuration file name;
                                   wfconfig.toml is used by default.
  -o,--output   (string)           Output ROM file name.
  --output-elf  (optional string)  Output ELF file name;
                                   only stored on request.
  --trim                           Trim the assembled ROM by removing unused
                                   space from the beginning of the file.
  -v,--verbose                     Enable verbose logging.
]],
    ["argument_separator"] = "--",
    ["description"] = "assemble a wswan target ROM",
    ["run"] = romlink_run
}
