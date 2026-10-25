-- world.lua
local Agent = require("agent")
local Interactable = require("interactable")

local World = {}

function World.new()
    local world = {
        cols = 80,
        rows = 60,
        cellSize = 20,
    }

    world.grid = {}
    for x = 1, world.cols do
        world.grid[x] = {}
        for y = 1, world.rows do world.grid[x][y] = 0 end
    end

    world.interactables = {
        Interactable.new("mine", 30, 15, { allowedRoles = { "miner" }, resourceLeft = 5, interactionTime = 1.5 }),
        Interactable.new("mine", 27, 20, { allowedRoles = { "miner" }, resourceLeft = 5, interactionTime = 1.5 }),
        Interactable.new("box", 20, 15, { allowedRoles = { "miner" }, capacity = 10, amount = 0, interactionTime = 1.0 }),
    }

    world.agents = {}
    table.insert(world.agents, Agent.new(10, 15, "miner"))
    table.insert(world.agents, Agent.new(12, 17, "miner"))

    return world
end

function World.update(world, dt)
    for _, agent in ipairs(world.agents) do
        agent:update(dt, world.cols, world.rows, world.grid, world.interactables, world.agents)
    end
end

function World.inBounds(world, cx, cy)
    return cx >= 1 and cx <= world.cols and cy >= 1 and cy <= world.rows
end

local function agentAt(world, cx, cy)
    for _, agent in ipairs(world.agents) do
        if agent.x == cx and agent.y == cy then return true end
    end
    return false
end

local function interactableAt(world, cx, cy)
    for _, item in ipairs(world.interactables) do
        if item.x == cx and item.y == cy then return true end
    end
    return false
end

function World.applyTool(world, tool, cx, cy)
    if not World.inBounds(world, cx, cy) then return end

    if tool == "erase" then
        world.grid[cx][cy] = 0
        for i = #world.interactables, 1, -1 do
            local item = world.interactables[i]
            if item.x == cx and item.y == cy then
                table.remove(world.interactables, i)
            end
        end
        return
    end

    if interactableAt(world, cx, cy) or agentAt(world, cx, cy) then return end

    if tool == "resource" then
        table.insert(world.interactables, Interactable.new("mine", cx, cy, {
            allowedRoles = { "miner" },
            resourceLeft = 5,
            interactionTime = 1.5,
        }))
    elseif tool == "box" then
        table.insert(world.interactables, Interactable.new("box", cx, cy, {
            allowedRoles = { "miner" },
            capacity = 10,
            amount = 0,
            interactionTime = 1.0,
        }))
    end
end

function World.spawnAgent(world, cx, cy)
    if not World.inBounds(world, cx, cy) then return end
    if agentAt(world, cx, cy) then return end
    table.insert(world.agents, Agent.new(cx, cy, "miner"))
end

function World.clearGrid(world)
    for x = 1, world.cols do
        for y = 1, world.rows do world.grid[x][y] = 0 end
    end
end

-- Draws world content; caller is responsible for camera attach/detach.
function World.draw(world, x1, y1, x2, y2)
    local cellSize = world.cellSize

    for x = x1, x2 do
        for y = y1, y2 do
            local px, py = (x - 1) * cellSize, (y - 1) * cellSize

            if interactableAt(world, x, y) then
                love.graphics.setColor(0.25, 0.25, 0.25)
            elseif world.grid[x][y] == 1 then
                love.graphics.setColor(0.3, 0.3, 0.3)
            else
                love.graphics.setColor(0.12, 0.12, 0.12)
            end

            love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        end
    end

    for _, item in ipairs(world.interactables) do
        local px = (item.x - 1) * cellSize + 2
        local py = (item.y - 1) * cellSize - 14
        love.graphics.setColor(1, 1, 1)

        if item.kind == "mine" then
            local percent = 0
            if item.resourceLeft and item.resourceLeft > 0 then
                local total = 5
                percent = math.floor((item.resourceLeft / total) * 100)
            end
            love.graphics.print(string.format("Mine:%d%%", percent), px, py)
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
    for _, agent in ipairs(world.agents) do
        local px = (agent.renderX - 0.5) * cellSize
        local py = (agent.renderY - 0.5) * cellSize
        love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(agent.statusText, px - 10, py - 18)
        love.graphics.setColor(0.2, 1, 0.3)
    end
end

return World
