-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- <a href="https://github.com/WonderfulToolchain/lzsa">wf-lzsa</a> tool wrapper.
-- @module wf.api.v1.process.tools.lzsa
-- @alias M

local process = require("wf.api.v1.process")
local path = require("pl.path")
local tablex = require("pl.tablex")
local wfpath = require("wf.internal.path")
local wfutil = require("wf.internal.util")

local tool_path = wfpath.executable("wf-lzsa")
if not path.exists(tool_path) then
    error("tool not installed: wf-lzsa")
end

local function tool_run(input, args, config)
    if getmetatable(config) ~= nil and getmetatable(config).__config_data ~= nil then
        config = getmetatable(config).__config_data
    end
    input = process.to_file(input)
    args = tablex.copy(args)
    if config and config.data then
        config = config.data
        if config.fast then table.insert(args, "--prefer-speed") end
        if config.verbose then table.insert(args, "-v") end
        if config.backward then table.insert(args, "-b") end
    end
    local output = process.tmpfile(".lzsa")
    process.touch(input, "rb")
    process.touch(output, "wb")
    table.insert(args, input.file)
    table.insert(args, output.file)
    wfutil.execute_or_error(tool_path, args, wfutil.OUTPUT_SHELL, _WFPROCESS.verbose)
    return output
end

--- LZSA tool configuration.
-- @type lzsa.Config
local config = {}

--- Compress/decompress data backwards.
-- @treturn table Configuration table.
function config:backward()
    self.data.backward = true
    return self
end

--- Optimize for compression speed.
-- @treturn table Configuration table.
function config:fast()
    self.data.fast = true
    return self
end

--- Enable verbose terminal output.
-- @treturn table Configuration table.
function config:verbose()
    self.data.verbose = true
    return self
end

---
-- @section end

local M = {}

--- Create a configuration table.
-- @tparam ?table options Initial options.
-- @treturn table Configuration table.
function M.config(options)
    local c = tablex.deepcopy(options or {})
    local result = {["data"]=c}
    setmetatable(result, config)
    return result
end

--- Compress file data to raw LZSA1.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.compress1(input, config)
    return tool_run(input, {"-r", "-f", "1"}, config)
end

--- Compress file data to raw LZSA2.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.compress2(input, config)
    return tool_run(input, {"-r", "-f", "2"}, config)
end

--- Compress file data to headered LZSA1.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.compress1_block(input, config)
    return tool_run(input, {"-f", "1"}, config)
end

--- Compress file data to headered LZSA2.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.compress2_block(input, config)
    return tool_run(input, {"-f", "2"}, config)
end

--- Decompress raw LZSA1 file data.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.decompress1(input, config)
    return tool_run(input, {"-d", "-r", "-f", "1"}, config)
end

--- Decompress raw LZSA2 file data.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.decompress2(input, config)
    return tool_run(input, {"-d", "-r", "-f", "2"}, config)
end

--- Decompress headered LZSA1 file data.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.decompress1_block(input, config)
    return tool_run(input, {"-d", "-f", "1"}, config)
end

--- Decompress headered LZSA2 file data.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.decompress2_block(input, config)
    return tool_run(input, {"-d", "-f", "2"}, config)
end

return M
