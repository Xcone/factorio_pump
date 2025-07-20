local PriorityQueue = require("priority-queue")
local math2d = require "math2d"
local assistant = require "planner-assistant"

-- returns a string representation of a position
local function key(position)
    return math.floor(position.x) .. "," .. math.floor(position.y)
end

local function heuristic_score_taxicab(goals, node)
    local score = math.huge
    for _, goal in ipairs(goals) do
        score = math.min(score, math.abs(goal.position.x - node.position.x) + math.abs(goal.position.y - node.position.y))
    end
    return score
end

function create_node(position)
    return {
        key = key(position),
        position = position
    }
end

local pipe_neighbors = {
    {
        x = 0,
        y = -1
    }, {
        x = 1,
        y = 0
    }, {
        x = 0,
        y = 1
    }, {
        x = -1,
        y = 0
    }}

local function make_neighbors(parent, penalty_fn)
    local nodes = {}
    for i, vector in ipairs(pipe_neighbors) do
        local node = create_node(math2d.position.add(parent.position, vector))
        node.parent = parent

        -- compute tentative g_score using provided cost_fn (default 1)
        local step_cost = 0
        if penalty_fn then                    
            step_cost = penalty_fn(parent, node)
        end
        node.g_score = parent.g_score + 1 + step_cost
        
        nodes[i] = node
    end
    return nodes
end

local function positions_to_nodes(positions)
  local nodes = {}
  for _, position in pairs(positions) do
    create_node(position)
    table.insert(nodes, create_node(position))
  end

  return nodes
end

-- astar(..., cost_fn)
-- If provided, cost_fn(parent_node, neighbor_position) should return the movement cost
-- from parent_node.position to neighbor_position (numeric). If nil, cost defaults to 1.
function astar(start_positions, goal_positions, search_bounds, blocked_xy, max_length, penalty_fn, is_shortcut_fn)
    local start_nodes = positions_to_nodes(start_positions)
    local goal_nodes = positions_to_nodes(goal_positions)
    local search_queue = PriorityQueue()
    local count = 0
    if not max_length then
        max_length = 999
    end

    local all_nodes_map = {}

    -- Immediate solution if any start node is also a goal node
    for _, node in ipairs(start_nodes) do
        for _, goal in ipairs(goal_nodes) do
            if node.key == goal.key then
                return node
            end
        end
    end

    for _, node in ipairs(start_nodes) do
        if not assistant.is_position_blocked(blocked_xy, node.position) then
            node.g_score = 0
            node.f_score = 0 + heuristic_score_taxicab(goal_nodes, node)
            all_nodes_map[node.key] = node
            search_queue:put(node, node.f_score * 1000 + count)
            count = count + 1
        end
    end

    while not search_queue:empty() do
        local best = search_queue:pop()

        for _, node in ipairs(make_neighbors(best, penalty_fn)) do
            if math2d.bounding_box.contains_point(search_bounds, node.position) then
                if node.g_score <= max_length and not assistant.is_position_blocked(blocked_xy, node.position) then
                    
                    if is_shortcut_fn and is_shortcut_fn(node.position) then
                        --pump_log(node)
                        return node
                    end

                    local o = all_nodes_map[node.key]
                    if o == nil or node.g_score < o.g_score then
                        local h = heuristic_score_taxicab(goal_nodes, node)
                        if h == 0 then
                            -- for _, g in ipairs(goal_nodes) do
                            --     if g.key == node.key then
                            --         g.parent = node.parent
                            --         return g
                            --     end
                            -- end
                            return node
                        end
                        node.f_score = node.g_score + h
                        all_nodes_map[node.key] = node
                        search_queue:put(node, node.f_score * 1000 + count)
                        count = count + 1
                    end
                end
            end
        end
    end
    -- no path found
    return nil
end
