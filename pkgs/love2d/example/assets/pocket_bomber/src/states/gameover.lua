-- Game over state

local G = require("src.globals")
local Colors = require("src.colors")
local StateMachine = require("src.state_machine")
local UI = require("src.ui")
local Save = require("src.save")

local gameover = {}

local finalScore = 0
local newHighScore = false
local won = false
local buttons = {}
local selectedButton = 1

function gameover.enter(params)
    finalScore = params.score or 0
    won = params.won or false

    -- Update high score
    local hs, isNew = Save.updateHighScore(finalScore)
    newHighScore = isNew
    G.highScore = hs

    buttons = {
        {text = "TRY AGAIN", action = function() G.currentScore = 0; StateMachine.switch("playing", {level = 1}) end, y = 380},
        {text = "MAIN MENU", action = function() G.currentScore = 0; StateMachine.switch("menu") end, y = 440}
    }

    selectedButton = 1
end

function gameover.update(dt)
    local mx, my = love.mouse.getPosition()
    mx, my = require("src.camera").toGame(mx, my)

    for i, btn in ipairs(buttons) do
        btn.hovered = mx >= 330 and mx <= 630 and my >= btn.y - 20 and my <= btn.y + 20
        if btn.hovered then
            selectedButton = i
        end
    end
end

function gameover.draw()
    -- Background
    love.graphics.setColor(G.COLORS.BACKGROUND)
    love.graphics.rectangle("fill", 0, 0, G.SCREEN_WIDTH, G.SCREEN_HEIGHT)

    -- Title
    if won then
        love.graphics.setColor(G.COLORS.PLAYER)
        love.graphics.setNewFont(36)
        love.graphics.printf("YOU WIN!", 0, 80, G.SCREEN_WIDTH, "center")

        love.graphics.setColor(G.COLORS.HIGHLIGHT)
        love.graphics.setNewFont(20)
        love.graphics.printf("ALL LEVELS CLEARED", 0, 130, G.SCREEN_WIDTH, "center")
    else
        love.graphics.setColor(G.COLORS.EXPLOSION_CENTER)
        love.graphics.setNewFont(36)
        love.graphics.printf("GAME OVER", 0, 80, G.SCREEN_WIDTH, "center")
    end

    -- Score display
    love.graphics.setColor(G.COLORS.TEXT)
    love.graphics.setNewFont(24)
    love.graphics.printf("FINAL SCORE: " .. finalScore, 0, 200, G.SCREEN_WIDTH, "center")

    -- High score
    if newHighScore then
        love.graphics.setColor(G.COLORS.HIGHLIGHT)
        love.graphics.setNewFont(20)
        love.graphics.printf("NEW HIGH SCORE!", 0, 250, G.SCREEN_WIDTH, "center")
    else
        love.graphics.setColor(G.COLORS.TEXT_DIM)
        love.graphics.setNewFont(16)
        love.graphics.printf("HIGH SCORE: " .. G.highScore, 0, 250, G.SCREEN_WIDTH, "center")
    end

    -- Buttons
    for i, btn in ipairs(buttons) do
        local isSelected = i == selectedButton
        UI.drawButton(btn.text, 480, btn.y, isSelected or btn.hovered)
    end

    -- Reset font
    love.graphics.setNewFont(12)
end

function gameover.keypressed(key)
    if key == "up" or key == "w" then
        selectedButton = selectedButton - 1
        if selectedButton < 1 then selectedButton = #buttons end
    elseif key == "down" or key == "s" then
        selectedButton = selectedButton + 1
        if selectedButton > #buttons then selectedButton = 1 end
    elseif key == "return" or key == "space" then
        buttons[selectedButton].action()
    end
end

function gameover.mousepressed(x, y, button)
    if button == 1 then
        x, y = require("src.camera").toGame(x, y)
        for _, btn in ipairs(buttons) do
            if x >= 330 and x <= 630 and y >= btn.y - 20 and y <= btn.y + 20 then
                btn.action()
            end
        end
    end
end

return gameover
