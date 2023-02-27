local math2d = require 'math2d'

local helpers = {}
helpers.directions = {
    [defines.direction.north] = {
        vector = {x = 0, y = -1},
        next = defines.direction.east,
        previous = defines.direction.west,
        opposite = defines.direction.south,
        squash_bounding_box = function(bounds)
            bounds.right_bottom.y = bounds.left_top.y
        end,
        to_edge = function(bounds, position)
            return {x = position.x, y = bounds.left_top.y}
        end
    },

    [defines.direction.east] = {
        vector = {x = 1, y = 0},
        next = defines.direction.south,
        previous = defines.direction.north,
        opposite = defines.direction.west,
        squash_bounding_box = function(bounds)
            bounds.left_top.x = bounds.right_bottom.x
        end,
        to_edge = function(bounds, position)
            return {x = bounds.right_bottom.x, y = position.y}
        end
    },

    [defines.direction.south] = {
        vector = {x = 0, y = 1},
        next = defines.direction.west,
        previous = defines.direction.east,
        opposite = defines.direction.north,
        squash_bounding_box = function(bounds)
            bounds.left_top.y = bounds.right_bottom.y
        end,
        to_edge = function(bounds, position)
            return {x = position.x, y = bounds.right_bottom.y}
        end
    },

    [defines.direction.west] = {
        vector = {x = -1, y = 0},
        next = defines.direction.north,
        previous = defines.direction.south,
        opposite = defines.direction.east,
        squash_bounding_box = function(bounds)
            bounds.right_bottom.x = bounds.left_top.x
        end,
        to_edge = function(bounds, position)
            return {x = bounds.left_top.x, y = position.y}
        end
    }
}

helpers.bounding_box = {
    -- flattens the bounding_box in the given directon. 
    --  input:  #  north:  #  south:   #  west:   #  east:
    --  ______  #  ______  #  .      . #  _     . # .     _
    -- |      | # |______| #           # | |      #      | |
    -- |      | #          #   ______  # | |      #      | |
    -- |______| # .      . #  |______| # |_|    . # .    |_|
    squash = function(bounds, direction)
        helpers.directions[direction].squash_bounding_box(bounds)
    end,

    get_cross_section_size = function(bounds, direction)
        local squashed_box = helpers.bounding_box.copy(bounds)
        local sideways = helpers.directions[direction].next
        helpers.bounding_box.squash(squashed_box, sideways)

        return helpers.bounding_box.get_size(squashed_box)
    end,

    get_size = function(bounds)
        -- Add 1, because it's zero inclusive ( x=0 to x=3 is a size of 4)        
        local x_diff = (bounds.right_bottom.x - bounds.left_top.x) + 1
        local y_diff = (bounds.right_bottom.y - bounds.left_top.y) + 1

        return x_diff * y_diff
    end,

    translate = function(bounds, direction, amount)
        local offset = helpers.directions[direction].vector
        offset = math2d.position.multiply_scalar(offset, amount)
        helpers.bounding_box.offset(bounds, offset)
    end,

    offset = function(bounds, offset)
        bounds.left_top = math2d.position.add(bounds.left_top, offset)
        bounds.right_bottom = math2d.position.add(bounds.right_bottom, offset)
    end,

    copy = function(bounds)
        local result = {
            left_top = math2d.position.ensure_xy(bounds.left_top),
            right_bottom = math2d.position.ensure_xy(bounds.right_bottom)
        }
        return result
    end,

    split = function(bounds, slice)

        if slice.left_top.x < bounds.left_top.x or slice.right_bottom.x >
            bounds.right_bottom.x or slice.left_top.y < bounds.left_top.y or
            slice.right_bottom.y > bounds.right_bottom.y then
            error("Slice should be within the bounds and be 1-dimensional")
        end

        local sub_bounds_1 = helpers.bounding_box.copy(bounds)
        local sub_bounds_2 = helpers.bounding_box.copy(bounds)

        if slice.left_top.x == slice.right_bottom.x then
            -- slice vertical
            sub_bounds_1.right_bottom.x = slice.left_top.x - 1
            sub_bounds_2.left_top.x = slice.right_bottom.x + 1
        elseif (slice.left_top.y == slice.right_bottom.y) then
            -- slice horizontal
            sub_bounds_1.right_bottom.y = slice.left_top.y - 1
            sub_bounds_2.left_top.y = slice.right_bottom.y + 1
        else
            error("Slice should be within the bounds and be 1-dimensional")
        end

        return {sub_bounds_1 = sub_bounds_1, sub_bounds_2 = sub_bounds_2}
    end,

    create = function(pos_a, pos_b)
        return {
            left_top = {
                x = math.min(pos_a.x, pos_b.x),
                y = math.min(pos_a.y, pos_b.y)
            },
            right_bottom = {
                x = math.max(pos_a.x, pos_b.x),
                y = math.max(pos_a.y, pos_b.y)
            }
        }
    end,

    position_to_edge = function(bounds, position, direction)
        return helpers.directions[direction].to_edge(bounds, position)
    end,

    contains = function(outer, inner)
        return outer.left_top.x <= inner.left_top.x and outer.left_top.y <=
                   inner.left_top.y and outer.right_bottom.x >=
                   inner.right_bottom.x and outer.right_bottom.y >=
                   inner.right_bottom.y
    end,

    each_grid_position = function(bounds, action)
        for x = bounds.left_top.x, bounds.right_bottom.x do
            for y = bounds.left_top.y, bounds.right_bottom.y do
                local position = {x = x, y = y}
                action(position)
            end
        end
    end,

    each_edge_position = function(bounds, action)
        for x = bounds.left_top.x, bounds.right_bottom.x do
            if x == bounds.left_top.x or bounds.right_bottom.x then
                for y = bounds.left_top.y, bounds.right_bottom.y do                    
                    action({x = x, y = y})
                end
            else                
                action({x = x, y = bounds.left_top.y})            
                if bounds.left_top.y ~= bounds.right_bottom.y then
                    action({x = x, y = bounds.right_bottom.y})
                end
            end
        end
    end,

    grow = function(bounds, amount)
        bounds.left_top.x = bounds.left_top.x - amount
        bounds.left_top.y = bounds.left_top.y - amount
        bounds.right_bottom.x = bounds.right_bottom.x + amount
        bounds.right_bottom.y = bounds.right_bottom.y + amount
    end
}

helpers.xy = {
    first = function(xy_table, action)
        for x, subtable in pairs(xy_table) do
            for y, subject in pairs(subtable) do
                local position = {x = x, y = y}
                action(subject, position)
                return
            end
        end
    end,

    each = function(xy_table, action)
        for x, subtable in pairs(xy_table) do
            for y, subject in pairs(subtable) do
                local position = {x = x, y = y}
                action(subject, position)
            end
        end
    end,

    where = function(xy_table, comparer)
        local result = {}
        helpers.xy.each(xy_table, function(subject, position)
            if comparer(subject, position) then
                helpers.xy.set(result, position, subject)
            end
        end)
        return result
    end,

    set = function(xy_table, position, value)
        local subtable = xy_table[position.x]
        if subtable == nil then
            subtable = {}
            xy_table[position.x] = subtable
        end
        subtable[position.y] = value
    end,

    get = function(xy_table, position)
        local subtable = xy_table[position.x]
        if subtable == nil then return nil end
        return subtable[position.y]
    end,

    any = function(xy_table) 
        return next(xy_table) ~= nil
    end,

    remove = function(xy_table, position)
        local subtable = xy_table[position.x]
        if subtable ~= nil then
            subtable[position.y] = nil
            if next(subtable) == nil then
                xy_table[position.x] = nil
            end
        end
    end,


}

return helpers

