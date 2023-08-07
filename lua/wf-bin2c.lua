#!/opt/wonderful/bin/wf-lua
-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

local lfs = require('lfs')
local lapp = require('pl.lapp')
local path = require('pl.path')
local wfbin2c = require('wf.internal.bin2c')
local wfutil = require('wf.internal.util')

---- Utility functions

---- Program

local args = lapp [[
wf-bin2c: convert binary file to .c/.h file pair
  -a,--align      (optional number)   Data alignment.
  --address-space (optional string)   Address space (for wswan target).
  <output_dir>    (string)            Output directory.
  <input_file>    (string)            Input binary file (use '-' for stdin).
  <array_name>    (optional string)   Array name.
]]

--- open input file

if args.input_file == '-' then
  lfs.setmode(io.stdin, "binary")
  input_file = io.stdin
else
  input_file = lapp.open(args.input_file, "rb")
end

--- generate names

local array_name, output_path, output_path_ext
if args.array_name then
  array_name = args.array_name
  output_path = array_name
  output_path_ext = ""
else
  if args.input_file == '-' then
    lapp.error("must provide array name if reading from stdin")
  else
    array_name = path.splitext(path.basename(args.input_file))
    output_path, output_path_ext = path.splitext(path.basename(args.input_file))
  end
end
array_name = wfutil.to_c_identifier(array_name)

output_path = path.join(args.output_dir, output_path)
if #output_path_ext > 0 then
  output_path = output_path .. "_" .. output_path_ext:sub(2)
end

--- write files

local input_data = input_file:read("*all")
input_file:close()

local c_file <close> = lapp.open(output_path .. ".c", "w")
local h_file <close> = lapp.open(output_path .. ".h", "w")

wfbin2c.bin2c(c_file, h_file, "wf-bin2c", {
  [array_name] = {
    ["address_space"]=args.address_space,
    ["align"]=args.align,
    ["data"]=input_data
  }
})
