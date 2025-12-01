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
        },
        needs_heat = true,
    }

    toolbox.connector = {
        entity_name = 'not-used-by-visualizer',
        underground_entity_name = 'not-used-by-visualizer',
        underground_distance_min = 0,
        underground_distance_max = 9,
        needs_heat = true,
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

    toolbox.beacon = {
        entity_name = 'not-used-by-visualizer',
        effect_radius = 4,
        relative_bounds = { left_top = {x = -1, y = -1}, right_bottom = {x = 1, y = 1} },
        quality_name = 'normal',
        needs_heat = true,
    }

    toolbox.heat_pipe = {
        entity_name = 'not-used-by-visualizer',
        quality_name = 'normal',
        needs_heat = false,
    }

    -- toolbox.power_pole = small_pole
    toolbox.power_pole = medium_pole
    -- toolbox.power_pole = big_pole
    -- toolbox.power_pole = substation
    toolbox.pipe_bury_distance_preference = 1


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
        local place_result = item.place_as_tile_result     

        local can_cover_meltable_tile = not place_result.condition.layers["meltable"]
        if place_result.invert then
            can_cover_meltable_tile = not can_cover_meltable_tile
        end

        local requires_specific_tiles = next(item.place_as_tile_result.tile_condition) ~= nil

        if can_cover_meltable_tile and not requires_specific_tiles then
            meltable_tile_covers[item.name] = { item_name = item.name }
        end
    end
end

local function add_available_beacons(available_beacons, player, quality_name)
    local all_beacons = prototypes.get_entity_filtered({{filter = "type", type = "beacon"}})
    for _, beacon in pairs(all_beacons) do
        if meets_tech_requirement(beacon, player) then
            local collision_box = math2d.bounding_box.ensure_xy(beacon.collision_box)
            local relative_bounds = {
                left_top = {x = math.ceil(collision_box.left_top.x), y = math.ceil(collision_box.left_top.y)},
                right_bottom = {x = math.floor(collision_box.right_bottom.x), y = math.floor(collision_box.right_bottom.y)}
            }

            available_beacons[beacon.name] = {
                entity_name = beacon.name,
                effect_radius = beacon.get_supply_area_distance and beacon.get_supply_area_distance(quality_name),
                relative_bounds = relative_bounds
            }
        end
    end    
end

local function add_available_heat_pipes(available_heat_pipes, player)
    local all_heat_pipes = prototypes.get_entity_filtered({{filter = "type", type = "heat-pipe"}})
    for _, heat_pipe in pairs(all_heat_pipes) do
        if meets_tech_requirement(heat_pipe, player) then
            available_heat_pipes[heat_pipe.name] = {
                entity_name = heat_pipe.name
            }
        end
    end
    if next(available_heat_pipes) == nil then return {"failure.no-heat-pipe"} end
end

local function get_allowed_modules(prototype, player)
    local allowed = {}
    if not prototype.module_inventory_size or prototype.module_inventory_size == 0 then
        return allowed
    end
    for _, module in pairs(prototypes.get_item_filtered({{filter = "type", type = "module"}})) do
        local module_allowed = true
        -- Check research requirements
        if not meets_tech_requirement(module, player) then
            module_allowed = false
        end
        -- Check allowed module categories
        if module_allowed and prototype.allowed_module_categories and not prototype.allowed_module_categories[module.category] then
            module_allowed = false
        end
        -- Check allowed effects
        if module_allowed and module.module_effects then
            for effect_name, effect_value in pairs(module.module_effects) do
                if effect_value > 0 then
                    if prototype.allowed_effects and not prototype.allowed_effects[effect_name] then
                        module_allowed = false
                        break
                    end
                end
            end
        end
        if module_allowed then
            table.insert(allowed, module.name)
        end
    end
    return allowed
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

local function get_beacon_pick()
    if not storage.toolpicker_config.beacon_pick then
        storage.toolpicker_config.beacon_pick = {selected = nil, available = {}, quality_name = nil}
    end
    return storage.toolpicker_config.beacon_pick
end

local function get_heat_pipe_pick()
    if not storage.toolpicker_config.heat_pipe_pick then
        storage.toolpicker_config.heat_pipe_pick = {selected = nil, available = {}, quality_name = nil}
    end
    return storage.toolpicker_config.heat_pipe_pick
end

function get_pipe_bury_option()
    if not storage.toolpicker_config.pipe_bury_option then
        storage.toolpicker_config.pipe_bury_option = 1
    end

    return storage.toolpicker_config.pipe_bury_option
end

local function get_module_pick(entity_name)
    if not storage.toolpicker_config.module_pick then
        storage.toolpicker_config.module_pick = {}
    end
    if not storage.toolpicker_config.module_pick[entity_name] then
        storage.toolpicker_config.module_pick[entity_name] = {selected = nil, available = {}}
    end
    return storage.toolpicker_config.module_pick[entity_name]
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

function reset_selection_if_pick_no_longer_available(pick, available)
    if pick.selected ~= "none" then
        if not table.contains(available, pick.selected) then pick.selected = nil; end
    end
end

-- Add needs_heat property to each toolbox entry in create_toolbox_options
local function create_toolbox_options(toolbox_name, type, pick, toolbox_entries, optional_behavior, failure, modules_inventory_define, player, needs_heat)
    if failure then
        return {failure = failure}
    end

    local names = {}
    for name, entry in pairs(toolbox_entries) do
        table.insert(names, name)
        entry.needs_heat = needs_heat
    end

    -- A mod might've been removed
    reset_selection_if_pick_no_longer_available(pick, names)

     -- Quality might've changed
     if get_quality_index(pick.quality_name) == 0 then
        pick.quality_name = nil
    end

    -- Multiple options available, and no previous selection is known.
    local selection_required = (#names > 1 and not pick.selected)

    -- There's a selection, and P.U.M.P. can work. But the available tools have changed. 
    local new_options_available = pick.selected and 
        #names > 1 and
        not table.compare(pick.available, names)

    -- persist the available entities for next time, in order to check when new options have been added in the meantime.
    pick.available = names

    -- ensure a default selection
    if not pick.selected then
        if optional_behavior and optional_behavior.is_optional and optional_behavior.default_is_none then
            pick.selected = "none"
        else
            pick.selected = names[1]
        end
    end

    local modules_pick = nil    
    if type == "entity" and pick.selected ~= "none" and not assistant.use_module_inserter_ex(player) then        

        modules_pick = get_module_pick(pick.selected)        
        modules_pick.available = get_allowed_modules(prototypes.entity[pick.selected], player)
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
        optional = optional_behavior and optional_behavior.is_optional or false,
        -- If this option allows for modules, this will be a table of module names
        modules_pick = modules_pick,
        -- The inventory to add modules to
        modules_inventory_define = modules_inventory_define,
        -- Should prompt the user for a selection. This can be because the selection was never made. Or because a mod was removed.
        selection_required = selection_required,
        -- Whether new options are available. This can be because a mod was added or research was completed.
        new_options_available = new_options_available
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
        { is_optional = false, default_is_none = false },
        failure,
        defines.inventory.mining_drill_modules,
        player,
        true
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
        { is_optional = false, default_is_none = false },
        failure,
        nil,
        player,
        true
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
        { is_optional = true, default_is_none = false },
        failure,
        nil,
        player,
        true
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
        { is_optional = false, default_is_none = false },
        failure,
        nil,
        player,
        true
    )
end

local function create_toolbox_beacon_options(player)
    local toolbox_entries = {}
    local pick = get_beacon_pick()
    local failure = add_available_beacons(toolbox_entries, player, pick.quality_name)
    return create_toolbox_options(
        "beacon",
        "entity",
        pick,
        toolbox_entries,
        { is_optional = true, default_is_none = true },
        failure,
        defines.inventory.beacon_modules,
        player,
        true
    )
end

local function create_toolbox_heat_pipe_options(player)
    local toolbox_entries = {}
    local pick = get_heat_pipe_pick()
    local failure = add_available_heat_pipes(toolbox_entries, player)
    return create_toolbox_options(
        "heat_pipe",
        "entity",
        pick,
        toolbox_entries,
        { is_optional = true, default_is_none = false },
        failure,
        nil,
        player,
        false
    )
end

function create_all_toolbox_options(player, resource_category)
    local all_toolbox_options = {}    
    if not storage.toolpicker_config then storage.toolpicker_config = {} end

    table.insert(all_toolbox_options, create_toolbox_extractor_options(player, resource_category))
    table.insert(all_toolbox_options, create_toolbox_pipe_options(player))
    table.insert(all_toolbox_options, create_toolbox_power_pole_options(player))
    table.insert(all_toolbox_options, create_toolbox_beacon_options(player))

    if assistant.surface_has_meltable_tiles(player) then
        table.insert(all_toolbox_options, create_toolbox_heat_pipe_options(player))
        table.insert(all_toolbox_options, create_toolbox_meltable_tile_cover_options(player))
    end

    dump_to_file(all_toolbox_options, "all_toolbox_options")

    return all_toolbox_options
end

function update_toolbox_after_changed_options(current_action, player, toolbox_name)
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
                    -- Add module selection if present
                    if refreshed_option.modules_pick and refreshed_option.modules_pick.selected then
                        current_action.toolbox[toolbox_name].module = refreshed_option.modules_pick.selected
                        current_action.toolbox[toolbox_name].module_quality_name = refreshed_option.modules_pick.quality_name                        
                        current_action.toolbox[toolbox_name].modules_inventory_define = refreshed_option.modules_inventory_define
                    end
                end
            end            
        end
    end   

    current_action.toolbox.pipe_bury_distance_preference = convert_pipe_bury_option_to_distance(get_pipe_bury_option())
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

