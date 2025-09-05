-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local class = require('pl.class')
local wfterm = require('wf.internal.term')

local Graph = class()

local ascii_shades = {
    {"."},
    {"-"},
    {"="},
    {"#"}
}

local function get_next_offset_value(graph, offset)
    if offset == graph.graph_size then
        return graph.data_size
    else
        return graph.offsets[offset + 1]
    end
end

local function get_max_count(graph, offset)
    return get_next_offset_value(graph, offset) - graph.offsets[offset]
end

function Graph:_init(width, height, data_size)
    self.width = width
    self.height = height
    self.graph_size = width * height
    self.data_size = data_size
    self.counts = {}
    self.offsets = {}
    for i=1,self.graph_size do
        table.insert(self.counts, 0)
        table.insert(self.offsets, math.floor((i - 1) * self.data_size / self.graph_size))
    end
end

function Graph:mark_area_used(first, size)
    if size <= 0 then return end

    local o = math.floor(first * self.graph_size / self.data_size)
    if o < 1 then o = 1 end

    while o >= 1 and o <= self.graph_size and size > 0 do
        local from = self.offsets[o]
        local to = get_next_offset_value(self, o) - 1
        local last = first + size - 1

        if (first >= from and first <= to) or (last >= from and last <= to) then
            if from > first then
                size = size - (from - first)
                first = from
            end
            if to >= last then
                self.counts[o] = self.counts[o] + size
                break
            else
                local count = to - first + 1
                self.counts[o] = self.counts[o] + count
                size = size - count
                first = first + count
            end
        end
        o = o + 1
    end
end

function Graph:generate_ascii_text()
    local s = ""
    for i=1,self.graph_size do
        local idx = 1
        local cnt = self.counts[i]
        if cnt > 0 then
            local cnt_max = get_max_count(self, i)
            idx = 1 + math.ceil(cnt * (#ascii_shades - 1) / cnt_max)
        end
        s = s .. ascii_shades[idx][1]

        -- if (i % self.width) == 0 then s = s .. wfterm.reset() end
        if i < self.graph_size and (i % self.width) == 0 then s = s .. "\n" end
    end
    return s
end

return Graph
