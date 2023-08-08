-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Assorted utilities.
-- @module wf.internal.util
-- @alias M

local utils = require("pl.utils")
local M = {}

--- Convert a table's numbered string entries to boolean flags.
function M.indices_to_boolean_flags(tbl)
    for i=#tbl,1,-1 do
        tbl[tbl[i]] = true
        tbl[i] = nil
    end
end

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
    print(cmd)
    if output_mode == 1 then
        local success, exit_type, code = os.execute(cmd)
        if exit_type ~= "exit" then
            code = nil
        end
        return success == true, code
    else
        local success, code, stdout, stderr = utils.executeex(cmd, output_mode == 3)
        if output_mode == 0 then
            return success, code
        else
            return success, code, stdout, stderr
        end
    end
end

--- Execute a given command with the specified arguments.
-- Fatal error if the command fails.
function M.execute_or_error(command, args, output_mode, verbose)
    local cmd = command .. " " .. utils.quote_arg(args)
    if verbose then
        print("executing '" .. cmd .. "'")
    end
    local success, code, stdout, stderr = M.execute(command, args, output_mode)
    if not success then
        error("error executing '" .. cmd .. "': " .. code)
    end
    return success, code, stdout, stderr
end

--- Convert a string into a valid C identifier.
-- The following rules are used:
-- 1. Any character which is not alphanumeric is turned into an underscore.
-- 2. If the string starts with a number, an additional underscore is appended.
function M.to_c_identifier(s)
  s = s:gsub("[^a-zA-Z0-9_]", "_")
  if not s:sub(1, 1):match("[_a-zA-Z]") then
    s = "_" .. s
  end
  return s
end

--- Get the current script name.
-- @treturn string The current script name.
function M.script_name()
    if arg then
        return arg[0]:gsub(".+[\\/]", ""):gsub("%.%w+$", "")
    else
        return "unknown"
    end
end

return M
