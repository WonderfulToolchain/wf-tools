-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- <a href="https://github.com/WonderfulToolchain/salvador">wf-zx0-salvador</a> tool wrapper.
-- @module wf.api.v1.process.tools.zx0
-- @alias M

local process = require("wf.api.v1.process")
local path = require("pl.path")
local tablex = require("pl.tablex")
local wfpath = require("wf.internal.path")
local wfutil = require("wf.internal.util")

local tool_path = wfpath.executable("wf-zx0-salvador")
if not path.exists(tool_path) then
    error("tool not installed: wf-zx0-salvador")
end

local function tool_run(input, args, config)
    if getmetatable(config) ~= nil and getmetatable(config).__config_data ~= nil then
        config = getmetatable(config).__config_data
    end
    input = process.to_file(input)
    args = tablex.copy(args)
    if config and config.data then
        config = config.data
        if config.verbose then table.insert(args, "-v") end
        if config.backward then table.insert(args, "-b") end
    end
    local output = process.tmpfile(".zx0")
    process.touch(input, "rb")
    process.touch(output, "wb")
    table.insert(args, input.file)
    table.insert(args, output.file)
    wfutil.execute_or_error(tool_path, args, wfutil.OUTPUT_SHELL, _WFPROCESS.verbose)
    return output
end

--- ZX0 tool configuration.
-- @type zx0.Config
local config = {}

--- Compress/decompress data backwards.
-- @treturn table Configuration table.
function config:backward()
    self.data.backward = true
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

--- Compress file data to ZX0 (classic).
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.compress_classic(input, config)
    return tool_run(input, {"-classic"}, config)
end

--- Compress file data to ZX0.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.compress(input, config)
    return tool_run(input, {}, config)
end

--- Decompress ZX0 (classic) file data.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.decompress_classic(input, config)
    return tool_run(input, {"-d", "-classic"}, config)
end

--- Decompress ZX0 file data.
-- @tparam string input Input file data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted file data.
-- @see config
function M.decompress(input, config)
    return tool_run(input, {"-d"}, config)
end

return M
