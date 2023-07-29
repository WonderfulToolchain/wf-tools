-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Path querying.
-- @module wf.internal.path
-- @alias M

local compat = require("pl.compat")
local dir = require("pl.dir")
local path = require("pl.path")
local M = {}

local dir_separator = compat.dir_separator
local base_dir, executable_extension
if compat.is_windows then
    executable_extension = '.exe'
    base_dir = '/opt/wonderful'
else
    executable_extension = ''
    base_dir = '/opt/wonderful'
end
M.base = base_dir

--- Generate an absolute path to the given executable.
-- @tparam string binary_name The executable name.
-- @tparam ?string subpath The subpath, if any; for example, a subpath of "others" resolves to "/opt/wonderful/others/bin".
-- @treturn string The absolute path to the given executable.
function M.executable(binary_name, subpath)
    if subpath then
        subpath = subpath:gsub("/", dir_separator) .. dir_separator
    else
        subpath = ""
    end

    return path.join(base_dir, subpath .. "bin", binary_name .. executable_extension)
end

function M.copypath(src, dest, filter)
    src = path.abspath(src)
    dest = path.abspath(dest)
    for root, dirs, files in dir.walk(src) do
        local source_dir = path.relpath(root, src)
        local destination_dir = path.join(dest, source_dir)
        if #source_dir <= 0 or filter == nil or filter(source_dir) then
            if not path.isdir(destination_dir) then
                if not dir.makepath(destination_dir) then
                    error("could not create directory: " .. source_dir)
                end
            end
            for i, file in ipairs(files) do
                local source_file_path = path.join(root, file)
                local source_file = path.relpath(source_file_path, src)
                if filter == nil or filter(source_file) then
                    local destination_file_path = path.join(dest, source_file)
                    if not dir.copyfile(source_file_path, destination_file_path) then
                        error("could not create file: " .. source_file)
                    end
                end
            end
        end
    end
end

return M
