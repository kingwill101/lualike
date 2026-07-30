local state = {
  status = "booting",
  dt = 0,
}

function love.load()
  state.status = "loaded"
end

function love.update(dt)
  state.dt = dt
  state.status = "updated"
end

function love.draw()
  love.graphics.clear(0.06, 0.07, 0.10, 1.0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Hello, LuaLike", 20, 20)
  love.graphics.print(state.status, 20, 44)
end
