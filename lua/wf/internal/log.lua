-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2024

--- Logging library.

local wfterm = require("wf.internal.term")

local M = {}

local function print_error(prefix, level, message)
    local info = debug.getinfo(3, "Sl")
    io.stderr:write(prefix, level, ": ", wfterm.reset(), info.short_src, ":", info.currentline, ": ", message, "\n")
    io.stderr:flush()
end

M.verbose = false
M.fatal_raised = false

M.info = function(...)
    local args = {...}
    if M.verbose then
        io.stderr:write("info: ", string.format(table.unpack(args)), "\n")
        io.stderr:flush()
    end
end

M.warn = function(...)
    local args = {...}
    print_error(wfterm.fg.bright_yellow(), "warning", string.format(table.unpack(args)))
end

M.error = function(...)
    local args = {...}
    print_error(wfterm.fg.bright_red(), "error", string.format(table.unpack(args)))
    M.fatal_raised = true
end

M.fatal = function(...)
    local args = {...}
    if M.verbose then
        error(string.format(table.unpack(args)))
    else
        print_error(wfterm.fg.bright_red(), "error", string.format(table.unpack(args)))
        os.exit(1)
    end
end

M.exit_if_fatal = function()
    if M.fatal_raised then os.exit(1) end
end

return M
