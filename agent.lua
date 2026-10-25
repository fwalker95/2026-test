local Pathfinding = require("pathfinding")
local AI = require("ai")

local Agent = {}
Agent.__index = Agent

local R = (love and love.math) or math

-- Fallback colors when no PNG exists for the role
local roleColors = {
    miner = { 0.2, 1.0, 0.3 },
    scientist = { 0.3, 0.6, 1.0 },
}

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

    if target.getNearestWorkTileFrom and type(target.getNearestWorkTileFrom) == "function" then
        local tile = target:getNearestWorkTileFrom(fromX, fromY)
        if tile then return tile end
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

    self.idle = nil
    self.idleCooldown = R.random() * 1.5

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

function Agent:draw(cellSize)
    local px = (self.renderX - 0.5) * cellSize
    local py = (self.renderY - 0.5) * cellSize

    if self.image then
        love.graphics.setColor(1, 1, 1)
        local sx = cellSize / self.image:getWidth()
        local sy = cellSize / self.image:getHeight()
        love.graphics.draw(self.image, px, py, 0, sx, sy)
    else
        local c = roleColors[self.role] or { 0.2, 1, 0.3 }
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.print(self.statusText or "Idle", px - 10, py - 18)
end

function Agent:moveAlongPath(dt, cols, rows, grid, allAgents, goalX, goalY)
    local note = nil
    local reservations = Pathfinding.buildReservationMap(allAgents, self)
    self.moveTimer = self.moveTimer + dt
    local stepInterval = 1.0 / math.max(0.001, self.moveSpeed)

    while self.moveTimer >= stepInterval and self.path and #self.path > 0 do
        self.moveTimer = self.moveTimer - stepInterval
        local nextCell = table.remove(self.path, 1)
        local nextKey = cellKey(nextCell.x, nextCell.y)

        if Pathfinding.isWalkable(grid, cols, rows, nextCell.x, nextCell.y)
            and not reservations[nextKey]
            and not isOccupiedByAgent(allAgents, self, nextCell.x, nextCell.y) then
            self.x = nextCell.x
            self.y = nextCell.y
            self.targetRenderX = self.x - 0.5
            self.targetRenderY = self.y - 0.5
            self._reservedCell = { x = self.x, y = self.y }
            reservations = Pathfinding.buildReservationMap(allAgents, self)
        else
            local alternative = Pathfinding.findBestAlternativeStep(self, grid, cols, rows, goalX or self.x, goalY or self.y, reservations)

            if alternative
                and Pathfinding.isWalkable(grid, cols, rows, alternative.x, alternative.y)
                and not reservations[cellKey(alternative.x, alternative.y)]
                and not isOccupiedByAgent(allAgents, self, alternative.x, alternative.y) then
                self.x = alternative.x
                self.y = alternative.y
                self.targetRenderX = self.x - 0.5
                self.targetRenderY = self.y - 0.5
                note = "Making space"
                self._reservedCell = { x = self.x, y = self.y }
                reservations = Pathfinding.buildReservationMap(allAgents, self)
            else
                self.path = nil
                note = "Yielding"
                self.crowdCooldown = 0.25
                self._reservedCell = { x = self.x, y = self.y }
                break
            end
        end
    end

    return note
end

function Agent:endIdle(cooldown)
    local idle = self.idle
    if idle and idle.partner then
        local p = idle.partner
        if p.idle and p.idle.partner == self then
            p.idle = nil
            p.path = nil
            p.idleCooldown = 1 + R.random() * 2
        end
    end
    self.idle = nil
    self.path = nil
    self.idleCooldown = cooldown or (1 + R.random() * 2)
end

function Agent:beginIdle(choice, cols, rows, grid)
    if choice.type == "smoke" then
        self.idle = { type = "smoke", timer = 4 + R.random() * 4 }

    elseif choice.type == "chat" and choice.partner then
        local dur = 3 + R.random() * 3
        local p = choice.partner
        if p.idle then p:endIdle() end
        p.path = nil
        p.idle = { type = "chat", timer = dur, partner = self, role = "listener" }
        self.idle = { type = "chat", timer = dur, partner = p, role = "initiator" }

    else
        local tries = 0
        while tries < 8 do
            tries = tries + 1
            local tx = self.x + R.random(-6, 6)
            local ty = self.y + R.random(-6, 6)
            if (tx ~= self.x or ty ~= self.y) and Pathfinding.isWalkable(grid, cols, rows, tx, ty) then
                local path = Pathfinding.findPath(grid, cols, rows, self.x, self.y, tx, ty)
                if path and #path > 0 then
                    self.path = path
                    self.idle = { type = "wander", tx = tx, ty = ty }
                    return
                end
            end
        end
        self.idle = nil
        self.idleCooldown = 1
    end
end

function Agent:updateIdle(dt, cols, rows, grid, allAgents)
    self._reservedCell = { x = self.x, y = self.y }

    if not self.idle then
        self.idleCooldown = math.max(0, (self.idleCooldown or 0) - dt)
        self.statusText = "Idle"
        if self.idleCooldown > 0 then return end
        self:beginIdle(AI.chooseIdle(self, allAgents), cols, rows, grid)
        if not self.idle then return end
    end

    local idle = self.idle

    if idle.type == "smoke" then
        self.statusText = "Smoking"
        idle.timer = idle.timer - dt
        if idle.timer <= 0 then self:endIdle() end

    elseif idle.type == "wander" then
        self.statusText = "Wandering"
        if self.path and #self.path > 0 then
            self:moveAlongPath(dt, cols, rows, grid, allAgents, idle.tx, idle.ty)
        end
        if not self.path or #self.path == 0 then
            self:endIdle()
        end

    elseif idle.type == "chat" then
        self.statusText = "Chatting"
        local p = idle.partner
        if not p or not p.idle or p.idle.partner ~= self or p.currentTask then
            self:endIdle()
            return
        end

        if idle.role == "listener" then
            self.path = nil
            return
        end

        if manhattan(self.x, self.y, p.x, p.y) <= 2 then
            self.path = nil
            idle.timer = idle.timer - dt
            if idle.timer <= 0 then self:endIdle() end
        else
            if not self.path or #self.path == 0 then
                local found = nil
                local neighbours = {
                    { p.x + 1, p.y }, { p.x - 1, p.y }, { p.x, p.y + 1 }, { p.x, p.y - 1 },
                }
                for _, n in ipairs(neighbours) do
                    if Pathfinding.isWalkable(grid, cols, rows, n[1], n[2])
                        and not isOccupiedByAgent(allAgents, self, n[1], n[2]) then
                        found = Pathfinding.findPath(grid, cols, rows, self.x, self.y, n[1], n[2])
                        if found and #found > 0 then break end
                        found = nil
                    end
                end
                if not found then
                    self:endIdle()
                    return
                end
                self.path = found
            end
            self:moveAlongPath(dt, cols, rows, grid, allAgents, p.x, p.y)
        end
    end
end

function Agent:update(dt, cols, rows, grid, interactables, allAgents)
    dt = dt or 0.016
    self.crowdCooldown = math.max(0, self.crowdCooldown - dt)

    self.renderX = self.renderX + (self.targetRenderX - self.renderX) * math.min(1, dt * 12)
    self.renderY = self.renderY + (self.targetRenderY - self.renderY) * math.min(1, dt * 12)

    if not self.currentTask then
        self:chooseTask(interactables)
        if self.currentTask and self.idle then
            self:endIdle(0)
        end
    end

    if not self.currentTask then
        self:updateIdle(dt, cols, rows, grid, allAgents)
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
        local ttype = self.currentTask.type

        if ttype == "mine" then
            if target:work(self, dt) then
                self.resourceHeld = true
                self.statusText = "Holding resource"
                target:release()
                self.currentTask = nil
                self.path = nil
                self.harvestTimer = 0
            end
            self._reservedCell = { x = self.x, y = self.y }
            return
        end

        if ttype == "deliver" then
            if target:work(self, dt) then
                self.resourceHeld = false
                self.statusText = "Delivered"
                target:release()
                self.currentTask = nil
                self.path = nil
                self.harvestTimer = 0
            end
            self._reservedCell = { x = self.x, y = self.y }
            return
        end

        if ttype == "research" then
            if target:work(self, dt) then
                target:release()
                self.currentTask = nil
                self.path = nil
                self.harvestTimer = 0
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
            if target.release then target:release() end
            self.currentTask = nil
            self._reservedCell = { x = self.x, y = self.y }
            return
        end
    end

    local note = self:moveAlongPath(dt, cols, rows, grid, allAgents, target.x, target.y)
    if note then self.statusText = note end
end

return Agent
