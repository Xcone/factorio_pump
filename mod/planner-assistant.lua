require 'util'
local math2d = require 'math2d'
local plib = require 'plib'
local xy = plib.xy

local assistant = {}

assistant.add_warning = function(mod_context, position, message)
    table.insert(mod_context.warnings, {
        position = position,
        message = message
    })
end

assistant.is_position_blocked = function(blocked_positions, position)
    return xy.get(blocked_positions, position)
end

assistant.is_area_blocked = function(blocked_positions, bounding_box)
    return plib.bounding_box.any_grid_position(bounding_box, function(position) 
        return xy.get(blocked_positions, position)
    end)
end

assistant.find_in_construction_plan = function(construction_plan, search_for_name)
    return xy.where(construction_plan, function(candidate)
        return candidate.name == search_for_name
    end)
end

assistant.find_oilwells = function(segment)
    local oilwells = {}

    plib.bounding_box.each_grid_position(segment.area_bounds, function(position)
        if xy.get(segment.area, position) == "oil-well" then
            table.insert(oilwells, {
                position = position
            })
        end
    end)

    return oilwells
end

assistant.add_extractor = function(construct_entities, position, direction)
    xy.set(construct_entities, position, {
        name = "extractor",
        direction = direction
    })
end

assistant.add_connector = function(construct_entities, position)
    xy.set(construct_entities, position, {
        name = "pipe",
        direction = defines.direction.east
    })
end

assistant.add_connector_joint = function(construct_entities, position)
    xy.set(construct_entities, position, {
        name = "pipe_joint",
        direction = defines.direction.east
    })
end

assistant.add_output = function(construct_entities, position, direction)
    xy.set(construct_entities, position, {
        name = "output",
        direction = direction
    })
end

assistant.add_pipe_tunnel = function(construct_entities, start_position, end_position, toolbox)
    local start_direction
    local end_direction
    local diff = 100

    if start_position.x == end_position.x then
        diff = start_position.y - end_position.y

        if start_position.y < end_position.y then
            end_direction = defines.direction.south
            start_direction = defines.direction.north
        else
            start_direction = defines.direction.south
            end_direction = defines.direction.north
        end
    else
        diff = start_position.x - end_position.x

        if start_position.x < end_position.x then
            start_direction = defines.direction.west
            end_direction = defines.direction.east
        else
            start_direction = defines.direction.east
            end_direction = defines.direction.west
        end
    end

    diff = math.abs(diff)
    -- rationale: distance measurement is zero-based. So if the underground distance=3, the difference should be
    -- max 4 (and not 5! as with reported bug), to account underground entrances. Schematically:
    --
    --   \ _ _ _ /
    -- x=0 1 2 3 4
    --
    -- Therefor: 4-0 = 4, and not 5 as was assumed when the bug occurred
    if diff > toolbox.connector.underground_distance_max + 1 then
        error("Underground distance too far")

        -- it also has to be far enough apart to be able to place the entrance and the exit
        --
        --   \ /
        -- x=0 1
    elseif diff == 0 then
        error("Underground exit and entrance on same position ")
    end

    xy.set(construct_entities, start_position, {
        name = "pipe_tunnel",
        direction = start_direction
    })

    xy.set(construct_entities, end_position, {
        name = "pipe_tunnel",
        direction = end_direction
    })
end

assistant.take_series_of_pipes = function(construct_entities, start_joint_position, direction)
    local probe_location = math2d.position.ensure_xy(start_joint_position)
    local pipe_positions = {}
    local tunnel_positions = {}
    local construct_entity_at_position = nil
    local is_tunneling = false
    local tunnel_start_direction = plib.directions[direction].opposite
    local tunnel_end_direction = direction
    local vector = plib.directions[direction].vector
    local keep_searching = true

    local iterations = 0

    repeat
        probe_location = plib.position.add(probe_location, vector)
        construct_entity_at_position = xy.get(construct_entities, probe_location)
        keep_searching = false
        if construct_entity_at_position then
            if construct_entity_at_position.name == "pipe" then
                table.insert(pipe_positions, probe_location)
                keep_searching = true
            else
                if construct_entity_at_position.name == "pipe_tunnel" then
                    if not is_tunneling then
                        if construct_entity_at_position.direction == tunnel_start_direction then
                            -- tunnel started
                            is_tunneling = true
                            keep_searching = true
                            table.insert(tunnel_positions, {
                                position = probe_location,
                                direction = construct_entity_at_position.direction
                            })
                        end
                    else
                        if construct_entity_at_position.direction == tunnel_end_direction then
                            -- tunnel ended
                            is_tunneling = false
                            keep_searching = true
                            table.insert(tunnel_positions, {
                                position = probe_location,
                                direction = construct_entity_at_position.direction
                            })
                        end
                    end
                else
                    -- Could be reservation for pump?
                    keep_searching = is_tunneling
                end
            end
        else
            keep_searching = is_tunneling
        end

        iterations = iterations + 1
    until (not keep_searching) or iterations > 99

    if #tunnel_positions % 2 > 0 then
        pump_log("From")
        pump_log(start_joint_position)
        pump_log("To")
        pump_log(probe_location)
        pump_log(tunnel_positions)

        error("Unexpected uneven number of tunnel pieces")
    end

    return {
        last_hit = construct_entity_at_position,
        last_hit_position = probe_location,
        pipe_positions = pipe_positions,
        tunnel_positions = tunnel_positions
    }
end

assistant.remove_pipes = function(construct_entities, pipe_positions)
    for i, pipe_position in pairs(pipe_positions) do
        construct_entities[pipe_position.x][pipe_position.y] = nil
    end
end

local function convert_outputs_to_joints_when_flanked(construction_plan)
    local output_positions = assistant.find_in_construction_plan(construction_plan, "output")

    xy.each(output_positions, function(output, position)
        local flank_direction = plib.directions[output.direction].next
        local flank_position = math2d.position.add(position, plib.directions[flank_direction].vector)

        local entity_on_flank = nil
        if construction_plan[flank_position.x] ~= nil then
            entity_on_flank = construction_plan[flank_position.x][flank_position.y]

            if entity_on_flank == nil then
                flank_direction = plib.directions[output.direction].previous
                flank_position = math2d.position.add(position, plib.directions[flank_direction].vector)

                if construction_plan[flank_position.x] ~= nil then
                    entity_on_flank = construction_plan[flank_position.x][flank_position.y]
                end
            end
        end

        if entity_on_flank ~= nil then
            xy.get(construction_plan, position).name = "pipe_joint"
        end
    end)
end

local try_replace_pipes_with_tunnels = function(construction_plan, pipe_positions, tunnel_positions, toolbox)
    local tunnel_length_min = toolbox.connector.underground_distance_min + 2
    local tunnel_length_max = toolbox.connector.underground_distance_max + 1

    if toolbox.pipe_bury_distance_preference > tunnel_length_min then
        tunnel_length_min = toolbox.pipe_bury_distance_preference
    end

    local tunnels = {}
    local tunnel_start = nil

    -- Merge existing tunnels
    for i, pipe_tunnel in pairs(tunnel_positions) do
        if tunnel_start ~= nil then
            table.insert(tunnels, {
                down = tunnel_start,
                up = pipe_tunnel
            })
            tunnel_start = nil
        else
            tunnel_start = pipe_tunnel
        end
    end

    local previous_tunnel
    for i, tunnel in pairs(tunnels) do
        if not previous_tunnel then
            previous_tunnel = tunnel
        else
            if math2d.position.distance(previous_tunnel.down.position, tunnel.up.position) <= tunnel_length_max then
                xy.remove(construction_plan, previous_tunnel.up.position)
                xy.remove(construction_plan, tunnel.down.position)
                previous_tunnel.up = tunnel.up
                tunnels[i] = nil
            else
                previous_tunnel = tunnel
            end
        end
    end

    -- Extend existing tunnels
    local pipe_xy = {}
    for _, position in pairs(pipe_positions) do
        xy.set(pipe_xy, position, true)
    end

    local move_tunnel_piece = function(pipe_position, tunnel_piece)
        xy.remove(pipe_xy, pipe_position)
        local planned_tunnel_piece = xy.get(construction_plan, tunnel_piece.position)
        xy.set(construction_plan, pipe_position, planned_tunnel_piece)
        xy.remove(construction_plan, tunnel_piece.position)
        tunnel_piece.position = pipe_position
    end

    for _, tunnel in pairs(tunnels) do
        local direction_before_down = tunnel.down.direction
        local direction_after_up = tunnel.up.direction
        local vector_before_down = plib.directions[direction_before_down].vector
        local vector_after_up = plib.directions[direction_after_up].vector
        local tunnel_length = math2d.position.distance(tunnel.down.position, tunnel.up.position)

        repeat
            local took_pipe = false
            local position_before_tunnel = plib.position.add(tunnel.down.position, vector_before_down)
            local pipe_before_tunnel = xy.get(pipe_xy, position_before_tunnel)

            if pipe_before_tunnel ~= nil and tunnel_length < tunnel_length_max then
                took_pipe = true
                tunnel_length = tunnel_length + 1
                move_tunnel_piece(position_before_tunnel, tunnel.down)
            end
        until not took_pipe

        repeat
            local took_pipe = false
            local position_after_tunnel = plib.position.add(tunnel.up.position, vector_after_up)
            local pipe_before_tunnel = xy.get(pipe_xy, position_after_tunnel)

            if pipe_before_tunnel ~= nil and tunnel_length < tunnel_length_max then
                took_pipe = true
                tunnel_length = tunnel_length + 1
                move_tunnel_piece(position_after_tunnel, tunnel.up)
            end
        until not took_pipe
    end

    -- TODO:
    -- Determine stretches of above-ground pipes that remaing after the tunneling was optimized

    -- If there's remaining pipe-pieces, turn those into tunnels, too
    if #tunnel_positions == 0 then
        -- Make tunnels
        while #pipe_positions >= tunnel_length_min do
            local pipe_positions_this_batch = {}
            local take_until = #pipe_positions - tunnel_length_max
            if take_until < 1 then
                take_until = 1
            end

            for i = #pipe_positions, take_until, -1 do
                table.insert(pipe_positions_this_batch, pipe_positions[i])
                pipe_positions[i] = nil
            end

            assistant.remove_pipes(construction_plan, pipe_positions_this_batch)

            local first_pipe = pipe_positions_this_batch[1]
            local last_pipe = pipe_positions_this_batch[#pipe_positions_this_batch]

            assistant.add_pipe_tunnel(construction_plan, first_pipe, last_pipe, toolbox)
        end
    end
end

assistant.create_tunnels_between_joints = function(construction_plan, toolbox)
    convert_outputs_to_joints_when_flanked(construction_plan)
    local pipe_joint_positions = assistant.find_in_construction_plan(construction_plan, "pipe_joint")

    xy.each(pipe_joint_positions, function(pipe_joint, position)
        for direction, toolbox_direction in pairs(plib.directions) do
            local result = assistant.take_series_of_pipes(construction_plan, position, direction)
            if result.last_hit == nil then
                -- Skip dead ends until all tunnels are placed
            elseif result.last_hit.name == "output" then
                if result.last_hit.direction == direction or result.last_hit.direction == toolbox_direction.opposite then
                    table.insert(result.pipe_positions, result.last_hit_position)
                end
                try_replace_pipes_with_tunnels(construction_plan, result.pipe_positions, result.tunnel_positions, toolbox)
            elseif result.last_hit.name == "pipe_joint" then
                try_replace_pipes_with_tunnels(construction_plan, result.pipe_positions, result.tunnel_positions, toolbox)
            end
        end
    end)
end

assistant.surface_has_meltable_tiles = function(player)
    return player.surface.planet and player.surface.planet.prototype.entities_require_heating
end

assistant.add_beacon = function(construct_entities, position)
    xy.set(construct_entities, position, {
        name = "beacon",
        direction = defines.direction.north
    })
end

assistant.use_module_inserter_ex = function (player)
    local setting = player.mod_settings["pump-interface-with-module-inserter-mod"]
    if setting and setting.value and remote.interfaces["ModuleInserterEx"] then
        return true
    end
    return false
end

return assistant
