-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local lapp = require('pl.lapp')
local tablex = require('pl.tablex')
local wftempfile = require('wf.internal.tempfile')
local wfutil = require('wf.internal.util')

local args
temp_dir = wftempfile.create_directory(false)

function print_verbose(...)
    if args.verbose then
        print(table.unpack({...}))
    end
end

function execute_verbose(cmd, arg)
    if args.verbose then
        return wfutil.execute(cmd, arg, wfutil.OUTPUT_SHELL)
    else
        return wfutil.execute(cmd, arg, wfutil.OUTPUT_NONE)
    end
end

local function args_split2(arg_table, sep)
    local sep_pos = tablex.find(arg_table, sep or "--")
    if sep_pos == nil then
        return arg_table, {}
    else
        return tablex.sub(arg_table, 1, sep_pos - 1), tablex.sub(arg_table, sep_pos + 1)
    end
end

if #arg < 1 or not commands[arg[1]] then
    io.stderr:write(wfutil.script_name() .. ": ")
    if #arg < 1 then
        io.stderr:write("missing subcommand")
    else
        io.stderr:write("unknown subcommand: " .. arg[1])
    end
    io.stderr:write("\n\navailable subcommands:\n")
    for k, v in tablex.sort(commands) do
        io.stderr:write("\t" .. k .. ": " .. v.description .. "\n")
    end
else
    local cmd = commands[arg[1]]
    local cmd_arg = tablex.sub(arg, 2)
    local cmd_arg_other = nil
    if cmd.argument_separator then
        cmd_arg, cmd_arg_other = args_split2(cmd_arg, cmd.argument_separator)
    end
    args = lapp(cmd.arguments, cmd_arg)
    cmd.run(args, cmd_arg_other)
end
