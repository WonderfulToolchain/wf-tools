-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

--- GNU Make-related utilities.

local M = {}

--- Escape a string for use in a Makefile.
--- @param value string The string to escape.
--- @return string result The escaped string.
function M.escape(value)
    return value:gsub(" ", "\\ "):gsub("%$", "$$"):gsub("#", "\\#")
end

return M
