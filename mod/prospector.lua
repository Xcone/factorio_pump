local plib = require 'plib'
local xy = plib.xy

function add_area_information(current_action, entities, surface, player)
    current_action.area = {}
    current_action.blocked_positions = {}

    local area_bounds = current_action.area_bounds

    -- fill the map with default data 
    plib.bounding_box.each_grid_position(area_bounds, function(position)
        xy.set(current_action.area, position, "undefined")
    end)

    -- mark where the pumps will be
    for i, entity in pairs(entities) do
        local direction = defines.direction.east
        if can_place_extractor(surface, entity.position, direction, current_action.toolbox, player) then

            local extractor_bounds = plib.bounding_box.offset(current_action.toolbox.extractor.relative_bounds, entity.position)

            plib.bounding_box.each_grid_position(extractor_bounds, function(position)
                xy.set(current_action.area, position, "reserved-for-pump")

            end)
            xy.set(current_action.area, entity.position, "oil-well")
        else
            return {"failure.obstructed-resource"}
        end
    end

    xy.each(current_action.area, function(reservation, position)
        if reservation == "undefined" then
            if can_place_pipe(surface, position, player) then
                xy.set(current_action.area, position, "can-build")
            else
                xy.set(current_action.area, position, "can-not-build")

            end
        end
    end)
end

function populate_blocked_positions_from_area(current_action)
    current_action.blocked_positions = {}
    xy.each(current_action.area, function(reservation, position)
        if reservation ~= "can-build" then
            xy.set(current_action.blocked_positions, position, true)
        end
    end)
end

function pipes_present_in_area(surface, area)
    -- make search area one larger. This will make sure pipes right outside the selection are also found
    -- those might otherwise end up touching with the pipes we will add ourselves.
    local search_area = {
        left_top = {
            x = area.left_top.x - 1,
            y = area.left_top.y - 1
        },
        right_bottom = {
            x = area.right_bottom.x + 1,
            y = area.right_bottom.y + 1
        }
    }

    found_pipes = surface.find_entities_filtered {
        area = search_area,
        name = {"pipe", "pipe-to-ground"}
    }

    found_ghosts_of_pipes = surface.find_entities_filtered {
        area = search_area,
        ghost_name = {"pipe", "pipe-to-ground"}
    }

    if #found_pipes > 0 or #found_ghosts_of_pipes > 0 then
        return {"failure.other-pipes-nearby"}
    end
end

function can_place_extractor(surface, position, direction, toolbox, player)
    return surface.can_place_entity({
        name = toolbox.extractor.entity_name,
        position = position,
        direction = direction,
        force = player.force,
        build_check_type = defines.build_check_type.manual_ghost,
        forced = true
    })
end

function can_place_pipe(surface, position, player)
    return surface.can_place_entity({
        name = "pipe",
        position = position,
        direction = defines.direction.north,
        force = player.force,
        build_check_type = defines.build_check_type.manual_ghost,
        forced = true
    })
end
