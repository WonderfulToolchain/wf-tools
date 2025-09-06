-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local wfelf = require('wf.internal.elf')

local target = {}

target.load_elf = function(file, flags)
    return wfelf.ELF(file, flags, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_ARM, wfelf.ET_EXEC)
end

target.group_address_ranges = {
    {0x02000000, 0x0203ffff},
    {0x03000000, 0x03007fff},
    {0x06000000, 0x06017fff},
    {0x08000000, 0x09ffffff}
}

target.address_ranges_to_banks = function(ranges, args, config)
    local banks = {}
    table.insert(banks, {name="IWRAM", range={0x03000000, 0x03007fff}, size=32768, mask=0x7fff})
    table.insert(banks, {name="EWRAM", range={0x02000000, 0x0203ffff}, size=262144, mask=0x3ffff})
    if ranges[3] ~= nil then
        table.insert(banks, {name="VRAM", range={0x06000000, 0x06017fff}, size=96*1024, mask=0x1ffff})
    end
    if ranges[4] ~= nil then
        table.insert(banks, {name="ROM", range={0x08000000, 0x09ffffff}, size=32*1024*1024, mask=0x1ffffff})
    end
    return banks
end

return target