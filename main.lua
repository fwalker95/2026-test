-- main.lua
local Agent = require("agent")

local function listAgentsMenu(agents)
    local items = {}
    for i, agent in ipairs(agents) do
        local status = agent.statusText or "Idle"
        local holding = agent.worldState and tostring(agent.worldState.hasResource) or "false"
        table.insert(items, string.format("Agent %d: (%d,%d) %s hold=%s", i, agent.x, agent.y, status, holding))
    end
    return items
end

UIButton = {}
UIButton.__index = UIButton

function UIButton:new(x, y, w, h, label, onClick)
    local btn = setmetatable({}, UIButton)
    btn.x = x
    btn.y = y
    btn.w = w
    btn.h = h
    btn.label = label or "Button"
    btn.onClick = onClick or function() end
    btn.selected = false
    return btn
end

function UIButton:contains(px, py)
    return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
end

function UIButton:draw()
    if self.selected then
        love.graphics.setColor(0.3, 0.75, 0.95)
    else
        love.graphics.setColor(0.18, 0.18, 0.2)
    end
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(self.label, self.x + 10, self.y + 8)
end

Menu = {}
Menu.__index = Menu

function Menu:new(x, y, w, h)
    local m = setmetatable({}, Menu)
    m.x = x
    m.y = y
    m.w = w
    m.h = h
    m.visible = false
    m.items = {}
    return m
end

function Menu:addItem(label, callback)
    table.insert(self.items, { label = label, callback = callback })
end

function Menu:draw()
    if not self.visible then return end

    love.graphics.setColor(0.12, 0.12, 0.15, 0.95)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    for i, item in ipairs(self.items) do
        local iy = self.y + 10 + (i - 1) * 22
        love.graphics.setColor(0.22, 0.22, 0.28)
        love.graphics.rectangle("fill", self.x + 6, iy, self.w - 12, 18)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.label, self.x + 12, iy + 4)
    end
end

function Menu:click(px, py)
    if not self.visible then return false end

    for i, item in ipairs(self.items) do
        local iy = self.y + 10 + (i - 1) * 22
        if px >= self.x + 6 and px <= self.x + self.w - 6 and py >= iy and py <= iy + 18 then
            if item.callback then item.callback() end
            return true
        end
    end

    return false
end

AgentListMenu = setmetatable({}, { __index = Menu })

function AgentListMenu:new(x, y, w)
    local m = Menu.new(self, x, y, w, 220)
    m.visible = false
    m.refresh = function(self, agents)
        self.items = {}
        if #agents == 0 then
            table.insert(self.items, { label = "No agents", callback = function() end })
            return
        end

        for i, agent in ipairs(agents) do
            local status = agent.statusText or "Idle"
            local holding = agent.resourceHeld and "yes" or "no"
            local label = string.format("Agent %d: (%d,%d) %s hold=%s", i, agent.x, agent.y, status, holding)
            table.insert(self.items, {
                label = label,
                callback = function() end
            })
        end
    end
    return m
end

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
        { x = 30, y = 15, remaining = 5, type = "resource" }
    }
    boxNodes = {
        { x = 20, y = 15, amount = 0, capacity = 10, type = "box" }
    }

    agents = {}
    table.insert(agents, Agent.new(10, 15))

    selectedTool = "resource"
    menuRect = { x = 10, y = 10, w = 150, h = 80 }

    agentButton = UIButton:new(10, 100, 160, 28, "Agents", function()
        agentMenu.visible = not agentMenu.visible
    end)

    agentMenu = AgentListMenu:new(190, 100, 360)
    agentMenu:refresh(agents)
end

function love.update(dt)
    if agentMenu then
        agentMenu:refresh(agents)
    end

    if love.mouse.isDown(1) then
        local mx, my = love.mouse.getPosition()

        if agentButton:contains(mx, my) then
            return
        end

        if agentMenu.visible and agentMenu:click(mx, my) then
            return
        end

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
                for _, agent in ipairs(agents) do
                    if agent.x == cx and agent.y == cy then
                        occupied = true
                        break
                    end
                end
                if not occupied then
                    table.insert(resourceNodes, { x = cx, y = cy, remaining = 5, type = "resource" })
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
                for _, agent in ipairs(agents) do
                    if agent.x == cx and agent.y == cy then
                        occupied = true
                        break
                    end
                end
                if not occupied then
                    table.insert(boxNodes, { x = cx, y = cy, amount = 0, capacity = 10, type = "box" })
                end
            end
        end
    end

    if love.mouse.isDown(2) then
        local mx, my = love.mouse.getPosition()
        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            grid[cx][cy] = 0
        end
    end

    for _, agent in ipairs(agents) do
        agent:update(dt, cols, rows, grid, resourceNodes, boxNodes, agents)
    end
end

function love.keypressed(key)
    if key == "space" then
        local mx, my = love.mouse.getPosition()
        local cx, cy = math.floor(mx / cellSize) + 1, math.floor(my / cellSize) + 1
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            local occupied = false
            for _, agent in ipairs(agents) do
                if agent.x == cx and agent.y == cy then
                    occupied = true
                    break
                end
            end
            if not occupied then
                table.insert(agents, Agent.new(cx, cy))
            end
        end
    end

    if key == "c" then
        for x = 1, cols do
            for y = 1, rows do grid[x][y] = 0 end
        end
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end

    if agentButton:contains(x, y) then
        agentButton.onClick()
        return
    end

    if agentMenu.visible and agentMenu:click(x, y) then
        return
    end

    if x >= menuRect.x and x <= menuRect.x + menuRect.w and y >= menuRect.y and y <= menuRect.y + menuRect.h then
        if y <= menuRect.y + 30 then
            selectedTool = "resource"
        elseif y <= menuRect.y + 60 then
            selectedTool = "box"
        else
            selectedTool = "erase"
        end
        return
    end

    local cx, cy = math.floor(x / cellSize) + 1, math.floor(y / cellSize) + 1
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
            for _, agent in ipairs(agents) do
                if agent.x == cx and agent.y == cy then
                    occupied = true
                    break
                end
            end
            if not occupied then
                table.insert(resourceNodes, { x = cx, y = cy, remaining = 5, type = "resource" })
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
            for _, agent in ipairs(agents) do
                if agent.x == cx and agent.y == cy then
                    occupied = true
                    break
                end
            end
            if not occupied then
                table.insert(boxNodes, { x = cx, y = cy, amount = 0, capacity = 10, type = "box" })
            end
        end
    end
end

function love.draw()
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

    for _, box in ipairs(boxNodes) do
        local pct = math.floor((box.amount / math.max(1, box.capacity)) * 100)
        local px = (box.x - 1) * cellSize + 2
        local py = (box.y - 1) * cellSize - 14
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("[%d%%]", pct), px, py)
    end

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

    agentButton:draw()
    if agentMenu then
        agentMenu:draw()
    end

    love.graphics.setColor(0.2, 1, 0.3)
    for _, agent in ipairs(agents) do
        local px = (agent.renderX - 0.5) * cellSize
        local py = (agent.renderY - 0.5) * cellSize
        love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(agent.statusText, px - 10, py - 18)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Left-click: Place/Select | Right-click: Erase Walls | SPACE: Spawn Agent | 'C': Clear Walls", 20, 10)
end
