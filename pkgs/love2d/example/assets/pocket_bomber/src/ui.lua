-- UI components

local G = require("src.globals")
local Colors = require("src.colors")

local ui = {}

function ui.drawButton(text, x, y, highlighted)
    local w = 200
    local h = 40

    if highlighted then
        love.graphics.setColor(Colors.BUTTON_HOVER)
    else
        love.graphics.setColor(Colors.BUTTON_BG)
    end

    love.graphics.rectangle("fill", x - w/2, y - h/2, w, h, 5, 5)
    love.graphics.setColor(Colors.TEXT)
    love.graphics.rectangle("line", x - w/2, y - h/2, w, h, 5, 5)

    love.graphics.setColor(Colors.TEXT)
    love.graphics.printf(text, x - w/2, y - 8, w, "center")
end

function ui.drawHUD(levelData, score, highScore)
    -- Level indicator
    love.graphics.setColor(Colors.TEXT)
    love.graphics.setNewFont(20)
    love.graphics.print("LEVEL " .. G.currentLevel .. "/5", 20, 20)

    -- Score
    love.graphics.print("SCORE: " .. score, 20, 50)

    -- High score
    love.graphics.setColor(Colors.HIGHLIGHT)
    love.graphics.print("HI: " .. highScore, 20, 80)

    -- Time remaining
    local timeColor = Colors.TEXT
    if levelData.timeRemaining < 30 then
        timeColor = Colors.EXPLOSION_CENTER
    end
    love.graphics.setColor(timeColor)
    love.graphics.print("TIME: " .. math.ceil(levelData.timeRemaining), G.SCREEN_WIDTH - 150, 20)

    -- Enemies remaining
    love.graphics.setColor(Colors.ENEMY_BASIC)
    love.graphics.print("ENEMIES: " .. #G.enemies, G.SCREEN_WIDTH - 150, 50)

    -- Reset font
    love.graphics.setNewFont(12)
end

function ui.drawBanner(text, color)
    local alpha = 0.9
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, G.SCREEN_HEIGHT/2 - 50, G.SCREEN_WIDTH, 100)

    love.graphics.setColor(color)
    love.graphics.setNewFont(48)
    love.graphics.printf(text, 0, G.SCREEN_HEIGHT/2 - 25, G.SCREEN_WIDTH, "center")

    love.graphics.setNewFont(12)
end

return ui
