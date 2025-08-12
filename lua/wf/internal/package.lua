-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

--- Package management/querying utilities.

local stringx = require("pl.stringx")
local wfpath = require("wf.internal.path")
local wfutil = require("wf.internal.util")
local M = {}

--- Check if a package is installed.
--- @param name string The name of the package.
--- @return boolean result True if the package is installed.
function M.installed(name)
    local success = wfutil.execute(
        wfpath.executable("wf-pacman"), {"-Qs", name},
        wfutil.OUTPUT_NONE
    )
    return success
end

--[[
function M.version(name)
    local success, code, stdout, stderr = wfutil.execute(
        wfpath.executable("wf-pacman"), {"-Q", name},
        wfutil.OUTPUT_CAPTURE
    )
    if success then
        return stringx.strip(stringx.split(stdout)[2])
    else
        return nil
    end
end
]]

--[[
function M.files(name)
    local success, code, stdout, stderr = wfutil.execute(
        wfpath.executable("wf-pacman"), {"-Fl", "--machinereadable", name},
        wfutil.OUTPUT_CAPTURE_BINARY
    )
    local list = {}
    if success then
        for line in string.gmatch(stdout,'[^\r\n]+') do
            local repository, package, package_version, file_path = table.unpack(stringx.split(line, string.char(0)))
            table.insert(list, stringx.rstrip(file_path))
        end
    end
    return list
end
]]

--[[
function M.file_owner(path)
    local success, code, stdout, stderr = wfutil.execute(
        wfpath.executable("wf-pacman"), {"-F", "--machinereadable", path},
        wfutil.OUTPUT_CAPTURE_BINARY
    )
    if success then
        local repository, package, package_version, file_path = table.unpack(stringx.split(stdout, string.char(0)))
        -- NOTE: file_path is not trimmed at this point
        return package, package_version
    else
        return nil, nil
    end
end
]]

return M
