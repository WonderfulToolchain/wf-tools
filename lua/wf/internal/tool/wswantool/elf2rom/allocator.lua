-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

-- @module wf.internal.tool.wswantool.romlink.allocator
-- @alias M

local class = require("pl.class")
local tablex = require("pl.tablex")

local M = {}

local Bank = class()
M.Bank = Bank

function Bank:_init(size, descending)
    self.size = size
    self.entries = {}
    self.descending = descending
end

function Bank:allocation_start()
    local first = self.entries[1]
    if first == nil then
        return 0
    else
        return first.offset
    end
end

function Bank:allocation_end()
    local last = self.entries[#self.entries]
    if last == nil then
        return -1
    else
        return last.offset + #last.data - 1
    end
end

function Bank:is_empty()
    return #self.entries == 0
end

function Bank:is_full()
    return self:allocation_end() == self.size - 1
end

local function calc_eoffset(estart, eend, elen, descending, align)
    if descending then
        local eoffset = eend - (elen or 0)
        if align ~= nil then
            eoffset = eoffset - (eoffset % align)
        end
        if eoffset >= estart then
            return eoffset
        end
    else
        local eoffset = estart
        if align ~= nil then
            eoffset = eoffset + align - 1
            eoffset = eoffset - (eoffset % align)
        end
        if (eoffset + elen) <= eend then
            return eoffset
        end
    end

    return nil
end

function Bank:largest_gap()
    if self:is_empty() then
        return 0, self.size
    else
        local previous = self.entries[1]
        local gap_start = 0
        local gap_size = previous.offset

        for i=2,#self.entries do
            local current = self.entries[i]

            local current_gap = current.offset - previous.offset - #previous.data
            if current_gap > gap_size then
                gap_start = previous.offset + #previous.data
                gap_size = current_gap
            end

            previous = current
        end

        local current_gap = self.size - previous.offset - #previous.data
        if current_gap > gap_size then
            gap_start = previous.offset + #previous.data
            gap_size = current_gap
        end

        return gap_start, gap_size
    end
end

-- offset can be set or not set
function Bank:try_place(entry, simulate)
    if #entry.data > self.size then
        return false
    end

    if self:is_empty() then
        local eoffset = entry.offset or calc_eoffset(0, self.size, #entry.data, self.descending, entry.align)
        if not simulate then
            entry.offset = eoffset
            table.insert(self.entries, entry)
        end
        return true, eoffset
    else
        if entry.offset ~= nil then
            -- Offset defined.
            -- Doesn't handle alignment!
            -- TODO: Merge adjacent entries.
            local estart = entry.offset
            local eend = entry.offset + #entry.data - 1

            local previous = self.entries[1]
            if eend < previous.offset then
                if not simulate then
                    entry.offset = estart
                    table.insert(self.entries, 1, entry)
                end
                return true, estart
            end

            for i=2,#self.entries do
                local current = self.entries[i]

                if estart >= (previous.offset + #previous.data) and estart < current.offset then
                    local gap = current.offset - estart
                    if gap >= #entry.data then
                        if not simulate then
                            entry.offset = estart
                            table.insert(self.entries, i, entry)
                        end
                        return true, estart
                    end
                end

                previous = current
            end
            
            if estart >= (previous.offset + #previous.data) then
                local gap = self.size - estart
                if gap >= #entry.data then
                    if not simulate then
                        entry.offset = estart
                        table.insert(self.entries, entry)
                    end
                    return true, estart
                end
            end
        else
            -- Offset not defined.
            -- TODO: Merge adjacent entries.
            local previous = self.entries[1]
            if previous.offset >= #entry.data then
                local eoffset = calc_eoffset(0, previous.offset, #entry.data, self.descending, entry.align)
                if eoffset ~= nil then
                    if not simulate then
                        entry.offset = eoffset
                        table.insert(self.entries, 1, entry)
                    end
                    return true, eoffset
                end
            end

            for i=2,#self.entries do
                local current = self.entries[i]

                local gap = current.offset - previous.offset - #previous.data
                if gap >= #entry.data then
                    local eoffset = calc_eoffset(previous.offset + #previous.data, current.offset, #entry.data, self.descending, entry.align)
                    if eoffset ~= nil then
                        if not simulate then
                            entry.offset = eoffset
                            table.insert(self.entries, i, entry)
                        end
                        return true, eoffset
                    end
                end

                previous = current
            end

            local gap = self.size - previous.offset - #previous.data
            if gap >= #entry.data then
                local eoffset = calc_eoffset(previous.offset + #previous.data, self.size, #entry.data, self.descending, entry.align)
                if eoffset ~= nil then
                    if not simulate then
                        entry.offset = eoffset
                        table.insert(self.entries, entry)
                    end
                    return true, eoffset
                end
            end
        end
    end

    return false
end

local Allocator = class()
M.SRAM = -2
M.IRAM = -3
M.BANK01 = -1
M.BANK0 = 0
M.BANK1 = 1
M.BANKLINEAR = 2
M.Allocator = Allocator

function Allocator:_init()
    self.entries = {}
    self.fixed_entries = {}
    self.banks = nil
end

--- Add an entry to the bank allocator.
-- Fields:
-- * data: binary data to add
-- * type: M.SRAM, M.IRAM, M.BANK...
-- * bank: physical bank index to add to
-- * offset: offset in physical bank to add to
-- * align: alignment
function Allocator:add(entry)
    if entry.offset then
        table.insert(self.fixed_entries, entry)
    else
        table.insert(self.entries, entry)
    end
end

local function get_entry_name(entry)
    -- TODO: Improve logging.
    if entry.name then
        if type(entry.name) == "string" then
            return entry.name
        else
            return entry:name()
        end
    else
        return "???"
    end
end

-- discerns limit from type
local function try_place_entry_inner(banks, entry)
    local bank = banks[entry.bank]
    if bank == nil then
        return false
    end

    if (#entry.data <= bank.size) then
        if bank:try_place(entry, false) then
            return true
        end
    end

    local limit = nil
    if entry.type then
        if entry.type == 2 then
            limit = 16 - (entry.bank & 0x0F)
        elseif entry.type == -1 then
            limit = 2
        else
            limit = 1
        end
    end

    -- TODO: Implement splitting across multiple banks
    return false    
end

local function try_place_entry(banks, entry)
    banks = banks[entry.type]

    if entry.type == 2 and entry.bank ~= nil then
        for i=(entry.bank * 16 + 15),(entry.bank * 16 + 4),-1 do
            entry.bank = i
            if try_place_entry_inner(banks, entry) then
                return true
            end
        end
    elseif entry.bank == nil then
        if entry.type < -1 then
            for i, v in tablex.sort(banks, function(a, b) return a < b end) do
                entry.bank = i
                if try_place_entry_inner(banks, entry) then
                    return true
                end
            end
        else
            for i, v in tablex.sort(banks, function(a, b) return a > b end) do
                entry.bank = i
                if try_place_entry_inner(banks, entry) then
                    return true
                end
            end
        end
        return false
    end

    return try_place_entry_inner(banks, entry)
end

local function calculate_bank_sizes(banks)
    local first_bank = 10000000
    local last_bank = -1
    for i, bank in pairs(banks) do
        if not bank:is_empty() then
            if first_bank > i then first_bank = i end
            if last_bank < i then last_bank = i end
        end
    end
    if first_bank > last_bank then
        return {
            ["count"] = 0
        }
    else
        return {
            ["first"] = first_bank,
            ["last"] = last_bank,
            ["count"] = last_bank + 1 - first_bank
        }
    end
end

function Allocator:allocate(config)
    local banks = self.banks
    if banks == nil then
        banks = {}
        banks[-3] = {Bank(config.iram_size or 65536, false)} -- IRAM
        banks[-2] = {} -- SRAM
        banks[0] = {}
        banks[2] = {}

        local sram_size = config.sram_size or 0
        for i=0,sram_size,65536 do
            banks[-2][i] = Bank(math.min(65536, sram_size - i), false)
        end

        local max_bank_count = config.rom_banks or 128
        for i=0,max_bank_count-1 do
            local b = Bank(65536, true)
            banks[0][65535 - i] = b
            if ((i & 0xF) < 0xC) then
                banks[2][65535 - i] = b
            end
        end

        banks[1] = banks[0]
        banks[-1] = banks[0]
    end

    -- Add fixed entries, as we know exactly where they need to go.
    for i, entry in pairs(self.fixed_entries) do
        if not try_place_entry(banks, entry) then
            error("could not allocate: " .. get_entry_name(entry))
        end
    end
    
    -- Sort entries in addition order:
    -- First, consider type: type 2 comes before type 0 and 1
    -- Second, consider bank: present comes before non-present
    -- Third, consider offset: present comes before non-present
    -- (We don't need to consider this, as fixed entries are processed early.)
    -- Fourth, consider alignment: present comes before non-present
    -- Fifth, consider size: largest comes before smallest

    table.sort(self.entries, function(a, b)
        if a.type > b.type then return true end
        if a.type < b.type then return false end
        if a.bank ~= nil and b.bank == nil then return true end
        if a.bank == nil and b.bank ~= nil then return false end
        if a.offset ~= nil and b.offset == nil then return true end
        if a.offset == nil and b.offset ~= nil then return false end
        if a.align ~= nil and b.align == nil then return true end
        if a.align == nil and b.align ~= nil then return false end
        return #a.data > #b.data
    end)

    for i, entry in pairs(self.entries) do
        if not try_place_entry(banks, entry) then
            error("could not allocate: " .. get_entry_name(entry))
        end
    end

    self.entries = {}
    self.fixed_entries = {}
    self.banks = banks
    self.bank_sizes = {}
    for i, v in pairs(self.banks) do
        self.bank_sizes[i] = calculate_bank_sizes(self.banks[i])
    end
end

return M
