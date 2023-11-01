#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023
local dir = require("pl.dir")
local lapp = require("pl.lapp")
local lfs = require("lfs")
local path = require("pl.path")
local stringx = require("pl.stringx")
local tablex = require("pl.tablex")
local wftempfile = require("wf.internal.tempfile")

local args = lapp [[
wf-process: script-driven asset pipeline tool

This asset pipeline tool is meant to be used as part of a larger build script.
For example, consider the following command line:

wf-process -o build/assets/graphics/script.c
           -f build/iso
           -D
           assets/graphics/script.lua

This will create the following files:
- build/assets/graphics/script.c (from -o)
- build/assets/graphics/script.d (from -D)
- build/.../*.h (from header filenames matching the provided files)
- build/iso/graphics.dat (if such a file is requested)

The build system is expected to process the .d file (if requested)
and compile the .c file (likewise if requested).

Tool arguments:
  <script>         (string)           Script filename.
  <args...>        (optional string)  Script inputs.
  -f,--filesystem  (optional string)  Filesystem directory.
  -o,--output      (optional string)  Output file (.c).
  -t,--target      (optional string)  Target name, in Wonderful convention.
  --symbol-prefix  (optional string)  Default symbol prefix.
  -D,--depfile     (optional string)  Emit .d dependency file.
  --depfile-target (optional string)  .d dependency file target.
  -v,--verbose                        Enable verbose output.
]]

_WFPROCESS = {}
_WFPROCESS.target = stringx.split(args.target or "", "/") or {}
_WFPROCESS.temp_dir = wftempfile.create_directory(true)
_WFPROCESS.verbose = args.verbose or false

-- TODO: Move to somewhere else.
local bin2c_processor = function(obj) end

if _WFPROCESS.target[1] == "wswan" then
    bin2c_processor = function(obj, key)
        if _WFPROCESS.target[2] ~= "bootfriend" then
            obj.align = obj.options.align or 2
            obj.address_space = "__wf_rom"
            if obj.options.section == nil
            and (obj.options.bank == 0 or obj.options.bank == 1 or obj.options.bank == "0" or obj.options.bank == "1" or obj.options.bank == "L") then
                local section = ".rom" .. obj.options.bank
                if obj.options.bank_index ~= nil then
                    local index = obj.options.bank_index
                    if type(index) == "number" then index = string.format("%X", index) end
                    section = section .. "_" .. index
                    if obj.options.bank_offset ~= nil then
                        index = obj.options.bank_offset
                        if type(index) == "number" then index = string.format("%X", index) end
                        section = section .. "_" .. index
                    end
                end
                obj.bank = true
                obj.section = section .. ".a." .. key
            end
        end
    end
elseif _WFPROCESS.target[1] == "psx" then
    bin2c_processor = function(obj)
        obj.align = obj.options.align or 4
    end
elseif _WFPROCESS.target[1] == "gba" then
    bin2c_processor = function(obj)
        obj.align = obj.options.align or 2
    end
end

-- Build script environment.
local senv = {
    ["assert"] = assert,
    ["collectgarbage"] = collectgarbage,
    ["coroutine"] = coroutine,
    ["dofile"] = dofile,
    ["error"] = error,
    ["getmetatable"] = getmetatable,
    ["io"] = io,
    ["ipairs"] = ipairs,
    ["load"] = load,
    ["loadfile"] = loadfile,
    ["math"] = math,
    ["next"] = next,
    ["os"] = {},
    ["pairs"] = pairs,
    ["pcall"] = pcall,
    ["print"] = print,
    ["rawequal"] = rawequal,
    ["rawget"] = rawget,
    ["rawlen"] = rawlen,
    ["rawset"] = rawset,
    ["select"] = select,
    ["setmetatable"] = setmetatable,
    ["string"] = string,
    ["table"] = table,
    ["tonumber"] = tonumber,
    ["tostring"] = tostring,
    ["type"] = type,
    ["utf8"] = utf8,
    ["warn"] = warn,
    ["xpcall"] = xpcall,
    ["_VERSION"] = _VERSION
}
senv.os.clock = os.clock
senv.os.date = os.date
senv.os.difftime = os.difftime
senv.os.time = os.time
senv["_G"] = senv

local blocked_packages = {}
blocked_packages["pl.app"] = true
blocked_packages["pl.compat"] = true
blocked_packages["pl.dir"] = true
blocked_packages["pl.file"] = true
blocked_packages["pl.lapp"] = true

-- Package loading hooks.
senv.require = function(name)
    if blocked_packages[name] == nil then
        if stringx.startswith(name, "pl.") or stringx.startswith(name, "wf.api.v") then
            return require(name)
        end
    end

    error("forbidden require caught: " .. name)
end
tablex.clear(package.loaded)

-- File access hooks.
local sinputs = {}
local soutputs = {}
local scapture_enabled = false
_WFPROCESS.access_file = function(name, mode)
    if scapture_enabled then
        name = path.abspath(name)
        if not stringx.startswith(name, _WFPROCESS.temp_dir.name) then
            if mode == nil or stringx.startswith(mode, "r") then
                sinputs[name] = true
            else
                soutputs[name] = true
            end
        end
    end
end
local rio = io
io = tablex.deepcopy(io)

io.lines = nil
io.open = function(name, mode)
    local file = rio.open(name, mode)
    _WFPROCESS.access_file(path.abspath(name), mode)
    return file
end

-- args/files
local spath = path.abspath(args.script)
local sname = path.splitext(path.basename(spath))
local scwd = path.normpath(path.join(spath, ".."))
local ocwd = path.normpath(path.join(args.output, ".."))
local soutput, format = path.splitext(args.output)

senv.args = args.args

if args.filesystem then
    _WFPROCESS.filesystem = {}
end
if format == ".c" then
    local soutbase = path.splitext(path.basename(soutput))
    _WFPROCESS.bin2c_default_header = soutbase .. ".h"
    _WFPROCESS.bin2c_default_prefix = args.symbol_prefix or ""
    _WFPROCESS.bin2c = {}
end

local applicable_files = nil
_WFPROCESS.files = function(...)
    local exts = {...}

    if applicable_files == nil then
        local process = require("wf.api.v1.process")

        -- List all files, split into Lua (dictionary) and non-Lua (array) files
        local lua_files = {}
        local asset_files = {}
        for k, v in pairs(dir.getfiles(scwd)) do
            local filename = path.basename(v)
            local filebase, fileext = path.splitext(filename)
            if fileext == ".lua" then
                lua_files[filebase] = true
            else
                if asset_files[filebase] == nil then
                    asset_files[filebase] = {}
                end
                table.insert(asset_files[filebase], process.File(filename))
            end
        end

        -- If x.[non-lua] exists, only process x.* files.
        -- Otherwise, only process files.* which don't have a files.lua.
        if asset_files[sname] ~= nil then
            applicable_files = asset_files[sname]
        else
            applicable_files = {}
            for k, v in pairs(asset_files) do
                if lua_files[k] == nil then
                    tablex.insertvalues(applicable_files, v)
                end
            end
        end
        
        table.sort(applicable_files, function(a, b) return a.file < b.file end)
    end

    if #exts == 0 then
        return applicable_files
    else
        return tablex.filter(applicable_files, function(fn)
            for i = 1, #exts do
                if stringx.endswith(fn.file, exts[i]) then
                    return true
                end
            end
            return false
        end)
    end
end

-- Run the script.
local old_cwd = lfs.currentdir()
local script_func = assert(loadfile(args.script, "bt", senv))
sinputs[path.abspath(args.script)] = true
path.chdir(scwd)
scapture_enabled = true
script_func()
path.chdir(old_cwd)

-- Emit output files.
if format == ".c" then
    local process = require("wf.api.v1.process")
    local wfbin2c = require("wf.internal.bin2c")
    local all_bin2c_entries = {}

    -- Emit header files.
    for k, v in pairs(_WFPROCESS.bin2c) do
        local h_file <close> = io.open(path.join(ocwd, k), "w")

        local bin2c_entries = tablex.deepcopy(v)
        for entry_key, entry in pairs(bin2c_entries) do
            bin2c_processor(entry, entry_key)
            bin2c_entries[entry_key] = entry
            all_bin2c_entries[entry_key] = entry
        end

        wfbin2c.bin2c(nil, h_file, "wf-process", bin2c_entries)
    end

    local c_file <close> = io.open(soutput .. ".c", "w")
    wfbin2c.bin2c(c_file, nil, "wf-process", all_bin2c_entries)
end

-- Emit dependency file.
scapture_enabled = false
if args.depfile ~= nil then
    local depfilename = args.depfile
    if args.depfile == "" then
        depfilename = soutput .. ".d"
    end
    local depfile <close> = io.open(depfilename, "w")
    if args.depfile_target ~= nil then
        soutputs = {}
        soutputs[args.depfile_target] = true
    end
    for ok, ov in pairs(soutputs) do
        depfile:write(ok .. ":")
        for ik, iv in pairs(sinputs) do
            depfile:write(" " .. ik)
        end
        depfile:write("\n\n")
    end
end
