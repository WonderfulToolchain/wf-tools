-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2024

--- Logging library.
-- @module wf.internal.log
-- @alias M

local M = {}

local function print_error(level, message)
    local info = debug.getinfo(3, "Sl")
    print(level .. ": " .. info.short_src .. ":" .. info.currentline .. ": " .. message)
end

M.verbose = false
M.fatal_raised = false

M.info = function(...)
    local args = {...}
    if M.verbose then
        print_error("info", string.format(table.unpack(args)))
    end
end

M.warn = function(...)
    local args = {...}
    print_error("warning", string.format(table.unpack(args)))
end

M.error = function(...)
    local args = {...}
    print_error("error", string.format(table.unpack(args)))
    M.fatal_raised = true
end

M.exit_if_fatal = function()
    if M.fatal_raised then os.exit(1) end
end

return M
