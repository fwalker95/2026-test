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

local function cellKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function isOccupiedByAgent(agents, ignoreAgent, x, y)
    if not agents then return false end
    if not x or not y then return true end

    for _, other in ipairs(agents) do
        if other ~= ignoreAgent and other.x == x and other.y == y then
            return true
        end
    end

    return false
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

local function nearestAvailableNode(x, y, nodes, predicate)
    if not nodes or #nodes == 0 then
        return nil
    end

    local bestNode = nil
    local bestDist = math.huge
    for _, node in ipairs(nodes) do
        if (not predicate) or predicate(node) then
            local d = manhattan(x, y, node.x, node.y)
            if d < bestDist then
                bestDist = d
                bestNode = node
            end
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

local function buildReservationMap(agents, ignoreAgent)
    local reservations = {}
    if not agents then return reservations end

    for _, other in ipairs(agents) do
        if other ~= ignoreAgent then
            local reservedCell = other._reservedCell or { x = other.x, y = other.y }
            if reservedCell and reservedCell.x and reservedCell.y then
                reservations[cellKey(reservedCell.x, reservedCell.y)] = true
            end
        end
    end

    return reservations
end

local function findBestAlternativeStep(agent, grid, cols, rows, goalX, goalY, reservations, allAgents)
    local best = nil
    local bestScore = math.huge
    local options = {
        {0, 1}, {0, -1}, {1, 0}, {-1, 0},
        {1, 1}, {-1, 1}, {1, -1}, {-1, -1},
        {2, 0}, {-2, 0}, {0, 2}, {0, -2},
        {1, 2}, {-1, 2}, {1, -2}, {-1, -2},
        {2, 1}, {2, -1}, {-2, 1}, {-2, -1}
    }

    for _, dir in ipairs(options) do
        local nx, ny = agent.x + dir[1], agent.y + dir[2]
        local key = cellKey(nx, ny)

        if isWalkable(grid, cols, rows, nx, ny) and not reservations[key] and not isOccupiedByAgent(allAgents, agent, nx, ny) then
            local score = manhattan(nx, ny, goalX, goalY)
            score = score + (math.abs(nx - agent.x) + math.abs(ny - agent.y)) * 0.85
            if score < bestScore then
                bestScore = score
                best = { x = nx, y = ny }
            end
        end
    end

    return best
end

local function nearestInteractable(agent, interactables, predicate)
    if not interactables or #interactables == 0 then return nil end

    local best = nil
    local bestDist = math.huge
    for _, node in ipairs(interactables) do
        if node and predicate(node) then
            local d = manhattan(agent.x, agent.y, node.x, node.y)
            if d < bestDist then
                bestDist = d
                best = node
            end
        end
    end

    return best
end

local function findBestLegalWorkTile(agent, target, grid, cols, rows, reservations)
    if not target then return nil end
    local tiles = target:getWorkTiles and target:getWorkTiles() or { { x = target.x, y = target.y } }
    local best = nil
    local bestScore = math.huge

    for _, tile in ipairs(tiles) do
        local key = cellKey(tile.x, tile.y)
        if tile and tile.x and tile.y and (tile.x ~= target.x or tile.y ~= target.y) then
            if isWalkable(grid, cols, rows, tile.x, tile.y) and not reservations[key] then
                local score = manhattan(agent.x, agent.y, tile.x, tile.y)
                score = score + manhattan(tile.x, tile.y, target.x, target.y) * 0.25
                if score < bestScore then
                    bestScore = score
                    best = tile
                end
            end
        end
    end

    return best
end

local function hasValidTask(task)
    return task ~= nil and task.target ~= nil and task.target.enabled ~= false
end

function Agent.new(x, y, role)
    local self = setmetatable({}, Agent)
    self.x = math.floor(x or 1)
    self.y = math.floor(y or 1)
    self.renderX = self.x - 0.5
    self.renderY = self.y - 0.5
    self.targetRenderX = self.renderX
    self.targetRenderY = self.renderY
    self._reservedCell = { x = self.x, y = self.y }

    self.role = role or "miner"
    self.taskQueue = {}
    self.currentTask = nil
    self.currentGoal = nil
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
    self.crowdCooldown = 0
    self.wanderTarget = nil
    self.chatPartner = nil
    self.chatTimer = 0

    return self
end

function Agent:setTask(task)
    self.currentTask = task
    self.targetNode = task and task.target or nil
    self.statusText = task and task.label or "Idle"
end

function Agent:chooseTask(interactables)
    if not interactables then return nil end

    local function mineReady(node)
        return node.kind == "mine" and node:canInteract(self) and (node.resourceLeft == nil or node.resourceLeft > 0) and not node.claimedBy
    end

    local function dropOffReady(node)
        return (node.kind == "box" or node.kind == "storage") and node:canInteract(self) and (node.capacity == nil or (node.amount or 0) < node.capacity) and not node.claimedBy
    end

    if self.role == "miner" then
        if self.resourceHeld then
            local box = nearestInteractable(self, interactables, dropOffReady)
            if box then
                if box:claim(self) then
                    self:setTask({ type = "deliver", label = "Delivering", target = box, kind = box.kind })
                    return self.currentTask
                end
            end
        else
            local mine = nearestInteractable(self, interactables, mineReady)
            if mine then
                if mine:claim(self) then
                    self:setTask({ type = "mine", label = "Mining", target = mine, kind = "mine" })
                    return self.currentTask
                end
            end
        end
    end

    return nil
end

function Agent:pickWanderTarget(grid, cols, rows, allAgents)
    local candidates = {}
    for x = -5, 5 do
        for y = -5, 5 do
            if math.abs(x) + math.abs(y) > 0 and math.abs(x) + math.abs(y) <= 6 then
                local nx = self.x + x
                local ny = self.y + y
                if isWalkable(grid, cols, rows, nx, ny) and not isOccupiedByAgent(allAgents, self, nx, ny) then
                    table.insert(candidates, { x = nx, y = ny })
                end
            end
        end
    end

    if #candidates == 0 then
        self.wanderTarget = nil
        return nil
    end

    local target = candidates[math.random(1, #candidates)]
    self.wanderTarget = target
    return target
end

function Agent:tryChat(allAgents)
    if self.chatTimer > 0 then
        self.chatTimer = self.chatTimer - 0.1
        if self.chatTimer <= 0 then
            self.chatPartner = nil
        end
        return true
    end

    local bestPartner = nil
    local bestDist = math.huge
    for _, other in ipairs(allAgents or {}) do
        if other ~= self then
            local d = manhattan(self.x, self.y, other.x, other.y)
            if d <= 2 and (other.statusText == "Wandering" or other.statusText == "Chatting") then
                if d < bestDist then
                    bestDist = d
                    bestPartner = other
                end
            end
        end
    end

    if bestPartner then
        self.chatPartner = bestPartner
        self.chatTimer = 2.0
        self.statusText = "Chatting"
        return true
    end

    self.chatPartner = nil
    return false
end

function Agent:update(dt, cols, rows, grid, interactables, allAgents)
    dt = dt or 0.016
    self.crowdCooldown = math.max(0, self.crowdCooldown - dt)

    self.renderX = self.renderX + (self.targetRenderX - self.renderX) * math.min(1, dt * 12)
    self.renderY = self.renderY + (self.targetRenderY - self.renderY) * math.min(1, dt * 12)

    if self.chatTimer > 0 then
        self.chatTimer = math.max(0, self.chatTimer - dt)
        if self.chatTimer == 0 then
            self.chatPartner = nil
        end
    end

    if not self.currentTask then
        self:chooseTask(interactables)
        if not self.currentTask then
            if not self.wanderTarget or (self.x == self.wanderTarget.x and self.y == self.wanderTarget.y) then
                self:pickWanderTarget(grid, cols, rows, allAgents)
            end
            if self.wanderTarget then
                self:setTask({ type = "wander", label = "Wandering", target = { x = self.wanderTarget.x, y = self.wanderTarget.y, enabled = true } })
            end
        end
    end

    if not self.currentTask then
        self.statusText = "Idle"
        self.path = nil
        self._reservedCell = { x = self.x, y = self.y }
        return
    end

    local target = self.currentTask.target
    if not hasValidTask(self.currentTask) then
        self.currentTask = nil
        self.targetNode = nil
        self.path = nil
        self._reservedCell = { x = self.x, y = self.y }
        return
    end

    if self.x == target.x and self.y == target.y then
        if self.currentTask.type == "wander" then
            self.wanderTarget = nil
            self.chatPartner = nil
            self.statusText = "Chatting"
            self.chatTimer = 1.2
            self.currentTask = nil
            self.targetNode = nil
            self.path = nil
            self._reservedCell = { x = self.x, y = self.y }
            if self:tryChat(allAgents) then
                self.statusText = "Chatting"
            end
            return
        end

        self.statusText = "Blocked"
        self.currentTask = nil
        self.targetNode = nil
        self.path = nil
        self._reservedCell = { x = self.x, y = self.y }
        return
    end

    local reservations = buildReservationMap(allAgents, self)
    local workTile = nil
    if target and target.getWorkTiles and target:isLegalWorkPosition(self.x, self.y) then
        workTile = { x = self.x, y = self.y }
    else
        workTile = findBestLegalWorkTile(self, target, grid, cols, rows, reservations)
    end

    if not workTile then
        self.statusText = "Blocked"
        self.currentTask = nil
        self.targetNode = nil
        self.path = nil
        self._reservedCell = { x = self.x, y = self.y }
        return
    end

    if target:isLegalWorkPosition and target:isLegalWorkPosition(workTile.x, workTile.y) then
        if self.x == workTile.x and self.y == workTile.y then
            self.statusText = self.currentTask.label
            self.harvestTimer = self.harvestTimer + dt

            if self.currentTask.type == "mine" then
                if target:work(self, dt) then
                    self.resourceHeld = true
                    self.statusText = "Holding resource"
                    target:release()
                    self.currentTask = nil
                    self.targetNode = nil
                    self.path = nil
                    self.harvestTimer = 0
                    self._reservedCell = { x = self.x, y = self.y }
                    self.wanderTarget = nil
                    return
                end
                self._reservedCell = { x = self.x, y = self.y }
                return
            end

            if self.currentTask.type == "deliver" then
                if target:work(self, dt) then
                    self.resourceHeld = false
                    self.statusText = "Delivered"
                    target:release()
                    self.currentTask = nil
                    self.targetNode = nil
                    self.path = nil
                    self.harvestTimer = 0
                    self._reservedCell = { x = self.x, y = self.y }
                    self.wanderTarget = nil
                    return
                end
                self._reservedCell = { x = self.x, y = self.y }
                return
            end
        end
    end

    self.statusText = self.currentTask.label
    if not self.path or #self.path == 0 or (self.path[#self.path] and (self.path[#self.path].x ~= workTile.x or self.path[#self.path].y ~= workTile.y)) then
        if workTile then
            self.path = findPath(grid, cols, rows, self.x, self.y, workTile.x, workTile.y)
        end
        if not self.path or #self.path == 0 then
            self.statusText = "Blocked"
            self.path = nil
            self.currentTask = nil
            self.targetNode = nil
            self._reservedCell = { x = self.x, y = self.y }
            return
        end
    end

    reservations = buildReservationMap(allAgents, self)
    self.moveTimer = self.moveTimer + dt
    local stepInterval = 1.0 / math.max(0.001, self.moveSpeed)

    while self.moveTimer >= stepInterval and self.path and #self.path > 0 do
        self.moveTimer = self.moveTimer - stepInterval
        local nextCell = table.remove(self.path, 1)
        local nextKey = cellKey(nextCell.x, nextCell.y)

        if isWalkable(grid, cols, rows, nextCell.x, nextCell.y) and not reservations[nextKey] and not isOccupiedByAgent(allAgents, self, nextCell.x, nextCell.y) then
            self.x = nextCell.x
            self.y = nextCell.y
            self.targetRenderX = self.x - 0.5
            self.targetRenderY = self.y - 0.5
            self._reservedCell = { x = self.x, y = self.y }
            reservations = buildReservationMap(allAgents, self)
        else
            local goalX = workTile and workTile.x or self.x
            local goalY = workTile and workTile.y or self.y
            local alternative = findBestAlternativeStep(self, grid, cols, rows, goalX, goalY, reservations, allAgents)

            if alternative and isWalkable(grid, cols, rows, alternative.x, alternative.y) and not reservations[cellKey(alternative.x, alternative.y)] and not isOccupiedByAgent(allAgents, self, alternative.x, alternative.y) then
                self.x = alternative.x
                self.y = alternative.y
                self.targetRenderX = self.x - 0.5
                self.targetRenderY = self.y - 0.5
                self.statusText = "Making space"
                self._reservedCell = { x = self.x, y = self.y }
                reservations = buildReservationMap(allAgents, self)
            else
                self.path = nil
                self.statusText = "Yielding"
                self.crowdCooldown = 0.25
                self._reservedCell = { x = self.x, y = self.y }
                break
            end
        end
    end

    if self.currentTask and self.currentTask.type == "wander" then
        self:tryChat(allAgents)
    end
end

return Agent
