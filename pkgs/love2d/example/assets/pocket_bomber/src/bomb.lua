-- Bomb entity with fuse timing

local G = require("src.globals")
local Colors = require("src.colors")
local Grid = require("src.grid")

local Bomb = {}
Bomb.__index = Bomb

function Bomb:new(col, row, fromPlayer)
    local x, y = Grid.tileToWorld(G.grid, col, row)

    local b = {
        col = col,
        row = row,
        x = x,
        y = y,
        fromPlayer = fromPlayer,
        timer = G.FUSE_TIME,
        maxTimer = G.FUSE_TIME,
        blinkTimer = 0,
        visible = true,
        scale = 0.8
    }
    return setmetatable(b, Bomb)
end

function Bomb:update(dt)
    self.timer = self.timer - dt

    -- Blink rate accelerates as fuse runs down
    local progress = 1 - (self.timer / self.maxTimer)
    local blinkRate = G.BLINK_RATE_START - (G.BLINK_RATE_START - G.BLINK_RATE_END) * progress

    self.blinkTimer = self.blinkTimer + dt
    if self.blinkTimer >= blinkRate then
        self.blinkTimer = 0
        self.visible = not self.visible
    end

    -- Scale animation
    local targetScale = 0.8 + progress * 0.2
    self.scale = self.scale + (targetScale - self.scale) * dt * 5

    return self.timer <= 0
end

function Bomb:draw()
    -- Draw bomb body
    local bodyColor = self.visible and Colors.BOMB or Colors.BOMB_LIT
    love.graphics.setColor(bodyColor)

    local size = G.TILE_SIZE * 0.6 * self.scale
    love.graphics.rectangle("fill", self.x - size/2, self.y - size/2, size, size)

    -- Fuse (small dot on top)
    love.graphics.setColor(Colors.HIGHLIGHT)
    love.graphics.rectangle("fill", self.x - 3, self.y - size/2 - 4, 6, 4)

    -- Blinking highlight
    if self.visible then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.rectangle("fill", self.x - size/4, self.y - size/4, size/2, size/2)
    end
end

return Bomb
