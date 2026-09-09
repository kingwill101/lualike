local frame_total = tonumber(arg and arg[1]) or 240
assert(frame_total >= 1 and frame_total <= 100000,
  "signal lattice frames must be between 1 and 100000")

local lattice_chunk = assert(loadfile("shared/signal_lattice.lua"))
local lattice = lattice_chunk()
local state = lattice.new()
local started = os.clock()

for frame = 1, frame_total do
  lattice.step(state)
end

local elapsed_micros = math.floor((os.clock() - started) * 1000000 + 0.5)
print(string.format(
  "NEON_SIGNAL_RESULT frames=%d nodes=%d substeps=%d tick=%d checksum=%d elapsedMicros=%d",
  frame_total,
  lattice.node_count,
  lattice.substeps_per_frame,
  state.tick,
  state.checksum,
  elapsed_micros
))
