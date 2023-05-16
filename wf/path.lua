local compat = require("pl.compat")
local path = require("pl.path")
local M = {}

local dir_separator = compat.dir_separator
local base_dir, executable_extension
if compat.is_windows then
    executable_extension = '.exe'
    error('windows is not currently supported')
else
    executable_extension = ''
    base_dir = '/opt/wonderful'
end
M.base = base_dir

local function executable(binary_name, subpath)
    if subpath then
        subpath = subpath:gsub("/", dir_separator) .. dir_separator
    else
        subpath = ""
    end

    return path.join(base_dir, subpath .. "bin", binary_name .. executable_extension)
end
M.executable = executable

return M