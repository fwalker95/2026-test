local Pathfinding = require("pathfinding")

local AI = {}

local function manhattan(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

local function nearestInteractable(agent, interactables, predicate)
    if not interactables or #interactables == 0 then return nil end

    local best = nil
    local bestDist = math.huge

    for _, node in ipairs(interactables) do
        if node and predicate(node) then
            local d = manhattan(agent.x, agent.y, node.x, node.y)
            if d < bestDist then
                bestDist = d
                best = node
            end
        end
    end

    return best
end

function AI.chooseTask(agent, interactables)
    if not interactables then return nil end

    local function mineReady(node)
        if not node or node.kind ~= "mine" then return false end
        if not node:canInteract(agent) then return false end
        if node.resourceLeft ~= nil and node.resourceLeft <= 0 then return false end
        return not node.claimedBy
    end

    local function storageReady(node)
        if not node or node.kind ~= "box" and node.kind ~= "storage" then return false end
        if not node:canInteract(agent) then return false end
        if node.capacity == nil then return true end
        return (node.amount or 0) < node.capacity
    end

    if agent.role == "miner" then
        if agent.resourceHeld then
            local storage = nearestInteractable(agent, interactables, storageReady)
            if storage then
                if storage:claim(agent) then
                    return {
                        type = "deliver",
                        label = "Delivering",
                        target = storage,
                        kind = storage.kind,
                    }
                end
            end
        else
            local mine = nearestInteractable(agent, interactables, mineReady)
            if mine then
                if mine:claim(agent) then
                    return {
                        type = "mine",
                        label = "Mining",
                        target = mine,
                        kind = "mine",
                    }
                end
            end
        end
    end

    return nil
end

return AI
