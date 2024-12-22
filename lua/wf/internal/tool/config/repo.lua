-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2024

local lfs = require("lfs")
local dir = require("pl.dir")
local path = require("pl.path")
local wflog = require("wf.internal.log")
local wfpath = require("wf.internal.path")

local tpl_loc = path.join(wfpath.base, "pacman", "config")
local cfg_loc = path.join(wfpath.base, "etc", "pacman.d")

local function repo_enable_run(args)
    wflog.verbose = args.verbose

    local found = false
    for _, loc in pairs(dir.getfiles(tpl_loc, "*-" .. args.repo_name .. ".conf")) do
        wflog.info("adding " .. loc)
        local dloc, floc = path.splitpath(loc)
        local dst_loc = path.join(cfg_loc, floc)
        if lfs.link(path.relpath(loc, cfg_loc), dst_loc, true) == nil then
            dir.copyfile(loc, dst_loc)
        end
        found = true
    end
    if not found then
        wflog.error("configuration files not found for repository \"" .. args.repo_name .. "\"")
    end
end

local function repo_disable_run(args)
    wflog.verbose = args.verbose

    local found = false
    local removed = false
    for _, loc in pairs(dir.getfiles(tpl_loc, "*-" .. args.repo_name .. ".conf")) do
        local dloc, floc = path.splitpath(loc)
        local loc_at_cfg = path.join(cfg_loc, floc)
        if path.exists(loc_at_cfg) then
            wflog.info("removing " .. loc_at_cfg)
            os.remove(loc_at_cfg)
            removed = true
        end
        found = true
    end
    if not found then
        wflog.error("configuration files not found for repository \"" .. args.repo_name .. "\"")
    elseif not removed then
        wflog.error("repository \"" .. args.repo_name .. "\" was not previously enabled")
    end
end

return {
    ["enable"] = {
        ["arguments"] = [[
...: enable specified repository

  <repo_name>   (string)           Input repository name.
  -v,--verbose                     Enable verbose logging.
]],
        ["description"] = "enable specified repository",
        ["run"] = repo_enable_run
    },
    ["disable"] = {
        ["arguments"] = [[
...: disable specified repository

  <repo_name>   (string)           Input repository name.
  -v,--verbose                     Enable verbose logging.
]],
        ["description"] = "disable specified repository",
        ["run"] = repo_disable_run
    }
}
