--- Math-related utilities.
-- @module wf.math
-- @alias M

local M = {}

--- Align a number (by incrementing) or string (by padding with zeroes) up to a specified alignment.
-- @tparam number|string value The value to be aligned.
-- @tparam number alignment The alignment.
-- @treturn number|string The aligned value.
function M.pad_alignment_to(value, alignment)
    if type(value) == "number" then
        return math.floor(math.ceil(i / alignment) * alignment)
    elseif type(value) == "string" then
        local bytes_to_append = M.pad_alignment_to(#value, alignment) - #value
        return value + string.char(0):rep(bytes_to_append)
    else
        error("invalid value type")
    end  
end

--- Provide the next power of two for a given value.
-- @tparam number i The given value.
-- @tparam ?number min_size The minimum output value.
-- @treturn number The next power of two for the given value.
function M.next_power_of_two(i, min_size)
    min_size = min_size or 0
    if i < min_size then
        i = min_size
    end
    i = i - 1
    i = i | (i >> 1)
    i = i | (i >> 2)
    i = i | (i >> 4)
    i = i | (i >> 8)
    i = i | (i >> 16)
    i = i | (i >> 32)
    return i + 1
end

--- Convert a binary-coded decimal to a value.
-- @tparam number value The given value.
-- @treturn number The binary-coded value.
function M.from_bcd(value)
    local result = 0
    local offset = 1
    while value > 0 do
        result = result + ((value & 0x0F) * offset)
        value = value >> 4
        offset = offset * 10
    end
    return result
end

--- Convert a value to a binary-coded decimal.
-- @tparam number value The given value.
-- @tparam ?number bits The amount of bits taken into account for conversion.
-- @treturn number The binary-coded value.
function M.to_bcd(value, bits)
    bits = bits or 64
    local result = 0
    local offset = 0
    while value > 0 and bits > 0 do
        local i = (value % 10) & ((1 << math.min(bits, 4)) - 1)
        value = value // 10

        result = result | (i << offset)
        bits = bits - 4
        offset = offset + 4
    end
    return result
end

return M