require 'util'
local math2d = require 'math2d'
local plib = require 'plib'
local xy = plib.xy

local function area_contains_obstruction(area, bounds)
    for x = bounds.left_top.x, bounds.right_bottom.x, 1 do
        for y = bounds.left_top.y, bounds.right_bottom.y, 1 do
            if area[x][y] ~= "can-build" then return true end
        end
    end

    return false
end

local function get_distance_to_edge(segment, position, direction)

    local toolbox_direction = plib.directions[direction]
    local vector_inwards = plib.directions[toolbox_direction.opposite].vector

    local is_in_segment = math2d.bounding_box.contains_point(
                              segment.area_bounds, position)

    if is_in_segment and segment.connectable_edges[direction] then
        local edge_position = toolbox_direction.to_edge(segment.area_bounds,
                                                        position)
        local line_to_edge = plib.bounding_box
                                 .create(position, edge_position)

        if not area_contains_obstruction(segment.area, line_to_edge) then
            return plib.bounding_box.get_size(line_to_edge)
        end
    else
        local position_offset_inwards = math2d.position.add(position,
                                                            vector_inwards)

        local is_on_outer_edge = not is_in_segment and
                                     math2d.bounding_box
                                         .contains_point(segment.area_bounds,
                                                         position_offset_inwards)

        if is_on_outer_edge then return 0 end
    end

    return 1000
end

local function add_extractor(construct_entities, position, direction)
    xy.set(construct_entities, position,
           {name = "extractor", direction = direction})
end

local function add_connector(construct_entities, position)
    xy.set(construct_entities, position,
           {name = "pipe", direction = defines.direction.east})
end

local function add_connector_joint(construct_entities, position)
    xy.set(construct_entities, position,
           {name = "pipe_joint", direction = defines.direction.east})
end

local function add_output(construct_entities, position, direction)
    xy.set(construct_entities, position,
           {name = "output", direction = direction})
end

local function add_pipe_tunnel(construct_entities, start_position, end_position,
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

    xy.set(construct_entities, start_position,
           {name = "pipe_tunnel", direction = start_direction})

    xy.set(construct_entities, end_position,
           {name = "pipe_tunnel", direction = end_direction})
end

local function remove_pipes(construct_entities, pipe_positions)
    for i, pipe_position in pairs(pipe_positions) do
        construct_entities[pipe_position.x][pipe_position.y] = nil
    end
end

local function try_replace_pipes_with_tunnels(construct_entities, pipe_positions, toolbox)
    local tunnel_length_min = toolbox.connector.underground_distance_min + 2
    local tunnel_length_max = toolbox.connector.underground_distance_max + 1

    if toolbox.pipe_bury_distance_preference > tunnel_length_min then
        tunnel_length_min = toolbox.pipe_bury_distance_preference
    end

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

        add_pipe_tunnel(construct_entities, first_pipe, last_pipe, toolbox)
    end
end

local function copy_construct_entities_into(construct_entities_from,
                                      construct_entities_to)
    xy.each(construct_entities_from, function(construct_entity, position)
        if construct_entity.name == "pipe" then
            add_connector(construct_entities_to, position)
        end
        if construct_entity.name == "pipe_joint" then
            add_connector_joint(construct_entities_to, position)
        end
        if construct_entity.name == "extractor" then
            add_extractor(construct_entities_to, position,
                          construct_entity.direction)
        end
        if construct_entity.name == "output" then
            add_output(construct_entities_to, position,
                       construct_entity.direction)
        end
    end)
end

local function find_in_construct_entities(construct_entities, search_for_name)
    return xy.where(construct_entities, function(candidate)
        return candidate.name == search_for_name
    end)
end

local function take_series_of_pipes(construct_entities, start_joint_position,
                              direction)

    local probe_location = math2d.position.ensure_xy(start_joint_position)
    local is_pipe = false
    local pipe_positions = {}
    local construct_entity_at_position = nil

    repeat
        probe_location = math2d.position.add(probe_location,
                                             plib.directions[direction]
                                                 .vector)
        is_pipe = false
        construct_entity_at_position =
            xy.get(construct_entities, probe_location)
        if construct_entity_at_position then
            is_pipe = construct_entity_at_position.name == "pipe"
        end

        if (is_pipe) then table.insert(pipe_positions, probe_location) end
    until not is_pipe

    return {
        last_hit = construct_entity_at_position,
        last_hit_position = probe_location,
        pipe_positions = pipe_positions
    }
end

local function find_oilwells(segment)
    local oilwells = {}

    plib.bounding_box.each_grid_position(segment.area_bounds, function (position)
        if xy.get(segment.area, position) == "oil-well" then
            table.insert(oilwells, { position = position })
        end
    end)

    return oilwells
end

local function verify_all_extractors_connected(segment)
    if segment.split_direction == "none" then
        if segment.construct_entities ~= nil then
            return true
        else
            return #find_oilwells(segment) == 0
        end
    else
        return verify_all_extractors_connected(segment.sub_segment_1) and
                   verify_all_extractors_connected(segment.sub_segment_2)
    end
end

local function get_best_extractor_placement(oilwell_construction_analysis)
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

local function get_best_pipe_placement_to_edge(segment, pipe_start_position)

    local distances = {}
    local acceptable_distance = segment.toolbox.connector
                                    .underground_distance_max + 2

    for direction, _ in pairs(plib.directions) do
        distances[direction] = get_distance_to_edge(segment,
                                                    pipe_start_position,
                                                    direction)
    end

    local smallest_distance = 1000
    local result = nil

    for direction, distance in pairs(distances) do
        if distance <= acceptable_distance and distance < smallest_distance then
            result = {
                edge_distance = distance,
                edge_direction = direction,
                pipe_start_position = pipe_start_position
            }
        end
    end

    return result
end

local function create_base_segment(mod_context)
    local segment = {}
    segment.area_bounds = mod_context.area_bounds
    segment.area = mod_context.area
    segment.toolbox = mod_context.toolbox
    segment["split_direction"] = "none"
    segment["connectable_edges"] = {
        [defines.direction.north] = false,
        [defines.direction.east] = false,
        [defines.direction.south] = false,
        [defines.direction.west] = false
    }
    segment.number_of_splits = 0
    return segment
end

local function add_construct_entities_from_segments(segment, construct_entities)
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

local function convert_outputs_to_joints_when_flanked(construct_entities, toolbox)
    local output_positions = find_in_construct_entities(construct_entities,
                                                        "output")

    xy.each(output_positions, function(output, position)
        local flank_direction = plib.directions[output.direction].next
        local flank_position = math2d.position.add(position,
                                                   plib.directions[flank_direction]
                                                       .vector)

        local entity_on_flank = nil
        if construct_entities[flank_position.x] ~= nil then
            entity_on_flank =
                construct_entities[flank_position.x][flank_position.y]

            if entity_on_flank == nil then
                flank_direction = plib.directions[output.direction].previous
                flank_position = math2d.position.add(position,
                                                     plib.directions[flank_direction]
                                                         .vector)

                if construct_entities[flank_position.x] ~= nil then
                    entity_on_flank =
                        construct_entities[flank_position.x][flank_position.y]
                end
            end
        end

        if entity_on_flank ~= nil then
            xy.get(construct_entities, position).name = "pipe_joint"
        end
    end)
end

local function optimize_construct_entities(construct_entities, toolbox)
    convert_outputs_to_joints_when_flanked(construct_entities, toolbox)

    local pipe_joint_positions = find_in_construct_entities(construct_entities,
                                                            "pipe_joint")

    -- Replace straight pipes between joints/joints or joints/outputs with tunnels                                                            
    xy.each(pipe_joint_positions, function(pipe_joint, position)
        for direction, toolbox_direction in pairs(plib.directions) do
            local result = take_series_of_pipes(construct_entities, position,
                                                direction)
            if result.last_hit == nil then
                -- Skip dead ends until all tunnels are placed
            elseif result.last_hit.name == "output" then
                if result.last_hit.direction == direction or
                    result.last_hit.direction == toolbox_direction.opposite then
                    table.insert(result.pipe_positions, result.last_hit_position)
                end
                try_replace_pipes_with_tunnels(construct_entities,
                                               result.pipe_positions, toolbox)
            elseif result.last_hit.name == "pipe_joint" then
                try_replace_pipes_with_tunnels(construct_entities,
                                               result.pipe_positions, toolbox)
            end
        end
    end)

    -- Remove dead ends
    xy.each(pipe_joint_positions, function(pipe_joint, position)
        for direction, toolbox_direction in pairs(plib.directions) do
            local result = take_series_of_pipes(construct_entities, position,
                                                direction)
            if result.last_hit == nil then
                remove_pipes(construct_entities, result.pipe_positions)
            end
        end
    end)
end

local function make_sub_area(area, bounds)
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
local function find_split(segment, direction)
    local sideways = plib.directions[direction].next

    -- Get a 1-wide slice of the area on the side of the area
    local slice = plib.bounding_box.copy(segment.area_bounds)
    plib.bounding_box.squash(slice, sideways)

    -- Prepare 2 slices to scan for obstructions. Start in the middle, and work outwards. 1 slice in each direction
    local number_of_slices = plib.bounding_box.get_cross_section_size(
                                 segment.area_bounds, sideways)

    local middle = math.ceil(number_of_slices / 2)
    plib.bounding_box.translate(slice, sideways, -middle)
    local opposite_slice = plib.bounding_box.copy(slice)

    local is_even_number_of_slices = number_of_slices % 2 == 0
    if is_even_number_of_slices then
        -- if number_of_slices is 8, both slices are now at 5. Translate opposite_slice 1 more to be at 4
        plib.bounding_box.translate(opposite_slice, sideways, -1)
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
        -- If the segment has a even-size, there's no exact middle. Check if the slice passed the bounds of the segmenent.
        if plib.bounding_box.contains(segment.area_bounds, slice) then
            if area_contains_obstruction(segment.area, slice) then
                slice_result.found_obstruction = true
            else
                slice_result.unobstructed_slice =
                    plib.bounding_box.copy(slice)
            end

            if slice_result.unobstructed_slice and
                slice_result.found_obstruction then
                return slice_result
            end
        end

        -- If the segment has a even-size, there's no exact middle. Check if the slice passed the bounds of the segmenent.
        if plib.bounding_box.contains(segment.area_bounds, opposite_slice) then
            if area_contains_obstruction(segment.area, opposite_slice) then
                opposite_slice_result.found_obstruction = true
            else
                opposite_slice_result.unobstructed_slice =
                    plib.bounding_box.copy(opposite_slice)
            end

            if opposite_slice_result.unobstructed_slice and
                opposite_slice_result.found_obstruction then
                return opposite_slice_result
            end
        end

        plib.bounding_box.translate(slice, sideways, 1)
        plib.bounding_box.translate(opposite_slice, sideways, -1)
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

local function construct_pipes_on_splits(segment, construct_entities)
    if segment.split_direction == "none" then return end

    if segment.split_direction == "split_horizontal" then
        local y = segment.sub_segment_1.area_bounds.right_bottom.y + 1
        if segment.connectable_edges[defines.direction.west] then
            local position = {
                x = segment.sub_segment_1.area_bounds.left_top.x - 1,
                y = y
            }
            add_connector_joint(construct_entities, position)
        end

        if segment.connectable_edges[defines.direction.east] then
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
        if segment.connectable_edges[defines.direction.north] then
            local position = {
                x = x,
                y = segment.sub_segment_1.area_bounds.left_top.y - 1
            }
            add_connector_joint(construct_entities, position)
        end

        if segment.connectable_edges[defines.direction.south] then
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

local function try_connect_extractors(segment)
    local oilwells = find_oilwells(segment)
    local construct_entities = {}

    for i = 1, #oilwells do

        local extractor_position = oilwells[i].position
        oilwells[i].construction_analysis = {}

        for direction, offset in pairs(segment.toolbox.extractor.output_offsets) do
            local pipe_start_position = {
                x = extractor_position.x + offset.x,
                y = extractor_position.y + offset.y
            }

            local pipe_placement_result =
                get_best_pipe_placement_to_edge(segment, pipe_start_position)
            if pipe_placement_result ~= nil then
                pipe_placement_result.pump_direction = direction
                table.insert(oilwells[i].construction_analysis,
                             pipe_placement_result)
            end
        end

        local best_option = get_best_extractor_placement(oilwells[i]
                                                             .construction_analysis)
        if best_option ~= nil then

            add_extractor(construct_entities, extractor_position,
                          best_option.pump_direction)

            for pipe_index = 0, best_option.edge_distance do
                local vector = plib.directions[best_option.edge_direction]
                                   .vector

                vector = math2d.position.multiply_scalar(vector, pipe_index)
                local pipe_position = math2d.position.add(
                                          best_option.pipe_start_position,
                                          vector)

                if pipe_index == 0 then
                    add_output(construct_entities, pipe_position,
                               best_option.pump_direction)
                elseif pipe_index == best_option.edge_distance then
                    add_connector_joint(construct_entities, pipe_position)
                elseif xy.get(construct_entities, pipe_position) == nil then
                    -- outputs or joint take precedence.
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

local split_segment -- defined later

local function segmentate(segment, previous_split)
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
            local split = plib.bounding_box.split(segment.area_bounds,
                                                     split_result.unobstructed_slice)
            split_segment(segment, split.sub_bounds_1, split.sub_bounds_2,
                          next_split)
        end
    elseif next_split == "split_vertical" then
        local split_result = find_split(segment, defines.direction.south)
        if split_result.unobstructed_slice then
            local split = plib.bounding_box.split(segment.area_bounds,
                                                     split_result.unobstructed_slice)

            split_segment(segment, split.sub_bounds_1, split.sub_bounds_2,
                          next_split)
        end
    end
end

split_segment = function (segment, bounds_1, bounds_2, split_direction)
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
        segment.sub_segment_1.connectable_edges[defines.direction.south] = true
        segment.sub_segment_2.connectable_edges[defines.direction.north] = true
    elseif split_direction == "split_vertical" then
        segment.sub_segment_1.connectable_edges[defines.direction.east] = true
        segment.sub_segment_2.connectable_edges[defines.direction.west] = true
    end

    if not try_connect_extractors(segment.sub_segment_1) then
        segmentate(segment.sub_segment_1, split_direction)
    end
    if not try_connect_extractors(segment.sub_segment_2) then
        segmentate(segment.sub_segment_2, split_direction)
    end
end

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
function plan_plumbing(mod_context)
    pump_log(mod_context.area_bounds)
    local base_segment = create_base_segment(mod_context)
    segmentate(base_segment, "none")

    if not verify_all_extractors_connected(base_segment) then
        return {"failure.obstructed-pipe"}
    end

    local construct_entities = {}
    construct_pipes_on_splits(base_segment, construct_entities)
    add_construct_entities_from_segments(base_segment, construct_entities)
    optimize_construct_entities(construct_entities, base_segment.toolbox)

    mod_context.construction_plan = construct_entities    
end