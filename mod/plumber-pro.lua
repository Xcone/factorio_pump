require 'util'
local math2d = require 'math2d'
local plib = require 'plib'
local xy = plib.xy
local PriorityQueue = require("priority-queue")
local assistant = require 'planner-assistant'
require "astar"

local function is_pipe_or_pipe_joint(construct_entity)
    return construct_entity and (construct_entity.name == "pipe" or construct_entity.name == "pipe_joint" or construct_entity.name == "output")
end

local function get_end_of_branch(branch)
    return plib.line.end_position(branch.start_position, branch.direction, branch.length - 1)
end

local function get_pipe_neighbours(mod_context, position)
    local neighbour_pipe_positions = {}
    for direction, toolbox_direction in pairs(plib.directions) do
        local neighbour_position = plib.position.add(position, toolbox_direction.vector)
        local planned = xy.get(mod_context.construction_plan, neighbour_position)
        if is_pipe_or_pipe_joint(planned) then
            neighbour_pipe_positions[direction] = neighbour_position
        end
    end

    return neighbour_pipe_positions
end

local function can_build_connector_on_position(mod_context, position)
    local result = false
    if not assistant.is_position_blocked(mod_context.blocked_positions, position) then
        local planned_entity = xy.get(mod_context.construction_plan, position)
        result = planned_entity == nil or is_pipe_or_pipe_joint(planned_entity)
    end

    return result
end

local function create_extractors_lookup(mod_context)
    local extractors = assistant.find_oilwells(mod_context)
    local extractors_xy = {}
    for _, extractor in pairs(extractors) do
        local extractor_bounds = table.deepcopy(mod_context.toolbox.extractor.relative_bounds)
        plib.bounding_box.offset(extractor_bounds, extractor.position)
        local can_build_extractor = true
        plib.bounding_box.each_grid_position(extractor_bounds, function(position)
            if xy.get(mod_context.area, position) == "can-not-build" then
                can_build_extractor = false
            end
        end)

        if can_build_extractor then
            xy.set(extractors_xy, extractor.position, extractor)
        end
    end

    local extractors_lookup = {
        xy = extractors_xy
    }

    -- First prep, mark all outputs to make them findable    
    xy.each(extractors_lookup.xy, function(extractor, position)
        extractor.outputs = {}
        extractor.is_connected = false

        for output_direction, offset in pairs(mod_context.toolbox.extractor.output_offsets) do
            local output = {
                direction = output_direction,
                position = {
                    x = extractor.position.x + offset.x,
                    y = extractor.position.y + offset.y
                },
                branches = {}
            }

            if can_build_connector_on_position(mod_context, output.position) then
                table.insert(extractor.outputs, output)
            end
        end
    end)

    -- Lookup table to find extractors based on the output position
    -- each position can have multiple extractors
    local extractor_outputs = {}
    xy.each(extractors_lookup.xy, function(extractor, position)
        for _, output in pairs(extractor.outputs) do
            local extractor_output = {
                extractor = extractor,
                output = output
            }
            local extractors_at_output_position = xy.get(extractor_outputs, output.position)
            if not extractors_at_output_position then
                extractors_at_output_position = {}
                xy.set(extractor_outputs, output.position, extractors_at_output_position)
            end
            table.insert(extractors_at_output_position, extractor_output)
        end
    end)

    extractors_lookup.by_output_xy = extractor_outputs
    return extractors_lookup
end

local function remove_extractor_output_candidate(extractors_lookup, extractor, position)
    local extractors_at_output_position = xy.get(extractors_lookup.by_output_xy, position)

    -- Remove from the outputs_by_xy
    if extractors_at_output_position then -- Might not be in the lookup in this position, if the output is blocked
        for i, extractor_output in pairs(extractors_at_output_position) do
            if extractor == extractor_output.extractor then
                extractors_at_output_position[i] = nil
            end
        end

        if next(extractors_at_output_position) == nil then
            xy.remove(extractors_lookup.by_output_xy, position)
        end
    end

    -- Remove from extractor.outputs
    for i, output in pairs(extractor.outputs) do
        if output.position.x == position.x and output.position.y == position.y then
            extractor.outputs[i] = nil
        end
    end
    xy.remove(extractors_lookup.by_output_xy, position)

end

local function commit_extractor_output(mod_context, extractors_lookup, extractor, connected_direction)
    for output_direction, offset in pairs(mod_context.toolbox.extractor.output_offsets) do
        local output_position = plib.position.add(extractor.position, offset)
        if connected_direction == output_direction then
            -- Mark the connected output; keep the connected output in the lookup table as it might be useful in later steps
            extractor.connected_output_position = output_position
        else
            -- Remove the candidate output position that didn't make it.
            remove_extractor_output_candidate(extractors_lookup, extractor, output_position)
        end
    end
end

local function commit_construction_plan(mod_context, extractors_lookup, construction_plan)
    xy.each(construction_plan, function(planned_entity, position)
        xy.set(mod_context.construction_plan, position, table.deepcopy(planned_entity))
        if planned_entity.name == "pipe_tunnel" then
            -- We can be flexible with pipes in order to connect from every direction, and even overwrite a pipe to a joint or output.
            -- However, tunnels are final.
            -- Extractors are already on the block-list due they reserved space in the planner_input so they dont need this exception.
            xy.set(mod_context.blocked_positions, position, true)
            local extractors_at_output_position = xy.get(extractors_lookup.by_output_xy, position)
            if extractors_at_output_position then
                for i, extractor_output in pairs(extractors_at_output_position) do
                    remove_extractor_output_candidate(extractors_lookup, extractor_output.extractor, position)
                end
            end
        end
    end)
end

local function commit_extractor_plan(mod_context, extractors_lookup, extractor)
    assistant.add_extractor(mod_context.construction_plan, extractor.position, extractor.scored_plan.output_direction)
    extractor.is_connected = true
    commit_construction_plan(mod_context, extractors_lookup, extractor.scored_plan.construction_plan)
    commit_extractor_output(mod_context, extractors_lookup, extractor, extractor.scored_plan.output_direction)

    for _, other_extractor in pairs(extractor.scored_plan.other_extractor_output_hits) do
        other_extractor.extractor.is_connected = true
        assistant.add_extractor(mod_context.construction_plan, other_extractor.extractor.position, other_extractor.output.direction)
        assistant.add_output(mod_context.construction_plan, other_extractor.output.position, other_extractor.output.direction)
        commit_extractor_output(mod_context, extractors_lookup, other_extractor.extractor, other_extractor.output.direction)
    end
end

local function get_extractors_in_reach_of_branch(extractors_lookup, branch)
    local next_vector = plib.directions[plib.directions[branch.direction].next].vector
    local previous_vector = plib.directions[plib.directions[branch.direction].previous].vector

    local branch_reach_distance = 12
    local branch_end_position = get_end_of_branch(branch)

    local pos_a = plib.position.add(branch.start_position, math2d.position.multiply_scalar(next_vector, branch_reach_distance))
    local pos_b = plib.position.add(branch_end_position, math2d.position.multiply_scalar(previous_vector, branch_reach_distance))
    local branch_reach_bounds = plib.bounding_box.create(pos_a, pos_b)

    local extractors_in_reach = {}
    xy.each(extractors_lookup.xy, function(extractor, position)
        if plib.bounding_box.contains_position(branch_reach_bounds, position) then
            table.insert(extractors_in_reach, extractor)
        end
    end)

    return extractors_in_reach
end

local function commit_branch(mod_context, extractors_lookup, branch)
    branch.connectable_positions = {}

    xy.each(branch.construction_plan, function(value, position)
        if is_pipe_or_pipe_joint(value) then
            xy.set(branch.connectable_positions, position, true)
        end
    end)

    commit_construction_plan(mod_context, extractors_lookup, branch.construction_plan)

    local extractors_in_reach = get_extractors_in_reach_of_branch(extractors_lookup, branch)

    for _, extractor in pairs(extractors_in_reach) do
        extractor.is_in_reach_of_branch = true
    end
end

function plan_pipe_line(mod_context, start_position, direction, length)
    local sample_start = pump_sample_start()
    local plan = {}
    local has_placed_first_pipe = false
    local tunnel_start_position = nil

    local position = start_position
    local offset = plib.directions[direction].vector
    local actual_length = 0
    local tunnel_count = 0
    local connector_count = 0
    local tunnel_gap = 0

    for i = 1, length do
        local next_position = plib.position.add(position, offset)

        if can_build_connector_on_position(mod_context, position) then
            if tunnel_start_position ~= nil then
                if tunnel_gap > mod_context.toolbox.connector.underground_distance_max then
                    -- When only illegal branches are available, put down the pipe as far as it'll go and then stop.
                    -- With luck all pumps can still connect and it doesn't matter it stopped earlier.
                    break
                end

                -- Cant end the tunnel now if the next position is not builable; another space is needed to start a new tunnel if needed.
                -- So if there's not space, the current tunnel needs to continue.
                if can_build_connector_on_position(mod_context, next_position) then
                    assistant.add_pipe_tunnel(plan, tunnel_start_position, position, mod_context.toolbox)
                    tunnel_count = tunnel_count + 1
                    tunnel_start_position = nil
                else
                    tunnel_gap = tunnel_gap + 1
                end
            else
                assistant.add_connector(plan, position)
                connector_count = connector_count + 1
            end

            has_placed_first_pipe = true
        else
            if not has_placed_first_pipe then
                -- Need to have at least 1 tile to start a tunnel
                break
            end
            if has_placed_first_pipe and not tunnel_start_position then
                -- Can't build here, consider the previous tile the tunnel start.
                tunnel_start_position = plib.position.subtract(position, offset)
                tunnel_gap = 1
            else
                tunnel_gap = tunnel_gap + 1
            end
        end

        position = next_position
        actual_length = actual_length + 1
    end

    pump_sample_finish("plan_pipe_line", sample_start)

    return plan, actual_length, connector_count, tunnel_count
end

function create_branch_candidate(mod_context, extractors_lookup, slice, branch_length, branch_direction, parent_branch, extra_penalty)
    local sample_start = pump_sample_start()

    local branch_candidate = {}
    local branch_position = {
        x = slice.left_top.x,
        y = slice.left_top.y
    }
    branch_position = plib.directions[plib.directions[branch_direction].opposite].to_edge(slice, branch_position)
    branch_candidate.start_position = table.deepcopy(branch_position)
    branch_candidate.length = branch_length
    branch_candidate.direction = branch_direction
    branch_candidate.parent_branch = parent_branch
    branch_candidate.is_invalid = false
    branch_vector = plib.directions[branch_direction].vector

    local extractors_in_reach = get_extractors_in_reach_of_branch(extractors_lookup, branch_candidate)

    for i, extractor in pairs(extractors_in_reach) do
        -- Already in reach of another branch, no need to cover it twice
        if extractor.is_in_reach_of_branch then
            extractors_in_reach[i] = nil
        end
    end

    branch_candidate.number_of_extractors_in_reach = #extractors_in_reach
    if branch_candidate.number_of_extractors_in_reach < 2 then
        -- There's no point to a branch if nothing connects to it. 
        -- A single extractor would be better of directly connecting to something nearby
        return nil
    end

    local plan, actual_length, connector_count, tunnel_count = plan_pipe_line(mod_context, branch_candidate.start_position, branch_direction, branch_length)

    if actual_length < 5 then
        -- Too short to be worth it
        return nil
    end

    branch_candidate.construction_plan = plan

    if actual_length ~= branch_length then
        branch_candidate.is_invalid = true
        branch_candidate.length = actual_length
    end

    local score = 0

    -- Bonus points for each extractor in range
    score = score + branch_candidate.number_of_extractors_in_reach

    -- Big penalty if the branch requires an underground segment of pipes longer then the pipe supports.
    -- It basically makes this branch unusable for everything  after this tunnel

    if branch_candidate.is_invalid then
        score = score - 9999
    end

    if parent_branch then
        local connection_point = plib.position.subtract(branch_candidate.start_position, branch_vector)
        -- Medium penalty of the branch doesn't connect to trunk; can be remedied in later stages.
        if xy.get(parent_branch.connectable_positions, connection_point) then
            branch_candidate.is_connected_to_parent = true
            branch_candidate.connection_point = connection_point
        else
            score = score - 10
        end
    end

    branch_candidate.slice = plib.bounding_box.copy(slice)

    -- Small penalty for every tile that is not a connector
    score = score - (branch_length - connector_count)

    branch_candidate.score = score - extra_penalty

    pump_sample_finish("create_branch_candidate", sample_start)

    return branch_candidate
end

function find_best_branch(mod_context, extractors_lookup, search_area, branch_direction, parent_branch, committed_branches)
    local sample_start = pump_sample_start()

    local branch_length = plib.bounding_box.get_cross_section_size(search_area, branch_direction)
    local branch_candidate_count = plib.bounding_box.get_cross_section_size(search_area, plib.directions[branch_direction].next)

    local start_slice = plib.bounding_box.copy(search_area)
    plib.bounding_box.squash(start_slice, plib.directions[branch_direction].previous)

    local best_branch = nil

    -- Same parent branch, same side
    local neighbour_branches = {}

    -- NOTE: This isn't fully safe; and only works because there's 1 trunk and 1 set of branches.
    -- If there's another layer of branches, this needs refinement.
    for _, branch in pairs(committed_branches) do
        if branch.direction == branch_direction then
            table.insert(neighbour_branches, branch)
        end
    end
    local has_neighbour_branch = next(neighbour_branches) ~= nil

    -- Prefer middle of the area for the trunk
    local ideal_distance = branch_candidate_count / 2
    -- For branches prefer a distance between branches that each pump can connect with a single tunnel
    if parent_branch ~= nil then
        ideal_distance = mod_context.toolbox.connector.underground_distance_max;
        if has_neighbour_branch then
            -- tunnel can go both ways, so count twice the tunnel distance.
            ideal_distance = ideal_distance * 2
        end
    end

    local start_candidate = 1
    if next(neighbour_branches) ~= nil then
        -- (almost) touching branches is pointless. Skip the first set of positions if this is not the first branch.
        start_candidate = 4
    end

    local slice_offsets_by_distance_from_ideal = PriorityQueue();

    for i = start_candidate, branch_candidate_count do
        slice_offsets_by_distance_from_ideal:put(i, math.abs(ideal_distance - i))
    end

    local iterations = 0
    local slice_index = slice_offsets_by_distance_from_ideal:pop()
    while slice_index do
        if best_branch then
            local connection_check = not parent_branch or (best_branch.is_connected_to_parent)

            if iterations > 5 and connection_check and best_branch.score > 3 then
                -- Got a near-perfect match in the 5 attempts. Just take it and save the computations.       
                break
            end

            if best_branch.score > 0 and iterations > 15 then
                -- after 15 attempt we went 7 positions either way, enough width to seach between 4 pumps next to each other
                -- if there is a suitable branch, just take it as it's getting expensive.                                
                break
            end
        end

        -- A good spread of branches is preferred. So add penalty if the branch deviates from the preferred location
        local score_offset = math.abs(ideal_distance - slice_index)
        local slice = table.deepcopy(start_slice)
        plib.bounding_box.translate(slice, plib.directions[branch_direction].next, slice_index - 1)

        local branch_candidate = create_branch_candidate(mod_context, extractors_lookup, slice, branch_length, branch_direction, parent_branch, score_offset)

        if branch_candidate ~= nil and (best_branch == nil or branch_candidate.score > best_branch.score) then
            best_branch = branch_candidate
        end

        iterations = iterations + 1
        slice_index = slice_offsets_by_distance_from_ideal:pop()
    end

    pump_sample_finish("find_best_branch", sample_start)

    return best_branch
end

function plan_branches(mod_context, extractors_lookup, branch_area, branch_direction, parent_branch, commited_branches)
    local pending_branch_areas = {}
    table.insert(pending_branch_areas, {
        branch_area = branch_area,
        branch_direction = branch_direction
    })

    local branch_length = plib.bounding_box.get_cross_section_size(branch_area, branch_direction)    
    if branch_length < 8 then
        return
    end

    local previous_brach = nil

    while #pending_branch_areas > 0 do
        local pending_branch_area = table.remove(pending_branch_areas)
        local branch_area = pending_branch_area.branch_area
        local branch_direction = pending_branch_area.branch_direction

        -- Make at least one branch.
        local branch = find_best_branch(mod_context, extractors_lookup, pending_branch_area.branch_area, pending_branch_area.branch_direction, parent_branch, commited_branches)

        if not branch or not branch.is_connected_to_parent then
            break
        end

        -- Make branches aware of each other. Useful in a later step to interconnect branches when one can't connect to the trunk
        commit_branch(mod_context, extractors_lookup, branch)
        branch.previous_branch = previous_brach
        if previous_brach then
            previous_brach.next_branch = branch
        end
        previous_brach = branch
        table.insert(commited_branches, branch)

        split_result = plib.bounding_box.directional_split(branch_area, branch.slice, branch.direction)
        local pending_area = split_result.right
        -- Make additional branches if the area big enough. Ideally pumps are but 1 tunnel-distance away
        if plib.bounding_box.get_cross_section_size(pending_area, plib.directions[branch_direction].next) > mod_context.toolbox.connector.underground_distance_max then
            table.insert(pending_branch_areas, {
                branch_area = pending_area,
                branch_direction = branch_direction
            })
        end
    end
end

local function resolve_extractor_direction(extractor, output_position)

    for _, output in pairs(extractor.outputs) do
        if output.position.x == output_position.x and output.position.y == output_position.y then
            return output.direction
        end
    end

    error("Position is not a candidate output position")
end

local function convert_astar_result_to_pipe(reached_pipe)
    local construction_plan = {}

    -- Mark joint, to keep it above ground when burying pipes
    assistant.add_connector_joint(construction_plan, reached_pipe.position)
    local previous_pipe = reached_pipe
    local pipe = reached_pipe.parent

    while pipe do
        assistant.add_connector(construction_plan, pipe.position)
        previous_pipe = pipe
        pipe = pipe.parent
    end

    return construction_plan, previous_pipe.position
end

local function try_connect_extractor_to_nearby_pipes(mod_context, extractors_lookup, extractor, max_distance_from_extractor)
    local sample_start = pump_sample_start();

    local output_positions = {}
    for _, output in pairs(extractor.outputs) do
        table.insert(output_positions, output.position)
    end

    -- First search area is the edge around the extractor
    local search_bounds = table.deepcopy(mod_context.toolbox.extractor.relative_bounds)    
    plib.bounding_box.offset(search_bounds, extractor.position)
    plib.bounding_box.grow(search_bounds, max_distance_from_extractor * 2)
    plib.bounding_box.clamp(search_bounds, mod_context.area_bounds)

    local sample_neaby_pipes_start = pump_sample_start();

    local nearby_pipe_positions_by_distance = PriorityQueue()
    plib.bounding_box.each_grid_position(search_bounds, function(position)
        if is_pipe_or_pipe_joint(xy.get(mod_context.construction_plan, position)) then
            nearby_pipe_positions_by_distance:put(position, plib.position.taxicab_distance(position, extractor.position))
        end
    end)

    pump_sample_finish("sample_neaby_pipes", sample_neaby_pipes_start);

    if nearby_pipe_positions_by_distance:size() > 0 then
        local nearby_pipe_positions = {}
        
        while #nearby_pipe_positions < 10 and nearby_pipe_positions_by_distance:peek() do
            local p = nearby_pipe_positions_by_distance:pop()
            table.insert(nearby_pipe_positions, p)
        end
        
        local reached_pipe = astar(output_positions, nearby_pipe_positions, search_bounds, mod_context.blocked_positions, heuristic_score_taxicab, max_distance_from_extractor * 2)
        if reached_pipe then
            local construction_plan, start_position = convert_astar_result_to_pipe(reached_pipe)
            local direction = resolve_extractor_direction(extractor, start_position)

            extractor.scored_plan = {
                construction_plan = construction_plan,
                other_extractor_output_hits = {},
                output_direction = direction
            }
        end
    end

    pump_sample_finish("try_connect_extractor_to_nearby_pipes", sample_start);
end

local function try_connect_extractor_to_nearby_extractors(mod_context, extractors_lookup, extractor)
    local sample_start = pump_sample_start()
    local start_positions = {}
    for _, output in pairs(extractor.outputs) do
        table.insert(start_positions, output.position)
    end

    local goal_positions = {}
    xy.each(extractors_lookup.by_output_xy, function(extractor_outputs, ouput_position)
        for _, extractor_output in pairs(extractor_outputs) do
            if extractor_output.extractor.is_connected then
                table.insert(goal_positions, extractor_output.output.position)
            end
        end
    end)

    if next(goal_positions) then
        local reached_pipe = astar(start_positions, goal_positions, mod_context.area_bounds, mod_context.blocked_positions, heuristic_score_taxicab)
        if reached_pipe then
            local construction_plan, start_position = convert_astar_result_to_pipe(reached_pipe)
            local direction = resolve_extractor_direction(extractor, start_position)

            extractor.scored_plan = {
                construction_plan = construction_plan,
                other_extractor_output_hits = {},
                output_direction = direction
            }
        end
    else
        error("Nothing to connect to")
    end

    pump_sample_finish("try_connect_extractor_to_nearby_extractors", sample_start)
end

local function try_connect_extractor_to_branch_using_tunnels(mod_context, extractors_lookup, extractor)
    -- Long range, straight_search. This includes tunneling underneath obstacles, like other pumps or water.
    for _, output in pairs(extractor.outputs) do
        for direction, branch_intersection in pairs(output.branches) do
            local other_extractor_output_hits = {}
            local end_position = plib.line.end_position(output.position, direction, branch_intersection.tile_count - 1)

            local construction_plan = plan_pipe_line(mod_context, output.position, direction, branch_intersection.tile_count)
            branch_intersection.can_build = is_pipe_or_pipe_joint(xy.get(construction_plan, output.position)) and is_pipe_or_pipe_joint(xy.get(construction_plan, end_position))

            xy.each(construction_plan, function(planned, position)
                if planned.name == "pipe" then
                    local extractor_outputs_at_position = xy.get(extractors_lookup.by_output_xy, position)
                    if extractor_outputs_at_position ~= nil then
                        for _, extractor_output in pairs(extractor_outputs_at_position) do
                            if not extractor_output.extractor.is_connected then
                                table.insert(other_extractor_output_hits, extractor_output)
                            end
                        end
                    end
                end
            end)

            if branch_intersection.can_build then
                assistant.add_output(construction_plan, output.position, output.direction)
                assistant.add_connector_joint(construction_plan, end_position)

                local score_extra_outputs = #other_extractor_output_hits * 3
                local score_distance = 15 - branch_intersection.tile_count

                local scored_plan = {
                    score = score_distance + score_extra_outputs,
                    output_direction = output.direction,
                    construction_plan = construction_plan,
                    other_extractor_output_hits = other_extractor_output_hits
                }

                if not extractor.scored_plan or extractor.scored_plan.score < scored_plan.score then
                    extractor.scored_plan = scored_plan
                end
            end
        end
    end

end

function connect_extractors(mod_context, extractors_lookup, committed_branches)
    local search_range = 15

    -- Find the quick wins. The outputs that are already directly on one of the branches
    xy.each(extractors_lookup.xy, function(extractor, position)
        for _, output in pairs(extractor.outputs) do
            local planned_construction = xy.get(mod_context.construction_plan, output.position)
            local output_touches_existing_pipe = is_pipe_or_pipe_joint(planned_construction) or next(get_pipe_neighbours(mod_context, output.position)) ~= nil

            if output_touches_existing_pipe then
                local construction_plan = {}
                assistant.add_extractor(construction_plan, extractor.position, output.direction)
                assistant.add_output(construction_plan, output.position, output.direction)
                local scored_plan = {
                    output_direction = output.direction,
                    construction_plan = construction_plan,
                    other_extractor_output_hits = {}
                }
                extractor.scored_plan = scored_plan
                commit_extractor_plan(mod_context, extractors_lookup, extractor)
                break
            end
        end
    end)

    -- Find the nearest branches in each direction for each extractor and the individual outputs
    xy.each(extractors_lookup.xy, function(extractor, position)
        extractor.distance_to_branch = 999
        for _, branch in pairs(committed_branches) do
            local branch_end = get_end_of_branch(branch)
            for direction, _ in pairs(plib.directions) do
                local extractor_to_branch_search_end = plib.line.end_position(extractor.position, direction, search_range)
                local intersects, intersection_point = plib.line.intersects(extractor.position, extractor_to_branch_search_end, branch.start_position, branch_end)

                if (intersects) then
                    local extractor_distance_to_branch = plib.line.count_tiles(extractor.position, intersection_point)
                    if extractor_distance_to_branch < extractor.distance_to_branch then
                        extractor.distance_to_branch = extractor_distance_to_branch
                    end
                end

                for _, output in pairs(extractor.outputs) do
                    local output_search_end = plib.line.end_position(output.position, direction, search_range)
                    intersects, intersection_point = plib.line.intersects(output.position, output_search_end, branch.start_position, branch_end)

                    if intersects then
                        local new_tile_count = plib.line.count_tiles(output.position, intersection_point)
                        if output.branches[direction] ~= nil then
                            if new_tile_count < output.branches[direction].tile_count then
                                output.branches[direction] = {
                                    branch = branch,
                                    intersection_point = intersection_point,
                                    tile_count = new_tile_count
                                }
                            end
                        else
                            output.branches[direction] = {
                                branch = branch,
                                intersection_point = intersection_point,
                                tile_count = new_tile_count
                            }
                        end
                    end
                end
            end
        end
    end)

    -- Prioritize extractors further away from a branch, to increase the odds of a pipe-line connecting to another output along the way
    local extractors_by_branch_distance = PriorityQueue()
    xy.each(extractors_lookup.xy, function(extractor, position)
        extractors_by_branch_distance:put(extractor, 0 - extractor.distance_to_branch)
    end)

    local extractor = extractors_by_branch_distance:pop()
    while (extractor) do
        if not extractor.is_connected then
            -- Short range search, in case the pump is really close to of a branch or another pipe that was already committed
            try_connect_extractor_to_nearby_pipes(mod_context, extractors_lookup, extractor, 4)

            if not extractor.scored_plan then
                try_connect_extractor_to_branch_using_tunnels(mod_context, extractors_lookup, extractor)
            end

            if extractor.scored_plan then
                commit_extractor_plan(mod_context, extractors_lookup, extractor)
            else
                pump_log("Simple plan failed. Do astar instead")
            end
        end

        extractor = extractors_by_branch_distance:pop()
    end
end

local function is_pipe_flanked(entity_on_flank, connecting_direction)
    if entity_on_flank == nil or entity_on_flank.name == "extractor" then
        return false
    end

    if entity_on_flank.name == "pipe_tunnel" and entity_on_flank.direction ~= connecting_direction then
        return false
    end
    return true
end

local function prune_pipe_dead_end(mod_context, start_position, prune_direction, max_length)
    local plan = mod_context.construction_plan

    local flank_previous_direction = plib.directions[prune_direction].previous
    local flank_previous_vector = plib.directions[flank_previous_direction].vector
    local flank_next_direction = plib.directions[prune_direction].next

    local flank_next_vector = plib.directions[flank_next_direction].vector
    local branch_has_connections = false
    local is_tunneling = false

    plib.line.trace(start_position, prune_direction, max_length, function(position)
        local planned = xy.get(plan, position)
        local planned_is_tunnel = planned ~= nil and planned.name == "pipe_tunnel"
        if not planned_is_tunnel then

            if planned and (planned.name == "output" or planned.name == "pipe_joint") then
                branch_has_connections = true
                return true
            end

            local flank_position = plib.position.add(position, flank_next_vector)
            planned = xy.get(plan, flank_position)

            if is_pipe_flanked(planned, flank_previous_vector) then
                branch_has_connections = true
                return true
            end

            flank_position = plib.position.add(position, flank_previous_vector)
            planned = xy.get(plan, flank_position)
            if is_pipe_flanked(planned, flank_next_direction) then
                branch_has_connections = true
                return true
            end
        end

        if not is_tunneling or planned_is_tunnel then
            xy.remove(plan, position)
        end

        if planned_is_tunnel then
            is_tunneling = not is_tunneling
        end
    end)

    return branch_has_connections
end

local function optimize_pipes(mod_context, branches)
    local trunk = nil

    for _, branch in pairs(branches) do
        if branch.parent_branch then
            local branch_has_connections = prune_pipe_dead_end(mod_context, get_end_of_branch(branch), plib.directions[branch.direction].opposite, branch.length)
            if branch_has_connections and branch.is_connected_to_parent then
                assistant.add_connector_joint(mod_context.construction_plan, branch.connection_point)
            end
        else
            trunk = branch
        end
    end

    if trunk then
        -- Trunk is pruned last, to allow an unused branch to be removed.
        -- Trunk is also pruned on both ends as it doesnt connect on either side
        prune_pipe_dead_end(mod_context, trunk.start_position, trunk.direction, trunk.length)
        prune_pipe_dead_end(mod_context, get_end_of_branch(trunk), plib.directions[trunk.direction].opposite, trunk.length)
    end

    assistant.create_tunnels_between_joints(mod_context.construction_plan, mod_context.toolbox)
end

function plan_plumbing_pro(mod_context)
    mod_context.construction_plan = {}
    mod_context.blocked_positions = {}

    -- Settings, maybe? For now just debug purpose.
    local use_trunk = true
    local use_branches = true

    xy.each(mod_context.area, function(reservation, pos)
        if reservation ~= "can-build" then
            xy.set(mod_context.blocked_positions, pos, true)
        end
    end)

    local extractors_lookup = create_extractors_lookup(mod_context)

    local trunk_area = plib.bounding_box.copy(mod_context.area_bounds)
    local vertical_size = plib.bounding_box.get_cross_section_size(trunk_area, defines.direction.north)
    local horizontal_size = plib.bounding_box.get_cross_section_size(trunk_area, defines.direction.east)

    -- By default, prefer to keep the trunk short (future setting?)
    -- Rationale being that branches reach out on both sides. So the length of the trunk and the branches should be slightly more similar.
    local trunk_direction = defines.direction.south
    local trunk_length = vertical_size
    if horizontal_size >= vertical_size then
        trunk_direction = defines.direction.east
        trunk_length = horizontal_size
    end    

    if use_trunk and trunk_length > 10 then

        local committed_branches = {}
        pump_lap("done initial prep")

        -- Trunk is just the first branch
        local trunk = find_best_branch(mod_context, extractors_lookup, trunk_area, trunk_direction, nil, committed_branches)
        if trunk then
            commit_branch(mod_context, extractors_lookup, trunk)
            table.insert(committed_branches, trunk)
            pump_lap("got trunk")
            if use_branches then
                local split_area = plib.bounding_box.directional_split(trunk_area, trunk.slice, trunk_direction)

                plan_branches(mod_context, extractors_lookup, split_area.right, plib.directions[trunk_direction].next, trunk, committed_branches)
                plan_branches(mod_context, extractors_lookup, split_area.left, plib.directions[trunk_direction].previous, trunk, committed_branches)
                pump_lap("got branches")
            end

            connect_extractors(mod_context, extractors_lookup, committed_branches)
            pump_lap("extractors connected to branches")
        end

        optimize_pipes(mod_context, committed_branches)
    end

    local has_connected_extractor = xy.any(xy.where(extractors_lookup.xy, function(extractor, position)
        return extractor.is_connected
    end))
    if not has_connected_extractor then
        pump_log("picking default extractor")
        -- Connect to first available output and hope the rest can A* back to it.
        xy.first(extractors_lookup.by_output_xy, function(extractor_outputs, position)
            local construction_plan = {}
            local _, extractor_output = next(extractor_outputs)
            
            assistant.add_extractor(construction_plan, extractor_output.extractor.position, extractor_output.output.direction)
            assistant.add_output(construction_plan, position, extractor_output.output.direction)

            extractor_output.extractor.scored_plan = {
                construction_plan = construction_plan,
                other_extractor_output_hits = {},
                output_direction = extractor_output.output.direction
            }

            commit_extractor_plan(mod_context, extractors_lookup, extractor_output.extractor)
        end)
    end

    local pending_extractors = PriorityQueue()

    xy.each(extractors_lookup.xy, function(extractor, position)
        if not extractor.is_connected then
            local closest_connected_extractor_distance = nil
            local closest_connected_extractor = nil
            xy.each(extractors_lookup.xy, function(other_extractor, other_position)
                if other_extractor.is_connected then
                    local other_connector_distance = math2d.position.distance_squared(extractor.position, other_extractor.position)
                    if not closest_connected_extractor or other_connector_distance < closest_connected_extractor_distance then
                        closest_connected_extractor_distance = other_connector_distance
                        closest_connected_extractor = other_extractor
                    end
                end
            end)

            pending_extractors:put(extractor, closest_connected_extractor_distance)
        end
    end)

    local pending_extractor = pending_extractors:pop()
    while pending_extractor do
        -- Look for other pipes further out then the first attempt
        try_connect_extractor_to_nearby_pipes(mod_context, extractors_lookup, pending_extractor, 10)
        if not pending_extractor.scored_plan then
            try_connect_extractor_to_nearby_extractors(mod_context, extractors_lookup, pending_extractor)
        end
        if pending_extractor.scored_plan then
            commit_extractor_plan(mod_context, extractors_lookup, pending_extractor)
        else
            mod_context.failure = "Not all extractors are connected. "
        end

        pending_extractor = pending_extractors:pop()
    end

    pump_lap("remaining extractor connections made with fallback")
end
