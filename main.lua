-- main.lua
local Camera = require("camera")
local UI = require("ui")
local World = require("world")

local world, camera, ui

function love.load()
    world = World.new()
    ui = UI.new(world.agents)

    local worldW = world.cols * world.cellSize
    local worldH = world.rows * world.cellSize
    camera = Camera.new(worldW, worldH, { speed = 700, edgeSize = 18, edgeScroll = true })
end

function love.update(dt)
    UI.update(ui, world.agents)

    camera:update(dt)

    if love.mouse.isDown(1) then
        local mx, my = love.mouse.getPosition()

        -- UI is screen space (not camera-translated)
        if UI.handleLeftClick(ui, mx, my, true) then
            return
        end

        local cx, cy = camera:screenToCell(mx, my, world.cellSize)
        World.applyTool(world, ui.selectedTool, cx, cy)
    end

    World.update(world, dt)
end

function love.keypressed(key)
    if key == "space" then
        local mx, my = love.mouse.getPosition()
        local cx, cy = camera:screenToCell(mx, my, world.cellSize)
        World.spawnAgent(world, cx, cy)
    end

    if key == "c" then
        World.clearGrid(world)
    end
end

function love.mousepressed(x, y, button)
    if camera:mousepressed(x, y, button) then return end
    if button ~= 1 then return end

    if UI.handleLeftClick(ui, x, y) then
        return
    end

    local cx, cy = camera:screenToCell(x, y, world.cellSize)
    World.applyTool(world, ui.selectedTool, cx, cy)
end

function love.mousereleased(x, y, button)
    camera:mousereleased(x, y, button)
end

function love.draw()
    camera:attach()
    local x1, y1, x2, y2 = camera:visibleCells(world.cellSize, world.cols, world.rows)
    World.draw(world, x1, y1, x2, y2)
    camera:detach()

    -- UI in screen space
    UI.draw(ui)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Pan: WASD/Arrows, edge scroll, or middle mouse drag | Left-click: Place/Select | SPACE: Spawn Agent | 'C': Clear Walls", 20, 10)
end
