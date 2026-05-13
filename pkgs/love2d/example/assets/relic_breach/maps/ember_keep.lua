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
  id = "ember_keep",
  name = "Ember Keep",
  tilewidth = TILE,
  tileheight = TILE,
  width = 40,
  height = 22,
  worldWidth = WORLD_WIDTH,
  worldHeight = WORLD_HEIGHT,
  playerSpawn = center(20, 18),
  relic = center(20, 8),
  exit = { x = WORLD_WIDTH / 2, y = 24, radius = 22 },
  walls = {
    wall(WORLD_WIDTH / 2, 6, WORLD_WIDTH, 12),
    wall(WORLD_WIDTH / 2, WORLD_HEIGHT - 6, WORLD_WIDTH, 12),
    wall(6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(WORLD_WIDTH - 6, WORLD_HEIGHT / 2, 12, WORLD_HEIGHT),
    wall(160, 120, 32, 80),
    wall(480, 120, 32, 80),
    wall(240, 232, 64, 24),
    wall(400, 232, 64, 24),
    wall(WORLD_WIDTH / 2, 120, 96, 20),
  },
  waterPools = {
    rect(9, 7, 4, 7),
    rect(28, 7, 4, 7),
    rect(16, 13, 8, 3),
  },
  props = {
    { kind = "banner", x = 88, y = 42, variant = "left" },
    { kind = "banner", x = WORLD_WIDTH - 88, y = 42, variant = "right" },
    { kind = "door", x = WORLD_WIDTH / 2, y = 24, role = "exit" },
    { kind = "door", x = WORLD_WIDTH / 2, y = WORLD_HEIGHT - 24, role = "entry" },
    { kind = "shelf", x = 176, y = 42, variant = 2 },
    { kind = "shelf", x = 200, y = 42, variant = 3 },
    { kind = "shelf", x = 224, y = 42, variant = 4 },
    { kind = "shelf", x = 416, y = 42, variant = 7 },
    { kind = "shelf", x = 440, y = 42, variant = 8 },
    { kind = "shelf", x = 464, y = 42, variant = 9 },
  },
  crates = {
    center(11, 15),
    center(13, 15),
    center(28, 15),
    center(30, 15),
    center(18, 10),
    center(20, 10),
    center(22, 10),
    center(18, 17),
    center(20, 17),
    center(22, 17),
    center(25, 18),
    center(15, 18),
  },
}
