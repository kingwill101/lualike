-- Deterministic native/Canvas/GPU probe for printf and Text:setf. Keep this
-- source free of animation and host input so exact 800x600 captures compare.

local columns = {
  {x = 40, align = "left"},
  {x = 300, align = "center"},
  {x = 560, align = "right"},
}
local wrap_width = 200
local wrapped = "ALPHA BETA GAMMA DELTA EPSILON ZETA"
local explicit_lines = "FIRST LINE\nSECOND LINE\nTHIRD LINE"
local colored = {
  {1.0, 0.34, 0.66, 1.0},
  "PINK ",
  {0.28, 0.92, 1.0, 1.0},
  "CYAN WORDS ",
  {0.72, 1.0, 0.48, 1.0},
  "WRAP IN COLOR",
}
local text_objects = {}

function love.load()
  love.graphics.setBackgroundColor(0.012, 0.018, 0.042)
  local font = love.graphics.getFont()
  for index, column in ipairs(columns) do
    local text = love.graphics.newText(font)
    text:setf(colored, wrap_width, column.align)
    text_objects[index] = text
  end
end

function love.keypressed(key)
  -- The shared capture harness presses v to establish a deterministic frame.
end

local function guides(y, height)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.16, 0.34, 0.48, 0.72)
  for _, column in ipairs(columns) do
    love.graphics.rectangle("line", column.x, y, wrap_width, height)
  end
end

function love.draw()
  love.graphics.setColor(0.74, 0.94, 1.0, 1.0)
  love.graphics.print("LOVE 11.5 FORMATTED ATLAS TEXT PROBE", 40, 22)
  for _, column in ipairs(columns) do
    love.graphics.setColor(0.52, 0.72, 0.86, 1.0)
    love.graphics.print(string.upper(column.align), column.x, 54)
  end

  guides(80, 66)
  love.graphics.setColor(0.82, 0.94, 1.0, 1.0)
  for _, column in ipairs(columns) do
    love.graphics.printf(wrapped, column.x, 84, wrap_width, column.align)
  end

  guides(174, 66)
  love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
  for _, column in ipairs(columns) do
    love.graphics.printf(colored, column.x, 178, wrap_width, column.align)
  end

  guides(268, 66)
  love.graphics.setColor(0.84, 0.72, 1.0, 1.0)
  for _, column in ipairs(columns) do
    love.graphics.printf(
      explicit_lines,
      column.x,
      272,
      wrap_width,
      column.align
    )
  end

  guides(362, 66)
  love.graphics.setColor(0.90, 0.96, 1.0, 0.88)
  for index, column in ipairs(columns) do
    love.graphics.draw(text_objects[index], column.x, 366)
  end

  love.graphics.setColor(0.46, 0.66, 0.78, 1.0)
  love.graphics.print(
    "PRINTF WRAP / ALIGN / COLORED SPANS / EXPLICIT NEWLINES / TEXT:SETF",
    40,
    470
  )
end
