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

local function get_extractor_pick_for_resource(resource_category)
    if not global.toolpicker_config then
        global.toolpicker_config = {
            extractor_pick = {selected = nil, available = {}}
        }
    end

    if not global.toolpicker_config.extractor_pick[resource_category] then
        global.toolpicker_config.extractor_pick[resource_category] =
            {selected = nil, available = {}}
    end

    return global.toolpicker_config.extractor_pick[resource_category]
end

local function reset_selection_if_pick_no_longer_available(pick, available)
    if not table.contains(available, pick.selected) then pick.selected = nil; end
end

local function pick_tools(player, toolbox, resource_category,
                          available_extractors, force_ui)
    local extractor_pick = get_extractor_pick_for_resource(
                               toolbox.resource_category);

    local available_extractor_names = {}
    for _, extractor in pairs(available_extractors) do
        table.insert(available_extractor_names, extractor.entity_name)
    end

    -- A mod might've been removed
    reset_selection_if_pick_no_longer_available(extractor_pick,
                                                available_extractor_names)

    -- availble extractors might've changed. In case of a new game, will always be true because the previous selection is empty                                            
    local available_extractors_changed =
        not table.compare(extractor_pick.available, available_extractor_names)

    -- persist the available extractors for next time
    extractor_pick.available = available_extractor_names;

    -- ensure a default selection
    if not extractor_pick.selected then
        extractor_pick.selected = available_extractor_names[1]
    end

    -- put selection in toolbox, though it might later be overwritten after the UI closes
    for _, extractor in pairs(available_extractors) do
        if extractor.entity_name == extractor_pick.selected then
            toolbox.extractor = extractor
        end
    end

    if force_ui or available_extractors_changed then

        local frame = player.gui.center.add {
            type = "frame",
            name = "pump_tool_picker_frame",
            caption = {"pump-toolpicker.title"},
            direction = "vertical"
        }

        local caption = {"pump-toolpicker.choose-extractor-generic"}

        if not force_ui then
            if available_extractors_changed then
                caption = {"pump-toolpicker.choose-extractor-changed-options"}
            else
                caption = {"pump-toolpicker.choose-extractor-unknown-selection"}
            end
        end

        frame.add {type = "label", caption = caption}

        local extractor_button = frame.add {
            type = "choose-elem-button",
            name = "pump_extractor_picker",
            elem_type = "entity",
            elem_filters = {{filter = "name", name = available_extractor_names}},
            entity = extractor_pick.selected
        }

        frame.add {
            type = "button",
            name = "pump_tool_picker_confirm_button",
            caption = {"pump-toolpicker.confirm"}
        }

        global.toolpicker_ui = {resource_category = resource_category}
    end
end

function confirm_tool_picker_ui(player)
    local frame = player.gui.center.pump_tool_picker_frame

    if frame then

        local extractor_pick = get_extractor_pick_for_resource(
                                   global.toolpicker_ui.resource_category)

        extractor_pick.selected = frame.pump_extractor_picker.elem_value

        frame.destroy()
    end

    global.toolpicker_ui = nil
end

function is_ui_open(player)

    local flow = player.gui.center
    local frame = flow.pump_tool_picker_frame

    if frame then
        return true
    else
        return false
    end
end

function table.contains(table, element)
    for _, value in pairs(table) do if value == element then return true end end
    return false
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

local function find_available_extractors(resource_category)
    local all_extractors = game.get_filtered_entity_prototypes(
                               {{filter = "type", type = "mining-drill"}})

    local suitable_extractors = {}
    for _, extractor in pairs(all_extractors) do
        if extractor.resource_categories[resource_category] then
            table.insert(suitable_extractors, extractor)
        end
    end

    if #suitable_extractors == 0 then
        return {"failure.no-suitable-extractor", resource_category}
    end

    local available_extractors = {}

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

    return available_extractors
end

function add_toolbox(target, resource_category, player, force_ui)
    local toolbox = {}
    toolbox.resource_category = resource_category
    add_module_config(toolbox, player)

    local available_extractors = find_available_extractors(resource_category)
    if #available_extractors == 0 then
        return {"failure.extractor-must-be-square", resource_category}
    end

    pick_tools(player, toolbox, resource_category, available_extractors,
               force_ui)

    toolbox.connector = {
        entity_name = "pipe",
        underground_entity_name = "pipe-to-ground",

        -- underground_distance is excluding the entity placement itself. But rather the available space between connector entities.        
        underground_distance_min = 0,
        underground_distance_max = 9
    }

    target.toolbox = toolbox
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

