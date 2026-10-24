local Pathfinding = {}

local function cellKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function manhattan(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
end

function Pathfinding.isWalkable(grid, cols, rows, x, y)
    if not x or not y then return false end
    if x < 1 or x > cols or y < 1 or y > rows then return false end

    if grid and grid[x] then
        local cell = grid[x][y]
        if cell == 1 or cell == true or cell == "wall" then
            return false
        end
    end

    return true
end

function Pathfinding.cellKey(x, y)
    return cellKey(x, y)
end

function Pathfinding.findPath(grid, cols, rows, startX, startY, goalX, goalY)
    if startX == goalX and startY == goalY then
        return {}
    end

    if not Pathfinding.isWalkable(grid, cols, rows, goalX, goalY) then
        local bestAdjX, bestAdjY = nil, nil
        local bestDist = math.huge
        local neighbors = { {0, 1}, {0, -1}, {1, 0}, {-1, 0} }

        for _, n in ipairs(neighbors) do
            local nx, ny = goalX + n[1], goalY + n[2]
            if Pathfinding.isWalkable(grid, cols, rows, nx, ny) then
                local d = manhattan(startX, startY, nx, ny)
                if d < bestDist then
                    bestDist = d
                    bestAdjX, bestAdjY = nx, ny
                end
            end
        end

        if not bestAdjX then return nil end
        goalX, goalY = bestAdjX, bestAdjY

        if startX == goalX and startY == goalY then
            return {}
        end
    end

    local function posKey(x, y)
        return tostring(x) .. "," .. tostring(y)
    end

    local openSet = {
        { x = startX, y = startY, f = manhattan(startX, startY, goalX, goalY) }
    }
    local cameFrom = {}
    local gScore = { [posKey(startX, startY)] = 0 }
    local inOpen = { [posKey(startX, startY)] = true }

    local dirs = { {0, 1}, {0, -1}, {1, 0}, {-1, 0} }
    local maxSteps = cols * rows * 2
    local steps = 0

    while #openSet > 0 and steps < maxSteps do
        steps = steps + 1
        local bestIdx = 1
        local lowestF = openSet[1].f

        for i = 2, #openSet do
            if openSet[i].f < lowestF then
                lowestF = openSet[i].f
                bestIdx = i
            end
        end

        local current = table.remove(openSet, bestIdx)
        inOpen[posKey(current.x, current.y)] = nil

        if current.x == goalX and current.y == goalY then
            local path = {}
            local currKey = posKey(goalX, goalY)

            while cameFrom[currKey] do
                local prev = cameFrom[currKey]
                table.insert(path, 1, { x = current.x, y = current.y })
                current = prev
                currKey = posKey(current.x, current.y)
            end

            return path
        end

        local currentG = gScore[posKey(current.x, current.y)] or math.huge

        for _, d in ipairs(dirs) do
            local nx, ny = current.x + d[1], current.y + d[2]
            if Pathfinding.isWalkable(grid, cols, rows, nx, ny) then
                local tentativeG = currentG + 1
                local nKey = posKey(nx, ny)

                if tentativeG < (gScore[nKey] or math.huge) then
                    cameFrom[nKey] = { x = current.x, y = current.y }
                    gScore[nKey] = tentativeG

                    local fScore = tentativeG + manhattan(nx, ny, goalX, goalY)
                    if not inOpen[nKey] then
                        table.insert(openSet, { x = nx, y = ny, f = fScore })
                        inOpen[nKey] = true
                    end
                end
            end
        end
    end

    return nil
end

function Pathfinding.buildReservationMap(agents, ignoreAgent)
    local reservations = {}
    if not agents then return reservations end

    for _, other in ipairs(agents) do
        if other ~= ignoreAgent then
            local reservedCell = other._reservedCell or { x = other.x, y = other.y }
            if reservedCell and reservedCell.x and reservedCell.y then
                reservations[cellKey(reservedCell.x, reservedCell.y)] = true
            end
        end
    end

    return reservations
end

function Pathfinding.findBestAlternativeStep(agent, grid, cols, rows, goalX, goalY, reservations)
    local best = nil
    local bestScore = math.huge

    local options = {
        {0, 1}, {0, -1}, {1, 0}, {-1, 0},
        {1, 1}, {-1, 1}, {1, -1}, {-1, -1},
        {2, 0}, {-2, 0}, {0, 2}, {0, -2},
        {1, 2}, {-1, 2}, {1, -2}, {-1, -2},
        {2, 1}, {2, -1}, {-2, 1}, {-2, -1}
    }

    for _, dir in ipairs(options) do
        local nx, ny = agent.x + dir[1], agent.y + dir[2]
        local key = cellKey(nx, ny)

        if Pathfinding.isWalkable(grid, cols, rows, nx, ny) and not reservations[key] then
            local score = manhattan(nx, ny, goalX, goalY)
            score = score + (math.abs(nx - agent.x) + math.abs(ny - agent.y)) * 0.85

            if score < bestScore then
                bestScore = score
                best = { x = nx, y = ny }
            end
        end
    end

    return best
end

function Pathfinding.findBestLegalWorkTile(agent, target, grid, cols, rows, reservations)
    if not target then return nil end

    local tiles = target.getWorkTiles and target:getWorkTiles() or { { x = target.x, y = target.y } }
    local best = nil
    local bestScore = math.huge

    for _, tile in ipairs(tiles) do
        local key = cellKey(tile.x, tile.y)

        if Pathfinding.isWalkable(grid, cols, rows, tile.x, tile.y) and not reservations[key] then
            local score = manhattan(agent.x, agent.y, tile.x, tile.y)
            score = score + manhattan(tile.x, tile.y, target.x, target.y) * 0.25

            if score < bestScore then
                bestScore = score
                best = tile
            end
        end
    end

    if best then return best end

    return nil
end

return Pathfinding
