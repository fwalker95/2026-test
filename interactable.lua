-- interactable.lua
local Interactable = {}
Interactable.__index = Interactable

function Interactable.new(kind, x, y, opts)
    local self = setmetatable({}, Interactable)
    self.kind = kind or "generic"
    self.x = x or 0
    self.y = y or 0
    self.name = (opts and opts.name) or kind or "generic"
    self.allowedRoles = (opts and opts.allowedRoles) or {}
    self.interactionTime = (opts and opts.interactionTime) or 1.2
    self.maxProgress = (opts and opts.maxProgress) or 1
    self.progress = 0
    self.enabled = true
    self.claimedBy = nil
    self.data = (opts and opts.data) or {}
    self.resourceLeft = (opts and opts.resourceLeft) or nil
    self.capacity = (opts and opts.capacity) or nil
    self.amount = (opts and opts.amount) or 0
    return self
end

function Interactable:canInteract(agent)
    if not self.enabled then return false end
    if not agent then return false end
    if not self.allowedRoles or #self.allowedRoles == 0 then return true end

    for _, role in ipairs(self.allowedRoles) do
        if role == agent.role then
            return true
        end
    end

    return false
end

function Interactable:claim(agent)
    if not self:canInteract(agent) then return false end
    self.claimedBy = agent
    return true
end

function Interactable:release()
    self.claimedBy = nil
end

function Interactable:work(agent, dt)
    if not self:canInteract(agent) then return false end
    if self.resourceLeft ~= nil and self.resourceLeft <= 0 then return false end
    if self.capacity ~= nil and self.amount >= self.capacity then return false end

    self.progress = (self.progress or 0) + dt
    if self.progress >= self.interactionTime then
        if self.resourceLeft ~= nil then
            self.resourceLeft = math.max(0, self.resourceLeft - 1)
        end
        if self.capacity ~= nil then
            self.amount = math.min(self.capacity, (self.amount or 0) + 1)
        end
        self.progress = 0
        return true
    end

    return false
end

return Interactable
