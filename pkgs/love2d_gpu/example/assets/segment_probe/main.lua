-- Isolates LOVE's default circle point count at the radius used by enemy 5.

local radius = 26 + 18 + math.sin(0.4) * 2
local centers = { 84, 242, 400, 558, 716 }
local counts = { false, 28, 29, 30, 31 }
local rectangle_counts = { false, 8, 12, 16, 20 }

function love.load()
  love.graphics.setBackgroundColor(0.015, 0.02, 0.05)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)
end

function love.update(_)
end

function love.draw()
  love.graphics.setColor(0.68, 0.86, 0.96, 0.92)
  love.graphics.print("LOVE 11.5 SEGMENT BOUNDARY PROBE", 24, 18)
  love.graphics.setColor(0.42, 0.72, 0.86, 0.84)
  love.graphics.print("radius = 26 + 18 + sin(0.4) * 2", 24, 47)

  for index = 1, #centers do
    local center_x = centers[index]
    local count = counts[index]
    love.graphics.setColor(0.05, 0.10, 0.20, 0.55)
    love.graphics.rectangle("fill", center_x - 70, 110, 140, 190, 8, 8)
    love.graphics.setColor(0.18, 0.66, 0.88, 0.32)
    love.graphics.rectangle("line", center_x - 70, 110, 140, 190, 8, 8)
    love.graphics.setColor(0.54, 0.82, 0.94, 0.86)
    love.graphics.printf(count and (count .. " points") or "default", center_x - 65, 128, 130, "center")
    love.graphics.setColor(1.0, 0.36, 0.68, 0.55)
    if count then
      love.graphics.circle("line", center_x, 220, radius, count)
    else
      love.graphics.circle("line", center_x, 220, radius)
    end
  end

  love.graphics.setColor(0.42, 0.72, 0.86, 0.84)
  love.graphics.print("Rounded rectangle point-count division", 24, 336)
  for index = 1, #centers do
    local center_x = centers[index]
    local count = rectangle_counts[index]
    love.graphics.setColor(0.54, 0.82, 0.94, 0.86)
    love.graphics.printf(count and (count .. " points") or "default", center_x - 65, 370, 130, "center")
    love.graphics.setColor(0.24, 0.92, 1.0, 0.72)
    if count then
      love.graphics.rectangle("line", center_x - 52, 410, 104, 70, 20, 14, count)
    else
      love.graphics.rectangle("line", center_x - 52, 410, 104, 70, 20, 14)
    end
  end
end
