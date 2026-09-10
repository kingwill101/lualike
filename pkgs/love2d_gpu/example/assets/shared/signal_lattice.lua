-- Deterministic fixed-capacity signal simulation shared by Neon Relay and
-- the standalone native/Lualike CPU benchmark. The hot step allocates no Lua
-- tables: it mutates the arrays created by new() and returns an observable
-- integer checksum.

local M = {}

local NODE_COUNT = 64
local SUBSTEPS_PER_FRAME = 1
local WORLD_LEFT = 72
local WORLD_TOP = 92
local WORLD_WIDTH = 656
local WORLD_HEIGHT = 416

local function seed_state(state)
  local x = state.x
  local y = state.y
  local vx = state.vx
  local vy = state.vy
  local signal = state.signal

  for i = 1, NODE_COUNT do
    x[i] = WORLD_LEFT + ((i * 97) % WORLD_WIDTH)
    y[i] = WORLD_TOP + ((i * 53) % WORLD_HEIGHT)
    vx[i] = ((i * 29) % 17 - 8) * 0.03125
    vy[i] = ((i * 43) % 19 - 9) * 0.03125
    signal[i] = ((i * 61) % 127) / 127
  end

  state.tick = 0
  state.checksum = 0
end

function M.new()
  local state = {
    x = {},
    y = {},
    vx = {},
    vy = {},
    signal = {},
    tick = 0,
    checksum = 0,
  }
  seed_state(state)
  return state
end

function M.reset(state)
  seed_state(state)
end

function M.step(state)
  local x = state.x
  local y = state.y
  local vx = state.vx
  local vy = state.vy
  local signal = state.signal
  local tick = state.tick
  local checksum = 0

  for substep = 1, SUBSTEPS_PER_FRAME do
    for i = 1, NODE_COUNT do
      local previous = i - 1
      if previous == 0 then previous = NODE_COUNT end
      local following = i + 1
      if following > NODE_COUNT then following = 1 end
      local probe = ((i * 37 + tick + substep * 13) % NODE_COUNT) + 1

      local px = x[i]
      local py = y[i]
      local next_vx = vx[i] * 0.96875
        + (x[following] - x[previous]) * 0.00125
        + (x[probe] - px) * 0.0003125
        + (400 - px) * 0.0000625
      local next_vy = vy[i] * 0.96875
        + (y[following] - y[previous]) * 0.00125
        + (y[probe] - py) * 0.0003125
        + (300 - py) * 0.0000625

      px = px + next_vx
      py = py + next_vy
      if px < WORLD_LEFT then
        px = px + WORLD_WIDTH
      elseif px >= WORLD_LEFT + WORLD_WIDTH then
        px = px - WORLD_WIDTH
      end
      if py < WORLD_TOP then
        py = py + WORLD_HEIGHT
      elseif py >= WORLD_TOP + WORLD_HEIGHT then
        py = py - WORLD_HEIGHT
      end

      local next_signal = signal[i] * 0.8125
        + signal[previous] * 0.109375
        + signal[following] * 0.0625
        + signal[probe] * 0.015625
      if ((i + tick + substep) % 31) == 0 then
        next_signal = next_signal + 0.125
      end
      if next_signal >= 1 then next_signal = next_signal - 1 end

      x[i] = px
      y[i] = py
      vx[i] = next_vx
      vy[i] = next_vy
      signal[i] = next_signal
      checksum = (checksum
        + px * 3
        + py * 5
        + next_vx * 11
        + next_vy * 13
        + next_signal * 17) % 1000000
    end
    tick = tick + 1
  end

  state.tick = tick
  state.checksum = math.floor(checksum * 1000 + 0.5) % 1000000
  return state.checksum
end

M.node_count = NODE_COUNT
M.substeps_per_frame = SUBSTEPS_PER_FRAME

return M
