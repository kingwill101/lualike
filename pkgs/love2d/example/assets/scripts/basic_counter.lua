local state = {
  count = 0,
}

function love.load()
  testbed = state
end

function love.update(dt)
  state.count = state.count + 1
end

function love.draw()
  love.graphics.clear(0.04, 0.05, 0.08, 1.0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Tick count: " .. state.count, 20, 20)
end
