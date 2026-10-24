-- asset_manager.lua
local AssetManager = {}
AssetManager.__index = AssetManager

local function clamp(v, min, max)
    if v < min then return min end
    if v > max then return max end
    return v
end

function AssetManager.new()
    local self = setmetatable({}, AssetManager)
    self.images = {}
    return self
end

function AssetManager:loadImage(key, path)
    if not path then return nil end

    local ok, image = pcall(function()
        return love.graphics.newImage(path)
    end)

    if not ok then
        return nil
    end

    self.images[key] = image
    return image
end

function AssetManager:get(key)
    return self.images[key]
end

function AssetManager:assign(key, object)
    if not object then return nil end
    object.image = self.images[key]
    object.imageKey = key
    return object
end

function AssetManager:drawTile(image, x, y, cellSize, color)
    local px = (x - 1) * cellSize
    local py = (y - 1) * cellSize

    if image then
        local iw = image:getWidth()
        local ih = image:getHeight()
        local scale = clamp(cellSize / math.max(iw, 1), 0.2, 3)
        local drawX = px + (cellSize - iw * scale) * 0.5
        local drawY = py + (cellSize - ih * scale) * 0.5
        love.graphics.draw(image, drawX, drawY, 0, scale, scale)
        return true
    end

    if color then
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
        love.graphics.rectangle("fill", px, py, cellSize - 1, cellSize - 1)
    end
    return false
end

function AssetManager:drawObject(object, x, y, cellSize, fallbackColor)
    if not object then return end
    if object.image then
        self:drawTile(object.image, x, y, cellSize)
        return
    end

    if fallbackColor then
        self:drawTile(nil, x, y, cellSize, fallbackColor)
    end
end

return AssetManager
