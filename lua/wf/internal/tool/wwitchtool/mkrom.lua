-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local path = require('pl.path')
local utils = require('pl.utils')
local wfpath = require("wf.internal.path")
local wwitch = require('wf.internal.platform.wwitch')
local log = require('wf.internal.log')

local ATHENAOS_DIR = path.join(wfpath.base, "target/wwitch/fbin/")

local function mkrom_run(args)
    log.verbose = log.verbose or args.verbose

    local executable_file_id = nil
    local executable_file_name = nil
    local file_id = 0
    local file_count = #args.input
    local file_headers = {}
    local file_names = {}
    local file_offsets = {}
    local file_datas = {}
    local file_length = 0

    log.info("/rom0 file count is " .. file_count)

    for _,file in pairs(args.input) do
        log.info("adding " .. file)

        local data = utils.readfile(file, true)

        local header = nil
        local length = #data
        local is_executable = false
        if (#data >= 128) and (data:sub(1,4) == "#!ws") then
            header = data:sub(65, 128)
            local parsed_header = wwitch.parse_fent_header(data:sub(1, 128))

            data = data:sub(129)
            length = #data

            is_executable = is_executable or (parsed_header.mode:find("x") ~= nil and parsed_header.mode:find("i") == nil)
            local xmodem_length = parsed_header.xmodem_chunk_count * 128
            if xmodem_length > length then length = xmodem_length end
        else
            header = wwitch.create_fent_header({
                ["name"]=path.basename(file),
                ["length"]=length,
                ["mode"]=4
            })
        end

        length = (length + 127) & ~127
        if is_executable then
            if executable_file_id == nil then
                executable_file_id = file_id
                executable_file_name = file
            else
                log.warn(executable_file_name .. " already marked as bootable, " .. file .. " will not be launched")
            end
        end

        table.insert(file_headers, header)
        table.insert(file_names, file)
        table.insert(file_offsets, file_length)
        table.insert(file_datas, data)

        file_id = file_id + 1
        file_length = file_length + length
    end

    local seg_file_end = 0xE000
    local seg_file_start = seg_file_end - (file_length >> 4)
    local seg_file_header_start = seg_file_start - (file_count << 2)

    local rom_offset = seg_file_header_start
    local rom_size = (0x10000 - rom_offset) << 4
    if rom_offset < 0x4000 then
        log.fatal("ROM contents too large: " .. rom_size .. " bytes > " .. (768*1024) .. " bytes")
    end
    if not args.trim then
        if rom_offset < 0x8000 then rom_offset = 0x0000 end
        if rom_offset < 0xC000 then rom_offset = 0x8000 end
        if rom_offset > 0xC000 then rom_offset = 0xC000 end
    end
    rom_size = (0x10000 - rom_offset) << 4
    log.info(string.format("executable #%d, headers at %04X:0000, files at %04X:0000", executable_file_id, seg_file_header_start, seg_file_start))

    local path_bios = ATHENAOS_DIR .. "athenabios.rom.raw"
    local path_os = ATHENAOS_DIR .. "athenaos.rom.raw"
    if args.small then
        path_bios = ATHENAOS_DIR .. "athenabios.smallrom.raw"
        path_os = ATHENAOS_DIR .. "athenaos.smallrom.raw"
    end
    if not path.exists(path_bios) or not path.exists(path_os) then
        log.fatal("please install target-wswan-athenaos")
    end

    local output_file <close> = io.open(args.output, "wb")
    if output_file == nil then
        log.fatal("failed to open file '" .. args.output .. "' for writing")
    end
    print("writing " .. args.output)
    output_file:write(string.char(0xFF):rep(rom_size - ((0x10000 - seg_file_header_start) << 4)))

    for i,v in pairs(file_headers) do
        local segment = ((file_offsets[i] >> 4) + seg_file_start)
        log.info(string.format("placing %s at %04X:0000", file_names[i], segment))

        -- relocate segment in header
        v = v:sub(1,40) .. string.pack("< I4", segment << 16) .. v:sub(45,64)

        output_file:write(v)
    end

    for _,v in pairs(file_datas) do
        output_file:write(v)

        local length = #v
        local pad_length = (length + 127) & ~127
        if pad_length > length then
            output_file:write(string.char(0xFF):rep(pad_length - length))
        end
    end

    local data_bios = utils.readfile(path_bios, true)
    local data_os = utils.readfile(path_os, true)
    if #data_bios > 65536 or #data_os > 65504 then
        log.fatal("bios/os too large - files corrupt?")
    end

    output_file:write(data_os)
    if #data_os < 65504 then
        output_file:write(string.char(0xFF):rep(65504 - #data_os))
    end
    -- AthenaOS header
    output_file:write(string.pack("< I2 I2 I2 I2 I2 I2 I2 I2",
        0x5AA5, -- magic
        1, -- version
        seg_file_header_start,
        file_count, -- rom0 count
        executable_file_id,
        0, -- ram0 count
        0, 0
    ))
    -- generic OS header
    output_file:write(string.pack("< I1 I2 I2 I1 I2 I4 I4",
        0xEA, 0x0000, 0xE000,
        0x00, (#data_os + 127) >> 7,
        0xFFFFFFFF, 0xFFFFFFFF
    ))

    if #data_bios < 65536 then
        output_file:write(string.char(0xFF):rep(65536 - #data_bios))
    end
    output_file:write(data_bios)
end

return {
    ["arguments"] = [[
...: combine .fx files into AthenaOS ROM
  -o,--output   (string)           The name for the output .ws file.
  <input...>    (string)           Input files to add.
  --small                          Use 128K SRAM-compatible AthenaOS variant.
  --trim                           Trim the assembled ROM by removing unused
                                   space from the beginning of the file.
  -v,--verbose                     Enable verbose logging.
]],
    ["description"] = "combine .fx files into AthenaOS ROM",
    ["run"] = mkrom_run
}
