#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

commands = {}
commands.mkfent = require('wf.internal.tool.wwitchtool.mkfent')
commands.mkrom = require('wf.internal.tool.wwitchtool.mkrom')
commands.project = require('wf.internal.tool.project')('wwitch')
commands.usage = require('wf.internal.tool.usage.main')('wwitch')

require('wf.internal.tool')
