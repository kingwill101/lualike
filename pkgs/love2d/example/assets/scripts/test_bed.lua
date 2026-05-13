testbed = {
  status = "booting",
  compressed_detection = "synthetic_ktx=true",
  compressed_summary = "DXT1 16x8 compressed=true linear=true",
  generated_sprite = "dpi=2.00 mips=4 linear=true",
  spritebatch_summary = "count=0 buffer=0",
  particle_summary = "count=0 mode=bottom",
  mapped_pixel = "",
  encoded_image = "Image.png png bytes=0 data=true",
  encoded_roundtrip = "pending",
}

local sprite = nil
local spritebatch = nil
local particles = nil
local elapsed = 0
local image_error = nil

local function fmt_color(r, g, b, a)
  return string.format("%.2f/%.2f/%.2f/%.2f", r, g, b, a)
end

local function build_image_diagnostics()
  local data = love.image.newImageData(8, 8)
  for y = 0, 7 do
    for x = 0, 7 do
      local red = x / 7
      local green = y / 7
      local blue = ((x + y) % 2 == 0) and 0.85 or 0.25
      data:setPixel(x, y, red, green, blue, 1.0)
    end
  end

  data:mapPixel(function(x, y, r, g, b, a)
    if x == 1 and y == 0 then
      return g, b, r, a
    end
    return r, g, b, a
  end, 0, 0, 2, 1)

  local r, g, b, a = data:getPixel(1, 0)
  testbed.mapped_pixel = fmt_color(r, g, b, a)

  local encoded = data:encode("png")
  testbed.encoded_image = string.format(
    "%s %s bytes=%d data=%s",
    encoded:getFilename(),
    encoded:getExtension(),
    encoded:getSize(),
    tostring(encoded:typeOf("Data"))
  )

  local decoded = love.image.newImageData(encoded)
  local rr, rg, rb, ra = decoded:getPixel(1, 0)
  testbed.encoded_roundtrip = fmt_color(rr, rg, rb, ra)

  sprite = love.graphics.newImage(data, { mipmaps = true, linear = true })

  spritebatch = love.graphics.newSpriteBatch(sprite, 2)
  spritebatch:add(24, 24)
  local quad = love.graphics.newQuad(0, 0, 4, 4, sprite)
  spritebatch:add(quad, 48, 24, 0, 2, 2)
  spritebatch:add(78, 24)
  testbed.spritebatch_summary = string.format(
    "count=%d buffer=%d",
    spritebatch:getCount(),
    spritebatch:getBufferSize()
  )

  particles = love.graphics.newParticleSystem(sprite, 4)
  particles:setInsertMode("bottom")
  particles:setParticleLifetime(0.5, 1.0)
  particles:setEmissionRate(8)
  particles:setSpeed(12, 30)
  particles:setPosition(96, 58)
  particles:emit(6)
  testbed.particle_summary = string.format(
    "count=%d mode=%s",
    particles:getCount(),
    particles:getInsertMode()
  )
end

function love.load()
  local ok, err = pcall(build_image_diagnostics)
  if not ok then
    image_error = tostring(err)
    testbed.mapped_pixel = "error"
    testbed.encoded_roundtrip = image_error
  end

  testbed.status = "love.load complete"
end

function love.update(dt)
  elapsed = elapsed + dt
  if particles then
    particles:update(dt)
  end
end

function love.draw()
  love.graphics.clear(0.05, 0.07, 0.12, 1.0)
  love.graphics.setColor(0.20, 0.75, 0.95, 1.0)
  love.graphics.rectangle("fill", 20, 18, 140 + math.sin(elapsed * 2) * 18, 18)
  love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
  love.graphics.print("LuaLike LOVE test bed", 20, 48)
  love.graphics.print(testbed.status, 20, 68)

  if spritebatch then
    love.graphics.draw(spritebatch, 0, 64)
  end

  if particles then
    love.graphics.draw(particles, 0, 82)
  end

  if image_error then
    love.graphics.setColor(1.0, 0.35, 0.35, 1.0)
    love.graphics.print(image_error, 20, 110)
  end

  love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
end
