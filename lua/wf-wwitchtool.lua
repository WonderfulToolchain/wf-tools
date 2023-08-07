#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

commands = {}
commands.mkfent = require('wf.internal.tool.wwitchtool.mkfent')
commands.project = require('wf.internal.tool.project')('wwitch')

require('wf.internal.tool')
