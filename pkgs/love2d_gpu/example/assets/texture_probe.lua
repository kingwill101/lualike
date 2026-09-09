-- Source-identical minified texture probe for native LOVE and Flutter GPU.

local player = nil
local sentinel = nil
local player_batch = nil
local sentinel_batch = nil
local loaded = false

local player_x1 = 120
local player_x2 = 300
local sentinel_x1 = 500
local sentinel_x2 = 680
local direct_y = 185
local batch_y = 445
local small_scale = 0.074
local large_scale = 0.145
local rotated_angle = 0.23

local function configure_image(path)
  local image = love.graphics.newImage(path, { linear = true, mipmaps = true })
  image:setFilter("linear", "linear")
  return image
end
local function setup()
  if loaded then return end
  loaded = true

  love.graphics.setBackgroundColor(0.012, 0.018, 0.042)
  love.graphics.setLineStyle("rough")
  player = configure_image("art/neon_relay_player.png")
  sentinel = configure_image("art/neon_relay_sentinel.png")

  local player_ox = player:getWidth() * 0.5
  local player_oy = player:getHeight() * 0.5
  local sentinel_ox = sentinel:getWidth() * 0.5
  local sentinel_oy = sentinel:getHeight() * 0.5

  player_batch = love.graphics.newSpriteBatch(player, 2, "static")
  player_batch:add(
    player_x1, batch_y, 0,
    small_scale, small_scale,
    player_ox, player_oy
  )
  player_batch:add(
    player_x2 + 0.5, batch_y + 0.5, rotated_angle,
    large_scale, large_scale,
    player_ox, player_oy
  )

  sentinel_batch = love.graphics.newSpriteBatch(sentinel, 2, "static")
  sentinel_batch:add(
    sentinel_x1, batch_y, 0,
    small_scale, small_scale,
    sentinel_ox, sentinel_oy
  )
  sentinel_batch:add(
    sentinel_x2 + 0.5, batch_y + 0.5, -rotated_angle,
    large_scale, large_scale,
    sentinel_ox, sentinel_oy
  )
end

local function draw_guides()
  love.graphics.setColor(0.08, 0.72, 0.92, 0.16)
  love.graphics.setLineWidth(1)
  for x = 20, 780, 40 do
    love.graphics.line(x + 0.5, 70.5, x + 0.5, 570.5)
  end
  for y = 70, 570, 40 do
    love.graphics.line(20.5, y + 0.5, 780.5, y + 0.5)
  end
  love.graphics.setColor(0.20, 0.88, 1.0, 0.52)
  love.graphics.rectangle("line", 20, 70, 760, 500)
  love.graphics.line(20, 310, 780, 310)
end

function love.load()
  setup()
end

function love.update(_)
end

function love.draw()
  setup()
  draw_guides()

  love.graphics.setColor(0.68, 0.86, 0.96, 0.92)
  love.graphics.print("LOVE 11.5 MINIFIED TEXTURE / SPRITEBATCH PROBE", 24, 18)
  love.graphics.setColor(0.42, 0.72, 0.86, 0.84)
  love.graphics.print("DIRECT IMAGE", 24, 48)
  love.graphics.print("SPRITEBATCH", 24, 324)
  love.graphics.printf("PLAYER", 55, 82, 310, "center")
  love.graphics.printf("SENTINEL", 435, 82, 310, "center")

  love.graphics.setColor(1, 1, 1, 1)
  local player_ox = player:getWidth() * 0.5
  local player_oy = player:getHeight() * 0.5
  local sentinel_ox = sentinel:getWidth() * 0.5
  local sentinel_oy = sentinel:getHeight() * 0.5
  love.graphics.draw(
    player,
    player_x1, direct_y,
    0, small_scale, small_scale,
    player_ox, player_oy
  )
  love.graphics.draw(
    player,
    player_x2 + 0.5, direct_y + 0.5,
    rotated_angle, large_scale, large_scale,
    player_ox, player_oy
  )
  love.graphics.draw(
    sentinel,
    sentinel_x1, direct_y,
    0, small_scale, small_scale,
    sentinel_ox, sentinel_oy
  )
  love.graphics.draw(
    sentinel,
    sentinel_x2 + 0.5, direct_y + 0.5,
    -rotated_angle, large_scale, large_scale,
    sentinel_ox, sentinel_oy
  )

  love.graphics.draw(player_batch)
  love.graphics.draw(sentinel_batch)

  love.graphics.setColor(0.42, 0.72, 0.86, 0.84)
  love.graphics.printf("0.074x / integer", 42, 286, 156, "center")
  love.graphics.printf("0.145x / rotated half", 206, 286, 188, "center")
  love.graphics.printf("0.074x / integer", 422, 286, 156, "center")
  love.graphics.printf("0.145x / rotated half", 586, 286, 188, "center")
  love.graphics.printf("0.074x / integer", 42, 546, 156, "center")
  love.graphics.printf("0.145x / rotated half", 206, 546, 188, "center")
  love.graphics.printf("0.074x / integer", 422, 546, 156, "center")
  love.graphics.printf("0.145x / rotated half", 586, 546, 188, "center")
end

return function()
  setup()
  love.load = function() end
end
