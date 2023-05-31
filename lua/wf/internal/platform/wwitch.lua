-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Helpers for the "wwitch" target.
-- @module wf.internal.platform.wwitch
-- @alias M

local wfstring = require("wf.string")
local M = {}

--- FreyaOS file attribute flags.
M.FILE_ATTRIBUTE_FLAGS = {
    ["x"] = 0x01, -- Execute flag.
    ["w"] = 0x02, -- Write flag.
    ["r"] = 0x04, -- Read flag.
    ["i"] = 0x20 -- IL flag.
}
-- TODO: Add remaining modes.

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
    return math.min(0x7FFFFFFF, math.max(0, value - 946080000))
end

function M.create_fent_header(settings)
    local xmodem_chunk_count = (settings.length + 127) >> 7
    local mode = M.file_attributes_to_integer(settings.mode or 7)
    -- seconds since January 1st, 2000
    local mtime = M.unix_to_freya_time(settings.mtime or os.time())
    local resource_start = -1
    if settings.resource then
        resource_start = settings.length
    end

    return "#!ws" .. string.char(255):rep(60)
        .. wfstring.convert(settings.name, "sjis", "utf8", 16)
        .. wfstring.convert(settings.info or settings.name, "sjis", "utf8", 24)
        .. string.pack(
            "< I4 I4 I2 I2 I4 I4 i4",
            0, -- TODO: unknown
            settings.length,
            xmodem_chunk_count,
            mode,
            mtime,
            0, -- TODO: unknown
            resource_start
        )
end

return M