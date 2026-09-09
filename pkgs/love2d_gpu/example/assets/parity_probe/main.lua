-- Deterministic native/Canvas/GPU probe for pixel-corner lines and the
-- built-in LOVE font. Keep this source free of animation and host input.

local function grid(origin_x, origin_y, half_pixel)
  local offset = half_pixel and 0.5 or 0
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.10, 0.72, 0.95, 0.62)
  for coordinate = 0, 320, 20 do
    love.graphics.line(
      origin_x + coordinate + offset,
      origin_y + offset,
      origin_x + coordinate + offset,
      origin_y + 240 + offset
    )
  end
  for coordinate = 0, 240, 20 do
    love.graphics.line(
      origin_x + offset,
      origin_y + coordinate + offset,
      origin_x + 320 + offset,
      origin_y + coordinate + offset
    )
  end
end

local function stroke_samples()
  love.graphics.setLineStyle("rough")
  for width = 1, 3 do
    love.graphics.setLineWidth(width)
    love.graphics.setColor(0.96, 0.22 + width * 0.12, 0.72, 0.92)
    local y = 358 + width * 22
    love.graphics.line(40, y, 360, y)
    love.graphics.line(440, y, 760, y + width * 4)
  end

  love.graphics.setLineStyle("smooth")
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.24, 0.94, 1.0, 0.90)
  love.graphics.line(40, 454, 360, 454)
  love.graphics.line(440, 454.5, 760, 454.5)
end

function love.load()
  love.graphics.setBackgroundColor(0.012, 0.018, 0.042)
end

function love.keypressed(key)
  -- The shared capture harness presses v to establish a deterministic frame.
end

function love.draw()
  love.graphics.setColor(0.74, 0.94, 1.0, 1.0)
  love.graphics.print("LOVE 11.5 PIXEL-CORNER / DEFAULT-FONT PROBE", 40, 24)
  love.graphics.setColor(0.52, 0.72, 0.86, 1.0)
  love.graphics.print("INTEGER ROUGH GRID", 40, 52)
  love.graphics.print("HALF-PIXEL ROUGH GRID", 440, 52)

  love.graphics.setLineStyle("rough")
  grid(40, 80, false)
  grid(440, 80, true)
  stroke_samples()

  love.graphics.setColor(0.82, 0.94, 1.0, 1.0)
  love.graphics.print("DEFAULT  AaBb  0123456789  /\\[]{}", 40, 486)
  love.graphics.setColor(1.0, 0.38, 0.72, 1.0)
  love.graphics.printf("LEFT", 40, 516, 200, "left")
  love.graphics.printf("CENTER", 300, 516, 200, "center")
  love.graphics.printf("RIGHT", 560, 516, 200, "right")

  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.36, 0.82, 1.0, 0.72)
  love.graphics.rectangle("line", 20, 12, 760, 560)
end
