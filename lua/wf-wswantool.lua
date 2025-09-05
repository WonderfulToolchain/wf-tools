#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

commands = {}
commands.build = require('wf.internal.tool.wswantool.elf2rom.main')
commands.project = require('wf.internal.tool.project')('wswan')
commands.usage = require('wf.internal.tool.usage')('wswan')

require('wf.internal.tool')
