-- Virtual joystick and buttons for touch controls (floating joystick pattern)

local G = require("src.globals")
local Colors = require("src.colors")
local Input = require("src.input")
local Camera = require("src.camera")

local touch = {}

-- Check if we're on mobile
function touch.isMobile()
    local os = love.system.getOS()
    return os == "iOS" or os == "Android"
end

-- Joystick settings (floating pattern - appears where you touch)
touch.joystick = {
    active = false,
    touchId = nil,
    baseX = 0,
    baseY = 0,
    knobX = 0,
    knobY = 0,
    radius = 60,
    knobRadius = 25,
    deadzone = 0.15,
    dx = 0,
    dy = 0
}

-- Button settings (positioned relative to screen size)
touch.bombButton = {
    x = 0,  -- Set in updatePositions
    y = 0,
    radius = 55,
    touchId = nil,
    active = false,
    pulse = 0  -- For pulsing animation
}

touch.pauseButton = {
    x = 0,  -- Set in updatePositions
    y = 0,
    radius = 35,
    touchId = nil,
    active = false
}

-- Update button positions based on screen size
function touch.updatePositions()
    local screenW, screenH = Camera.getGameDimensions()

    -- Bomb button - bottom right
    touch.bombButton.x = screenW - 100
    touch.bombButton.y = screenH - 100

    -- Pause button - top right
    touch.pauseButton.x = screenW - 60
    touch.pauseButton.y = 60
end

function touch.update(dt)
    -- Update positions in case screen size changed
    touch.updatePositions()

    -- Update input module with joystick values
    if touch.joystick.active then
        -- Apply deadzone
        local dist = math.sqrt(touch.joystick.dx^2 + touch.joystick.dy^2)
        if dist < touch.joystick.deadzone then
            Input.setTouchJoystick(0, 0, false)
        else
            -- Remap to full range
            local scale = (dist - touch.joystick.deadzone) / (1 - touch.joystick.deadzone)
            local nx = (touch.joystick.dx / dist) * scale
            local ny = (touch.joystick.dy / dist) * scale
            Input.setTouchJoystick(nx, ny, true)
        end
    else
        Input.setTouchJoystick(0, 0, false)
    end

    -- Update bomb button
    Input.setTouchBomb(touch.bombButton.touchId ~= nil)

    -- Update bomb button pulse animation
    touch.bombButton.pulse = touch.bombButton.pulse + dt * 3
    if touch.bombButton.pulse > math.pi * 2 then
        touch.bombButton.pulse = touch.bombButton.pulse - math.pi * 2
    end

    -- Update pause button (only trigger on new press)
    if touch.pauseButton.touchId and not touch.pauseButton.active then
        Input.setTouchPause(true)
        touch.pauseButton.active = true
    else
        Input.setTouchPause(false)
    end
end

local function pointInCircle(px, py, cx, cy, r)
    local dx = px - cx
    local dy = py - cy
    return (dx * dx + dy * dy) <= (r * r)
end

function touch.touchpressed(id, x, y)
    -- Check bomb button first (higher priority)
    if pointInCircle(x, y, touch.bombButton.x, touch.bombButton.y, touch.bombButton.radius * 1.3) then
        if not touch.bombButton.touchId then
            touch.bombButton.touchId = id
            return
        end
    end

    -- Check pause button
    if pointInCircle(x, y, touch.pauseButton.x, touch.pauseButton.y, touch.pauseButton.radius * 1.3) then
        if not touch.pauseButton.touchId then
            touch.pauseButton.touchId = id
            touch.pauseButton.active = false  -- Will trigger on next update
            return
        end
    end

    -- Left side of screen = joystick zone (floating joystick)
    -- Note: Joystick should not be spawned if touch was already consumed by menu/UI
    local screenW = Camera.getGameDimensions()
    if x < screenW / 2 and not touch.joystick.touchId then
        touch.joystick.active = true
        touch.joystick.touchId = id
        touch.joystick.baseX = x
        touch.joystick.baseY = y
        touch.joystick.knobX = x
        touch.joystick.knobY = y
        touch.joystick.dx = 0
        touch.joystick.dy = 0
    end
end

function touch.touchmoved(id, x, y)
    if touch.joystick.touchId == id then
        local dx = x - touch.joystick.baseX
        local dy = y - touch.joystick.baseY
        local dist = math.sqrt(dx * dx + dy * dy)
        local maxDist = touch.joystick.radius

        if dist > maxDist then
            dx = dx / dist * maxDist
            dy = dy / dist * maxDist
        end

        touch.joystick.knobX = touch.joystick.baseX + dx
        touch.joystick.knobY = touch.joystick.baseY + dy

        if dist > 0 then
            touch.joystick.dx = dx / maxDist
            touch.joystick.dy = dy / maxDist
        else
            touch.joystick.dx = 0
            touch.joystick.dy = 0
        end
    end
end

function touch.touchreleased(id, x, y)
    if touch.joystick.touchId == id then
        touch.joystick.active = false
        touch.joystick.touchId = nil
        touch.joystick.dx = 0
        touch.joystick.dy = 0
    end
    if touch.bombButton.touchId == id then
        touch.bombButton.touchId = nil
    end
    if touch.pauseButton.touchId == id then
        touch.pauseButton.touchId = nil
        touch.pauseButton.active = false
    end
end

function touch.draw()
    -- Only draw on mobile or if explicitly enabled
    if not touch.isMobile() then return end

    -- Only show game controls during gameplay (not in menu)
    local StateMachine = require("src.state_machine")
    local currentState = StateMachine.getCurrent()
    local MenuState = require("src.states.menu")
    if currentState == MenuState then return end

    -- Update positions before drawing
    touch.updatePositions()

    -- Draw joystick (only when active)
    if touch.joystick.active then
        -- Base circle (semi-transparent)
        love.graphics.setColor(Colors.BUTTON_BG[1], Colors.BUTTON_BG[2], Colors.BUTTON_BG[3], 0.4)
        love.graphics.circle("fill", touch.joystick.baseX, touch.joystick.baseY, touch.joystick.radius)
        love.graphics.setColor(Colors.TEXT[1], Colors.TEXT[2], Colors.TEXT[3], 0.5)
        love.graphics.circle("line", touch.joystick.baseX, touch.joystick.baseY, touch.joystick.radius)

        -- Knob
        love.graphics.setColor(Colors.HIGHLIGHT[1], Colors.HIGHLIGHT[2], Colors.HIGHLIGHT[3], 0.9)
        love.graphics.circle("fill", touch.joystick.knobX, touch.joystick.knobY, touch.joystick.knobRadius)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.circle("line", touch.joystick.knobX, touch.joystick.knobY, touch.joystick.knobRadius)
    end

    -- Draw bomb button with pulsing effect and bomb icon
    local bombPressed = touch.bombButton.touchId ~= nil
    local pulseScale = 1 + math.sin(touch.bombButton.pulse) * 0.08

    -- Outer glow ring (pulsing)
    local glowColor = {Colors.EXPLOSION_CENTER[1], Colors.EXPLOSION_CENTER[2], Colors.EXPLOSION_CENTER[3]}
    love.graphics.setColor(glowColor[1], glowColor[2], glowColor[3], 0.3)
    love.graphics.circle("fill", touch.bombButton.x, touch.bombButton.y, touch.bombButton.radius * pulseScale * 1.3)

    -- Main button circle
    local bombColor = bombPressed and Colors.EXPLOSION_CENTER or Colors.BOMB_LIT
    love.graphics.setColor(bombColor[1], bombColor[2], bombColor[3], bombPressed and 1.0 or 0.85)
    love.graphics.circle("fill", touch.bombButton.x, touch.bombButton.y, touch.bombButton.radius)

    -- Inner highlight
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("fill", touch.bombButton.x - 15, touch.bombButton.y - 15, touch.bombButton.radius * 0.4)

    -- Thick border
    love.graphics.setColor(Colors.EXPLOSION_CENTER[1], Colors.EXPLOSION_CENTER[2], Colors.EXPLOSION_CENTER[3], 1.0)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", touch.bombButton.x, touch.bombButton.y, touch.bombButton.radius)
    love.graphics.setLineWidth(1)

    -- Bomb icon (fuse + body)
    love.graphics.setColor(0.1, 0.1, 0.1, 1.0)
    -- Bomb body
    love.graphics.circle("fill", touch.bombButton.x, touch.bombButton.y + 5, 22)
    -- Bomb fuse
    love.graphics.setLineWidth(3)
    love.graphics.line(touch.bombButton.x, touch.bombButton.y - 10, touch.bombButton.x + 8, touch.bombButton.y - 22)
    love.graphics.setLineWidth(1)
    -- Spark on fuse (pulsing)
    local sparkSize = 4 + math.sin(touch.bombButton.pulse * 2) * 2
    love.graphics.setColor(1, 0.8, 0.2, 1.0)
    love.graphics.circle("fill", touch.bombButton.x + 8, touch.bombButton.y - 22, sparkSize)

    -- BOMB label below the icon
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("BOMB", touch.bombButton.x - 60, touch.bombButton.y + 35, 120, "center")

    -- Draw pause button
    local pausePressed = touch.pauseButton.touchId ~= nil
    local pauseColor = pausePressed and Colors.BUTTON_HOVER or Colors.BUTTON_BG
    love.graphics.setColor(pauseColor[1], pauseColor[2], pauseColor[3], pausePressed and 0.9 or 0.6)
    love.graphics.circle("fill", touch.pauseButton.x, touch.pauseButton.y, touch.pauseButton.radius)
    love.graphics.setColor(Colors.TEXT[1], Colors.TEXT[2], Colors.TEXT[3], 0.8)
    love.graphics.circle("line", touch.pauseButton.x, touch.pauseButton.y, touch.pauseButton.radius)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("||", touch.pauseButton.x - 20, touch.pauseButton.y - 10, 40, "center")
end

return touch
