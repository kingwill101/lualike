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
  id = "moonlit_crossing",
  name = "Moonlit Crossing",
  tilewidth = TILE,
  tileheight = TILE,
  width = 40,
  height = 22,
  worldWidth = WORLD_WIDTH,
  worldHeight = WORLD_HEIGHT,
  playerSpawn = center(10, 18),
  relic = center(30, 7),
  exit = { x = WORLD_WIDTH / 2, y = 24, radius = 22 },
  walls = {
    wall(WORLD_WIDTH / 2, 6, WORLD_WIDTH, 12),
    wall(WORLD_WIDTH / 2, WORLD_HEIGHT - 6, WORLD_WIDTH, 12),
    wall(6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(WORLD_WIDTH - 6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(104, 112, 28, 88),
    wall(176, 72, 28, 72),
    wall(248, 112, 28, 88),
    wall(320, 72, 28, 72),
    wall(392, 112, 28, 88),
    wall(464, 72, 28, 72),
    wall(208, 232, 72, 22),
    wall(328, 232, 72, 22),
  },
  waterPools = {
    rect(8, 8, 4, 4),
    rect(14, 14, 5, 5),
    rect(22, 9, 4, 4),
    rect(29, 15, 5, 4),
  },
  props = {
    { kind = "banner", x = 64, y = 42, variant = "left" },
    { kind = "banner", x = WORLD_WIDTH - 64, y = 42, variant = "right" },
    { kind = "door", x = WORLD_WIDTH / 2, y = 24, role = "exit" },
    { kind = "door", x = WORLD_WIDTH / 2, y = WORLD_HEIGHT - 24, role = "entry" },
    { kind = "shelf", x = 200, y = 42, variant = 1 },
    { kind = "shelf", x = 224, y = 42, variant = 2 },
    { kind = "shelf", x = 248, y = 42, variant = 3 },
    { kind = "shelf", x = 272, y = 42, variant = 4 },
    { kind = "shelf", x = 296, y = 42, variant = 5 },
    { kind = "shelf", x = 320, y = 42, variant = 6 },
  },
  crates = {
    center(12, 15),
    center(14, 15),
    center(16, 16),
    center(18, 16),
    center(20, 13),
    center(22, 13),
    center(24, 16),
    center(26, 16),
    center(28, 15),
    center(30, 15),
    center(32, 16),
    center(34, 16),
    center(18, 18),
    center(22, 18),
    center(26, 18),
    center(30, 18),
  },
}
