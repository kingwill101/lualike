-- Deterministic source-identical curve probe for native LOVE and Flutter GPU.

local columns = { 140, 400, 660 }
local widths = { 1, 2, 3 }

local function panel(center_x, top, title)
  love.graphics.setColor(0.05, 0.10, 0.20, 0.55)
  love.graphics.rectangle("fill", center_x - 110, top, 220, 230, 8, 8)
  love.graphics.setColor(0.18, 0.66, 0.88, 0.32)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", center_x - 110, top, 220, 230, 8, 8)
  love.graphics.setColor(0.54, 0.82, 0.94, 0.86)
  love.graphics.printf(title, center_x - 100, top + 10, 200, "center")
end

function love.load()
  love.graphics.setBackgroundColor(0.012, 0.018, 0.042)
  love.graphics.setLineStyle("rough")
end

function love.update(_)
end

function love.draw()
  love.graphics.setColor(0.68, 0.86, 0.96, 0.92)
  love.graphics.print("LOVE 11.5 GENERATED CURVE PROBE", 24, 18)
  love.graphics.setColor(0.42, 0.72, 0.86, 0.84)
  love.graphics.print("Default segment counts / rough line style", 24, 47)

  for index = 1, 3 do
    local center_x = columns[index]
    local width = widths[index]
    local radius = 48 + math.sin(index * 0.9) * 2
    panel(center_x, 78, "CIRCLE / WIDTH " .. width)
    panel(center_x, 334, "OPEN ARC / WIDTH " .. width)

    love.graphics.setLineWidth(width)
    love.graphics.setColor(0.96, 0.18, 0.72, 0.72)
    love.graphics.circle("line", center_x, 202, radius)

    love.graphics.setColor(0.24, 0.92, 1.0, 0.72)
    love.graphics.arc("line", "open", center_x, 458, radius, -0.62, 4.76)
  end
end
