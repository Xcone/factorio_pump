function add_area_information(current_action, entities, surface, player)
    current_action.area = {}

    local area_bounds = current_action.area_bounds

    -- fill the map with default data 
    for x = area_bounds.left_top.x, area_bounds.right_bottom.x, 1 do
        current_action.area[x] = {}
        for y = area_bounds.left_top.y, area_bounds.right_bottom.y, 1 do
            current_action.area[x][y] = "undefined"
        end
    end

    -- mark where the pumps will be
    for i, entity in pairs(entities) do
        local direction = defines.direction.east
        if can_place_extractor(surface, entity.position, direction,
                               current_action.toolbox, player) then

            local relative_bounds = current_action.toolbox.extractor
                                        .relative_bounds

            for x = relative_bounds.left_top.x, relative_bounds.right_bottom.x do
                for y = relative_bounds.left_top.y, relative_bounds.right_bottom
                    .y do

                    current_action.area[entity.position.x + x][entity.position.y +
                        y] = "reserved-for-pump"
                end
            end
            current_action.area[entity.position.x][entity.position.y] =
                "oil-well"
        else
            return {"failure.obstructed-resource"}
        end
    end

    for x, reservations in pairs(current_action.area) do
        for y, reservation in pairs(reservations) do
            if reservation == "undefined" then
                if can_place_pipe(surface, {x = x, y = y}, player) then
                    current_action.area[x][y] = "can-build"
                else
                    current_action.area[x][y] = "can-not-build"
                end
            end
        end
    end
end

function pipes_present_in_area(surface, area)
    -- make search area one larger. This will make sure pipes right outside the selection are also found
    -- those might otherwise end up touching with the pipes we will add ourselves.
    local search_area = {
        left_top = {x = area.left_top.x - 1, y = area.left_top.y - 1},
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
