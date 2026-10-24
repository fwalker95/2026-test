-- agent.lua
-- Goal-Oriented Action Planning (GOAP) Agent for grid environments
-- Compatible with Lua 5.1+, LuaJIT, and game engines (LÖVE2D, Defold, etc.)

local Agent = {}
Agent.__index = Agent

local function cloneTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = (type(v) == "table") and cloneTable(v) or v
    end
    return copy
end

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

local function satisfies(state, conditions)
    if not conditions then return true end
    for k, v in pairs(conditions) do
        if state[k] ~= v then return false end
    end
    return true
end

local function manhattan(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

local function isWalkable(grid, cols, rows, x, y)
    if not x or not y then return false end
    if x < 1 or x > cols or y < 1 or y > rows then return false end
    if grid and grid[x] then
        local cell = grid[x][y]
        if cell == 1 or cell == true or cell == "wall" then
            return false
        end
    end
    return true
end

local function nearestNodeFromList(x, y, nodes)
    if not nodes or #nodes == 0 then
        return nil
    end

    local bestNode = nil
    local bestDist = math.huge
    for _, node in ipairs(nodes) do
        local d = manhattan(x, y, node.x, node.y)
        if d < bestDist then
            bestDist = d
            bestNode = node
        end
    end
    return bestNode
end

local function findPath(grid, cols, rows, startX, startY, goalX, goalY)
    if startX == goalX and startY == goalY then
        return {}
    end

    if not isWalkable(grid, cols, rows, goalX, goalY) then
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
        if not bestAdjX then return nil end
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

    return nil
end

function Agent.new(x, y)
    local self = setmetatable({}, Agent)
    self.x = math.floor(x or 1)
    self.y = math.floor(y or 1)

    self.worldState = {
        knowsLocation = false,
        atResource = false,
        hasResource = false
    }

    self.currentPlan = {}
    self.statusText = "Idle"
    self.moveSpeed = 2.0
    self.moveTimer = 0
    self.path = nil
    self.targetNode = nil
    self.harvestTimer = 0
    self.requiredHarvestTime = 2.0
    self.resourceHeld = false

    return self
end

function Agent:update(dt, cols, rows, grid, resourceNodes, boxNodes)
    dt = dt or 0.016

    if not self.resourceHeld then
        if not self.targetNode or self.targetNode.type ~= "resource" then
            self.targetNode = nearestNodeFromList(self.x, self.y, resourceNodes)
        end

        if not self.targetNode then
            self.statusText = "Need resource"
            self.path = nil
            return
        end

        if self.x == self.targetNode.x and self.y == self.targetNode.y then
            self.statusText = "Mining"
            self.harvestTimer = self.harvestTimer + dt
            if self.harvestTimer >= self.requiredHarvestTime then
                self.resourceHeld = true
                self.harvestTimer = 0
                self.statusText = "Holding resource"
                self.targetNode = nil
                self.path = nil
            end
            return
        end

        self.statusText = "Gathering"
        if not self.path or #self.path == 0 then
            self.path = findPath(grid, cols, rows, self.x, self.y, self.targetNode.x, self.targetNode.y)
            if not self.path or #self.path == 0 then
                self.statusText = "Blocked"
                self.path = nil
                return
            end
        end
    else
        if not self.targetNode or self.targetNode.type ~= "box" then
            self.targetNode = nearestNodeFromList(self.x, self.y, boxNodes)
        end

        if not self.targetNode then
            self.statusText = "Need box"
            self.path = nil
            return
        end

        if self.x == self.targetNode.x and self.y == self.targetNode.y then
            self.resourceHeld = false
            self.statusText = "Delivered"
            self.targetNode = nil
            self.path = nil
            self.harvestTimer = 0
            return
        end

        self.statusText = "Delivering"
        if not self.path or #self.path == 0 then
            self.path = findPath(grid, cols, rows, self.x, self.y, self.targetNode.x, self.targetNode.y)
            if not self.path or #self.path == 0 then
                self.statusText = "Blocked"
                self.path = nil
                return
            end
        end
    end

    self.moveTimer = self.moveTimer + dt
    local stepInterval = 1.0 / math.max(0.001, self.moveSpeed)
    while self.moveTimer >= stepInterval and self.path and #self.path > 0 do
        self.moveTimer = self.moveTimer - stepInterval
        local nextCell = table.remove(self.path, 1)
        if isWalkable(grid, cols, rows, nextCell.x, nextCell.y) then
            self.x = nextCell.x
            self.y = nextCell.y
        else
            self.path = nil
            break
        end
    end
end

return Agent
