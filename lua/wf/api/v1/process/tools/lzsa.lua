-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- <a href="https://github.com/WonderfulToolchain/lzsa">wf-lzsa</a> tool wrapper.

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
--- @class wf.api.v1.process.tools.lzsa.Config
local config = {}

--- Compress/decompress data backwards.
--- @return wf.api.v1.process.tools.lzsa.Config self Configuration table.
function config:backward()
    self.data.backward = true
    return self
end

--- Optimize for compression speed.
--- @return wf.api.v1.process.tools.lzsa.Config self Configuration table.
function config:fast()
    self.data.fast = true
    return self
end

--- Enable verbose terminal output.
--- @return wf.api.v1.process.tools.lzsa.Config self Configuration table.
function config:verbose()
    self.data.verbose = true
    return self
end

---
-- @section end

local M = {}

--- Create a configuration table.
--- @param options? table Initial options.
--- @return wf.api.v1.process.tools.lzsa.Config self Configuration table.
function M.config(options)
    local c = tablex.deepcopy(options or {})
    local result = {["data"]=c}
    setmetatable(result, config)
    return result
end

--- Compress file data to raw LZSA1.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.compress1(input, config)
    return tool_run(input, {"-r", "-f", "1"}, config)
end

--- Compress file data to raw LZSA2.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.compress2(input, config)
    return tool_run(input, {"-r", "-f", "2"}, config)
end

--- Compress file data to headered LZSA1.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.compress1_block(input, config)
    return tool_run(input, {"-f", "1"}, config)
end

--- Compress file data to headered LZSA2.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.compress2_block(input, config)
    return tool_run(input, {"-f", "2"}, config)
end

--- Decompress raw LZSA1 file data.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.decompress1(input, config)
    return tool_run(input, {"-d", "-r", "-f", "1"}, config)
end

--- Decompress raw LZSA2 file data.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.decompress2(input, config)
    return tool_run(input, {"-d", "-r", "-f", "2"}, config)
end

--- Decompress headered LZSA1 file data.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.decompress1_block(input, config)
    return tool_run(input, {"-d", "-f", "1"}, config)
end

--- Decompress headered LZSA2 file data.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @param config? table Configuration table.
--- @return wf.api.v1.process.Ingredient output Converted file data.
--- @see wf.api.v1.process.tools.lzsa.Config
function M.decompress2_block(input, config)
    return tool_run(input, {"-d", "-f", "2"}, config)
end

return M
