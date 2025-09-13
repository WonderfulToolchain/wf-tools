#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2024, 2025

commands = {}
commands["clean-caches"] = require('wf.internal.tool.config.clean_caches')
commands.env = require('wf.internal.tool.config.env')
commands.migrate = require('wf.internal.tool.config.migrate')
commands.repo = require('wf.internal.tool.config.repo')

require('wf.internal.tool')

