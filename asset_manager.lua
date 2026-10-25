-- asset_manager.lua
local AssetManager = {}
AssetManager.__index = AssetManager

function AssetManager.new()
    local self = setmetatable({}, AssetManager)
    self.images = {}

    -- Centralized image path registry
    self:loadImage("agent", "assets/agent.png")          -- generic fallback
    self:loadImage("miner", "assets/miner.png")
    self:loadImage("scientist", "assets/scientist.png")
    self:loadImage("resource", "assets/resource.png")
    self:loadImage("box", "assets/box.png")
    self:loadImage("lab", "assets/lab.png")
    self:loadImage("wall", "assets/wall.png")
    self:loadImage("ground", "assets/ground.png")

    return self
end

function AssetManager:loadImage(key, path)
    local ok, image = pcall(function()
        return love.graphics.newImage(path)
    end)

    if not ok then
        print("AssetManager: failed to load image '" .. tostring(path) .. "': " .. tostring(image))
        return nil
    end

    self.images[key] = image
    return image
end

function AssetManager:get(key)
    return self.images[key]
end

function AssetManager:assignImage(object, key)
    if not object then return nil end
    object.image = self.images[key]
    object.imageKey = key
    return object
end

-- Uses assets/<role>.png, falls back to assets/agent.png
function AssetManager:assignAgent(agent)
    if not agent then return nil end
    local key = agent.role
    if not self.images[key] then key = "agent" end
    return self:assignImage(agent, key)
end

function AssetManager:assignAll(world)
    if not world then return end

    for _, agent in ipairs(world.agents or {}) do
        self:assignAgent(agent)
    end

    for _, node in ipairs(world.resourceNodes or {}) do
        self:assignImage(node, "resource")
    end

    for _, box in ipairs(world.boxNodes or {}) do
        self:assignImage(box, "box")
    end

    for _, wall in ipairs(world.walls or {}) do
        self:assignImage(wall, "wall")
    end
end

return AssetManager
