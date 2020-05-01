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

function add_toolbox(target, resource_category)
    local toolbox = {}

    local all_extractors = game.get_filtered_entity_prototypes(
                               {{filter = "type", type = "mining-drill"}})
    local suitable_extractors = {}
    for _, extractor in pairs(all_extractors) do
        if extractor.resource_categories[resource_category] then
            table.insert(suitable_extractors, extractor)
        end
    end

    for _, extractor in pairs(suitable_extractors) do
        toolbox.extractor = {
            entity_name = extractor.name,
            output_offsets = {
                [defines.direction.north] = {x = 1, y = -2},
                [defines.direction.east] = {x = 2, y = -1},
                [defines.direction.south] = {x = -1, y = 2},
                [defines.direction.west] = {x = -2, y = 1}
            }
        }

        break
    end

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

