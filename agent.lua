-- agent.lua
-- Goal-Oriented Action Planning (GOAP) Agent for grid environments
-- Compatible with Lua 5.1+, LuaJIT, and game engines (LÖVE2D, Defold, etc.)

local Agent = {}
Agent.__index = Agent

-- Helper: Deep clone a simple key-value table
local function cloneTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = (type(v) == "table") and cloneTable(v) or v
    end
    return copy
end

-- Helper: Serialize state to string for visited set in GOAP planner
local function stateToKey(state)
    local keys = {}
    for k in pairs(state) do
        table.insert(keys, k)
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        table.insert(parts, tostring(k) .. "=" .. tostring(state[k]))
    end
    return table.concat(parts, ";")
end

-- Helper: Check if a state satisfies required conditions
local function satisfies(state, conditions)
    if not conditions then return true end
    for k, v in pairs(conditions) do
        if state[k] ~= v then return false end
    end
    return true
end

-- Helper: Manhattan distance on grid
local function manhattan(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

-- Helper: Check if a grid coordinate is walkable
local function isWalkable(grid, cols, rows, x, y)
    if not x or not y then return false end
    if x < 1 or x > cols or y < 1 or y > rows then return false end
    -- Standard convention: grid[y][x] == 1 or true means wall/blocked; 0, nil, or false means open
    if grid and grid[y] then
        local cell = grid[y][x]
        if cell == 1 or cell == true or cell == "wall" then
            return false
        end
    end
    return true
end

-- Helper: A* Pathfinding to navigate around walls and obstacles
local function findPath(grid, cols, rows, startX, startY, goalX, goalY)
    if startX == goalX and startY == goalY then
        return {}
    end

    -- If goal itself is blocked (e.g. resource is a solid rock/tree),
    -- target the nearest walkable adjacent cell instead.
    local targetIsGoal = true
    if not isWalkable(grid, cols, rows, goalX, goalY) then
        targetIsGoal = false
        local bestAdjX, bestAdjY = nil, nil
        local bestDist = math.huge
        local neighbors = { {0, 1}, {0, -1}, {1, 0}, {-1, 0} }
        for _, n in ipairs(neighbors) do
            local nx, ny = goalX + n[1], goalY + n[2]
            if isWalkable(grid, cols, rows, nx, ny) then
                local d = manhattan(startX, startY, nx, ny)
                if d < bestDist then
                    bestDist = d
                    bestAdjX, bestAdjY = nx, ny
                end
            end
        end
        if not bestAdjX then return nil end -- completely blocked
        goalX, goalY = bestAdjX, bestAdjY
        if startX == goalX and startY == goalY then
            return {}
        end
    end

    local function posKey(x, y) return x .. "," .. y end

    local openSet = { { x = startX, y = startY, f = manhattan(startX, startY, goalX, goalY) } }
    local cameFrom = {}
    local gScore = { [posKey(startX, startY)] = 0 }
    local inOpen = { [posKey(startX, startY)] = true }

    local dirs = { {0, 1}, {0, -1}, {1, 0}, {-1, 0} }
    local maxSteps = cols * rows * 2
    local steps = 0

    while #openSet > 0 and steps < maxSteps do
        steps = steps + 1
        -- Find node with lowest f score
        local bestIdx = 1
        local lowestF = openSet[1].f
        for i = 2, #openSet do
            if openSet[i].f < lowestF then
                lowestF = openSet[i].f
                bestIdx = i
            end
        end

        local current = table.remove(openSet, bestIdx)
        inOpen[posKey(current.x, current.y)] = nil

        if current.x == goalX and current.y == goalY then
            -- Reconstruct path
            local path = {}
            local currKey = posKey(goalX, goalY)
            while cameFrom[currKey] do
                local prev = cameFrom[currKey]
                table.insert(path, 1, { x = current.x, y = current.y })
                current = prev
                currKey = posKey(current.x, current.y)
            end
            return path
        end

        local currentG = gScore[posKey(current.x, current.y)] or math.huge

        for _, d in ipairs(dirs) do
            local nx, ny = current.x + d[1], current.y + d[2]
            if isWalkable(grid, cols, rows, nx, ny) then
                local tentativeG = currentG + 1
                local nKey = posKey(nx, ny)
                if tentativeG < (gScore[nKey] or math.huge) then
                    cameFrom[nKey] = { x = current.x, y = current.y }
                    gScore[nKey] = tentativeG
                    local fScore = tentativeG + manhattan(nx, ny, goalX, goalY)
                    if not inOpen[nKey] then
                        table.insert(openSet, { x = nx, y = ny, f = fScore })
                        inOpen[nKey] = true
                    end
                end
            end
        end
    end

    return nil -- No path found
end

-- Constructor
function Agent.new(x, y)
    local self = setmetatable({}, Agent)
    self.x = math.floor(x or 1)
    self.y = math.floor(y or 1)
    
    -- Agent's internal belief state
    self.worldState = {
        knowsLocation = false,
        atResource = false,
        hasResource = false
    }

    -- Action Toolbox
    self.actions = {
        {
            name = "FindResource",
            cost = 1,
            preconditions = { knowsLocation = false },
            effects = { knowsLocation = true }
        },
        {
            name = "WalkToResource",
            cost = 2,
            preconditions = { knowsLocation = true, atResource = false },
            effects = { atResource = true }
        },
        {
            name = "Harvest",
            cost = 3,
            preconditions = { atResource = true, hasResource = false },
            effects = { hasResource = true }
        }
    }
    
    self.currentPlan = {}
    self.statusText = "Idle"
    
    -- Movement & timing configuration
    self.moveSpeed = 4.0            -- Tiles per second
    self.moveTimer = 0              -- Accumulator for movement
    self.path = nil                 -- Current path waypoints
    
    -- Harvest configuration
    self.harvestTimer = 0
    self.requiredHarvestTime = 3.0  -- Takes 3 seconds to mine
    
    return self
end

-- GOAP State Space Planner with visited-set optimization and cost tracking
function Agent:plan(goalState)
    local queue = {}
    local visited = {}
    
    local initialNode = {
        state = cloneTable(self.worldState),
        plan = {},
        cost = 0
    }
    table.insert(queue, initialNode)
    visited[stateToKey(initialNode.state)] = true

    local safety = 0
    while #queue > 0 and safety < 200 do
        safety = safety + 1
        
        -- Pop cheapest / earliest node
        local bestIdx = 1
        for i = 2, #queue do
            if queue[i].cost < queue[bestIdx].cost then
                bestIdx = i
            end
        end
        local current = table.remove(queue, bestIdx)

        -- Goal check
        if satisfies(current.state, goalState) then
            return current.plan
        end

        -- Expand valid actions
        for _, action in ipairs(self.actions) do
            if satisfies(current.state, action.preconditions) then
                local nextState = cloneTable(current.state)
                for k, v in pairs(action.effects) do
                    nextState[k] = v
                end

                local key = stateToKey(nextState)
                if not visited[key] then
                    visited[key] = true
                    
                    local nextPlan = {}
                    for _, a in ipairs(current.plan) do
                        table.insert(nextPlan, a)
                    end
                    table.insert(nextPlan, action)

                    table.insert(queue, {
                        state = nextState,
                        plan = nextPlan,
                        cost = current.cost + (action.cost or 1)
                    })
                end
            end
        end
    end

    return {} -- No feasible plan found
end

-- Main update loop
function Agent:update(dt, cols, rows, grid, targetX, targetY, resourceNode)
    dt = dt or 0.016

    -- 1. Check if target resource is depleted
    if resourceNode and (resourceNode.usesLeft ~= nil and resourceNode.usesLeft <= 0) then
        -- Only reset location/destination flags; DO NOT clear hasResource if we already mined it!
        self.worldState.knowsLocation = false
        self.worldState.atResource = false
        self.path = nil
        self.harvestTimer = 0
        if not self.worldState.hasResource then
            self.currentPlan = {}
            self.statusText = "Resource Depleted - Searching..."
            return
        end
    end

    -- 2. Formulate plan if plan queue is empty and goal not yet met
    if #self.currentPlan == 0 and not self.worldState.hasResource then
        self.currentPlan = self:plan({ hasResource = true })
        if #self.currentPlan == 0 then
            self.statusText = "No valid plan available"
            return
        end
    end

    -- 3. Execute current action in plan
    if #self.currentPlan > 0 then
        local nextAction = self.currentPlan[1]
        
        -- Action: FindResource
        if nextAction.name == "FindResource" then
            self.statusText = "Plan: Located Resource Node"
            self.worldState.knowsLocation = true
            self.path = nil -- clear old path
            table.remove(self.currentPlan, 1)
            
        -- Action: WalkToResource
        elseif nextAction.name == "WalkToResource" then
            if not targetX or not targetY then
                self.statusText = "Error: Invalid target coordinates"
                return
            end

            -- Arrival check (either on tile or directly adjacent if tile is solid)
            local isDirectArrival = (self.x == targetX and self.y == targetY)
            local isAdjacentArrival = (manhattan(self.x, self.y, targetX, targetY) <= 1) and not isWalkable(grid, cols, rows, targetX, targetY)
            
            if isDirectArrival or isAdjacentArrival then
                self.worldState.atResource = true
                self.path = nil
                self.moveTimer = 0
                table.remove(self.currentPlan, 1)
                return
            end

            self.statusText = "Executing: Walking to Resource"
            
            -- Compute path if not cached or if reached last waypoint
            if not self.path or #self.path == 0 then
                self.path = findPath(grid, cols, rows, self.x, self.y, targetX, targetY)
                if not self.path or #self.path == 0 then
                    self.statusText = "Blocked: No path to resource"
                    -- Replanning trigger: reset knowsLocation so agent can find another node
                    self.worldState.knowsLocation = false
                    self.currentPlan = {}
                    return
                end
            end

            -- Step-by-step movement regulated by delta-time (moveSpeed)
            self.moveTimer = self.moveTimer + dt
            local stepInterval = 1.0 / math.max(0.001, self.moveSpeed)
            
            while self.moveTimer >= stepInterval and self.path and #self.path > 0 do
                self.moveTimer = self.moveTimer - stepInterval
                local nextCell = table.remove(self.path, 1)
                if isWalkable(grid, cols, rows, nextCell.x, nextCell.y) then
                    self.x = nextCell.x
                    self.y = nextCell.y
                else
                    -- Obstacle appeared dynamically; invalidate path to recalculate next frame
                    self.path = nil
                    break
                end
            end

            -- Re-check arrival after moving
            if (self.x == targetX and self.y == targetY) or 
               ((manhattan(self.x, self.y, targetX, targetY) <= 1) and not isWalkable(grid, cols, rows, targetX, targetY)) then
                self.worldState.atResource = true
                self.path = nil
                self.moveTimer = 0
                table.remove(self.currentPlan, 1)
            end
            
        -- Action: Harvest
        elseif nextAction.name == "Harvest" then
            self.harvestTimer = self.harvestTimer + dt
            local timeLeft = math.max(0, self.requiredHarvestTime - self.harvestTimer)
            self.statusText = string.format("Mining... (%.1fs left)", timeLeft)
            
            if self.harvestTimer >= self.requiredHarvestTime then
                self.statusText = "Executing: Harvest Complete!"
                self.worldState.hasResource = true
                
                -- Decrement resource uses safely
                if resourceNode and resourceNode.usesLeft then
                    resourceNode.usesLeft = resourceNode.usesLeft - 1
                end
                
                self.harvestTimer = 0
                table.remove(self.currentPlan, 1)
            end
        end
    else
        if self.worldState.hasResource then
            self.statusText = "Goal Complete: Resource Secured!"
        end
    end
end

return Agent
