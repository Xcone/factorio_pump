require 'util'
local math2d = require 'math2d'
local plib = require 'plib'
local xy = plib.xy
local PriorityQueue = require("priority-queue")
local assistant = require 'planner-assistant'
require "astar"

local branch_min_extractors_threshold = 2

local function is_pipe_or_pipe_joint(construct_entity)
    return construct_entity and (construct_entity.name == "pipe" or construct_entity.name == "pipe_joint" or construct_entity.name == "output")
end

local function get_end_of_branch(branch)
    return plib.line.end_position(branch.start_position, branch.direction, branch.length - 1)
end

local function can_build_connector_on_position(mod_context, position)
    local result = false
    if not assistant.is_position_blocked(mod_context.blocked_positions, position) then
        local planned_entity = xy.get(mod_context.construction_plan, position)
        result = planned_entity == nil or is_pipe_or_pipe_joint(planned_entity)
    end

    return result
end

local function get_output_position(extractor, output_direction, offset, mirrored)
    local adjusted_offset = {
        x = offset.x,
        y = offset.y
    }

    if mirrored then
        if output_direction == defines.direction.north or output_direction == defines.direction.south then
            adjusted_offset.x = -adjusted_offset.x
        else
            adjusted_offset.y = -adjusted_offset.y
        end
    end

    return {
        x = extractor.position.x + adjusted_offset.x,
        y = extractor.position.y + adjusted_offset.y
    }
end

local function get_neighbor_positions(position)
    return {
        {x = position.x + 1, y = position.y},
        {x = position.x - 1, y = position.y},
        {x = position.x, y = position.y + 1},
        {x = position.x, y = position.y - 1}
    }
end

local function increase_proximity_score(proximity_scores, position)
    xy.set(proximity_scores, position, (xy.get(proximity_scores, position) or 0) + 4)
    
    for _, neighbor_position in ipairs(get_neighbor_positions(position)) do
        xy.set(proximity_scores, neighbor_position, (xy.get(proximity_scores, neighbor_position) or 0) + 3)
    end
end

local function create_extractor_lookup_v2(mod_context)
    local lookup = {
        -- All extractors to process. Extractors are not removed. But the outputs_xy inside of it is.
        extractors_xy = {},

        -- Reverse lookup to find extractors by output positions.
        -- Multiple extractors can potentially output to the same position. The value of this table 
        -- is another xy table, using extractor position to find how the extractor should be placed to output here.
        -- As extractors are connected, the contents of the table is pruned.
        outputs_xy = {},

        outputs_xy_proximity_score = {},

        add_extractor = function(self, extractor)
            xy.set(self.extractors_xy, extractor.position, extractor)
            xy.set(self.extractors_xy_pending_branch_coverage, extractor.position, extractor)
            xy.set(self.extractors_xy_pending_connection, extractor.position, extractor)
            
            extractor.outputs_xy = {}            

            for output_direction, offset in pairs(mod_context.toolbox.extractor.output_offsets) do
                for _, mirrored in ipairs({false, true}) do
                    local output_position = get_output_position(extractor, output_direction, offset, mirrored)
                    local extractor_placement_for_output = {
                        direction = output_direction,
                        mirrored = mirrored,
                        branches = {}
                    }

                    if can_build_connector_on_position(mod_context, output_position) then
                        -- set of output candidate positions for the extractor.
                        xy.set(extractor.outputs_xy, output_position, extractor_placement_for_output)
                        
                        -- and the reverse .. a set of extractor candidate positions for the output.
                        local for_extractor_xy = xy.get_or_create(self.outputs_xy, output_position, {})                                                                    
                        xy.set(for_extractor_xy, extractor.position, extractor_placement_for_output) 
                        
                        -- build scores
                        increase_proximity_score(self.outputs_xy_proximity_score, output_position)
                    end
                end
            end
        end,

        extractors_xy_pending_branch_coverage = {},
        extractors_xy_pending_connection = {},
        extractors_xy_connected = {},
        connected_extractor_exists = false,

        remove_connected_extractor = function (self, extractor, direction, mirrored)
            self.connected_extractor_exists = true;

            local outputs_to_remove = {}
            -- Remove from outputs_xy
            -- First iterating possible outputs of the extractor
            -- Then using the output candidate positions, we can find each output_xy table that contains the extractor.
            -- Then remove it from the found output_xy reverse lookup            
            xy.each(extractor.outputs_xy, function(extractor_placement, output_position) 
                local extractors_xy_at_output = xy.get(self.outputs_xy, output_position);
                if extractors_xy_at_output then 
                    xy.remove(extractors_xy_at_output, extractor.position)
                end

                if not (extractor_placement.direction == direction and extractor_placement.mirrored == mirrored) then
                    xy.set(outputs_to_remove, output_position, true)
                end
            end)

            -- Remove outputs that didn't make it. Keep the output that's connected. 
            -- It's referred to later on when navigating pipes from pending extractors using a-star.
            xy.each(outputs_to_remove, function (_, output_position) 
                xy.remove(extractor.outputs_xy, output_position)
            end)            
            
            -- Does not need a branch anymore if its connected.
            xy.remove(self.extractors_xy_pending_branch_coverage, extractor.position)

            -- Does not need additional attempts for new connections anymore.
            xy.remove(self.extractors_xy_pending_connection, extractor.position)

            -- Mark it as connected            
            xy.set(self.extractors_xy_connected, extractor.position, extractor)
        end,

        remove_blocked_output = function (self, output_position)
            -- Remove the output candidate from the extractors that might output here.
            local extractors_xy_at_output = xy.get(self.outputs_xy, output_position);
            if extractors_xy_at_output then 
                xy.each(extractors_xy_at_output, function(_, extractor_position) 
                    local extractor = xy.get(self.extractors_xy, extractor_position)
                    if extractor then
                        xy.remove(extractor.outputs_xy, output_position)
                    end
                end)
            end

            xy.remove(self.outputs_xy, output_position)
        end
    }

    local extractors = assistant.find_oilwells(mod_context)    

    for _, extractor in pairs(extractors) do
        local extractor_bounds = plib.bounding_box.offset(mod_context.toolbox.extractor.relative_bounds, extractor.position)
        local can_build_extractor = not plib.bounding_box.any_grid_position(extractor_bounds, function(position)
            return xy.get(mod_context.area, position) == "can-not-build"
        end)

        if can_build_extractor then
            lookup:add_extractor(extractor)
        end
    end

    return lookup
end

local function commit_construction_plan(mod_context, extractors_lookup_v2, construction_plan)
    xy.each(construction_plan, function(planned_entity, position)
        xy.set(mod_context.construction_plan, position, table.deepcopy(planned_entity))
        if planned_entity.name == "pipe_tunnel" then
            -- We can be flexible with pipes in order to connect from every direction, and even overwrite a pipe to a joint or output.
            -- However, tunnels are final.
            -- Extractors are already on the block-list due they reserved space in the planner_input so they dont need this exception.
            xy.set(mod_context.blocked_positions, position, true)
            extractors_lookup_v2:remove_blocked_output(position)
        end
    end)
end

local function commit_extractor_plan(mod_context, extractors_lookup_v2, extractor)
    assistant.add_extractor(mod_context.construction_plan, extractor.position, extractor.scored_plan.output_direction, extractor.scored_plan.mirrored)
    commit_construction_plan(mod_context, extractors_lookup_v2, extractor.scored_plan.construction_plan)
    extractors_lookup_v2:remove_connected_extractor(extractor, extractor.scored_plan.output_direction, extractor.scored_plan.mirrored)
    
    for _, other_extractor_info in pairs(extractor.scored_plan.other_extractor_output_hits) do
        assistant.add_extractor(mod_context.construction_plan, other_extractor_info.position, other_extractor_info.placement.direction, other_extractor_info.placement.mirrored)
        assistant.add_output(mod_context.construction_plan, other_extractor_info.output_position, other_extractor_info.placement.direction)
        local other_extractor = xy.get(extractors_lookup_v2.extractors_xy, other_extractor_info.position)
        extractors_lookup_v2:remove_connected_extractor(other_extractor, other_extractor_info.placement.direction, other_extractor_info.placement.mirrored)
    end
end

local function get_extractors_in_reach_of_branch(extractors_lookup_v2, branch)
    local next_vector = plib.directions[plib.directions[branch.direction].next].vector
    local previous_vector = plib.directions[plib.directions[branch.direction].previous].vector

    local branch_reach_distance = 12
    local branch_end_position = get_end_of_branch(branch)

    local pos_a = plib.position.add(branch.start_position, math2d.position.multiply_scalar(next_vector, branch_reach_distance))
    local pos_b = plib.position.add(branch_end_position, math2d.position.multiply_scalar(previous_vector, branch_reach_distance))
    local branch_reach_bounds = plib.bounding_box.create(pos_a, pos_b)

    local extractors_in_reach = {}
    xy.each(extractors_lookup_v2.extractors_xy_pending_branch_coverage, function(extractor, position)
        if plib.bounding_box.contains_position(branch_reach_bounds, position) then
            table.insert(extractors_in_reach, extractor)
        end
    end)
    return extractors_in_reach
end

local function commit_branch(mod_context, extractors_lookup_v2, branch)
    branch.connectable_positions = {}

    xy.each(branch.construction_plan, function(value, position)
        if is_pipe_or_pipe_joint(value) then
            xy.set(branch.connectable_positions, position, true)
        end
    end)

    commit_construction_plan(mod_context, extractors_lookup_v2, branch.construction_plan)

    for _, extractor in pairs(branch.extractors_in_reach) do
        xy.remove(extractors_lookup_v2.extractors_xy_pending_branch_coverage, extractor.position)        
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

function create_branch_candidate(mod_context, extractors_lookup_v2, slice, branch_length, branch_direction, parent_branch, extra_penalty)
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

    local sample_find_extractors_in_reach = pump_sample_start()
    local extractors_in_reach = get_extractors_in_reach_of_branch(extractors_lookup_v2, branch_candidate)
    pump_sample_finish("find_extractors_in_reach", sample_find_extractors_in_reach)

    local in_reach = #extractors_in_reach

    branch_candidate.number_of_extractors_in_reach = in_reach
    branch_candidate.extractors_in_reach = extractors_in_reach
    if in_reach < branch_min_extractors_threshold then
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

    return branch_candidate
end

function find_best_branch(mod_context, extractors_lookup_v2, search_area, branch_direction, parent_branch, committed_branches)
    local sample_start = pump_sample_start()

    local extractors_in_search_area = 0
    xy.where(extractors_lookup_v2.extractors_xy_pending_branch_coverage, function(_, extractor_position)
        if plib.bounding_box.contains_position(search_area, extractor_position) then
            extractors_in_search_area = extractors_in_search_area + 1
        end
    end)    

    if extractors_in_search_area < branch_min_extractors_threshold then
        return nil
    end

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

        local sample_create_branch_candidate = pump_sample_start()
        local branch_candidate = create_branch_candidate(mod_context, extractors_lookup_v2, slice, branch_length, branch_direction, parent_branch, score_offset)
        pump_sample_finish("create_branch_candidate", sample_create_branch_candidate)

        if branch_candidate ~= nil and (best_branch == nil or branch_candidate.score > best_branch.score) then
            best_branch = branch_candidate
        end

        iterations = iterations + 1
        slice_index = slice_offsets_by_distance_from_ideal:pop()
    end

    pump_sample_finish("find_best_branch", sample_start)

    return best_branch
end

function plan_branches(mod_context, extractors_lookup_v2, branch_area, branch_direction, parent_branch, commited_branches)
    local pending_branch_areas = {}
    table.insert(pending_branch_areas, {
        branch_area = branch_area,
        branch_direction = branch_direction
    })

    local branch_length = plib.bounding_box.get_cross_section_size(branch_area, branch_direction)
    if branch_length < 8 then
        return
    end

    local pending_branch_area_count = #pending_branch_areas

    while pending_branch_area_count > 0 do
        local pending_branch_area = table.remove(pending_branch_areas)
        pending_branch_area_count = pending_branch_area_count - 1
        local branch_area = pending_branch_area.branch_area
        local branch_direction = pending_branch_area.branch_direction

        local branch = find_best_branch(mod_context, extractors_lookup_v2, pending_branch_area.branch_area, pending_branch_area.branch_direction, parent_branch, commited_branches)

        if not branch or not branch.is_connected_to_parent then
            break
        end

        commit_branch(mod_context, extractors_lookup_v2, branch)
        table.insert(commited_branches, branch)

        split_result = plib.bounding_box.directional_split(branch_area, branch.slice, branch.direction)
        local pending_area = split_result.right
        -- Make additional branches if the area big enough. Ideally pumps are but 1 tunnel-distance away
        if plib.bounding_box.get_cross_section_size(pending_area, plib.directions[branch_direction].next) > mod_context.toolbox.connector.underground_distance_max then
            pending_branch_area_count = pending_branch_area_count + 1
            table.insert(pending_branch_areas, {
                branch_area = pending_area,
                branch_direction = branch_direction
            })
        end
    end
end

local function resolve_extractor_placement(extractor, output_position)
    local placement = nil

    xy.each(extractor.outputs_xy, function(extractor_placement, position)
        if position.x == output_position.x and position.y == output_position.y then
            placement = extractor_placement
            return true
        end
    end)

    if not placement then
        error("Position is not a candidate output position")
    end

    return placement
end

local function convert_astar_result_to_pipe(reached_pipe)
    local construction_plan = {}

    local current_pipe = reached_pipe
    local next_pipe = reached_pipe.parent
    local x_dir = 0
    local y_dir = 0

    while next_pipe do
        local next_x_dir = current_pipe.position.x - next_pipe.position.x
        local next_y_dir = current_pipe.position.y - next_pipe.position.y

        if x_dir ~= next_x_dir or y_dir ~= next_y_dir then
            -- Mark every bend as joint, to help later with burying pipes
            assistant.add_connector_joint(construction_plan, current_pipe.position)        
        else
            assistant.add_connector(construction_plan, current_pipe.position)        
        end

        x_dir = next_x_dir
        y_dir = next_y_dir
        current_pipe = next_pipe
        next_pipe = current_pipe.parent
    end

    return construction_plan, current_pipe.position
end

local function convert_astar_result_to_extractor_plan(reached_pipe, extractor)
    local construction_plan, start_position = convert_astar_result_to_pipe(reached_pipe)
    local placement = resolve_extractor_placement(extractor, start_position)
    assistant.add_output(construction_plan, start_position, placement.direction)

    return {
        construction_plan = construction_plan,
        other_extractor_output_hits = {},
        output_direction = placement.direction,
        mirrored = placement.mirrored
    }
end

local function try_connect_extractor_to_nearby_pipes(mod_context, extractors_lookup_v2, extractor, max_distance_from_extractor)
    local sample_start = pump_sample_start();

    
    local output_positions_by_proximity_score = PriorityQueue()
    xy.each(extractor.outputs_xy, function(_, output_position)        
        output_positions_by_proximity_score:put(output_position, -xy.get(extractors_lookup_v2.outputs_xy_proximity_score, output_position))
    end)

    local output_positions = {}
    while #output_positions < 4 and output_positions_by_proximity_score:peek() do
        local p = output_positions_by_proximity_score:pop()
        table.insert(output_positions, p)
    end

    -- First search area is the edge around the extractor
    local search_bounds = plib.bounding_box.offset(mod_context.toolbox.extractor.relative_bounds, extractor.position)
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

        local reached_pipe = astar(output_positions, nearby_pipe_positions, search_bounds, mod_context.blocked_positions, max_distance_from_extractor * 2)
        if reached_pipe then
            extractor.scored_plan = convert_astar_result_to_extractor_plan(reached_pipe, extractor)
        end
    end

    pump_sample_finish("try_connect_extractor_to_nearby_pipes", sample_start);
end

local function try_connect_extractor_to_nearby_extractors(mod_context, extractors_lookup_v2, extractor)
    local sample_start = pump_sample_start()
    local start_positions = {}    
    xy.each(extractor.outputs_xy, function(_, output_position)
        table.insert(start_positions, output_position)
    end)

    local goal_positions = {}
    xy.each(extractors_lookup_v2.extractors_xy_connected, function(extractor, _)
        xy.first(extractor.outputs_xy, function(_, output_position)
            table.insert(goal_positions, output_position)                    
        end)        
    end)    
    
    if next(goal_positions) then
        local reached_pipe = astar(start_positions, goal_positions, mod_context.area_bounds, mod_context.blocked_positions)
        if reached_pipe then
            extractor.scored_plan = convert_astar_result_to_extractor_plan(reached_pipe, extractor)
        end
    else
        error("Nothing to connect to")
    end

    pump_sample_finish("try_connect_extractor_to_nearby_extractors", sample_start)
end

local function try_connect_extractor_to_branch_using_tunnels(mod_context, extractors_lookup_v2, extractor)
    -- Long range, straight_search. This includes tunneling underneath obstacles, like other pumps or water.
    xy.each(extractor.outputs_xy, function (extractor_placement_for_output, output_position) 
        for direction, branch_intersection in pairs(extractor_placement_for_output.branches) do
            local other_extractor_output_hits = {}
            local other_extractor_output_hits_seen = {}
            local end_position = plib.line.end_position(output_position, direction, branch_intersection.tile_count - 1)

            local construction_plan = plan_pipe_line(mod_context, output_position, direction, branch_intersection.tile_count)
            branch_intersection.can_build = is_pipe_or_pipe_joint(xy.get(construction_plan, output_position)) and is_pipe_or_pipe_joint(xy.get(construction_plan, end_position))

            xy.each(construction_plan, function(planned, position)
                if planned.name == "pipe" then
                    local extractor_candidate_placements_xy = xy.get(extractors_lookup_v2.outputs_xy, position)

                    if extractor_candidate_placements_xy then                         
                        xy.each(extractor_candidate_placements_xy, function(extractor_placement, extractor_position)
                            if not plib.position.are_equal(extractor_position, extractor.position) then
                                local is_pending_connection = xy.get(extractors_lookup_v2.extractors_xy_pending_connection, extractor_position)
                                if is_pending_connection then
                                    local seen_hit = xy.get(other_extractor_output_hits_seen, extractor_position)
                                    local proximity_score = xy.get(extractors_lookup_v2.outputs_xy_proximity_score, position) or 0
                                    if not seen_hit then
                                        local hit = {
                                            position = extractor_position,
                                            placement = extractor_placement,
                                            output_position = position,
                                            proximity_score = proximity_score
                                        }
                                        table.insert(other_extractor_output_hits, hit)
                                        xy.set(other_extractor_output_hits_seen, extractor_position, hit)
                                    elseif proximity_score > (seen_hit.proximity_score or 0) then
                                        seen_hit.placement = extractor_placement
                                        seen_hit.output_position = position
                                        seen_hit.proximity_score = proximity_score
                                    end
                                end
                            end
                        end)                            
                    end
                end
            end)

            if branch_intersection.can_build then
                assistant.add_output(construction_plan, output_position, extractor_placement_for_output.direction)
                assistant.add_connector_joint(construction_plan, end_position)

                local score_extra_outputs = #other_extractor_output_hits * 3
                local score_distance = 15 - branch_intersection.tile_count

                local scored_plan = {
                    score = score_distance + score_extra_outputs,
                    output_direction = extractor_placement_for_output.direction,
                    mirrored = extractor_placement_for_output.mirrored,
                    construction_plan = construction_plan,
                    other_extractor_output_hits = other_extractor_output_hits
                }

                if not extractor.scored_plan or extractor.scored_plan.score < scored_plan.score then
                    extractor.scored_plan = scored_plan
                end
            end
        end
    end)
end

function connect_extractors(mod_context, extractors_lookup_v2, committed_branches)
    local search_range = 20

    -- Find the quick wins. The outputs that are already directly on an existing pipe
    local sample_quick_wins = pump_sample_start()
    local pending_extractors = {}
    xy.each(extractors_lookup_v2.extractors_xy_pending_connection, function(extractor, position)
        table.insert(pending_extractors, extractor)
    end)

    for _, extractor in ipairs(pending_extractors) do
        local committed = false
        xy.each(extractor.outputs_xy, function(extractor_placement_for_output, output_position)
            local planned_construction = xy.get(mod_context.construction_plan, output_position)
            local is_quick_win = is_pipe_or_pipe_joint(planned_construction)

            if is_quick_win then
                local construction_plan = {}
                assistant.add_extractor(construction_plan, extractor.position, extractor_placement_for_output.direction, extractor_placement_for_output.mirrored)
                assistant.add_output(construction_plan, output_position, extractor_placement_for_output.direction)

                local scored_plan = {
                    output_direction = extractor_placement_for_output.direction,
                    mirrored = extractor_placement_for_output.mirrored,
                    construction_plan = construction_plan,
                    other_extractor_output_hits = {}
                }
                extractor.scored_plan = scored_plan
                commit_extractor_plan(mod_context, extractors_lookup_v2, extractor)
                
                return true --break
            end
        end)
    end
    pump_sample_finish("connect_extractors.quickwins", sample_quick_wins)

    -- Find the nearest branches in each direction for each extractor and the individual outputs

    xy.each(extractors_lookup_v2.extractors_xy, function(extractor, position)
        local sample_find_nearest_branches = pump_sample_start()
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

                if (intersects) then
                    xy.each(extractor.outputs_xy, function(extractor_placement_for_output, output_position)
                        local output_search_end = plib.line.end_position(output_position, direction, search_range)
                        intersects, intersection_point = plib.line.intersects(output_position, output_search_end, branch.start_position, branch_end)

                        if intersects then
                            local new_tile_count = plib.line.count_tiles(output_position, intersection_point)
                            if extractor_placement_for_output.branches[direction] ~= nil then
                                if new_tile_count < extractor_placement_for_output.branches[direction].tile_count then
                                    extractor_placement_for_output.branches[direction] = {
                                        branch = branch,
                                        intersection_point = intersection_point,
                                        tile_count = new_tile_count
                                    }
                                end
                            else
                                extractor_placement_for_output.branches[direction] = {
                                    branch = branch,
                                    intersection_point = intersection_point,
                                    tile_count = new_tile_count
                                }
                            end
                        end
                    end)
                end
            end
        end
        pump_sample_finish("connect_extractors.find_nearest_branches", sample_find_nearest_branches)
    end)

    -- Prioritize extractors further away from a branch, to increase the odds of a pipe-line connecting to another output along the way
    local sample_connect_to_branches = pump_sample_start()
    local extractors_by_branch_distance = PriorityQueue()
    xy.each(extractors_lookup_v2.extractors_xy, function(extractor, position)
        extractors_by_branch_distance:put(extractor, 0 - extractor.distance_to_branch)
    end)

    local extractor = extractors_by_branch_distance:pop()
    while (extractor) do
        if xy.get(extractors_lookup_v2.extractors_xy_pending_connection, extractor.position) then
            -- Short range search, in case the pump is really close to of a branch or another pipe that was already committed
            try_connect_extractor_to_nearby_pipes(mod_context, extractors_lookup_v2, extractor, 4)

            if not extractor.scored_plan then
                try_connect_extractor_to_branch_using_tunnels(mod_context, extractors_lookup_v2, extractor)
            end

            if extractor.scored_plan then
                commit_extractor_plan(mod_context, extractors_lookup_v2, extractor)
            else
                pump_log("Simple plan failed. Do astar instead")
            end            
        end

        extractor = extractors_by_branch_distance:pop()
    end
    pump_sample_finish("connect_extractors.sample_connect_to_branches", sample_connect_to_branches)
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

local function prune_branch_ends(mod_context, start_position, prune_direction, max_length)
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
        if not is_tunneling and not planned_is_tunnel then            
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

    if is_tunneling then
        error("Trace ended while tunneling. Expected end of tunnel before the end of trace.")
    end

    return branch_has_connections
end

local function prune_branches(mod_context, branches)
    local trunk = nil

    for _, branch in pairs(branches) do
        if branch.parent_branch then
            local branch_has_connections = prune_branch_ends(mod_context, get_end_of_branch(branch), plib.directions[branch.direction].opposite, branch.length)
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
        prune_branch_ends(mod_context, trunk.start_position, trunk.direction, trunk.length)
        prune_branch_ends(mod_context, get_end_of_branch(trunk), plib.directions[trunk.direction].opposite, trunk.length)
    end
end

local function bury_pipes(mod_context)
    assistant.create_tunnels_between_joints(mod_context.construction_plan, mod_context.toolbox)

    -- Pipes are now buried, so we can mark all positions as blocked
    xy.each(mod_context.construction_plan, function(_, position)
        xy.set(mod_context.blocked_positions, position, true)
    end)
end

function plan_plumbing_pro(mod_context)
    mod_context.construction_plan = {}

    -- Settings, maybe? For now just debug purpose.
    local use_trunk = true
    local use_branches = true

    local extractors_lookup_v2 = create_extractor_lookup_v2(mod_context)    

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
        local trunk = find_best_branch(mod_context, extractors_lookup_v2, trunk_area, trunk_direction, nil, committed_branches)
        if trunk then
            commit_branch(mod_context, extractors_lookup_v2, trunk)
            table.insert(committed_branches, trunk)
            pump_lap("got trunk")
            if use_branches then
                local split_area = plib.bounding_box.directional_split(trunk_area, trunk.slice, trunk_direction)

                plan_branches(mod_context, extractors_lookup_v2, split_area.right, plib.directions[trunk_direction].next, trunk, committed_branches)
                plan_branches(mod_context, extractors_lookup_v2, split_area.left, plib.directions[trunk_direction].previous, trunk, committed_branches)
                pump_lap("got branches")
            end

            connect_extractors(mod_context, extractors_lookup_v2, committed_branches)
            pump_lap("extractors connected to branches")
        end

        prune_branches(mod_context, committed_branches)
    end

    if not extractors_lookup_v2.connected_extractor_exists then
        pump_log("picking default extractor")
        -- Connect to first available output and hope the rest can A* back to it.
        xy.first(extractors_lookup_v2.outputs_xy, function(extractor_outputs, ouput_position)
            xy.first(extractor_outputs, function(extractor_placement, extractor_position) 
                local construction_plan = {}
                local extractor = xy.get(extractors_lookup_v2.extractors_xy, extractor_position)

                assistant.add_extractor(construction_plan, extractor_position, extractor_placement.direction, extractor_placement.mirrored)
                assistant.add_output(construction_plan, ouput_position, extractor_placement.direction)

                extractor.scored_plan = {
                    output_direction = extractor_placement.direction,
                    mirrored = extractor_placement.mirrored,
                    construction_plan = construction_plan,
                    other_extractor_output_hits = {}
                }

                commit_extractor_plan(mod_context, extractors_lookup_v2, extractor)
            end)            
        end)
    end

    local pending_extractors = PriorityQueue()

    xy.each(extractors_lookup_v2.extractors_xy_pending_connection, function(extractor, position)
        local closest_connected_extractor_distance = nil
        local closest_connected_extractor = nil
        xy.each(extractors_lookup_v2.extractors_xy_connected, function(other_extractor, other_position)            
            local other_connector_distance = plib.position.distance_squared(extractor.position, other_extractor.position)
            if not closest_connected_extractor or other_connector_distance < closest_connected_extractor_distance then
                closest_connected_extractor_distance = other_connector_distance
                closest_connected_extractor = other_extractor
            end
        end)

        pending_extractors:put(extractor, closest_connected_extractor_distance)
    end)    

    local pending_extractor = pending_extractors:pop()
    while pending_extractor do
        -- Look for other pipes further out then the first attempt
        try_connect_extractor_to_nearby_pipes(mod_context, extractors_lookup_v2, pending_extractor, 10)
        if not pending_extractor.scored_plan then            
            try_connect_extractor_to_nearby_extractors(mod_context, extractors_lookup_v2, pending_extractor)
        end
        if pending_extractor.scored_plan then
            commit_extractor_plan(mod_context, extractors_lookup_v2, pending_extractor)
        else
            assistant.add_warning(mod_context, pending_extractor.position, "warning.resource-not-planned")
        end

        pending_extractor = pending_extractors:pop()
    end
    pump_lap("remaining extractor connections made with fallback")

    bury_pipes(mod_context)
    pump_lap("buried pipes")

end
