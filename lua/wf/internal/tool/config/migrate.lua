-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2024

local wflog = require("wf.internal.log")
local wfpackage = require("wf.internal.package")
local cmd_repo = require("wf.internal.tool.config.repo")

local function migrate_run(args)
    wflog.verbose = args.verbose

    if wfpackage.installed("thirdparty-blocksds-toolchain") or wfpackage.installed("thirdparty-blocksds-git-toolchain") then
        wflog.info("old blocksds packages detected - ensuring blocksds repo is enabled...")
        cmd_repo["enable"]["run"]({["repo_name"]="blocksds"})
    end
end

return {
    ["arguments"] = [[
...: migrate configuration after wf-tools update

Usually launched automatically by the wf-tools post-install script.

  -v,--verbose                     Enable verbose logging.
]],
    ["description"] = "migrate configuration",
    ["run"] = migrate_run
}
