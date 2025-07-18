local plib = require 'plib'
local xy = plib.xy
local assistant = require 'planner-assistant'

-- options: { beacons_per_pump = number }
local function plan_beacons(mod_context)
    local pumps = assistant.find_in_construction_plan(mod_context.construction_plan, "extractor")
    local blocked = mod_context.blocked_positions

    local effect_radius = mod_context.toolbox.beacon.effect_radius

    local function make_beacon_box(pos)
        return plib.bounding_box.offset(mod_context.toolbox.beacon.relative_bounds, pos)        
    end

    local function can_place_beacon_at(pos)
        return not assistant.is_area_blocked(mod_context.blocked_positions, make_beacon_box(pos))
    end

    -- Build a cache: for each possible beacon position, track which pumps it would cover
    local beacon_cache = {} 
    local extractor_bounds = mod_context.toolbox.extractor.relative_bounds
    local beacon_bounds = mod_context.toolbox.beacon.relative_bounds
    local relative_coverage_area = plib.bounding_box.create(
        plib.position.add(extractor_bounds.left_top, plib.position.add(beacon_bounds.left_top, {x = -effect_radius, y = -effect_radius})),
        plib.position.add(extractor_bounds.right_bottom, plib.position.add(beacon_bounds.right_bottom, {x = effect_radius, y = effect_radius}))
    )

    xy.each(pumps, function(_, pump_pos)
        local pump_key = pump_pos.x .. "," .. pump_pos.y
        local coverage_box = plib.bounding_box.offset(relative_coverage_area, pump_pos)
        plib.bounding_box.clamp(coverage_box, mod_context.area_bounds)

        plib.bounding_box.each_grid_position(coverage_box, function(beacon_pos)
            if can_place_beacon_at(beacon_pos) then
                local pumpset = xy.get(beacon_cache, beacon_pos) or {}
                pumpset[pump_key] = true
                xy.set(beacon_cache, beacon_pos, pumpset)                
            end
        end)
    end)

    -- Greedily pick beacon positions covering the most pumps
    while true do
        local best_pos, best_count, best_pumps = nil, 0, nil
        xy.each(beacon_cache, function(pumpset, pos)
            local count, pumps_here = 0, {}
            for pump_key, _ in pairs(pumpset) do
                count = count + 1
                table.insert(pumps_here, pump_key)
            end
            if count > best_count then
                best_count = count
                best_pos = pos
                best_pumps = pumps_here
            end
        end)
        if not best_pos or best_count == 0 then break end
        assistant.add_beacon(mod_context.construction_plan, best_pos)
        -- Remove all positions in the beacon's bounding box from beacon_cache and update blocked_positions
        local beacon_box = make_beacon_box(best_pos)
        plib.bounding_box.each_grid_position(beacon_box, function(pos)
            xy.remove(beacon_cache, pos)
            xy.set(blocked, pos, true)
        end)
        -- Remove these pumps from all remaining beacon_cache entries
        xy.each(beacon_cache, function(pumpset, pos)
            for _, pump_key in ipairs(best_pumps) do
                pumpset[pump_key] = nil
            end
            local is_empty = true
            for _ in pairs(pumpset) do is_empty = false; break end
            if is_empty then
                xy.remove(beacon_cache, pos)
            end
        end)
    end    
end

return {
    plan_beacons = plan_beacons
} 