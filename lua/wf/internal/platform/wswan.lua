-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Helpers for the "wswan" target.
-- @module wf.internal.platform.wswan
-- @alias M

local wfmath = require("wf.internal.math")
local M = {}

--- The size of the wswan ROM header, in bytes.
M.ROM_HEADER_SIZE = 16

--- Table of supported mapper types.
M.MAPPER_TYPES = {
    "2001", -- 2001
    "2003", -- 2003
    "KARNAK" -- KARNAK (PCv2-specific)
}

--- Map of ROM bank counts to ROM size values for the header.
M.ROM_BANK_COUNT_TO_HEADER_SIZE = {
    [2] = 0x00, -- 0x00 (guessed)
    [4] = 0x01, -- 0x01 (guessed)
    [8] = 0x02, -- 0x02
    [16] = 0x03, -- 0x03
    [32] = 0x04, -- 0x04
    [48] = 0x05, -- 0x05 (guessed)
    [64] = 0x06, -- 0x06
    [96] = 0x07, -- 0x07 (guessed)
    [128] = 0x08, -- 0x08
    [256] = 0x09, -- 0x09
    [512] = 0x0A, -- 0x0A (guessed, 2003 mapper only)
    [1024] = 0x0B  -- 0x0B (guessed, 2003 mapper only)
}

--- Map of save type names to header values.
M.SAVE_TYPES_BY_NAME = {
    ["NONE"] = 0x00, -- No save memory present.
    ["SRAM_8KB"] = 0x01, -- 8 kilobytes of SRAM.
    ["SRAM_32KB"] = 0x02, -- 32 kilobytes of SRAM.
    ["SRAM_128KB"] = 0x03, -- 128 kilobytes of SRAM.
    ["SRAM_256KB"] = 0x04, -- 256 kilobytes of SRAM.
    ["SRAM_512KB"] = 0x05, -- 512 kilobytes of SRAM.
    ["EEPROM_128B"] = 0x10, -- 128 bytes of EEPROM.
    ["EEPROM_2KB"] = 0x20, -- 2 kilobytes of EEPROM.
    ["EEPROM_1KB"] = 0x50 -- 1 kilobyte of EEPROM.
}

--- Fast method to calculate the ROM checksum for a repeated byte.
-- @tparam number pad The padding byte value.
-- @tparam number count The number of occurences of the given byte.
-- @treturn number The calculated checksum.
function M.calculate_rom_padding_checksum(pad, count)
    if count < 0 then
        error("invalid pad count: " .. count)
    end
    return ((pad & 0xFF) * (count & 0xFFFF)) & 0xFFFF
end

--- Calculate the ROM checksum for the provided values.
-- @tparam string|table|number ... Checksum component.
-- @treturn number The calculated checksum.
function M.calculate_rom_checksum(...)
    local arg = {...}
    local checksum = 0
    local bytes_read = 0
    for i, value in ipairs(arg) do
        if type(value) == "number" then
            checksum = (checksum + value) & 0xFFFF
        elseif type(value) == "string" then
            for k = 1, #value do
                checksum = (checksum + value:byte(k, k)) & 0xFFFF
            end
            bytes_read = bytes_read + #value
        elseif type(value) == "table" then
            local v_checksum, v_bytes_read = M.calculate_rom_checksum(table.unpack(value))
            checksum = (checksum + v_checksum) & 0xFFFF
            bytes_read = bytes_read + v_bytes_read
        else
            error("unsupported value type")
        end
    end
    return checksum, bytes_read
end

--- Create a ROM header for the specified checksum and settings.
-- @tparam number checksum The checksum for the ROM, excluding the header.
-- @tparam table settings The settings.
-- @treturn string The ROM header.
function M.create_rom_header(checksum, settings)
    local maintenance = settings.maintenance or 0x00
    if settings.disable_custom_boot_splash then
        maintenance = maintenance | 0x80
    end

    local color = 0x00
    if settings.color then
        color = 0x01
    end

    local game_version = settings.game_version or 0x00
    if settings.unlock_internal_eeprom then
        game_version = game_version | 0x80
    else
        game_version = game_version & 0x7F
    end

    local flags = settings.flags or 0x04
    if settings.rom_speed then
        if settings.rom_speed == 3 then
            flags = flags | 0x08
        elseif settings.rom_speed == 1 then
            flags = flags & 0xF7
        else
            error("invalid rom_speed value")
        end
    end
    if settings.rom_bus_width then
        if settings.rom_bus_width == 16 then
            flags = flags | 0x04
        elseif settings.rom_bus_width == 8 then
            flags = flags & 0xFB
        else
            error("invalid rom_bus_width value")
        end
    end
    if settings.orientation then
        if settings.orientation == "vertical" then
            flags = flags | 0x01
        elseif settings.orientation == "horizontal" then
            flags = flags & 0xFE
        else
            error("invalid orientation value")
        end
    elseif settings.vertical then
        flags = flags | 0x01
    end

    local mapper = 0x00
    if type(settings.mapper) == "number" then
        mapper = settings.mapper
    elseif settings.mapper == "KARNAK" then
        mapper = 0x02
    elseif settings.rtc or (settings.mapper == "2003") then
        mapper = 0x01
    elseif settings.mapper and (settings.mapper ~= "2001") then
        error("invalid mapper value")
    end

    local save_type = M.SAVE_TYPES_BY_NAME[settings.save_type or "NONE"]
    if save_type == nil then
        error("invalid save type value")
    end

    local header = string.char(
        -- Far jump to code start
        0xEA,
        (settings.start_offset) & 0xFF,
        (settings.start_offset >> 8) & 0xFF,
        (settings.start_segment) & 0xFF,
        (settings.start_segment >> 8) & 0xFF,

        maintenance,
        settings.publisher_id or 0xFF,
        color,
        wfmath.to_bcd(settings.game_id or 0, 8),
        game_version,

        settings.rom_size,
        save_type,
        flags,
        mapper
    )
    
    checksum = M.calculate_rom_checksum(checksum, header)
    return header .. string.char(checksum & 0xFF, checksum >> 8)
end

return M
