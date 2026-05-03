-- Pocket Bomber - A Bomberman-style game for LÖVE 11.5

local G = require("src.globals")
local Colors = require("src.colors")
local Camera = require("src.camera")
local Input = require("src.input")
local Touch = require("src.touch_controls")
local StateMachine = require("src.state_machine")

-- State modules
local MenuState = require("src.states.menu")
local PlayingState = require("src.states.playing")
local PausedState = require("src.states.paused")
local GameOverState = require("src.states.gameover")

function love.load()
    -- Initialize globals
    G.COLORS = Colors
    G.highScore = 0
    G.currentScore = 0
    G.currentLevel = 1

    -- Initialize camera
    Camera.update(love.graphics.getDimensions())

    -- Register game states
    StateMachine.register("menu", MenuState)
    StateMachine.register("playing", PlayingState)
    StateMachine.register("paused", PausedState)
    StateMachine.register("gameover", GameOverState)

    -- Start at menu
    StateMachine.switch("menu")
end

function love.update(dt)
    -- Cap dt to prevent huge jumps
    if dt > 0.1 then dt = 0.1 end

    -- Update input
    Input.update()

    -- Update touch controls
    Touch.update(dt)

    -- Update current state
    StateMachine.update(dt)
end

function love.draw()
    -- Apply camera transform
    Camera.apply()

    -- Draw current state
    StateMachine.draw()

    -- Remove camera transform
    Camera.remove()

    -- Draw touch controls on top (for mobile)
    Touch.draw()
end

function love.resize(w, h)
    Camera.update(w, h)
end

function love.keypressed(key)
    Input.keypressed(key)
    StateMachine.keypressed(key)
end

function love.keyreleased(key)
    StateMachine.keyreleased(key)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    x, y = Camera.toGame(x, y)
    -- Let state handle touch first (for menu buttons, etc.)
    StateMachine.touchpressed(id, x, y)
    -- Then pass to touch controls (joystick/buttons)
    Touch.touchpressed(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    x, y = Camera.toGame(x, y)
    Touch.touchmoved(id, x, y)
    StateMachine.touchmoved(id, x, y)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    x, y = Camera.toGame(x, y)
    Touch.touchreleased(id, x, y)
    StateMachine.touchreleased(id, x, y)
end

function love.mousepressed(x, y, button)
    x, y = Camera.toGame(x, y)
    local state = StateMachine.getCurrent()
    if state and state.mousepressed then
        state.mousepressed(x, y, button)
    end
end
