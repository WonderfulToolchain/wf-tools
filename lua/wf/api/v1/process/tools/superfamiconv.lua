-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- wf-superfamiconv tool wrapper.
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

local M = {}



return M
