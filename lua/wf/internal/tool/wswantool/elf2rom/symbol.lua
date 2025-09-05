-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local class = require("pl.class")
local tablex = require("pl.tablex")
local wfelf = require("wf.internal.elf")

local Symbol = class()

function Symbol:_init(fields)
    for k, v in pairs(fields) do self[k] = v end
end

function Symbol:is_defined()
    return (self.value ~= nil) or (self.elf ~= nil and self.elf.shndx ~= wfelf.SHN_UNDEF)
end

return {
    Symbol=Symbol
}