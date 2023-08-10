-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- wf-process helper functions
-- @module wf.api.v1.process
-- @alias M

if _WFPROCESS == nil then
    error("not running inside wf-process")
end

local class = require("pl.class")
local path = require("pl.path")
local wfutil = require("wf.internal.util")

local M = {}

M.Data = class()
M.File = class()

function M.Data:_init(data)
    self.data = data
end

function M.File:_init(file)
    self.file = file
end

local tmpfile_counter = 0
--- Allocate a temporary file.
-- This file will be deleted once wf-process finishes operation.
-- @tparam ?string ext File extension.
-- @treturn table Temporary file table.
function M.tmpfile(ext)
    tmpfile_counter = tmpfile_counter + 1
    return M.File(_WFPROCESS.temp_dir:path(string.format("wf%05d%s", tmpfile_counter, ext or "")))
end

--- Retrieve a filename from a string or file table.
function M.filename(obj)
    if M.File:class_of(obj) then
        return obj.file
    elseif type(obj) == "string" then
        return obj
    else
        return nil
    end
end

--- Convert a filename or data file to a file table.
function M.to_file(obj)
    if type(obj) == "table" then
        if M.File:class_of(obj) then
            return obj
        elseif M.Data:class_of(obj) then
            local result = M.tmpfile(".tmp")
            local file <close> = io.open(result.file, "wb")
            file:write(obj.data)
            return result
        end
    elseif type(obj) == "string" then
        return M.File(obj)
    else
        error("unsupported type")
    end
end

--- Convert a string or file table to a data table.
function M.to_data(obj)
    if type(obj) == "table" then
        if M.Data:class_of(obj) then
            return obj
        elseif M.File:class_of(obj) then
            local result = {}
            local file <close> = io.open(obj.file, "rb")
            result.data = file:read("*all")
            return result
        end
    elseif type(obj) == "string" then
        return M.Data(obj)
    else
        error("unsupported type")
    end
end

--- Return a list of inputs applicable to this execution of the script,
-- optionally filtered by extension.
function M.inputs(...)
    local args = {...}
    return _WFPROCESS.files(table.unpack(args))
end

--- Access a file without opening or closing it.
-- This is required to correctly emit Makefile dependency files, if a file
-- is not accessed via Lua's "io" package (for example, by an external tool).
-- @tparam string name Filename, as in Lua's "io" package.
-- @tparam string mode File access mode, as in Lua's "io" package.
function M.touch(name, mode)
    _WFPROCESS.access_file(M.filename(name), mode)
end

--- Create a symbol name from a string or file table. Error if not possible.
function M.symbol(obj)
    local filename = M.filename(obj)
    if filename == nil then
        error("could not determine filename for symbol")
    end
    local basename = path.splitext(path.basename(filename))
    return wfutil.to_c_identifier(basename)
end

--- Emit a symbol.
function M.emit_symbol(name, data)
    if M.File:class_of(name) then
        name = _WFPROCESS.bin2c_default_prefix .. M.symbol(name)
    end

    if type(data) == "table" then
        if M.Data:class_of(data) then
            data = data.data
        elseif M.File:class_of(data) then
            data = M.to_data(data).data
        else
            for k, v in pairs(data) do
                M.emit_symbol(name .. "_" .. k, v)
            end
            return
        end
    end

    if _WFPROCESS.bin2c == nil then
        error("emit_symbol not supported by current configuration")
    end
    
    local header_name = _WFPROCESS.bin2c_default_header
    if _WFPROCESS.bin2c[header_name] == nil then
        _WFPROCESS.bin2c[header_name] = {}
    end
    _WFPROCESS.bin2c[header_name][name] = data
end

return M
