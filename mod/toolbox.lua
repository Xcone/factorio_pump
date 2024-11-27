require 'util'
local math2d = require 'math2d'
local plib = require 'plib'
local assistant = require 'planner-assistant'

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

    local small_pole = {
        entity_name = "not-used-by-visualizer",
        supply_range = 2.5,
        wire_range = 7.5,
        size = 1
    }

    local medium_pole = {
        entity_name = "not-used-by-visualizer",
        supply_range = 3.5,
        wire_range = 9,
        size = 1
    }

    local big_pole = {
        entity_name = "not-used-by-visualizer",
        supply_range = 2,
        wire_range = 30,
        size = 2
    }

    local substation = {
        entity_name = "not-used-by-visualizer",
        supply_range = 8, -- 9 from the center; but P.U.M.P. calculates from the edge
        wire_range = 18,
        size = 2
    }

    -- toolbox.power_pole = small_pole
    -- toolbox.power_pole = medium_pole
    -- toolbox.power_pole = big_pole
    toolbox.power_pole = substation
    toolbox.pipe_bury_distance_preference = 999


    target.toolbox = toolbox
end

local function meets_tech_requirement(entity, player)
    entity_is_unlocked = false;

    local setting = player.mod_settings["pump-ignore-research"]
    local ignore_resaearch = setting and setting.value

    if ignore_resaearch then
        entity_is_unlocked = true
    else
        local recipies_for_entity = prototypes.get_recipe_filtered {
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
        prototypes.get_entity_filtered(
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
    local all_pipes = prototypes.get_entity_filtered(
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
    local all_extractors = prototypes.get_entity_filtered(
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
            [defines.direction.north] = math2d.position.add(plib.directions[defines.direction.north].vector, cardinal_output_positions[1]),
            [defines.direction.east] = math2d.position.add(plib.directions[defines.direction.east].vector, cardinal_output_positions[2]),
            [defines.direction.south] = math2d.position.add(plib.directions[defines.direction.south].vector, cardinal_output_positions[3]),
            [defines.direction.west] = math2d.position.add(plib.directions[defines.direction.west].vector, cardinal_output_positions[4])
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

local function add_available_power_poles(available_power_poles, player, quality_name)
    local all_poles = prototypes.get_entity_filtered({{filter = "type", type = "electric-pole"}})
    local has_big_poles = false

    for _, pole in pairs(all_poles) do
        if meets_tech_requirement(pole, player) then            
            local pole_collision_box = math2d.bounding_box.ensure_xy(pole.collision_box)
            local size = math.abs(pole_collision_box.left_top.x) + math.abs(pole_collision_box.right_bottom.x)            
            if size < 2 then
                local size = math.ceil(size)
                available_power_poles[pole.name] = {
                    entity_name = pole.name,
                    supply_range = pole.get_supply_area_distance(quality_name) - (size - 1), -- subtract 1 for a 2x2 power-pole
                    wire_range = pole.get_max_wire_distance(quality_name),
                    size = size,
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

local function add_meltable_tile_covers(meltable_tile_covers)
    local placable_tile_items = prototypes.get_item_filtered{{filter = "place-as-tile", comparison = ">", value = 1}}    
    for _, item in pairs(placable_tile_items) do
        -- Not sure why, but if a tile has a frozen variant, it counts as meltable-protection.
        -- Maybe it actually means something else, but it does give the expected result.
        if item.place_as_tile_result.result.frozen_variant ~= nil then
            meltable_tile_covers[item.name] = { item_name = item.name }
        end
    end
end

local function get_extractor_pick_for_resource(resource_category)
    if not storage.toolpicker_config.extractor_pick then
        storage.toolpicker_config.extractor_pick = {}
    end

    if not storage.toolpicker_config.extractor_pick[resource_category] then
        storage.toolpicker_config.extractor_pick[resource_category] =
            {selected = nil, available = {}, quality_name = nil}
    end

    return storage.toolpicker_config.extractor_pick[resource_category]
end

local function get_pipe_pick()
    if not storage.toolpicker_config.pipe_pick then
        storage.toolpicker_config.pipe_pick = {selected = nil, available = {}, quality_name = nil}
    end

    return storage.toolpicker_config.pipe_pick
end

local function get_power_pole_pick()
    if not storage.toolpicker_config.power_pole_pick then
        storage.toolpicker_config.power_pole_pick = {selected = nil, available = {}, quality_name = nil}
    end

    return storage.toolpicker_config.power_pole_pick
end

local function get_meltable_tile_cover_pick()
    if not storage.toolpicker_config.meltable_tile_cover_pick then
        storage.toolpicker_config.meltable_tile_cover_pick = {selected = nil, available = {}}
    end

    return storage.toolpicker_config.meltable_tile_cover_pick
end

local function get_pipe_bury_option()
    if not storage.toolpicker_config.pipe_bury_option then
        storage.toolpicker_config.pipe_bury_option = 1
    end

    return storage.toolpicker_config.pipe_bury_option
end

local function convert_pipe_bury_option_to_distance(option)
    if option == 1 then
        return 2
    end
    if option == 2 then
        return 4
    end
    if option == 3 then
        return 6
    end
    if option == 4 then
        return 99
    end
end

local function reset_selection_if_pick_no_longer_available(pick, available)
    if pick.selected ~= "none" then
        if not table.contains(available, pick.selected) then pick.selected = nil; end
    end
end

local function get_visible_qualities()
    local qualities = {}

    for _, quality in pairs(prototypes.quality) do
        if not quality.hidden then
            table.insert(qualities, quality)
        end
    end

    return qualities
end

local function get_quality_index(quality_name)
    for index, quality in pairs(get_visible_qualities()) do
        if quality_name == quality.name then
            return index;
        end
    end

    return 0;
end

local function add_pick_options_to_flow(flow, toolbox_options)
    flow.clear()    

    local qualities = get_visible_qualities()
    if #qualities > 1 then
        local quality_index = 1;
        local quality_texts = {}

        for index, quality in pairs(qualities) do               
            table.insert(quality_texts, "[quality=" .. quality.name .. "]")
            if toolbox_options.pick.quality_name == quality.name then
                quality_index = index
            end
        end

        local dropdown = flow.add {            
            type = "drop-down",
            name = toolbox_options.quality_dropdown_name,
            items = quality_texts,
            selected_index = quality_index,
            style = "circuit_condition_comparator_dropdown"
        }

        dropdown.style.margin = {1, 4};
        dropdown.style.height = 38;
        dropdown.style.width = 58;
    end

    for _, pick_name in pairs(toolbox_options.pick.available) do
        local style = "slot_sized_button"

        if pick_name == toolbox_options.pick.selected then
            style = "slot_sized_button_pressed"
        end 

        local button = flow.add {
            type = "choose-elem-button",
            name = toolbox_options.button_prefix .. pick_name,
            elem_type = toolbox_options.type,
            elem_filters = {{filter = "name", name = {pick_name}}},            
            style = style,
            [toolbox_options.type] = pick_name,
        }
        button.locked = true 
    end

    if toolbox_options.optional then
        local style = "slot_sized_button"

        pick_name = "none"

        if toolbox_options.pick.selected == "none" then
            style = "slot_sized_button_pressed"
        end

        flow.add {            
            type = "sprite-button",
            name = toolbox_options.button_prefix .. pick_name,            
            style = style,
            sprite = "utility/hand_black",
            tooltip = {"pump-toolpicker.exclude-option-tooltip"}
        }
    end
end

local function create_toolbox_options(toolbox_name, type, pick, toolbox_entries, optional, failure)
    if failure then
        return {failure = failure}
    end

    local names = {}
    for name, _ in pairs(toolbox_entries) do
        table.insert(names, name)
    end

    return {
        -- "entity", "item", "tile", etc. use for setting up the choose-elem-buttom
        type = type,
        -- The last selection persisted storage. Contains the entity name as well as a list of all available entity names at the time
        -- The list of names is then used to determine of new options are available and the UI should show again 
        pick = pick,
        -- Prefix to uniquely name the buttons in the UI
        button_prefix = "pump_toolbox_picker_button_" .. toolbox_name .. "__",
        -- Prefix to uniquely name the quality dropdown in the UI
        quality_dropdown_name = "pump_toolbox_quality_dropdown__" .. toolbox_name,
        -- Name of the flow containing the button in the UI
        flow_name = "pump_toolbox_picker_flow_" .. toolbox_name,
        
        -- Used in the planner as mod_context.toolbox.<INSERT-toolbox_name-HERE>
        toolbox_name = toolbox_name,
        -- Table keyed on entity-names with content made available via toolbox in the planner.
        toolbox_entries = toolbox_entries,
        -- Available names, can be used as keys for toolbox_entries
        names = names,
        -- Add option to the dialog to not pick anything
        optional = optional
    }
end

local function create_toolbox_extractor_options(player, resource_category)
    local toolbox_entries = {}
    local failure = add_available_extractors(toolbox_entries, resource_category, player)

    return create_toolbox_options(
        "extractor",
        "entity",
        get_extractor_pick_for_resource(resource_category),
        toolbox_entries,
        false,
        failure
    )
end

local function create_toolbox_pipe_options(player)
    local toolbox_entries = {}
    local failure = add_available_pipes(toolbox_entries, player)

    return create_toolbox_options(
        "connector",
        "entity",
        get_pipe_pick(),
        toolbox_entries,
        false,
        failure
    )
end

local function create_toolbox_power_pole_options(player)
    local toolbox_entries = {}
    local pick = get_power_pole_pick()
    local failure = add_available_power_poles(toolbox_entries, player, pick.quality_name)

    return create_toolbox_options(
        "power_pole",
        "entity",
        pick,
        toolbox_entries,
        true,
        failure
    )
end

local function create_toolbox_meltable_tile_cover_options(player)
    local toolbox_entries = {}
    local pick = get_meltable_tile_cover_pick()
    local failure = add_meltable_tile_covers(toolbox_entries)

    return create_toolbox_options(
        "meltable_tile_cover",
        "item",
        pick,
        toolbox_entries,
        false,
        failure
    )
end

local function create_all_toolbox_options(player, resource_category)
    local all_toolbox_options = {}    
    if not storage.toolpicker_config then storage.toolpicker_config = {} end

    table.insert(all_toolbox_options, create_toolbox_extractor_options(player, resource_category))
    table.insert(all_toolbox_options, create_toolbox_pipe_options(player))
    table.insert(all_toolbox_options, create_toolbox_power_pole_options(player))

    if assistant.surface_has_meltable_tiles(player) then
        table.insert(all_toolbox_options, create_toolbox_meltable_tile_cover_options(player))
    end

    return all_toolbox_options
end

local function should_show_always(player)
    local mod_setting_always_show = player.mod_settings["pump-always-show"]
    return mod_setting_always_show.value
end

local function update_toolbox_after_changed_options(current_action, player, toolbox_name)
    -- Refresh the options. The quality could've changed which would impact things like the wire-range
    local refreshed_all_options = create_all_toolbox_options(player, current_action.resource_category)

    for _, refreshed_option in pairs(refreshed_all_options) do
        if refreshed_option.toolbox_name == toolbox_name then
            if refreshed_option.pick.selected == "none" then
                -- Remove the (optional) selection
                current_action.toolbox[toolbox_name] = nil
            else
                -- Reassign the selected extractor, wire or power pole to the toolbox
                current_action.toolbox[toolbox_name] = refreshed_option.toolbox_entries[refreshed_option.pick.selected]
                if current_action.toolbox[toolbox_name] then
                    current_action.toolbox[toolbox_name].quality_name = refreshed_option.pick.quality_name
                end
            end            
        end
    end   

    current_action.toolbox.pipe_bury_distance_preference = convert_pipe_bury_option_to_distance(get_pipe_bury_option())
end

local function pick_tools(current_action, player, all_toolbox_options, force_ui)
    local selection_required = false
    local new_options_available = false

    for _, options in pairs(all_toolbox_options) do

        -- A mod might've been removed
        reset_selection_if_pick_no_longer_available(options.pick, options.names)

        -- Quality might've changed
        if get_quality_index(options.quality_name) == 0 then
            options.quality_name = nil
        end

        -- Multiple options available, and no previous selection is known.
        selection_required = selection_required or (#options.names > 1 and not options.pick.selected)

        -- There's a selection, and P.U.M.P. can work. But the available tools have changed. 
        new_options_available = new_options_available or (
            options.pick.selected and 
            #options.names > 1 and
            not table.compare(options.pick.available, options.names))

        -- persist the available entities for next time, in order to check when new options have been added in the meantime.
        options.pick.available = options.names

        -- ensure a default selection
        if not options.pick.selected then options.pick.selected = options.names[1] end

        -- Put the picked options in toolbox. 
        -- If the UI doesn't open this is what the planner will work with,
        -- If the UI opens, these will be overwritten when the player changes the selected options
        update_toolbox_after_changed_options(current_action, player, options.toolbox_name)
    end

    if force_ui or selection_required or new_options_available or should_show_always(player) then

        local frame = player.gui.screen.add {
            type = "frame",
            name = "pump_tool_picker_frame",
            direction = "vertical",
            caption = {"pump-toolpicker.title"},
        }
        frame.auto_center = true
        player.opened = frame

        -- Title
        local caption = {"pump-toolpicker.choose-extractor-generic"}

        if not (force_ui or should_show_always(player)) then
            if selection_required then
                caption = {"pump-toolpicker.choose-extractor-unknown-selection"}
            else
                caption = {"pump-toolpicker.choose-extractor-changed-options"}
            end
        end

        local label = frame.add {
            type = "label",
            caption = caption,                        
        }

        label.style.maximal_width = 300
        label.style.single_line = false

        -- Picks

        local innerFrame = frame.add {
            type = "frame",
            name = "all_entity_options",
            direction = "vertical",
            style="inside_shallow_frame",
        }

        function create_flow(options) 
            innerFrame.add {type = "line", style="inside_shallow_frame_with_padding_line"}
            local flow = innerFrame.add {
                type = "flow",
                direction = "horizontal",
                name = options.flow_name
            }
            add_pick_options_to_flow(flow, options)
        end

        for _, options in pairs(all_toolbox_options) do
            if options.type == "entity" then                
                create_flow(options)
            end
        end        

        for _, options in pairs(all_toolbox_options) do
            if options.type == "item" and options.toolbox_name == "meltable_tile_cover" then         
                local label = frame.add {
                    type = "label",
                    caption = {"pump-toolpicker.meltable-tile-cover"},                        
                }                

                innerFrame = frame.add {
                    type = "frame",
                    name = "all_item_options",
                    direction = "vertical",
                    style="inside_shallow_frame",
                }
                create_flow(options)
            end
        end

        frame.add {
            type = "label",
            caption = {"pump-toolpicker.pipe-bury-label"},
            tooltip = {"pump-toolpicker.pipe-bury-tooltip"},
        }

        local pipe_bury_options = {}

        table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-no-minimum"})
        table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-short"})
        table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-long"})
        table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-skip"})

        frame.add { 
            type = "drop-down",
            name = "pump_tool_picker_pipe_bury_distance",                        
            items = pipe_bury_options,
            selected_index = get_pipe_bury_option()
        }

        frame.add {
            type = "checkbox",
            name = "pump_tool_picker_always_show",
            caption = {"pump-toolpicker.always-show"},
            state = should_show_always(player),
            tooltip = {"mod-setting-description.pump-always-show"},
        }                
        
        -- Footer
        local bottom_flow = frame.add {
            type = "flow",
            direction = "horizontal",
        }

        bottom_flow.style.top_padding = 4
        bottom_flow.add {
            type = "button",
            name = "pump_tool_picker_cancel_button",
            caption = {"pump-toolpicker.cancel"},
            style = "back_button"
        }
        local filler = bottom_flow.add{
            type = "empty-widget",
            style = "draggable_space",
            ignored_by_interaction = true,
        }
        filler.style.height = 32
        filler.style.horizontally_stretchable = true
        bottom_flow.add {
            type = "button",
            name = "pump_tool_picker_confirm_button",
            caption = {"pump-toolpicker.confirm"},
            style = "confirm_button"
        }
    end
end

local function add_module_config(toolbox, player)

    local setting = player.mod_settings["pump-interface-with-module-inserter-mod"]

    if setting and setting.value and remote.interfaces["mi"] then
        toolbox.module_config = remote.call("mi", "get_module_config", player.index)
    end

    if not toolbox.module_config then toolbox.module_config = {} end
end

function add_toolbox(current_action, player, force_ui)
    local toolbox = {}
    current_action.toolbox = toolbox

    add_module_config(toolbox, player)

    local all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
    for _, options in pairs(all_toolbox_options) do
        if options.failure then return options.failure end
    end

    pick_tools(current_action, player, all_toolbox_options, force_ui)

end

function close_tool_picker_ui(player, confirmed)
    local frame = player.gui.screen.pump_tool_picker_frame

    if frame then 
        if confirmed then
            player.mod_settings["pump-always-show"] = { value = frame.pump_tool_picker_always_show.state }
        end
        frame.destroy()
    end
end

function handle_gui_element_click(element_name, player)
    local frame = player.gui.screen.pump_tool_picker_frame
    local current_action = storage.current_action

    if frame then    
        local all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
        for _, options in pairs(all_toolbox_options) do

            local pick_name = ""

            if (options.button_prefix .. "none") == element_name then
                pick_name = "none"
            end

            for _, entity_name in pairs(options.names) do

                local element_name_for_entity = options.button_prefix .. entity_name
                if element_name == element_name_for_entity then
                    pick_name = entity_name
                    break
                end
            end

            if pick_name ~= "" then
                -- Store selection (by-ref into global-storage)
                options.pick.selected = pick_name

                -- Update selection option in the UI
                add_pick_options_to_flow(frame["all_" .. options.type .. "_options"][options.flow_name], options)

                update_toolbox_after_changed_options(current_action, player, options.toolbox_name)                
            end
        end
    end
end

function handle_gui_element_quality_selection_change(dropdown_gui_element, player)
    local frame = player.gui.screen.pump_tool_picker_frame
    local current_action = storage.current_action

    if frame then    
        local all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
        for _, options in pairs(all_toolbox_options) do

            if options.quality_dropdown_name == dropdown_gui_element.name then
                options.pick.quality_name = nil
                if dropdown_gui_element.selected_index > 1 then
                    local qualities = get_visible_qualities()
                    options.pick.quality_name = qualities[dropdown_gui_element.selected_index].name
                else
                    options.pick.quality_name = nil
                end

                update_toolbox_after_changed_options(current_action, player, options.toolbox_name)
            end
        end
    end
end

function handle_pipe_bury_preference_change(dropdown_gui_element, player)
    local current_action = storage.current_action
    storage.toolpicker_config.pipe_bury_option = dropdown_gui_element.selected_index   

    update_toolbox_after_changed_options(current_action, player, nil)
end

function is_ui_open(player)
    if player.gui.screen.pump_tool_picker_frame then
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

