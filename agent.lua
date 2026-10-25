local Pathfinding = require("pathfinding")
local AI = require("ai")

local Agent = {}
Agent.__index = Agent

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

local function getTaskTile(target, fromX, fromY)
    if not target then return nil end

    if type(target.getWorkTiles) == "function" then
        local tiles = target:getWorkTiles()
        local best = nil
        local bestDist = math.huge

        for _, tile in ipairs(tiles) do
            if tile.x and tile.y then
                local d = manhattan(fromX, fromY, tile.x, tile.y)
                if d < bestDist then
                    bestDist = d
                    best = tile
                end
            end
        end

        if best then return best end
    end

    return { x = target.x, y = target.y }
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
    self.currentTask = nil
    self.statusText = "Idle"
    self.moveSpeed = 2.0
    self.moveTimer = 0
    self.path = nil
    self.targetNode = nil
    self.harvestTimer = 0
    self.worldState = {
        knowsLocation = false,
        atResource = false,
        hasResource = false,
    }
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
    self:setTask(AI.chooseTask(self, interactables))
    return self.currentTask
end

function Agent:update(dt, cols, rows, grid, interactables, allAgents)
    dt = dt or 0.016
    self.crowdCooldown = math.max(0, self.crowdCooldown - dt)

    self.renderX = self.renderX + (self.targetRenderX - self.renderX) * math.min(1, dt * 12)
    self.renderY = self.renderY + (self.targetRenderY - self.renderY) * math.min(1, dt * 12)

    if not self.currentTask then
        self:chooseTask(interactables)
    end

    if not self.currentTask then
        self.statusText = "Idle"
        self.path = nil
        self._reservedCell = { x = self.x, y = self.y }
        return
    end

    local target = self.currentTask.target
    if not target or not target.enabled then
        self.currentTask = nil
        self.path = nil
        self._reservedCell = { x = self.x, y = self.y }
        return
    end

    local interactionTile = getTaskTile(target, self.x, self.y)
    self.currentTask.workTile = interactionTile

    if self.x == interactionTile.x and self.y == interactionTile.y then
        self.statusText = self.currentTask.label
        self.harvestTimer = self.harvestTimer + dt

        if self.currentTask.type == "mine" then
            if target:work(self, dt) then
                self.resourceHeld = true
                self.statusText = "Holding resource"
                target:release()
                self.currentTask = nil
                self.path = nil
                self.harvestTimer = 0
                self._reservedCell = { x = self.x, y = self.y }
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
                self.path = nil
                self.harvestTimer = 0
                self._reservedCell = { x = self.x, y = self.y }
                return
            end
            self._reservedCell = { x = self.x, y = self.y }
            return
        end
    end

    self.statusText = self.currentTask.label
    if not self.path or #self.path == 0 then
        self.path = Pathfinding.findPath(grid, cols, rows, self.x, self.y, interactionTile.x, interactionTile.y)
        if not self.path or #self.path == 0 then
            self.statusText = "Blocked"
            self.path = nil
            self.currentTask = nil
            self._reservedCell = { x = self.x, y = self.y }
            return
        end
    end

    local reservations = Pathfinding.buildReservationMap(allAgents, self)
    self.moveTimer = self.moveTimer + dt
    local stepInterval = 1.0 / math.max(0.001, self.moveSpeed)

    while self.moveTimer >= stepInterval and self.path and #self.path > 0 do
        self.moveTimer = self.moveTimer - stepInterval
        local nextCell = table.remove(self.path, 1)
        local nextKey = cellKey(nextCell.x, nextCell.y)

        if Pathfinding.isWalkable(grid, cols, rows, nextCell.x, nextCell.y) and not reservations[nextKey] and not isOccupiedByAgent(allAgents, self, nextCell.x, nextCell.y) then
            self.x = nextCell.x
            self.y = nextCell.y
            self.targetRenderX = self.x - 0.5
            self.targetRenderY = self.y - 0.5
            self._reservedCell = { x = self.x, y = self.y }
            reservations = Pathfinding.buildReservationMap(allAgents, self)
        else
            local goalX = interactionTile.x
            local goalY = interactionTile.y
            local alternative = Pathfinding.findBestAlternativeStep(self, grid, cols, rows, goalX, goalY, reservations)

            if alternative and not isOccupiedByAgent(allAgents, self, alternative.x, alternative.y) then
                self.x = alternative.x
                self.y = alternative.y
                self.targetRenderX = self.x - 0.5
                self.targetRenderY = self.y - 0.5
                self.statusText = "Making space"
                self._reservedCell = { x = self.x, y = self.y }
                self.path = nil
                reservations = Pathfinding.buildReservationMap(allAgents, self)
            else
                self.path = nil
                self.statusText = "Yielding"
                self.crowdCooldown = 0.25
                self._reservedCell = { x = self.x, y = self.y }
                break
            end
        end
    end
end

return Agent
