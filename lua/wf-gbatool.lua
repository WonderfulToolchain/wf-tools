#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

commands = {}
commands.fix = require('wf.internal.tool.gbatool.fix')
commands.project = require('wf.internal.tool.project')('gba')

require('wf.internal.tool')
