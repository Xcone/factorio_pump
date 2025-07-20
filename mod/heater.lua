local plib = require 'plib'
local xy = plib.xy
local assistant = require 'planner-assistant'
local priority_queue = require("priority-queue")
require "astar"

local function get_area_center(mod_context)
    local area_bounds = mod_context.area_bounds
    local area_center = {
        x = (area_bounds.left_top.x + area_bounds.right_bottom.x) / 2,
        y = (area_bounds.left_top.y + area_bounds.right_bottom.y) / 2
    }

    return area_center
end

local function group_entities_needing_heat(entities_needing_heat)
    local groups = {}
    local visited = {}

    -- Numbers are debug only. Group1 is not really a group, but rather the connections.
    local group_number = 2 

    -- Depth Firt Search to collect touching entities
    local function collect_group(position, group)
        xy.set(visited, position, true)

        local start_entity = xy.get(entities_needing_heat, position)
        table.insert(group.entities_needing_heat, start_entity)

        xy.each(entities_needing_heat, function(other_entity_needing_heat, other_position)
            if not xy.get(visited, other_position) and plib.bounding_box.are_touching(start_entity.heatpipe_box, other_entity_needing_heat.heatpipe_box) then
                collect_group(other_position, group)
            end
        end)
    end

    -- Build groups
    xy.each(entities_needing_heat, function(entity_needing_heat, position)
        if not xy.get(visited, position) then
            local group_key = 'group' .. group_number
            local group = {
                number = group_number,
                key = group_key,
                entities_needing_heat = {},
                connection_candidates = {},
                connection_points = {},      
                heatpipe_positions = {}          
            }
            group_number = group_number + 1
            collect_group(position, group)
            groups[group_key] = group
        end
    end)

    return groups;
end

local function find_nearest_group(position, entities_needing_heat, groups)
    local nearest_entity = plib.xy.nearest(entities_needing_heat, position).value

    for _, group in pairs(groups) do
        for _, entity_needing_heat in pairs(group.entities_needing_heat) do
            if entity_needing_heat == nearest_entity then
                return group
            end
        end
    end
end

local function find_closest_entities_between_groups(this_group, other_group)
    local best_pair = {
        distance = 99999,
        this_group_entity_needing_heat = nil,
        other_group_entity_needing_heat = nil,
        this_group_key = nil,
        other_group_key = nil,
    }

    for _, this_group_entity in pairs(this_group.entities_needing_heat) do
        for _, other_group_entity in pairs(other_group.entities_needing_heat) do
           local distance = plib.position.taxicab_distance(this_group_entity.position, other_group_entity.position)

           if best_pair.distance > distance then
                best_pair = {
                    distance = distance,
                    this_group_entity_needing_heat = this_group_entity,
                    other_group_entity_needing_heat = other_group_entity,
                    this_group_key = this_group.key,
                    other_group_key = other_group.key
                }
           end
        end
    end

    return best_pair;
end

local function add_group_connection_candidates(groups)
    for _, this_group in pairs(groups) do
        for _, other_group in pairs(groups) do
            if this_group.key == other_group.key then 
                goto skip_connect_to_self 
            end

            if this_group.connection_candidates[other_group.key] and other_group.connection_candidates[this_group.key] then
                 goto already_established 
            end

            -- Information how this group would connect to other group
            local nearest_entities = find_closest_entities_between_groups(this_group, other_group)
            this_group.connection_candidates[ other_group.key] = nearest_entities;

            -- Invert it, so it discribes how other group connects to this group
            local inverse_nearest_entities = {
                distance = nearest_entities.distance,
                this_group_entity_needing_heat = nearest_entities.other_group_entity_needing_heat,
                other_group_entity_needing_heat = nearest_entities.this_group_entity_needing_heat,
                other_group_key = this_group.key,
                this_group_key = other_group.key
            }
            other_group.connection_candidates[this_group.key] = inverse_nearest_entities;            

            ::skip_connect_to_self::
            ::already_established::
        end
    end
end

local function plan_heat_pipe(mod_context, position, placement_order)
    assistant.add_heat_pipe(mod_context.construction_plan, position)
    xy.set(mod_context.blocked_positions, position, true)    
    xy.get(mod_context.construction_plan, position).placement_order = placement_order
end

local function connect_groups(groups, center_group, mod_context)
    local connected_groups = {[center_group.key] = center_group}
    local unconnected_groups = {}
    for _, group in pairs(groups) do
        if group ~= center_group then
            unconnected_groups[group.key] = group
        end
    end

    local area_center = get_area_center(mod_context)

    local function find_next_connection()
        local best_candidate = nil
        for _, connected_group in pairs(connected_groups) do
            for _, unconnected_group in pairs(unconnected_groups) do
                local candidate = connected_group.connection_candidates[unconnected_group.key]

                if best_candidate == nil then
                    best_candidate = candidate
                else
                    if candidate.distance < best_candidate.distance then
                        best_candidate = candidate
                    else 
                        -- if the distance between candidates is the same; prefer the connection closer to the center of the map
                        if candidate.distance == best_candidate.distance then
                            local best_candidate_distance_to_center = plib.position.taxicab_distance(best_candidate.this_group_entity_needing_heat.position, area_center)
                            local candidate_distance_to_center = plib.position.taxicab_distance(candidate.this_group_entity_needing_heat.position, area_center)

                            if candidate_distance_to_center < best_candidate_distance_to_center then 
                                best_candidate = candidate
                            end  
                        end                      
                    end
                end                
            end       
        end
        return best_candidate
    end

    local function mark_connected(group)
        unconnected_groups[group.key] = nil
        connected_groups[group.key] = group
    end

    local function get_heatpipe_positions(entity)
        local positions = {}
        plib.bounding_box.each_edge_position(entity.heatpipe_box, function(position)
            table.insert(positions, position)
        end)
        return positions
    end

    local connection_number = 50

    local connections = {}

    while next(unconnected_groups) do
        local best_candidate = find_next_connection()       

        local connected_group = connected_groups[best_candidate.this_group_key]
        local unconnected_group = unconnected_groups[best_candidate.other_group_key]

        local start_entity = best_candidate.this_group_entity_needing_heat
        local end_entity = best_candidate.other_group_entity_needing_heat

        local start_positions = get_heatpipe_positions(start_entity)
        local end_positions = get_heatpipe_positions(end_entity)

        local path = astar(start_positions, end_positions, mod_context.area_bounds, mod_context.blocked_positions)
        if path then
            local pathEnd = path.position
            local pathStart = path.position         
            local connection = {
                groupA = connected_group.key,
                groupB = unconnected_group.key,
                heatpipe_positions = {}
            }

            table.insert(connections, connection)

            while path do      
                xy.set(connection.heatpipe_positions, path.position, true)                      
                pathStart = path.position
                path = path.parent
            end

            table.insert(connected_group.connection_points, {
                position = pathStart,
                other_group_key = unconnected_group.key,
                other_group_position = pathEnd,
                connection = connection
            })

            table.insert(unconnected_group.connection_points, {
                position = pathEnd,
                other_group_key = connected_group.key,
                other_group_position = pathStart,
                connection = connection
            })
        end

        connection_number = connection_number + 1
        mark_connected(unconnected_group)
    end

    return connections
end

local function connect_connections_within_group(mod_context, group, groups, primary_connection_position, depth)
    local pending_connections = {}

    if depth > 10 then 
        mod_context.failure = {"failure.too-many-heatpipe-groups"}
        return
    end

    for _, connection in pairs(group.connection_points) do
        xy.set(group.heatpipe_positions, connection.position)

        if plib.position.are_equal(connection.position, primary_connection_position) then            
            connection.attached_within_group = true            
        else
            pending_connections[connection.other_group_key] = connection
        end        
    end    

    -- We want to prioritize a path that passes past entities, which will be the whitelisted positions
    local preferred_heatpipe_positions = {}
    for _, entity_needing_heat in pairs(group.entities_needing_heat) do
        plib.bounding_box.each_edge_position(entity_needing_heat.heatpipe_box, function(position)            
            if not assistant.is_position_blocked(mod_context.blocked_positions, position) then                
                xy.set(preferred_heatpipe_positions, position, true)
            end
        end)
    end

    local function astar_preferred_positions(starts, ends)
        local function is_shortcut(position)
            return xy.get(group.heatpipe_positions, position)
        end

        local function penalize_non_preferred_positions(parent_node, node) 
            if not xy.get(preferred_heatpipe_positions, node.position) then
                -- Penalise positions that don't heat anything
                return 2
            end
                
            return 0
        end

        return astar(starts, ends, mod_context.area_bounds, mod_context.blocked_positions, 100, penalize_non_preferred_positions, is_shortcut)
    end

    local connection_queue = priority_queue();
    for _, connection in pairs(pending_connections) do   
        local distance = plib.position.taxicab_distance(primary_connection_position, connection.position)
        connection_queue:put( connection, 1000 - distance )
    end

    while not connection_queue:empty() do
        local connection = connection_queue:pop()
        local path = astar_preferred_positions({connection.position}, {primary_connection_position})
        if not path then  
            assistant.add_warning(mod_context, connection.position, "warning.building-group-not-heated")
        end

        while(path) do    
            xy.set(group.heatpipe_positions, path.position, 2)           
            path = path.parent
        end

        connect_connections_within_group(mod_context, groups[connection.other_group_key], groups, connection.other_group_position, depth + 1)
    end

    local entities_queue = priority_queue();
    for _, entity_needing_heat in pairs(group.entities_needing_heat) do   
        local distance = plib.position.taxicab_distance(primary_connection_position, entity_needing_heat.position)
        entities_queue:put( entity_needing_heat, 1000 - distance )
    end

    while not entities_queue:empty() do
        local entity_needing_heat = entities_queue:pop()
        local start_positions = {}
        local already_heated = false        

        plib.bounding_box.each_edge_position(entity_needing_heat.heatpipe_box, function(position)
            if xy.get(group.heatpipe_positions, position) then
                already_heated = true                
            end            
            table.insert(start_positions, position)            
        end)

        if not already_heated then
            local path = astar_preferred_positions(start_positions, {primary_connection_position})
        
            if not path then   
                assistant.add_warning(mod_context, entity_needing_heat.position, "warning.building-not-heated")                         
            end

            while(path) do    
                if not xy.get(group.heatpipe_positions, path.position)  then
                    xy.set(group.heatpipe_positions, path.position, 3)           
                end
                path = path.parent
            end
        end
    end
end
    

function plan_heat_pipes(mod_context)
    local entities_needing_heat = {}

    xy.each(mod_context.construction_plan, function(entity, entity_position)
        if entity.name ~= "power_pole" then
            local entity_box = assistant.get_planned_entity_bounding_box(mod_context, entity_position)
            local heatpipe_box = plib.bounding_box.copy(entity_box)
            plib.bounding_box.grow(heatpipe_box, 1)

            local entity_needing_heat = {
                entity_box = entity_box,
                heatpipe_box = heatpipe_box,
                position = entity_position
            }

            xy.set(entities_needing_heat, entity_position, entity_needing_heat)
        end
    end)
    
    -- Bundle entities in groups for which the the heatpipes would overlap or touch if the entities were encircled with heatpipes.
    local groups = group_entities_needing_heat(entities_needing_heat)

    -- For each group, find for each other group which entity combination would make those groups the closest
    add_group_connection_candidates(groups)

    -- Find the group closest to the area_center. We'll branch out to other groups from here.
    local area_center = get_area_center(mod_context)
    local center_group = find_nearest_group(area_center, entities_needing_heat, groups);

    -- Use the earlier established connection-candidates, as well as the center group, to find the connection we really want to make.
    -- The actual made connections are also added to the groups.
    local connections = connect_groups(groups, center_group, mod_context)

    -- The connection used to connect back to the center is the primary connection.
    -- For the center group there's no really a preference which connection is treated as the primary one.
    local _, any_connnection = next(center_group.connection_points)
    if any_connnection then        
        local other_group = groups[any_connnection.other_group_key]
        local other_group_position = any_connnection.other_group_position

        connect_connections_within_group(mod_context, center_group, groups, any_connnection.position, 0)
        connect_connections_within_group(mod_context, other_group, groups, other_group_position, 0)
    else
        local _, any_entity = next(center_group.entities_needing_heat)
        local best_position = nil
        local best_distance = 999999
        plib.bounding_box.each_edge_position(any_entity.heatpipe_box, function(position)
            if not assistant.is_position_blocked(mod_context.blocked_positions, position) then
                local distance = plib.position.taxicab_distance(position, area_center)
                if distance < best_distance then
                    best_position = position
                    best_distance = distance
                end
            end
        end)

        if best_position then        
            connect_connections_within_group(mod_context, center_group, groups, best_position, 0)
        end
    end
    
    for _, group in pairs(groups) do        
        xy.each(group.heatpipe_positions, function(placement_order, position)
            plan_heat_pipe(mod_context, position, placement_order)
        end)
    end

    for _, connection in pairs(connections) do        
        xy.each(connection.heatpipe_positions, function(_, position)
            plan_heat_pipe(mod_context, position, 1)
        end)
    end

    return mod_context.failure
end

return {
    plan_heat_pipes = plan_heat_pipes
}
