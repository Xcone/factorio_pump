function plan(planner_input)

    -- add the required info to make planner_input a segment
    planner_input["split_direction"] = "none"
    planner_input["connectable_edges"] =
        {top = false, left = false, bottom = false, right = false}
    planner_input.number_of_splits = 0

    segmentate(planner_input, "none")

    local construct_entities = {["pumpjack"] = {}, ["pipe"] = {}}
    construct_pipes_on_splits(planner_input, construct_entities)

    return construct_entities
end

--[[
local segment = {
    area_bounds = {left_top = {x, y}, right_bottom = {x, y}},
    split_direction = "split_horizontal",
    connectable_edges = {
        [top] = false,
        [left] = false,
        [bottom] = false,
        [right] = false
    },
    
    sub_segment_1 = {
        area_bounds = {left_top = {x, y}, right_bottom = {x, y}},
        split_direction = "none",
        area = {....},
        connectable_edges = {
            [top] = false,
            [left] = false,
            [bottom] = true,
            [right] = false
        }
    },
    sub_segment_2 = {
        area_bounds = {left_top = {x, y}, right_bottom = {x, y}},
        split_direction = "none",
        area = {......},
        connectable_edges = {
            [top] = true,
            [left] = false,
            [bottom] = false,
            [right] = false
        }
    }
}
]]

function segmentate(segment, previous_split)
    local left = segment.area_bounds.left_top.x
    local right = segment.area_bounds.right_bottom.x
    local top = segment.area_bounds.left_top.y
    local bottom = segment.area_bounds.right_bottom.y
    local size_horizontal = right - left
    local size_vertical = bottom - top

    local next_split = "none"

    if previous_split == "none" then
        if size_vertical > size_horizontal then
            previous_split = "split_vertical"
        else
            previous_split = "split_horizontal"
        end
    end

    if previous_split == "split_vertical" then
        if size_vertical > 18 then next_split = "split_horizontal" end
    elseif previous_split == "split_horizontal" then
        if size_horizontal > 18 then next_split = "split_vertical" end
    end

    if next_split == "split_horizontal" then
        local split_result = find_split_horizontal(segment)
        if split_result.found_split then
            local top_bounds = {
                left_top = {x = left, y = top},
                right_bottom = {x = right, y = split_result.value - 1}
            }
            local bottom_bounds = {
                left_top = {x = left, y = split_result.value + 1},
                right_bottom = {x = right, y = bottom}
            }

            split_segment(segment, top_bounds, bottom_bounds, next_split)
        end
    elseif next_split == "split_vertical" then
        local split_result = find_split_vertical(segment)
        if split_result.found_split then
            local left_bounds = {
                left_top = {x = left, y = top},
                right_bottom = {x = split_result.value - 1, y = bottom}
            }
            local right_bounds = {
                left_top = {x = split_result.value + 1, y = top},
                right_bottom = {x = right, y = bottom}
            }

            split_segment(segment, left_bounds, right_bounds, next_split)
        end
    end
end

function split_segment(segment, bounds_1, bounds_2, split_direction)
    local area_1 = make_sub_area(segment.area, bounds_1)
    local area_2 = make_sub_area(segment.area, bounds_2)
    segment.area = nil
    segment.split_direction = split_direction

    segment.sub_segment_1 = {
        area = area_1,
        area_bounds = bounds_1,
        split_direction = "none",
        connectable_edges = table.deepcopy(segment.connectable_edges),
        number_of_splits = segment.number_of_splits + 1
    }

    segment.sub_segment_2 = {
        area = area_2,
        area_bounds = bounds_2,
        split_direction = "none",
        connectable_edges = table.deepcopy(segment.connectable_edges),
        number_of_splits = segment.number_of_splits + 1
    }

    if split_direction == "split_horizontal" then
        segment.sub_segment_1.connectable_edges.bottom = true
        segment.sub_segment_2.connectable_edges.top = true
    elseif split_direction == "split_vertical" then
        segment.sub_segment_1.connectable_edges.right = true
        segment.sub_segment_2.connectable_edges.left = true
    end

    segmentate(segment.sub_segment_1, split_direction)
    segmentate(segment.sub_segment_2, split_direction)
end

function make_sub_area(area, bounds)
    local left = bounds.left_top.x;
    local right = bounds.right_bottom.x;
    local top = bounds.left_top.y;
    local bottom = bounds.right_bottom.y;

    local result = {}

    for x = left, right do
        result[x] = {}
        for y = top, bottom do result[x][y] = area[x][y] end
    end

    return result
end

-- Look top to bottom, to find an all-clear from left to right
function find_split_horizontal(segment)
    local top = segment.area_bounds.left_top.y;
    local bottom = segment.area_bounds.right_bottom.y;
    local left = segment.area_bounds.left_top.x;
    local right = segment.area_bounds.right_bottom.x;

    local middle = get_middle(top, bottom)

    offset = 0

    local result_a = {
        found_split = false,
        value = middle,
        query_value = middle,
        found_obstruction = false
    }
    local result_b = {
        found_split = false,
        value = middle,
        query_value = middle,
        found_obstruction = false
    }

    while result_a.query_value > top and result_b.query_value < bottom do

        if area_contains_obstruction(segment.area,
                                     {x = left, y = result_a.query_value},
                                     {x = right, y = result_a.query_value}) then
            result_a.found_obstruction = true
        else
            result_a.value = result_a.query_value
            result_a.found_split = true
        end

        if result_a.found_split and result_a.found_obstruction then
            return result_a
        else
            result_a.query_value = result_a.query_value - 1
        end

        if area_contains_obstruction(segment.area,
                                     {x = left, y = result_b.query_value},
                                     {x = right, y = result_b.query_value}) then
            result_b.found_obstruction = true
        else
            result_b.value = result_b.query_value
            result_b.found_split = true
        end

        if result_b.found_split and result_b.found_obstruction then
            return result_b
        else
            result_b.query_value = result_b.query_value - 1
        end
    end

    return {found_split = false, value = middle}
end

-- Look left to right, to find an all-clear from top to bottom
function find_split_vertical(segment)
    local top = segment.area_bounds.left_top.y;
    local bottom = segment.area_bounds.right_bottom.y;
    local left = segment.area_bounds.left_top.x;
    local right = segment.area_bounds.right_bottom.x;

    local middle = get_middle(left, right)

    offset = 0

    local result_a = {
        found_split = false,
        value = middle,
        query_value = middle,
        found_obstruction = false
    }
    local result_b = {
        found_split = false,
        value = middle,
        query_value = middle,
        found_obstruction = false
    }

    while result_a.query_value > left and result_b.query_value < right do

        if area_contains_obstruction(segment.area,
                                     {x = result_a.query_value, y = top},
                                     {x = result_a.query_value, y = bottom}) then
            result_a.found_obstruction = true
        else
            result_a.value = result_a.query_value
            result_a.found_split = true
        end

        if result_a.found_split and result_a.found_obstruction then
            return result_a
        else
            result_a.query_value = result_a.query_value - 1
        end

        if area_contains_obstruction(segment.area,
                                     {x = result_b.query_value, y = top},
                                     {x = result_b.query_value, y = bottom}) then
            result_b.found_obstruction = true
        else
            result_b.value = result_b.query_value
            result_b.found_split = true
        end

        if result_b.found_split and result_b.found_obstruction then
            return result_b
        else
            result_b.query_value = result_b.query_value - 1
        end
    end

    return {found_split = false, value = middle}
end

function get_middle(min, max)
    local middle_unrounded = min + ((max - min) / 2)
    local middle_rounded = min

    for i = min, max do
        if i < middle_unrounded then
            middle_rounded = i
        else
            break
        end
    end

    return middle_rounded
end

function area_contains_obstruction(area, left_top, right_bottom)
    for x = left_top.x, right_bottom.x, 1 do
        for y = left_top.y, right_bottom.y, 1 do
            if area[x][y] ~= "can-build" then return true end
        end
    end

    return false
end

function construct_pipes_on_splits(segment, construct_entities)
    if segment.split_direction == "none" then return end

    if segment.split_direction == "split_horizontal" then
        for x = segment.sub_segment_1.area_bounds.left_top.x, segment.sub_segment_1
            .area_bounds.right_bottom.x do
            table.insert(construct_entities["pipe"], {
                position = {
                    x = x,
                    y = segment.sub_segment_1.area_bounds.right_bottom.y + 1
                },
                direction = defines.direction.east
            })
        end
    end

    if segment.split_direction == "split_vertical" then
        for y = segment.sub_segment_1.area_bounds.left_top.y, segment.sub_segment_1
            .area_bounds.right_bottom.y do
            table.insert(construct_entities["pipe"], {
                position = {
                    x = segment.sub_segment_1.area_bounds.right_bottom.x + 1,
                    y = y
                },
                direction = defines.direction.east
            })
        end
    end

    construct_pipes_on_splits(segment.sub_segment_1, construct_entities)
    construct_pipes_on_splits(segment.sub_segment_2, construct_entities)
end

function get_pump_output_offset(direction)
    if direction == defines.direction.north then return {x = 1, y = -2} end
    if direction == defines.direction.east then return {x = 2, y = -1} end
    if direction == defines.direction.south then return {x = -1, y = 2} end
    if direction == defines.direction.west then return {x = -2, y = 1} end
end

function table.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[table.deepcopy(orig_key)] = table.deepcopy(orig_value)
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- custom log method used for the 
function pump_log(object_to_log)
    if pumpdebug then pumpdebug.log(object_to_log) end
end
