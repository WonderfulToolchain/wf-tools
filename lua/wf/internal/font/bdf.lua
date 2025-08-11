-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local stringx = require("pl.stringx")

--- BDF glyph loader.

local M = {}

--- @class wf.api.internal.font.bdf.Char BDF character data
--- @field name string
--- @field encoding? number
--- @field swx0? number
--- @field swy0? number
--- @field dwx0? number
--- @field dwy0? number
--- @field swx1? number
--- @field swy1? number
--- @field dwx1? number
--- @field dwy1? number
--- @field x? number
--- @field y? number
--- @field width? number
--- @field height? number
--- @field bitmap? number[]

--- @class wf.api.internal.font.bdf.Font BDF font data
--- @field bdf_version? string BDF version
--- @field name? string
--- @field pointsize? number
--- @field xdpi? number
--- @field ydpi? number
--- @field x? number
--- @field y? number
--- @field width? number
--- @field height? number
--- @field ascent? number
--- @field descent? number
--- @field family? string
--- @field weight? string
--- @field version? string
--- @field copyright? string
--- @field foundry? string
--- @field chars wf.api.internal.font.bdf.Char[]

--- @return wf.api.internal.font.bdf.Font
M.parse = function(filename)
    local font = {
        ["chars"] = {}
    }
    local file <close> = io.open(filename)
    local infont = false
    local inproperties = nil
    local inchar = nil
    local char = nil
    local inbitmap = nil
    for line in file:lines() do
        if (inbitmap ~= nil) then
            table.insert(char.bitmap, tonumber(line, 16))
            if inbitmap <= 1 then
                inbitmap = nil
            else
                inbitmap = inbitmap - 1
            end
        else
            local key, value = table.unpack(stringx.split(stringx.strip(line), " ", 2))
            if key == "STARTFONT" then
                if not infont then
                    font.bdf_version = value
                    infont = true
                end
            elseif key == "FONT" then
                font.name = value
            elseif key == "SIZE" then
                value = stringx.split(value, " ")
                font.pointsize = tonumber(value[1])
                font.xdpi = tonumber(value[2])
                font.ydpi = tonumber(value[3])
            elseif key == "FONTBOUNDINGBOX" then
                value = stringx.split(value, " ")
                font.x = tonumber(value[3])
                font.y = tonumber(value[4])
                font.width = tonumber(value[1])
                font.height = tonumber(value[2])
            elseif key == "STARTPROPERTIES" then
                inproperties = tonumber(value)
            elseif (inproperties ~= nil) and (key == "FONT_ASCENT") then
                font.ascent = tonumber(value)
            elseif (inproperties ~= nil) and (key == "FONT_DESCENT") then
                font.descent = tonumber(value)
            elseif (inproperties ~= nil) and (key == "FAMILY_NAME") then
                font.family = value
            elseif (inproperties ~= nil) and (key == "WEIGHT_NAME") then
                font.weight = value
            elseif (inproperties ~= nil) and (key == "FONT_VERSION") then
                font.version = value
            elseif (inproperties ~= nil) and (key == "COPYRIGHT") then
                font.copyright = value
            elseif (inproperties ~= nil) and (key == "FOUNDRY") then
                font.foundry = value
            elseif key == "ENDPROPERTIES" then
                inproperties = nil
            elseif key == "CHARS" then
                inchar = tonumber(value)
            elseif (inchar ~= nil) and (key == "STARTCHAR") then
                char = {["name"]=value}
            elseif (char ~= nil) and (key == "ENCODING") then
                char.encoding = tonumber(value)
            elseif (char ~= nil) and (key == "SWIDTH") then
                value = stringx.split(value, " ")
                char.swx0 = tonumber(value[1])
                char.swy0 = tonumber(value[2])    
            elseif (char ~= nil) and (key == "SWIDTH1") then
                value = stringx.split(value, " ")
                char.swx1 = tonumber(value[1])
                char.swy1 = tonumber(value[2])
            elseif (char ~= nil) and (key == "DWIDTH") then
                value = stringx.split(value, " ")
                char.dwx0 = tonumber(value[1])
                char.dwy0 = tonumber(value[2])
            elseif (char ~= nil) and (key == "DWIDTH1") then
                value = stringx.split(value, " ")
                char.dwx1 = tonumber(value[1])
                char.dwy1 = tonumber(value[2])  
            elseif (char ~= nil) and (key == "BBX") then
                value = stringx.split(value, " ")
                char.x = tonumber(value[3])
                char.y = tonumber(value[4])
                char.width = tonumber(value[1])
                char.height = tonumber(value[2])
            elseif (char ~= nil) and (key == "BITMAP") then
                char.bitmap = {}
                if char.height > 0 then
                    inbitmap = char.height
                end
            elseif (char ~= nil) and (key == "ENDCHAR") then
                font.chars[char.encoding] = char
                char = nil
            else
                print("bdf: unknown key: " .. key)
            end
        end
    end
    return font
end

return M
