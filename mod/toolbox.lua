require 'util'
local math2d = require 'math2d'
local helpers = require 'helpers'

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

    toolbox.power_pole = {
        entity_name = "not-used-by-visualizer",
        --// medium-range
        supply_range = 3.5,
        wire_range = 9,

        --// small-range
        -- supply_range = 2.5,
        -- wire_range = 7.5,
        
        --// substation
        -- wire_range = 18,
        -- supply_range = 9,
        size = 1,
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
                available_pipes[pipe.name] = {
                    entity_name = pipe.name,
                    underground_entity_name = pipe.name .. "-to-ground",

                    -- TODO: Get these from the entity-search as well
                    -- underground_distance is excluding the entity placement itself. But rather the available space between connector entities.        
                    -- In the factorio-data the distance is actually 10 (including the pipe on the far side)        
                    underground_distance_min = 0,
                    underground_distance_max = 9
                }                
            end
        end
    end

    if next(available_pipes) == nil then return {"failure.no-pipe"} end
end

local function get_output_fluidbox(extractor)
    local output_fluid_boxes = {}
    for _, fluidbox in pairs(extractor.fluidbox_prototypes) do
        if fluidbox and fluidbox.production_type == "output" then
            table.insert(output_fluid_boxes, fluidbox);
        end
    end
    return output_fluid_boxes[1];
end

local function add_available_extractors(available_extractors, resource_category, player)
    local all_extractors = game.get_filtered_entity_prototypes(
                               {{filter = "type", type = "mining-drill"}})

    local suitable_extractors = {}
    for _, extractor in pairs(all_extractors) do
        if extractor.resource_categories[resource_category] and get_output_fluidbox(extractor) and
            meets_tech_requirement(extractor, player) then
            table.insert(suitable_extractors, extractor)
        end
    end

    if #suitable_extractors == 0 then
        return {"failure.no-suitable-extractor", resource_category}
    end

    for _, extractor in pairs(suitable_extractors) do
        local cardinal_output_positions = get_output_fluidbox(extractor).pipe_connections[1].positions

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
            available_extractors[extractor.name] = {
                entity_name = extractor.name,
                output_offsets = output_offsets,
                relative_bounds = relative_bounds
            };
        end
    end

    if next(available_extractors) == nil then
        return {"failure.extractor-must-be-square", resource_category}
    end
end

local function add_available_power_poles(available_power_poles, player)
    local all_poles = game.get_filtered_entity_prototypes({{filter = "type", type = "electric-pole"}})
    local has_big_poles = false

    for _, pole in pairs(all_poles) do
        if meets_tech_requirement(pole, player) then            
            local pole_collision_box = math2d.bounding_box.ensure_xy(pole.collision_box)
            local size = math.abs(pole_collision_box.left_top.x) + math.abs(pole_collision_box.right_bottom.x)            
            if size < 1 then
                available_power_poles[pole.name] = {
                    entity_name = pole.name,
                    supply_range = pole.supply_area_distance,
                    wire_range = pole.max_wire_distance,
                    size = 1,
                }
            else
                has_big_poles = true
            end
        end
    end

    if next(available_power_poles) == nil then
        if has_big_poles then
            return {"failure.no-suitable-power-pole"}
        end
        return {"failure.no-pole"}
    end
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

local function get_power_pole_pick()
    if not global.toolpicker_config then global.toolpicker_config = {} end

    if not global.toolpicker_config.power_pole_pick then
        global.toolpicker_config.power_pole_pick = {selected = nil, available = {}}
    end

    return global.toolpicker_config.power_pole_pick
end

local function reset_selection_if_pick_no_longer_available(pick, available)
    if not table.contains(available, pick.selected) then pick.selected = nil; end
end

local function add_pick_options_to_flow(flow, toolbox_options)
    flow.clear()

    for _, pick_name in pairs(toolbox_options.pick.available) do
        local style = "slot_sized_button"

        if pick_name == toolbox_options.pick.selected then
            style = "slot_sized_button_pressed"
        end

        local button = flow.add {
            type = "choose-elem-button",
            name = toolbox_options.button_prefix .. pick_name,
            elem_type = "entity",
            elem_filters = {{filter = "name", name = toolbox_options.pick.available}},
            entity = pick_name,
            style = style
        }
        button.locked = true
    end
end

local function create_toolbox_entity_options(toolbox_name, pick, toolbox_entries, failure)
    if failure then
        return {failure = failure}
    end

    local entity_names = {}
    for name, _ in pairs(toolbox_entries) do
        table.insert(entity_names, name)
    end

    return {
        -- The last selection persisted storage. Contains the entity name as well as a list of all available entity names at the time
        -- The list of names is then used to determine of new options are available and the UI should show again 
        pick = pick,
        -- Prefix to uniquely name the buttons in the UI
        button_prefix = "pump_toolbox_picker_button_" .. toolbox_name .. "__",
        -- Name of the flow containing the button in the UI
        flow_name = "pump_toolbox_picker_flow_" .. toolbox_name,
        
        -- Used in the planner as mod_context.toolbox.<INSERT-toolbox_name-HERE>
        toolbox_name = toolbox_name,
        -- Table keyed on entity-names with content made available via toolbox in the planned.
        toolbox_entries = toolbox_entries,
        -- Available entity names, can be used as keys for toolbox_entries
        entity_names = entity_names
    }
end

local function create_toolbox_extractor_options(player, resource_category)
    local toolbox_entries = {}
    local failure = add_available_extractors(toolbox_entries, resource_category, player)

    return create_toolbox_entity_options(
        "extractor",
        get_extractor_pick_for_resource(resource_category),
        toolbox_entries,
        failure
    )
end

local function create_toolbox_pipe_options(player)
    local toolbox_entries = {}
    local failure = add_available_pipes(toolbox_entries, player)

    return create_toolbox_entity_options(
        "connector",
        get_pipe_pick(),
        toolbox_entries,
        failure
    )
end

local function create_toolbox_power_pole_options(player)
    local toolbox_entries = {}
    local failure = add_available_power_poles(toolbox_entries, player)

    return create_toolbox_entity_options(
        "power_pole",
        get_power_pole_pick(),
        toolbox_entries,
        failure
    )
end

local function create_all_toolbox_options(player, resource_category)
    local all_toolbox_options = {}
    table.insert(all_toolbox_options, create_toolbox_extractor_options(player, resource_category))
    table.insert(all_toolbox_options, create_toolbox_pipe_options(player))
    table.insert(all_toolbox_options, create_toolbox_power_pole_options(player))
    return all_toolbox_options
end

local function pick_tools(player, toolbox, all_toolbox_options, force_ui)

    local selection_required = false
    local new_options_available = false

    for _, options in pairs(all_toolbox_options) do
        -- A mod might've been removed
        reset_selection_if_pick_no_longer_available(options.pick, options.entity_names)

        -- Multiple options available, and no previous selection is known.
        selection_required = selection_required or (#options.entity_names > 1 and not options.pick.selected)

        -- There's a selection, and P.U.M.P. can work. But the available tools have changed. 
        new_options_available = new_options_available or (
            options.pick.selected and 
            #options.entity_names > 1 and
            not table.compare(options.pick.available, options.entity_names))

        -- persist the available entities for next time, in order to check when new options have been added in the meantime.
        options.pick.available = options.entity_names

        -- ensure a default selection
        if not options.pick.selected then options.pick.selected = options.entity_names[1] end

        -- put selection in toolbox. 
        -- If the UI doesn't open this is what the planner will work with,
        -- If the UI opens, these will be overwritten
        toolbox[options.toolbox_name] = options.toolbox_entries[options.pick.selected]
    end

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

        function create_flow(options) 
            local flow = frame.add {
                type = "flow",
                direction = "horizontal",
                name = options.flow_name
            }
            add_pick_options_to_flow(flow, options)
        end

        for _, options in pairs(all_toolbox_options) do
            create_flow(options)
        end

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

function add_toolbox(current_action, player, force_ui)
    local toolbox = {}
    add_module_config(toolbox, player)

    local all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
    for _, options in pairs(all_toolbox_options) do
        if options.failure then return options.failure end
    end

    pick_tools(player, toolbox, all_toolbox_options, force_ui)

    current_action.toolbox = toolbox
end

function confirm_tool_picker_ui(player)
    local frame = player.gui.center.pump_tool_picker_frame
    if frame then frame.destroy() end
end

function handle_gui_element_click(element_name, player)
    local frame = player.gui.center.pump_tool_picker_frame
    local current_action = global.current_action

    if frame then
        local all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
        for _, options in pairs(all_toolbox_options) do
            for _, entity_name in pairs(options.entity_names) do
                local element_name_for_entity = options.button_prefix .. entity_name
                if element_name == element_name_for_entity then

                    -- Store selection
                    options.pick.selected = entity_name

                    -- Update selection option in the UI
                    add_pick_options_to_flow(frame[options.flow_name], options)

                    -- Update toolbox content for the planner
                    current_action.toolbox[options.toolbox_name] = options.toolbox_entries[entity_name]
                end
            end        
        end
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

