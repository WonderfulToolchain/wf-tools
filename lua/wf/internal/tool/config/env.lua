-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local compat = require("pl.compat")
local dir = require("pl.dir")
local path = require("pl.path")
local stringx = require("pl.stringx")
local tablex = require('pl.tablex')
local wflog = require("wf.internal.log")
local wfpackage = require("wf.internal.package")
local wfpath = require("wf.internal.path")
local wfutil = require("wf.internal.util")

local env_path_separator = ":"
if compat.is_windows then env_path_separator = ";" end

local TYPE_STRING = "string"
local TYPE_PATH = "path"
local TYPE_LIST = "list"

local function env_set(name, value, type, suffix)
    -- FIXME: On MSYS2, we receive Windows paths, but should be outputting Unix paths.
    if compat.is_windows then
        if type == TYPE_PATH then
            local success, code, stdout = wfutil.execute("cygpath", {value}, wfutil.OUTPUT_CAPTURE)
            value = stringx.strip(stdout)
        elseif type == TYPE_LIST then
            local success, code, stdout = wfutil.execute("cygpath", {"-p", value}, wfutil.OUTPUT_CAPTURE)
            value = stringx.strip(stdout)
        end
    end
    if suffix then
        wflog.info("setting " .. name .. " = \"" .. value .. suffix .. "\"")
        print("export " .. name .. "='" .. value .. "'" .. suffix)
    else
        wflog.info("setting " .. name .. " = \"" .. value .. "\"")
        print("export " .. name .. "='" .. value .. "'")
    end
end

local function env_add_subpaths(paths, parent, bindir)
    if path.exists(parent) then
        for _, subdir in pairs(dir.getdirectories(parent)) do
            table.insert(paths, path.join(parent, subdir, bindir))
        end
    end
    return paths
end

local function env_run(args)
    wflog.verbose = args.verbose

    env_set("WONDERFUL_TOOLCHAIN", wfpath.base, TYPE_PATH)
    local paths = {path.join(wfpath.base, "bin")}

    if args.all then
        paths = env_add_subpaths(paths, path.join(wfpath.base, "toolchain"), "bin")
    end

    if args.independent then
        env_set("PATH", stringx.join(env_path_separator, paths), TYPE_LIST, env_path_separator .. "$PATH")
    else
        new_paths = tablex.makeset(paths)
        for _, p in pairs(stringx.split(os.getenv("PATH"), env_path_separator)) do
            if not new_paths[p] then
                table.insert(paths, p)
            end
        end
        env_set("PATH", stringx.join(env_path_separator, paths), TYPE_LIST)
    end

    if wfpackage.installed("blocksds-toolchain") then
        env_set("BLOCKSDS", path.join(wfpath.base, "thirdparty", "blocksds", "core"), TYPE_PATH)
        env_set("BLOCKSDSEXT", path.join(wfpath.base, "thirdparty", "blocksds", "external"), TYPE_PATH)
    end
end

return {
    ["generate"] = {
        ["arguments"] = [[
...: generate script to set environment variables

  -a,--all                         Add all toolchains to PATH.
  -i,--independent                 Avoid overwriting contents of existing
                                   environment variables.
  -v,--verbose                     Enable verbose logging.
]],
        ["description"] = "generate script to set environment variables",
        ["run"] = env_run
    }
}
