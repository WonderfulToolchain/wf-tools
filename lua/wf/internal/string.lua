-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- String-related utilities.
-- @module wf.internal.string
-- @alias M

local iconv = require("iconv")
local M = {}

--- Convert a string to an encoded binary buffer.
-- @tparam string s The string to convert.
-- @tparam string to Target encoding.
-- @tparam ?string from Source encoding; if not specified, UTF-8 is assumed.
-- @tparam ?number length Length of the output buffer; if not specified, dynamic.
-- @treturn string Converted string.
function M.convert(s, to, from, length)
    local result, err
    if from == to then
        result = s
    else
        local cvt = iconv.new(to, from or "utf8")
        result, err = cvt:iconv(s)
        if err ~= nil then
            error("could not convert string from " .. from .. " to " .. to)
        end
    end
    if length then
        if #result < length then
            result = result .. string.char(0):rep(length - #result)
        elseif #result > length then
            result = result:sub(1, length)
        end
    end
    return result
end

return M
