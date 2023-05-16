--- Assorted utilities.
-- @module wf.util
-- @alias M

local utils = require("pl.utils")
local M = {}

--- Align a number (by incrementing) or string (by padding with zeroes) up to a specified alignment.
-- @tparam number|string value The value to be aligned.
-- @tparam number alignment The alignment.
-- @treturn number|string The aligned value.
function M.align_up_to(value, alignment)
    if type(value) == "number" then
        return math.floor(math.ceil(i / alignment) * alignment)
    elseif type(value) == "string" then
        local bytes_to_append = align_up_to(#value, alignment) - #value
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
    return i + 1
end

M.OUTPUT_NONE = 0
M.OUTPUT_SHELL = 1
M.OUTPUT_CAPTURE = 2
M.OUTPUT_CAPTURE_BINARY = 3
--- Execute a given command with the specified arguments.
function M.execute(command, args, output_mode)
    local cmd = command .. " " .. utils.quote_arg(args)
    if output_mode == 1 then
        return os.execute(cmd)
    else
        local success, code, stdout, stderr = utils.executeex(cmd, output_mode == 3)
        if output_mode == 0 then
            return success, code
        else
            return success, code, stdout, stderr
        end
    end
end

return M