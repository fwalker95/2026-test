local AI = {}

local R = (love and love.math) or math

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

-- Work goals per role. Returns nil when there is nothing to do.
function AI.chooseTask(agent, interactables)
    if not interactables then return nil end

    local function mineReady(node)
        if not node or node.kind ~= "mine" then return false end
        if not node:canInteract(agent) then return false end
        if node.resourceLeft ~= nil and node.resourceLeft <= 0 then return false end
        return not node.claimedBy
    end

    local function storageReady(node)
        if not node or (node.kind ~= "box" and node.kind ~= "storage") then return false end
        if not node:canInteract(agent) then return false end
        if node.capacity == nil then return true end
        return (node.amount or 0) < node.capacity
    end

    local function labReady(node)
        if not node or node.kind ~= "lab" then return false end
        if not node:canInteract(agent) then return false end
        return not node.claimedBy
    end

    if agent.role == "miner" then
        if agent.resourceHeld then
            local storage = nearestInteractable(agent, interactables, storageReady)
            if storage and storage:claim(agent) then
                return { type = "deliver", label = "Delivering", target = storage, kind = storage.kind }
            end
        else
            local mine = nearestInteractable(agent, interactables, mineReady)
            if mine and mine:claim(agent) then
                return { type = "mine", label = "Mining", target = mine, kind = "mine" }
            end
        end

    elseif agent.role == "scientist" then
        local lab = nearestInteractable(agent, interactables, labReady)
        if lab and lab:claim(agent) then
            return { type = "research", label = "Researching", target = lab, kind = "lab" }
        end
    end

    return nil
end

-- Nearest other agent that is free to chat (not working, not already chatting).
function AI.findChatPartner(agent, allAgents, maxDist)
    maxDist = maxDist or 15
    local best, bestDist = nil, math.huge

    for _, other in ipairs(allAgents or {}) do
        if other ~= agent
            and not other.currentTask
            and not (other.idle and other.idle.type == "chat") then
            local d = manhattan(agent.x, agent.y, other.x, other.y)
            if d <= maxDist and d < bestDist then
                best, bestDist = other, d
            end
        end
    end

    return best
end

-- Idle goal: used only when there is no work. Weighted random pick.
function AI.chooseIdle(agent, allAgents)
    local partner = AI.findChatPartner(agent, allAgents)

    local options = {
        { type = "wander", weight = 5 },
        { type = "smoke", weight = 3 },
    }
    if partner then
        table.insert(options, { type = "chat", weight = 4, partner = partner })
    end

    local total = 0
    for _, o in ipairs(options) do total = total + o.weight end

    local roll = R.random() * total
    for _, o in ipairs(options) do
        roll = roll - o.weight
        if roll <= 0 then return o end
    end

    return options[1]
end

return AI
