-- dna_field.lua
-- Randomly generated field of A/C/T/G bases with clusters and empty spaces.
local DNAField = {}
DNAField.__index = DNAField

local R = (love and love.math) or math

DNAField.letters = { "A", "C", "T", "G" }
DNAField.colors = {
    A = { 0.40, 0.90, 0.40 },
    C = { 0.40, 0.65, 1.00 },
    T = { 1.00, 0.55, 0.35 },
    G = { 1.00, 0.85, 0.30 },
}

function DNAField.new(cols, rows)
    local self = setmetatable({}, DNAField)
    self.cols = cols or 40
    self.rows = rows or 22
    self:generate()
    return self
end

function DNAField:generate()
    local cols, rows = self.cols, self.rows
    local cells = {}
    for x = 1, cols do
        cells[x] = {}
    end

    local function randLetter()
        return DNAField.letters[R.random(1, #DNAField.letters)]
    end

    -- clusters: dense blobs, mostly one dominant letter
    local clusterCount = R.random(7, 12)
    for _ = 1, clusterCount do
        local cx = R.random(1, cols)
        local cy = R.random(1, rows)
        local radius = R.random(2, 5) + R.random()
        local dominant = randLetter()

        for x = math.max(1, math.floor(cx - radius)), math.min(cols, math.ceil(cx + radius)) do
            for y = math.max(1, math.floor(cy - radius)), math.min(rows, math.ceil(cy + radius)) do
                local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
                if d <= radius then
                    local density = 1.0 - (d / radius) * 0.6
                    if R.random() < density then
                        cells[x][y] = (R.random() < 0.75) and dominant or randLetter()
                    end
                end
            end
        end
    end

    -- sparse stray bases in the empty space
    for x = 1, cols do
        for y = 1, rows do
            if not cells[x][y] and R.random() < 0.04 then
                cells[x][y] = randLetter()
            end
        end
    end

    self.cells = cells
end

function DNAField:counts()
    local c = { A = 0, C = 0, T = 0, G = 0 }
    for x = 1, self.cols do
        for y = 1, self.rows do
            local l = self.cells[x][y]
            if l then c[l] = c[l] + 1 end
        end
    end
    return c
end

-- Draws the field inside the rectangle (x, y, w, h).
function DNAField:draw(x, y, w, h)
    local cs = math.floor(math.min(w / self.cols, h / self.rows))
    local fw, fh = cs * self.cols, cs * self.rows
    local ox = x + math.floor((w - fw) / 2)
    local oy = y + math.floor((h - fh) / 2)

    love.graphics.setColor(0.02, 0.03, 0.05, 1)
    love.graphics.rectangle("fill", ox, oy, fw, fh)

    local font = love.graphics.getFont()
    local scale = math.max(0.5, (cs * 0.7) / font:getHeight())

    for gx = 1, self.cols do
        for gy = 1, self.rows do
            local l = self.cells[gx][gy]
            if l then
                local c = DNAField.colors[l]
                local px = ox + (gx - 1) * cs
                local py = oy + (gy - 1) * cs
                love.graphics.setColor(c[1], c[2], c[3], 0.12)
                love.graphics.rectangle("fill", px, py, cs - 1, cs - 1)
                love.graphics.setColor(c[1], c[2], c[3], 1)
                local tw = font:getWidth(l) * scale
                local th = font:getHeight() * scale
                love.graphics.print(l, px + (cs - tw) / 2, py + (cs - th) / 2, 0, scale, scale)
            end
        end
    end

    love.graphics.setColor(0.2, 0.4, 0.6, 1)
    love.graphics.rectangle("line", ox, oy, fw, fh)
    love.graphics.setColor(1, 1, 1, 1)
end

return DNAField
