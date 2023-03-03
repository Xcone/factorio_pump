require 'util'
local math2d = require 'math2d'
local helpers = require 'helpers'
local xy = helpers.xy

-- Heuristics
local score_adjacent_extractor = 0.45
local score_adjacent_pipe = 0.45
local score_supplying_consumer = 1.5
local score_cardinally_aligned_over_distance = 2
local score_optimal_distance = 2.5
local score_connects_to_other_pole = 5

local initial_search_radius = 1
local pole_count = 0

local function calculate_initial_search_radius(mod_context)
    return math.min(
        6,
        math.ceil(mod_context.toolbox.power_pole.supply_range)
    )
end

local function get_consumer_bounds(consumer_position)
    local bounds = helpers.bounding_box.create(consumer_position, consumer_position) --1x1
    helpers.bounding_box.grow(bounds, 1) --3x3
    return bounds
end

local function get_power_pole_bounds(mod_context, power_pole_position)
    local bounds = helpers.bounding_box.create(power_pole_position, power_pole_position)
    if mod_context.toolbox.power_pole.size > 1 then
        bounds.right_bottom.x = bounds.right_bottom.x + 1
        bounds.right_bottom.y = bounds.right_bottom.y + 1
    end

    return bounds
end

local function get_consumers_in_supply_area(mod_context, power_pole_position, consumers)
    local consumer_positions_in_range = {}
    xy.each(consumers, function(consumer, consumer_position)
        if math2d.bounding_box.contains_point(consumer.pole_in_range_bounds, power_pole_position) then
            table.insert(consumer_positions_in_range, consumer_position)
        end
    end)

    return consumer_positions_in_range
end

local function score_consumer_count(mod_context, score, test_position, unplanned_consumer_positions)    
    score.consumers = #get_consumers_in_supply_area(mod_context, test_position, unplanned_consumer_positions) * score_supplying_consumer
end

local function score_position_to_planned_poles(mod_context, score, test_position, planned_poles)
    local wire_range = mod_context.toolbox.power_pole.wire_range    
    local cardinally_aligned_score = 0
    local distance_closest_pole = -1 
    local has_a_pole = 0

    xy.each(planned_poles, function(pole, pole_position)
        local distance = math2d.position.distance(test_position, pole_position)
        
        if distance <= wire_range and (distance <= distance_closest_pole or distance_closest_pole < 0) then
            distance_closest_pole = distance
            has_a_pole = score_connects_to_other_pole
        end

        if test_position.x == pole_position.x or test_position.y == pole_position.y then
            cardinally_aligned_score = math.min(score_cardinally_aligned_over_distance, ((1 / distance) * wire_range * score_cardinally_aligned_over_distance))
        end
    end)

    score.cardinally_aligned_score = cardinally_aligned_score
    score.distance_score = ((distance_closest_pole / wire_range) * score_optimal_distance) + has_a_pole
end

local function score_adjacent_cells(mod_context, score, position)
    score.adjacent_extractors = 0
    score.adjacent_pipes = 0

    for _, direction in pairs(helpers.directions) do
        local offset_position = math2d.position.add(position, direction.vector)
        local neighbour_cell = xy.get(mod_context.area, offset_position)
        
        if neighbour_cell ~= nil then            
            if neighbour_cell == "reserved-for-pump" then
                score.adjacent_extractors = score.adjacent_extractors + score_adjacent_extractor
            else 
                if neighbour_cell == "construct-pipe" then
                    score.adjacent_pipes = score.adjacent_pipes + score_adjacent_pipe
                end
            end
        end
    end

end

local function score_potential_pole(mod_context, test_position, planned_poles, unplanned_consumer_positions)
    local score = {}

    score_consumer_count(mod_context, score, test_position, unplanned_consumer_positions)
    score_position_to_planned_poles(mod_context, score, test_position, planned_poles)
    score_adjacent_cells(mod_context, score, test_position)

    local total = 0
    for key, value in pairs(score) do
        total = total + value
    end

    score.pole_nr = mod_context.pole_count
    score.total = total   
    score.position = test_position
    return score
end

local function can_build_pole(mod_context, pole_position)
    if mod_context.toolbox.power_pole.size <= 1 then
        return xy.get(mod_context.area, pole_position) == "can-build"
    end

    local result = true

    box = get_power_pole_bounds(mod_context, pole_position)
    helpers.bounding_box.each_grid_position(box, function(position)
        if xy.get(mod_context.area, position) ~= "can-build" then
            result = false
        end
    end)
    return result
end

local function find_pole_position_nearby(mod_context, position, planned_poles, unplanned_consumer_positions)
    local search_area = helpers.bounding_box.create(position, position)
    helpers.bounding_box.grow(search_area, initial_search_radius)
    
    local best_pole_score = {total = -1000};
    local best_pole_position = nil

    local test_position = function (position)
        if can_build_pole(mod_context, position) then
            local score = score_potential_pole(mod_context, position, planned_poles, unplanned_consumer_positions)
            if score.total > best_pole_score.total then
                best_pole_position = position
                best_pole_score = score
            end
        end
    end

    helpers.bounding_box.each_grid_position(search_area, test_position)
    while(best_pole_position == nil) do
        helpers.bounding_box.each_edge_position(search_area, test_position)
        helpers.bounding_box.grow(search_area, 1)
    end

    return best_pole_position
end

local function commit_pole(mod_context, pole_position, planned_poles, unplanned_consumer_positions)
    xy.set(planned_poles, pole_position, {placement_order=pole_count})

    local consumers_in_range = get_consumers_in_supply_area(mod_context, pole_position, unplanned_consumer_positions)
    for _, consumer_position in pairs(consumers_in_range) do
        xy.remove(unplanned_consumer_positions, consumer_position)
    end
    
    pole_count = pole_count + 1    
end

function find_nearby_pole_and_consumer(planned_poles, unplanned_consumer_positions)
    local nearest = nil
    xy.each(planned_poles, function(_, pole_position)
        local current = xy.nearest(unplanned_consumer_positions,  pole_position)
        if nearest == nil or nearest.distance > current.distance then
            nearest = {
                pole_position = pole_position,
                consumer_position = current.position,
                distance = current.distance
            }
        end
    end)

    return nearest
end

function get_next_pole_search_position(mod_context, pole_and_consumer_position)
    if pole_and_consumer_position.distance < mod_context.toolbox.power_pole.wire_range then
        return pole_and_consumer_position.consumer_position
    end

    local pole_position = pole_and_consumer_position.pole_position

    local ideal_pole_position_unaligned = math2d.position.add(
        pole_position, 
        math2d.position.multiply_scalar(
            math2d.position.get_normalised(
                math2d.position.subtract(
                    pole_and_consumer_position.consumer_position,
                    pole_position
                )
            ),
            mod_context.toolbox.power_pole.wire_range - initial_search_radius
        )
    )

    local diff = math2d.position.subtract(ideal_pole_position_unaligned, pole_position)
    diff.x = math.ceil(diff.x)
    if diff.x < 0 then
        diff.x = diff.x - 1
    end
    diff.y = math.ceil(diff.y)
    if diff.y < 0 then
        diff.y = diff.y - 1
    end

    return math2d.position.add(pole_position, diff)
end

function plan_power(mod_context)
    pole_count = 0
    initial_search_radius = calculate_initial_search_radius(mod_context)
    local consumer_positions = {}
    
    xy.each(mod_context.construction_plan, function(planned_entity, position)
        xy.set(mod_context.area, position, "construct-pipe")

        if (planned_entity.name == "extractor") then
            local pole_in_range_bounds = get_consumer_bounds(position)

            helpers.bounding_box.grow(pole_in_range_bounds, mod_context.toolbox.power_pole.supply_range)
            if mod_context.toolbox.power_pole.size > 1 then
                pole_in_range_bounds.left_top.x = pole_in_range_bounds.left_top.x - 1
                pole_in_range_bounds.left_top.y = pole_in_range_bounds.left_top.y - 1
            end

            xy.set(consumer_positions, position, {
                bounds = get_consumer_bounds(position),
                pole_in_range_bounds = pole_in_range_bounds
            })
        end
    end)

    local planned_poles = {}
    local unplanned_consumer_positions = table.deepcopy(consumer_positions)

    local first_consumer = xy.nearest(unplanned_consumer_positions, math2d.bounding_box.get_centre(mod_context.area_bounds))
    local first_pole_position = find_pole_position_nearby(mod_context, first_consumer.position, planned_poles, unplanned_consumer_positions)
    commit_pole(mod_context, first_pole_position, planned_poles, unplanned_consumer_positions)

    local iteration_count = 0

    while(xy.any(unplanned_consumer_positions)) do
        iteration_count = iteration_count + 1
        if iteration_count > 100 then
            pump_log("Planning failure")
            break
        end

        local pole_and_consumer = find_nearby_pole_and_consumer(planned_poles, unplanned_consumer_positions)
        local next_pole_search_position = get_next_pole_search_position(mod_context, pole_and_consumer)
        local next_pole_position = find_pole_position_nearby(mod_context, next_pole_search_position, planned_poles, unplanned_consumer_positions)
        
        commit_pole(mod_context, next_pole_position, planned_poles, unplanned_consumer_positions)
    end


    xy.each(planned_poles, function (pole_plan, position)
        xy.set(mod_context.construction_plan, position, {name="power_pole", direction = defines.direction.north, placement_order = pole_plan.placement_order})
    end)

end