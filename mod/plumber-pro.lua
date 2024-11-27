require 'util'
local math2d = require 'math2d'
local plib = require 'plib'
local xy = plib.xy
local PriorityQueue = require("priority-queue")
local assistant = require 'planner-assistant'
local star = require "astar"

local function is_pipe_or_pipe_joint(construct_entity)
    return construct_entity and (construct_entity.name == "pipe" or construct_entity.name == "pipe_joint" or construct_entity.name == "output")
end

local function commit_construction_plan(mod_context, construction_plan)
    xy.each(construction_plan, function(planned_entity, position)
        xy.set(mod_context.construction_plan, position, table.deepcopy(planned_entity))
        if planned_entity.name == "pipe_tunnel" then
            -- We can be flexible with pipes in orde to connect from every direction, and even overwrite a pipe to a joint or output.
            -- However, tunnels are final.
            -- Extractors are already on the block-list due they reserved space in the planner_input so they dont need this exception.
            xy.set(mod_context.blocked_positions, position, true)
        end
    end)
end

local function can_build_connector_on_position(mod_context, position)
    local result = false
    if not assistant.is_position_blocked(mod_context.blocked_positions, position) then
        local planned_entity = xy.get(mod_context.construction_plan, position)
        result = planned_entity == nil or is_pipe_or_pipe_joint(planned_entity)
    end

    return result
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

function create_branch_candidate(mod_context, slice, branch_length, branch_direction, parent_branch, extra_penalty)
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

    local plan, actual_length, connector_count, tunnel_count = plan_pipe_line(mod_context, branch_candidate.start_position, branch_direction, branch_length)
    branch_candidate.construction_plan = plan

    if actual_length ~= branch_length then
        branch_candidate.is_invalid = true
        branch_candidate.length = actual_length
    end

    -- Big penalty if the branch requires an underground segment of pipes longer then the pipe supports.
    -- It basically makes this branch unusable
    local penalty = 0
    if branch_candidate.is_invalid then
        penalty = penalty + 9999
    end

    if parent_branch then
        local connection_point = plib.position.subtract(branch_candidate.start_position, branch_vector)
        -- Medium penalty of the branch doesn't connect to trunk; can be remedied in later stages.
        if xy.get(parent_branch.connectable_positions, connection_point) then
            branch_candidate.is_connected_to_parent = true
            branch_candidate.connection_point = connection_point
        else
            penalty = penalty + 10
        end
    end

    branch_candidate.slice = plib.bounding_box.copy(slice)

    -- Small penalty for every tile that is not a connector
    penalty = penalty + (branch_length - connector_count)

    branch_candidate.penalty = penalty + extra_penalty

    pump_sample_finish("create_branch_candidate", sample_start)

    return branch_candidate
end

function find_best_branch(mod_context, search_area, branch_direction, parent_branch, committed_branches)
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

            if iterations > 5 and connection_check and best_branch.penalty < 3 then
                -- Got a near-perfect match in the 5 attempts. Just take it and save the computations.                
                break
            end

            if best_branch.penalty < 10 and iterations > 15 then
                -- after 15 attempt we went 7 positions either way, enough width to seach between 4 pumps next to each other
                -- if there is a suitable branch, just take it as it's getting expensive.                
                break
            end
        end

        -- A good spread of branches is preferred. So add penalty if the branch deviates from the preferred location
        local score_offset = math.abs(ideal_distance - slice_index)
        local slice = table.deepcopy(start_slice)
        plib.bounding_box.translate(slice, plib.directions[branch_direction].next, slice_index - 1)

        local branch_candidate = create_branch_candidate(mod_context, slice, branch_length, branch_direction, parent_branch, score_offset)

        if best_branch == nil or best_branch.penalty > branch_candidate.penalty then
            best_branch = branch_candidate
        end

        iterations = iterations + 1
        slice_index = slice_offsets_by_distance_from_ideal:pop()
    end

    pump_sample_finish("find_best_branch", sample_start)

    return best_branch
end

function commit_branch(mod_context, branch)
    branch.connectable_positions = {}

    xy.each(branch.construction_plan, function(value, position)
        if is_pipe_or_pipe_joint(value) then
            xy.set(branch.connectable_positions, position, true)
        end
    end)

    commit_construction_plan(mod_context, branch.construction_plan)
end

function plan_branches(mod_context, branch_area, branch_direction, parent_branch, commited_branches)
    local pending_branch_areas = {}
    table.insert(pending_branch_areas, {
        branch_area = branch_area,
        branch_direction = branch_direction
    })

    local previous_brach = nil

    while #pending_branch_areas > 0 do
        local pending_branch_area = table.remove(pending_branch_areas)
        local branch_area = pending_branch_area.branch_area
        local branch_direction = pending_branch_area.branch_direction

        -- Make at least one branch.
        local branch = find_best_branch(mod_context, pending_branch_area.branch_area, pending_branch_area.branch_direction, parent_branch, commited_branches)

        -- Make branches aware of each other. Useful in a later step to interconnect branches when one can't connect to the trunk
        commit_branch(mod_context, branch)
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

local function try_connect_extractor_to_nearby_pipes(mod_context, extractor, max_search_iterations)    
    local sample_start = pump_sample_start();
    
    local output_positions = {}
    for _, output in pairs(extractor.outputs) do
        table.insert(output_positions, output.position)
    end

    -- First search area is the edge around the extractor
    local search_bounds = table.deepcopy(mod_context.toolbox.extractor.relative_bounds)
    plib.bounding_box.offset(search_bounds, extractor.position)
    plib.bounding_box.grow(search_bounds, 1)
    plib.bounding_box.clamp(search_bounds, mod_context.area_bounds)

    -- Search area is grown each iteration, and the edge of the area is checked for existing pipes. 
    -- When pipes are found, A* is used to try and connect, in case it needs a little bend, or 2

    for i = 1, max_search_iterations do
        local nearby_pipes = {}

        plib.bounding_box.each_edge_position(search_bounds, function(position)
            if is_pipe_or_pipe_joint(xy.get(mod_context.construction_plan, position)) then
                table.insert(nearby_pipes, position)
            end
        end)

        if next(nearby_pipes) ~= nil then
            local reached_pipe = astar(output_positions, nearby_pipes, search_bounds, mod_context.blocked_positions, heuristic_score_taxicab)
            if reached_pipe then
                local construction_plan = {}

                assistant.add_connector_joint(construction_plan, reached_pipe.position)
                local parent_pipe = reached_pipe.parent
                local direction = nil
                while parent_pipe do
                    if parent_pipe.parent == nil then
                        for _, output in pairs(extractor.outputs) do
                            if output.position.x == parent_pipe.position.x and output.position.y == parent_pipe.position.y then
                                direction = output.direction
                                assistant.add_output(construction_plan, parent_pipe.position, direction)
                            end
                        end

                        parent_pipe = nil
                    else
                        assistant.add_connector(construction_plan, parent_pipe.position)
                        parent_pipe = parent_pipe.parent
                    end
                end

                if not direction then
                    error("Path does not reach output")
                end

                extractor.scored_plan = {
                    construction_plan = construction_plan,
                    other_extractor_output_hits = {},
                    output_direction = direction
                }
                shortrange = true
            end
        end

        plib.bounding_box.grow(search_bounds, 1)
        plib.bounding_box.clamp(search_bounds, mod_context.area_bounds)
    end

    pump_sample_finish("try_connect_extractor_to_nearby_pipes", sample_start);
end

function connect_extractors(mod_context, extractors_lookup, committed_branches)
    local search_range = 15

    -- Find the quick wins. The outputs that are already directly on one of the branches
    xy.each(extractors_lookup.xy, function(extractor, position)
        for _, output in pairs(extractor.outputs) do
            local planned_construction = xy.get(mod_context.construction_plan, output.position)
            if is_pipe_or_pipe_joint(planned_construction) then
                assistant.add_extractor(mod_context.construction_plan, extractor.position, output.direction)
                assistant.add_output(mod_context.construction_plan, output.position, output.direction)
                extractor.is_connected = true                
                break
            end
        end
    end)

    -- Find the nearest branches in each direction for each extractor and the individual outputs
    xy.each(extractors_lookup.xy, function(extractor, position)
        extractor.distance_to_branch = 999
        for _, branch in pairs(committed_branches) do
            local branch_end = plib.line.end_position(branch.start_position, branch.direction, branch.length)
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
            -- Short range search, in case the pump is really close or on top of a branch. 
            if extractor.distance_to_branch < 5 then
                -- At least 2 iterations. If the pump is on top of a branch, the circle around the pump will only have the tunnel.
                -- In such case a pipe won't be found until the second itation.
                try_connect_extractor_to_nearby_pipes(mod_context, extractor, math.max(2, extractor.distance_to_branch))
            end

            if not extractor.scored_plan then
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

            if extractor.scored_plan then
                assistant.add_extractor(mod_context.construction_plan, extractor.position, extractor.scored_plan.output_direction)
                extractor.is_connected = true
                commit_construction_plan(mod_context, extractor.scored_plan.construction_plan)

                for _, other_extractor in pairs(extractor.scored_plan.other_extractor_output_hits) do
                    other_extractor.extractor.is_connected = true
                    assistant.add_extractor(mod_context.construction_plan, other_extractor.extractor.position, other_extractor.output.direction)
                    assistant.add_output(mod_context.construction_plan, other_extractor.output.position, other_extractor.output.direction)
                end
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

    plib.line.trace(start_position, prune_direction, max_length, function(position)
        local planned = xy.get(plan, position)
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

        xy.remove(plan, position)
    end)

    return branch_has_connections
end

local function get_end_of_branch(branch)
    return plib.line.end_position(branch.start_position, branch.direction, branch.length - 1)
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

function create_extractors_lookup(mod_context)
    local extractors = assistant.find_oilwells(mod_context)
    local extractors_xy = {}
    for _, extractor in pairs(extractors) do
        xy.set(extractors_xy, extractor.position, extractor)
    end

    local extractors_lookup = {xy = extractors_xy}
    
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

function plan_plumbing_pro(mod_context)
    mod_context.construction_plan = {}
    mod_context.blocked_positions = {}    

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
    if horizontal_size > vertical_size then
        trunk_direction = defines.direction.east
    end

    local committed_branches = {}

    pump_lap("done initial prep")

    -- Trunk is just the first branch
    local trunk = find_best_branch(mod_context, trunk_area, trunk_direction, nil, committed_branches)
    commit_branch(mod_context, trunk)
    table.insert(committed_branches, trunk)
    pump_lap("got trunk")

    local split_area = plib.bounding_box.directional_split(trunk_area, trunk.slice, trunk_direction)

    plan_branches(mod_context, split_area.right, plib.directions[trunk_direction].next, trunk, committed_branches)
    plan_branches(mod_context, split_area.left, plib.directions[trunk_direction].previous, trunk, committed_branches)
    pump_lap("got branches")

    connect_extractors(mod_context, extractors_lookup, committed_branches)
    pump_lap("extractors connected")

    for _, branch in pairs(committed_branches) do
        if branch.parent_branch and not branch.is_connected_to_parent then
            mod_context.failure = "Not all pipe segments are connected. "
        end
    end

    xy.each(extractors_lookup.xy, function(extractor, position)
        if not extractor.is_connected then
            mod_context.failure = "Not all extractors are connected. "
        end
    end)
    
    optimize_pipes(mod_context, committed_branches)
end
