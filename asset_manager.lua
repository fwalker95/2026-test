-- asset_manager.lua
local AssetManager = {}
AssetManager.__index = AssetManager

function AssetManager.new()
    local self = setmetatable({}, AssetManager)
    self.images = {}

    -- Centralized image path registry
    self:loadImage("agent", "assets/agent.png")
    self:loadImage("resource", "assets/resource.png")
    self:loadImage("box", "assets/box.png")
    self:loadImage("wall", "assets/wall.png")
    self:loadImage("ground", "assets/ground.png")

    return self
end

function AssetManager:loadImage(key, path)
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

function AssetManager:assignImage(object, key)
    if not object then return nil end
    object.image = self.images[key]
    object.imageKey = key
    return object
end

function AssetManager:assignAll(world)
    if not world then return end

    for _, agent in ipairs(world.agents or {}) do
        self:assignImage(agent, "agent")
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
