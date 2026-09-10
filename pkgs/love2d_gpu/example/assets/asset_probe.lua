-- Source-identical gameplay-scale asset probe for native LOVE and Flutter GPU.

local specs = {
  { "DRONE", "art/neon_relay_drone.png", 0.105, 100, 140 },
  { "BEACON", "art/neon_relay_beacon.png", 0.078, 300, 140 },
  { "CORE", "art/neon_relay_core.png", 0.072, 500, 140 },
  { "CORE DAMAGED", "art/neon_relay_core_damaged.png", 0.072, 700, 140 },
  { "CELL", "art/neon_relay_cell.png", 0.045, 100, 310 },
  { "BOLT", "art/neon_relay_bolt.png", 0.040, 300, 310 },
  { "SHIELD", "art/neon_relay_shield.png", 0.046, 500, 310 },
  { "OVERDRIVE", "art/neon_relay_overdrive.png", 0.047, 700, 310 },
  { "IMPACT", "art/neon_relay_impact.png", 80 / 384, 100, 485 },
  { "PLAYER", "art/neon_relay_player.png", 0.145, 300, 485 },
  { "SENTINEL", "art/neon_relay_sentinel.png", 0.145, 500, 485 },
}

local images = {}

local function setup()
  if #images > 0 then return end
  love.graphics.setBackgroundColor(0.012, 0.018, 0.042)
  love.graphics.setLineStyle("rough")
  for index, spec in ipairs(specs) do
    local image = love.graphics.newImage(spec[2], { linear = true, mipmaps = true })
    image:setFilter("linear", "linear")
    images[index] = image
  end
end

function love.load()
  setup()
end

function love.update(_)
end

function love.draw()
  setup()
  love.graphics.setColor(0.68, 0.86, 0.96, 0.92)
  love.graphics.print("LOVE 11.5 GAMEPLAY-SCALE ASSET PROBE", 24, 16)
  love.graphics.setColor(0.42, 0.72, 0.86, 0.84)
  love.graphics.print("Generated Neon Relay assets / linear mipmaps", 24, 42)

  for index, spec in ipairs(specs) do
    local image = images[index]
    local x = spec[4]
    local y = spec[5]
    love.graphics.setColor(0.05, 0.10, 0.20, 0.55)
    love.graphics.rectangle("fill", x - 92, y - 76, 184, 152, 8, 8)
    love.graphics.setColor(0.54, 0.82, 0.94, 0.86)
    love.graphics.printf(spec[1], x - 88, y - 70, 176, "center")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
      image,
      x, y + 8,
      0, spec[3], spec[3],
      image:getWidth() * 0.5,
      image:getHeight() * 0.5
    )
  end
end
