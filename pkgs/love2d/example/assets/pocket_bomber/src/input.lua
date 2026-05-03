-- Unified input system for keyboard and touch

local G = require("src.globals")

local input = {}

-- Keyboard state tracking
local prevKeyState = {}
local currKeyState = {}

-- Touch state
input.touchJoystick = { x = 0, y = 0, active = false }
input.touchBomb = false
input.touchPause = false

function input.update()
    -- Store previous state
    for k, v in pairs(currKeyState) do
        prevKeyState[k] = v
    end

    -- Reset current state
    currKeyState = {}

    -- Keyboard input (movement)
    local dx, dy = 0, 0

    if love.keyboard.isDown("left", "a") then dx = -1 end
    if love.keyboard.isDown("right", "d") then dx = 1 end
    if love.keyboard.isDown("up", "w") then dy = -1 end
    if love.keyboard.isDown("down", "s") then dy = 1 end

    -- Normalize diagonal movement
    if dx ~= 0 and dy ~= 0 then
        local len = math.sqrt(dx * dx + dy * dy)
        dx = dx / len
        dy = dy / len
    end

    -- Combine with touch joystick
    if input.touchJoystick.active then
        dx = input.touchJoystick.x
        dy = input.touchJoystick.y
    end

    -- Store as cardinal direction (no diagonals for grid movement)
    G.input.dx, G.input.dy = 0, 0
    if math.abs(dx) > math.abs(dy) then
        G.input.dx = dx > 0 and 1 or -1
    elseif math.abs(dy) > 0 then
        G.input.dy = dy > 0 and 1 or -1
    end

    -- Bomb button
    G.input.bombPressed = love.keyboard.isDown("space", "z", "j") or input.touchBomb

    -- Pause button
    G.input.pausePressed = love.keyboard.isDown("escape", "p") or input.touchPause
end

function input.keypressed(key)
    currKeyState[key] = true
end

function input.keyjustPressed(key)
    return currKeyState[key] and not prevKeyState[key]
end

function input.setTouchJoystick(x, y, active)
    input.touchJoystick.x = x
    input.touchJoystick.y = y
    input.touchJoystick.active = active
end

function input.setTouchBomb(pressed)
    input.touchBomb = pressed
end

function input.setTouchPause(pressed)
    input.touchPause = pressed
end

return input
