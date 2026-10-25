-- dna_field.lua
-- One unique ACTG field per biomass sample.
-- All bases start greyed out. Scanning reveals TGA (gene start) / TAG (gene end)
-- codons, but damages random single gene blocks. Repeated scans start revealing
-- every kind of base.
local DNAField = {}
DNAField.__index = DNAField

DNAField.letters = { "A", "C", "T", "G" }
DNAField.colors = {
    A = { 0.40, 0.90, 0.40 },
    C = { 0.40, 0.65, 1.00 },
    T = { 1.00, 0.55, 0.35 },
    G = { 1.00, 0.85, 0.30 },
}

local STOPS = { TGA = true, TAG = true, TAA = true }

function DNAField.new(cols, rows, seed)
    local self = setmetatable({}, DNAField)
    self.cols = cols or 40
    self.rows = rows or 22
    self.seed = seed or os.time()
    self.rng = love.math.newRandomGenerator(self.seed)
    self.presses = 0
    self.lastLog = "No scan yet"
    self:generate()
    return self
end

local function newCell(letter)
    return { letter = letter, revealed = false, destroyed = false, role = nil, gene = nil }
end

function DNAField:randLetter()
    return DNAField.letters[self.rng:random(1, #DNAField.letters)]
end

function DNAField:randBodyCodon()
    while true do
        local c = self:randLetter() .. self:randLetter() .. self:randLetter()
        if not STOPS[c] then return c end
    end
end

function DNAField:generate()
    local cols, rows, rng = self.cols, self.rows, self.rng
    local cells = {}
    for x = 1, cols do cells[x] = {} end

    -- clusters
    local clusterCount = rng:random(7, 12)
    for _ = 1, clusterCount do
        local cx = rng:random(1, cols)
        local cy = rng:random(1, rows)
        local radius = rng:random(2, 5) + rng:random()
        local dominant = self:randLetter()

        for x = math.max(1, math.floor(cx - radius)), math.min(cols, math.ceil(cx + radius)) do
            for y = math.max(1, math.floor(cy - radius)), math.min(rows, math.ceil(cy + radius)) do
                local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
                if d <= radius then
                    local density = 1.0 - (d / radius) * 0.6
                    if rng:random() < density then
                        cells[x][y] = newCell((rng:random() < 0.75) and dominant or self:randLetter())
                    end
                end
            end
        end
    end

    -- sparse stray bases
    for x = 1, cols do
        for y = 1, rows do
            if not cells[x][y] and rng:random() < 0.04 then
                cells[x][y] = newCell(self:randLetter())
            end
        end
    end

    -- genes: TGA ... TAG laid out horizontally
    self.genes = {}
    local wanted = rng:random(3, 6)
    local attempts = 0
    while #self.genes < wanted and attempts < 60 do
        attempts = attempts + 1
        local bodyCodons = rng:random(2, 5)
        local len = 6 + bodyCodons * 3
        local row = rng:random(1, rows)
        local sx = rng:random(1, cols - len + 1)

        local free = true
        for x = sx, sx + len - 1 do
            if cells[x][row] and cells[x][row].gene then free = false break end
        end

        if free then
            local gi = #self.genes + 1
            local seq = "TGA"
            for _ = 1, bodyCodons do seq = seq .. self:randBodyCodon() end
            seq = seq .. "TAG"

            for i = 1, len do
                local x = sx + i - 1
                local c = newCell(seq:sub(i, i))
                c.gene = gi
                if i <= 3 then c.role = "start"
                elseif i > len - 3 then c.role = "end"
                else c.role = "body" end
                cells[x][row] = c
            end

            self.genes[gi] = { row = row, sx = sx, ex = sx + len - 1, startRevealed = false, endRevealed = false }
        end
    end

    self.cells = cells
end

local function revealCodon(self, gene, which)
    local from, to
    if which == "start" then from, to = gene.sx, gene.sx + 2
    else from, to = gene.ex - 2, gene.ex end
    for x = from, to do
        self.cells[x][gene.row].revealed = true
    end
    if which == "start" then gene.startRevealed = true else gene.endRevealed = true end
end

local function shuffle(list, rng)
    for i = #list, 2, -1 do
        local j = rng:random(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- The scan button. Returns nothing; results go to self.lastLog.
function DNAField:scan()
    local rng = self.rng
    self.presses = self.presses + 1

    -- 1) reveal random numbers of TGA (start) and TAG (end) codons
    local pendingStarts, pendingEnds = {}, {}
    for _, g in ipairs(self.genes) do
        if not g.startRevealed then pendingStarts[#pendingStarts + 1] = g end
        if not g.endRevealed then pendingEnds[#pendingEnds + 1] = g end
    end
    shuffle(pendingStarts, rng)
    shuffle(pendingEnds, rng)

    local tgaCount = math.min(#pendingStarts, rng:random(1, 3)) -- TGA gets a bonus
    local tagCount = math.min(#pendingEnds, rng:random(0, 2))
    for i = 1, tgaCount do revealCodon(self, pendingStarts[i], "start") end
    for i = 1, tagCount do revealCodon(self, pendingEnds[i], "end") end

    -- 2) scanning destroys a random number of single gene blocks
    local bodies = {}
    for _, g in ipairs(self.genes) do
        for x = g.sx + 3, g.ex - 3 do
            local c = self.cells[x][g.row]
            if not c.destroyed then bodies[#bodies + 1] = c end
        end
    end
    shuffle(bodies, rng)
    local destroyed = math.min(#bodies, rng:random(1, 4))
    for i = 1, destroyed do
        bodies[i].destroyed = true
        bodies[i].revealed = false
    end

    -- 3) from the 3rd press on, all base types start being revealed
    local extra = 0
    if self.presses >= 3 then
        local hidden = {}
        for x = 1, self.cols do
            for y = 1, self.rows do
                local c = self.cells[x][y]
                if c and not c.revealed and not c.destroyed then hidden[#hidden + 1] = c end
            end
        end
        shuffle(hidden, rng)
        extra = math.min(#hidden, rng:random(1, (self.presses - 2) * 4))
        for i = 1, extra do hidden[i].revealed = true end
    end

    self.lastLog = string.format("Scan %d: +%d TGA, +%d TAG, %d blocks destroyed, %d bases revealed",
        self.presses, tgaCount, tagCount, destroyed, extra)
end

function DNAField:stats()
    local s = {
        genes = #self.genes, intact = 0,
        starts = 0, ends = 0,
        revealed = 0, total = 0, destroyed = 0,
    }
    for _, g in ipairs(self.genes) do
        if g.startRevealed then s.starts = s.starts + 1 end
        if g.endRevealed then s.ends = s.ends + 1 end
        local ok = true
        for x = g.sx, g.ex do
            if self.cells[x][g.row].destroyed then ok = false break end
        end
        if ok then s.intact = s.intact + 1 end
    end
    for x = 1, self.cols do
        for y = 1, self.rows do
            local c = self.cells[x][y]
            if c then
                s.total = s.total + 1
                if c.revealed then s.revealed = s.revealed + 1 end
                if c.destroyed then s.destroyed = s.destroyed + 1 end
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

    local font = love.graphics.getFont()
    local scale = math.max(0.5, (cs * 0.7) / font:getHeight())

    for gx = 1, self.cols do
        for gy = 1, self.rows do
            local c = self.cells[gx][gy]
            if c then
                local px = ox + (gx - 1) * cs
                local py = oy + (gy - 1) * cs

                if c.destroyed then
                    love.graphics.setColor(0.16, 0.05, 0.05, 1)
                    love.graphics.rectangle("fill", px, py, cs - 1, cs - 1)
                    love.graphics.setColor(0.5, 0.12, 0.12, 1)
                    love.graphics.line(px + 3, py + 3, px + cs - 4, py + cs - 4)
                    love.graphics.line(px + cs - 4, py + 3, px + 3, py + cs - 4)
                elseif not c.revealed then
                    -- greyed out box
                    love.graphics.setColor(0.24, 0.26, 0.30, 1)
                    love.graphics.rectangle("fill", px, py, cs - 1, cs - 1)
                else
                    local col = DNAField.colors[c.letter]
                    love.graphics.setColor(col[1], col[2], col[3], 0.15)
                    love.graphics.rectangle("fill", px, py, cs - 1, cs - 1)
                    love.graphics.setColor(col[1], col[2], col[3], 1)
                    local tw = font:getWidth(c.letter) * scale
                    local th = font:getHeight() * scale
                    love.graphics.print(c.letter, px + (cs - tw) / 2, py + (cs - th) / 2, 0, scale, scale)

                    if c.role == "start" then
                        love.graphics.setColor(0.3, 1.0, 0.4, 1)
                        love.graphics.rectangle("line", px, py, cs - 1, cs - 1)
                    elseif c.role == "end" then
                        love.graphics.setColor(1.0, 0.3, 0.3, 1)
                        love.graphics.rectangle("line", px, py, cs - 1, cs - 1)
                    end
                end
            end
        end
    end

    love.graphics.setColor(0.2, 0.4, 0.6, 1)
    love.graphics.rectangle("line", ox, oy, fw, fh)
    love.graphics.setColor(1, 1, 1, 1)
end

return DNAField
