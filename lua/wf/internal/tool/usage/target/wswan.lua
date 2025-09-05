-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local wfelf = require('wf.internal.elf')
local wfwswan = require('wf.internal.platform.wswan')

local target = {}

-- IRAM
-- +- Mono
-- +- Color
-- SRAM
-- +- $00
-- Cartridge ROM
-- +- Bank $F0
-- +- Linear $Fx
--    +- Bank $FF

target.load_elf = function(file)
    return wfelf.ELF(file, wfelf.ELFCLASS32, wfelf.ELFDATA2LSB, wfelf.EM_386)
end

target.group_address_ranges = {
    {0x00000000, 0x0000ffff},
    {0x10000000, 0x1fffffff},
    {0x20000000, 0x2fffffff}
}

-- Map ELF addresses to:
-- 0x0000nnnn - IRAM
-- 0x1bbbnnnn - SRAM
-- 0x2bbbnnnn - ROM
target.map_address = function(address)
    if address <= 0xffff then return address end
    if (address & 0xf0000) == 0x10000 then
        return 0x10000000 | ((address >> 4) & 0xfff0000) | (address & 0xffff)
    end
    if address >= 0x80000000 then
        return 0x20000000 | ((address >> 4) & 0xfff0000) | (address & 0xffff)
    end
    return nil
end

target.address_ranges_to_banks = function(ranges, config)
    local banks = {}
    if ranges[1] ~= nil then
        local bank_iram = {name="IRAM", range={0x00000000, 0x00003fff}, size=16384, mask=0xFFFF}
        table.insert(banks, bank_iram)
        if ranges[1][2] >= 0x4000 then
            bank_iram.range[2] = 0x0000ffff
            bank_iram.size = 65536
            table.insert(banks, {name="Mono area", depth=1, range={0x00000000, 0x00003fff}, size=16384, mask=0xFFFF})
            table.insert(banks, {name="Color area", depth=1, range={0x00004000, 0x0000ffff}, size=49152, mask=0xFFFF})
        end
    end

    local sram_size = wfwswan.SRAM_SIZE_BY_TYPE[config.cartridge.save_type or "NONE"] or 0
    if sram_size == 0 and ranges[2] ~= nil then
        -- Estimate SRAM size
        sram_size = ((ranges[2][2] >> 16) - 0x1000) * 65536
    end
    if sram_size > 0 then
        local sram_last = 0x10000000 + sram_size - 1
        table.insert(banks, {name="SRAM", range={0x10000000, sram_last}, size=sram_size, mask=sram_last-0x10000000})
        for i=0,sram_size-1,65536 do
            local bank_size = sram_size - i
            if bank_size > 65536 then bank_size = 65536 end
            local sram_first = ((i & 0xFFFF0000) << 4) | 0x10000
            local sram_last = ((i & 0xFFFF0000) << 4) | 0x1ffff
            table.insert(banks, {name=string.format("$%02X", i >> 16), depth=1, range={sram_first, sram_last}, size=65536})
        end
    end

    if ranges[3] ~= nil then
        local rom_size = 131072
        if config.cartridge.rom_banks then
            rom_size = config.cartridge.rom_banks * 65536
        end
        local elf_rom_size = ((ranges[3][2] >> 16) - (ranges[3][1] >> 16) + 1) * 65536
        if rom_size < elf_rom_size then rom_size = elf_rom_size end

        local banks_count = math.ceil(rom_size / 65536)
        local banks_width_small = math.ceil(math.log(banks_count, 2) / 4)
        if banks_width_small < 1 then banks_width_small = 1 end
        local banks_width = banks_width_small
        if banks_width < 2 then banks_width = 2 end
        local banks_elf_offset = (0x1000 - (1 << (4 * banks_width)))
        local banks_offset = (1 << (4 * banks_width)) - banks_count
        local banks_str = "Bank $%0" .. banks_width .. "X"
        local linear_banks_count = math.ceil(rom_size / 1048576)
        local linear_banks_width = 2
        local linear_banks_offset = (1 << (4 * linear_banks_width)) - linear_banks_count
        local linear_banks_str = "Linear $%0" .. linear_banks_width .. "X"
        local address_mask = (0x10000 << (banks_width_small * 4)) - 1

        table.insert(banks, {name="Cartridge ROM", range={(ranges[3][2] | 0xFFFF) - (banks_count * 65536) + 1, ranges[3][2] | 0xFFFF}, size=rom_size, mask=address_mask})

        local define_rom_bank = function(bank, depth)
            local range_from = ((banks_elf_offset + bank) << 16) + 0x20000000
            local range_to = range_from + 0xffff
            local size = 65536
            if (rom_size & 65535) ~= 0 and bank == banks_offset then
                size = (rom_size & 65535)
            end
            return {name=string.format(banks_str, bank), depth=depth, range={range_from, range_to}, size=size, mask=address_mask}
        end

        for i=0,linear_banks_count-1,1 do
            local linear_bank_idx = linear_banks_offset + i
            local bank_idx_offset = (linear_bank_idx & ((1 << (4 * (banks_width - 1))) - 1)) << 4
            local linear_range_from = ((banks_elf_offset + bank_idx_offset + 4) << 16) + 0x20000000
            local linear_range_to = linear_range_from + 0xbffff

            for i=0,3 do
                local idx = bank_idx_offset + i
                if idx >= banks_offset then
                    table.insert(banks, define_rom_bank(idx, 1))
                end
            end

            local linear_bank_count = 12
            if (bank_idx_offset + 4) < banks_offset then
                linear_bank_count = 16 - (banks_offset - bank_idx_offset)
            end
            local linear_size = linear_bank_count << 16

            local linear_bank = {name=string.format(linear_banks_str, linear_bank_idx), depth=1, range={linear_range_from, linear_range_to}, size=linear_size, mask=address_mask}
            table.insert(banks, linear_bank)

            for i=4,15 do
                local idx = bank_idx_offset + i
                if idx >= banks_offset then
                    table.insert(banks, define_rom_bank(idx, 2))
                end
            end
        end
    end

    return banks
end

return target