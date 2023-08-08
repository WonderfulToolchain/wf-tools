-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- <a href="https://github.com/WonderfulToolchain/SuperFamiconv">wf-superfamiconv</a> tool wrapper.
-- @module wf.api.v1.process.tools.superfamiconv
-- @alias M

local process = require("wf.api.v1.process")
local path = require("pl.path")
local tablex = require("pl.tablex")
local wfpath = require("wf.internal.path")
local wfutil = require("wf.internal.util")

local tool_path = wfpath.executable("wf-superfamiconv")
if not path.exists(tool_path) then
    error("tool not installed: wf-superfamiconv")
end

local function tool_run(command, inputs, output_mode, config)
    local args = {command}
    for k, v in pairs(inputs) do
        local input = process.to_file(v)
        process.touch(input, "rb")
        table.insert(args, "-" .. k)
        table.insert(args, input.file)
    end
    local output = process.tmpfile(".sfcnv")
    process.touch(output, "wb")
    table.insert(args, "-" .. output_mode)
    table.insert(args, output.file)
    if config and config.data then
        config = config.data
        if config.mode then table.insert(args, "-M") table.insert(args, config.mode) end
        if config.tile_size then
            table.insert(args, "-W") table.insert(args, tostring(config.tile_size[1]))
            table.insert(args, "-H") table.insert(args, tostring(config.tile_size[2]))
        end
        if config.verbose then table.insert(args, "-v") end
        if command == nil or command == "palette" or command == "tiles" then
            if config.no_remap then table.insert(args, "-R") end
            if config.sprite_mode then table.insert(args, "-S") end
        end
        if command == nil or command == "tiles" then
            if config.no_discard then table.insert(args, "-D") end
        end
        if command == nil or command == "tiles" or command == "map" then
            if config.no_flip then table.insert(args, "-F") end
        end
        if command == nil or command == "map" then
            if config.tile_base then table.insert(args, "-T") table.insert(args, tostring(config.tile_base)) end
        end
        if command == nil or command == "palette" then
            if config.color_zero then table.insert(args, "--color-zero") table.insert(args, tostring(config.color_zero)) end
        end
        if command == "palette" then
            if config.palettes then table.insert(args, "-P") table.insert(args, tostring(config.palettes)) end
            if config.colors then table.insert(args, "-C") table.insert(args, tostring(config.colors))
            elseif config.bpp then table.insert(args, "-C") table.insert(args, tostring(1 << config.bpp)) end
        else
            if config.bpp then table.insert(args, "-B") table.insert(args, tostring(config.bpp)) end
        end
        if command == "tiles" then
            if config.max_tiles then table.insert(args, "-T") table.insert(args, tostring(max_tiles)) end
        end
        if command == "map" then
            if config.palette_base then table.insert(args, "-P") table.insert(args, tostring(config.palette_base)) end
            if config.map_size then
                table.insert(args, "--map-width") table.insert(args, tostring(config.map_size[1]))
                table.insert(args, "--map-height") table.insert(args, tostring(config.map_size[2]))
            end
            if config.map_split then
                table.insert(args, "--split-width") table.insert(args, tostring(config.map_split[1]))
                table.insert(args, "--split-height") table.insert(args, tostring(config.map_split[2]))
            end
            if config.column_order then table.insert(args, "--column-order") end
        end
    end
    wfutil.execute_or_error(tool_path, args, wfutil.OUTPUT_SHELL, _WFPROCESS.verbose)
    return output
end

--- SuperFamiconv tool configuration.
-- @type superfamiconv.Config
local config = {}

--- Select target mode/platform.
-- @tparam string mode Mode/platform:<br>
-- <ul><li>snes</li>
-- <li>snes_mode7</li>
-- <li>gb</li>
-- <li>gbc</li>
-- <li>gba</li>
-- <li>gba_affine</li>
-- <li>md</li>
-- <li>pce</li>
-- <li>pce_sprite</li>
-- <li>ws</li>
-- <li>wsc</li>
-- <li>wsc_packed</li></ul>
-- @treturn table Configuration table.
function config:mode(mode)
    self.data.mode = mode
    return self
end

--- Select output bits per pixel.
-- @tparam number bpp Bits per pixel.
-- @treturn table Configuration table.
function config:bpp(bpp)
    self.data.bpp = bpp
    return self
end

--- Select output tile size.
-- @tparam number width Tile width.
-- @tparam number height Tile height.
-- @treturn table Configuration table.
function config:tile_size(width, height)
    self.data.tile_size = {width, height}
    return self
end

--- Disable color remapping.
-- @treturn table Configuration table.
function config:no_remap()
    self.data.no_remap = true
    return self
end

--- Disable discarding redundant tiles.
-- @treturn table Configuration table.
function config:no_discard()
    self.data.no_discard = true
    return self
end

--- Disable horizontal/vertical tile flipping.
-- @treturn table Configuration table.
function config:no_flip()
    self.data.no_flip = true
    return self
end

--- Disable all tilemap optimizations; assume the image
-- is a direct representation of the desired tiles.
-- @treturn table Configuration table.
function config:tile_direct()
    self.data.no_remap = true
    self.data.no_discard = true
    self.data.no_flip = true
    return self
end

--- Apply sprite output settings.
-- @treturn table Configuration table.
function config:sprite_mode()
    self.data.sprite_mode = true
    return self
end

--- Set a maximum number of tiles.
-- @tparam number count Tile count.
-- @treturn table Configuration table.
function config:max_tiles(count)
    self.data.max_tiles = count
    return self
end

--- Split a palette into subpalettes.
-- @tparam number palettes Number of palettes.
-- @tparam number colors Colors per subpalette.
-- @treturn table Configuration table.
function config:subpalettes(palettes, colors)
    self.data.palettes = palettes
    self.data.colors = colors
    return self
end

--- Configure color #0.
-- @tparam string value Color value.
-- @treturn table Configuration table.
function config:color_zero(value)
    self.data.color_zero = value
    return self
end

--- Set base tile offset.
-- @tparam number offset Offset.
-- @treturn table Configuration table.
function config:tile_base(offset)
    self.data.tile_base = offset
    return self
end

--- Set base palette offset.
-- @tparam number offset Offset.
-- @treturn table Configuration table.
function config:palette_base(offset)
    self.data.palette_base = offset
    return self
end

--- Set output map size.
-- @tparam number width Width.
-- @tparam number height Height.
-- @treturn table Configuration table.
function config:map_size(width, height)
    self.data.map_size = {width, height}
    return self
end

--- Split output map into columns and rows of specified size.
-- @tparam number width Width.
-- @tparam number height Height.
-- @tparam ?boolean column_order If true, use column-major order to output map data.
-- @treturn table Configuration table.
function config:split_map(width, height, column_order)
    self.data.map_split = {width, height}
    self.data.map_column_order = column_order or false
    return self
end

--- Enable verbose terminal output.
-- @treturn table Configuration table.
function config:verbose()
    self.data.verbose = true
    return self
end

config.__index = config

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

--- Convert image data to raw palette data.
-- @tparam string input Input image data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted raw palette data.
-- @see config
function M.palette(input, config)
    return tool_run("palette", {["i"]=input}, "d", config)
end

--- Convert image data to raw tile data.
-- @tparam string input Input image data.
-- @tparam string palette Input palette data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted raw palette data.
-- @see config
function M.tiles(input, palette, config)
    return tool_run("tiles", {["i"]=input, ["p"]=palette}, "d", config)
end

--- Convert image data to raw map data.
-- @tparam string input Input image data.
-- @tparam string palette Input palette data.
-- @tparam string tiles Input tile data.
-- @tparam ?table config Configuration table.
-- @treturn string Converted raw palette data.
-- @see config
function M.map(input, palette, tiles, config)
    return tool_run("map", {["i"]=input, ["p"]=palette, ["t"]=tiles}, "d", config)
end

--- Convert image data to palette and tile data.
-- @tparam string input Input image data.
-- @tparam ?table config Configuration table.
-- @treturn table Converted raw palette, tiles, and map data.
-- @see config
function M.convert_tileset(input, config)
    local palette = M.palette(input, config)
    local tiles = M.tiles(input, palette, config)
    return {
        ["palette"]=palette,
        ["tiles"]=tiles
    }
end

--- Convert image data to palette, tile and map data.
-- @tparam string input Input image data.
-- @tparam ?table config Configuration table.
-- @treturn table Converted raw palette, tiles, and map data.
-- @see config
function M.convert_tilemap(input, config)
    local palette = M.palette(input, config)
    local tiles = M.tiles(input, palette, config)
    local map = M.map(input, palette, tiles, config)
    return {
        ["palette"]=palette,
        ["tiles"]=tiles,
        ["map"]=map
    }
end

return M
