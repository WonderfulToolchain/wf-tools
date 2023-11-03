-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local dir = require("pl.dir")
local path = require('pl.path')
local tablex = require('pl.tablex')
local utils = require('pl.utils')
local toml = require('wf.internal.toml')
local wfpath = require('wf.internal.path')
local wfstring = require('wf.internal.string')
local wfutil = require('wf.internal.util')

local function gbafix_strfield(rom, name, loc, value, vlen, pad)
    if value ~= nil then
        local s = wfstring.pad_to_length(value:upper(), vlen, pad)
        print_verbose("adjusting " .. name .. " to: " .. s)
        rom:seek("set", loc)
        rom:write(string.pack("<c" .. tostring(vlen), s))
    end
end

local function gbafix_run(args)
    local config = args
    local config_filename = args.config or "wfconfig.toml"
    if (args.config ~= nil) or path.exists(config_filename) then
        local config_data = toml.decodeFromFile(config_filename)
        if config_data.cartridge ~= nil then
            config = tablex.union(config_data.cartridge, config)
        end
    end

    local rom_filename = args.input_file
    if args.output and path.normpath(args.output) ~= path.normpath(args.input_file) then
        if not dir.copyfile(args.input_file, args.output) then
            error("could not create file: " .. args.output)
        end
        rom_filename = args.output
    end
    local rom <close> = io.open(rom_filename, "r+b")
    if rom == nil then
        error("could not open file: " .. rom_filename)
    end

    -- adjust config-requested fields
    gbafix_strfield(rom, "game title", 0xA0, config.title, 12, string.char(0))
    gbafix_strfield(rom, "game code", 0xAC, config.code, 4, "X")
    gbafix_strfield(rom, "maker code", 0xB0, config.maker, 2, "0")
    if config.revision ~= nil then
        local v = tonumber(config.revision) & 0xFF
        print_verbose("adjusting game version to " .. v)
        rom:seek("set", 0xBC)
        rom:write(string.pack("<B", v))
    end
    if config.logo ~= nil then
        local logo_data = nil
        local logo_path = config.logo
        local logo_path_builtin = path.join(wfpath.base, "target", "gba", "header", logo_path .. ".bin")
        if path.exists(logo_path_builtin) then
            logo_path = logo_path_builtin
        end
        logo_data = utils.readfile(logo_path, true)
        if logo_data == nil then
            error("could not load logo data: " .. config.logo)
        elseif #logo_data ~= 156 then
            error("could not load logo data: " .. config.logo .. " (invalid size " .. #logo_data .. ")")
        end
        print_verbose("adjusting logo to " .. config.logo)
        rom:seek("set", 0x04)
        rom:write(logo_data)
    end

    -- adjust debug
    if config.debug ~= nil then
        rom:seek("set", 0x9C)
        local x9c_value = string.byte(rom:read(1))
        rom:seek("set", 0x9C)
        rom:write(string.char(x9c_value | 0x84))
        rom:seek("set", 0xB4)
        if config.debug > 0 then
            rom:write("\x80")
        else
            rom:write("\x00")
        end
    end

    -- adjust fixed value
    rom:seek("set", 0xB2)
    local b2_value = string.byte(rom:read(1))
    if b2_value ~= 0x96 then
        print_verbose("adjusting 0xB2 fixed value to: 0x96")
        rom:seek("set", 0xB2)
        rom:write("\x96")
    end

    -- adjust checksum (must be last)
    rom:seek("set", 0xA0)
    local checksum_data = rom:read(0xBD - 0xA0)
    local checksum = -0x19
    for i = 1, #checksum_data do
        checksum = checksum - string.byte(checksum_data, i)
    end
    print_verbose("adjusting checksum")
    rom:seek("set", 0xBD)
    rom:write(string.char(checksum & 0xFF))
end

return {
    ["arguments"] = [[
...: adjust .gba file header
  
  -o,--output   (optional string)  The name for the output .gba file.
                                   By default, the input will be overwritten.
  -c,--config   (optional string)  Configuration file name;
                                   wfconfig.toml is used by default.
  -t,--title    (optional string)  The game title to use.
  --code        (optional string)  The game code to use.
  -m,--maker    (optional string)  The maker code to use.
  -d,--debug    (optional number)  Enable GBA BIOS debug handler.
                                     - 0 = 0x09FFC000
                                     - 1 = 0x09FE2000
  -r,--revision (optional number)  The game version to use.
  -l,--logo     (optional string)  The logo value to use.
                                   Special values:
                                     - official
  <input_file>  (string)           Input binary file.
  -v,--verbose                     Enable verbose logging.
]],
    ["description"] = "adjust .gba file header",
    ["run"] = gbafix_run
}
