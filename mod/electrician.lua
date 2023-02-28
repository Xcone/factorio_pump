require 'util'
local math2d = require 'math2d'
local helpers = require 'helpers'
local xy = helpers.xy


-- Heuristics
local score_adjacent_extractor = 0.55
local score_adjacent_pipe = 0.55
local max_adjacent_score = math.max(score_adjacent_extractor, score_adjacent_pipe) * 4

local function score_consumer_count(pole)
    local consumer_weight = 1;
    return pole.consumer_count * consumer_weight
end

local function score_in_range_of_nearby_pole(mod_context, position, nearby_pole_position)
    local wire_range = mod_context.toolbox.power_pole.wire_range

    if nearby_pole_position ~= nil then
        if math2d.position.distance(position, nearby_pole_position) <= wire_range then
            return 1
        end
    end

    return 0
end

local function score_adjacent_cells(mod_context, position)    
    local score = 0

    for _, direction in pairs(helpers.directions) do
        local offset_position = math2d.position.add(position, direction.vector)
        local neighbour_cell = xy.get(mod_context.area, offset_position)
        
        if neighbour_cell ~= nil then            
            if neighbour_cell == "reserved-for-pump" then
                score = score + score_adjacent_extractor
            else 
                if neighbour_cell == "construct-pipe" then
                    score = score + score_adjacent_pipe
                end
            end
        end
    end

    return score
end

local function score_potential_pole(mod_context, pole, position, nearby_pole_position, score_to_beat)
    local score = score_consumer_count(pole)
    score = score + score_in_range_of_nearby_pole(mod_context, position, nearby_pole_position)
    if (score + max_adjacent_score) >= score_to_beat then
        score = score + score_adjacent_cells(mod_context, position)
    end

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

local function remove_consumer_from_pole_positions(mod_context, potential_pole_positions, consumer_position)
    local pole_position_area = get_power_pole_bounds_for_consumer(mod_context, consumer_position);

    helpers.bounding_box.each_grid_position(pole_position_area, function (power_pole_position)
        local power_pole = xy.get(potential_pole_positions, power_pole_position)        
        if (power_pole ~= nil) then
            for key, pole_consumer_position in pairs(power_pole.consumer_positions) do
                if consumer_position.x == pole_consumer_position.x and consumer_position.y == pole_consumer_position.y then
                    power_pole.consumer_positions[key] = nil
                    power_pole.consumer_count = power_pole.consumer_count - 1
                    if power_pole.consumer_count == 0 then
                        xy.remove(potential_pole_positions, power_pole_position)
                    end
                end
            end
        end
    end)
end

local function find_next_power_pole(mod_context, potential_pole_positions, pole_groups, remaining_consumers)
    local center = math2d.bounding_box.get_centre(mod_context.area_bounds)

    local nearby_consumer_position = nil
    local nearby_pole_position = nil
    local nearby_pole_group = 0
    local nearest_distance = 99999

    -- Find the consumer that's closest to one of the chosen pole positions
    xy.each(pole_groups.positions, function(pole, pole_position)
        xy.each(remaining_consumers, function(consumer, consumer_position)
            local d = math2d.position.distance(pole_position, consumer_position)
            if d < nearest_distance then
                nearest_distance = d
                nearby_consumer_position = consumer_position
                nearby_pole_position = pole_position
                nearby_pole_group = pole.group
            end
        end)
    end)

    if nearby_consumer_position == nil then
        xy.each(remaining_consumers, function(consumer, consumer_position)
            local d = math2d.position.distance(center, consumer_position)
            if d < nearest_distance then
                nearest_distance = d
                nearby_consumer_position = consumer_position
            end
        end)
    end

    local nearby_consumer_supply_area = get_power_pole_bounds_for_consumer(mod_context, nearby_consumer_position)
    local best_pole_score = 0;
    local best_pole_positions = {}

    helpers.bounding_box.each_grid_position(nearby_consumer_supply_area, function(position)
        local pole = xy.get(potential_pole_positions, position)
        if pole ~= nil then
            local score = score_potential_pole(mod_context, pole, position, nearby_pole_position, best_pole_score)
    
            if ((score) > best_pole_score) then
                best_pole_score = score;
                best_pole_positions = {}
            end

            if (score == best_pole_score) then
                xy.set(best_pole_positions, position, pole)
            end
        end
    end)
        
    local pole_distance_to_center = 99999;    
    local pole_closest_to_center = nil
    local pole_position = nil
    xy.each(best_pole_positions, function(pole, position) 
        local distance = math2d.position.distance(center, position)
        if distance < pole_distance_to_center then
            pole_closest_to_center = pole
            pole_distance_to_center = distance
            pole_position = position
        end
    end)

    if score_in_range_of_nearby_pole(mod_context, pole_position, nearby_pole_position) == 0 then
        pole_groups.group_count = pole_groups.group_count + 1
        pole_closest_to_center.group = pole_groups.group_count
    else
        pole_closest_to_center.group = nearby_pole_group
    end    

    return {pole = pole_closest_to_center, position = pole_position}
end

local function group_power_poles(mod_context, potential_pole_positions, consumer_positions)
    local iterations = 0;
    local pole_groups = {group_count=0, positions={}}

    local remaining_consumers = table.deepcopy(consumer_positions)

    while (xy.any(remaining_consumers) and iterations < 100) do
        iterations = iterations + 1

        local next_pole = find_next_power_pole(mod_context, potential_pole_positions, pole_groups, remaining_consumers)
        
        for _, consumer_position in pairs(next_pole.pole.consumer_positions) do
            remove_consumer_from_pole_positions(mod_context, potential_pole_positions, consumer_position)
            xy.remove(remaining_consumers, consumer_position)
        end

        xy.set(pole_groups.positions, next_pole.position, next_pole.pole)
    
    end

    return pole_groups
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

local function merge_power_pole_groups(mod_context, pole_groups)
    local result = xy.where(pole_groups.positions, function(pole, position) return pole.group == 1 end)
    pole_groups.positions = xy.where(pole_groups.positions, function(pole, position) return pole.group ~= 1 end)
    pole_groups.group_count = pole_groups.group_count - 1

    while pole_groups.group_count > 0 do

        local result_position = nil
        local nearby_position = nil
        local nearby_distance = 99999
        local nearby_group = 0        

        xy.each(result, function (result_pole, a) 
            xy.each(pole_groups.positions, function (nearby_pole, b)
                local d = math2d.position.distance(a, b)
                if d < nearby_distance then
                    result_position = a
                    nearby_position = b
                    nearby_group = nearby_pole.group
                    nearby_distance = d
                end
            end)
        end)

        local wire_range = mod_context.toolbox.power_pole.wire_range
        local last_position = result_position
        local number_of_connecting_poles = 0
        while math2d.position.distance(last_position, nearby_position) > wire_range do
            local initial_search_radius = 2
            
            local ideal_pole_position_unaligned = math2d.position.add(
                last_position, 
                math2d.position.multiply_scalar(
                    math2d.position.get_normalised(
                        math2d.position.subtract(
                            nearby_position, 
                            last_position                    
                        )
                    ),
                    wire_range - initial_search_radius 
                )
            )

            local diff = math2d.position.subtract(ideal_pole_position_unaligned, last_position)
            diff.x = math.floor(diff.x)
            if diff.x < 0 then
                diff.x = diff.x + 1
            end
            diff.y = math.floor(diff.y)
            if diff.y < 0 then
                diff.y = diff.y + 1
            end

            local search_position = math2d.position.add(last_position, diff)
            local search_box = helpers.bounding_box.create(search_position, search_position)
            helpers.bounding_box.grow(search_box, initial_search_radius)     
            local best_position = nil
            local best_score = 0

            local test_position = function (position)
                local result_distance = math2d.position.distance(position, last_position)
                if xy.get(mod_context.area, position) == "can-build" and result_distance < wire_range then                
                    local score = score_adjacent_cells(mod_context, position)
                    score = score + (result_distance * 0.25)
                    if score > best_score then
                        best_position = position
                        best_score = score
                    end
                end
            end

            helpers.bounding_box.each_grid_position(search_box, test_position)
            while(best_position == nil) do
                helpers.bounding_box.each_edge_position(search_box, test_position)
                helpers.bounding_box.grow(search_box, 1)
            end
        
            xy.set(result, best_position, {group=0})
            last_position = best_position
            number_of_connecting_poles = number_of_connecting_poles + 1
        end
        
        xy.each(pole_groups.positions, function (nearby_pole, position)
            if nearby_pole.group == nearby_group then
                xy.set(result, position, nearby_pole)
                xy.remove(pole_groups.positions, position)
            end
        end)
        
        pole_groups.group_count = pole_groups.group_count - 1
       
    end

    return result
end

function plan_power(mod_context)
    local consumer_positions = {};
    
    xy.each(mod_context.construction_plan, function(planned_entity, position)
        xy.set(mod_context.area, position, "construct-pipe")

        if (planned_entity.name == "extractor") then
            xy.set(consumer_positions, position, {--[[Maybe add some info later?]]})
        end
    end)   
    
    local consumer_power_poles_map = map_possible_consumer_power_pole_positions(mod_context, consumer_positions)
    local pole_groups = group_power_poles(mod_context, consumer_power_poles_map, consumer_positions)
    local connected_poles = merge_power_pole_groups(mod_context, pole_groups)

    xy.each(connected_poles, function (pole_plan, position)
        xy.set(mod_context.construction_plan, position, {name="power_pole", direction = defines.direction.north, group = pole_plan.group})
    end)
end