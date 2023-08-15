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

function Bank:largest_gap(eoffset_min, eoffset_max)
    eoffset_min = eoffset_min or 0
    eoffset_max = eoffset_max or self.size - 1
    if not self:is_empty() then
        return eoffset_min, eoffset_max + 1
    else
        local previous = self.entries[1]
        local gap_start = math.max(eoffset_min, 0)
        local gap_size = previous.offset - eoffset_min

        for i=2,#self.entries do
            local current = self.entries[i]

            local current_gap_start = math.max(eoffset_min, previous.offset + #previous.data)
            local current_gap_end = math.min(math.min(eoffset_max, self.size), current.offset)

            local current_gap = current_gap_end - current_gap_start
            if current_gap > 0 and current_gap > gap_size then
                gap_start = current_gap_start
                gap_size = current_gap
            end

            previous = current
        end

        local current_gap_start = math.max(eoffset_min, previous.offset + #previous.data)
        local current_gap_end = math.min(eoffset_max, self.size)

        local current_gap = current_gap_end - current_gap_start
        if current_gap > 0 and current_gap > gap_size then
            gap_start = current_gap_start
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
        -- TODO: Merge adjacent entries.
        local eoffset_min = 0
        local eoffset_max = self.size
        if entry.offset ~= nil then
            if type(entry.offset) == "table" then
                eoffset_min = math.max(eoffset_min, entry.offset[1])
                eoffset_max = math.min(eoffset_max, entry.offset[2] + 1)
            else
                eoffset_min = entry.offset
                eoffset_max = entry.offset + #entry.data
            end
        end

        local previous = self.entries[1]

        local gap_start = eoffset_min
        local gap_end = math.min(math.min(eoffset_max, self.size), previous.offset)

        local gap = gap_end - gap_start
        if gap >= #entry.data then
            local eoffset = calc_eoffset(gap_start, gap_end, #entry.data, self.descending, entry.align)
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

            gap_start = math.max(eoffset_min, previous.offset + #previous.data)
            gap_end = math.min(math.min(eoffset_max, self.size), current.offset)

            gap = gap_end - gap_start
            if gap >= #entry.data then
                local eoffset = calc_eoffset(gap_start, gap_end, #entry.data, self.descending, entry.align)
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

        gap_start = math.max(eoffset_min, previous.offset + #previous.data)
        gap_end = math.min(eoffset_max, self.size)

        gap = gap_end - gap_start
        if gap >= #entry.data then
            local eoffset = calc_eoffset(gap_start, gap_end, #entry.data, self.descending, entry.align)
            if eoffset ~= nil then
                if not simulate then
                    entry.offset = eoffset
                    table.insert(self.entries, entry)
                end
                return true, eoffset
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
-- * offset: offset in physical bank to add to; can be a value or a range
-- * align: alignment
function Allocator:add(entry)
    if entry.offset ~= nil and type(entry.offset) == "number" then
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
            if bank.descending then
                limit = ((entry.bank & 0x0F) - 4) + 1
            else
                limit = (15 - (entry.bank & 0x0F)) + 1
            end
        elseif entry.type == -1 then
            limit = 2
        else
            limit = 1
        end
    end

    if limit == nil or limit > 1 then
        -- Split across multiple banks.

        local start_bank = entry.bank
        local end_bank = entry.bank
        local start_offset = 0
        local end_offset = bank.size - 1
        if bank.descending then
            end_offset = banks[end_bank]:allocation_start()
            local next_start_bank = entry.bank
            for i=start_bank-1,start_bank-(limit-1),-1 do
                next_start_bank = i
                if not banks[i]:is_empty() then
                    start_offset = banks[i]:allocation_end() + 1
                    break
                end
            end
            start_bank = next_start_bank
        else
            start_offset = banks[start_bank]:allocation_end() + 1
            local next_end_bank = entry.bank
            for i=start_bank+1,start_bank+(limit-1),-1 do
                next_end_bank = i
                if not banks[i]:is_empty() then
                    end_offset = banks[i]:allocation_start()
                    break
                end
            end
            end_bank = next_end_bank
        end
        if start_offset == bank.size then
            start_bank = start_bank + 1
            start_offset = 0
        end
        if entry.offset ~= nil then
            if type(entry.offset) == "table" then
                -- TODO: support descending alignment properly
                if start_offset > entry.offset[1] then
                    return false
                end
                start_offset = entry.offset[1]
            else
                if start_offset > entry.offset then
                    return false
                end
                start_offset = entry.offset
            end
        end

        local joined_linear_start = (start_bank * bank.size + start_offset)
        local joined_linear_end = (end_bank * bank.size + end_offset)
        local joined_size = joined_linear_end - joined_linear_start
        if joined_size < #entry.data then
            return false
        end

        if entry.offset == nil then
            joined_linear_start = calc_eoffset(joined_linear_start, joined_linear_end, #entry.data, bank.descending, entry.align)
        end
        joined_linear_end = joined_linear_start + #entry.data
        local joined_start_bank = joined_linear_start // bank.size
        local joined_start_offset = joined_linear_start % bank.size
        local joined_end_bank = (joined_linear_end - 1) // bank.size
        local joined_end_offset = (joined_linear_end - 1) % bank.size
        local bank_count = joined_end_bank + 1 - joined_start_bank

        if limit and bank_count > limit then
            return false
        end

        -- Split entry across multiple banks (simulation).
        -- TODO: Doing the :sub twice is probably a little slow, but cross-bank
        -- splitting should be rare.
        local sentry = tablex.deepcopy(entry)
        sentry.bank = joined_start_bank
        sentry.offset = joined_start_offset
        local pos = 1
        for i = 1,bank_count do
            sentry.data = entry.data:sub(pos, pos + bank.size - 1 - sentry.offset)
            if not banks[sentry.bank]:try_place(sentry, true) then
                return false
            end
            pos = pos + bank.size - sentry.offset
            sentry.bank = sentry.bank + 1
            sentry.offset = 0
        end

        -- Split entry across multiple banks (real placement).
        entry.bank = joined_start_bank
        entry.offset = joined_start_offset
        pos = 1
        local sentry = tablex.deepcopy(entry)
        for i = 1,bank_count do
            sentry.parent = entry
            sentry.parent_offset = pos - 1
            sentry.data = entry.data:sub(pos, pos + bank.size - 1 - sentry.offset)
            if not banks[sentry.bank]:try_place(sentry, false) then
                error("unexpected disagreement between simulation and real bank placement attempt")
            end
            if i ~= bank_count then
                pos = pos + bank.size - sentry.offset
                sentry = tablex.deepcopy(sentry)
                sentry.bank = sentry.bank + 1
                sentry.offset = 0
            end
        end

        return true
    end
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

local function copy_from_parent(entry)
    if entry.parent ~= nil and entry.parent_offset ~= nil then
        if entry.parent.parent ~= nil then
            copy_from_parent(entry.parent)
        end
        entry.data = entry.parent.data:sub(entry.parent_offset + 1, entry.parent_offset + #entry.data)
    end
end

local function get_offset_for_compare(offset)
    if offset == nil then return 2 end
    if type(offset) == "table" then return 1 end
    return 0
end

function Allocator:allocate(config, is_final)
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
    -- Fifth, consider emptiness: non-empty comes before empty
    -- Sixth, consider size: largest comes before smallest

    table.sort(self.entries, function(a, b)
        if a.type > b.type then return true end
        if a.type < b.type then return false end
        if a.bank ~= nil and b.bank == nil then return true end
        if a.bank == nil and b.bank ~= nil then return false end
        local a_offset = get_offset_for_compare(a.offset)
        local b_offset = get_offset_for_compare(b.offset)
        if a_offset < b_offset then return true end
        if a_offset > b_offset then return false end
        if a.align ~= nil and b.align == nil then return true end
        if a.align == nil and b.align ~= nil then return false end
        if not a.empty and b.empty then return true end
        if a.empty and not b.empty then return false end
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
    if is_final then
        for i, v in pairs(self.banks) do
            for j, bank in pairs(v) do
                for k, entry in pairs(bank.entries) do
                    copy_from_parent(entry)
                end
            end
        end
    end
end

return M
