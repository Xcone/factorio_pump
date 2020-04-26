require "toolbox"
require "prospector"
require "planner"

script.on_event({defines.events.on_player_selected_area}, function(event)
    if event.item == 'pump-selection-tool' then
        process_selected_area_with_this_mod(event)
    end
end)

function process_selected_area_with_this_mod(event)
    local mod_context = {failure = nil}

    if not mod_context.failure then
        mod_context.failure = trim_event_area(event)
    end

    if not mod_context.failure then
        mod_context.failure = pipes_present_in_area(event.surface, event.area)
    end

    if not mod_context.failure then
        mod_context.failure = add_area_information(event, mod_context)
    end

    if not mod_context.failure then
        mod_context.failure = add_toolbox(mod_context)
    end

    if not mod_context.failure then
        mod_context.failure = add_construction_plan(mod_context)
    end

    if not mod_context.failure then
        mod_context.failure = construct_entities(mod_context.construction_plan,
                                                 event.surface,
                                                 mod_context.toolbox)
    end

    if mod_context.failure then
        local player = game.get_player(event.player_index)
        player.print(mod_context.failure)
    end

    dump_to_file(mod_context, "planner_input")
end

function trim_event_area(event)
    if #event.entities == 0 then return {"failure.missing-resource"} end

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

function construct_entities(construction_plan, surface, toolbox)
    for construction_plan_catagory_name, entities_to_place in
        pairs(construction_plan) do
        local entity_name = "unknown"

        if construction_plan_catagory_name == "extractors" then
            entity_name = toolbox.extractor.entity_name
        end

        if construction_plan_catagory_name == "outputs" then
            entity_name = toolbox.connector.entity_name
        end

        if construction_plan_catagory_name == "connectors" then
            entity_name = toolbox.connector.entity_name
        end

        if construction_plan_catagory_name == "connector_joints" then
            entity_name = toolbox.connector.entity_name
        end

        if construction_plan_catagory_name == "connectors_underground" then
            entity_name = toolbox.connector.underground_entity_name
        end

        for i, parameters in pairs(entities_to_place) do
            surface.create_entity {
                name = "entity-ghost",
                inner_name = entity_name,
                position = parameters.position,
                direction = parameters.direction,
                force = "player"
            }
        end
    end
end

function dump_to_file(table_to_write, description)
    local planner_input_as_json = game.table_to_json(table_to_write)
    game.write_file("pump_" .. description .. ".json", planner_input_as_json)
end
