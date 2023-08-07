#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023
local dir = require("pl.dir")
local lapp = require("pl.lapp")
local path = require("pl.path")
local stringx = require("pl.stringx")
local tablex = require("pl.tablex")
local wftempfile = require("wf.internal.tempfile")

local args = lapp [[
wf-process: script-driven asset generator
  -o,--output     (string)           Output filename.
                                     (the extension will be ignored)
  <script>        (string)           Script filename.
  <args...>       (optional string)  Script inputs.
  -t,--target     (optional string)  Target name.
  -f,--format     (optional string)  Output format.
  -D                                 Emit .d dependency files.
  -v,--verbose                       Enable verbose output.
]]
local format = args.format or "c"

_WFPROCESS = {}
_WFPROCESS.target = stringx.split(args.target or "", "/") or {}
_WFPROCESS.temp_dir = wftempfile.create_directory(true)
_WFPROCESS.verbose = args.verbose or false

-- TODO: Move to somewhere else.
local default_bin2c_args = {}
if (_WFPROCESS.target[1] == "wswan") and (_WFPROCESS.target[2] ~= "bootfriend") then
    default_bin2c_args.address_space = "__wf_rom"
    default_bin2c_args.align = 2
elseif (_WFPROCESS.target[1] == "psx") then
    default_bin2c_args.align = 4
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
    if scapture_enabled and not stringx.startswith(name, _WFPROCESS.temp_dir.name) then
        if mode == nil or stringx.startswith(mode, "r") then
            sinputs[name] = true
        else
            soutputs[name] = true
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
local soutput = path.splitext(args.output)

senv.args = args.args

local applicable_files = nil
senv.files = function(...)
    local exts = {...}

    if applicable_files == nil then
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
                table.insert(asset_files[filebase], {["file"]=filename})
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
path.chdir(scwd)
sinputs[args.script] = true
scapture_enabled = true
local result = loadfile(args.script, "bt", senv)()

-- Emit output files.
if format == "c" then
    local c_file <close> = io.open(soutput .. ".c", "w")
    local h_file <close> = io.open(soutput .. ".h", "w")
    local process = require("wf.api.v1.process")
    local wfbin2c = require("wf.internal.bin2c")
    local bin2c_entries = tablex.deepcopy(result)
    for entry_key, entry in pairs(bin2c_entries) do
        entry = process.to_data(entry)
        for k, v in pairs(default_bin2c_args) do
            if entry[k] == nil then
                entry[k] = v
            end
        end
        bin2c_entries[entry_key] = entry
    end
    wfbin2c.bin2c(c_file, h_file, "wf-process", bin2c_entries)
else
    error("unsupported format: " .. format)
end

-- Emit dependency file.
scapture_enabled = false
if args.D then
    local depfile <close> = io.open(soutput .. ".d", "w")
    for ok, ov in pairs(soutputs) do
        depfile:write(path.abspath(ok) .. ":")
        for ik, iv in pairs(sinputs) do
            depfile:write(" " .. path.abspath(ik))
        end
        depfile:write("\n\n")
    end
end
