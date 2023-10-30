-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

overlay_list = require("overlay_list")

local function validate(combinations, layer_count)
    local l = overlay_list.create(combinations)

    local function print_debug_info()
        print(require("pl.pretty").write(combinations))
        print(require("pl.pretty").write(l))
    end

    for _, v in pairs(combinations) do
        local layers_used = {}
        for _, node_name in pairs(v) do
            -- find layer on which a given node resides
            local found = false
            for layer_i, layer_v in pairs(l) do
                for _, layer_node in pairs(layer_v) do
                    if layer_node.name == node_name then
                        found = true
                        if layers_used[layer_i] ~= nil then
                            print_debug_info()
                            print(require("pl.pretty").write(v))
                            error("layer conflict for: " .. node_name .. " with " .. layers_used[layer_i])
                        end
                        layers_used[layer_i] = node_name
                        break
                    end
                end
            end
            if not found then
                print_debug_info()
                error("could not find node: " .. node_name)
            end
        end
    end

    if layer_count ~= nil and #l > layer_count then
        print_debug_info()
        error("too many layers: " .. #l .. " > " .. layer_count)
    end
end

validate({{"a"}, {"b"}, {"c"}}, 1)
validate({{"a", "b"}, {"b"}, {"c"}}, 2)
validate({{"a", "b", "c", "d", "e"}}, 5)
validate({{"b", "a", "c"}, {"a", "d"}, {"a", "e"}, {"a", "b", "g"}, {"f"}})
validate({{"b", "a", "c"}, {"a", "d", "e"}}, 3)
validate({{"b", "a", "c"}, {"a", "d", "e"}, {"a", "b", "d"}})
print("tests passed")
