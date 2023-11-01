-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local toml = require('toml')

local M = {}

M.decode = function(filename)
    local succeeded, table = pcall(toml.decode, filename)
    if succeeded then
        return table
    else
        error(require('pl.pretty').write(table))
    end
end

M.decodeFromFile = function(filename)
    local succeeded, table = pcall(toml.decodeFromFile, filename)
    if succeeded then
        return table
    else
        error(require('pl.pretty').write(table))
    end
end

return M
