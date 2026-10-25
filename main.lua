-- main.lua
local Agent = require("agent")
local Interactable = require("interactable")
local Camera = require("camera")
local Resources = require("resources")
local AssetManager = require("asset_manager")
local LabSphere = require("lab_sphere")

local kindImageKeys = { mine = "resource", box = "box", lab = "lab" }

local function drawImageInCell(image, px, py, size)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, px, py, 0, size / image:getWidth(), size / image:getHeight())
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

function Menu:addItem(label, callback, isSelected)
    table.insert(self.items, { label = label, callback = callback, isSelected = isSelected })
end

function Menu:contains(px, py)
    return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
end

function Menu:draw()
    if not self.visible then return end

    love.graphics.setColor(0.12, 0.12, 0.15, 0.95)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    for i, item in ipairs(self.items) do
        local iy = self.y + 10 + (i - 1) * 22
        if item.isSelected and item.isSelected() then
            love.graphics.setColor(0.35, 0.9, 0.35)
        else
            love.graphics.setColor(0.22, 0.22, 0.28)
        end
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
    m.contains = Menu.contains
    m.draw = Menu.draw
    m.click = Menu.click
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
            local label = string.format("%d [%s]: (%d,%d) %s hold=%s carry=%s", i, agent.role, agent.x, agent.y, status, holding, carried)
            table.insert(self.items, { label = label, callback = function() end })
        end
    end
    return m
end

local toolItems = {
    { name = "resource", label = "Resource" },
    { name = "box", label = "Box" },
    { name = "lab", label = "Lab" },
    { name = "erase", label = "Erase" },
}

local function isAgentTool(tool)
    return tool == "agent_miner" or tool == "agent_scientist"
end

local function isCellOccupied(cx, cy)
    for _, item in ipairs(interactables) do
        if item.x == cx and item.y == cy then return true end
    end
    for _, agent in ipairs(agents) do
        if agent.x == cx and agent.y == cy then return true end
    end
    return false
end

local function spawnAgent(cx, cy, role)
    local a = Agent.new(cx, cy, role)
    assets:assignAgent(a)
    table.insert(agents, a)
    return a
end

local function placeAt(cx, cy, pressed)
    if cx < 1 or cx > cols or cy < 1 or cy > rows then return end

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

    if isAgentTool(selectedTool) then
        if pressed and not isCellOccupied(cx, cy) then
            spawnAgent(cx, cy, selectedTool == "agent_scientist" and "scientist" or "miner")
        end
        return
    end

    if isCellOccupied(cx, cy) then return end

    if selectedTool == "resource" then
        table.insert(interactables, Interactable.new("mine", cx, cy, {
            allowedRoles = { "miner" },
            resourceLeft = 5,
            interactionTime = 1.5,
        }))
    elseif selectedTool == "box" then
        table.insert(interactables, Interactable.new("box", cx, cy, {
            allowedRoles = { "miner" },
            capacity = 10,
            amount = 0,
            interactionTime = 1.0,
        }))
    elseif selectedTool == "lab" then
        table.insert(interactables, Interactable.new("lab", cx, cy, {
            allowedRoles = { "scientist" },
            interactionTime = 3.0,
        }))
    end
    resources:recount(interactables)
end

local function closeLabMenu()
    labMenuOpen = false
    selectedLab = nil
end

local function openLabMenu(lab)
    selectedLab = lab
    labMenuOpen = true
end

local function hitLabAtCell(cx, cy)
    for _, item in ipairs(interactables) do
        if item.kind == "lab" and item.x == cx and item.y == cy then
            return item
        end
    end
    return nil
end

local function handleUI(x, y, onPress)
    if labMenuOpen then
        local insideLabPanel = (x >= labPanel.x and x <= labPanel.x + labPanel.w and y >= labPanel.y and y <= labPanel.y + labPanel.h)
        if insideLabPanel then
            return true
        end

        if onPress then
            closeLabMenu()
        end
        return true
    end

    if agentButton:contains(x, y) then
        if onPress then agentButton.onClick() end
        return true
    end

    if placeButton:contains(x, y) then
        if onPress then placeButton.onClick() end
        return true
    end

    if agentMenu.visible and agentMenu:contains(x, y) then
        if onPress then agentMenu:click(x, y) end
        return true
    end

    if placeMenu.visible and placeMenu:contains(x, y) then
        if onPress then placeMenu:click(x, y) end
        return true
    end

    if x >= menuRect.x and x <= menuRect.x + menuRect.w and y >= menuRect.y and y <= menuRect.y + menuRect.h then
        local idx = math.floor((y - menuRect.y) / 30) + 1
        if toolItems[idx] then selectedTool = toolItems[idx].name end
        return true
    end

    return false
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
        Interactable.new("lab", 20, 22, { allowedRoles = { "scientist" }, interactionTime = 3.0 }),
    }

    resources = Resources.new()
    resources:recount(interactables)

    assets = AssetManager.new()

    agents = {}
    spawnAgent(10, 15, "miner")
    spawnAgent(12, 17, "miner")
    spawnAgent(14, 19, "scientist")

    selectedTool = "resource"
    menuRect = { x = 10, y = 10, w = 150, h = #toolItems * 30 }

    agentButton = UIButton:new(10, 140, 160, 28, "Agents", function()
        agentMenu.visible = not agentMenu.visible
    end)

    placeButton = UIButton:new(10, 175, 160, 28, "Place Agent", function()
        placeMenu.visible = not placeMenu.visible
    end)

    agentMenu = AgentListMenu:new(190, 140, 460)
    agentMenu:refresh(agents)

    placeMenu = Menu:new(190, 175, 200, 70)
    placeMenu:addItem("Miner", function() selectedTool = "agent_miner" end, function() return selectedTool == "agent_miner" end)
    placeMenu:addItem("Scientist", function() selectedTool = "agent_scientist" end, function() return selectedTool == "agent_scientist" end)

    labSphere = LabSphere.new({ baseColor = { 0.35, 0.75, 1.0 }, spinSpeed = 1.2, tilt = 0.4 })
    labMenuOpen = false
    selectedLab = nil
    labPanel = { x = 780, y = 120, w = 360, h = 420 }

    local worldW = cols * cellSize
    local worldH = rows * cellSize
    camera = Camera.new(worldW, worldH, { speed = 700, edgeSize = 18, edgeScroll = true })
end

function love.update(dt)
    agentMenu:refresh(agents)
    camera:update(dt)

    if labMenuOpen then
        labSphere:update(dt)
    end

    if love.mouse.isDown(1) and not labMenuOpen then
        local mx, my = love.mouse.getPosition()
        if not handleUI(mx, my, false) and not isAgentTool(selectedTool) then
            local cx, cy = camera:screenToCell(mx, my, cellSize)
            placeAt(cx, cy, false)
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
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows and not isCellOccupied(cx, cy) then
            spawnAgent(cx, cy, "miner")
        end
    end

    if key == "n" and labMenuOpen then
        labSphere.showNormals = not labSphere.showNormals
    end

    if key == "escape" and labMenuOpen then
        closeLabMenu()
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

    if handleUI(x, y, true) then return end

    local cx, cy = camera:screenToCell(x, y, cellSize)
    local clickedLab = hitLabAtCell(cx, cy)
    if clickedLab then
        openLabMenu(clickedLab)
        return
    end

    placeAt(cx, cy, true)
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

            local tileImage = assets:get(grid[x][y] == 1 and "wall" or "ground")
            if tileImage and not isInteractable then
                drawImageInCell(tileImage, px, py, cellSize)
            else
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
    end

    for _, item in ipairs(interactables) do
        if not item.image and kindImageKeys[item.kind] then
            assets:assignImage(item, kindImageKeys[item.kind])
        end
        if item.image then
            drawImageInCell(item.image, (item.x - 1) * cellSize, (item.y - 1) * cellSize, cellSize)
        end

        local px = (item.x - 1) * cellSize + 2
        local py = (item.y - 1) * cellSize - 14
        love.graphics.setColor(1, 1, 1)

        if item.kind == "mine" then
            local percent = 0
            if item.resourceLeft and item.resourceLeft > 0 then
                percent = math.floor((item.resourceLeft / 5) * 100)
            end
            love.graphics.print(string.format("Mine:%d%% (%s)", percent, item.resourceType or "?"), px, py)
        elseif item.kind == "box" then
            local total = item.capacity or 1
            local used = item.amount or 0
            love.graphics.print(string.format("Box:%d%%", math.floor((used / total) * 100)), px, py)
        else
            love.graphics.print(item.kind, px, py)
        end
    end

    for _, agent in ipairs(agents) do
        agent:draw(cellSize)
    end

    camera:detach()

    love.graphics.setColor(0.12, 0.12, 0.18, 0.9)
    love.graphics.rectangle("fill", menuRect.x, menuRect.y, menuRect.w, menuRect.h)

    for i, item in ipairs(toolItems) do
        local y = menuRect.y + (i - 1) * 30
        local selected = selectedTool == item.name
        love.graphics.setColor(selected and 0.35 or 0.2, selected and 0.9 or 0.5, selected and 0.35 or 0.6)
        love.graphics.rectangle("fill", menuRect.x + 5, y + 5, menuRect.w - 10, 20)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.label, menuRect.x + 15, y + 8)
    end

    agentButton:draw()
    placeButton.selected = isAgentTool(selectedTool)
    placeButton:draw()
    agentMenu:draw()
    placeMenu:draw()

    resources:draw(10, 215)

    if labMenuOpen then
        love.graphics.setColor(0.05, 0.08, 0.12, 0.93)
        love.graphics.rectangle("fill", labPanel.x, labPanel.y, labPanel.w, labPanel.h, 8, 8)
        love.graphics.setColor(0.2, 0.7, 1.0)
        love.graphics.rectangle("line", labPanel.x, labPanel.y, labPanel.w, labPanel.h, 8, 8)

        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Lab Control", labPanel.x + 14, labPanel.y + 14)
        if selectedLab then
            love.graphics.print(string.format("Lab @ (%d,%d)", selectedLab.x, selectedLab.y), labPanel.x + 14, labPanel.y + 36)
        end

        local cx = labPanel.x + math.floor(labPanel.w * 0.5)
        local cy = labPanel.y + 215
        labSphere:draw(cx, cy, 110)

        love.graphics.setColor(0.8, 0.9, 1.0)
        love.graphics.print("N: toggle normal view", labPanel.x + 14, labPanel.y + labPanel.h - 46)
        love.graphics.print("ESC/click outside: close", labPanel.x + 14, labPanel.y + labPanel.h - 26)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Pan: WASD/Arrows, edge scroll, or middle mouse drag | Left-click: Place / open Lab menu", 180, 10)
end
