--- Path querying.
-- @module wf.internal.path
-- @alias M

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

return M