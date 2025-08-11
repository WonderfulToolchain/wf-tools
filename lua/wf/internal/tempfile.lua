-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Lua 5.4+ temporary file library.
-- @module wf.internal.tempfile
-- @alias M

local compat = require("pl.compat")
local dir = require('pl.dir')
local path = require('pl.path')
local posix_stdlib
if not compat.is_windows then
    posix_stdlib = require('posix.stdlib')
end
local stringx = require('pl.stringx')

local M = {}

local tmp_directory_mt = {
    ["__close"] = function(obj)
        if obj.auto_remove and obj.name then
            dir.rmtree(obj.name)
        end
    end
}
tmp_directory_mt["__gc"] = tmp_directory_mt["__close"]
local function tmp_directory_path(obj, ...)
    return path.join(obj.name, table.unpack({...}))
end

local tmp_directory_parent = path.abspath(path.join(os.tmpname(), ".."))
--- Returns true if the provided path is in a temporary directory.
--- @param dir string Directory/file path to check.
M.is_in_temp_path = function(dir)
    return stringx.startswith(path.abspath(dir), tmp_directory_parent .. path.sep)
end

--- Create a temporary directory, which supports automatic tree removal using a to-be-closed variable.
--- @param auto_remove? boolean If explicitly set to false, the directory will not be automatically deleted.
M.create_directory = function(auto_remove)
    auto_remove = auto_remove ~= false and true or false

    local dirname
    if compat.is_windows then
        dirname = os.tmpname()
        local mkdir_success, mkdir_error = path.mkdir(dirname)
        if not mkdir_success then
            error("could not create temporary directory: " .. mkdir_error)
        end
    else
        dirname, dirname_error = posix_stdlib.mkdtemp("/tmp/wf-XXXXXXXX")
        if not dirname then
            error("could not create temporary directory: " .. dirname_error)
        end
    end

    local result = {["auto_remove"] = auto_remove, ["name"] = dirname, ["path"] = tmp_directory_path}
    setmetatable(result, tmp_directory_mt)
    
    return result
end

return M
