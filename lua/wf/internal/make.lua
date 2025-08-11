-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

--- GNU Make-related utilities.
-- @module wf.internal.make
-- @alias M

local M = {}

--- Escape a string for use in a Makefile.
-- @tparam string value The string to escape.
-- @return string The escaped string.
function M.escape(value)
    return value:gsub(" ", "\\ "):gsub("%$", "$$"):gsub("#", "\\#")
end

return M
