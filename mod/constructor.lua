local helpers = require 'helpers'

function construct_entities(construction_plan, surface, toolbox)
    local entities = get_entities_to_construct(construction_plan)

    for construction_plan_catagory_name, entities_to_place in pairs(entities) do
        local entity_name = nil
        local modules = nil

        if construction_plan_catagory_name == "extractors" then
            entity_name = toolbox.extractor.entity_name
        end

        if construction_plan_catagory_name == "outputs" then
            entity_name = toolbox.connector.entity_name
        end

        if construction_plan_catagory_name == "connectors" then
            entity_name = toolbox.connector.entity_name
        end

        if construction_plan_catagory_name == "connector_joints" then
            entity_name = toolbox.connector.entity_name
        end

        if construction_plan_catagory_name == "connectors_underground" then
            entity_name = toolbox.connector.underground_entity_name
        end

        if entity_name then
            modules = toolbox.module_config[entity_name]
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
end

function get_entities_to_construct(construct_entities)
    local result = {}
    result.extractors = {}
    result.outputs = {}
    result.connectors = {}
    result.connector_joints = {}
    result.connectors_underground = {}

    helpers.xy.each(construct_entities, function(construct_entity, position)

        local target_name = construct_entity.name
        local placement = {
            position = position,
            direction = construct_entity.direction
        }

        if target_name == "pumpjack" then
            table.insert(result.extractors, placement)
        end

        if target_name == "output" then
            table.insert(result.outputs, placement)
        end

        if target_name == "pipe" then
            table.insert(result.connectors, placement)
        end

        if target_name == "pipe_joint" then
            table.insert(result.connector_joints, placement)
        end

        if target_name == "pipe-to-ground" then
            table.insert(result.connectors_underground, placement)
        end
    end)

    return result
end
