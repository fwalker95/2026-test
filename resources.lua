-- resources.lua
-- Tracks all base resources, i.e. everything stored in boxes.
local Resources = {}
Resources.__index = Resources

-- Ordered list of resource types (key, display label, HUD color)
Resources.types = {
    { key = "biomass",    label = "Biomass",           color = { 0.4, 0.9, 0.3 } },
    { key = "funds",      label = "Funds",             color = { 1.0, 0.85, 0.3 } },
    { key = "volatile",   label = "Volatile Compounds", color = { 1.0, 0.5, 0.2 } },
    { key = "acids",      label = "Acids",             color = { 0.7, 1.0, 0.2 } },
    { key = "dna",        label = "DNA Samples",       color = { 0.5, 0.7, 1.0 } },
}

Resources.byKey = {}
for _, t in ipairs(Resources.types) do
    Resources.byKey[t.key] = t
end

function Resources.isValid(key)
    return Resources.byKey[key] ~= nil
end

function Resources.randomType()
    local rnd = (love and love.math) or math
    return Resources.types[rnd.random(1, #Resources.types)].key
end

function Resources.new()
    local self = setmetatable({}, Resources)
    self.totals = {}
    self:reset()
    return self
end

function Resources:reset()
    for _, t in ipairs(Resources.types) do
        self.totals[t.key] = 0
    end
end

-- Rebuild totals from the contents of every box/storage interactable.
-- Call once per frame (cheap) so erased/changed boxes are always reflected.
function Resources:recount(interactables)
    self:reset()
    for _, node in ipairs(interactables or {}) do
        if (node.kind == "box" or node.kind == "storage") and node.contents then
            for key, count in pairs(node.contents) do
                if self.totals[key] ~= nil then
                    self.totals[key] = self.totals[key] + count
                end
            end
        end
    end
end

function Resources:get(key)
    return self.totals[key] or 0
end

function Resources:getAll()
    local copy = {}
    for k, v in pairs(self.totals) do copy[k] = v end
    return copy
end

-- Screen-space HUD panel. Call after camera:detach().
function Resources:draw(x, y)
    local lineH = 20
    local w = 230
    local h = 12 + (#Resources.types + 1) * lineH

    love.graphics.setColor(0.12, 0.12, 0.18, 0.9)
    love.graphics.rectangle("fill", x, y, w, h)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Base Resources", x + 10, y + 6)

    for i, t in ipairs(Resources.types) do
        local ly = y + 6 + i * lineH
        love.graphics.setColor(t.color[1], t.color[2], t.color[3])
        love.graphics.print(string.format("%s: %d", t.label, self.totals[t.key] or 0), x + 10, ly)
    end

    love.graphics.setColor(1, 1, 1)
end

return Resources
