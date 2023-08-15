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

--- Binary data class; contains a "data" key with a binary data string.
-- @type process.Data
M.Data = class()

function M.Data:_init(data)
    self.data = data
end
---
-- @section end

--- File reference class; contains a "file" key with a filename string.
-- @type process.File
M.File = class()

function M.File:_init(file)
    self.file = file
end
---
-- @section end

local tmpfile_counter = 0
--- Allocate a temporary file.
-- This file will be deleted once wf-process finishes operation.
-- @tparam ?string ext File extension.
-- @treturn process.File Temporary file reference.
function M.tmpfile(ext)
    tmpfile_counter = tmpfile_counter + 1
    return M.File(_WFPROCESS.temp_dir:path(string.format("wf%05d%s", tmpfile_counter, ext or "")))
end

--- Retrieve a filename from a string or file reference.
-- @tparam ?|string|process.File obj
-- @treturn ?string Filename.
function M.filename(obj)
    if M.File:class_of(obj) then
        return obj.file
    elseif type(obj) == "string" then
        return obj
    else
        return nil
    end
end

--- Convert a filename or reference to a file reference.
-- @tparam ?|string|process.Data|process.File obj Reference or filename. 
-- @treturn process.File File reference.
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

--- Convert a binary data string or reference to a binary data reference.
-- @tparam ?|string|process.Data|process.File obj Reference or filename. 
-- @treturn process.Data Binary data reference.
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
-- @tparam ?string ... Optional extensions to filter by.
-- @treturn {process.File,...} Table of process files.
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

--- Create a symbol name from a string or file reference. Error if not possible.
-- @tparam string|process.File file File reference or filename.
-- @treturn string Symbol name.
function M.symbol(file)
    local filename = M.filename(file)
    if filename == nil then
        error("could not determine filename for symbol")
    end
    local basename = path.splitext(path.basename(filename))
    return wfutil.to_c_identifier(basename)
end

--- Emit a symbol accessible to C code.
-- @tparam string|process.File name Symbol name; can be generated automaticaly from an input file.
-- @tparam string|table|process.Data|process.File data Data to emit.
function M.emit_symbol(name, data, options)
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
    _WFPROCESS.bin2c[header_name][name] = {
        ["data"] = data,
        ["options"] = options
    }
end

return M
