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
  id = "flooded_sanctum",
  name = "Flooded Sanctum",
  tilewidth = TILE,
  tileheight = TILE,
  width = 40,
  height = 22,
  worldWidth = WORLD_WIDTH,
  worldHeight = WORLD_HEIGHT,
  playerSpawn = center(20, 18),
  relic = center(20, 7),
  exit = { x = WORLD_WIDTH / 2, y = 24, radius = 22 },
  walls = {
    wall(WORLD_WIDTH / 2, 6, WORLD_WIDTH, 12),
    wall(WORLD_WIDTH / 2, WORLD_HEIGHT - 6, WORLD_WIDTH, 12),
    wall(6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(WORLD_WIDTH - 6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(164, 88, 28, 64),
    wall(220, 144, 36, 28),
    wall(280, 88, 28, 64),
    wall(344, 144, 36, 28),
    wall(404, 88, 28, 64),
    wall(232, 220, 92, 22),
    wall(360, 220, 92, 22),
  },
  waterPools = {
    rect(7, 7, 7, 5),
    rect(16, 11, 9, 5),
    rect(28, 7, 7, 5),
    rect(24, 15, 6, 4),
  },
  props = {
    { kind = "banner", x = 56, y = 42, variant = "left" },
    { kind = "banner", x = WORLD_WIDTH - 56, y = 42, variant = "right" },
    { kind = "door", x = WORLD_WIDTH / 2, y = 24, role = "exit" },
    { kind = "door", x = WORLD_WIDTH / 2, y = WORLD_HEIGHT - 24, role = "entry" },
    { kind = "shelf", x = 208, y = 42, variant = 2 },
    { kind = "shelf", x = 232, y = 42, variant = 3 },
    { kind = "shelf", x = 256, y = 42, variant = 4 },
    { kind = "shelf", x = 280, y = 42, variant = 5 },
    { kind = "shelf", x = 304, y = 42, variant = 6 },
    { kind = "shelf", x = 328, y = 42, variant = 7 },
  },
  crates = {
    center(10, 17),
    center(12, 17),
    center(14, 16),
    center(17, 14),
    center(19, 14),
    center(21, 14),
    center(23, 14),
    center(26, 16),
    center(28, 17),
    center(30, 17),
    center(33, 16),
    center(16, 18),
    center(24, 18),
    center(32, 18),
  },
}
