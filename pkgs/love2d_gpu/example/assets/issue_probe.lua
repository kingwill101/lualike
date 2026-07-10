local checker_texture = nil
local sprite_batch = nil
local textured_mesh = nil
local elapsed = 0

local function make_checker_data()
  local data = love.image.newImageData(64, 64)
  for y = 0, 63 do
    for x = 0, 63 do
      local c = ((math.floor(x / 8) + math.floor(y / 8)) % 2 == 0) and 0.88 or 0.15
      data:setPixel(x, y, c * 0.7, c * 0.75, c, 1.0)
    end
  end
  return data
end

function love.load()
  love.graphics.setBackgroundColor(0.05, 0.05, 0.08)
  love.graphics.setDefaultFilter("nearest", "nearest")

  checker_texture = love.graphics.newImage(make_checker_data())

  sprite_batch = love.graphics.newSpriteBatch(checker_texture, 16)
  for y = 0, 1 do
    for x = 0, 3 do
      sprite_batch:add(380 + x * 70, 120 + y * 70, 0, 0.7, 0.7, 32, 32)
    end
  end

  local vf = {
    {"VertexPosition", "float", 2},
    {"VertexTexCoord", "float", 2},
    {"VertexColor", "float", 4},
  }
  textured_mesh = love.graphics.newMesh(vf, {
    {0, 0, 0, 0, 1, 1, 1, 1},
    {96, 0, 1, 0, 1, 1, 1, 1},
    {96, 96, 1, 1, 1, 1, 1, 1},
    {0, 96, 0, 1, 1, 1, 1, 1},
  }, "fan")
  textured_mesh:setTexture(checker_texture)
end

function love.update(dt)
  elapsed = elapsed + dt
end

function love.draw()
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("issue probe: isolated textured paths", 20, 16)

  -- Direct image draw.
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("line", 20, 40, 280, 220)
  love.graphics.print("direct image draw", 28, 48)
  love.graphics.draw(checker_texture, 40, 80, 0, 3, 3)

  -- SpriteBatch draw.
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("line", 340, 40, 300, 220)
  love.graphics.print("sprite batch", 348, 48)
  love.graphics.draw(sprite_batch, 0, 0)

  -- Textured mesh draw.
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("line", 660, 40, 260, 220)
  love.graphics.print("textured mesh", 668, 48)
  love.graphics.push()
  love.graphics.translate(710, 120)
  love.graphics.rotate(elapsed * 0.8)
  love.graphics.translate(-48, -48)
  love.graphics.draw(textured_mesh, 0, 0)
  love.graphics.pop()

  -- Baseline shapes.
  love.graphics.setColor(0.95, 0.95, 0.95)
  love.graphics.rectangle("line", 20, 300, 180, 90)
  love.graphics.rectangle("fill", 230, 300, 180, 90)

  -- Extra obvious marker.
  love.graphics.setColor(1, 0.8, 0.1)
  love.graphics.circle("line", 520, 345, 36)
end
