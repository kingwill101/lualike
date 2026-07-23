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
  id = "brass_foundry",
  name = "Brass Foundry",
  tilewidth = TILE,
  tileheight = TILE,
  width = 40,
  height = 22,
  worldWidth = WORLD_WIDTH,
  worldHeight = WORLD_HEIGHT,
  playerSpawn = center(6, 18),
  relic = center(33, 6),
  exit = { x = WORLD_WIDTH / 2, y = 24, radius = 22 },
  walls = {
    wall(WORLD_WIDTH / 2, 6, WORLD_WIDTH, 12),
    wall(WORLD_WIDTH / 2, WORLD_HEIGHT - 6, WORLD_WIDTH, 12),
    wall(6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(WORLD_WIDTH - 6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(128, 72, 24, 72),
    wall(192, 120, 24, 88),
    wall(256, 72, 24, 72),
    wall(320, 120, 24, 88),
    wall(384, 72, 24, 72),
    wall(448, 120, 24, 88),
    wall(208, 224, 80, 22),
    wall(344, 224, 80, 22),
  },
  waterPools = {
    rect(9, 13, 5, 4),
    rect(18, 8, 5, 4),
    rect(28, 13, 5, 4),
  },
  props = {
    { kind = "banner", x = 80, y = 42, variant = "left" },
    { kind = "banner", x = WORLD_WIDTH - 80, y = 42, variant = "right" },
    { kind = "door", x = WORLD_WIDTH / 2, y = 24, role = "exit" },
    { kind = "door", x = WORLD_WIDTH / 2, y = WORLD_HEIGHT - 24, role = "entry" },
    { kind = "shelf", x = 160, y = 42, variant = 4 },
    { kind = "shelf", x = 184, y = 42, variant = 5 },
    { kind = "shelf", x = 208, y = 42, variant = 6 },
    { kind = "shelf", x = 424, y = 42, variant = 7 },
    { kind = "shelf", x = 448, y = 42, variant = 8 },
    { kind = "shelf", x = 472, y = 42, variant = 9 },
  },
  crates = {
    center(10, 15),
    center(12, 15),
    center(14, 15),
    center(16, 15),
    center(20, 10),
    center(22, 10),
    center(24, 10),
    center(26, 15),
    center(28, 15),
    center(30, 15),
    center(32, 15),
    center(18, 18),
    center(21, 18),
    center(24, 18),
    center(27, 18),
  },
}
