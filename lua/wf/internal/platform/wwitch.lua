-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Helpers for the "wwitch" target.
-- @module wf.internal.platform.wwitch
-- @alias M

local wfmath = require("wf.internal.math")
local wfstring = require("wf.internal.string")
local M = {}

--- FreyaOS file attribute flags.
M.FILE_ATTRIBUTE_FLAGS = {
    ["x"] = 0x01, -- Execute flag.
    ["w"] = 0x02, -- Write flag.
    ["r"] = 0x04, -- Read flag.
    ["m"] = 0x08, -- Prohibit mmap() use
    ["s"] = 0x10,
    ["i"] = 0x20, -- IL flag.
    ["l"] = 0x40, -- Symbolic link.
    ["d"] = 0x80  -- Directory.
}

--- Convert file attributes to their integer value.
-- @tparam mode number|string Input file attribute value.
-- @treturn number Output file attribute value.
function M.file_attributes_to_integer(mode)
    if type(mode) == "number" then
        return mode
    elseif type(mode) == "string" then
        local mode_int = tonumber(mode)
        if mode_int ~= nil then
            return mode_int
        end
        local result = 0
        for i = 1, #mode do
            local flag = mode:sub(i, i)
            local value = M.FILE_MODE_FLAGS[flag]
            if value ~= nil then
                result = result | value
            end
        end
        return result
    else
        error("invalid mode type")
    end
end

function M.unix_to_freya_time(value)
    local date = os.date("*t", value)
    return wfmath.clamp(date.sec >> 1, 0, 29)
        | (wfmath.clamp(date.min, 0, 59) << 5)
        | (wfmath.clamp(date.hour, 0, 23) << 11)
        | (wfmath.clamp(date.day, 1, 31) << 16)
        | (wfmath.clamp(date.month, 1, 12) << 21)
        | ((date.year - 2000) << 25)
end

function M.create_fent_header(settings)
    local total_length = settings.length
    local resource_start = -1
    if settings.resource then
        total_length = total_length + settings.resource_length
        resource_start = settings.length
    end
    local xmodem_chunk_count = (total_length + 127) >> 7
    local mode = M.file_attributes_to_integer(settings.mode or 7) & 0x2F
    -- seconds since January 1st, 2000
    local mtime = M.unix_to_freya_time(settings.mtime or os.time())

    return "#!ws" .. string.char(255):rep(60)
        .. wfstring.convert(settings.name, wfstring.encoding.shiftjis, wfstring.encoding.utf8, 16)
        .. wfstring.convert(settings.info or settings.name, wfstring.encoding.shiftjis, wfstring.encoding.utf8, 24)
        .. string.pack(
            "< I4 I4 I2 I2 I4 I4 i4",
            0, -- TODO: unknown
            total_length,
            xmodem_chunk_count,
            mode,
            mtime,
            0, -- TODO: unknown
            resource_start
        )
end

return M
