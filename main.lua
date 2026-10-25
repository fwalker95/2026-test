-- main.lua
local Agent = require("agent")
local Interactable = require("interactable")
local Camera = require("camera")
local Resources = require("resources")

local function listAgentsMenu(agents)
    local items = {}
    for i, agent in ipairs(agents) do
        local status = agent.statusText or "Idle"
        local holding = agent.resourceHeld and "yes" or "no"
        local carried = agent.carriedType or "none"
        table.insert(items, string.format("Agent %d: (%d,%d) %s hold=%s carry=%s", i, agent.x, agent.y, status, holding, carried))
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
            local carried = agent.carriedType or "none"
            local label = string.format("Agent %d: (%d,%d) %s hold=%s carry=%s", i, agent.x, agent.y, status, holding, carried)
            table.insert(self.items, {
                label = label,
                callback = function() end
            })
        end
    end
    return m
end

function love.load()
    cols = 80
    rows = 60
    cellSize = 20

    grid = {}
    for x = 1, cols do
        grid[x] = {}
        for y = 1, rows do grid[x][y] = 0 end
    end

    interactables = {
        Interactable.new("mine", 30, 15, { allowedRoles = { "miner" }, resourceLeft = 5, interactionTime = 1.5, resourceType = "biomass" }),
        Interactable.new("mine", 27, 20, { allowedRoles = { "miner" }, resourceLeft = 5, interactionTime = 1.5, resourceType = "dna" }),
        Interactable.new("box", 20, 15, { allowedRoles = { "miner" }, capacity = 10, amount = 0, interactionTime = 1.0 }),
    }

    resources = Resources.new()
    resources:recount(interactables)

    agents = {}
    table.insert(agents, Agent.new(10, 15, "miner"))
    table.insert(agents, Agent.new(12, 17, "miner"))

    selectedTool = "resource"
    menuRect = { x = 10, y = 10, w = 150, h = 80 }

    agentButton = UIButton:new(10, 100, 160, 28, "Agents", function()
        agentMenu.visible = not agentMenu.visible
    end)

    agentMenu = AgentListMenu:new(190, 100, 420)
    agentMenu:refresh(agents)

    local worldW = cols * cellSize
    local worldH = rows * cellSize
    camera = Camera.new(worldW, worldH, { speed = 700, edgeSize = 18, edgeScroll = true })
end

function love.update(dt)
    if agentMenu then
        agentMenu:refresh(agents)
    end

    camera:update(dt)

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

        local cx, cy = camera:screenToCell(mx, my, cellSize)
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            if selectedTool == "erase" then
                grid[cx][cy] = 0
                for i = #interactables, 1, -1 do
                    local item = interactables[i]
                    if item.x == cx and item.y == cy then
                        table.remove(interactables, i)
                    end
                end
                resources:recount(interactables)
                return
            end

            if selectedTool == "resource" then
                local occupied = false
                for _, item in ipairs(interactables) do
                    if item.x == cx and item.y == cy then
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
                    table.insert(interactables, Interactable.new("mine", cx, cy, {
                        allowedRoles = { "miner" },
                        resourceLeft = 5,
                        interactionTime = 1.5,
                    }))
                    resources:recount(interactables)
                end
            elseif selectedTool == "box" then
                local occupied = false
                for _, item in ipairs(interactables) do
                    if item.x == cx and item.y == cy then
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
                    table.insert(interactables, Interactable.new("box", cx, cy, {
                        allowedRoles = { "miner" },
                        capacity = 10,
                        amount = 0,
                        interactionTime = 1.0,
                    }))
                    resources:recount(interactables)
                end
            end
        end
    end

    for _, agent in ipairs(agents) do
        agent:update(dt, cols, rows, grid, interactables, agents)
    end

    resources:recount(interactables)
end

function love.keypressed(key)
    if key == "space" then
        local mx, my = love.mouse.getPosition()
        local cx, cy = camera:screenToCell(mx, my, cellSize)
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
            local occupied = false
            for _, agent in ipairs(agents) do
                if agent.x == cx and agent.y == cy then
                    occupied = true
                    break
                end
            end
            if not occupied then
                table.insert(agents, Agent.new(cx, cy, "miner"))
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
    if camera:mousepressed(x, y, button) then return end
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

    local cx, cy = camera:screenToCell(x, y, cellSize)
    if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows then
        if selectedTool == "erase" then
            grid[cx][cy] = 0
            for i = #interactables, 1, -1 do
                local item = interactables[i]
                if item.x == cx and item.y == cy then
                    table.remove(interactables, i)
                end
            end
            resources:recount(interactables)
            return
        end

        if selectedTool == "resource" then
            local occupied = false
            for _, item in ipairs(interactables) do
                if item.x == cx and item.y == cy then
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
                table.insert(interactables, Interactable.new("mine", cx, cy, {
                    allowedRoles = { "miner" },
                    resourceLeft = 5,
                    interactionTime = 1.5,
                }))
                resources:recount(interactables)
            end
        elseif selectedTool == "box" then
            local occupied = false
            for _, item in ipairs(interactables) do
                if item.x == cx and item.y == cy then
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
                table.insert(interactables, Interactable.new("box", cx, cy, {
                    allowedRoles = { "miner" },
                    capacity = 10,
                    amount = 0,
                    interactionTime = 1.0,
                }))
                resources:recount(interactables)
            end
        end
    end
end

function love.mousereleased(x, y, button)
    camera:mousereleased(x, y, button)
end

function love.draw()
    camera:attach()

    local x1, y1, x2, y2 = camera:visibleCells(cellSize, cols, rows)
    for x = x1, x2 do
        for y = y1, y2 do
            local px, py = (x - 1) * cellSize, (y - 1) * cellSize
            local isInteractable = false

            for _, item in ipairs(interactables) do
                if item.x == x and item.y == y then
                    isInteractable = true
                    break
                end
            end

            if isInteractable then
                love.graphics.setColor(0.25, 0.25, 0.25)
            elseif grid[x][y] == 1 then
                love.graphics.setColor(0.3, 0.3, 0.3)
            else
                love.graphics.setColor(0.12, 0.12, 0.12)
            end

            love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        end
    end

    for _, item in ipairs(interactables) do
        local px = (item.x - 1) * cellSize + 2
        local py = (item.y - 1) * cellSize - 14
        love.graphics.setColor(1, 1, 1)

        if item.kind == "mine" then
            local percent = 0
            if item.resourceLeft and item.resourceLeft > 0 then
                local total = 5
                percent = math.floor((item.resourceLeft / total) * 100)
            end
            local typeLabel = item.resourceType or "unknown"
            love.graphics.print(string.format("Mine:%d%% (%s)", percent, typeLabel), px, py)
        elseif item.kind == "box" then
            local total = item.capacity or 1
            local used = item.amount or 0
            local percent = math.floor((used / total) * 100)
            love.graphics.print(string.format("Box:%d%%", percent), px, py)
        else
            love.graphics.print(item.kind, px, py)
        end
    end

    love.graphics.setColor(0.2, 1, 0.3)
    for _, agent in ipairs(agents) do
        local px = (agent.renderX - 0.5) * cellSize
        local py = (agent.renderY - 0.5) * cellSize
        love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(agent.statusText, px - 10, py - 18)
        love.graphics.setColor(0.2, 1, 0.3)
    end

    camera:detach()

    -- UI in screen space
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

    -- Resource HUD panel
    if resources then
        resources:draw(10, 150)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Pan: WASD/Arrows, edge scroll, or middle mouse drag | Left-click: Place/Select | SPACE: Spawn Agent | 'C': Clear Walls", 20, 10)
end
