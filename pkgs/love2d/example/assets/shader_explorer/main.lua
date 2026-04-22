local App = require("src.app")

function love.load(args)
  App.load(args)
end

function love.update(dt)
  App.update(dt)
end

function love.draw()
  App.draw()
end

function love.keypressed(key)
  App.keypressed(key)
end

function love.mousemoved(x, y, dx, dy, istouch)
  App.mousemoved(x, y, dx, dy, istouch)
end

function love.wheelmoved(x, y)
  App.wheelmoved(x, y)
end

function love.resize(w, h)
  App.resize(w, h)
end
