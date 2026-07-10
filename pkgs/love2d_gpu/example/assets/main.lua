local elapsed = 0
local frame_count = 0
local fps = 0
local fps_timer = 0

local checker_texture = nil
local sprite_batch = nil
local mesh = nil

function love.load()
  love.graphics.setBackgroundColor(0.04, 0.04, 0.08)

  -- Programmatic checkerboard texture
  local data = love.image.newImageData(64, 64)
  for y = 0, 63 do
    for x = 0, 63 do
      local cx = math.floor(x / 8) % 2
      local cy = math.floor(y / 8) % 2
      local c = (cx ~ cy) and 0.85 or 0.12
      data:setPixel(x, y, c * 0.7, c * 0.75, c, 1.0)
    end
  end
  checker_texture = love.graphics.newImage(data)

  -- Sprite batch showing the checkerboard as a grid of small tiles
  sprite_batch = love.graphics.newSpriteBatch(checker_texture, 64)
  for i = 0, 7 do
    for j = 0, 7 do
      sprite_batch:add(
        j * 40 + 520, i * 40 + 250,
        0,      -- rotation
        0.5, 0.5, -- scale
        32, 32,  -- origin
        0, 0     -- shear
      )
    end
  end

  -- Colored triangle mesh
  local vf = {
    {"VertexPosition", "float", 2},
    {"VertexColor", "float", 4},
  }
  mesh = love.graphics.newMesh(vf, {
    {0, -60,  1.0, 0.2, 0.2, 1.0},
    {-52, 40, 0.2, 1.0, 0.2, 1.0},
    {52, 40,  0.2, 0.2, 1.0, 1.0},
  }, "fan")
end

function love.update(dt)
  elapsed = elapsed + dt
  frame_count = frame_count + 1
  fps_timer = fps_timer + dt
  if fps_timer >= 0.5 then
    fps = frame_count / fps_timer
    frame_count = 0
    fps_timer = 0
  end
end

function love.draw()
  love.graphics.push()
  love.graphics.translate(30, 30)
  love.graphics.setColor(0.25, 0.80, 0.95)
  love.graphics.rectangle("fill", 0, 0, 180, 130)

  love.graphics.setColor(0.95, 0.30, 0.30)
  love.graphics.circle("fill", 280, 65, 65)

  love.graphics.setColor(0.30, 0.90, 0.40)
  love.graphics.ellipse("fill", 460, 65, 80, 50)
  love.graphics.pop()

  -- Border
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("line", 1, 1, love.graphics.getWidth() - 2, love.graphics.getHeight() - 2)

  -- Dashed circle outline
  love.graphics.setColor(1.0, 0.6, 0.0, 0.6)
  love.graphics.circle("line", 600, 95, 55)

  -- Animated rotating bar
  love.graphics.push()
  love.graphics.translate(120, 230)
  love.graphics.rotate(elapsed * 0.5)
  love.graphics.setColor(0.6, 0.2, 0.8)
  love.graphics.rectangle("fill", -60, -10, 120, 20)
  love.graphics.pop()

  -- Pulsating circle
  love.graphics.push()
  love.graphics.translate(310, 230)
  local pulse = 0.5 + 0.5 * math.sin(elapsed * 3.0)
  love.graphics.scale(pulse, pulse)
  love.graphics.setColor(0.8, 0.2, 0.5, 0.8)
  love.graphics.circle("fill", 0, 0, 50)
  love.graphics.pop()

  -- Spinning squares trail
  for i = 0, 5 do
    love.graphics.push()
    love.graphics.translate(470 + i * 26, 190 + i * 18)
    love.graphics.rotate(elapsed + i * 0.8)
    love.graphics.setColor(0.2 + i * 0.12, 0.8 - i * 0.1, 0.6 + i * 0.05, 0.6)
    love.graphics.rectangle("fill", -12, -12, 24, 24)
    love.graphics.pop()
  end

  -- Polygon shapes
  love.graphics.setColor(0.7, 0.3, 1.0, 0.8)
  love.graphics.polygon("line", 30, 330, 80, 300, 130, 340, 100, 380, 50, 370)

  love.graphics.setColor(0.3, 1.0, 0.7, 0.4)
  love.graphics.polygon("fill", 170, 330, 220, 300, 270, 340, 240, 380, 190, 370)

  -- Lines
  love.graphics.setColor(1, 1, 1, 0.8)
  love.graphics.line(320, 320, 420, 380, 440, 330, 480, 360)
  love.graphics.line(380, 320, 380, 380)

  -- Sprite batch (checkerboard tiles)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(sprite_batch, 0, 0)

  -- Colored mesh (triangle fan)
  love.graphics.push()
  love.graphics.translate(600, 360)
  love.graphics.rotate(elapsed * 0.8)
  local s = 0.9 + 0.2 * math.sin(elapsed * 2.0)
  love.graphics.scale(s, s)
  love.graphics.draw(mesh, 0, 0)
  love.graphics.pop()

  -- HUD info
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("love2d_gpu render demo", 20, 550)
  love.graphics.print("Backend: " .. love.graphics.getRendererInfo(), 20, 570)
  love.graphics.print(string.format("FPS: %.0f", fps), 20, 590)
end
