require 'toolbox'
require 'util'
local math2d = require 'math2d'
local plib = require 'plib'
local assistant = require 'planner-assistant'

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

local function should_show_always(player)
    local mod_setting_always_show = player.mod_settings["pump-always-show"]
    return mod_setting_always_show.value
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

    for _, pick_name in pairs(toolbox_options.names) do
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

local function add_module_options_to_flow(flow, toolbox_options)
    flow.clear()    
    local qualities = get_visible_qualities()

    if toolbox_options.modules_pick and next(toolbox_options.modules_pick.available) then
        local module_names = {}
        for name, _ in pairs(toolbox_options.modules_pick.available) do
            table.insert(module_names, name)
        end

        local quality_index = 1;
        local quality_texts = {}

        for index, quality in pairs(qualities) do               
            table.insert(quality_texts, "[quality=" .. quality.name .. "]")
            if toolbox_options.modules_pick.quality_name == quality.name then
                quality_index = index
            end
        end

        local dropdown = flow.add {            
            type = "drop-down",
            name = toolbox_options.quality_dropdown_name .. "module_pick",
            items = quality_texts,
            selected_index = quality_index,
            style = "circuit_condition_comparator_dropdown"
        }

        dropdown.style.margin = {1, 4};
        dropdown.style.height = 38;
        dropdown.style.width = 58;

        local module_elem = flow.add {
            type = "choose-elem-button",
            name = toolbox_options.button_prefix .. "module_pick",
            elem_type = "item",
            elem_filters = {{filter = "name", name = module_names}},
            style = "slot_sized_button",
        }
        if toolbox_options.modules_pick.selected then
            module_elem.elem_value = toolbox_options.modules_pick.selected
        end
    else
        -- Reserve space to keep the options between frames aligned
        local spacer = flow.add {
            type = "empty-widget",
            style = "draggable_space",
            ignored_by_interaction = true,
        }
        spacer.style.height = 38
        spacer.style.vertically_stretchable = true
    end
end

local function add_ui_content(options_holder, all_toolbox_options, player)
    -- Create a horizontal flow to hold both frames
    local main_flow = options_holder.add {
        type = "flow",
        name = "main_horizontal_flow",
        direction = "horizontal"
    }

    local left_frame = main_flow.add {
        type = "frame",
        name = "all_entity_options",
        direction = "vertical",
        style = "inside_shallow_frame",
    }
    
    local right_frame = main_flow.add {
        type = "frame",
        name = "right_options_frame",
        direction = "vertical",
        style = "inside_shallow_frame",
    }

    function create_flow(options, options_frame, modules_frame)
        options_frame.add {type = "line", style = "inside_shallow_frame_with_padding_line"}
        add_pick_options_to_flow(options_frame.add {
            type = "flow",
            direction = "horizontal",
            name = options.flow_name
        }, options)

        if modules_frame then
            modules_frame.add {type = "line", style = "inside_shallow_frame_with_padding_line"}
            add_module_options_to_flow(modules_frame.add {
                type = "flow",
                direction = "horizontal",
                name = options.flow_name
            }, options)
        end
    end

    for _, options in pairs(all_toolbox_options) do
        if options.type == "entity" and #options.names > 0 then
            create_flow(options, left_frame, right_frame)
        end
    end

    for _, options in pairs(all_toolbox_options) do
        if options.type == "item" and options.toolbox_name == "meltable_tile_cover" and #options.names > 0 then
            local label = options_holder.add {
                type = "label",
                caption = {"pump-toolpicker.meltable-tile-cover"},
            }

            local meltable_tile_cover_options_frame = options_holder.add {
                type = "frame",
                name = "meltable_tile_cover_options",
                direction = "vertical",
                style = "inside_shallow_frame",
            }
            create_flow(options, meltable_tile_cover_options_frame)
        end
    end

    options_holder.add {
        type = "label",
        caption = {"pump-toolpicker.pipe-bury-label"},
        tooltip = {"pump-toolpicker.pipe-bury-tooltip"},
    }

    local pipe_bury_options = {}
    table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-no-minimum"})
    table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-short"})
    table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-long"})
    table.insert(pipe_bury_options, {"pump-toolpicker.pipe-bury-skip"})

    options_holder.add {
        type = "drop-down",
        name = "pump_tool_picker_pipe_bury_distance",
        items = pipe_bury_options,
        selected_index = get_pipe_bury_option()
    }
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

        local options_holder = frame.options_holder or frame.add {
            type = "flow",
            name = "options_holder",
            direction = "vertical"
        }        
        add_ui_content(options_holder, all_toolbox_options, player)              
        
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

function add_toolbox(current_action, player, force_ui)
    local toolbox = {}
    current_action.toolbox = toolbox    

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
                update_toolbox_after_changed_options(current_action, player, options.toolbox_name)
            end
        end
        -- Only refresh options_holder if element_name does NOT contain 'module_pick'
        if not string.find(element_name, "module_pick", 1, true) then
            local options_holder = frame["options_holder"]
            if options_holder then
                options_holder.clear()
                all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
                add_ui_content(options_holder, all_toolbox_options, player)
            end
        end
    end
end

function handle_gui_element_quality_selection_change(dropdown_gui_element, player)
    local frame = player.gui.screen.pump_tool_picker_frame
    local current_action = storage.current_action

    if frame then    
        local all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
        local qualities = get_visible_qualities()
        for _, options in pairs(all_toolbox_options) do
            -- Main entity quality dropdown
            if options.quality_dropdown_name == dropdown_gui_element.name then
                options.pick.quality_name = nil
                if dropdown_gui_element.selected_index > 1 then                    
                    options.pick.quality_name = qualities[dropdown_gui_element.selected_index].name
                end
                update_toolbox_after_changed_options(current_action, player, options.toolbox_name)
            end
            -- Module quality dropdown
            if options.modules_pick and (options.quality_dropdown_name .. "module_pick") == dropdown_gui_element.name then
                options.modules_pick.quality_name = nil
                if dropdown_gui_element.selected_index > 1 then
                    options.modules_pick.quality_name = qualities[dropdown_gui_element.selected_index].name
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

function handle_gui_elem_changed(element, player)
    if element and element.valid then
        if element.name and string.find(element.name, "module_pick", 1, true) then
            -- Find the matching toolbox option and update modules_pick.selected
            local current_action = storage.current_action
            if not current_action then return end
            local all_toolbox_options = create_all_toolbox_options(player, current_action.resource_category)
            for _, options in pairs(all_toolbox_options) do
                if options.modules_pick and (options.button_prefix .. "module_pick") == element.name then
                    options.modules_pick.selected = element.elem_value            
                end
            end
        end
    end
end

function is_ui_open(player)
    if player.opened ~= nil and player.gui.screen.pump_tool_picker_frame == player.opened then
        return true
    else
        return false
    end
end
