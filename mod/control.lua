require "prospector"
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
    if planner_input.failure then
        player.print(planner_input.failure)
        return
    end

    local construct_entities = plan(planner_input)
    if planner_input.failure then
        player.print(planner_input.failure)
        return
    end

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

    for i, entity in pairs(event.entities) do
        if entity.position.x < event.area.left_top.x or uninitialized then
            event.area.left_top.x = entity.position.x
        end

        if entity.position.y < event.area.left_top.y or uninitialized then
            event.area.left_top.y = entity.position.y
        end

        if entity.position.x > event.area.right_bottom.x or uninitialized then
            event.area.right_bottom.x = entity.position.x
        end

        if entity.position.y > event.area.right_bottom.y or uninitialized then
            event.area.right_bottom.y = entity.position.y
        end

        uninitialized = false
    end

    local padding = 2 -- 1 for the size of the pump, 1 more for outgoing pipe
    event.area.left_top.x = event.area.left_top.x - padding
    event.area.left_top.y = event.area.left_top.y - padding
    event.area.right_bottom.x = event.area.right_bottom.x + padding
    event.area.right_bottom.y = event.area.right_bottom.y + padding
end

function dump_to_file(table_to_write, description)
    local planner_input_as_json = game.table_to_json(table_to_write)
    game.write_file("pump_" .. description .. ".json", planner_input_as_json)
end
