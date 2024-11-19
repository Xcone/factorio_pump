local math2d = require 'math2d'

-- custom log method used in conjunction with the C# LayoutTester-tool
function pump_log(object_to_log)
    if pumpdebug then pumpdebug.log(object_to_log) end
end

function pump_lap(message)
    if pumpdebug then pumpdebug.lap(message) end
end

function pump_sample_start()
   if pumpdebug then return pumpdebug.sample_start() end    
end

function pump_sample_finish(key, start)
   if pumpdebug then pumpdebug.sample_finish(key, start) end    
end

local plib = {}
plib.directions = {
    [defines.direction.north] = {
        vector = { x = 0, y = -1 },
        next = defines.direction.east,
        previous = defines.direction.west,
        opposite = defines.direction.south,
        squash_bounding_box = function(bounds)
            bounds.right_bottom.y = bounds.left_top.y
        end,
        to_edge = function(bounds, position)
            return { x = position.x, y = bounds.left_top.y }
        end
    },

    [defines.direction.east] = {
        vector = { x = 1, y = 0 },
        next = defines.direction.south,
        previous = defines.direction.north,
        opposite = defines.direction.west,
        squash_bounding_box = function(bounds)
            bounds.left_top.x = bounds.right_bottom.x
        end,
        to_edge = function(bounds, position)
            return { x = bounds.right_bottom.x, y = position.y }
        end
    },

    [defines.direction.south] = {
        vector = { x = 0, y = 1 },
        next = defines.direction.west,
        previous = defines.direction.east,
        opposite = defines.direction.north,
        squash_bounding_box = function(bounds)
            bounds.left_top.y = bounds.right_bottom.y
        end,
        to_edge = function(bounds, position)
            return { x = position.x, y = bounds.right_bottom.y }
        end
    },

    [defines.direction.west] = {
        vector = { x = -1, y = 0 },
        next = defines.direction.north,
        previous = defines.direction.south,
        opposite = defines.direction.east,
        squash_bounding_box = function(bounds)
            bounds.right_bottom.x = bounds.left_top.x
        end,
        to_edge = function(bounds, position)
            return { x = bounds.left_top.x, y = position.y }
        end,
    }
}

plib.line = {
    -- Calls 'action' for each position along a line, either until action returns true, or the count is reached
    trace = function(start_position, direction, count, action)
        local position = start_position
        local vector = plib.directions[direction].vector

        for i = 1, count do            
            if action(position) then
                break
            end
            position = math2d.position.add(position, vector)
        end
    end,

    end_position = function(start_position, direction, distance)
        local offset = math2d.position.multiply_scalar(plib.directions[direction].vector, distance)
        return math2d.position.add(start_position, offset)
    end,

    -- Start-tile inclusive. So it returns 1 if the start and end are the same
    count_tiles = function(start_position, end_position) 
        if start_position.x == end_position.x then
            return math.abs(end_position.y - start_position.y) + 1
        end

        return math.abs(end_position.x - start_position.x) + 1
    end,

    -- Math taken from: https://2dengine.com/doc/intersections.html#Segment_vs_segment
    intersects = function(line1_start, line1_end, line2_start, line2_end)
        local x1 = line1_start.x
        local x2 = line1_end.x
        local x3 = line2_start.x
        local x4 = line2_end.x

        local y1 = line1_start.y
        local y2 = line1_end.y
        local y3 = line2_start.y
        local y4 = line2_end.y

        local dx1, dy1 = x2 - x1, y2 - y1
        local dx2, dy2 = x4 - x3, y4 - y3
        local dx3, dy3 = x1 - x3, y1 - y3
        local d = dx1 * dy2 - dy1 * dx2
        if d == 0 then
            return false
        end
        local t1 = (dx2 * dy3 - dy2 * dx3) / d
        if t1 < 0 or t1 > 1 then
            return false
        end
        local t2 = (dx1 * dy3 - dy1 * dx3) / d
        if t2 < 0 or t2 > 1 then
            return false
        end
        -- point of intersection
        return true, { x = x1 + t1 * dx1, y = y1 + t1 * dy1 }
    end
}

plib.bounding_box = {
    -- flattens the bounding_box in the given directon.
    --  input:  #  north:  #  south:   #  west:   #  east:
    --  ______  #  ______  #  .      . #  _     . # .     _
    -- |      | # |______| #           # | |      #      | |
    -- |      | #          #   ______  # | |      #      | |
    -- |______| # .      . #  |______| # |_|    . # .    |_|
    squash = function(bounds, direction)
        plib.directions[direction].squash_bounding_box(bounds)
    end,

    get_cross_section_size = function(bounds, direction)
        local squashed_box = plib.bounding_box.copy(bounds)
        local sideways = plib.directions[direction].next
        plib.bounding_box.squash(squashed_box, sideways)

        return plib.bounding_box.get_size(squashed_box)
    end,

    get_size = function(bounds)
        -- Add 1, because it's zero inclusive ( x=0 to x=3 is a size of 4)
        local x_diff = (bounds.right_bottom.x - bounds.left_top.x) + 1
        local y_diff = (bounds.right_bottom.y - bounds.left_top.y) + 1

        return x_diff * y_diff
    end,

    translate = function(bounds, direction, amount)
        local offset = plib.directions[direction].vector
        offset = math2d.position.multiply_scalar(offset, amount)
        plib.bounding_box.offset(bounds, offset)
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

        local sub_bounds_1 = plib.bounding_box.copy(bounds)
        local sub_bounds_2 = plib.bounding_box.copy(bounds)

        if slice.left_top.x == slice.right_bottom.x then
            -- slice vertical

            -- west
            sub_bounds_1.right_bottom.x = slice.left_top.x - 1

            -- east
            sub_bounds_2.left_top.x = slice.right_bottom.x + 1
        elseif (slice.left_top.y == slice.right_bottom.y) then
            -- slice horizontal

            -- north
            sub_bounds_1.right_bottom.y = slice.left_top.y - 1

            -- south
            sub_bounds_2.left_top.y = slice.right_bottom.y + 1
        else
            error("Slice should be within the bounds and be 1-dimensional")
        end

        return { sub_bounds_1 = sub_bounds_1, sub_bounds_2 = sub_bounds_2 }
    end,

    directional_split = function(bounds, slice, direction)
        local split_result = plib.bounding_box.split(bounds, slice)

        -- west or north
        local left = split_result.sub_bounds_1
        -- east or south
        local right = split_result.sub_bounds_2

        if direction == defines.direction.south or direction == defines.direction.west then
            left = split_result.sub_bounds_2
            right = split_result.sub_bounds_1
        end

        return { left = left, right = right }
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
        return plib.directions[direction].to_edge(bounds, position)
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
                local position = { x = x, y = y }
                action(position)
            end
        end
    end,

    each_edge_position = function(bounds, action)
        for x = bounds.left_top.x, bounds.right_bottom.x do
            if x == bounds.left_top.x or bounds.right_bottom.x then
                for y = bounds.left_top.y, bounds.right_bottom.y do
                    action({ x = x, y = y })
                end
            else
                action({ x = x, y = bounds.left_top.y })
                if bounds.left_top.y ~= bounds.right_bottom.y then
                    action({ x = x, y = bounds.right_bottom.y })
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

plib.xy = {
    first = function(xy_table, action)
        for x, subtable in pairs(xy_table) do
            for y, subject in pairs(subtable) do
                local position = { x = x, y = y }
                action(subject, position)
                return
            end
        end
    end,

    each = function(xy_table, action)
        for x, subtable in pairs(xy_table) do
            for y, subject in pairs(subtable) do
                local position = { x = x, y = y }
                action(subject, position)
            end
        end
    end,

    where = function(xy_table, comparer)
        local result = {}
        plib.xy.each(xy_table, function(subject, position)
            if comparer(subject, position) then
                plib.xy.set(result, position, subject)
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

    nearest = function(xy_table, search_position)
        local nearest_distance = 99999
        local nearest_position = nil
        local nearest_value = nil

        plib.xy.each(xy_table, function(value, entry_position)
            local d = math2d.position.distance(search_position, entry_position)
            if d < nearest_distance then
                nearest_distance = d
                nearest_position = entry_position
                nearest_value = value
            end
        end)

        return { position = nearest_position, distance = nearest_distance, value = nearest_value }
    end
}

plib.position = {
    add = function(posA, posB) 
        return {x = posA.x + posB.x, y = posA.y + posB.y}
    end,

    subtract = function(posA, posB) 
        return {x = posA.x - posB.x, y = posA.y - posB.y}
    end,

    to_key = function(position)        
        return math.floor(position.x) .. "," .. math.floor(position.y)
    end
}

return plib
