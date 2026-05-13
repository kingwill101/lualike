-- Player entity

local G = require("src.globals")
local Colors = require("src.colors")
local Utils = require("src.utils")
local Grid = require("src.grid")

local Player = {}
Player.__index = Player

function Player:new(x, y)
    local p = {
        x = x,
        y = y,
        width = G.TILE_SIZE * 0.7,
        height = G.TILE_SIZE * 0.7,
        speed = G.PLAYER_SPEED,
        dirX = 0,
        dirY = 1,
        moving = false,
        wobble = 0,
        wobbleTime = 0,
        scale = 1,
        standingOnBomb = nil, -- Track which bomb we're standing on
        dead = false,
        deathTime = 0
    }
    return setmetatable(p, Player)
end

function Player:update(dt, grid)
    -- Update death animation even when dead
    if self.dead then
        self.deathTime = self.deathTime + dt
        -- Continue animating death
        local progress = math.min(self.deathTime / 0.8, 1)
        self.scale = 1 + progress * 0.5
        return
    end

    -- Check if we're still standing on a bomb (check if any part overlaps the bomb tile)
    if self.standingOnBomb then
        if not self:isOnBombTile(self.standingOnBomb) then
            self.standingOnBomb = nil
        end
    end

    -- Get input
    local dx, dy = G.input.dx, G.input.dy

    -- Normalize to cardinal directions
    if dx ~= 0 or dy ~= 0 then
        if math.abs(dx) > math.abs(dy) then
            dy = 0
        else
            dx = 0
        end
    end

    -- Store direction when moving
    if dx ~= 0 or dy ~= 0 then
        self.dirX = dx
        self.dirY = dy
    end

    -- Try to move
    local moveX = dx * self.speed * dt
    local moveY = dy * self.speed * dt

    -- Apply cornering assist
    if dx ~= 0 and moveX ~= 0 then
        moveY = self:tryCornerAssist(grid, moveX, 0)
    elseif dy ~= 0 and moveY ~= 0 then
        moveX = self:tryCornerAssist(grid, 0, moveY)
    end

    -- Move with collision
    self:moveWithCollision(grid, moveX, moveY)

    -- Update animation
    self.moving = dx ~= 0 or dy ~= 0
    self.wobbleTime = self.wobbleTime + dt * (self.moving and G.WOBBLE_SPEED or G.WOBBLE_SPEED * 0.5)
    local amp = self.moving and G.WOBBLE_AMP_WALK or G.WOBBLE_AMP_IDLE
    self.wobble = math.sin(self.wobbleTime) * amp

    -- Bounce scale
    if self.moving then
        self.scale = 1 + math.sin(self.wobbleTime * 2) * 0.05
    else
        self.scale = Utils.lerp(self.scale, 1, dt * 10)
    end
end

function Player:tryCornerAssist(grid, dx, dy)
    local newX = self.x + dx
    local newY = self.y + dy

    -- Check if collision would occur
    if self:checkCollision(grid, newX, newY) then
        return 0
    end

    -- If moving horizontally, check for vertical alignment assist
    if dx ~= 0 and dy == 0 then
        local _, row = Grid.worldToTile(grid, self.x, self.y)
        local targetY = select(2, Grid.tileToWorld(grid, 1, row))
        local diff = targetY - self.y
        if math.abs(diff) < G.CORNER_ASSIST_PX then
            return diff * 0.5
        end
    end

    -- If moving vertically, check for horizontal alignment assist
    if dy ~= 0 and dx == 0 then
        local col, _ = Grid.worldToTile(grid, self.x, self.y)
        local targetX = select(1, Grid.tileToWorld(grid, col, 1))
        local diff = targetX - self.x
        if math.abs(diff) < G.CORNER_ASSIST_PX then
            return diff * 0.5
        end
    end

    return 0
end

function Player:moveWithCollision(grid, dx, dy)
    -- Try X movement
    local newX = self.x + dx
    if not self:checkCollision(grid, newX, self.y) then
        self.x = newX
    end

    -- Try Y movement
    local newY = self.y + dy
    if not self:checkCollision(grid, self.x, newY) then
        self.y = newY
    end
end

function Player:checkCollision(grid, x, y)
    local halfW = self.width / 2
    local halfH = self.height / 2

    -- Check corners of player hitbox
    local corners = {
        {x - halfW + 2, y - halfH + 2},
        {x + halfW - 2, y - halfH + 2},
        {x - halfW + 2, y + halfH - 2},
        {x + halfW - 2, y + halfH - 2}
    }

    for _, corner in ipairs(corners) do
        local col, row = Grid.worldToTile(grid, corner[1], corner[2])
        if Grid.isSolid(grid, col, row) then
            return true
        end

        -- Check bomb collision
        for _, bomb in ipairs(G.bombs) do
            if bomb.col == col and bomb.row == row then
                -- Allow passing through the bomb we're standing on
                if self.standingOnBomb == bomb then
                    -- Can walk through this bomb
                else
                    return true
                end
            end
        end
    end

    return false
end

function Player:isOnBombTile(bomb)
    -- Check if any corner of the player is on the bomb's tile
    local halfW = self.width / 2
    local halfH = self.height / 2

    local corners = {
        {self.x - halfW + 2, self.y - halfH + 2},
        {self.x + halfW - 2, self.y - halfH + 2},
        {self.x - halfW + 2, self.y + halfH - 2},
        {self.x + halfW - 2, self.y + halfH - 2}
    }

    for _, corner in ipairs(corners) do
        local col, row = Grid.worldToTile(G.grid, corner[1], corner[2])
        if col == bomb.col and row == bomb.row then
            return true
        end
    end

    -- Also check center
    local centerCol, centerRow = self:getGridPosition()
    if centerCol == bomb.col and centerRow == bomb.row then
        return true
    end

    return false
end

function Player:onBombPlaced(bomb)
    self.standingOnBomb = bomb
end

function Player:getGridPosition()
    local col = math.floor((self.x - G.GRID_OFFSET_X) / G.TILE_SIZE) + 1
    local row = math.floor((self.y - G.GRID_OFFSET_Y) / G.TILE_SIZE) + 1
    return col, row
end

function Player:die()
    self.dead = true
    self.deathTime = 0
end

function Player:draw()
    if self.dead then
        -- Death animation - expand and fade with rotation
        local progress = math.min(self.deathTime / 0.8, 1)
        local alpha = math.max(0, 1 - progress * 1.5)
        local rotation = progress * math.pi * 4
        local currentScale = self.scale * (1 + progress)

        love.graphics.push()
        love.graphics.translate(self.x, self.y)
        love.graphics.rotate(rotation)
        love.graphics.scale(currentScale, currentScale)

        -- Flash between red and player color
        local flash = math.sin(progress * math.pi * 8)
        if flash > 0 then
            love.graphics.setColor(Colors.EXPLOSION_CENTER[1], Colors.EXPLOSION_CENTER[2], Colors.EXPLOSION_CENTER[3], alpha)
        else
            love.graphics.setColor(Colors.PLAYER[1], Colors.PLAYER[2], Colors.PLAYER[3], alpha)
        end
        love.graphics.rectangle("fill", -self.width/2, -self.height/2, self.width, self.height)

        -- Draw X eyes for death
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.setLineWidth(2)
        love.graphics.line(-8, -6, -2, 0)
        love.graphics.line(-8, 0, -2, -6)
        love.graphics.line(2, -6, 8, 0)
        love.graphics.line(2, 0, 8, -6)
        love.graphics.setLineWidth(1)

        love.graphics.pop()
        return
    end

    -- Normal draw with wobble
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.rotate(self.wobble)
    love.graphics.scale(self.scale, self.scale)

    -- Body
    love.graphics.setColor(Colors.PLAYER)
    love.graphics.rectangle("fill", -self.width/2, -self.height/2, self.width, self.height)

    -- Eyes (show direction)
    love.graphics.setColor(1, 1, 1)
    local eyeOffsetX = self.dirX * 4
    local eyeOffsetY = self.dirY * 4 - 2
    love.graphics.rectangle("fill", -8 + eyeOffsetX, -6 + eyeOffsetY, 6, 6)
    love.graphics.rectangle("fill", 2 + eyeOffsetX, -6 + eyeOffsetY, 6, 6)

    -- Pupils
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", -6 + eyeOffsetX + self.dirX * 2, -4 + eyeOffsetY + self.dirY * 2, 2, 2)
    love.graphics.rectangle("fill", 4 + eyeOffsetX + self.dirX * 2, -4 + eyeOffsetY + self.dirY * 2, 2, 2)

    love.graphics.pop()
end

return Player
