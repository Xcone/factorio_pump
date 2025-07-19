local math2d = require 'math2d'
local plib = require 'plib'
local assistant = require 'planner-assistant'


local function expand_box(box, amount)
    box.left_top.x = box.left_top.x - amount
    box.left_top.y = box.left_top.y - amount
    box.right_bottom.x = box.right_bottom.x + amount
    box.right_bottom.y = box.right_bottom.y + amount
end

local function get_planned_entities(construction_plan, toolbox)
    local extractors = {}
    local pipes = {}
    local pipe_tunnels = {}
    local power_poles = {}
    local beacons = {}

    plib.xy.each(construction_plan, function(planned_entity, position)

        local planned_entity_name = planned_entity.name
        local placement = {
            position = position,
            direction = planned_entity.direction,
            deconstruct_area = {
                left_top = {x = position.x - 1, y = position.y - 1},
                right_bottom = {x = position.x + 1, y = position.y + 1}
            },
            cover_area = plib.bounding_box.create(position, position)
        }

        local function add_areas_to_placement(placement, relative_bounds, position)
            placement.deconstruct_area = plib.bounding_box.offset(relative_bounds, position);
            plib.bounding_box.grow(placement.deconstruct_area, 1)
            placement.cover_area = plib.bounding_box.offset(relative_bounds, position)
        end

        if planned_entity_name == "extractor" then
            add_areas_to_placement(placement, toolbox.extractor.relative_bounds, position)
            placement.quality_name = toolbox.extractor.quality_name
            if toolbox.extractor.module then
                placement.module = toolbox.extractor.module
                placement.module_quality_name = toolbox.extractor.module_quality_name                
                placement.modules_inventory_define = toolbox.extractor.modules_inventory_define                
            end
            table.insert(extractors, placement)
        end

        if planned_entity_name == "output" then
            placement.quality_name = toolbox.connector.quality_name
            table.insert(pipes, placement)
        end

        if planned_entity_name == "pipe" then
            placement.quality_name = toolbox.connector.quality_name
            table.insert(pipes, placement)
        end

        if planned_entity_name == "pipe_joint" then
            placement.quality_name = toolbox.connector.quality_name
            table.insert(pipes, placement)
        end

        if planned_entity_name == "pipe_tunnel" then
            placement.quality_name = toolbox.connector.quality_name
            table.insert(pipe_tunnels, placement)
        end

        if planned_entity_name == "power_pole" then            
            placement.quality_name = toolbox.power_pole.quality_name
            local size = toolbox.power_pole.size
            if (size == 2) then
                placement.cover_area = plib.bounding_box.create(position, math2d.position.add(position, {x=1, y=1}))
            end       
            
            table.insert(power_poles, placement)
        end

        if planned_entity_name == "beacon" then
            add_areas_to_placement(placement, toolbox.beacon.relative_bounds, position)

            placement.quality_name = toolbox.beacon.quality_name
            if toolbox.beacon.module then
                placement.module = toolbox.beacon.module
                placement.module_quality_name = toolbox.beacon.module_quality_name
                placement.modules_inventory_define = toolbox.beacon.modules_inventory_define
            end

            table.insert(beacons, placement)
        end
        
    end)

    local result = {
        [toolbox.extractor.entity_name] = extractors,
        [toolbox.connector.entity_name] = pipes,
        [toolbox.connector.underground_entity_name] = pipe_tunnels,
        ["beacon"] = beacons,
    }

    if toolbox.power_pole ~= nil then
        result[toolbox.power_pole.entity_name] = power_poles
    end

    return result
end

local function cover(player, cover_area, tile_name_when_cover_is_meltable)
    plib.bounding_box.each_grid_position(cover_area, function(tile_position) 
        local tile_prototype = player.surface.get_tile(tile_position.x, tile_position.y).prototype;
        local foundation_prototype = tile_prototype.default_cover_tile
        if foundation_prototype ~= nil then        
            player.surface.create_entity {
                name = "tile-ghost",
                inner_name = foundation_prototype.name,
                position = tile_position,
                force = player.force,
                player = player           
            }
    
            tile_prototype = foundation_prototype
        end

        if tile_prototype.collision_mask.layers.meltable and tile_name_when_cover_is_meltable then            
            player.surface.create_entity {
                name = "tile-ghost",
                inner_name = tile_name_when_cover_is_meltable,
                position = tile_position,
                force = player.force,
                player = player           
            }           
        end          
    end )    
end

local function add_modules(ghosts, player) 
    local setting = player.mod_settings["pump-interface-with-module-inserter-mod"]

    if setting and setting.value and remote.interfaces["ModuleInserterEx"] then
        remote.call("ModuleInserterEx", "apply_module_config_to_entities", player.index, ghosts)
    end
end

function construct_entities(construction_plan, player, toolbox)
    local planned_entities = get_planned_entities(construction_plan, toolbox)

    for entity_name, entities_to_place in pairs(planned_entities) do
        local mask = prototypes.entity[entity_name].collision_mask.layers
        for i, parameters in pairs(entities_to_place) do
            local entities_to_remove = player.surface.find_entities_filtered({
                area = parameters.deconstruct_area, 
                collision_mask = mask
            });
            for i, entity in pairs(entities_to_remove) do
                entity.order_deconstruction(player.force, player)
            end
        end
    end

    local tile_name_when_cover_is_meltable = nil

    if assistant.surface_has_meltable_tiles(player) then                    
        tile_name_when_cover_is_meltable = prototypes.item[toolbox.meltable_tile_cover.item_name].place_as_tile_result.result.name
    end  

    local entity_ghosts = {}

    for entity_name, entities_to_place in pairs(planned_entities) do
        for i, parameters in pairs(entities_to_place) do
            cover(player, parameters.cover_area, tile_name_when_cover_is_meltable)

            local ghost = player.surface.create_entity {
                name = "entity-ghost",
                inner_name = entity_name,
                position = parameters.position,
                direction = parameters.direction,
                force = player.force,
                player = player,
                quality = parameters.quality_name
            }

            -- Add module request to the ghost if module is specified
            if parameters.module then
                local module_count = ghost.ghost_prototype.module_inventory_size
                local insert_plan = ghost.insert_plan
                for i = 1, module_count do
                    table.insert(insert_plan, {
                        id = { name= parameters.module, quality = parameters.module_quality_name },
                        items = {
                            in_inventory = {{
                                inventory = parameters.modules_inventory_define,
                                stack = i - 1,
                                count = 1,
                            }}
                        }
                    })
                end
                
                ghost.insert_plan = insert_plan
            end

            table.insert(entity_ghosts, ghost)

            -- raise built event so other mods can detect the new ghost
            script.raise_script_built{entity=ghost}
        end

        add_modules(entity_ghosts, player)
    end
end
