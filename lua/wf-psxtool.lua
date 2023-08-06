#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

commands = {}
commands.project = require('wf.internal.tool.project')('psx')
commands.build = {}
commands.build.exe = require('wf.internal.psxtool.buildexe')

require('wf.internal.tool')
