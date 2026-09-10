-- Source-identical composition probe for native LOVE and Flutter GPU.

local player = nil
local sentinel = nil
local loaded = false

local panel_x = { 20, 215, 410, 605 }
local panel_width = 175
local top_y = 82
local bottom_y = 338
local panel_height = 230

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
end

local function panel(index, y, title)
  local x = panel_x[index]
  love.graphics.setColor(0.05, 0.10, 0.20, 0.55)
  love.graphics.rectangle("fill", x, y, panel_width, panel_height, 8, 8)
  love.graphics.setColor(0.18, 0.66, 0.88, 0.32)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x, y, panel_width, panel_height, 8, 8)
  love.graphics.setColor(0.54, 0.82, 0.94, 0.86)
  love.graphics.printf(title, x + 5, y + 8, panel_width - 10, "center")
end

local function draw_centered(image, x, y, scale)
  love.graphics.draw(
    image,
    x, y,
    0, scale, scale,
    image:getWidth() * 0.5,
    image:getHeight() * 0.5
  )
end

local function draw_guides()
  local top_titles = { "OPAQUE", "ALPHA", "TINT + ALPHA", "FILLS" }
  local bottom_titles = {
    "LINES + ARCS", "OVERLAP", "PLAYER LAYERS", "SENTINEL LAYERS"
  }
  for i = 1, 4 do
    panel(i, top_y, top_titles[i])
    panel(i, bottom_y, bottom_titles[i])
  end
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
  love.graphics.print("LOVE 11.5 ALPHA / SHAPE COMPOSITION PROBE", 24, 18)
  love.graphics.setColor(0.42, 0.72, 0.86, 0.84)
  love.graphics.print("Each inner panel is scored independently", 24, 47)

  -- Opaque images retain the already-proven texture baseline.
  love.graphics.setColor(1, 1, 1, 1)
  draw_centered(player, 70, 205, 0.105)
  draw_centered(sentinel, 146, 205, 0.105)

  -- Alpha-only image tint isolates source-alpha blend behavior.
  love.graphics.setColor(1, 1, 1, 0.48)
  draw_centered(player, 265, 205, 0.105)
  draw_centered(sentinel, 341, 205, 0.105)

  -- Simultaneous RGB tint and alpha isolates color modulation.
  love.graphics.setColor(0.32, 0.82, 1.0, 0.52)
  draw_centered(player, 460, 205, 0.105)
  love.graphics.setColor(1.0, 0.30, 0.76, 0.52)
  draw_centered(sentinel, 536, 205, 0.105)

  -- Alpha-filled primitives with deliberate overlap.
  love.graphics.setColor(0.15, 0.88, 1.0, 0.24)
  love.graphics.circle("fill", 665, 192, 49)
  love.graphics.setColor(1.0, 0.42, 0.12, 0.48)
  love.graphics.circle("fill", 720, 211, 36)
  love.graphics.setColor(0.96, 0.18, 0.72, 0.28)
  love.graphics.rectangle("fill", 655, 232, 84, 34, 8, 8)

  -- Rough lines, circles, and open arcs.
  love.graphics.setLineWidth(3)
  love.graphics.setColor(0.24, 0.92, 1.0, 0.72)
  love.graphics.line(42, 486, 174, 392)
  love.graphics.setColor(0.98, 0.18, 0.76, 0.72)
  love.graphics.arc("line", "open", 108, 458, 54, -0.45, 4.2)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.62, 0.98, 1.0, 0.56)
  love.graphics.circle("line", 108, 458, 32)

  -- Repeated translucent primitives expose blend accumulation.
  love.graphics.setColor(0.12, 0.88, 1.0, 0.18)
  love.graphics.circle("fill", 278, 449, 54)
  love.graphics.setColor(0.98, 0.12, 0.72, 0.20)
  love.graphics.circle("fill", 323, 449, 54)
  love.graphics.setColor(1.0, 0.62, 0.18, 0.22)
  love.graphics.circle("fill", 300, 486, 54)
  love.graphics.setColor(0.76, 0.98, 1.0, 0.38)
  love.graphics.rectangle("fill", 258, 426, 84, 84, 11, 11)

  -- Player-style composition from the Neon Relay scene.
  local player_x = 497
  local player_y = 458
  love.graphics.setColor(0.18, 0.90, 1.0, 0.15)
  love.graphics.circle("fill", player_x, player_y, 51)
  love.graphics.setColor(0.62, 0.98, 1.0, 0.82)
  love.graphics.arc("line", "open", player_x, player_y, 55, 0.55, 5.25)
  love.graphics.setColor(0.15, 0.88, 1.0, 0.24)
  love.graphics.circle("fill", player_x, player_y + 18, 34)
  love.graphics.setColor(1.0, 0.42, 0.12, 0.48)
  love.graphics.circle("fill", player_x, player_y + 26, 17)
  love.graphics.setColor(0.24, 0.92, 1.0, 0.72)
  love.graphics.line(player_x, player_y, player_x + 62, player_y - 38)
  love.graphics.setColor(1, 1, 1, 1)
  draw_centered(player, player_x, player_y, 0.105)

  -- Sentinel-style composition from the Neon Relay scene.
  local sentinel_x = 692
  local sentinel_y = 458
  love.graphics.setColor(0.98, 0.12, 0.72, 0.20)
  love.graphics.circle("fill", sentinel_x, sentinel_y, 62)
  love.graphics.setColor(0.98, 0.18, 0.76, 0.72)
  love.graphics.arc("line", "open", sentinel_x, sentinel_y, 57, 0.35, 4.9)
  love.graphics.setColor(0.24, 0.92, 1.0, 0.28)
  love.graphics.circle("line", sentinel_x, sentinel_y, 69)
  love.graphics.setColor(1.0, 0.86, 1.0, 1.0)
  draw_centered(sentinel, sentinel_x, sentinel_y, 0.105)
end

return function()
  setup()
  love.load = function() end
end
