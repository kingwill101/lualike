local inGame = require("states/inGame")

local MainMenu = {
    delayAfterEnter = 0.5
}

local buttons = {}

local function newButton(text, fn)
    return {
        text = text,
        fn = fn,
        now = false,
        last = false
    }
end

local function addMenuButtons()
    buttons = {}
    
    table.insert(buttons, newButton(
        "Play",
        function()
            GameStateManager:setState(inGame)
        end
    ))

    table.insert(buttons, newButton(
        "Exit",
        function()
            love.event.quit()
        end
    ))
end

local logoSprite
local radialGradientShader
local sounds = {}

function MainMenu:enter()
    MainMenu.delay = MainMenu.delayAfterEnter
    local myFont = love.graphics.newFont(25)
    love.graphics.setFont(myFont)
    logoSprite = love.graphics.newImage("sprites/logo.png")

    radialGradientShader = love.graphics.newShader[[
        extern number innerRadius;
        extern number outerRadius;
        extern vec2 center;
        extern vec4 colorInner;
        extern vec4 colorOuter;

        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
        {
            number dist = distance(screen_coords, center);
            number t = smoothstep(innerRadius, outerRadius, dist);
            return mix(colorInner, colorOuter, t) * Texel(texture, texture_coords);
        }
    ]]
    radialGradientShader:send("innerRadius", love.graphics.getWidth() / 10)
    radialGradientShader:send("outerRadius", love.graphics.getWidth())
    radialGradientShader:send("center", {love.graphics.getWidth() / 2, love.graphics.getHeight() / 2})
    radialGradientShader:send("colorInner", {0.109803922, 0.109803922, 0.109803922, 1})  -- White center
    radialGradientShader:send("colorOuter", {0, 0, 0, 1})  -- Fades to black

    sounds["theme"] = love.audio.newSource("sounds/theme.mp3", "static")
    sounds["theme"]:play()
    sounds["theme"]:setLooping(true)

    addMenuButtons()
end

function MainMenu:update(dt)
    if MainMenu.delay and MainMenu.delay > 0 then
        MainMenu.delay = MainMenu.delay - dt
        return
    end

    -- Reset delay to nil to indicate the delay period is over
    MainMenu.delay = nil

    local x, y = love.mouse.getPosition()

    for i, button in ipairs(buttons) do
        button.last = button.now
        button.now = x > button.x and x < button.x + button.width and y > button.y and y < button.y + button.height

        if button.now and love.mouse.isDown(1)  then
            button.fn()
        end
    end
end 

local function drawRoundedRectWithOutline(x, y, width, height, borderRadius, fillColor, outlineColor, lineWidth)
    love.graphics.setColor(fillColor)

    love.graphics.rectangle("fill", x, y, width, height, borderRadius, borderRadius)

    love.graphics.setColor(outlineColor)
    love.graphics.setLineWidth(lineWidth or 2) 

    love.graphics.rectangle("line", x, y, width, height, borderRadius, borderRadius)

    love.graphics.setColor(1, 1, 1, 1)
end

function MainMenu:draw()
    love.graphics.setShader(radialGradientShader)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setShader()

    local windowWidth, windowHeight = love.graphics.getDimensions()
    local buttonWidth, buttonHeight = 200, 50
    local buttonSpacing = 15
    local totalHeight = (#buttons * (buttonHeight + buttonSpacing)) - buttonSpacing
    local startY = (windowHeight - totalHeight) / 2

    love.graphics.setColor(1, 1, 1)
    local logoScale = 0.5 -- Adjust as needed
    local logoWidth, logoHeight = logoSprite:getWidth() * logoScale, logoSprite:getHeight() * logoScale
    love.graphics.draw(logoSprite, (windowWidth - logoWidth) / 2, startY - logoHeight - 60, 0, logoScale, logoScale)

    for i, button in ipairs(buttons) do
        button.x = (windowWidth - buttonWidth) / 2
        button.y = startY + (i - 1) * (buttonHeight + buttonSpacing)
        button.width = buttonWidth
        button.height = buttonHeight

        local colorFill = {0.5, 0.5, 0.5, 1} -- Grey fill for a retro look
        local colorHover = {0.8, 0.8, 0.8, 1} -- Lighter grey when hovering

        -- Set the button fill color
        love.graphics.setColor(button.now and colorHover or colorFill)
        love.graphics.rectangle('fill', button.x, button.y, button.width, button.height)

        -- Set the text color and draw the text centered in the button
        love.graphics.setColor(0, 0, 0, 1) -- Black text
        local textWidth = love.graphics.getFont():getWidth(button.text)
        local textHeight = love.graphics.getFont():getHeight(button.text)
        love.graphics.print(button.text, button.x + (button.width - textWidth) / 2, button.y + (button.height - textHeight) / 2)
    end
end


return MainMenu