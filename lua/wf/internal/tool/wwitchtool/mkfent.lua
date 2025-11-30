-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local plconfig = require('pl.config')
local path = require('pl.path')
local tablex = require('pl.tablex')
local utils = require('pl.utils')
local wfmath = require('wf.internal.math')
local wfpackage = require('wf.internal.package')
local wwitch = require('wf.internal.platform.wwitch')
local log = require('wf.internal.log')

local function mkfent_elf_to_binary(in_filename)
    local tmp_filename = os.tmpname()
    local success, code = execute_verbose_or_error(
        wfpackage.executable_or_error('toolchain-gcc-ia16-elf-binutils', 'ia16-elf-objcopy', 'toolchain/gcc-ia16-elf'),
        table.pack("-O", "binary", in_filename, tmp_filename)
    )
    return tmp_filename
end

local MODE_CONFIG = 0
local MODE_FILE = 1
local MODE_REVERSE = 2
local MODE_INSPECT = 3

local function mkfent_run(args)
    log.verbose = log.verbose or args.verbose

    local config = args
    local mode = MODE_CONFIG
    local source = nil
    if args.file or args.source then mode = MODE_FILE end
    if args.reverse then mode = MODE_REVERSE end
    if args.inspect then mode = MODE_INSPECT end

    if mode == MODE_CONFIG then
        config_from_file = plconfig.read(args.input_file, {
            ["keysep"] = ":"
        })
        if not config_file then
            log.fatal("error reading config file")
        end
        config = tablex.union(config_file, config)
        source = config.source
    else
        source = args.input_file
    end

    if not source then
        log.fatal("missing mandatory field: source")
    end
    local source_base, source_ext = path.splitext(source)

    if mode == MODE_REVERSE or mode == MODE_INSPECT then
        local input_file <close> = io.open(source, "rb")
        local header = wwitch.read_fent_header(input_file)

        if mode == MODE_INSPECT then
            print("name: " .. header.name)
            print("info: " .. header.info)
            print("mode: " .. header.mode)
            -- TODO: handle mtime
            print("length: " .. header.length .. " (" .. header.xmodem_chunk_count .. " chunks)")
            if header.resource_length > 0 then
                print("resource: (" .. header.resource_length .. " bytes)")
            end
            return
        end

        if mode == MODE_REVERSE then
            local source_basename = path.basename(source_base)
            print("writing " .. source_basename .. ".bin")
            local bin_file <close> = io.open(source_basename .. ".bin", "wb")
            bin_file:write(input_file:read(header.length))
            if header.resource_length > 0 then
                print("writing " .. source_basename .. ".dat")
                local res_file <close> = io.open(source_basename .. ".dat", "wb")
                res_file:write(input_file:read(header.resource_length))
            end
        end
    end

    if mode == MODE_CONFIG then
        if not config.name then
            log.fatal("missing mandatory field: name")
        end
    else
        config.name = config.name or path.basename(source_base):sub(1, 12)
    end
    config.info = config.info or config.name
    config.mode = config.mode or 7
    config.output = config.output or (source_base .. ".fx")

    if source_ext == ".elf" then
        source = mkfent_elf_to_binary(source)
    end

    local source_data = wfmath.pad_alignment_to(utils.readfile(source, true), 16, 0x00)
    local resource_data = nil
    if config.resource then
        resource_data = wfmath.pad_alignment_to(utils.readfile(config.resource, true), 16, 0x00)
        config.resource_length = #resource_data
    end
    config.length = #source_data

    local header = wwitch.create_fent_header(config)
    local output_file <close> = io.open(config.output, "wb")
    output_file:write(header)
    output_file:write(source_data)
    if resource_data then
        output_file:write(resource_data)
    end
end

return {
    ["arguments"] = [[
...: process .fx files
  -o,--output   (optional string)  The name for the output .fx file.
  -i,--inspect                     Print information about the .fx file.
  -r,--reverse                     Treat input as a .fx file to extract.
  -f,--file                        Treat input as a binary file to convert.
  -s,--source                      Treat input as a binary file to convert.
  --name        (optional string)  The name of the output .fx file.
  --info        (optional string)  The user-friendly name of the output file.
  --mode        (optional string)  The attribute flags of the output file.
  --resource    (optional string)  The name for the resource file to be
                                   appended.
  <input_file>  (string)           Input file; configuration file by default.
  -v,--verbose                     Enable verbose logging.
]],
    ["description"] = "create .fx file",
    ["run"] = mkfent_run
}
