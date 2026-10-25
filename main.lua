-- main.lua
local Agent = require("agent")
local Interactable = require("interactable")
local Camera = require("camera")
local Resources = require("resources")
local AssetManager = require("asset_manager")
local LabSphere = require("lab_sphere")
local json = require("json")

local kindImageKeys = { mine = "resource", box = "box", lab = "lab", gene_bank = "box" }

-- boxes can be used by miners (deliver) and scientists (take biomass)
local BOX_ROLES = { "miner", "scientist" }

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
            local holding = (agent.resourceHeld or agent.hasBiomass or agent.carriedDNASample) and "yes" or "no"
            local carried = agent.carriedType
                or (agent.hasBiomass and "biomass")
                or (agent.carriedDNASample and "dna_signature")
                or "none"
            local label = string.format("%d [%s]: (%d,%d) %s hold=%s carry=%s", i, agent.role, agent.x, agent.y, status, holding, carried)
            table.insert(self.items, { label = label, callback = function() end })
        end
    end
    return m
end

local TOP_BAR_H = 40
local PANEL_Y = 44

local buyItems = {
    assets = {
        { name = "resource", label = "Resource Node" },
        { name = "box", label = "Storage Box" },
        { name = "lab", label = "Lab" },
        { name = "gene_bank", label = "Gene Bank" },
    },
    workers = {
        { name = "agent_miner", label = "Miner" },
        { name = "agent_scientist", label = "Scientist" },
    },
}

local toolLabels = { erase = "Erase" }
for _, list in pairs(buyItems) do
    for _, item in ipairs(list) do toolLabels[item.name] = item.label end
end

local buyRect = { x = 10, y = PANEL_Y, w = 260, h = 190 }
local appendixRect = { x = 10, y = PANEL_Y, w = 720, h = 480 }

local function buyTabRects()
    return {
        assets = { x = buyRect.x + 10, y = buyRect.y + 10, w = 115, h = 26 },
        workers = { x = buyRect.x + 135, y = buyRect.y + 10, w = 115, h = 26 },
    }
end

local function buyItemRect(i)
    return { x = buyRect.x + 10, y = buyRect.y + 46 + (i - 1) * 34, w = buyRect.w - 20, h = 28 }
end

local function appendixListRect(i)
    return { x = appendixRect.x + 10, y = appendixRect.y + 40 + (i - 1) * 28, w = 170, h = 24 }
end

local function closePanels()
    buyOpen = false
    agentMenu.visible = false
    appendixOpen = false
end

local function loadCreatureData()
    local ok, data = pcall(function()
        local contents = love.filesystem.read("creatures.json")
        return json.decode(contents)
    end)
    if ok and type(data) == "table" then return data end
    return { creatures = {}, clusters = {}, trait_strength_thresholds = {} }
end

local function strengthLabel(level)
    local best, bestVal = nil, nil
    for name, threshold in pairs(creatureData.trait_strength_thresholds or {}) do
        if type(threshold) == "number" and type(level) == "number" and level >= threshold
            and (bestVal == nil or threshold > bestVal) then
            best, bestVal = name, threshold
        end
    end
    return best
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

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
            allowedRoles = BOX_ROLES,
            capacity = 10,
            amount = 0,
            interactionTime = 1.0,
        }))
    elseif selectedTool == "lab" then
        table.insert(interactables, Interactable.new("lab", cx, cy, {
            allowedRoles = { "scientist" },
            interactionTime = 3.0,
        }))
    elseif selectedTool == "gene_bank" then
        table.insert(interactables, Interactable.new("gene_bank", cx, cy, {
            allowedRoles = { "scientist" },
            capacity = 100,
            amount = 0,
            interactionTime = 1.0,
        }))
    end
    resources:recount(interactables)
end

-- Lab menu (full-window screen with tabs)
local function currentSample()
    if not selectedLab or #selectedLab.samples == 0 then return nil end
    labSampleIndex = math.max(1, math.min(labSampleIndex, #selectedLab.samples))
    return selectedLab.samples[labSampleIndex]
end

local function closeLabMenu()
    labMenuOpen = false
    selectedLab = nil
end

local function openLabMenu(lab)
    selectedLab = lab
    labMenuOpen = true
    labTab = "sequencer"
    labSampleIndex = math.max(1, #lab.samples)
end

local function stepSample(delta)
    if not selectedLab or #selectedLab.samples == 0 then return end
    labSampleIndex = ((labSampleIndex - 1 + delta) % #selectedLab.samples) + 1
end

local function labCloseButtonRect()
    local w = love.graphics.getWidth()
    return { x = w - 56, y = 16, w = 40, h = 40 }
end

local function labTabRects()
    return {
        sequencer = { x = 24, y = 90, w = 160, h = 32, label = "Sequencer" },
        useful = { x = 194, y = 90, w = 180, h = 32, label = "Useful Samples" },
        waste = { x = 384, y = 90, w = 170, h = 32, label = "Genetic Waste" },
    }
end

local function labPrevRect() return { x = 580, y = 90, w = 36, h = 32 } end
local function labNextRect() return { x = 740, y = 90, w = 36, h = 32 } end

local function inRect(r, x, y)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function hitLabAtCell(cx, cy)
    for _, item in ipairs(interactables) do
        if item.kind == "lab" and item.x == cx and item.y == cy then
            return item
        end
    end
    return nil
end

local topButtons = {}

local function handleUI(x, y, onPress)
    -- 1. top bar
    if y <= TOP_BAR_H then
        if onPress then
            for _, b in ipairs(topButtons) do
                if b:contains(x, y) then b.onClick() break end
            end
        end
        return true
    end

    -- 2. buy panel
    if buyOpen and inRect(buyRect, x, y) then
        if onPress then
            for name, r in pairs(buyTabRects()) do
                if inRect(r, x, y) then buyTab = name return true end
            end
            for i, item in ipairs(buyItems[buyTab]) do
                if inRect(buyItemRect(i), x, y) then
                    selectedTool = item.name
                    buyOpen = false
                    return true
                end
            end
        end
        return true
    end

    -- 3. agent menu
    if agentMenu.visible and agentMenu:contains(x, y) then
        if onPress then agentMenu:click(x, y) end
        return true
    end

    -- 4. appendix menu
    if appendixOpen and inRect(appendixRect, x, y) then
        if onPress then
            for i in ipairs(creatureData.creatures or {}) do
                if inRect(appendixListRect(i), x, y) then selectedCreature = i return true end
            end
        end
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
        Interactable.new("box", 20, 15, { allowedRoles = BOX_ROLES, capacity = 10, amount = 0, interactionTime = 1.0 }),
        Interactable.new("lab", 20, 22, { allowedRoles = { "scientist" }, interactionTime = 3.0 }),
        Interactable.new("gene_bank", 24, 22, { allowedRoles = { "scientist" }, capacity = 100, amount = 0, interactionTime = 1.0 }),
    }

    resources = Resources.new()
    resources:recount(interactables)

    assets = AssetManager.new()

    agents = {}
    spawnAgent(10, 15, "miner")
    spawnAgent(12, 17, "miner")
    spawnAgent(14, 19, "scientist")

    selectedTool = "resource"
    buyOpen = false
    buyTab = "assets"
    appendixOpen = false
    selectedCreature = 1
    creatureData = loadCreatureData()

    agentMenu = AgentListMenu:new(10, PANEL_Y, 460)
    agentMenu:refresh(agents)

    local function toggle(which)
        local wasOpen = (which == "buy" and buyOpen) or (which == "agents" and agentMenu.visible)
            or (which == "appendix" and appendixOpen)
        closePanels()
        if not wasOpen then
            if which == "buy" then buyOpen = true
            elseif which == "agents" then agentMenu.visible = true
            else appendixOpen = true end
        end
    end

    topButtons = {
        UIButton:new(10, 4, 80, 32, "Buy", function() toggle("buy") end),
        UIButton:new(100, 4, 80, 32, "Agents", function() toggle("agents") end),
        UIButton:new(190, 4, 80, 32, "Erase", function()
            selectedTool = (selectedTool == "erase") and "resource" or "erase"
        end),
        UIButton:new(280, 4, 90, 32, "Appendix", function() toggle("appendix") end),
    }

    labSphere = LabSphere.new({ baseColor = { 0.35, 0.75, 1.0 }, spinSpeed = 1.2, tilt = 0.4 })
    labMenuOpen = false
    labTab = "sequencer"
    labSampleIndex = 1
    selectedLab = nil

    local worldW = cols * cellSize
    local worldH = rows * cellSize
    camera = Camera.new(worldW, worldH, { speed = 700, edgeSize = 18, edgeScroll = true })
end

function love.update(dt)
    if labMenuOpen then
        labSphere:update(dt)
    else
        camera:update(dt)
    end

    agentMenu:refresh(agents)

    if not labMenuOpen and love.mouse.isDown(1) then
        local mx, my = love.mouse.getPosition()
        if not handleUI(mx, my, false) and not isAgentTool(selectedTool) then
            local cx, cy = camera:screenToCell(mx, my, cellSize)
            placeAt(cx, cy, false)
        end
    end

    -- simulation keeps running in the background
    for _, agent in ipairs(agents) do
        agent:update(dt, cols, rows, grid, interactables, agents)
    end

    resources:recount(interactables)
end

function love.keypressed(key)
    if labMenuOpen then
        if key == "escape" then closeLabMenu() end
        if key == "1" then labTab = "sequencer" end
        if key == "2" then labTab = "useful" end
        if key == "3" then labTab = "waste" end
        if labTab == "sequencer" then
            if key == "left" then stepSample(-1) end
            if key == "right" then stepSample(1) end
        end
        return
    end

    if key == "space" then
        local mx, my = love.mouse.getPosition()
        local cx, cy = camera:screenToCell(mx, my, cellSize)
        if cx >= 1 and cx <= cols and cy >= 1 and cy <= rows and not isCellOccupied(cx, cy) then
            spawnAgent(cx, cy, "miner")
        end
    end

    if key == "c" then
        for x = 1, cols do
            for y = 1, rows do grid[x][y] = 0 end
        end
    end
end

function love.mousepressed(x, y, button)
    if labMenuOpen then
        if button == 1 then
            if inRect(labCloseButtonRect(), x, y) then
                closeLabMenu()
                return
            end
            for name, r in pairs(labTabRects()) do
                if inRect(r, x, y) then labTab = name return end
            end
            if labTab == "sequencer" then
                if inRect(labPrevRect(), x, y) then stepSample(-1) end
                if inRect(labNextRect(), x, y) then stepSample(1) end
            end
        end
        return
    end

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
    if labMenuOpen then return end
    camera:mousereleased(x, y, button)
end

local function drawLabButton(r, label, active, hover)
    if active then
        love.graphics.setColor(0.25, 0.6, 0.9)
    elseif hover then
        love.graphics.setColor(0.25, 0.3, 0.4)
    else
        love.graphics.setColor(0.15, 0.18, 0.25)
    end
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(label, r.x + 12, r.y + 9)
end

local function drawLabScreen()
    local W, H = love.graphics.getWidth(), love.graphics.getHeight()
    local mx, my = love.mouse.getPosition()

    -- full-window background
    love.graphics.setColor(0.03, 0.05, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- title
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("LAB", 24, 24, 0, 2, 2)
    if selectedLab then
        love.graphics.setColor(0.7, 0.85, 1.0)
        love.graphics.print(string.format("Lab @ (%d,%d)   Research completed: %d   Active samples: %d", selectedLab.x, selectedLab.y, selectedLab.researchCount or 0, #selectedLab.samples), 24, 58)
    end

    -- tabs
    for name, r in pairs(labTabRects()) do
        drawLabButton(r, r.label, labTab == name, inRect(r, mx, my))
    end

    -- tab content
    local contentY = 140
    local contentH = H - contentY - 60

    if labTab == "sequencer" then
        local sample = currentSample()

        local pr, nr = labPrevRect(), labNextRect()
        drawLabButton(pr, "<", false, inRect(pr, mx, my))
        drawLabButton(nr, ">", false, inRect(nr, mx, my))
        love.graphics.setColor(1, 1, 1)
        local total = selectedLab and #selectedLab.samples or 0
        love.graphics.print(string.format("Sample %d / %d", sample and labSampleIndex or 0, total), 632, 99)

        if not sample then
            love.graphics.setColor(0.7, 0.8, 0.9)
            love.graphics.print("No active samples. Scientist must bring 1 biomass from storage before lab work.", 24, contentY + 20)
        else
            sample:draw(24, contentY, W - 48, contentH)
            local s = sample:stats()
            love.graphics.setColor(0.85, 0.9, 1.0)
            love.graphics.print(string.format("Mixed soup visible. Remaining bases: %d   Extracted: %d   Attempts: %d   Successes: %d",
                s.remaining, s.removed, s.attempts, s.successes), 24, H - 52)
            love.graphics.setColor(1.0, 0.85, 0.5)
            love.graphics.print(sample.lastLog or "", 24, H - 32)
        end
    elseif labTab == "useful" then
        love.graphics.setColor(0.8, 0.95, 0.8)
        love.graphics.print("Useful Samples", 24, contentY)
        local list = (selectedLab and selectedLab.usefulSamples) or {}
        if #list == 0 then
            love.graphics.setColor(0.7, 0.8, 0.9)
            love.graphics.print("No extracted useful sequences yet.", 24, contentY + 26)
        else
            local y = contentY + 26
            for i = #list, 1, -1 do
                local e = list[i]
                love.graphics.setColor(0.9, 1.0, 0.9)
                love.graphics.print(string.format("#%d [%s %d] skill=%.2f len=%d seq=%s", i, e.kind or "row", e.index or 0, e.skill or 0, #(e.sequence or ""), e.sequence or ""), 24, y)
                y = y + 20
                if y > H - 40 then break end
            end
        end
    else
        love.graphics.setColor(1.0, 0.8, 0.8)
        love.graphics.print("Genetic Waste", 24, contentY)
        local list = (selectedLab and selectedLab.geneticWaste) or {}
        if #list == 0 then
            love.graphics.setColor(0.7, 0.8, 0.9)
            love.graphics.print("No discarded samples yet.", 24, contentY + 26)
        else
            local y = contentY + 26
            for i = #list, 1, -1 do
                local e = list[i]
                love.graphics.setColor(1.0, 0.9, 0.9)
                love.graphics.print(string.format("Waste #%d reason=%s remaining=%d", i, e.reason or "n/a", e.sample and e.sample:countAvailable() or 0), 24, y)
                y = y + 20
                if y > H - 40 then break end
            end
        end
    end

    love.graphics.setColor(0.7, 0.8, 0.9)
    love.graphics.print(string.format("Biomass in storage: %d", resources:get("biomass")), 24, H - 22)

    -- X close button (top-right)
    local r = labCloseButtonRect()
    local hover = inRect(r, mx, my)
    love.graphics.setColor(hover and 0.9 or 0.65, hover and 0.2 or 0.15, hover and 0.2 or 0.15)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(3)
    love.graphics.line(r.x + 11, r.y + 11, r.x + r.w - 11, r.y + r.h - 11)
    love.graphics.line(r.x + r.w - 11, r.y + 11, r.x + 11, r.y + r.h - 11)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(0.6, 0.7, 0.8)
    love.graphics.print("1/2/3: tabs   Left/Right: sample   ESC or X: close", W - 420, H - 22)
end

function love.draw()
    if labMenuOpen then
        drawLabScreen()
        return
    end

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
        elseif item.kind == "gene_bank" then
            local dnaCount = (item.contents and item.contents.dna) or 0
            local sigs = #(item.dnaSignatures or {})
            love.graphics.print(string.format("GeneBank DNA:%d sig:%d", dnaCount, sigs), px, py)
        elseif item.kind == "lab" then
            love.graphics.print(string.format("lab (active:%d useful:%d waste:%d)", #item.samples, #(item.usefulSamples or {}), #(item.geneticWaste or {})), px, py)
        else
            love.graphics.print(item.kind, px, py)
        end
    end

    for _, agent in ipairs(agents) do
        agent:draw(cellSize)
    end

    camera:detach()

    local W = love.graphics.getWidth()
    love.graphics.setColor(0.1, 0.1, 0.14, 0.95)
    love.graphics.rectangle("fill", 0, 0, W, TOP_BAR_H)
    topButtons[1].selected = buyOpen
    topButtons[2].selected = agentMenu.visible
    topButtons[3].selected = selectedTool == "erase"
    topButtons[4].selected = appendixOpen
    for _, b in ipairs(topButtons) do b:draw() end
    if selectedTool == "erase" then
        love.graphics.setColor(1, 0.3, 0.3)
        love.graphics.rectangle("line", 190, 4, 80, 32)
        love.graphics.print("ERASE MODE", 380, 13)
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Selected: " .. (toolLabels[selectedTool] or tostring(selectedTool)), 380, 13)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Pan: WASD/Arrows, edge scroll, or middle mouse drag | Left-click: Place / open Lab", 560, 13)

    if buyOpen then
        love.graphics.setColor(0.12, 0.12, 0.15, 0.95)
        love.graphics.rectangle("fill", buyRect.x, buyRect.y, buyRect.w, buyRect.h)
        for name, r in pairs(buyTabRects()) do
            love.graphics.setColor(buyTab == name and 0.3 or 0.22, buyTab == name and 0.75 or 0.22, buyTab == name and 0.95 or 0.28)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(name == "assets" and "Assets" or "Workers", r.x + 10, r.y + 6)
        end
        for i, item in ipairs(buyItems[buyTab]) do
            local r = buyItemRect(i)
            local sel = selectedTool == item.name
            love.graphics.setColor(sel and 0.35 or 0.2, sel and 0.9 or 0.5, sel and 0.35 or 0.6)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(item.label, r.x + 10, r.y + 8)
        end
    end

    agentMenu:draw()

    if appendixOpen then
        local R = appendixRect
        love.graphics.setColor(0.12, 0.12, 0.15, 0.97)
        love.graphics.rectangle("fill", R.x, R.y, R.w, R.h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Creature Appendix", R.x + 10, R.y + 10)
        local creatures = creatureData.creatures or {}
        for i, c in ipairs(creatures) do
            local r = appendixListRect(i)
            love.graphics.setColor(i == selectedCreature and 0.3 or 0.22, i == selectedCreature and 0.75 or 0.22, i == selectedCreature and 0.95 or 0.28)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(c.name or c.id or "?", r.x + 8, r.y + 5)
        end
        local c = creatures[selectedCreature]
        local dx, dy = R.x + 200, R.y + 40
        local function line(text, color)
            love.graphics.setColor(color or { 1, 1, 1 })
            love.graphics.printf(text, dx, dy, R.w - 215)
            local _, wrapped = love.graphics.getFont():getWrap(text, R.w - 215)
            dy = dy + 16 * math.max(1, #wrapped)
        end
        if c then
            line(string.format("%s (%s)", c.name or "?", c.id or "?"), { 1, 0.9, 0.4 })
            if c.is_fallback then line("Fallback creature", { 1, 0.6, 0.3 }) end
            line("Description: " .. (c.description or ""))
            line("Tolerance: " .. tostring(c.tolerance or "-"))
            dy = dy + 6
            line("Profile:", { 0.5, 0.9, 1 })
            local keys = sortedKeys(c.profile)
            if #keys == 0 then line("  (none)", { 0.7, 0.7, 0.7 }) end
            for _, key in ipairs(keys) do
                local p = c.profile[key]
                local cl = (creatureData.clusters or {})[key]
                local text = string.format("  %s: level %s", key, tostring(p.level))
                local strength = strengthLabel(p.level)
                if strength then text = text .. " (" .. strength .. ")" end
                text = text .. string.format(", weight %s%s", tostring(p.weight), p.core and ", core" or "")
                if cl then
                    text = text .. string.format(" - %s [%s] trait: %s, genes: %s",
                        tostring(cl.name or key), tostring(cl.prefix or "?"), tostring(cl.trait or "?"), tostring(cl.gene_count or "?"))
                end
                line(text)
            end
            dy = dy + 6
            line("Forbidden:", { 1, 0.5, 0.5 })
            local forbidden = c.forbidden or {}
            if #forbidden == 0 then line("  (none)", { 0.7, 0.7, 0.7 }) end
            for _, key in ipairs(forbidden) do
                local cl = (creatureData.clusters or {})[key]
                line("  " .. key .. (cl and cl.name and (" - " .. cl.name) or ""))
            end
        end
    end

    resources:draw(W - 200, 50)
end
