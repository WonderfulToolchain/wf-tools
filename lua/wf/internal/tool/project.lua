local dir = require('pl.dir')
local path = require('pl.path')
local stringx = require('pl.stringx')
local utils = require('pl.utils')
local wfpath = require('wf.internal.path')

local ide_update_paths = {
    ".clangd",
    ".vscode"
}

return function(target)
    local function get_template_path(args)
        local template_name = target
        if args.type ~= nil then
            template_name = template_name .. "-" .. args.type
        end
        local template_path = path.join(wfpath.base, "templates", template_name)
        if not path.exists(template_path) then
            error("template " .. template_name .. " does not exist")
        end
        return template_path
    end

    local function create_new_project(args)
        local project_name = args.name
        local template_path = get_template_path(args)

        print_verbose("copying template files")
        wfpath.copypath(template_path, args.directory)

        local makefile_path = path.join(args.directory, "Makefile")
        if path.exists(makefile_path) then
            print_verbose("patching Makefile")
            local makefile_data = utils.readfile(makefile_path, false)
            makefile_data = makefile_data:gsub("(NAME%s+:=%s+)example", "%1" .. project_name)
            utils.writefile(makefile_path, makefile_data, false)
        end
    end

    local function refresh_ide_project(args)
        local template_path = get_template_path(args)

        print_verbose("copying template files")
        wfpath.copypath(template_path, args.directory, function(name)
            for i,v in ipairs(ide_update_paths) do
                if stringx.startswith(name, v) then
                    return true
                end
            end
            return false
        end)
    end

    local project = {}
    project.new = {
        ["arguments"] = [[
<name> <directory> [args]: create a new project
  <name>        (string)           Project name.
  <directory>   (string)           Project directory.
  -t,--type     (optional string)  Project type.
  -v,--verbose                     Enable verbose logging.
]],
        ["description"] = "create a new project",
        ["run"] = create_new_project
    }
    project["update-ide"] = {
        ["arguments"] = [[
<directory>: update/overwrite IDE configuration
  <directory>   (string)           Project directory.
]],
        ["description"] = "update/overwrite IDE configuration",
        ["run"] = refresh_ide_project
    }
    return project
end
