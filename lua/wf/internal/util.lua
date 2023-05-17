--- Assorted utilities.
-- @module wf.internal.util
-- @alias M

local utils = require("pl.utils")
local M = {}

--- For execute(), do not capture stdout/stderr.
M.OUTPUT_NONE = 0
--- For execute(), print stdout/stderr to the script's stdout/stderr.
M.OUTPUT_SHELL = 1
--- For execute(), capture stdout/stderr to variables as text data.
M.OUTPUT_CAPTURE = 2
--- For execute(), capture stdout/stderr to variables as binary data.
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