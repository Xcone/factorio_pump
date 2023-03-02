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

local function score_consumer_count(mod_context, score, pole)
    if pole == nil then 
        return 0 
    end

    score.consumers = pole.consumer_count * score_supplying_consumer
end

local function score_position_to_planned_poles(mod_context, score, test_position, planned_poles)
    local wire_range = mod_context.toolbox.power_pole.wire_range    
    local cardinally_aligned_score = 0
    local distance_closest_pole = -1

    xy.each(planned_poles, function(pole, pole_position)
        local distance = math2d.position.distance(test_position, pole_position)       
        
        if distance <= wire_range and (distance <= distance_closest_pole or distance_closest_pole < 0) then
            distance_closest_pole = distance
        end

        if test_position.x == pole_position.x or test_position.y == pole_position.y then
            cardinally_aligned_score = math.min(score_cardinally_aligned_over_distance, ((1 / distance) * wire_range * score_cardinally_aligned_over_distance))
        end
    end)

    score.cardinally_aligned_score = cardinally_aligned_score
    score.distance_score = (distance_closest_pole / wire_range) * score_optimal_distance
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

local function score_potential_pole(mod_context, position, pole_consumer_reach, planned_poles)
    local score = {}
    score_consumer_count(mod_context, score, pole_consumer_reach)
    score_position_to_planned_poles(mod_context, score, position, planned_poles)
    score_adjacent_cells(mod_context, score, position)

    local total = 0
    for key, value in pairs(score) do
        total = total + value
    end

    score.pole_nr = mod_context.pole_count
    score.total = total   
    score.position = position
    return score
end

local function get_power_pole_bounds_for_consumer(mod_context, consumer_position)
    -- Ceil to whole number, because 1-tile sizes power poles have a half-tile extra range to reach the edge of the tile.
    -- P.U.M.P. assumes full-tiles anyway, so that not the kind of precision we need.
    local supply_range = math.floor(mod_context.toolbox.power_pole.supply_range);

    -- Add 1 more for the size of the pump
    supply_range = supply_range + 1;

    return {
         left_top = math2d.position.add(consumer_position, {x=-supply_range, y=-supply_range}),
         right_bottom = math2d.position.add(consumer_position, {x=supply_range, y=supply_range})
    }
end

local function map_possible_consumer_power_pole_positions(mod_context, consumer_positions) 
    -- Produces an XY table; each entry containing a power_pole position with at least 1 consumer
    -- Additionally, each entry tracks which consumers it can provide for.
    local power_poles_with_consumers_in_range = {}

    -- Iterate all positions around each consumer that are in the supply range of the power_pole    
    xy.each(consumer_positions, function (_, consumer_position)
        local pole_position_area = get_power_pole_bounds_for_consumer(mod_context, consumer_position)

        helpers.bounding_box.each_grid_position(pole_position_area, function(power_pole_position)
            if xy.get(mod_context.area, power_pole_position) == "can-build" then
                local power_pole_with_consumer = xy.get(power_poles_with_consumers_in_range, power_pole_position)
                if power_pole_with_consumer == nil then
                    power_pole_with_consumer = {consumer_count = 0, consumer_positions = {}}
                end
                power_pole_with_consumer.consumer_count = power_pole_with_consumer.consumer_count + 1;
                table.insert(power_pole_with_consumer.consumer_positions, consumer_position);
                xy.set(power_poles_with_consumers_in_range, power_pole_position, power_pole_with_consumer)
            end
        end)
    end)

    return power_poles_with_consumers_in_range;
end

local function initial_search_radius(mod_context)
    return math.floor(mod_context.toolbox.power_pole.supply_range)
end

local function find_pole_position_nearby(mod_context, position, planned_poles, pole_to_consumer_reach)
    local search_area = helpers.bounding_box.create(position, position)
    helpers.bounding_box.grow(search_area, initial_search_radius(mod_context))
    
    local best_pole_score = {total = 0};
    local best_pole_position = nil

    local test_position = function (position)
        if xy.get(mod_context.area, position) == "can-build" then
            local pole = xy.get(pole_to_consumer_reach, position)
            local score = score_potential_pole(mod_context, position, pole, planned_poles)
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

local function remove_consumers_in_reach(mod_context, pole_to_consumer_reach, placed_pole_position, unplanned_consumer_positions)
    local reachable_consumers_by_placed_pole = xy.get(pole_to_consumer_reach, placed_pole_position)
    if reachable_consumers_by_placed_pole then
        for _, consumer_position in pairs(reachable_consumers_by_placed_pole.consumer_positions) do
            local pole_position_area = get_power_pole_bounds_for_consumer(mod_context, consumer_position);
            xy.remove(unplanned_consumer_positions, consumer_position)

            helpers.bounding_box.each_grid_position(pole_position_area, function (power_pole_position)
                local power_pole = xy.get(pole_to_consumer_reach, power_pole_position)
                if (power_pole ~= nil) then
                    for key, pole_consumer_position in pairs(power_pole.consumer_positions) do
                        if consumer_position.x == pole_consumer_position.x and consumer_position.y == pole_consumer_position.y then
                            power_pole.consumer_positions[key] = nil
                            power_pole.consumer_count = power_pole.consumer_count - 1
                            if power_pole.consumer_count == 0 then
                                xy.remove(pole_to_consumer_reach, power_pole_position)
                            end
                        end
                    end
                end
            end)
        end
    end
end

local function commit_pole(mod_context, pole_position, planned_poles, pole_to_consumer_reach, unplanned_consumer_positions)
    xy.set(planned_poles, pole_position, {group=mod_context.pole_count})
    remove_consumers_in_reach(mod_context, pole_to_consumer_reach, pole_position, unplanned_consumer_positions)
    mod_context.pole_count = mod_context.pole_count + 1;
    
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
            mod_context.toolbox.power_pole.wire_range - initial_search_radius(mod_context)
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
    mod_context.pole_count = 0
    local consumer_positions = {}
    
    xy.each(mod_context.construction_plan, function(planned_entity, position)
        xy.set(mod_context.area, position, "construct-pipe")

        if (planned_entity.name == "extractor") then
            xy.set(consumer_positions, position, {--[[Maybe add some info later?]]})
        end
    end)

    local planned_poles = {}
    local unplanned_consumer_positions = table.deepcopy(consumer_positions)
    local pole_to_consumer_reach = map_possible_consumer_power_pole_positions(mod_context, consumer_positions)

    local first_consumer = xy.nearest(unplanned_consumer_positions, math2d.bounding_box.get_centre(mod_context.area_bounds))
    local first_pole_position = find_pole_position_nearby(mod_context, first_consumer.position, planned_poles, pole_to_consumer_reach)
    commit_pole(mod_context, first_pole_position, planned_poles, pole_to_consumer_reach, unplanned_consumer_positions)


    local iteration_count = 0

    while(xy.any(unplanned_consumer_positions)) do
        iteration_count = iteration_count + 1
        if iteration_count > 100 then
            return "Planning failure"
        end

        local pole_and_consumer = find_nearby_pole_and_consumer(planned_poles, unplanned_consumer_positions)
        local next_pole_search_position = get_next_pole_search_position(mod_context, pole_and_consumer)
        local next_pole_position = find_pole_position_nearby(mod_context, next_pole_search_position, planned_poles, pole_to_consumer_reach)
        
        commit_pole(mod_context, next_pole_position, planned_poles, pole_to_consumer_reach, unplanned_consumer_positions)        
    end


    xy.each(planned_poles, function (pole_plan, position)
        xy.set(mod_context.construction_plan, position, {name="power_pole", direction = defines.direction.north, group = pole_plan.group})
    end)
end