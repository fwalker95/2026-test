-- main.lua
local Agent = require("agent")

function love.load()
    cols = 40
    rows = 30
    cellSize = 20

    grid = {}
    for x = 1, cols do
        grid[x] = {}
        for y = 1, rows do grid[x][y] = 0 end
    end

    -- Resource Node at column 30, row 15
    resourceX = 30
    resourceY = 15

    agents = {}
    -- Start with 1 agent at (10, 15)
    table.insert(agents, Agent.new(10, 15))

    moveTimer = 0
    moveInterval = 0.2 -- Speed step
end

function love.update(dt)
    -- Left-click paints walls
    if love.mouse.isDown(1) then
        local mx, my = love.mouse.getPosition()
        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            if not (cx == resourceX and cy == resourceY) then
                grid[cx][cy] = 1
            end
        end
    end

    -- Right-click erases walls
    if love.mouse.isDown(2) then
        local mx, my = love.mouse.getPosition()
        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            grid[cx][cy] = 0
        end
    end

    -- Step agents on timer tick
    moveTimer = moveTimer + dt
    if moveTimer >= moveInterval then
        moveTimer = 0
        for _, agent in ipairs(agents) do
            agent:update(dt, cols, rows, grid, resourceX, resourceY)
        end
    end
end

function love.keypressed(key)
    -- Spacebar spawns a new agent at mouse cursor
    if key == "space" then
        local mx, my = love.mouse.getPosition()
        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            table.insert(agents, Agent.new(cx, cy))
        end
    end

    -- 'c' clears all walls
    if key == "c" then
        for x = 1, cols do
            for y = 1, rows do grid[x][y] = 0 end
        end
    end
end

function love.draw()
    -- Draw grid
    for x = 1, cols do
        for y = 1, rows do
            local px, py = (x - 1) * cellSize, (y - 1) * cellSize
            if x == resourceX and y == resourceY then
                love.graphics.setColor(1, 0.8, 0.1) -- Gold Resource Node
            elseif grid[x][y] == 1 then
                love.graphics.setColor(0.3, 0.3, 0.3) -- Grey Wall
            else
                love.graphics.setColor(0.12, 0.12, 0.12) -- Dark Grid
            end
            love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        end
    end

    -- Draw agents (Green squares)
    love.graphics.setColor(0.2, 1, 0.3)
    for _, agent in ipairs(agents) do
        local px, py = (agent.x - 1) * cellSize, (agent.y - 1) * cellSize
        love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        
        -- Print live GOAP status text
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(agent.statusText, px - 10, py - 18)
    end
    
    -- Controls HUD
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Left-click: Draw Walls | Right-click: Erase | SPACE: Spawn Agent | 'C': Clear Walls", 20, 10)
end
