-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- wf-lzsa tool wrapper.
-- @module wf.api.v1.process.tools.lzsa
-- @alias M

local path = require("pl.path")
local process = require("wf.api.v1.process")
local tablex = require("pl.tablex")
local wfpath = require("wf.internal.path")
local wfutil = require("wf.internal.util")

local lzsa_path = wfpath.executable("wf-lzsa")
if not path.exists(lzsa_path) then
    error("tool not installed: wf-lzsa")
end

local function lzsa_run(input, args, opts)
    input = process.to_file(input)
    args = tablex.copy(args)
    if opts then
        for i,v in ipairs(opts) do
            if v == "fast" then
                table.insert(args, "--prefer-speed")
            elseif v == "verbose" then
                table.insert(args, "-v")
            elseif v == "backward" then
                table.insert(args, "-b")
            else
                error("unknown argument: " .. v)
            end
        end
    end
    local output = process.tmpfile(".lzsa")
    process.touch(input, "rb")
    table.insert(args, input.file)
    table.insert(args, output.file)
    local success, code = wfutil.execute(lzsa_path, args, wfutil.OUTPUT_SHELL)
    if not success then
        error("tool error: " .. code)
    end
    return output
end

local M = {}

--- Compress file data to raw LZSA1.
-- @tparam string input Input file data.
-- @tparam ?table opts Options table: "fast", "verbose", "backward".
-- @treturn string Converted file data.
function M.compress_raw_1(input, opts)
    return lzsa_run(input, {"-r", "-f", "1"}, opts)
end

--- Compress file data to raw LZSA2.
-- @tparam string input Input file data.
-- @tparam ?table opts Options table: "fast", "verbose", "backward".
-- @treturn string Converted file data.
function M.compress_raw_2(input, opts)
    return lzsa_run(input, {"-r", "-f", "2"}, opts)
end

--- Compress file data to headered LZSA1.
-- @tparam string input Input file data.
-- @tparam ?table opts Options table: "fast", "verbose", "backward".
-- @treturn string Converted file data.
function M.compress_block_1(input, opts)
    return lzsa_run(input, {"-f", "1"}, opts)
end

--- Compress file data to headered LZSA2.
-- @tparam string input Input file data.
-- @tparam ?table opts Options table: "fast", "verbose", "backward".
-- @treturn string Converted file data.
function M.compress_block_2(input, opts)
    return lzsa_run(input, {"-f", "2"}, opts)
end

return M
