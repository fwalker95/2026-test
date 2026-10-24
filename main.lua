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

    resourceNodes = {
        { x = 30, y = 15 }
    }
    boxNodes = {}

    agents = {}
    table.insert(agents, Agent.new(10, 15))

    selectedTool = "resource"
    menuRect = { x = 10, y = 10, w = 150, h = 80 }
end

function love.update(dt)
    -- Left-click paints walls
    if love.mouse.isDown(1) then
        local mx, my = love.mouse.getPosition()

        -- Top-left tool menu clicks
        if mx >= menuRect.x and mx <= menuRect.x + menuRect.w and my >= menuRect.y and my <= menuRect.y + menuRect.h then
            if my <= menuRect.y + 30 then
                selectedTool = "resource"
            elseif my <= menuRect.y + 60 then
                selectedTool = "box"
            else
                selectedTool = "erase"
            end
            return
        end

        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            if selectedTool == "erase" then
                grid[cx][cy] = 0
                for i = #resourceNodes, 1, -1 do
                    if resourceNodes[i].x == cx and resourceNodes[i].y == cy then
                        table.remove(resourceNodes, i)
                    end
                end
                for i = #boxNodes, 1, -1 do
                    if boxNodes[i].x == cx and boxNodes[i].y == cy then
                        table.remove(boxNodes, i)
                    end
                end
                return
            end

            if selectedTool == "resource" then
                if not (cx == resourceNodes[1] and cy == resourceNodes[1]) then
                    local occupied = false
                    for _, node in ipairs(resourceNodes) do
                        if node.x == cx and node.y == cy then
                            occupied = true
                            break
                        end
                    end
                    for _, box in ipairs(boxNodes) do
                        if box.x == cx and box.y == cy then
                            occupied = true
                            break
                        end
                    end
                    if not occupied then
                        table.insert(resourceNodes, { x = cx, y = cy })
                    end
                end
            elseif selectedTool == "box" then
                local occupied = false
                for _, node in ipairs(resourceNodes) do
                    if node.x == cx and node.y == cy then
                        occupied = true
                        break
                    end
                end
                for _, box in ipairs(boxNodes) do
                    if box.x == cx and box.y == cy then
                        occupied = true
                        break
                    end
                end
                if not occupied then
                    table.insert(boxNodes, { x = cx, y = cy })
                end
            end
        end
    end

    -- Right-click erases walls only.
    if love.mouse.isDown(2) then
        local mx, my = love.mouse.getPosition()
        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            grid[cx][cy] = 0
        end
    end

    for _, agent in ipairs(agents) do
        agent:update(dt, cols, rows, grid, resourceNodes, boxNodes)
    end
end

function love.keypressed(key)
    if key == "space" then
        local mx, my = love.mouse.getPosition()
        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            table.insert(agents, Agent.new(cx, cy))
        end
    end

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
            local isResource = false
            local isBox = false

            for _, node in ipairs(resourceNodes) do
                if node.x == x and node.y == y then
                    isResource = true
                    break
                end
            end

            for _, box in ipairs(boxNodes) do
                if box.x == x and box.y == y then
                    isBox = true
                    break
                end
            end

            if isResource then
                love.graphics.setColor(1, 0.8, 0.1)
            elseif isBox then
                love.graphics.setColor(0.2, 0.7, 1)
            elseif grid[x][y] == 1 then
                love.graphics.setColor(0.3, 0.3, 0.3)
            else
                love.graphics.setColor(0.12, 0.12, 0.12)
            end

            love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        end
    end

    -- Draw menu in top-left
    love.graphics.setColor(0.12, 0.12, 0.18, 0.9)
    love.graphics.rectangle("fill", menuRect.x, menuRect.y, menuRect.w, menuRect.h)

    local items = {
        { name = "resource", label = "Resource" },
        { name = "box", label = "Box" },
        { name = "erase", label = "Erase" }
    }

    for i, item in ipairs(items) do
        local y = menuRect.y + (i - 1) * 30
        local selected = selectedTool == item.name
        love.graphics.setColor(selected and 0.35 or 0.2, selected and 0.9 or 0.5, selected and 0.35 or 0.6)
        love.graphics.rectangle("fill", menuRect.x + 5, y + 5, menuRect.w - 10, 20)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.label, menuRect.x + 15, y + 8)
    end

    -- Draw agents
    love.graphics.setColor(0.2, 1, 0.3)
    for _, agent in ipairs(agents) do
        local px, py = (agent.x - 1) * cellSize, (agent.y - 1) * cellSize
        love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(agent.statusText, px - 10, py - 18)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Left-click: Place/Select | Right-click: Erase Walls | SPACE: Spawn Agent | 'C': Clear Walls", 20, 10)
end
