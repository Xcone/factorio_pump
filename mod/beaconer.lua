local plib = require 'plib'
local xy = plib.xy
local assistant = require 'planner-assistant'

local function make_beacon_box(mod_context, pos)
    return plib.bounding_box.offset(mod_context.toolbox.beacon.relative_bounds, pos)        
end

local function can_place_beacon_at(mod_context, pos)
    return not assistant.is_area_blocked(mod_context.blocked_positions, make_beacon_box(mod_context, pos))
end

local function add_beacon_to_construction_plan(mod_context, state, position)
    assistant.add_beacon(mod_context.construction_plan, position)

    local beacon_box = make_beacon_box(mod_context, position)
    plib.bounding_box.each_grid_position(beacon_box, function(pos)
        xy.set(mod_context.blocked_positions, pos, true)
    end)
    
    local beacon_candidates_cleanup_area = plib.bounding_box.add_relative_bounds(beacon_box, state.beacon_bounds)
    plib.bounding_box.each_grid_position(beacon_candidates_cleanup_area, function(pos)
        xy.remove(state.candidate_positions, pos)
    end)
end

local function remove_extractor_from_candidates(mod_context, beaconing_state, extractor_pos)
    -- Only check candidate positions in the extractor's possible coverage area
    local extractor_coverage = plib.bounding_box.offset(beaconing_state.area_in_range_of_extractor, extractor_pos)
    plib.bounding_box.clamp(extractor_coverage, mod_context.area_bounds)

    plib.bounding_box.each_grid_position(extractor_coverage, function(pos)
        local candidate2 = xy.get(beaconing_state.candidate_positions, pos)
        if not candidate2 then return end
        local present = xy.get(candidate2.extractors, extractor_pos)
        if present then
            xy.remove(candidate2.extractors, extractor_pos)
            if candidate2.count and candidate2.count > 0 then
                candidate2.count = candidate2.count - 1
            end
        end
        if not xy.any(candidate2.extractors) then
            xy.remove(beaconing_state.candidate_positions, pos)
        end
    end)
end

local function find_next_beacon_position(beaconing_state)
    -- find best candidate covering most extractors using cached counts
    local best_pos = nil
    local best_count = 0
    xy.each(beaconing_state.candidate_positions, function(candidate, pos)
        if candidate.count > best_count then            
            best_pos = pos
            best_count = candidate.count
        end
    end)

    return best_pos
end

local function plan_beacon(mod_context, beaconing_state, beacon_position)
    -- retrieve candidate (contains extractors set + count)
    local candidate = xy.get(beaconing_state.candidate_positions, beacon_position)
    if not candidate then return false end

    add_beacon_to_construction_plan(mod_context, beaconing_state, beacon_position)

    -- Update per-extractor beacon counts and find extractors that have reached their coverage limits.
    local extractors_reached_max = {}
    local extractors_reached_preferred = {}
    xy.each(candidate.extractors, function(_, extractor_pos)
        local count = xy.get(beaconing_state.extractor_beacon_count, extractor_pos)
        count = count + 1
        xy.set(beaconing_state.extractor_beacon_count, extractor_pos, count)
        if count >= beaconing_state.max_beacons then
            table.insert(extractors_reached_max, extractor_pos)
        else
            if count >= beaconing_state.preferred_beacons then
                table.insert(extractors_reached_preferred, extractor_pos)
            end
        end
    end)

    -- prune candidate positions for extractors that reached max
    if #extractors_reached_max > 0 then
        for _, extractor_pos in ipairs(extractors_reached_max) do
            local extractor_coverage = plib.bounding_box.offset(beaconing_state.area_in_range_of_extractor, extractor_pos)
            plib.bounding_box.clamp(extractor_coverage, mod_context.area_bounds)
            plib.bounding_box.each_grid_position(extractor_coverage, function(pos)
                xy.remove(beaconing_state.candidate_positions, pos)
            end)
        end
    end

    -- demote extractors that reached preferred threshold
    if #extractors_reached_preferred > 0 then
        for _, extractor_pos in ipairs(extractors_reached_preferred) do
            remove_extractor_from_candidates(mod_context, beaconing_state, extractor_pos)
        end
    end

    return true
end

local function plan_beacons(mod_context)
    local extractors = assistant.find_in_construction_plan(mod_context.construction_plan, "extractor")    
    local effect_radius = mod_context.toolbox.beacon.effect_radius    

    -- Build a cache: for each possible beacon position, track which extractors it would cover
    local beacon_candidate_positions = {} 
    local extractor_bounds = mod_context.toolbox.extractor.relative_bounds
    local beacon_bounds = mod_context.toolbox.beacon.relative_bounds
    local area_in_range_of_extractor = plib.bounding_box.create(
        plib.position.add(extractor_bounds.left_top, plib.position.add(beacon_bounds.left_top, {x = -effect_radius, y = -effect_radius})),
        plib.position.add(extractor_bounds.right_bottom, plib.position.add(beacon_bounds.right_bottom, {x = effect_radius, y = effect_radius}))
    )

    xy.each(extractors, function(_, extractor_pos)
        local coverage_box = plib.bounding_box.offset(area_in_range_of_extractor, extractor_pos)
        plib.bounding_box.clamp(coverage_box, mod_context.area_bounds)

        plib.bounding_box.each_grid_position(coverage_box, function(beacon_pos)
            if can_place_beacon_at(mod_context, beacon_pos) then
                local candidate = xy.get(beacon_candidate_positions, beacon_pos)
                if not candidate then
                    candidate = { extractors = {}, count = 0 }
                    xy.set(beacon_candidate_positions, beacon_pos, candidate)
                end
                if not xy.get(candidate.extractors, extractor_pos) then
                    xy.set(candidate.extractors, extractor_pos, true)
                    candidate.count = candidate.count + 1
                end
            end
        end)
    end)

    -- Apply a post-filter: remove beacon candidate positions that cover fewer extractors
    -- than the configured `min_extractors_per_beacon` (if > 1).
    xy.each(beacon_candidate_positions, function(candidate, pos)
        local count = candidate.count or 0
        if count < mod_context.toolbox.min_extractors_per_beacon then
            xy.remove(beacon_candidate_positions, pos)
        end
    end)

    -- Initialize per-extractor beacon counts to 0 to avoid nil checks later
    local extractor_beacon_count = {}
    xy.each(extractors, function(_, extractor_pos)
        xy.set(extractor_beacon_count, extractor_pos, 0)
    end)

    -- Create beaconing_state to hold mutable planning state and config
    local beaconing_state = {
        candidate_positions = beacon_candidate_positions,
        extractor_beacon_count = extractor_beacon_count,
        max_beacons =  mod_context.toolbox.max_beacons_per_extractor,
        preferred_beacons = mod_context.toolbox.preferred_beacons_per_extractor,
        area_in_range_of_extractor = area_in_range_of_extractor,
        beacon_bounds = beacon_bounds
    }

    -- Greedily place beacons using the extracted helper; loop until no candidate remains
    while true do
        local beacon_position = find_next_beacon_position(beaconing_state)
        if not beacon_position then 
            break 
        end
        plan_beacon(mod_context, beaconing_state, beacon_position)
    end
end

return {
    plan_beacons = plan_beacons
} 