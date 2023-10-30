-- SPDX-License-Identifier: MIT
-- SPDX-FileContributor: Adrian "asie" Siekierka, 2023

-- @module wf.internal.overlay_list
-- @alias M

local M = {}

M.create = function(combinations)
    local nodes = {}
    local nodes_added = {}
    local nodes_to_add = {}
    local new_nodes_to_add = nil

    local function count_remaining_neighbors(node)
        local i = 0
        for _, node in pairs(node.connected) do
            if nodes_added[node.name] ~= true then
                i = i + 1
            end
        end
        return i
    end

    -- {A and B and C} or {D and E}
    for _, v in pairs(combinations) do
        for _, node_name in pairs(v) do
            if nodes[node_name] == nil then
                nodes[node_name] = {["name"]=node_name, ["connected"]={}}
                table.insert(nodes_to_add, nodes[node_name])
            end
        end
        for _, node_name in pairs(v) do
            for _, other_name in pairs(v) do
                if other_name ~= node_name then
                    nodes[node_name].connected[other_name] = nodes[other_name]
                end
            end    
        end
    end

    local all_lists = {}
    local curr_list = {}

    local function add_node(node, terminating)
        table.insert(curr_list, {
            ["name"] = node.name,
            ["terminating"] = terminating
        })
        nodes_added[node.name] = true
    end

    while #nodes_to_add > 0 do
        -- add all terminating nodes
        new_nodes_to_add = {}
        for i, node in pairs(nodes_to_add) do
            if count_remaining_neighbors(node) == 0 then
                add_node(node, true)
            else
                table.insert(new_nodes_to_add, node)
            end
        end
        nodes_to_add = new_nodes_to_add

        -- add all non-terminating nodes
        -- from largest to smallest, but without 
        if #nodes_to_add > 0 then
            local connected_nodes = {}
            local max_nodes_to_add = {}
            while true do
                local max_node = nil
                local max_node_i = nil
                local max_node_count = -1
                for i, node in pairs(nodes_to_add) do
                    local node_count = count_remaining_neighbors(node)
                    if node_count > 0 and node_count > max_node_count then
                        local conflicts = false
                        for node_name, _ in pairs(connected_nodes) do
                            if nodes_added[node_name] ~= true and node.connected[node_name] ~= nil then
                                conflicts = true
                                break
                            end
                        end
                        if not conflicts then
                            max_node = node
                            max_node_i = i
                            max_node_count = node_count
                        end
                    end
                end

                if max_node == nil then break end
                table.insert(max_nodes_to_add, max_node)
                connected_nodes[max_node.name] = true
                for i, node in pairs(max_node.connected) do
                    connected_nodes[node.name] = true
                end
                table.remove(nodes_to_add, max_node_i)
            end
            for _, max_node in pairs(max_nodes_to_add) do
                add_node(max_node, false)
            end
        end

        -- advance layer
        if #curr_list == 0 then
            error("infinite loop detected?")
        end
        table.insert(all_lists, curr_list)
        curr_list = {}
    end

    return all_lists
end

return M
