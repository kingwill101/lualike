-- Menu state

local G = require("src.globals")
local Colors = require("src.colors")
local Save = require("src.save")
local UI = require("src.ui")
local StateMachine = require("src.state_machine")

local menu = {}

-- Button state
local buttons = {}
local selectedButton = 1

function menu.enter()
    G.highScore = Save.loadHighScore()

    buttons = {
        {text = "PLAY", action = function() StateMachine.switch("playing", {level = 1}) end, y = 320},
        {text = "CONTROLS", action = function() end, y = 380},
        {text = "QUIT", action = function() love.event.quit() end, y = 440}
    }

    selectedButton = 1
end

function menu.update(dt)
    -- Button hover check
    local mx, my = love.mouse.getPosition()
    mx, my = require("src.camera").toGame(mx, my)

    for i, btn in ipairs(buttons) do
        btn.hovered = mx >= 380 and mx <= 580 and my >= btn.y - 20 and my <= btn.y + 20
        if btn.hovered then
            selectedButton = i
        end
    end
end

function menu.draw()
    -- Background
    love.graphics.setColor(G.COLORS.BACKGROUND)
    love.graphics.rectangle("fill", 0, 0, G.SCREEN_WIDTH, G.SCREEN_HEIGHT)

    -- Title
    love.graphics.setColor(G.COLORS.PLAYER)
    love.graphics.setNewFont(48)
    love.graphics.printf("POCKET BOMBER", 0, 80, G.SCREEN_WIDTH, "center")

    -- Subtitle
    love.graphics.setColor(G.COLORS.TEXT_DIM)
    love.graphics.setNewFont(16)
    love.graphics.printf("A BOMBERMAN-STYLE GAME", 0, 140, G.SCREEN_WIDTH, "center")

    -- High score
    love.graphics.setColor(G.COLORS.HIGHLIGHT)
    love.graphics.setNewFont(20)
    love.graphics.printf("HIGH SCORE: " .. G.highScore, 0, 200, G.SCREEN_WIDTH, "center")

    -- Buttons
    for i, btn in ipairs(buttons) do
        local isSelected = i == selectedButton
        UI.drawButton(btn.text, 480, btn.y, isSelected or btn.hovered)
    end

    -- Controls hint
    love.graphics.setColor(G.COLORS.TEXT)
    love.graphics.setNewFont(14)
    love.graphics.printf("ARROWS/WASD: Move    SPACE: Bomb    ESC/P: Pause", 0, 500, G.SCREEN_WIDTH, "center")

    -- Reset font
    love.graphics.setNewFont(12)
end

function menu.keypressed(key)
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

function menu.mousepressed(x, y, button)
    if button == 1 then
        x, y = require("src.camera").toGame(x, y)
        for _, btn in ipairs(buttons) do
            if x >= 380 and x <= 580 and y >= btn.y - 20 and y <= btn.y + 20 then
                btn.action()
            end
        end
    end
end

-- Touch support for mobile
local activeTouchId = nil

function menu.touchpressed(id, x, y)
    activeTouchId = id
    -- Check if touch is on any button
    for _, btn in ipairs(buttons) do
        if x >= 380 and x <= 580 and y >= btn.y - 20 and y <= btn.y + 20 then
            btn.action()
            return
        end
    end
end

function menu.touchreleased(id, x, y)
    if activeTouchId == id then
        activeTouchId = nil
    end
end

return menu
