require "planner"

script.on_event({defines.events.on_player_selected_area}, function(event)
    if event.item == 'pump-selection-tool' then
        process_selected_area_with_this_mod(event)
    end
end)

function process_selected_area_with_this_mod(event)
    local player = game.get_player(event.player_index)

    if #event.entities == 0 then
        player.print(
            "P.U.M.P. cannot place pumpjacks, because there are no oil wells found in selected area.")
        return
    end

    trim_event_area(event)

    if pipes_present_in_area(event.surface, event.area) then
        player.print(
            "P.U.M.P. cannot safely place pumpjacks and pipes, because there are other pipes present within the selected area.")
        return
    end

    local planner_input = prepare_planner_input(event)
    dump_to_file(planner_input, "planner_input")
    local construct_entities = plan(planner_input)
    dump_to_file(construct_entities, "construct_entities")

    for entity_name, entities_to_place in pairs(construct_entities) do
        for i, parameters in pairs(entities_to_place) do
            event.surface.create_entity {
                name = "entity-ghost",
                inner_name = entity_name,
                position = parameters.position,
                direction = parameters.direction,
                force = "player"
            }
        end
    end
end

function trim_event_area(event)
    local uninitialized = true
    local padding = 2 -- 1 for the size of the pump, 1 more for outgoing pipe

    for i, entity in pairs(event.entities) do
        if entity.position.x < event.area.left_top.x or uninitialized then
            event.area.left_top.x = entity.position.x - padding
        end

        if entity.position.y < event.area.left_top.y or uninitialized then
            event.area.left_top.y = entity.position.y - padding
        end

        if entity.position.x > event.area.right_bottom.x or uninitialized then
            event.area.right_bottom.x = entity.position.x + padding
        end

        if entity.position.y > event.area.right_bottom.y or uninitialized then
            event.area.right_bottom.y = entity.position.y + padding
        end

        uninitialized = false
    end
end

function pipes_present_in_area(surface, area)
    -- make search area one larger. This will make sure pipes right outside the selection are also found
    -- those might otherwise end up touching with the pipes we will add ourselves.
    local search_area = {
        left_top = {x = area.left_top.x - 1, y = area.left_top.y - 1},
        right_bottom = {
            x = area.right_bottom.x + 1,
            y = area.right_bottom.y + 1
        }
    }

    found_pipes = surface.find_entities_filtered {
        area = search_area,
        name = {"pipe", "pipe-to-ground"}
    }

    found_ghosts_of_pipes = surface.find_entities_filtered {
        area = search_area,
        ghost_name = {"pipe", "pipe-to-ground"}
    }

    return #found_pipes > 0 or #found_ghosts_of_pipes > 0
end

function prepare_planner_input(event)
    local planner_input = {area = {}}

    planner_input.area_bounds = event.area

    -- fill the map with default data 
    for x = event.area.left_top.x, event.area.right_bottom.x, 1 do
        planner_input.area[x] = {}
        for y = event.area.left_top.y, event.area.right_bottom.y, 1 do
            planner_input.area[x][y] = "undefined"
        end
    end

    -- mark where the pumps will be
    for i, entity in pairs(event.entities) do
        local direction = defines.direction.east
        planner_input.area[entity.position.x][entity.position.y] = "oil-well"
        if can_place_pumpjack(event.surface, entity.position, direction) then
            planner_input.area[entity.position.x - 1][entity.position.y - 1] =
                "reserved-for-pump"
            planner_input.area[entity.position.x - 1][entity.position.y] =
                "reserved-for-pump"
            planner_input.area[entity.position.x - 1][entity.position.y + 1] =
                "reserved-for-pump"
            planner_input.area[entity.position.x][entity.position.y - 1] =
                "reserved-for-pump"
            planner_input.area[entity.position.x][entity.position.y + 1] =
                "reserved-for-pump"
            planner_input.area[entity.position.x + 1][entity.position.y - 1] =
                "reserved-for-pump"
            planner_input.area[entity.position.x + 1][entity.position.y] =
                "reserved-for-pump"
            planner_input.area[entity.position.x + 1][entity.position.y + 1] =
                "reserved-for-pump"
        end
    end

    for x, reservations in pairs(planner_input.area) do
        for y, reservation in pairs(reservations) do
            if reservation == "undefined" then
                if can_place_pipe(event.surface, {x = x, y = y}) then
                    planner_input.area[x][y] = "can-build"
                else
                    planner_input.area[x][y] = "can-not-build"
                end
            end
        end
    end

    return planner_input
end

function dump_to_file(table_to_write, description)
    local planner_input_as_block = serpent.block(table_to_write)
    game.write_file("pump_" .. description .. ".block", planner_input_as_block)
    local planner_input_as_json = game.table_to_json(table_to_write)
    game.write_file("pump_" .. description .. ".json", planner_input_as_json)
end

function can_place_pumpjack(surface, position, direction)
    return surface.can_place_entity({
        name = "pumpjack",
        position = position,
        direction = direction,
        force = "player",
        build_check_type = defines.build_check_type.ghost_place
    })
end

function can_place_pipe(surface, position)
    return surface.can_place_entity({
        name = "pipe",
        position = position,
        direction = defines.direction.north,
        force = "player",
        build_check_type = defines.build_check_type.ghost_place
    })
end
