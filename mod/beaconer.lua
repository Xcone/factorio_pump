local plib = require 'plib'
local xy = plib.xy
local assistant = require 'planner-assistant'

-- options: { beacons_per_pump = number }
local function plan_beacons(mod_context, options)
    options = options or {}
    local beacons_per_pump = options.beacons_per_pump or 1
    local beacon_size = 3
    local planned_beacons = {}
    local pumps = assistant.find_in_construction_plan(mod_context.construction_plan, "extractor")
    local area = mod_context.area
    local area_bounds = mod_context.area_bounds
    local blocked = mod_context.blocked_positions or {}

    -- Helper: check if a 3x3 area is free for a beacon
    local function can_place_beacon_at(pos)
        for dx = 0, beacon_size - 1 do
            for dy = 0, beacon_size - 1 do
                local check_pos = {x = pos.x + dx, y = pos.y + dy}
                if xy.get(blocked, check_pos) or (area and area[check_pos.x] and area[check_pos.x][check_pos.y] == "can-not-build") then
                    
                    
                    return false
                    
                end
            end
        end
        return true
    end

    -- Build a cache: for each possible beacon position, track which pumps it would cover
    local beacon_cache = {} -- [x][y] = { [pump_key] = true, ... }
    xy.each(pumps, function(_, pump_pos)
        local pump_key = pump_pos.x .. "," .. pump_pos.y
        -- For each possible beacon top-left that would cover this pump
        local beacon_effect_area = plib.bounding_box.create(
            {x = pump_pos.x - 4, y = pump_pos.y - 4},
            {x = pump_pos.x + 4, y = pump_pos.y + 4}
        );
        plib.bounding_box.each_grid_position(beacon_effect_area, function(beacon_pos)
            if can_place_beacon_at(beacon_pos) then
                local pumpset = xy.get(beacon_cache, beacon_pos) or {}
                pumpset[pump_key] = true
                xy.set(beacon_cache, beacon_pos, pumpset)
            end
        end)
    end)

    local planner_input_as_json = helpers.table_to_json(beacon_cache)
    helpers.write_file("pump_beaconer.json", planner_input_as_json)    

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
        game.print("work")

        if not best_pos or best_count == 0 then break end
        
        game.print("Found beacon position " .. best_pos.x .. "," .. best_pos.y)

        xy.set(planned_beacons, best_pos, {name = "beacon", direction = defines.direction.north})
        -- Remove these pumps from all beacon_cache entries, and remove empty entries
        xy.each(beacon_cache, function(pumpset, pos)
            for _, pump_key in ipairs(best_pumps) do
                pumpset[pump_key] = nil
            end
            -- If the pumpset is now empty, remove the beacon_cache entry
            local is_empty = true
            for _ in pairs(pumpset) do is_empty = false; break end
            if is_empty then
                xy.remove(beacon_cache, pos)
            end
        end)
    end

    -- Commit beacons to construction plan
    xy.each(planned_beacons, function(beacon, pos)
        xy.set(mod_context.construction_plan, pos, beacon)
        -- Mark area as blocked for future planners
        for dx = 0, beacon_size - 1 do
            for dy = 0, beacon_size - 1 do
                local block_pos = {x = pos.x + dx, y = pos.y + dy}
                xy.set(blocked, block_pos, true)
            end
        end
    end)

    mod_context.blocked_positions = blocked
end

return {
    plan_beacons = plan_beacons
} 