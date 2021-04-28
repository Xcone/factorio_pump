require 'util'

-- Simplified non-dynamic variation of the toolbox used by the C# WPF application to test planner.lua without mimicing all of factorio
function add_development_toolbox(target)
    local toolbox = {}
    toolbox.extractor = {
        entity_name = 'not-used-by-visualizer',
        output_offsets = {
            [defines.direction.north] = {x = 1, y = -2},
            [defines.direction.east] = {x = 2, y = -1},
            [defines.direction.south] = {x = -1, y = 2},
            [defines.direction.west] = {x = -2, y = 1}
        },
        relative_bounds = {
            left_top = {x = -1, y = -1},
            right_bottom = {x = 1, y = 1}
        }
    }

    toolbox.connector = {
        entity_name = 'not-used-by-visualizer',
        underground_entity_name = 'not-used-by-visualizer',
        underground_distance_min = 0,
        underground_distance_max = 9
    }

    target.toolbox = toolbox
end

local function meets_tech_requirement(entity, player)
    entity_is_unlocked = false;

    local setting = player.mod_settings["pump-ignore-research"]
    local ignore_resaearch = setting and setting.value

    if ignore_resaearch then
        entity_is_unlocked = true
    else
        local recipies_for_entity = game.get_filtered_recipe_prototypes {
            {
                filter = "has-product-item",
                elem_filters = {{filter = "name", name = entity.name}}
            }
        }

        for recipe_name, _ in pairs(recipies_for_entity) do
            local recipe = player.force.recipes[recipe_name]
            if recipe ~= nil and recipe.enabled then
                entity_is_unlocked = true
            end
        end
    end
    return entity_is_unlocked
end

local function get_extractor_pick_for_resource(resource_category)
    if not global.toolpicker_config then global.toolpicker_config = {} end

    if not global.toolpicker_config.extractor_pick then
        global.toolpicker_config.extractor_pick = {}
    end

    if not global.toolpicker_config.extractor_pick[resource_category] then
        global.toolpicker_config.extractor_pick[resource_category] =
            {selected = nil, available = {}}
    end

    return global.toolpicker_config.extractor_pick[resource_category]
end

local function get_pipe_pick()
    if not global.toolpicker_config then global.toolpicker_config = {} end

    if not global.toolpicker_config.pipe_pick then
        global.toolpicker_config.pipe_pick = {selected = nil, available = {}}
    end

    return global.toolpicker_config.pipe_pick
end

local function reset_selection_if_pick_no_longer_available(pick, available)
    if not table.contains(available, pick.selected) then pick.selected = nil; end
end

local function add_extractor_buttons_to_flow(extractor_flow, extractor_pick)
    for _, extractor_name in pairs(extractor_pick.available) do
        local style = "slot_sized_button"

        if extractor_name == extractor_pick.selected then
            style = "slot_sized_button_pressed"
        end

        local button = extractor_flow.add {
            type = "choose-elem-button",
            name = "pump_extractor_picker__" .. extractor_name,
            elem_type = "entity",
            elem_filters = {{filter = "name", name = extractor_pick.available}},
            entity = extractor_name,
            style = style
        }
        button.locked = true
    end
end

local function add_pipe_buttons_to_flow(pipe_flow, pipe_pick)
    for _, pipe_name in pairs(pipe_pick.available) do
        local style = "slot_sized_button"

        if pipe_name == pipe_pick.selected then
            style = "slot_sized_button_pressed"
        end

        local button = pipe_flow.add {
            type = "choose-elem-button",
            name = "pump_pipe_picker__" .. pipe_name,
            elem_type = "entity",
            elem_filters = {{filter = "name", name = pipe_pick.available}},
            entity = pipe_name,
            style = style
        }
        button.locked = true
    end
end

local function pick_tools(player, toolbox, resource_category,
                          available_extractors, available_pipes, force_ui)
    local extractor_pick = get_extractor_pick_for_resource(resource_category);
    local pipe_pick = get_pipe_pick();

    local available_extractor_names = {}
    for _, extractor in pairs(available_extractors) do
        table.insert(available_extractor_names, extractor.entity_name)
    end

    -- A mod might've been removed
    reset_selection_if_pick_no_longer_available(extractor_pick,
                                                available_extractor_names)

    reset_selection_if_pick_no_longer_available(pipe_pick, available_pipes)

    -- Multiple items, and no previous selection exists. Recipe for disaster!! Better ask.
    local selection_required = (#available_extractor_names > 1 and
                                   not extractor_pick.selected) or
                                   (#available_pipes > 1 and
                                       not pipe_pick.selected)

    -- There's a selection, and P.U.M.P. can work. But the available tools have changed. 
    local new_extractor_options_available =
        extractor_pick.selected and #available_extractor_names > 1 and
            not table.compare(extractor_pick.available,
                              available_extractor_names)

    local new_pipe_options_available = pipe_pick.selected and #available_pipes >
                                           1 and
                                           not table.compare(
                                               pipe_pick.available,
                                               available_pipes)

    local new_options_available = new_extractor_options_available or
                                      new_pipe_options_available

    -- persist the available extractors and pipes for next time
    extractor_pick.available = available_extractor_names;
    pipe_pick.available = available_pipes;

    -- ensure a default selection
    if not extractor_pick.selected then
        extractor_pick.selected = available_extractor_names[1]
    end

    if not pipe_pick.selected then pipe_pick.selected = available_pipes[1] end

    -- put selection in toolbox, though it might later be overwritten after the UI closes
    for _, extractor in pairs(available_extractors) do
        if extractor.entity_name == extractor_pick.selected then
            toolbox.extractor = extractor
        end
    end
    toolbox.connector.entity_name = pipe_pick.selected
    toolbox.connector.underground_entity_name =
        pipe_pick.selected .. '-to-ground'

    if force_ui or selection_required or new_options_available then

        local frame = player.gui.center.add {
            type = "frame",
            name = "pump_tool_picker_frame",
            caption = {"pump-toolpicker.title"},
            direction = "vertical"
        }

        local caption = {"pump-toolpicker.choose-extractor-generic"}

        if not force_ui then
            if selection_required then
                caption = {"pump-toolpicker.choose-extractor-unknown-selection"}
            else
                caption = {"pump-toolpicker.choose-extractor-changed-options"}
            end
        end

        frame.add {type = "label", caption = caption}

        local extractor_flow = frame.add {
            type = "flow",
            direction = "horizontal",
            name = "pump_extractor_picker_flow"
        }

        local pipe_flow = frame.add {
            type = "flow",
            direction = "horizontal",
            name = "pump_pipe_picker_flow"
        }

        add_extractor_buttons_to_flow(extractor_flow, extractor_pick)
        add_pipe_buttons_to_flow(pipe_flow, pipe_pick)

        frame.add {
            type = "button",
            name = "pump_tool_picker_confirm_button",
            caption = {"pump-toolpicker.confirm"},
            style = "confirm_button"
        }
    end
end

local function add_module_config(toolbox, player)

    local setting =
        player.mod_settings["pump-interface-with-module-inserter-mod"]

    if setting and setting.value and remote.interfaces["mi"] then
        toolbox.module_config = remote.call("mi", "get_module_config",
                                            player.index)
    end

    if not toolbox.module_config then toolbox.module_config = {} end
end

local function has_matching_pipe_to_ground(pipe_name)
    local matching_pipe_to_ground_result =
        game.get_filtered_entity_prototypes(
            {
                {filter = "type", type = "pipe-to-ground"},
                {
                    filter = "name",
                    name = pipe_name .. "-to-ground",
                    mode = "and"
                }
            })

    return #matching_pipe_to_ground_result > 0
end

local function add_available_pipes(available_pipes, player)
    local all_pipes = game.get_filtered_entity_prototypes(
                          {{filter = "type", type = "pipe"}})

    for _, pipe in pairs(all_pipes) do
        if meets_tech_requirement(pipe, player) then
            if has_matching_pipe_to_ground(pipe.name) then
                table.insert(available_pipes, pipe.name)
            end
        end
    end

    if #available_pipes == 0 then return {"failure.no-pipes"} end
end

local function add_available_extractors(available_extractors, resource_category,
                                        player)
    local all_extractors = game.get_filtered_entity_prototypes(
                               {{filter = "type", type = "mining-drill"}})

    local suitable_extractors = {}
    for _, extractor in pairs(all_extractors) do
        if extractor.resource_categories[resource_category] and
            meets_tech_requirement(extractor, player) then
            table.insert(suitable_extractors, extractor)
        end
    end

    if #suitable_extractors == 0 then
        return {"failure.no-suitable-extractor", resource_category}
    end

    for _, extractor in pairs(suitable_extractors) do
        local cardinal_output_positions =
            extractor.fluidbox_prototypes[1].pipe_connections[1].positions

        local output_offsets = {
            [defines.direction.north] = cardinal_output_positions[1],
            [defines.direction.east] = cardinal_output_positions[2],
            [defines.direction.south] = cardinal_output_positions[3],
            [defines.direction.west] = cardinal_output_positions[4]
        }

        local relative_bounds = {
            left_top = {
                x = output_offsets[defines.direction.west].x + 1,
                y = output_offsets[defines.direction.north].y + 1
            },
            right_bottom = {
                x = output_offsets[defines.direction.east].x - 1,
                y = output_offsets[defines.direction.south].y - 1
            }
        }

        local width = relative_bounds.right_bottom.x -
                          relative_bounds.left_top.x
        local height = relative_bounds.right_bottom.y -
                           relative_bounds.left_top.y

        if width == height then
            table.insert(available_extractors, {
                entity_name = extractor.name,
                output_offsets = output_offsets,
                relative_bounds = relative_bounds
            });
        end
    end

    if #available_extractors == 0 then
        return {"failure.extractor-must-be-square", resource_category}
    end
end

function add_toolbox(current_action, player, force_ui)
    local toolbox = {}
    add_module_config(toolbox, player)

    local failure = {}
    local available_extractors = {}
    failure = add_available_extractors(available_extractors,
                                       current_action.resource_category, player)

    if failure then return failure end

    local available_pipes = {}
    add_available_pipes(available_pipes, player)

    if failure then return failure end

    -- TODO: Figure out of the pipe-distance can be dynamically retrieved after pipe selection as well and remove these defaults.
    -- Note that entity names are being overwritten in the meantime.
    toolbox.connector = {
        entity_name = "pipe",
        underground_entity_name = "pipe-to-ground",

        -- underground_distance is excluding the entity placement itself. But rather the available space between connector entities.        
        underground_distance_min = 0,
        underground_distance_max = 9
    }

    pick_tools(player, toolbox, current_action.resource_category,
               available_extractors, available_pipes, force_ui)

    current_action.toolbox = toolbox
end

function confirm_tool_picker_ui(player)
    local frame = player.gui.center.pump_tool_picker_frame
    if frame then frame.destroy() end
end

function on_extractor_selection(player, extractor_name)
    local frame = player.gui.center.pump_tool_picker_frame

    if frame then

        local current_action = global.current_action
        local extractor_pick = get_extractor_pick_for_resource(
                                   current_action.resource_category)

        -- apply changed selection to extractor pick
        extractor_pick.selected = extractor_name

        -- refresh buttons on UI
        frame.pump_extractor_picker_flow.clear()
        add_extractor_buttons_to_flow(frame.pump_extractor_picker_flow,
                                      extractor_pick)

        -- update the extractor for the current action
        local available_extractors = {}
        local failure = add_available_extractors(available_extractors,
                                                 current_action.resource_category,
                                                 player)
        -- Note: The above failure does not need handling, because if it would've failed, the call before showing the UI would already have stopped the current action.

        for _, extractor in pairs(available_extractors) do
            if extractor.entity_name == extractor_pick.selected then
                current_action.toolbox.extractor = extractor
            end
        end
    end
end

function on_pipe_selection(player, pipe_name)
    local frame = player.gui.center.pump_tool_picker_frame

    if frame then

        local current_action = global.current_action
        local pipe_pick = get_pipe_pick()

        -- apply changed selection to pipe pick
        pipe_pick.selected = pipe_name

        -- refresh buttons on UI
        frame.pump_pipe_picker_flow.clear()
        add_pipe_buttons_to_flow(frame.pump_pipe_picker_flow, pipe_pick)

        -- update the pipe for the current action
        current_action.toolbox.connector.entity_name = pipe_pick.selected
        current_action.toolbox.connector.underground_entity_name =
            pipe_pick.selected .. '-to-ground'
    end
end

function is_ui_open(player)
    if player.gui.center.pump_tool_picker_frame then
        return true
    else
        return false
    end
end

function table.contains(table, element)
    for _, value in pairs(table) do if value == element then return true end end
    return false
end

function get_resource_category_map_from_data()
    local resource_category_map = {}
    for resource_category, _ in pairs(data.raw["resource-category"]) do
        resource_category_map[resource_category] =
            {fluids = {}, extractors = {}}
    end

    for name, resource in pairs(data.raw["resource"]) do
        if resource.minable.results ~= nil and #(resource.minable.results) == 1 then
            if resource.minable.results[1].type == "fluid" then
                table.insert(resource_category_map[resource.category].fluids,
                             name)
            end
        end
    end

    for name, extractor in pairs(data.raw["mining-drill"]) do
        for _, resource_category in pairs(extractor.resource_categories) do
            table.insert(resource_category_map[resource_category].extractors,
                         extractor.name)
        end
    end

    local resource_category_map_only_fluids = {}
    for resource_category, fluids_and_extractors in pairs(resource_category_map) do
        if #(fluids_and_extractors.fluids) > 0 and
            #(fluids_and_extractors.extractors) > 0 then
            resource_category_map_only_fluids[resource_category] =
                {
                    fluids = fluids_and_extractors.fluids,
                    extractors = fluids_and_extractors.extractors
                }
        end
    end

    return resource_category_map_only_fluids
end

