#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

commands = {}
commands.fix = require('wf.internal.tool.gbatool.fix')
commands.link = require('wf.internal.tool.gbatool.link')
commands.project = require('wf.internal.tool.project')('gba')
commands.usage = require('wf.internal.tool.usage')('gba')

require('wf.internal.tool')
