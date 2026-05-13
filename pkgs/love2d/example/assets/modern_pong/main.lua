GameStateManager = require("libs/gamestateManager")
local MainMenu = require("states/mainMenu")

function love.load()
    GameStateManager:setState(MainMenu)
end

function love.update(dt)   
    GameStateManager:update(dt)
end

function love.keypressed(key, scancode, isrepeat)
    GameStateManager:keypressed(key, scancode, isrepeat)
end

function love.draw()
    GameStateManager:draw()
end