-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- String-related utilities.

local iconv = require("iconv")
local M = {}

--- Useful constants for M.convert
M.encoding = {}
M.encoding.utf8 = "utf-8"
M.encoding.shiftjis = "sjis"

--- Pad a string to a specific length, padded by a specific character.
-- This will both truncate and expand the string.
--- @param value string The string to pad.
--- @param vlen number The expected length.
--- @param pad_char? number The padding character, \0 by default.
--- @return result string The aligned value.
function M.pad_to_length(value, vlen, pad_char)
    if #value == vlen then
        return value
    elseif #value > vlen then
        return value:sub(1, vlen)
    else
        local bytes_to_append = vlen - #value
        return value .. (pad_char or string.char(0)):rep(bytes_to_append)
    end  
end

--- Convert a string to an encoded binary buffer.
--- @param s string The string to convert.
--- @param to string Target encoding.
--- @param from? string Source encoding; if not specified, UTF-8 is assumed.
--- @param length? number Length of the output buffer; if not specified, dynamic.
--- @return string result Converted string.
function M.convert(s, to, from, length)
    local result, err
    if from == to then
        result = s
    else
        local cvt = iconv.new(to, from or M.encoding.utf8)
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
