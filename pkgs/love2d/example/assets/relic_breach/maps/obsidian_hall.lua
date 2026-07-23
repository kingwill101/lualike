local TILE = 16
local WORLD_WIDTH = 40 * TILE
local WORLD_HEIGHT = 22 * TILE

local function center(col, row, dx, dy)
  return {
    x = (col - 0.5) * TILE + (dx or 0),
    y = (row - 0.5) * TILE + (dy or 0),
  }
end

local function rect(col, row, w, h)
  return {
    x = (col - 1) * TILE,
    y = (row - 1) * TILE,
    w = w * TILE,
    h = h * TILE,
  }
end

local function wall(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end

return {
  id = "obsidian_hall",
  name = "Obsidian Hall",
  tilewidth = TILE,
  tileheight = TILE,
  width = 40,
  height = 22,
  worldWidth = WORLD_WIDTH,
  worldHeight = WORLD_HEIGHT,
  playerSpawn = center(7, 18),
  relic = center(32, 6),
  exit = { x = WORLD_WIDTH / 2, y = 24, radius = 22 },
  walls = {
    wall(WORLD_WIDTH / 2, 6, WORLD_WIDTH, 12),
    wall(WORLD_WIDTH / 2, WORLD_HEIGHT - 6, WORLD_WIDTH, 12),
    wall(6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(WORLD_WIDTH - 6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(120, 104, 28, 92),
    wall(180, 72, 28, 60),
    wall(252, 120, 36, 28),
    wall(320, 80, 28, 72),
    wall(420, 116, 28, 96),
    wall(496, 76, 28, 52),
    wall(256, 220, 96, 22),
    wall(404, 228, 84, 22),
  },
  waterPools = {
    rect(8, 8, 4, 6),
    rect(28, 13, 5, 4),
  },
  props = {
    { kind = "banner", x = 72, y = 42, variant = "left" },
    { kind = "banner", x = WORLD_WIDTH - 72, y = 42, variant = "right" },
    { kind = "door", x = WORLD_WIDTH / 2, y = 24, role = "exit" },
    { kind = "door", x = WORLD_WIDTH / 2, y = WORLD_HEIGHT - 24, role = "entry" },
    { kind = "shelf", x = 168, y = 42, variant = 1 },
    { kind = "shelf", x = 192, y = 42, variant = 2 },
    { kind = "shelf", x = 216, y = 42, variant = 3 },
    { kind = "shelf", x = 416, y = 42, variant = 8 },
    { kind = "shelf", x = 440, y = 42, variant = 9 },
    { kind = "shelf", x = 464, y = 42, variant = 10 },
  },
  crates = {
    center(10, 15),
    center(12, 15),
    center(14, 15),
    center(18, 12),
    center(21, 12),
    center(24, 12),
    center(27, 15),
    center(29, 15),
    center(31, 15),
    center(34, 16),
    center(16, 18),
    center(19, 18),
    center(22, 18),
    center(25, 18),
  },
}
