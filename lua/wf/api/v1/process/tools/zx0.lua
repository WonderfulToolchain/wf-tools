-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- <a href="https://github.com/WonderfulToolchain/salvador">wf-zx0-salvador</a> tool wrapper.

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
--- @class wf.api.v1.process.tools.zx0.Config
local config = {}

--- Compress/decompress data backwards.
--- @return wf.api.v1.process.tools.zx0.Config self Configuration table.
function config:backward()
    self.data.backward = true
    return self
end

--- Enable verbose terminal output.
--- @return wf.api.v1.process.tools.zx0.Config self Configuration table.
function config:verbose()
    self.data.verbose = true
    return self
end

---
-- @section end

local M = {}

--- Create a configuration table.
--- @param options? table Initial options.
--- @return wf.api.v1.process.tools.zx0.Config self Configuration table.
function M.config(options)
    local c = tablex.deepcopy(options or {})
    local result = {["data"]=c}
    setmetatable(result, config)
    return result
end

--- Compress file data to ZX0 (classic).
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.zx0.Config
function M.compress_classic(input, config)
    return tool_run(input, {"-classic"}, config)
end

--- Compress file data to ZX0.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.zx0.Config
function M.compress(input, config)
    return tool_run(input, {}, config)
end

--- Decompress ZX0 (classic) file data.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.zx0.Config
function M.decompress_classic(input, config)
    return tool_run(input, {"-d", "-classic"}, config)
end

--- Decompress ZX0 file data.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.zx0.Config
function M.decompress(input, config)
    return tool_run(input, {"-d"}, config)
end

return M
