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

local function mkfent_run(args)
    log.verbose = log.verbose or args.verbose

    local config = args
    if args.input_file then
        config = tablex.union(plconfig.read(args.input_file, {
            ["keysep"] = ":"
        }), config)
    end
    if not config then
        log.fatal("error reading config file")
    end
    if not config.source then
        log.fatal("missing mandatory field: source")
    end
    local source_base, source_ext = path.splitext(config.source)

    if args.input_file then
        if not config.name then
            log.fatal("missing mandatory field: name")
        end
        config.info = config.info or ""
    else
        config.name = config.name or path.basename(source_base):sub(1, 12)
        config.info = config.info or config.name
    end
    config.mode = config.mode or 7
    config.output = config.output or (source_base .. ".fx")

    if source_ext == ".elf" then
        config.source = mkfent_elf_to_binary(config.source)
    end

    local source_data = wfmath.pad_alignment_to(utils.readfile(config.source, true), 16, 0x00)
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
...: create .fx file
  -o,--output   (optional string)  The name for the output .fx file.
  -s,--source   (optional string)  The name for the file to be converted.
  --name        (optional string)  The name of the output .fx file.
  --info        (optional string)  The user-friendly name of the output file.
  --mode        (optional string)  The attribute flags of the output file.
  --resource    (optional string)  The name for the resource file to be
                                   appended.
  <input_file>  (optional string)  Input configuration file.
  -v,--verbose                     Enable verbose logging.
]],
    ["description"] = "create .fx file",
    ["run"] = mkfent_run
}
