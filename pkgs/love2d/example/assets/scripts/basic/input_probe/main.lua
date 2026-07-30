testbed = {
  key = nil,
  mouse = nil,
  touch = nil,
  draws = 0,
}

function love.keypressed(key)
  testbed.key = key
end

function love.mousepressed(x, y, button)
  testbed.mouse = {
    x = x,
    y = y,
    button = button,
  }
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  testbed.touch = {
    id = id,
    x = x,
    y = y,
    pressure = pressure,
  }
end

function love.draw()
  testbed.draws = testbed.draws + 1
  love.graphics.clear(0.08, 0.08, 0.12, 1.0)
  love.graphics.print("Input probe", 20, 20)
end
