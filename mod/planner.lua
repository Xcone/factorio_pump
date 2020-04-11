function plan(planner_input)
    local construct_entities = {["pumpjack"] = {}, ["pipe"] = {}}

    for x, reservations in pairs(planner_input.area) do
        for y, reservation in pairs(reservations) do
            if reservation == "oil-well" then

                table.insert(construct_entities["pumpjack"], {
                    position = {x = x, y = y},
                    direction = defines.direction.west
                })

                local offset = get_pump_output_offset(defines.direction.west)

                table.insert(construct_entities["pipe"], {
                    position = {x = x + offset.x, y = y + offset.y},
                    direction = defines.direction.east
                })
            end
        end
    end

    return construct_entities
end

function get_pump_output_offset(direction)
    if direction == defines.direction.north then return {x = 1, y = -2} end
    if direction == defines.direction.east then return {x = 2, y = -1} end
    if direction == defines.direction.south then return {x = -1, y = 2} end
    if direction == defines.direction.west then return {x = -2, y = 1} end
end
