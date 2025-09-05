-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local wfelf = require('wf.internal.elf')

local target = {}

target.load_elf = function(file)
    return wfelf.ELF(file, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_386)
end

target.group_address_ranges = {
    {0x00000000, 0x0000ffff},
    {0x00010000, 0x0001ffff}
}

target.address_ranges_to_banks = function(ranges, config)
    return {
        {name="Code", range={0x00000000, 0x0000ffff}, size=65536, mask=0xffff},
        {name="Data", range={0x00010000, 0x0001ffff}, size=65536, mask=0xffff}
    }
end

return target