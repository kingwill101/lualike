-- Enemy entity with AI

local G = require("src.globals")
local Colors = require("src.colors")
local Utils = require("src.utils")
local Grid = require("src.grid")

local Enemy = {}
Enemy.__index = Enemy

-- Enemy type definitions
Enemy.TYPES = {
    basic = {
        speed = G.ENEMY_SPEED_SLOW,
        color = "ENEMY_BASIC",
        score = 100
    },
    fast = {
        speed = G.ENEMY_SPEED_FAST,
        color = "ENEMY_FAST",
        score = 200
    },
    tank = {
        speed = G.ENEMY_SPEED_MEDIUM,
        color = "ENEMY_TANK",
        score = 300
    }
}

function Enemy:new(type, col, row)
    local enemyType = Enemy.TYPES[type] or Enemy.TYPES.basic
    local x, y = Grid.tileToWorld(G.grid, col, row)

    local e = {
        type = type,
        x = x,
        y = y,
        width = G.TILE_SIZE * 0.65,
        height = G.TILE_SIZE * 0.65,
        speed = enemyType.speed,
        colorName = enemyType.color,
        scoreValue = enemyType.score,
        dirX = 1,
        dirY = 0,
        wobbleTime = math.random() * 10,
        scale = 1,
        stuckTimer = 0,
        lastPos = {x = x, y = y}
    }
    return setmetatable(e, Enemy)
end

function Enemy:update(dt, grid)
    -- Update wobble animation
    self.wobbleTime = self.wobbleTime + dt * G.ENEMY_WOBBLE_SPEED
    self.scale = 1 + math.sin(self.wobbleTime) * G.ENEMY_WOBBLE_AMP

    -- AI: Move in current direction
    local moveX = self.dirX * self.speed * dt
    local moveY = self.dirY * self.speed * dt

    -- Check for collision ahead
    local checkDist = self.speed * dt * 2
    local aheadX = self.x + self.dirX * (self.width/2 + checkDist)
    local aheadY = self.y + self.dirY * (self.height/2 + checkDist)
    local aheadCol, aheadRow = Grid.worldToTile(grid, aheadX, aheadY)

    -- Check for bombs ahead
    local bombAhead = false
    for _, bomb in ipairs(G.bombs) do
        if bomb.col == aheadCol and bomb.row == aheadRow then
            bombAhead = true
            break
        end
    end

    -- Determine if we need to turn
    local needsTurn = Grid.isSolid(grid, aheadCol, aheadRow) or bombAhead

    -- Check if stuck
    local distMoved = Utils.distance(self.x, self.y, self.lastPos.x, self.lastPos.y)
    if distMoved < 1 then
        self.stuckTimer = self.stuckTimer + dt
    else
        self.stuckTimer = 0
        self.lastPos.x = self.x
        self.lastPos.y = self.y
    end

    if needsTurn or self.stuckTimer > 0.5 then
        -- Pick new direction
        local possibleDirs = {}
        local dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

        for _, d in ipairs(dirs) do
            local checkCol = aheadCol + d[1]
            local checkRow = aheadRow + d[2]

            -- Check if direction is clear
            local clear = true

            -- Check walls
            if Grid.isSolid(grid, checkCol, checkRow) then
                clear = false
            end

            -- Check bombs (avoid them)
            for _, bomb in ipairs(G.bombs) do
                if bomb.col == checkCol and bomb.row == checkRow then
                    clear = false
                    break
                end
            end

            -- Prefer not to reverse
            if d[1] == -self.dirX and d[2] == -self.dirY then
                clear = clear and math.random() < 0.3
            end

            if clear then
                table.insert(possibleDirs, d)
            end
        end

        -- Pick a direction
        if #possibleDirs > 0 then
            local choice = possibleDirs[math.random(#possibleDirs)]
            self.dirX = choice[1]
            self.dirY = choice[2]
        elseif self.stuckTimer > 0.5 then
            -- Reverse if completely stuck
            self.dirX = -self.dirX
            self.dirY = -self.dirY
        end
    end

    -- Move
    self:moveWithCollision(grid, moveX, moveY)
end

function Enemy:moveWithCollision(grid, dx, dy)
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

function Enemy:checkCollision(grid, x, y)
    local halfW = self.width / 2
    local halfH = self.height / 2

    -- Check corners
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
    end

    return false
end

function Enemy:getGridPosition()
    local col = math.floor((self.x - G.GRID_OFFSET_X + G.TILE_SIZE / 2) / G.TILE_SIZE) + 1
    local row = math.floor((self.y - G.GRID_OFFSET_Y + G.TILE_SIZE / 2) / G.TILE_SIZE) + 1
    return col, row
end

function Enemy:draw()
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
    love.graphics.scale(self.scale, self.scale)

    -- Body
    local color = Colors[self.colorName] or Colors.ENEMY_BASIC
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", -self.width/2, -self.height/2, self.width, self.height)

    -- Border
    love.graphics.setColor(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7)
    love.graphics.rectangle("line", -self.width/2, -self.height/2, self.width, self.height)

    -- Eyes
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", -10, -8, 6, 6)
    love.graphics.rectangle("fill", 4, -8, 6, 6)

    -- Pupils (look in movement direction)
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", -8 + self.dirX * 2, -6 + self.dirY * 2, 2, 2)
    love.graphics.rectangle("fill", 6 + self.dirX * 2, -6 + self.dirY * 2, 2, 2)

    love.graphics.pop()
end

return Enemy
