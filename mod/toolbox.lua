function add_toolbox(target)
    local toolbox = {}

    toolbox.extractor = {
        entity_name = "pumpjack",
        output_offsets = {
            [defines.direction.north] = {x = 1, y = -2},
            [defines.direction.east] = {x = 2, y = -1},
            [defines.direction.south] = {x = -1, y = 2},
            [defines.direction.west] = {x = -2, y = 1}
        }
    }

    toolbox.connector = {
        entity_name = "pipe",
        underground_entity_name = "pipe-to-ground",

        -- underground_distance is excluding the entity placement itself. But rather the available space between connector entities.        
        underground_distance_min = 0,
        underground_distance_max = 9
    }

    toolbox.directions = {
        [defines.direction.north] = {
            position = {x = 0, y = -1},
            next = defines.direction.east,
            previous = defines.direction.west,
            opposite = defines.direction.south
        },

        [defines.direction.east] = {
            position = {x = 1, y = 0},
            next = defines.direction.south,
            previous = defines.direction.north,
            opposite = defines.direction.west
        },

        [defines.direction.south] = {
            position = {x = 0, y = 1},
            next = defines.direction.west,
            previous = defines.direction.east,
            opposite = defines.direction.north
        },

        [defines.direction.west] = {
            position = {x = -1, y = 0},
            next = defines.direction.north,
            previous = defines.direction.south,
            opposite = defines.direction.east
        }
    }

    target.toolbox = toolbox
end
