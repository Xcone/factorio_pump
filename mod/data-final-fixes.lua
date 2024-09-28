require("toolbox")

local resource_category_map = get_resource_category_map_from_data()
log("Map of which extractors are usable for each fluid type:")
log(serpent.block(resource_category_map, {sparse = true}))

local distinct_fluids = {}
for resource_category, fluids_and_extractors in pairs(resource_category_map) do
    for _, fluid in pairs(fluids_and_extractors.fluids) do
        distinct_fluids[fluid] = true
    end
end

local fluids_that_can_be_extracted = {}
for fluid, _ in pairs(distinct_fluids) do
    table.insert(fluids_that_can_be_extracted, fluid)
end

local pumpSelectionTool = data.raw["selection-tool"]["pump-selection-tool"]

pumpSelectionTool.select.entity_filters = fluids_that_can_be_extracted
pumpSelectionTool.alt_select = pumpSelectionTool.select
pumpSelectionTool.super_forced_select = nil
pumpSelectionTool.reverse_select = nil

