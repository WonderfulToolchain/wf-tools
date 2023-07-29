-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local lapp = require('pl.lapp')
local pretty = require('pl.pretty')
local tablex = require('pl.tablex')
local wftempfile = require('wf.internal.tempfile')
local wfutil = require('wf.internal.util')

local args
temp_dir = wftempfile.create_directory(true)

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

local function has_subcommands(cmd)
    return cmd.arguments == nil
end

local program_name = wfutil.script_name()
local cmd = commands
local cmd_arg = arg
while cmd ~= nil and has_subcommands(cmd) and #cmd_arg > 0 and cmd[cmd_arg[1]] ~= nil do
    program_name = program_name .. " " .. cmd_arg[1]
    cmd = cmd[cmd_arg[1]]
    cmd_arg = tablex.sub(cmd_arg, 2)
end

local function list_subcommands(cmds, prefix)
    for k, v in tablex.sort(cmds) do
        if has_subcommands(v) then
            list_subcommands(v, prefix .. k .. " ")
        else
            io.stderr:write("\t" .. prefix .. k .. ": " .. v.description .. "\n")
        end
    end
end

if has_subcommands(cmd) then
    io.stderr:write(program_name .. ": ")
    if #cmd_arg < 1 then
        io.stderr:write("missing subcommand")
    else
        io.stderr:write("unknown subcommand: " .. cmd_arg[1])
    end
    io.stderr:write("\n\navailable subcommands:\n")
    list_subcommands(cmd, "")
else
    local cmd_arg_other = nil
    if cmd.argument_separator then
        cmd_arg, cmd_arg_other = args_split2(cmd_arg, cmd.argument_separator)
    end
    args = lapp(program_name .. " " .. cmd.arguments, cmd_arg)
    cmd.run(args, cmd_arg_other)
end
