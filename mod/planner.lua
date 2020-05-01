--[[
    Glossary:
    - area: A table using the X-position as key, of tables using the Y-position as key. Each entry containing a string-value describing what the tile is.      
      Can be accessed like: area[x][y]
      "can-build": the planner can use this tile to connect the pumpjacks
      "can-not-build": obstructed. It doesn't matter what by, but the planner will avoid the tile.
      "oilwell": tile contains an oilwell, and the planner will attempt to put a pumpjack here.
      "reserved-for-pump": the input determined the oilwell is unobstructed and reserves the 8 tiles around it to avoid pipes being planned here.
    - area_bounds: The left_top and right_bottom of the area
    - mod_context: Contains area, area_bounds and the toolbox, and is the input of the planner
    - construct_entities: a table with the key of the entity-name that will be built. Each value is a sub-table with a position and a direction to build the entity in.
    - segment: A table describing how the area provided by the mod_context is split into smaller chunks. Each containing:
      area: see above
      area_bounds: see above
      construct_entities: see above, only present if the planner was able to connect all pumpjacks in this segment, without subdeviding the segment further.
      split_direction: 'none' if the segment is not split, or 'split_vertical'/'split_horizontal' if the segment is split in smaller segments
      sub_segment_1: a segment, only present if the segment was split
      sub_segment_2: a segment, only present if the segment was split
      number_of_splits: how many times the base segment has been split into smaller segments to reach the current segment
      connectable_edges: Pipes are placed between segments. Therefor pumpjacks may connect to these edges of segments that connect to another segment
      toolbox: initially provided via mod_context. Contains some abstract info about entities the planner needs to plan, without exposing the details of those entities
]] --
function add_construction_plan(mod_context)
    pump_log(mod_context.area_bounds)
    local base_segment = create_base_segment(mod_context)
    segmentate(base_segment, "none")

    if not verify_all_pumps_connected(base_segment) then
        return {"failure.obstructed-pipe"}
    end

    local construct_entities = {}
    construct_pipes_on_splits(base_segment, construct_entities)
    add_construct_entities_from_segments(base_segment, construct_entities)
    optimize_construct_entities(construct_entities, base_segment.toolbox)

    mod_context.construction_plan = save_as_planner_result(construct_entities)
end

function verify_all_pumps_connected(segment)
    if segment.split_direction == "none" then
        if segment.construct_entities ~= nil then
            return true
        else
            return #find_oilwells(segment) == 0
        end
    else
        return verify_all_pumps_connected(segment.sub_segment_1) and
                   verify_all_pumps_connected(segment.sub_segment_2)
    end
end

function create_base_segment(mod_context)
    local segment = {}
    segment.area_bounds = mod_context.area_bounds
    segment.area = mod_context.area
    segment.toolbox = mod_context.toolbox
    segment["split_direction"] = "none"
    segment["connectable_edges"] = {
        top = false,
        left = false,
        bottom = false,
        right = false
    }
    segment.number_of_splits = 0
    return segment
end

function save_as_planner_result(construct_entities)
    local result = {}
    result.extractors = {}
    result.outputs = {}
    result.connectors = {}
    result.connector_joints = {}
    result.connectors_underground = {}

    for x, column in pairs(construct_entities) do
        for y, construct_entity in pairs(column) do
            local target_name = construct_entity.name
            local placement = {
                position = {x = x, y = y},
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
        end
    end

    return result
end

function add_construct_entities_from_segments(segment, construct_entities)
    if segment.split_direction == "none" then
        if segment.construct_entities ~= nil then
            copy_construct_entities_into(segment.construct_entities,
                                         construct_entities)
        end
    else
        add_construct_entities_from_segments(segment.sub_segment_1,
                                             construct_entities)
        add_construct_entities_from_segments(segment.sub_segment_2,
                                             construct_entities)
    end
end

function optimize_construct_entities(construct_entities, toolbox)
    convert_outputs_to_joints_when_flanked(construct_entities, toolbox)

    local pipe_joint_positions = find_in_construct_entities(construct_entities,
                                                            "pipe_joint")

    for x, column in pairs(pipe_joint_positions) do
        for y, pipe_joint in pairs(column) do
            for direction, toolbox_direction in pairs(helpers.directions) do
                local result = take_series_of_pipes(construct_entities,
                                                    {x = x, y = y},
                                                    toolbox_direction.position)
                if result.last_hit == nil then
                    remove_pipes(construct_entities, result.pipe_positions)
                elseif result.last_hit.name == "output" then
                    table.insert(result.pipe_positions, result.last_hit_position)
                    try_replace_pipes_with_tunnels(construct_entities,
                                                   result.pipe_positions,
                                                   toolbox)
                elseif result.last_hit.name == "pipe_joint" then
                    try_replace_pipes_with_tunnels(construct_entities,
                                                   result.pipe_positions,
                                                   toolbox)
                end
            end
        end
    end
end

function convert_outputs_to_joints_when_flanked(construct_entities, toolbox)
    local output_positions = find_in_construct_entities(construct_entities,
                                                        "output")

    for x, column in pairs(output_positions) do
        for y, output in pairs(column) do
            local flank_direction = helpers.directions[output.direction].next
            local flank_position = helpers.position.offset({x = x, y = y},
                                                           helpers.directions[flank_direction]
                                                               .position)

            local entity_on_flank = nil
            if construct_entities[flank_position.x] ~= nil then
                entity_on_flank =
                    construct_entities[flank_position.x][flank_position.y]

                if entity_on_flank == nil then
                    flank_direction = helpers.directions[output.direction]
                                          .previous
                    flank_position = helpers.position.offset({x = x, y = y},
                                                             helpers.directions[flank_direction]
                                                                 .position)

                    if construct_entities[flank_position.x] ~= nil then
                        entity_on_flank =
                            construct_entities[flank_position.x][flank_position.y]
                    end
                end
            end

            if entity_on_flank ~= nil then
                construct_entities[x][y].name = "pipe_joint"
            end
        end
    end
end

function find_in_construct_entities(construct_entities, search_for_name)
    local search_result = {}
    for x, column in pairs(construct_entities) do
        for y, candidate in pairs(column) do
            if candidate.name == search_for_name then
                get_or_create_position(search_result, {x = x, y = y})
                search_result[x][y] = candidate
            end
        end
    end

    return search_result
end

function copy_construct_entities_into(construct_entities_from,
                                      construct_entities_to)
    for x, column in pairs(construct_entities_from) do
        for y, construct_entity in pairs(column) do
            if construct_entity.name == "pipe" then
                add_connector(construct_entities_to, {x = x, y = y})
            end
            if construct_entity.name == "pipe_joint" then
                add_connector_joint(construct_entities_to, {x = x, y = y})
            end
            if construct_entity.name == "pumpjack" then
                add_pumpjack(construct_entities_to, {x = x, y = y},
                             construct_entity.direction)
            end
            if construct_entity.name == "output" then
                add_output(construct_entities_to, {x = x, y = y},
                           construct_entity.direction)
            end
        end
    end
end

function remove_pipes(construct_entities, pipe_positions)
    for i, pipe_position in pairs(pipe_positions) do
        construct_entities[pipe_position.x][pipe_position.y] = nil
    end
end

function try_replace_pipes_with_tunnels(construct_entities, pipe_positions,
                                        toolbox)

    local tunnel_length_min = toolbox.connector.underground_distance_min + 2
    local tunnel_length_max = toolbox.connector.underground_distance_max + 1

    while #pipe_positions >= tunnel_length_min do
        local pipe_positions_this_batch = {}
        local take_until = #pipe_positions - tunnel_length_max
        if take_until < 1 then take_until = 1 end

        for i = #pipe_positions, take_until, -1 do
            table.insert(pipe_positions_this_batch, pipe_positions[i])
            pipe_positions[i] = nil
        end

        remove_pipes(construct_entities, pipe_positions_this_batch)

        local first_pipe = pipe_positions_this_batch[1]
        local last_pipe = pipe_positions_this_batch[#pipe_positions_this_batch]

        add_pipe_to_ground(construct_entities, first_pipe, last_pipe, toolbox)
    end
end

function take_series_of_pipes(construct_entities, start_joint_position, offset)

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
        last_hit_position = {x = x, y = y},
        pipe_positions = pipe_positions
    }
end

function add_pumpjack(construct_entities, position, direction)
    local target = get_or_create_position(construct_entities, position)
    target.name = "pumpjack"
    target.direction = direction
end

function add_connector(construct_entities, position)
    local target = get_or_create_position(construct_entities, position)
    target.name = "pipe"
    target.direction = defines.direction.east
end

function add_connector_joint(construct_entities, position)
    local target = get_or_create_position(construct_entities, position)
    target.name = "pipe_joint"
    target.direction = defines.direction.east
end

function add_output(construct_entities, position, direction)
    local target = get_or_create_position(construct_entities, position)
    target.name = "output"
    target.direction = direction
end

function add_pipe_to_ground(construct_entities, start_position, end_position,
                            toolbox)
    local start_direction
    local end_direction
    local diff = 100

    if start_position.x == end_position.x then

        diff = start_position.y - end_position.y

        if start_position.y < end_position.y then
            end_direction = defines.direction.south
            start_direction = defines.direction.north
        else
            start_direction = defines.direction.south
            end_direction = defines.direction.north
        end
    else
        diff = start_position.x - end_position.x

        if start_position.x < end_position.x then
            start_direction = defines.direction.west
            end_direction = defines.direction.east
        else
            start_direction = defines.direction.east
            end_direction = defines.direction.west
        end
    end

    diff = math.abs(diff)
    -- rationale: distance measurement is zero-based. So if the underground distance=3, the difference should be
    -- max 4 (and not 5! as with reported bug), to account underground entrances. Schematically:
    -- 
    --   \ _ _ _ /
    -- x=0 1 2 3 4
    --
    -- Therefor: 4-0 = 4, and not 5 as was assumed when the bug occurred
    if diff > toolbox.connector.underground_distance_max + 1 then
        error("Underground distance too far")

        -- it also has to be far enough apart to be able to place the entrance and the exit
        --
        --   \ /
        -- x=0 1
    elseif diff == 0 then
        error("Underground exit and entrance on same position ")
    end

    local start_pipe =
        get_or_create_position(construct_entities, start_position)
    start_pipe.name = "pipe-to-ground"
    start_pipe.direction = start_direction

    local end_pipe = get_or_create_position(construct_entities, end_position)
    end_pipe.name = "pipe-to-ground"
    end_pipe.direction = end_direction
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
        next_split = "split_horizontal"
    elseif previous_split == "split_horizontal" then
        next_split = "split_vertical"
    end

    if next_split == "split_horizontal" then
        local split_result = find_split(segment, defines.direction.east)
        if split_result.unobstructed_slice then
            local split = helpers.bounding_box.split(segment.area_bounds,
                                                     split_result.unobstructed_slice)
            split_segment(segment, split.sub_bounds_1, split.sub_bounds_2,
                          next_split)
        end
    elseif next_split == "split_vertical" then
        local split_result = find_split(segment, defines.direction.south)
        if split_result.unobstructed_slice then
            local split = helpers.bounding_box.split(segment.area_bounds,
                                                     split_result.unobstructed_slice)

            split_segment(segment, split.sub_bounds_1, split.sub_bounds_2,
                          next_split)
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
        number_of_splits = segment.number_of_splits + 1,
        toolbox = segment.toolbox
    }

    segment.sub_segment_2 = {
        area = area_2,
        area_bounds = bounds_2,
        split_direction = "none",
        connectable_edges = table.deepcopy(segment.connectable_edges),
        number_of_splits = segment.number_of_splits + 1,
        toolbox = segment.toolbox
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

-- Look left to right, to find an all-clear from top to bottom
function find_split(segment, direction)
    local sideways = helpers.directions[direction].next

    -- Get a 1-wide slice of the area on the side of the area
    local slice = helpers.bounding_box.copy(segment.area_bounds)
    helpers.bounding_box.squash(slice, sideways)

    -- Prepare 2 slices to scan for obstructions. Start in the middle, and work outwards. 1 slice in each direction
    local number_of_slices = helpers.bounding_box.get_size(segment.area_bounds,
                                                           sideways)

    local middle = math.ceil(number_of_slices / 2)
    helpers.bounding_box.translate(slice, sideways, -middle)
    local opposite_slice = helpers.bounding_box.copy(slice)

    local is_even_number_of_slices = number_of_slices % 2 == 0
    if is_even_number_of_slices then
        -- if number_of_slices is 8, both slices are now at 5. Translate opposite_slice 1 more to be at 4
        helpers.bounding_box.translate(opposite_slice, sideways, -1)
    end

    -- Both slices are in the correct position now. Move slices outwards and look for obstructions.    
    -- Keep looking until there's actually an obstruction, that way the split will happen tightly next to an extractor
    local slice_result = {unobstructed_slice = nil, found_obstruction = false}
    local opposite_slice_result = {
        unobstructed_slice = nil,
        found_obstruction = false
    }

    local count = 0
    while count <= middle do
        if area_contains_obstruction(segment.area, slice) then
            slice_result.found_obstruction = true
        else
            slice_result.unobstructed_slice = helpers.bounding_box.copy(slice)
        end

        if slice_result.unobstructed_slice and slice_result.found_obstruction then
            return slice_result
        end

        if area_contains_obstruction(segment.area, opposite_slice) then
            opposite_slice_result.found_obstruction = true
        else
            opposite_slice_result.unobstructed_slice =
                helpers.bounding_box.copy(opposite_slice)
        end

        if opposite_slice_result.unobstructed_slice and
            opposite_slice_result.found_obstruction then
            return opposite_slice_result
        end

        helpers.bounding_box.translate(slice, sideways, 1)
        helpers.bounding_box.translate(opposite_slice, sideways, -1)
        count = count + 1
    end

    pump_log({
        could_not_split = {
            level = segment.number_of_splits,
            bounds = segment.area_bounds,
            slice_result = slice_result,
            opposite_slice_result = opposite_slice_result,
            slice = slice,
            opposite_slice = opposite_slice
        }
    })

    return {found_split = false, value = middle}
end

function area_contains_obstruction(area, bounds)
    for x = bounds.left_top.x, bounds.right_bottom.x, 1 do
        for y = bounds.left_top.y, bounds.right_bottom.y, 1 do
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
            add_connector_joint(construct_entities, position)
        end

        if segment.connectable_edges.right then
            local position = {
                x = segment.sub_segment_1.area_bounds.right_bottom.x + 1,
                y = y
            }
            add_connector_joint(construct_entities, position)
        end

        for x = segment.sub_segment_1.area_bounds.left_top.x, segment.sub_segment_1
            .area_bounds.right_bottom.x do

            add_connector(construct_entities, {x = x, y = y})
        end
    end

    if segment.split_direction == "split_vertical" then
        local x = segment.sub_segment_1.area_bounds.right_bottom.x + 1
        if segment.connectable_edges.top then
            local position = {
                x = x,
                y = segment.sub_segment_1.area_bounds.left_top.y - 1
            }
            add_connector_joint(construct_entities, position)
        end

        if segment.connectable_edges.bottom then
            local position = {
                x = x,
                y = segment.sub_segment_1.area_bounds.right_bottom.y + 1
            }
            add_connector_joint(construct_entities, position)
        end
        for y = segment.sub_segment_1.area_bounds.left_top.y, segment.sub_segment_1
            .area_bounds.right_bottom.y do

            add_connector(construct_entities, {x = x, y = y})
        end
    end

    construct_pipes_on_splits(segment.sub_segment_1, construct_entities)
    construct_pipes_on_splits(segment.sub_segment_2, construct_entities)
end

function try_connect_pumps(segment)
    local oilwells = find_oilwells(segment)
    local construct_entities = {}

    for i = 1, #oilwells do

        local pumpjack_position = oilwells[i].position
        oilwells[i].construction_analysis = {}

        for direction, offset in pairs(segment.toolbox.extractor.output_offsets) do
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

                local pipe_position = {
                    x = best_option.pipe_start_position.x + offset_x,
                    y = best_option.pipe_start_position.y + offset_y
                }

                if pipe_index == 0 then
                    add_output(construct_entities, pipe_position,
                               best_option.pump_direction)
                elseif pipe_index == best_option.edge_distance then
                    add_connector_joint(construct_entities, pipe_position)
                else
                    add_connector(construct_entities, pipe_position)
                end
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

        if not area_contains_obstruction(segment.area,
                                         helpers.bounding_box.create(lt, rb)) then
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

        if not area_contains_obstruction(segment.area,
                                         helpers.bounding_box.create(lt, rb)) then
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

        if not area_contains_obstruction(segment.area,
                                         helpers.bounding_box.create(lt, rb)) then
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

        if not area_contains_obstruction(segment.area,
                                         helpers.bounding_box.create(lt, rb)) then
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

    local acceptable_distance = segment.toolbox.connector
                                    .underground_distance_max + 2
    if smallest_distance <= acceptable_distance then
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
