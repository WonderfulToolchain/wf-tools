-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local dir = require("pl.dir")
local path = require("pl.path")
local stringx = require("pl.stringx")
local wflog = require("wf.internal.log")
local wfpackage = require("wf.internal.package")
local wfpath = require('wf.internal.path')
local tablex = require('pl.tablex')

local function env_set(name, value)
    wflog.info("setting " .. name .. " = \"" .. value .. "\"")
    print("export " .. name .. "='" .. value .. "'")
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

    env_set("WONDERFUL_TOOLCHAIN", wfpath.base)
    local paths = {path.join(wfpath.base, "bin")}

    if args.all then
        paths = env_add_subpaths(paths, path.join(wfpath.base, "toolchain"), "bin")
    end

    new_paths = tablex.makeset(paths)
    for _, p in pairs(stringx.split(os.getenv("PATH"), ":")) do
        if not new_paths[p] then
            table.insert(paths, p)
        end
    end
    env_set("PATH", stringx.join(":", paths))

    if wfpackage.installed("blocksds-toolchain") then
        env_set("BLOCKSDS", path.join(wfpath.base, "thirdparty", "blocksds", "core"))
        env_set("BLOCKSDSEXT", path.join(wfpath.base, "thirdparty", "blocksds", "external"))
    end
end

return {
    ["generate"] = {
        ["arguments"] = [[
    ...: generate script to set environment variables

    -a,--all                         Add all toolchains to PATH.
    -v,--verbose                     Enable verbose logging.
    ]],
        ["description"] = "generate script to set environment variables",
        ["run"] = env_run
    }
}
