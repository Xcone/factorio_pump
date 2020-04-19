--[[
    Glossary:
    - area: A table using the X-position as key, of tables using the Y-position as key. Each entry containing a string-value describing what the tile is.      
      Can be accessed like: area[x][y]
      "can-build": the planner can use this tile to connect the pumpjacks
      "can-not-build": obstructed. It doesn't matter what by, but the planner will avoid the tile.
      "oilwell": tile contains an oilwell, and the planner will attempt to put a pumpjack here.
      "reserved-for-pump": the input determined the oilwell is unobstructed and reserves the 8 tiles around it to avoid pipes being planned here.
    - area_bounds: The left_top and right_bottom of the area
    - planner_input: Contains area and area_bounds, and is the input of the planner
    - construct_entities: a table with the key of the entity-name that will be built. Each value is a sub-table with a position and a direction to build the entity in. The planner's goal is to populate this table using planner_input
    - segment: A table describing how the planner_input is split into smaller chunks. Each containing:
      area: see above
      area_bounds: see above
      construct_entities: see above, only present if the planner was able to connect all pumpjacks in this segment, without subdeviding the segment further.
      split_direction: none if the segment is not split, or split_vertical/split_horizontal if the segment is split in smaller segments
      sub_segment_1: a segment, only present if the segment was split
      sub_segment_2: a segment, only present if the segment was split
      number_of_splits: how many times the planner_input has been split into smaller segments to reach the current segment
      connectable_edges: Pipes are placed between segments. Therefor pumpjacks may connect to these edges of segments that connect to another segment
]] --
function plan(planner_input)
    local construct_entities = make_default_construction_entities_table()

    pump_log(planner_input.area_bounds)
    convert_planner_input_to_segment(planner_input)
    segmentate(planner_input, "none")
    construct_pipes_on_splits(planner_input, construct_entities)
    add_construct_entities_from_segments(planner_input, construct_entities)
    optimize_construct_entities(construct_entities)

    return save_as_planner_result(construct_entities)
end

function convert_planner_input_to_segment(planner_input)
    planner_input["split_direction"] = "none"
    planner_input["connectable_edges"] =
        {top = false, left = false, bottom = false, right = false}
    planner_input.number_of_splits = 0
end

function save_as_planner_result(construct_entities)
    local result = {}
    result.pipe = {}
    result.pumpjack = {}
    result.pipe_joint = {}

    for x, column in pairs(construct_entities) do
        for y, construct_entity in pairs(column) do
            table.insert(result[construct_entity.name], {
                position = {x = x, y = y},
                direction = construct_entity.direction
            })
        end
    end

    return result
end

function make_default_construction_entities_table() return {} end

function add_construct_entities_from_segments(segment, construct_entities)
    if segment.split_direction == "none" then
        if segment.construct_entities ~= nil then
            for x, column in pairs(segment.construct_entities) do
                for y, construct_entity in pairs(column) do
                    if construct_entity.name == "pipe" then
                        add_pipe(construct_entities, {x = x, y = y})
                    end
                    if construct_entity.name == "pipe_joint" then
                        add_pipe(construct_entities, {x = x, y = y}, true)
                    end
                    if construct_entity.name == "pumpjack" then
                        add_pumpjack(construct_entities, {x = x, y = y},
                                     construct_entity.direction)
                    end
                end
            end
        end
    else
        add_construct_entities_from_segments(segment.sub_segment_1,
                                             construct_entities)
        add_construct_entities_from_segments(segment.sub_segment_2,
                                             construct_entities)
    end
end

function optimize_construct_entities(construct_entities)
    local pipe_joint_positions = {}
    for x, column in pairs(construct_entities) do
        for y, construct_entity in pairs(column) do
            if construct_entity.name == "pipe_joint" then
                get_or_create_position(pipe_joint_positions, {x = x, y = y})
                pipe_joint_positions[x][y] = "pipe_joint"
            end
        end
    end

    local offsets = {
        {x = 0, y = 1}, {x = 0, y = -1}, {x = 1, y = 0}, {x = -1, y = 0}
    }

    for x, column in pairs(pipe_joint_positions) do
        for y, pipe_joint in pairs(column) do
            for _, offset in ipairs(offsets) do
                local result = get_pipes_until_nil_or_next_joint(
                                   construct_entities, {x = x, y = y}, offset)
                if result.last_hit == nil then
                    remove_pipes(construct_entities, result.pipe_positions)
                end
            end
        end
    end
end

function remove_pipes(construct_entities, pipe_positions)
    for i, pipe_position in pairs(pipe_positions) do
        construct_entities[pipe_position.x][pipe_position.y] = nil
    end
end

function get_pipes_until_nil_or_next_joint(construct_entities,
                                           start_joint_position, offset)

    local x = start_joint_position.x
    local y = start_joint_position.y
    local is_pipe = false
    local pipe_positions = {}
    local construct_entity_at_position = nil

    repeat
        x = x + offset.x
        y = y + offset.y
        is_pipe = false
        construct_entity_at_position = nil
        if construct_entities[x] ~= nil and construct_entities[x][y] ~= nil then
            construct_entity_at_position = construct_entities[x][y]
            is_pipe = construct_entity_at_position.name == "pipe"
        end

        if (is_pipe) then table.insert(pipe_positions, {x = x, y = y}) end
    until not is_pipe

    return {
        last_hit = construct_entity_at_position,
        pipe_positions = pipe_positions
    }
end

function add_pumpjack(construct_entities, position, direction)
    local target = get_or_create_position(construct_entities, position)
    target.name = "pumpjack"
    target.direction = direction
end

function add_pipe(construct_entities, position, do_not_optimize)
    local target = get_or_create_position(construct_entities, position)

    target.direction = defines.direction.east
    if do_not_optimize then
        target.name = "pipe_joint"
    else
        if target.name ~= "pipe_joint" then target.name = "pipe" end
    end
end

function get_or_create_position(table, position)
    if not table[position.x] then table[position.x] = {} end

    if not table[position.x][position.y] then
        table[position.x][position.y] = {}
    end

    return table[position.x][position.y]
end

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
        if size_vertical > 10 then next_split = "split_horizontal" end
    elseif previous_split == "split_horizontal" then
        if size_horizontal > 10 then next_split = "split_vertical" end
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

    if not try_connect_pumps(segment.sub_segment_1) then
        segmentate(segment.sub_segment_1, split_direction)
    end
    if not try_connect_pumps(segment.sub_segment_2) then
        segmentate(segment.sub_segment_2, split_direction)
    end
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
            result_b.query_value = result_b.query_value + 1
        end
    end

    pump_log({
        could_not_split_hotizontal = {
            level = segment.number_of_splits,
            bounds = segment.area_bounds,
            result_a = result_a,
            result_b = result_b
        }
    })

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
            result_b.query_value = result_b.query_value + 1
        end
    end

    pump_log({
        could_not_split_vertical = {
            level = segment.number_of_splits,
            bounds = segment.area_bounds,
            result_a = result_a,
            result_b = result_b
        }
    })

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
        local y = segment.sub_segment_1.area_bounds.right_bottom.y + 1
        if segment.connectable_edges.left then
            local position = {
                x = segment.sub_segment_1.area_bounds.left_top.x - 1,
                y = y
            }
            add_pipe(construct_entities, position, true)
        end

        if segment.connectable_edges.right then
            local position = {
                x = segment.sub_segment_1.area_bounds.right_bottom.x + 1,
                y = y
            }
            add_pipe(construct_entities, position, true)
        end

        for x = segment.sub_segment_1.area_bounds.left_top.x, segment.sub_segment_1
            .area_bounds.right_bottom.x do

            add_pipe(construct_entities, {x = x, y = y})
        end
    end

    if segment.split_direction == "split_vertical" then
        local x = segment.sub_segment_1.area_bounds.right_bottom.x + 1
        if segment.connectable_edges.top then
            local position = {
                x = x,
                y = segment.sub_segment_1.area_bounds.left_top.y - 1
            }
            add_pipe(construct_entities, position, true)
        end

        if segment.connectable_edges.bottom then
            local position = {
                x = x,
                y = segment.sub_segment_1.area_bounds.right_bottom.y + 1
            }
            add_pipe(construct_entities, position, true)
        end
        for y = segment.sub_segment_1.area_bounds.left_top.y, segment.sub_segment_1
            .area_bounds.right_bottom.y do

            add_pipe(construct_entities, {x = x, y = y})
        end
    end

    construct_pipes_on_splits(segment.sub_segment_1, construct_entities)
    construct_pipes_on_splits(segment.sub_segment_2, construct_entities)
end

function try_connect_pumps(segment)
    local oilwells = find_oilwells(segment)
    local construct_entities = make_default_construction_entities_table()

    for i = 1, #oilwells do

        local pumpjack_position = oilwells[i].position
        oilwells[i].construction_analysis = {}

        for direction, offset in pairs(get_pump_output_offsets()) do
            local pipe_start_position = {
                x = pumpjack_position.x + offset.x,
                y = pumpjack_position.y + offset.y
            }

            local pipe_placement_result =
                get_best_pipe_placement_to_edge(segment, pipe_start_position)
            if pipe_placement_result ~= nil then
                pipe_placement_result.pump_direction = direction
                table.insert(oilwells[i].construction_analysis,
                             pipe_placement_result)
            end
        end

        local best_option = get_best_pumpjack_placement(
                                oilwells[i].construction_analysis)
        if best_option ~= nil then

            add_pumpjack(construct_entities, pumpjack_position,
                         best_option.pump_direction)

            for pipe_index = 0, best_option.edge_distance do
                local offset_x = 0
                local offset_y = 0

                if best_option.edge_direction == defines.direction.north then
                    offset_y = -1 * pipe_index
                end
                if best_option.edge_direction == defines.direction.east then
                    offset_x = 1 * pipe_index
                end
                if best_option.edge_direction == defines.direction.south then
                    offset_y = 1 * pipe_index
                end
                if best_option.edge_direction == defines.direction.west then
                    offset_x = -1 * pipe_index
                end

                local is_pump_output = pipe_index == 0
                local is_edge_connection =
                    pipe_index == best_option.edge_distance

                add_pipe(construct_entities, {
                    x = best_option.pipe_start_position.x + offset_x,
                    y = best_option.pipe_start_position.y + offset_y
                }, is_pump_output or is_edge_connection)

            end
        else
            return false
        end
    end

    segment.construct_entities = construct_entities
    return true
end

function find_oilwells(segment)
    local oilwells = {}

    for x = segment.area_bounds.left_top.x, segment.area_bounds.right_bottom.x do
        for y = segment.area_bounds.left_top.y, segment.area_bounds.right_bottom
            .y do
            if segment.area[x][y] == "oil-well" then
                table.insert(oilwells, {position = {x = x, y = y}})
            end
        end
    end

    return oilwells
end

function get_best_pumpjack_placement(oilwell_construction_analysis)
    local best_option = nil
    local can_connect_pump_to_edge = #oilwell_construction_analysis > 0

    if can_connect_pump_to_edge then
        for i, analysis in pairs(oilwell_construction_analysis) do
            if best_option == nil or analysis.edge_distance <
                best_option.edge_distance then best_option = analysis end
        end
    end

    return best_option
end

function get_best_pipe_placement_to_edge(segment, pipe_start_position)
    local distance_to_top = 1000
    if is_on_top_edge(segment, pipe_start_position) then
        distance_to_top = 0
    elseif (not is_on_edge(segment, pipe_start_position)) and
        segment.connectable_edges.top then
        local lt = to_top_edge(pipe_start_position, segment.area_bounds)
        local rb = pipe_start_position

        if not area_contains_obstruction(segment.area, lt, rb) then
            distance_to_top = rb.y - lt.y + 1
        end
    end

    local distance_to_left = 1000
    if is_on_left_edge(segment, pipe_start_position) then
        distance_to_left = 0
    elseif (not is_on_edge(segment, pipe_start_position)) and
        segment.connectable_edges.left then
        local lt = to_left_edge(pipe_start_position, segment.area_bounds)
        local rb = pipe_start_position

        if not area_contains_obstruction(segment.area, lt, rb) then
            distance_to_left = rb.x - lt.x + 1
        end
    end

    local distance_to_bottom = 1000
    if is_on_bottom_edge(segment, pipe_start_position) then
        distance_to_bottom = 0
    elseif (not is_on_edge(segment, pipe_start_position)) and
        segment.connectable_edges.bottom then
        local lt = pipe_start_position
        local rb = to_bottom_edge(pipe_start_position, segment.area_bounds)

        if not area_contains_obstruction(segment.area, lt, rb) then
            distance_to_bottom = rb.y - lt.y + 1
        end
    end

    local distance_to_right = 1000
    if is_on_right_edge(segment, pipe_start_position) then
        distance_to_right = 0
    elseif (not is_on_edge(segment, pipe_start_position)) and
        segment.connectable_edges.right then
        local lt = pipe_start_position
        local rb = to_right_edge(pipe_start_position, segment.area_bounds)

        if not area_contains_obstruction(segment.area, lt, rb) then
            distance_to_right = rb.x - lt.x + 1
        end
    end

    local smallest_distance = distance_to_top
    local smallest_distance_direction = defines.direction.north
    if distance_to_left < smallest_distance then
        smallest_distance = distance_to_left
        smallest_distance_direction = defines.direction.west
    end
    if distance_to_bottom < smallest_distance then
        smallest_distance = distance_to_bottom
        smallest_distance_direction = defines.direction.south
    end
    if distance_to_right < smallest_distance then
        smallest_distance = distance_to_right
        smallest_distance_direction = defines.direction.east
    end

    if smallest_distance < 9 then
        return {
            edge_distance = smallest_distance,
            edge_direction = smallest_distance_direction,
            pipe_start_position = pipe_start_position
        }
    end

    return nil
end

function is_on_edge(segment, position)
    return is_on_top_edge(segment, position) or
               is_on_bottom_edge(segment, position) or
               is_on_left_edge(segment, position) or
               is_on_right_edge(segment, position)
end

function is_on_top_edge(segment, position)
    return on_top_edge(position, segment.area_bounds).y == position.y
end
function is_on_bottom_edge(segment, position)
    return on_bottom_edge(position, segment.area_bounds).y == position.y
end
function is_on_left_edge(segment, position)
    return on_left_edge(position, segment.area_bounds).x == position.x
end
function is_on_right_edge(segment, position)
    return on_right_edge(position, segment.area_bounds).x == position.x
end

-- exluding the edge itself
function to_top_edge(position, area_bounds)
    return {x = position.x, y = area_bounds.left_top.y}
end

-- exluding the edge itself
function to_bottom_edge(position, area_bounds)
    return {x = position.x, y = area_bounds.right_bottom.y}
end

-- exluding the edge itself
function to_left_edge(position, area_bounds)
    return {x = area_bounds.left_top.x, y = position.y}
end

-- exluding the edge itself
function to_right_edge(position, area_bounds)
    return {x = area_bounds.right_bottom.x, y = position.y}
end

-- including the edge itself
function on_top_edge(position, area_bounds)
    return {x = position.x, y = area_bounds.left_top.y - 1}
end

-- including the edge itself
function on_bottom_edge(position, area_bounds)
    return {x = position.x, y = area_bounds.right_bottom.y + 1}
end

-- including the edge itself
function on_left_edge(position, area_bounds)
    return {x = area_bounds.left_top.x - 1, y = position.y}
end

-- including the edge itself
function on_right_edge(position, area_bounds)
    return {x = area_bounds.right_bottom.x + 1, y = position.y}
end

function get_pump_output_offsets()
    return {
        [defines.direction.north] = {x = 1, y = -2},
        [defines.direction.east] = {x = 2, y = -1},
        [defines.direction.south] = {x = -1, y = 2},
        [defines.direction.west] = {x = -2, y = 1}
    }
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
