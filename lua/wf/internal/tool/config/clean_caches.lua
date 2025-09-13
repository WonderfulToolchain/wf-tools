-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2025

local lfs = require("lfs")
local dir = require("pl.dir")
local path = require("pl.path")
local stringx = require("pl.stringx")
local wflog = require("wf.internal.log")
local wfpath = require("wf.internal.path")
local wfterm = require("wf.internal.term")

local function env_run(args)
    wflog.verbose = args.verbose

    local cache_paths = {
        ["cached wf-pacman packages"] = path.join(path.join(wfpath.base, "pacman"), "cache")
    }

    for name,cpath in pairs(cache_paths) do
        local estimated_size = 0
        local has_files = false
        for _,file in pairs(dir.getallfiles(cpath)) do
            if path.isfile(file) then
                has_files = true
                estimated_size = estimated_size + path.getsize(file)
            end
        end

        if has_files then
            local estimated_size_str = string.format("%.1f MiB", estimated_size / (1024 * 1024))

            io.stdout:write("Remove " .. name .. " (" .. estimated_size_str .. " in " .. cpath .. ") [y/N]? ")
            io.stdout:flush()
            local result = string.lower(stringx.strip(io.read()))
            if result == "y" then
                print("Removing " .. name .. "...")
                dir.rmtree(cpath)
                lfs.mkdir(cpath)
            end
        else
            wflog.info("no " .. name .. " found")
        end
    end
end

return {
    ["arguments"] = [[
...: remove unused cache files

    -v,--verbose                     Enable verbose logging.
]],
    ["description"] = "remove unused cache files",
    ["run"] = env_run
}
