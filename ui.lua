-- ui.lua

local UI = {}

local UIButton = {}
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

local Menu = {}
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

local AgentListMenu = setmetatable({}, { __index = Menu })

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

function UI.new(agents)
    local state = {}

    state.selectedTool = "resource"
    state.menuRect = { x = 10, y = 10, w = 150, h = 80 }

    state.agentMenu = AgentListMenu:new(190, 100, 360)
    state.agentMenu:refresh(agents)

    state.agentButton = UIButton:new(10, 100, 160, 28, "Agents", function()
        state.agentMenu.visible = not state.agentMenu.visible
    end)

    return state
end

function UI.update(state, agents)
    if state.agentMenu then
        state.agentMenu:refresh(agents)
    end
end

function UI.handleLeftClick(state, x, y, held)
    if state.agentButton:contains(x, y) then
        if not held then state.agentButton.onClick() end
        return true
    end

    if state.agentMenu.visible and state.agentMenu:click(x, y) then
        return true
    end

    local r = state.menuRect
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
        if y <= r.y + 30 then
            state.selectedTool = "resource"
        elseif y <= r.y + 60 then
            state.selectedTool = "box"
        else
            state.selectedTool = "erase"
        end
        return true
    end

    return false
end

function UI.draw(state)
    love.graphics.setColor(0.12, 0.12, 0.18, 0.9)
    love.graphics.rectangle("fill", state.menuRect.x, state.menuRect.y, state.menuRect.w, state.menuRect.h)

    local items = {
        { name = "resource", label = "Resource" },
        { name = "box", label = "Box" },
        { name = "erase", label = "Erase" }
    }

    for i, item in ipairs(items) do
        local y = state.menuRect.y + (i - 1) * 30
        local selected = state.selectedTool == item.name
        love.graphics.setColor(selected and 0.35 or 0.2, selected and 0.9 or 0.5, selected and 0.35 or 0.6)
        love.graphics.rectangle("fill", state.menuRect.x + 5, y + 5, state.menuRect.w - 10, 20)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.label, state.menuRect.x + 15, y + 8)
    end

    state.agentButton:draw()
    if state.agentMenu then
        state.agentMenu:draw()
    end
end

return UI
