-- Explosion with cross propagation and damage timing

local G = require("src.globals")
local Colors = require("src.colors")
local Grid = require("src.grid")
local Utils = require("src.utils")

local Explosion = {}
Explosion.__index = Explosion

function Explosion:new(col, row, range)
    local e = {
        col = col,
        row = row,
        range = range or 2,
        timer = 0,
        duration = G.EXPLOSION_DURATION,
        tiles = {},
        graceTimer = G.GRACE_WINDOW,
        nearMissTimer = G.NEAR_MISS_TIME,
        damageActive = false
    }

    -- Calculate explosion tiles (cross shape)
    table.insert(e.tiles, {col = col, row = row, type = "center"})

    -- Four directions
    local dirs = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
    for _, d in ipairs(dirs) do
        for i = 1, e.range do
            local checkCol = col + d[1] * i
            local checkRow = row + d[2] * i

            -- Stop at permanent walls
            if Grid.get(G.grid, checkCol, checkRow) == Grid.WALL_PERMANENT then
                break
            end

            -- Add tile
            table.insert(e.tiles, {col = checkCol, row = checkRow, type = "arm"})

            -- Stop at breakable walls (but still include them for destruction)
            if Grid.get(G.grid, checkCol, checkRow) == Grid.WALL_BREAKABLE then
                break
            end
        end
    end

    return setmetatable(e, Explosion)
end

function Explosion:update(dt)
    self.timer = self.timer + dt

    -- Grace window - no damage initially
    if self.graceTimer > 0 then
        self.graceTimer = self.graceTimer - dt
    end

    -- Near miss detection
    if self.nearMissTimer > 0 then
        self.nearMissTimer = self.nearMissTimer - dt
    end

    -- Damage is active after grace window and before end
    self.damageActive = self.graceTimer <= 0 and self.timer < self.duration

    return self.timer >= self.duration
end

function Explosion:canDamage()
    return self.damageActive
end

function Explosion:isNearMiss()
    return self.nearMissTimer > 0 and self.graceTimer <= 0
end

function Explosion:checkCollision(x, y, width, height)
    if not self.damageActive then
        return false
    end

    local halfW = width / 2
    local halfH = height / 2

    for _, tile in ipairs(self.tiles) do
        local tileX, tileY = Grid.tileToWorld(G.grid, tile.col, tile.row)
        local tileL = tileX - G.TILE_SIZE / 2
        local tileR = tileX + G.TILE_SIZE / 2
        local tileT = tileY - G.TILE_SIZE / 2
        local tileB = tileY + G.TILE_SIZE / 2

        -- AABB collision check
        if x - halfW < tileR and x + halfW > tileL and
           y - halfH < tileB and y + halfH > tileT then
            return true
        end
    end

    return false
end

function Explosion:destroyBlocks()
    for _, tile in ipairs(self.tiles) do
        if Grid.destroyBlock(G.grid, tile.col, tile.row) then
            -- Spawn debris particles
            local x, y = Grid.tileToWorld(G.grid, tile.col, tile.row)
            require("src.particle").spawnDebris(x, y, Colors.WALL_BREAKABLE)
        end
    end
end

function Explosion:draw()
    local progress = self.timer / self.duration
    local alpha = 1 - progress
    local pulse = math.sin(self.timer * 20) * 0.2 + 0.8

    for _, tile in ipairs(self.tiles) do
        local x, y = Grid.tileToWorld(G.grid, tile.col, tile.row)
        local size = G.TILE_SIZE * (0.9 + progress * 0.1)

        if tile.type == "center" then
            love.graphics.setColor(Colors.EXPLOSION_CENTER[1], Colors.EXPLOSION_CENTER[2], Colors.EXPLOSION_CENTER[3], alpha)
        else
            love.graphics.setColor(Colors.EXPLOSION_ARM[1], Colors.EXPLOSION_ARM[2], Colors.EXPLOSION_ARM[3], alpha * pulse)
        end

        love.graphics.rectangle("fill", x - size/2, y - size/2, size, size)

        -- Core glow
        love.graphics.setColor(1, 1, 1, alpha * 0.5)
        local coreSize = size * 0.5
        love.graphics.rectangle("fill", x - coreSize/2, y - coreSize/2, coreSize, coreSize)
    end
end

return Explosion
