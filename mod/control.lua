require "toolbox"
require "prospector"
require "plumber"
require "plumber-pro"
require "electrician"
require 'constructor'

script.on_event({defines.events.on_player_selected_area}, function(event)
    if event.item == 'pump-selection-tool' then
        process_selected_area_with_this_mod(event, false)
    end
end)

script.on_event({defines.events.on_player_alt_selected_area}, function(event)
    if event.item == 'pump-selection-tool' then
        process_selected_area_with_this_mod(event, true)
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    local name = event.element.name
    local player = game.players[event.player_index]
    if name == "pump_tool_picker_confirm_button" then
        close_tool_picker_ui(player, true)
        resume_process_selected_area_with_this_mod()
    elseif name == "pump_tool_picker_cancel_button" then
        close_tool_picker_ui(player, false)
    else
        local button_prefix = "pump_toolbox_picker_button_"
        if string.find(name, button_prefix) == 1 then
            handle_gui_element_click(name, player)
        end
    end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    local name = event.element.name
    local player = game.players[event.player_index]

    local dropdown_prefix = "pump_toolbox_quality_dropdown"
    if string.find(name, dropdown_prefix) == 1 then
        handle_gui_element_quality_selection_change(event.element, player)
    end

    if string.find(name, "pump_tool_picker_pipe_bury_distance") == 1 then
        handle_pipe_bury_preference_change(event.element, player)
    end
end)

script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.players[event.player_index]

    if is_ui_open(player) then
        close_tool_picker_ui(player, false)
    end
end)

script.on_event("pump-selection-tool-toggle", function(event)
    local player = game.players[event.player_index]

    -- Check if the player already has the "pump-selection-tool" in the cursor
    if player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == "pump-selection-tool" then
        -- If the player has the tool in the cursor, clear the cursor
        player.cursor_stack.clear()
    else
        -- If the player doesn't have the tool in the cursor, place it in the cursor
        local pumpSelectionTool = "pump-selection-tool" -- Make sure this matches the item name defined in your data.lua
        player.cursor_stack.set_stack({name = pumpSelectionTool, count = 1})
    end
end
)

function process_selected_area_with_this_mod(event, force_ui)
    local player = game.get_player(event.player_index)

    -- The game is not paused with a ui open. So make sure a second selection is ignore until the window is closed.
    if is_ui_open(player) then return end

    -- Store required input in global, so it can resume after the ui is potentially shown.
    storage.current_action = {failure = nil}
    local current_action = storage.current_action

    current_action.player_index = event.player_index
    current_action.area_bounds = event.area
    current_action.surface_index = event.surface.index

    if not current_action.failure then
        current_action.failure = add_resource_category(current_action,
                                                       event.entities)
    end

    if not current_action.failure then
        current_action.failure = add_toolbox(current_action, player, force_ui)
    end

    if not is_ui_open(player) then
        resume_process_selected_area_with_this_mod()
    end
end

function resume_process_selected_area_with_this_mod()
    local current_action = storage.current_action
    local surface = game.get_surface(current_action.surface_index)
    local player = game.get_player(current_action.player_index)
    local entities = surface.find_entities_filtered {
        area = current_action.area_bounds,
        name = {current_action.resource_entity_name}
    }

    if not current_action.failure then
        current_action.failure = trim_selected_area(current_action, entities)
    end

    if not current_action.failure then
        current_action.failure = pipes_present_in_area(surface,
                                                       current_action.area_bounds)
    end

    if not current_action.failure then
        current_action.failure = add_area_information(current_action, entities,
                                                      surface, player)
    end

    dump_to_file(current_action, "planner_input")

    if not current_action.failure then
        local setting = player.mod_settings["pump-use-plumber-pro"] 
        if setting and setting.value then
            current_action.failure = plan_plumbing_pro(current_action)
        else
            current_action.failure = plan_plumbing(current_action)
        end
    end

    if not current_action.failure and current_action.toolbox.power_pole ~= nil then
        -- current_action.failure may be set directly by plan_power
        plan_power(current_action)
    end

    dump_to_file(current_action, "construction_plan")

    if not current_action.failure then
        current_action.failure = construct_entities(
                                     current_action.construction_plan, player,
                                     current_action.toolbox)
    end

    if current_action.failure then player.print(current_action.failure) end
end

function add_resource_category(current_action, entities_in_selection)
    if #entities_in_selection == 0 then return {"failure.missing-resource"} end

    local first_entity = nil

    for i, entity in pairs(entities_in_selection) do
        if first_entity == nil then
            first_entity = entity
        else
            if entity.name ~= first_entity.name then
                return {"failure.mixed-resources"}
            end
        end
    end

    current_action.resource_category = first_entity.prototype.resource_category
    current_action.resource_entity_name = first_entity.name
end

function trim_selected_area(current_action, entities)
    local uninitialized = true
    local area = current_action.area_bounds

    for i, entity in pairs(entities) do
        if entity.position.x < area.left_top.x or uninitialized then
            area.left_top.x = entity.position.x
        end

        if entity.position.y < area.left_top.y or uninitialized then
            area.left_top.y = entity.position.y
        end

        if entity.position.x > area.right_bottom.x or uninitialized then
            area.right_bottom.x = entity.position.x
        end

        if entity.position.y > area.right_bottom.y or uninitialized then
            area.right_bottom.y = entity.position.y
        end

        uninitialized = false
    end

    local extractor_bounds = current_action.toolbox.extractor.relative_bounds;

    area.left_top.x = (area.left_top.x + extractor_bounds.left_top.x) - 2
    area.left_top.y = (area.left_top.y + extractor_bounds.left_top.y) - 2
    area.right_bottom.x =
        (area.right_bottom.x + extractor_bounds.right_bottom.x) + 2
    area.right_bottom.y =
        (area.right_bottom.y + extractor_bounds.right_bottom.y) + 2
end

function dump_to_file(table_to_write, description)
    local planner_input_as_json = helpers.table_to_json(table_to_write)
    helpers.write_file("pump_" .. description .. ".json", planner_input_as_json)
end
