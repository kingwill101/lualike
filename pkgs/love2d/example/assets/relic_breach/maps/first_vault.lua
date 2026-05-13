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
  id = "first_vault",
  name = "Sunken Archive",
  tilewidth = TILE,
  tileheight = TILE,
  width = 40,
  height = 22,
  worldWidth = WORLD_WIDTH,
  worldHeight = WORLD_HEIGHT,
  playerSpawn = center(6, 7),
  relic = center(20, 5),
  exit = { x = WORLD_WIDTH / 2, y = 24, radius = 22 },
  walls = {
    wall(WORLD_WIDTH / 2, 6, WORLD_WIDTH, 12),
    wall(WORLD_WIDTH / 2, WORLD_HEIGHT - 6, WORLD_WIDTH, 12),
    wall(6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(WORLD_WIDTH - 6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(264, 96, 48, 32),
    wall(376, 96, 48, 32),
    wall(216, 264, 32, 32),
    wall(424, 264, 32, 32),
  },
  waterPools = {
    rect(8, 6, 7, 4),
    rect(25, 13, 7, 4),
  },
  props = {
    { kind = "banner", x = 56, y = 42, variant = "left" },
    { kind = "banner", x = WORLD_WIDTH - 56, y = 42, variant = "right" },
    { kind = "door", x = WORLD_WIDTH / 2, y = 24, role = "exit" },
    { kind = "door", x = WORLD_WIDTH / 2, y = WORLD_HEIGHT - 24, role = "entry" },
    { kind = "shelf", x = 216, y = 42, variant = 1 },
    { kind = "shelf", x = 240, y = 42, variant = 2 },
    { kind = "shelf", x = 264, y = 42, variant = 3 },
    { kind = "shelf", x = 288, y = 42, variant = 4 },
    { kind = "shelf", x = 312, y = 42, variant = 5 },
    { kind = "shelf", x = 336, y = 42, variant = 6 },
    { kind = "shelf", x = 360, y = 42, variant = 7 },
    { kind = "shelf", x = 384, y = 42, variant = 8 },
    { kind = "shelf", x = 408, y = 42, variant = 9 },
    { kind = "shelf", x = 432, y = 42, variant = 10 },
  },
  crates = {
    center(12, 12),
    center(14, 12),
    center(16, 12),
    center(25, 8),
    center(27, 8),
    center(29, 8),
    center(25, 10),
    center(27, 10),
    center(29, 10),
    center(18, 18),
    center(20, 18),
    center(22, 18),
    center(24, 18),
  },
}
