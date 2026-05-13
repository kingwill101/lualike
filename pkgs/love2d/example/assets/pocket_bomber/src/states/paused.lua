-- Paused state

local G = require("src.globals")
local Colors = require("src.colors")
local StateMachine = require("src.state_machine")
local UI = require("src.ui")

local paused = {}

local returnState = nil
local buttons = {}
local selectedButton = 1

function paused.enter(params)
    returnState = params.returnState or "playing"

    buttons = {
        {text = "RESUME", action = function() StateMachine.switch(returnState) end, y = 250},
        {text = "RESTART LEVEL", action = function() StateMachine.switch("playing", {level = G.currentLevel}) end, y = 310},
        {text = "QUIT TO MENU", action = function() StateMachine.switch("menu") end, y = 370}
    }

    selectedButton = 1
end

function paused.update(dt)
    local mx, my = love.mouse.getPosition()
    mx, my = require("src.camera").toGame(mx, my)

    for i, btn in ipairs(buttons) do
        btn.hovered = mx >= 330 and mx <= 630 and my >= btn.y - 20 and my <= btn.y + 20
        if btn.hovered then
            selectedButton = i
        end
    end
end

function paused.draw()
    -- Draw the game state behind (dimmed)
    local currentState = StateMachine.getCurrent()
    if returnState == "playing" then
        -- We need to draw the playing state manually since we're paused
        -- For now just draw a dark overlay
    end

    -- Dark overlay
    love.graphics.setColor(G.COLORS.PAUSE_OVERLAY)
    love.graphics.rectangle("fill", 0, 0, G.SCREEN_WIDTH, G.SCREEN_HEIGHT)

    -- Title
    love.graphics.setColor(G.COLORS.TEXT)
    love.graphics.setNewFont(36)
    love.graphics.printf("PAUSED", 0, 120, G.SCREEN_WIDTH, "center")

    -- Buttons
    for i, btn in ipairs(buttons) do
        local isSelected = i == selectedButton
        UI.drawButton(btn.text, 480, btn.y, isSelected or btn.hovered)
    end

    -- Reset font
    love.graphics.setNewFont(12)
end

function paused.keypressed(key)
    if key == "up" or key == "w" then
        selectedButton = selectedButton - 1
        if selectedButton < 1 then selectedButton = #buttons end
    elseif key == "down" or key == "s" then
        selectedButton = selectedButton + 1
        if selectedButton > #buttons then selectedButton = 1 end
    elseif key == "return" or key == "space" then
        buttons[selectedButton].action()
    elseif key == "escape" then
        StateMachine.switch(returnState)
    end
end

function paused.mousepressed(x, y, button)
    if button == 1 then
        x, y = require("src.camera").toGame(x, y)
        for _, btn in ipairs(buttons) do
            if x >= 330 and x <= 630 and y >= btn.y - 20 and y <= btn.y + 20 then
                btn.action()
            end
        end
    end
end

return paused
