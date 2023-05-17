--- Helpers for the "wwitch" target.
-- @module wf.internal.platform.wwitch
-- @alias M

local wfstring = require("wf.string")
local wfstruct = require("wf.struct")
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

function M.create_fent_header(settings)
    local xmodem_chunk_count = (settings.length + 127) >> 7
    local mode = M.file_attributes_to_integer(settings.mode or 7)
    -- seconds since January 1st, 2000
    local mtime = math.min(0x7FFFFFFF, math.max(0, (settings.mtime or os.time()) - 946080000))
    local resource_start = 0xFFFFFFFF
    if settings.resource then
        resource_start = settings.length
    end

    -- TODO: Create struct-like library for this.
    return "#!ws" .. string.char(255):rep(60)
        .. wfstring.convert(settings.name, "sjis", "utf8", 16)
        .. wfstring.convert(settings.info or settings.name, "sjis", "utf8", 24)
        .. string.char(
            0, 0, 0, 0, -- TODO: unknown
            (settings.length) & 0xFF,
            (settings.length >> 8) & 0xFF,
            (settings.length >> 16) & 0xFF,
            (settings.length >> 24) & 0xFF,
            (xmodem_chunk_count) & 0xFF,
            (xmodem_chunk_count >> 8) & 0xFF,
            (mode) & 0xFF,
            (mode >> 8) & 0xFF,
            (mtime) & 0xFF,
            (mtime >> 8) & 0xFF,
            (mtime >> 16) & 0xFF,
            (mtime >> 24) & 0xFF,
            0, 0, 0, 0, -- TODO: unknown
            (resource_start) & 0xFF,
            (resource_start >> 8) & 0xFF,
            (resource_start >> 16) & 0xFF,
            (resource_start >> 24) & 0xFF
        )
end

return M