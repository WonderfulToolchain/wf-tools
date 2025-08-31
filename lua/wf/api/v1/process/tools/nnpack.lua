-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- <a href="https://github.com/WonderfulToolchain/wf-nnpack">wf-nnpack</a> tool wrapper for GBA/NDS compressors by CUE.

local process = require("wf.api.v1.process")
local path = require("pl.path")
local wfpackage = require("wf.internal.package")
local wfutil = require("wf.internal.util")

local huffman_tool_path = wfpackage.executable_or_error("wf-nnpack", "wf-nnpack-huffman")
local lzss_tool_path = wfpackage.executable_or_error("wf-nnpack", "wf-nnpack-lzss")
local rle_tool_path = wfpackage.executable_or_error("wf-nnpack", "wf-nnpack-rle")
if (not path.exists(huffman_tool_path)) or (not path.exists(lzss_tool_path)) or (not path.exists(rle_tool_path)) then
    error("tool not installed: wf-nnpack")
end

local function tool_run(tool_path, input, mode)
    input = process.to_file(input)
    local output = process.tmpfile(".nn")

    process.touch(input, "rb")
    process.touch(output, "wb")    
    args = {mode, input.file, output.file}
    wfutil.execute_or_error(tool_path, args, wfutil.OUTPUT_SHELL, _WFPROCESS.verbose)
    return output
end

local M = {}

--- Compress file data using LZSS for VRAM.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_vram(input)
    return tool_run(lzss_tool_path, input, "-evn")
end

--- Compress file data using LZSS for WRAM.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_wram(input)
    return tool_run(lzss_tool_path, input, "-ewn")
end

--- Compress file data using LZSS for VRAM optimally.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_vram_slow(input)
    return tool_run(lzss_tool_path, input, "-evo")
end

--- Compress file data using LZSS for WRAM optimally.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_wram_slow(input)
    return tool_run(lzss_tool_path, input, "-ewo")
end

--- Compress file data using LZSS for VRAM regularly.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_vram_normal(input)
    return tool_run(lzss_tool_path, input, "-evn")
end

--- Compress file data using LZSS for WRAM regularly.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_wram_normal(input)
    return tool_run(lzss_tool_path, input, "-ewn")
end

--- Compress file data using LZSS for VRAM quickly.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_vram_fast(input)
    return tool_run(lzss_tool_path, input, "-evf")
end

--- Compress file data using LZSS for WRAM quickly.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_lzss_wram_fast(input)
    return tool_run(lzss_tool_path, input, "-ewf")
end

--- Decompress file data using LZSS.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.decompress_lzss(input)
    return tool_run(lzss_tool_path, input, "-d")
end

--- Compress file data using RLE.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_rle(input)
    return tool_run(rle_tool_path, input, "-e")
end

--- Decompress file data using RLE.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.decompress_rle(input)
    return tool_run(rle_tool_path, input, "-d")
end

--- Compress file data using Huffman.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_huffman(input)
    return tool_run(huffman_tool_path, input, "-e0")
end

--- Compress file data using 8-bit Huffman.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_huffman8(input)
    return tool_run(huffman_tool_path, input, "-e8")
end

--- Compress file data using 4-bit Huffman.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.compress_huffman4(input)
    return tool_run(huffman_tool_path, input, "-e4")
end

--- Decompress file data using Huffman.
--- @param input wf.api.v1.process.IngredientOrFilename Input file data.
--- @return wf.api.v1.process.Ingredient output Converted file data.
function M.decompress_huffman(input)
    return tool_run(huffman_tool_path, input, "-d")
end

return M
