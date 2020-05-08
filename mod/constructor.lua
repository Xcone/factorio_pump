local helpers = require 'helpers'

local function get_planned_entities(construction_plan, toolbox)
    local extractors = {}
    local pipes = {}
    local pipe_tunnels = {}

    helpers.xy.each(construction_plan, function(planned_entity, position)

        local planned_entity_name = planned_entity.name
        local placement = {
            position = position,
            direction = planned_entity.direction
        }

        if planned_entity_name == "extractor" then
            table.insert(extractors, placement)
        end

        if planned_entity_name == "output" then
            table.insert(pipes, placement)
        end

        if planned_entity_name == "pipe" then
            table.insert(pipes, placement)
        end

        if planned_entity_name == "pipe_joint" then
            table.insert(pipes, placement)
        end

        if planned_entity_name == "pipe_tunnel" then
            table.insert(pipe_tunnels, placement)
        end
    end)

    return {
        [toolbox.extractor.entity_name] = extractors,
        [toolbox.connector.entity_name] = pipes,
        [toolbox.connector.underground_entity_name] = pipe_tunnels
    }
end

function construct_entities(construction_plan, surface, toolbox)
    local planned_entities = get_planned_entities(construction_plan, toolbox)

    for entity_name, entities_to_place in pairs(planned_entities) do

        local modules = toolbox.module_config[entity_name]
        for i, parameters in pairs(entities_to_place) do
            local ghost = surface.create_entity {
                name = "entity-ghost",
                inner_name = entity_name,
                position = parameters.position,
                direction = parameters.direction,
                force = "player"
            }

            if modules then ghost.item_requests = modules end
        end
    end
end
