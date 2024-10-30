local plib = require 'plib'

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

    plib.xy.each(construction_plan, function(planned_entity, position)

        local planned_entity_name = planned_entity.name
        local placement = {
            position = position,
            direction = planned_entity.direction,
            deconstruct_area = {
                left_top = {x = position.x - 1, y = position.y - 1},
                right_bottom = {x = position.x + 1, y = position.y + 1}
            }
        }

        if planned_entity_name == "extractor" then
            local extractor_bounds = toolbox.extractor.relative_bounds;
            placement.deconstruct_area =
                {
                    left_top = {
                        x = position.x + extractor_bounds.left_top.x - 1,
                        y = position.y + extractor_bounds.left_top.y - 1
                    },
                    right_bottom = {
                        x = position.x + extractor_bounds.right_bottom.x + 1,
                        y = position.y + extractor_bounds.right_bottom.y + 1
                    }
                }
            placement.quality_name = toolbox.extractor.quality_name
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
            table.insert(power_poles, placement)
        end
        
    end)

    local result = {
        [toolbox.extractor.entity_name] = extractors,
        [toolbox.connector.entity_name] = pipes,
        [toolbox.connector.underground_entity_name] = pipe_tunnels,
    }

    if toolbox.power_pole ~= nil then
        result[toolbox.power_pole.entity_name] = power_poles
    end

    return result
end

function construct_entities(construction_plan, player, toolbox)
    local planned_entities = get_planned_entities(construction_plan, toolbox)

    for _, entities_to_place in pairs(planned_entities) do
        for i, parameters in pairs(entities_to_place) do
            local entities_to_remove = player.surface.find_entities(
                                           parameters.deconstruct_area);
            for i, entity in pairs(entities_to_remove) do
                entity.order_deconstruction(player.force)
            end
        end
    end

    for entity_name, entities_to_place in pairs(planned_entities) do
        local modules = toolbox.module_config[entity_name]
        for i, parameters in pairs(entities_to_place) do
            local ghost = player.surface.create_entity {
                name = "entity-ghost",
                inner_name = entity_name,
                position = parameters.position,
                direction = parameters.direction,
                force = player.force,
                player = player,
                quality = parameters.quality_name
            }

            if modules then ghost.item_requests = modules end

            -- raise built event so other mods can detect the new ghost
            script.raise_script_built{entity=ghost}
        end
    end
end
