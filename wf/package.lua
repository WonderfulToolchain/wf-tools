local stringx = require("pl.stringx")
local wfpath = require("wf.path")
local wfutil = require("wf.util")
local M = {}

local function installed(name)
    local success = wfutil.execute(
        wfpath.executable("wf-pacman"), {"-Qs", name},
        wfutil.OUTPUT_NONE
    )
    return success
end
M.installed = installed

local function version(name)
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
M.version = version

local function files(name)
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
M.files = files

local function file_owner(path)
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
M.file_owner = file_owner

return M