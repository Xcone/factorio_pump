-- control.lua
script.on_event({defines.events.on_player_selected_area}, function(event)
    if event.item == 'pump-selection-tool' then
        local player = game.get_player(event.player_index)

        if #event.entities == 0 then
            player.print(
                "P.U.M.P. cannot place pumpjacks, becayse there are no oil wells found in selected area.")
            return
        end

        if pipes_present_in_area(event.surface, event.area) then
            player.print(
                "P.U.M.P. cannot safely place pumpjacks and pipes, because there are other pipes present within the selected area.")
            return
        end

        local count = 0;
        for i, entity in ipairs(event.entities) do

            local direction = defines.direction.east
            if can_place_pumpjack(event.surface, entity.position, direction) then
                place_pumpjack(event.surface, entity.position, direction)
                count = count + 1
            end
        end

        player.print(count);
    end
end)

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

    return #found_pipes > 0 or #found_ghosts_of_pipes > 0
end

function can_place_pumpjack(surface, position, direction)
    return surface.can_place_entity({
        name = "pumpjack",
        position = position,
        direction = direction,
        force = "player",
        build_check_type = defines.build_check_type.ghost_place
    })
end

function place_pumpjack(surface, position, direction)
    surface.create_entity {
        name = "entity-ghost",
        inner_name = "pumpjack",
        position = position,
        direction = direction,
        force = "player"
    }

    local offset = get_pump_output_offset(direction);

    local pipePosition = {x = position.x + offset.x, y = position.y + offset.y}

    surface.create_entity {
        name = "entity-ghost",
        inner_name = "pipe",
        position = pipePosition,
        force = "player"
    }
end

function get_pump_output_offset(direction)
    if direction == defines.direction.north then return {x = 1, y = -2} end
    if direction == defines.direction.east then return {x = 2, y = -1} end
    if direction == defines.direction.south then return {x = -1, y = 2} end
    if direction == defines.direction.west then return {x = -2, y = 1} end
end

