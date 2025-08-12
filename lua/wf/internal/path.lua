-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Path querying.

local compat = require("pl.compat")
local dir = require("pl.dir")
local path = require("pl.path")
local stringx = require("pl.stringx")
local wfutil = require("wf.internal.util")
local M = {}

local dir_separator = compat.dir_separator
local base_path, executable_extension
local base_dir = os.getenv("WONDERFUL_TOOLCHAIN")
if base_dir == nil or #base_dir <= 0 then
    base_dir = "/opt/wonderful"
end

if compat.is_windows then
    executable_extension = '.exe'
    local bd_success, bd_error_code
    bd_success, bd_error_code, base_path = wfutil.execute(
        "cygpath", {"-w", base_dir},
        wfutil.OUTPUT_CAPTURE
    )
    if not bd_success then
        error("could not retrieve toolchain directory")
    end
    base_path = stringx.strip(base_path)
else
    executable_extension = ''
    base_path = base_dir
end

--- Base (WONDERFUL_TOOLCHAIN) directory path.
M.base = base_path

--- Base (WONDERFUL_TOOLCHAIN) directory user-friendly name.
M.base_name = base_dir

--- Generate an absolute path to the given executable.
--- @param binary_name string The executable name.
--- @param subpath? string The subpath, if any; for example, a subpath of "others" resolves to "/opt/wonderful/others/bin".
--- @return string path The absolute path to the given executable.
function M.executable(binary_name, subpath)
    if subpath then
        subpath = subpath:gsub("/", dir_separator) .. dir_separator
    else
        subpath = ""
    end

    return path.join(base_path, subpath .. "bin", binary_name .. executable_extension)
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
