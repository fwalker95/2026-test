-- dna_field.lua
-- One unique ACTG field per biomass sample.
-- Mixed-soup mode: all bases are fully visible from the start.
local DNAField = {}
DNAField.__index = DNAField

DNAField.letters = { "A", "C", "T", "G" }
DNAField.colors = {
    A = { 0.40, 0.90, 0.40 },
    C = { 0.40, 0.65, 1.00 },
    T = { 1.00, 0.55, 0.35 },
    G = { 1.00, 0.85, 0.30 },
}

function DNAField.new(cols, rows, seed)
    local self = setmetatable({}, DNAField)
    self.cols = cols or 40
    self.rows = rows or 22
    self.seed = seed or os.time()
    self.rng = love.math.newRandomGenerator(self.seed)
    self.presses = 0
    self.lastLog = "Sample generated"
    self.extractAttempts = 0
    self.extractSuccesses = 0
    self.totalRemoved = 0
    self.exhausted = false
    self.highlight = nil -- { kind = "row"|"column", index = N }
    self:generate()
    return self
end

local function newCell(letter)
    return { letter = letter, revealed = true, destroyed = false, role = nil, gene = nil }
end

function DNAField:randLetter()
    return DNAField.letters[self.rng:random(1, #DNAField.letters)]
end

function DNAField:generate()
    local cols, rows, rng = self.cols, self.rows, self.rng
    local cells = {}
    for x = 1, cols do cells[x] = {} end

    -- dense clusters for a mixed genetic soup look
    local clusterCount = rng:random(9, 16)
    for _ = 1, clusterCount do
        local cx = rng:random(1, cols)
        local cy = rng:random(1, rows)
        local radius = rng:random(2, 6) + rng:random()
        local dominant = self:randLetter()

        for x = math.max(1, math.floor(cx - radius)), math.min(cols, math.ceil(cx + radius)) do
            for y = math.max(1, math.floor(cy - radius)), math.min(rows, math.ceil(cy + radius)) do
                local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
                if d <= radius then
                    local density = 1.0 - (d / radius) * 0.55
                    if rng:random() < density then
                        cells[x][y] = newCell((rng:random() < 0.7) and dominant or self:randLetter())
                    end
                end
            end
        end
    end

    -- fill most remaining holes so the soup is mostly continuous
    for x = 1, cols do
        for y = 1, rows do
            if not cells[x][y] and rng:random() < 0.88 then
                cells[x][y] = newCell(self:randLetter())
            end
        end
    end

    self.cells = cells
end

function DNAField:setHighlight(kind, index)
    if not kind or not index then
        self.highlight = nil
        return
    end
    self.highlight = { kind = kind, index = index }
end

function DNAField:clearHighlight()
    self.highlight = nil
end

-- delete full row/column and return extracted sequence string from removed bases.
function DNAField:deleteLine(kind, index)
    if self.exhausted then return nil end

    local out = {}

    if kind == "row" then
        local y = math.max(1, math.min(self.rows, index or 1))
        for x = 1, self.cols do
            local c = self.cells[x][y]
            if c and not c.destroyed then
                out[#out + 1] = c.letter
                self.cells[x][y] = nil
            end
        end
    else
        local x = math.max(1, math.min(self.cols, index or 1))
        for y = 1, self.rows do
            local c = self.cells[x][y]
            if c and not c.destroyed then
                out[#out + 1] = c.letter
                self.cells[x][y] = nil
            end
        end
    end

    local seq = table.concat(out)
    if #seq > 0 then
        self.totalRemoved = self.totalRemoved + #seq
        self.lastLog = string.format("Deleted %s %d, removed %d bases", kind, index or 1, #seq)
    else
        self.lastLog = string.format("Deleted %s %d, but it was empty", kind, index or 1)
    end

    self:checkExhausted()
    return seq
end

function DNAField:countAvailable()
    local total = 0
    for x = 1, self.cols do
        for y = 1, self.rows do
            if self.cells[x][y] then total = total + 1 end
        end
    end
    return total
end

function DNAField:checkExhausted()
    self.exhausted = (self:countAvailable() == 0)
end

function DNAField:stats()
    local s = {
        total = 0,
        revealed = 0,
        destroyed = 0,
        genes = 0,
        intact = 0,
        starts = 0,
        ends = 0,
        remaining = 0,
        removed = self.totalRemoved or 0,
        attempts = self.extractAttempts or 0,
        successes = self.extractSuccesses or 0,
    }

    for x = 1, self.cols do
        for y = 1, self.rows do
            local c = self.cells[x][y]
            if c then
                s.total = s.total + 1
                s.revealed = s.revealed + 1
                s.remaining = s.remaining + 1
            end
        end
    end

    return s
end

-- Draws the field inside the rectangle (x, y, w, h).
function DNAField:draw(x, y, w, h)
    local cs = math.floor(math.min(w / self.cols, h / self.rows))
    local fw, fh = cs * self.cols, cs * self.rows
    local ox = x + math.floor((w - fw) / 2)
    local oy = y + math.floor((h - fh) / 2)

    love.graphics.setColor(0.02, 0.03, 0.05, 1)
    love.graphics.rectangle("fill", ox, oy, fw, fh)

    -- white row/column highlight during scientist lookup
    if self.highlight then
        love.graphics.setColor(1, 1, 1, 0.12)
        if self.highlight.kind == "row" then
            local y1 = oy + (self.highlight.index - 1) * cs
            love.graphics.rectangle("fill", ox, y1, fw, cs)
        else
            local x1 = ox + (self.highlight.index - 1) * cs
            love.graphics.rectangle("fill", x1, oy, cs, fh)
        end
    end

    local font = love.graphics.getFont()
    local scale = math.max(0.5, (cs * 0.7) / font:getHeight())

    for gx = 1, self.cols do
        for gy = 1, self.rows do
            local c = self.cells[gx][gy]
            if c then
                local px = ox + (gx - 1) * cs
                local py = oy + (gy - 1) * cs

                local col = DNAField.colors[c.letter]
                love.graphics.setColor(col[1], col[2], col[3], 0.15)
                love.graphics.rectangle("fill", px, py, cs - 1, cs - 1)
                love.graphics.setColor(col[1], col[2], col[3], 1)
                local tw = font:getWidth(c.letter) * scale
                local th = font:getHeight() * scale
                love.graphics.print(c.letter, px + (cs - tw) / 2, py + (cs - th) / 2, 0, scale, scale)
            end
        end
    end

    -- bright outline over highlighted line
    if self.highlight then
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.setLineWidth(2)
        if self.highlight.kind == "row" then
            local y1 = oy + (self.highlight.index - 1) * cs
            love.graphics.rectangle("line", ox, y1, fw, cs)
        else
            local x1 = ox + (self.highlight.index - 1) * cs
            love.graphics.rectangle("line", x1, oy, cs, fh)
        end
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(0.2, 0.4, 0.6, 1)
    love.graphics.rectangle("line", ox, oy, fw, fh)
    love.graphics.setColor(1, 1, 1, 1)
end

return DNAField
