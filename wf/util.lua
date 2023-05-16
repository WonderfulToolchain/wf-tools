local utils = require("pl.utils")
local M = {}

local function align_up_to(value, alignment)
    if type(value) == "number" then
        return math.floor(math.ceil(i / alignment) * alignment)
    elseif type(value) == "string" then
        local bytes_to_append = align_up_to(#value, alignment) - #value
        return value + string.char(0):rep(bytes_to_append)
    else
        error("invalid value type")
    end  
end
M.align_up_to = align_up_to

local function next_power_of_two(i, min_size)
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
M.next_power_of_two = next_power_of_two

M.OUTPUT_NONE = 0
M.OUTPUT_SHELL = 1
M.OUTPUT_CAPTURE = 2
M.OUTPUT_CAPTURE_BINARY = 3
local function execute(command, args, output_mode)
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
M.execute = execute

return M