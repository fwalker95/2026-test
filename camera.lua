-- camera.lua
-- RTS-style camera: pans over a fixed-size world grid.
-- Pan with WASD / arrow keys, screen-edge scrolling, or middle-mouse drag.

local Camera = {}
Camera.__index = Camera

function Camera.new(worldW, worldH, opts)
    opts = opts or {}
    local self = setmetatable({}, Camera)
    self.x = 0                           -- top-left of the view, in world pixels
    self.y = 0
    self.worldW = worldW                 -- world size in pixels
    self.worldH = worldH
    self.speed = opts.speed or 600       -- keyboard / edge pan speed (px/sec)
    self.edgeSize = opts.edgeSize or 20  -- edge scroll zone (px); 0 disables
    self.edgeScroll = opts.edgeScroll ~= false
    self.dragging = false
    self.lastMX, self.lastMY = 0, 0
    return self
end

function Camera:clamp()
    local sw, sh = love.graphics.getDimensions()
    local maxX = math.max(0, self.worldW - sw)
    local maxY = math.max(0, self.worldH - sh)
    self.x = math.max(0, math.min(self.x, maxX))
    self.y = math.max(0, math.min(self.y, maxY))
end

function Camera:update(dt)
    local dx, dy = 0, 0
    local kd = love.keyboard.isDown

    if kd("a") or kd("left") then dx = dx - 1 end
    if kd("d") or kd("right") then dx = dx + 1 end
    if kd("w") or kd("up") then dy = dy - 1 end
    if kd("s") or kd("down") then dy = dy + 1 end

    if self.edgeScroll and self.edgeSize > 0 and not self.dragging
        and love.window.hasMouseFocus() then
        local mx, my = love.mouse.getPosition()
        local sw, sh = love.graphics.getDimensions()
        if mx <= self.edgeSize then dx = dx - 1 end
        if mx >= sw - self.edgeSize then dx = dx + 1 end
        if my <= self.edgeSize then dy = dy - 1 end
        if my >= sh - self.edgeSize then dy = dy + 1 end
    end

    -- normalize so diagonals aren't faster
    if dx ~= 0 and dy ~= 0 then
        dx, dy = dx * 0.7071, dy * 0.7071
    end

    self.x = self.x + dx * self.speed * dt
    self.y = self.y + dy * self.speed * dt

    -- middle-mouse drag panning
    if self.dragging then
        local mx, my = love.mouse.getPosition()
        self.x = self.x - (mx - self.lastMX)
        self.y = self.y - (my - self.lastMY)
        self.lastMX, self.lastMY = mx, my
    end

    self:clamp()
end

-- Call from love.mousepressed / love.mousereleased
function Camera:mousepressed(x, y, button)
    if button == 3 then
        self.dragging = true
        self.lastMX, self.lastMY = x, y
        return true
    end
    return false
end

function Camera:mousereleased(x, y, button)
    if button == 3 then
        self.dragging = false
        return true
    end
    return false
end

-- Everything drawn between attach() and detach() is in world space.
function Camera:attach()
    love.graphics.push()
    love.graphics.translate(-math.floor(self.x), -math.floor(self.y))
end

function Camera:detach()
    love.graphics.pop()
end

function Camera:screenToWorld(sx, sy)
    return sx + self.x, sy + self.y
end

function Camera:worldToScreen(wx, wy)
    return wx - self.x, wy - self.y
end

-- Screen position -> 1-based grid cell
function Camera:screenToCell(sx, sy, cellSize)
    local wx, wy = self:screenToWorld(sx, sy)
    return math.floor(wx / cellSize) + 1, math.floor(wy / cellSize) + 1
end

-- Visible 1-based cell range (for culling the grid draw loop)
function Camera:visibleCells(cellSize, cols, rows)
    local sw, sh = love.graphics.getDimensions()
    local x1 = math.max(1, math.floor(self.x / cellSize) + 1)
    local y1 = math.max(1, math.floor(self.y / cellSize) + 1)
    local x2 = math.min(cols, math.floor((self.x + sw) / cellSize) + 1)
    local y2 = math.min(rows, math.floor((self.y + sh) / cellSize) + 1)
    return x1, y1, x2, y2
end

return Camera
