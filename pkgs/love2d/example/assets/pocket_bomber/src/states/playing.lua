-- Playing state

local G = require("src.globals")
local Colors = require("src.colors")
local StateMachine = require("src.state_machine")
local Grid = require("src.grid")
local Level = require("src.level")
local Player = require("src.player")
local Enemy = require("src.enemy")
local Bomb = require("src.bomb")
local Explosion = require("src.explosion")
local Particle = require("src.particle")
local Touch = require("src.touch_controls")
local UI = require("src.ui")
local Save = require("src.save")

local playing = {}

-- Game objects
local player = nil
local levelData = nil
local gameOverTimer = 0
local levelClearTimer = 0
local isPaused = false

function playing.enter(params)
    G.COLORS = Colors
    G.currentLevel = params.level or 1
    levelData = Level.load(G.currentLevel)

    if not levelData then
        -- All levels completed
        StateMachine.switch("menu")
        return
    end

    G.grid = levelData.grid

    -- Create player
    local startX, startY = Grid.tileToWorld(G.grid, levelData.playerStart.col, levelData.playerStart.row)
    player = Player:new(startX, startY)

    -- Create enemies
    G.enemies = {}
    for _, e in ipairs(levelData.enemies) do
        local enemy = Enemy:new(e.type, e.col, e.row)
        table.insert(G.enemies, enemy)
    end

    -- Clear other entities
    G.bombs = {}
    G.explosions = {}
    G.particles = {}

    gameOverTimer = 0
    levelClearTimer = 0
    isPaused = false
end

function playing.update(dt)
    if isPaused then return end

    -- Update level timer
    Level.update(levelData, dt)

    -- Update player (even when dead for animation)
    player:update(dt, G.grid)

    -- Check game over conditions (after player update for death animation)
    if player.dead then
        gameOverTimer = gameOverTimer + dt
        if gameOverTimer >= 2.0 then
            StateMachine.switch("gameover", {score = G.currentScore})
        end
    else
        -- Check time up (only if not already dead)
        if Level.isTimeUp(levelData) then
            player:die()
        end
    end

    -- Level clear
    if not player.dead and Level.isComplete(levelData) and levelClearTimer == 0 then
        levelClearTimer = 0.01
    end

    if levelClearTimer > 0 then
        levelClearTimer = levelClearTimer + dt
        if levelClearTimer >= 2 then
            -- Bonus for time remaining
            G.currentScore = G.currentScore + math.floor(levelData.timeRemaining * 10)

            -- Next level
            if G.currentLevel >= 5 then
                StateMachine.switch("gameover", {score = G.currentScore, won = true})
            else
                StateMachine.switch("playing", {level = G.currentLevel + 1})
            end
        end
        -- Continue updating world during level clear, but don't process player input
    end

    -- Skip gameplay updates if dead or level clear
    if player.dead or levelClearTimer > 0 then
        -- Still update particles and explosions for visual feedback
        Particle.update(dt)

        -- Update explosions
        for i = #G.explosions, 1, -1 do
            local explosion = G.explosions[i]
            if explosion:update(dt) then
                table.remove(G.explosions, i)
            end
        end

        -- Update bombs
        for i = #G.bombs, 1, -1 do
            local bomb = G.bombs[i]
            if bomb:update(dt) then
                table.remove(G.bombs, i)
                playing.spawnExplosion(bomb.col, bomb.row)
            end
        end

        return
    end

    -- Bomb placement
    if G.input.bombPressed and not player.bombPressedLast then
        playing.tryPlaceBomb()
    end
    player.bombPressedLast = G.input.bombPressed

    -- Update enemies
    for _, enemy in ipairs(G.enemies) do
        enemy:update(dt, G.grid)
    end

    -- Update bombs
    for i = #G.bombs, 1, -1 do
        local bomb = G.bombs[i]
        if bomb:update(dt) then
            -- Bomb exploded
            table.remove(G.bombs, i)
            playing.spawnExplosion(bomb.col, bomb.row)
        end
    end

    -- Update explosions
    for i = #G.explosions, 1, -1 do
        local explosion = G.explosions[i]

        -- Destroy blocks on first frame
        if explosion.timer == 0 then
            explosion:destroyBlocks()
        end

        if explosion:update(dt) then
            table.remove(G.explosions, i)
        else
            -- Check damage to player (only if still alive)
            if not player.dead and explosion:canDamage() and explosion:checkCollision(player.x, player.y, player.width, player.height) then
                player:die()
            end

            -- Check damage to enemies
            for j = #G.enemies, 1, -1 do
                local enemy = G.enemies[j]
                if explosion:checkCollision(enemy.x, enemy.y, enemy.width, enemy.height) then
                    -- Enemy killed
                    G.currentScore = G.currentScore + enemy.scoreValue
                    Particle.spawnText(enemy.x, enemy.y, tostring(enemy.scoreValue), Colors.HIGHLIGHT)
                    table.remove(G.enemies, j)
                end
            end
        end
    end

    -- Update particles
    Particle.update(dt)

    -- Check enemy collision with player (only if still alive)
    if not player.dead then
        for _, enemy in ipairs(G.enemies) do
            local dist = require("src.utils").distance(player.x, player.y, enemy.x, enemy.y)
            if dist < (player.width + enemy.width) / 2 then
                player:die()
                break
            end
        end
    end
end

function playing.tryPlaceBomb()
    local col, row = player:getGridPosition()

    -- Check if space is clear
    local canPlace = true
    for _, bomb in ipairs(G.bombs) do
        if bomb.col == col and bomb.row == row then
            canPlace = false
            break
        end
    end

    if canPlace then
        local bomb = Bomb:new(col, row, true)
        table.insert(G.bombs, bomb)
        player:onBombPlaced(bomb)
    end
end

function playing.spawnExplosion(col, row)
    local explosion = Explosion:new(col, row, 2)
    table.insert(G.explosions, explosion)
end

function playing.draw()
    -- Clear background
    love.graphics.setColor(G.COLORS.BACKGROUND)
    love.graphics.rectangle("fill", 0, 0, G.SCREEN_WIDTH, G.SCREEN_HEIGHT)

    -- Draw grid
    Grid.draw(G.grid, G.COLORS)

    -- Draw explosions (under entities)
    for _, explosion in ipairs(G.explosions) do
        explosion:draw()
    end

    -- Draw bombs
    for _, bomb in ipairs(G.bombs) do
        bomb:draw()
    end

    -- Draw enemies
    for _, enemy in ipairs(G.enemies) do
        enemy:draw()
    end

    -- Draw player
    player:draw()

    -- Draw particles
    Particle.draw()

    -- HUD
    UI.drawHUD(levelData, G.currentScore, G.highScore)

    -- Level clear banner
    if levelClearTimer > 0 then
        UI.drawBanner("LEVEL CLEAR", G.COLORS.PLAYER)
    end

end

function playing.keypressed(key)
    if key == "escape" or key == "p" then
        StateMachine.switch("paused", {returnState = "playing"})
    end
end

function playing.touchpressed(id, x, y)
    Touch.touchpressed(id, x, y)
end

function playing.touchmoved(id, x, y)
    Touch.touchmoved(id, x, y)
end

function playing.touchreleased(id, x, y)
    Touch.touchreleased(id, x, y)
end

return playing
