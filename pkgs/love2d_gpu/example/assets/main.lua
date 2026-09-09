-- Neon Relay: a deterministic, asset-backed LOVE scene for renderer parity.
--
-- The hot paths deliberately use fixed-capacity arrays.  The game is small,
-- but it is busy enough to expose frame pacing, texture filtering, batching,
-- alpha blending, mesh colors, input, and text in both render backends. Twelve
-- generated textures keep the asset path real without allocating per frame.

local SCREEN_W = 800
local SCREEN_H = 600
local ENEMY_COUNT = 8
local SHOT_COUNT = 24
local PARTICLE_COUNT = 72
local IMPACT_COUNT = 12
local CELL_COUNT = 5
local BOLT_COUNT = 24
local SHIELD_PICKUP_COUNT = 2
local BOSS_MAX_HEALTH = 18
local SHIELD_DURATION = 6
local OVERDRIVE_DURATION = 5
local SIGNAL_DISPLAY_NODE_COUNT = 16

local arena_image = nil
local player_image = nil
local drone_image = nil
local beacon_image = nil
local core_image = nil
local core_damaged_image = nil
local cell_image = nil
local sentinel_image = nil
local bolt_image = nil
local shield_image = nil
local overdrive_image = nil
local impact_image = nil
local signal_lattice = nil
local signal_state = nil
local signal_lab_active = false
local signal_kernel_only = false
local drone_batch = nil
local cell_batch = nil
local bolt_batch = nil
local shield_batch = nil
local target_mesh = nil
local drone_origin_x = 0
local drone_origin_y = 0
local cell_origin_x = 0
local cell_origin_y = 0
local sentinel_origin_x = 0
local sentinel_origin_y = 0
local bolt_origin_x = 0
local bolt_origin_y = 0
local shield_origin_x = 0
local shield_origin_y = 0
local overdrive_origin_x = 0
local overdrive_origin_y = 0
local impact_origin_x = 0
local impact_origin_y = 0
local core_origin_x = 0
local core_origin_y = 0
local core_damaged_origin_x = 0
local core_damaged_origin_y = 0

local elapsed = 0
local frame_count = 0
local fps_timer = 0
local fps = 0
local hud_fps = "FPS --"
local hud_cells = "CELLS 00"
local hud_shield = "SHIELD --"
local hud_overdrive = "BOOST --"
local hud_relay = "RELAY 100"
local hud_signal = "SIM OFF"
local score = 0
local wave = 1
local energy = 100
local kills = 0
local cells_collected = 0
local fire_cooldown = 0
local damage_flash = 0
local relay_integrity = 100
local boss_active = false
local boss_defeated = false
local boss_health = BOSS_MAX_HEALTH
local boss_x = 400
local boss_y = 170
local boss_angle = 0
local boss_hit_flash = 0
local boss_attack_timer = 0
local boss_attack_radius = 0
local boss_attack_active = false
local boss_attack_relay_hit = false
local boss_bolt_timer = 0
local boss_elapsed = 0
local shield_timer = 0
local shield_hit_flash = 0
local shield_display_second = -1
local overdrive_timer = 0
local overdrive_display_second = -1
local overdrive_x = 400
local overdrive_y = 398
local overdrive_phase = 1.2
local overdrive_active = true
local overdrive_respawn = 0
local parity_scene_frozen = false

-- Public diagnostics consumed by the Flutter benchmark harness and by native
-- LOVE checksum runs. They are scalars so observing the workload does not
-- create a fresh table every frame.
neon_relay_workload = "combat"
neon_relay_signal_tick = 0
neon_relay_signal_checksum = 0

local player_x = 400
local player_y = 470
local player_angle = 0

local enemy_start_x = { 126, 674, 400, 400, 190, 610, 280, 520 }
local enemy_start_y = { 126, 126, 118, 488, 306, 306, 190, 190 }
local enemy_x = { 126, 674, 400, 400, 190, 610, 280, 520 }
local enemy_y = { 126, 126, 118, 488, 306, 306, 190, 190 }
local enemy_phase = { 0.0, 0.9, 1.8, 2.7, 0.4, 1.3, 2.2, 3.1 }
local enemy_radius = { 30, 30, 30, 30, 26, 26, 26, 26 }
local enemy_health = { 3, 3, 3, 3, 2, 2, 2, 2 }
local enemy_alive = { true, true, true, true, true, true, true, true }
local enemy_respawn = { 0, 0, 0, 0, 0, 0, 0, 0 }
local enemy_batch_index = { 1, 2, 3, 4, 5, 6, 7, 8 }

local shot_x = {}
local shot_y = {}
local shot_vx = {}
local shot_vy = {}
local shot_life = {}

local bolt_x = {}
local bolt_y = {}
local bolt_vx = {}
local bolt_vy = {}
local bolt_angle = {}
local bolt_life = {}
local bolt_batch_index = {}

local shield_x = { 246, 554 }
local shield_y = { 360, 360 }
local shield_phase = { 0.4, 3.5 }
local shield_active = { true, true }
local shield_respawn = { 0, 0 }
local shield_batch_index = {}

local particle_x = {}
local particle_y = {}
local particle_vx = {}
local particle_vy = {}
local particle_life = {}
local particle_max_life = {}
local particle_size = {}
local particle_r = {}
local particle_g = {}
local particle_b = {}

local impact_x = {}
local impact_y = {}
local impact_life = {}
local impact_max_life = {}
local impact_size = {}
local impact_angle = {}
local impact_active_count = 0

local cell_x = { 150, 650, 150, 650, 400 }
local cell_y = { 160, 160, 400, 400, 220 }
local cell_phase = { 0.0, 1.1, 2.2, 3.3, 4.4 }
local cell_active = { true, true, true, true, true }
local cell_respawn = { 0, 0, 0, 0, 0 }
local cell_batch_index = { 1, 2, 3, 4, 5 }

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function ensure_signal_lattice()
  if signal_lattice == nil then
    local lattice_chunk = assert(love.filesystem.load("shared/signal_lattice.lua"))
    signal_lattice = lattice_chunk()
  end
  if signal_state == nil then
    signal_state = signal_lattice.new()
  end
end

local function reset_signal_lattice()
  ensure_signal_lattice()
  signal_lattice.reset(signal_state)
  hud_signal = "SIM OFF"
  neon_relay_signal_tick = 0
  neon_relay_signal_checksum = 0
end

local function set_relay_integrity(value)
  relay_integrity = clamp(math.floor(value + 0.5), 0, 100)
  hud_relay = "RELAY " .. string.format("%03d", relay_integrity)
end

local function screen_transform()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  local scale = math.min(width / SCREEN_W, height / SCREEN_H)
  local offset_x = (width - SCREEN_W * scale) * 0.5
  local offset_y = (height - SCREEN_H * scale) * 0.5
  return scale, offset_x, offset_y
end

local function pointer_in_world()
  if parity_scene_frozen or signal_lab_active then
    return 640, 360
  end
  local mouse_x, mouse_y = love.mouse.getPosition()
  local scale, offset_x, offset_y = screen_transform()
  return (mouse_x - offset_x) / scale, (mouse_y - offset_y) / scale
end

local function spawn_particle(x, y, r, g, b, speed, size, lifetime)
  for i = 1, PARTICLE_COUNT do
    if particle_life[i] <= 0 then
      local phase = i * 2.399963 + elapsed * 0.7
      particle_x[i] = x
      particle_y[i] = y
      particle_vx[i] = math.cos(phase) * speed
      particle_vy[i] = math.sin(phase) * speed
      particle_life[i] = lifetime
      particle_max_life[i] = lifetime
      particle_size[i] = size
      particle_r[i] = r
      particle_g[i] = g
      particle_b[i] = b
      return
    end
  end
end

local function spawn_burst(x, y, r, g, b, count)
  for i = 1, count do
    spawn_particle(x, y, r, g, b, 18 + i * 5, 2 + (i % 3), 0.24 + (i % 4) * 0.05)
  end
end

local function spawn_impact(x, y, size, lifetime, angle)
  for i = 1, IMPACT_COUNT do
    if impact_life[i] <= 0 then
      impact_x[i] = x
      impact_y[i] = y
      impact_life[i] = lifetime
      impact_max_life[i] = lifetime
      impact_size[i] = size
      impact_angle[i] = angle
      impact_active_count = impact_active_count + 1
      return
    end
  end
end

local function clear_bolts()
  for i = 1, BOLT_COUNT do
    bolt_x[i] = 0
    bolt_y[i] = 0
    bolt_vx[i] = 0
    bolt_vy[i] = 0
    bolt_angle[i] = 0
    bolt_life[i] = 0
    if bolt_batch ~= nil then
      bolt_batch:set(bolt_batch_index[i], -200, -200, 0, 0.04, 0.04)
    end
  end
end

local function spawn_bolt(angle)
  for i = 1, BOLT_COUNT do
    if bolt_life[i] <= 0 then
      local dx = math.cos(angle)
      local dy = math.sin(angle)
      bolt_x[i] = boss_x + dx * 54
      bolt_y[i] = boss_y + dy * 54
      bolt_vx[i] = dx * 178
      bolt_vy[i] = dy * 178
      bolt_angle[i] = angle - math.pi * 0.5
      bolt_life[i] = 3.4
      return
    end
  end
end

local function spawn_bolt_volley()
  local aim = math.atan(player_y - boss_y, player_x - boss_x)
  for offset = -2, 2 do
    spawn_bolt(aim + offset * 0.18)
  end
end

local function activate_boss()
  if boss_active then return end
  boss_active = true
  boss_defeated = false
  boss_health = BOSS_MAX_HEALTH
  boss_x = 400
  boss_y = 170
  boss_angle = 0
  boss_hit_flash = 0
  boss_attack_timer = 0.8
  boss_attack_radius = 0
  boss_attack_active = false
  boss_attack_relay_hit = false
  boss_bolt_timer = 0.38
  boss_elapsed = 0
  clear_bolts()
  wave = 2
  spawn_burst(boss_x, boss_y, 1.0, 0.12, 0.72, 18)
end

local function reset_session_state()
  elapsed = 0
  frame_count = 0
  fps_timer = 0
  fps = 0
  hud_fps = "FPS --"
  player_x = 400
  player_y = 470
  player_angle = 0
  score = 0
  wave = 1
  energy = 100
  kills = 0
  fire_cooldown = 0
  damage_flash = 0
  cells_collected = 0
  hud_cells = "CELLS 00"
  hud_shield = "SHIELD --"
  hud_overdrive = "BOOST --"
  set_relay_integrity(100)
  shield_timer = 0
  shield_hit_flash = 0
  shield_display_second = -1
  overdrive_timer = 0
  overdrive_display_second = -1
  overdrive_active = true
  overdrive_respawn = 0
  signal_lab_active = false
  neon_relay_workload = "combat"
  reset_signal_lattice()
  boss_active = false
  boss_defeated = false
  boss_health = BOSS_MAX_HEALTH
  boss_x = 400
  boss_y = 170
  boss_angle = 0
  boss_hit_flash = 0
  boss_attack_timer = 0
  boss_attack_radius = 0
  boss_attack_active = false
  boss_attack_relay_hit = false
  boss_bolt_timer = 0
  boss_elapsed = 0
end

local function reset_projectile_state()
  clear_bolts()
  impact_active_count = 0

  for i = 1, SHOT_COUNT do
    shot_x[i] = 0
    shot_y[i] = 0
    shot_vx[i] = 0
    shot_vy[i] = 0
    shot_life[i] = 0
  end
  for i = 1, PARTICLE_COUNT do
    particle_x[i] = 0
    particle_y[i] = 0
    particle_vx[i] = 0
    particle_vy[i] = 0
    particle_life[i] = 0
    particle_max_life[i] = 1
    particle_size[i] = 1
    particle_r[i] = 1
    particle_g[i] = 1
    particle_b[i] = 1
  end
  for i = 1, IMPACT_COUNT do
    impact_x[i] = 0
    impact_y[i] = 0
    impact_life[i] = 0
    impact_max_life[i] = 1
    impact_size[i] = 50
    impact_angle[i] = 0
  end
end

local function reset_world_state()
  for i = 1, ENEMY_COUNT do
    enemy_x[i] = enemy_start_x[i]
    enemy_y[i] = enemy_start_y[i]
    enemy_alive[i] = true
    enemy_respawn[i] = 0
    enemy_health[i] = i <= 4 and 3 or 2
    if drone_batch ~= nil then
      drone_batch:set(
        enemy_batch_index[i],
        enemy_x[i], enemy_y[i], enemy_phase[i],
        0.105, 0.105,
        drone_origin_x, drone_origin_y
      )
    end
  end
  for i = 1, CELL_COUNT do
    cell_active[i] = true
    cell_respawn[i] = 0
    if cell_batch ~= nil then
      local pulse = 0.5 + 0.5 * math.sin(cell_phase[i])
      local scale = 0.042 + pulse * 0.003
      cell_batch:set(
        cell_batch_index[i],
        cell_x[i], cell_y[i], cell_phase[i],
        scale, scale,
        cell_origin_x, cell_origin_y
      )
    end
  end
  for i = 1, SHIELD_PICKUP_COUNT do
    shield_active[i] = true
    shield_respawn[i] = 0
    if shield_batch ~= nil then
      local pulse = 0.5 + 0.5 * math.sin(shield_phase[i])
      local scale = 0.043 + pulse * 0.003
      shield_batch:set(
        shield_batch_index[i],
        shield_x[i], shield_y[i], shield_phase[i],
        scale, scale,
        shield_origin_x, shield_origin_y
      )
    end
  end
  overdrive_active = true
  overdrive_respawn = 0
end

local function reset_game()
  reset_session_state()
  reset_projectile_state()
  reset_world_state()
end

local function activate_signal_lab()
  reset_game()
  activate_boss()
  wave = 4
  signal_lab_active = true
  neon_relay_workload = "signal-lattice"
  hud_signal = string.format(
    "SIM %03d x %02d  CRC %06d",
    signal_lattice.node_count,
    signal_lattice.substeps_per_frame,
    signal_state.checksum
  )
end

local function run_signal_kernel(frame_total)
  ensure_signal_lattice()
  signal_lattice.reset(signal_state)
  local started = love.timer.getTime()
  for frame = 1, frame_total do
    signal_lattice.step(signal_state)
  end
  local elapsed_micros = math.floor((love.timer.getTime() - started) * 1000000 + 0.5)
  print(string.format(
    "NEON_SIGNAL_RESULT frames=%d nodes=%d substeps=%d tick=%d checksum=%d elapsedMicros=%d",
    frame_total,
    signal_lattice.node_count,
    signal_lattice.substeps_per_frame,
    signal_state.tick,
    signal_state.checksum,
    elapsed_micros
  ))
  signal_kernel_only = true
  love.event.quit(0)
end

local function freeze_parity_scene()
  parity_scene_frozen = false
  reset_game()
  activate_boss()
  set_relay_integrity(38)
  spawn_impact(400, 300, 80, 1.0, 0.2)
  parity_scene_frozen = true
end

local function fire_shot(target_x, target_y)
  local dx = target_x - player_x
  local dy = target_y - player_y
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 0.01 then return end
  dx = dx / length
  dy = dy / length

  for i = 1, SHOT_COUNT do
    if shot_life[i] <= 0 then
      shot_x[i] = player_x + dx * 22
      shot_y[i] = player_y + dy * 22
      shot_vx[i] = dx * 520
      shot_vy[i] = dy * 520
      shot_life[i] = 1.1
      spawn_particle(shot_x[i], shot_y[i], 0.25, 0.9, 1.0, 20, 2, 0.18)
      return
    end
  end
end

local function update_enemies(dt)
  local orbit_time = elapsed * 0.72
  for i = 1, ENEMY_COUNT do
    if enemy_alive[i] then
      local phase = orbit_time + enemy_phase[i]
      local orbit = 18 + (i % 3) * 8
      enemy_x[i] = enemy_x[i] + math.cos(phase) * dt * orbit
      enemy_y[i] = enemy_y[i] + math.sin(phase * 1.13) * dt * orbit
      enemy_x[i] = clamp(enemy_x[i], 88, SCREEN_W - 88)
      enemy_y[i] = clamp(enemy_y[i], 104, SCREEN_H - 126)
    else
      enemy_respawn[i] = enemy_respawn[i] - dt
      if enemy_respawn[i] <= 0 then
        enemy_alive[i] = true
        enemy_health[i] = i <= 4 and 3 or 2
        enemy_x[i] = 120 + ((i * 83) % 560)
        enemy_y[i] = 120 + ((i * 47) % 290)
        spawn_burst(enemy_x[i], enemy_y[i], 0.95, 0.15, 0.75, 5)
      end
    end

    if drone_batch ~= nil then
      if enemy_alive[i] then
        drone_batch:set(
          enemy_batch_index[i],
          enemy_x[i], enemy_y[i],
          elapsed * 0.28 + enemy_phase[i],
          0.105, 0.105,
          drone_origin_x, drone_origin_y
        )
      else
        drone_batch:set(enemy_batch_index[i], -200, -200, 0, 0.1, 0.1)
      end
    end
  end
end

local function update_shots(dt)
  for i = 1, SHOT_COUNT do
    if shot_life[i] > 0 then
      shot_life[i] = shot_life[i] - dt
      shot_x[i] = shot_x[i] + shot_vx[i] * dt
      shot_y[i] = shot_y[i] + shot_vy[i] * dt

      if shot_x[i] < 0 or shot_x[i] > SCREEN_W or shot_y[i] < 0 or shot_y[i] > SCREEN_H then
        shot_life[i] = 0
      else
        for enemy = 1, ENEMY_COUNT do
          if shot_life[i] > 0 and enemy_alive[enemy] then
            local dx = shot_x[i] - enemy_x[enemy]
            local dy = shot_y[i] - enemy_y[enemy]
            local radius = enemy_radius[enemy]
            if dx * dx + dy * dy < radius * radius then
              shot_life[i] = 0
              enemy_health[enemy] = enemy_health[enemy] - 1
              spawn_impact(shot_x[i], shot_y[i], 43, 0.20, enemy_phase[enemy])
              spawn_burst(shot_x[i], shot_y[i], 0.2, 0.85, 1.0, 4)
              if enemy_health[enemy] <= 0 then
                enemy_alive[enemy] = false
                enemy_respawn[enemy] = 2.4
                score = score + 125
                kills = kills + 1
                spawn_burst(enemy_x[enemy], enemy_y[enemy], 1.0, 0.12, 0.72, 12)
              end
            end
          end
        end

        if shot_life[i] > 0 and boss_active then
          local boss_dx = shot_x[i] - boss_x
          local boss_dy = shot_y[i] - boss_y
          if boss_dx * boss_dx + boss_dy * boss_dy < 72 * 72 then
            shot_life[i] = 0
            boss_health = boss_health - 1
            boss_hit_flash = 0.16
            spawn_impact(shot_x[i], shot_y[i], 55, 0.24, boss_elapsed)
            spawn_burst(shot_x[i], shot_y[i], 0.28, 0.9, 1.0, 4)
            if boss_health <= 0 then
              boss_active = false
              boss_defeated = true
              boss_attack_active = false
              wave = 3
              score = score + 2500
              spawn_impact(boss_x, boss_y, 138, 0.55, boss_elapsed)
              spawn_burst(boss_x, boss_y, 1.0, 0.12, 0.72, 28)
            end
          end
        end
      end
    end
  end
end

local function update_particles(dt)
  for i = 1, PARTICLE_COUNT do
    if particle_life[i] > 0 then
      particle_life[i] = particle_life[i] - dt
      particle_x[i] = particle_x[i] + particle_vx[i] * dt
      particle_y[i] = particle_y[i] + particle_vy[i] * dt
      particle_vx[i] = particle_vx[i] * 0.982
      particle_vy[i] = particle_vy[i] * 0.982
    end
  end
end

local function update_impacts(dt)
  if impact_active_count <= 0 then return end
  for i = 1, IMPACT_COUNT do
    if impact_life[i] > 0 then
      impact_life[i] = math.max(0, impact_life[i] - dt)
      impact_angle[i] = impact_angle[i] + dt * 1.8
      if impact_life[i] <= 0 then
        impact_active_count = impact_active_count - 1
      end
    end
  end
end

local function update_bolts(dt)
  for i = 1, BOLT_COUNT do
    if bolt_life[i] > 0 then
      bolt_life[i] = bolt_life[i] - dt
      bolt_x[i] = bolt_x[i] + bolt_vx[i] * dt
      bolt_y[i] = bolt_y[i] + bolt_vy[i] * dt

      local player_dx = bolt_x[i] - player_x
      local player_dy = bolt_y[i] - player_y
      if player_dx * player_dx + player_dy * player_dy < 21 * 21 then
        bolt_life[i] = 0
        spawn_impact(bolt_x[i], bolt_y[i], 50, 0.24, bolt_angle[i])
        if shield_timer > 0 then
          shield_timer = math.max(0, shield_timer - 0.85)
          shield_hit_flash = 0.3
          spawn_burst(bolt_x[i], bolt_y[i], 0.2, 0.92, 1.0, 8)
        else
          energy = math.max(0, energy - 12)
          damage_flash = math.max(damage_flash, 0.24)
          spawn_burst(bolt_x[i], bolt_y[i], 1.0, 0.12, 0.72, 6)
        end
      elseif bolt_x[i] < -60 or bolt_x[i] > SCREEN_W + 60 or bolt_y[i] < -60 or bolt_y[i] > SCREEN_H + 60 then
        bolt_life[i] = 0
      end
    end

    if bolt_batch ~= nil then
      if bolt_life[i] > 0 then
        bolt_batch:set(
          bolt_batch_index[i],
          bolt_x[i], bolt_y[i], bolt_angle[i],
          0.04, 0.04,
          bolt_origin_x, bolt_origin_y
        )
      else
        bolt_batch:set(bolt_batch_index[i], -200, -200, 0, 0.04, 0.04)
      end
    end
  end
end

local function update_cells(dt)
  for i = 1, CELL_COUNT do
    if cell_active[i] then
      local dx = player_x - cell_x[i]
      local dy = player_y - cell_y[i]
      if dx * dx + dy * dy < 34 * 34 then
        cell_active[i] = false
        cell_respawn[i] = 4.5
        cells_collected = cells_collected + 1
        hud_cells = "CELLS " .. string.format("%02d", cells_collected)
        energy = math.min(100, energy + 28)
        set_relay_integrity(relay_integrity + 8)
        score = score + 75
        spawn_burst(cell_x[i], cell_y[i], 0.18, 0.92, 1.0, 9)
      end
    else
      cell_respawn[i] = cell_respawn[i] - dt
      if cell_respawn[i] <= 0 then
        cell_active[i] = true
        spawn_burst(cell_x[i], cell_y[i], 0.18, 0.92, 1.0, 5)
      end
    end

    if cell_batch ~= nil then
      if cell_active[i] then
        local pulse = 0.5 + 0.5 * math.sin(elapsed * 4.2 + cell_phase[i])
        local scale = 0.042 + pulse * 0.003
        cell_batch:set(
          cell_batch_index[i],
          cell_x[i], cell_y[i],
          elapsed * 0.34 + cell_phase[i],
          scale, scale,
          cell_origin_x, cell_origin_y
        )
      else
        cell_batch:set(cell_batch_index[i], -200, -200, 0, 0.04, 0.04)
      end
    end
  end
end

local function update_shields(dt)
  shield_timer = math.max(0, shield_timer - dt)
  shield_hit_flash = math.max(0, shield_hit_flash - dt)
  local display_second = math.ceil(shield_timer)
  if display_second ~= shield_display_second then
    shield_display_second = display_second
    if display_second > 0 then
      hud_shield = "SHIELD " .. string.format("%02d", display_second)
    else
      hud_shield = "SHIELD --"
    end
  end

  for i = 1, SHIELD_PICKUP_COUNT do
    if shield_active[i] then
      local dx = player_x - shield_x[i]
      local dy = player_y - shield_y[i]
      if dx * dx + dy * dy < 38 * 38 then
        shield_active[i] = false
        shield_respawn[i] = 9
        shield_timer = SHIELD_DURATION
        shield_display_second = -1
        score = score + 150
        spawn_burst(shield_x[i], shield_y[i], 0.25, 0.92, 1.0, 12)
      end
    else
      shield_respawn[i] = shield_respawn[i] - dt
      if shield_respawn[i] <= 0 then
        shield_active[i] = true
        spawn_burst(shield_x[i], shield_y[i], 0.25, 0.92, 1.0, 6)
      end
    end

    if shield_batch ~= nil then
      if shield_active[i] then
        local pulse = 0.5 + 0.5 * math.sin(elapsed * 3.8 + shield_phase[i])
        local scale = 0.043 + pulse * 0.003
        shield_batch:set(
          shield_batch_index[i],
          shield_x[i], shield_y[i],
          -elapsed * 0.22 + shield_phase[i],
          scale, scale,
          shield_origin_x, shield_origin_y
        )
      else
        shield_batch:set(shield_batch_index[i], -200, -200, 0, 0.04, 0.04)
      end
    end
  end
end

local function update_overdrive(dt)
  overdrive_timer = math.max(0, overdrive_timer - dt)
  local display_second = math.ceil(overdrive_timer)
  if display_second ~= overdrive_display_second then
    overdrive_display_second = display_second
    if display_second > 0 then
      hud_overdrive = "BOOST " .. string.format("%02d", display_second)
    else
      hud_overdrive = "BOOST --"
    end
  end

  if overdrive_active then
    local dx = player_x - overdrive_x
    local dy = player_y - overdrive_y
    if dx * dx + dy * dy < 40 * 40 then
      overdrive_active = false
      overdrive_respawn = 12
      overdrive_timer = OVERDRIVE_DURATION
      overdrive_display_second = -1
      score = score + 225
      spawn_burst(overdrive_x, overdrive_y, 1.0, 0.48, 0.08, 14)
    end
  else
    overdrive_respawn = overdrive_respawn - dt
    if overdrive_respawn <= 0 then
      overdrive_active = true
      spawn_burst(overdrive_x, overdrive_y, 0.24, 0.92, 1.0, 8)
    end
  end
end

local function update_boss(dt)
  if not boss_active then
    if not boss_defeated and kills >= 8 then
      activate_boss()
    end
    return
  end

  boss_hit_flash = math.max(0, boss_hit_flash - dt)
  boss_elapsed = boss_elapsed + dt
  boss_x = 400 + math.sin(boss_elapsed * 0.62) * 165
  boss_y = 170 + math.sin(boss_elapsed * 0.91) * 30
  boss_angle = math.sin(boss_elapsed * 0.44) * 0.16

  boss_attack_timer = boss_attack_timer - dt
  if boss_attack_timer <= 0 then
    boss_attack_timer = 2.6
    boss_attack_radius = 24
    boss_attack_active = true
    boss_attack_relay_hit = false
    spawn_burst(boss_x, boss_y, 1.0, 0.14, 0.72, 8)
  end


  boss_bolt_timer = boss_bolt_timer - dt
  if boss_bolt_timer <= 0 then
    boss_bolt_timer = 1.15
    spawn_bolt_volley()
  end

  if boss_attack_active then
    local previous_attack_radius = boss_attack_radius
    boss_attack_radius = boss_attack_radius + dt * 190
    local player_dx = player_x - boss_x
    local player_dy = player_y - boss_y
    local player_distance = math.sqrt(player_dx * player_dx + player_dy * player_dy)
    if math.abs(player_distance - boss_attack_radius) < 15 then
      if shield_timer > 0 then
        shield_timer = math.max(0, shield_timer - dt * 4)
        shield_hit_flash = math.max(shield_hit_flash, 0.12)
      else
        energy = math.max(0, energy - dt * 38)
        damage_flash = math.max(damage_flash, 0.12)
      end
    end
    local relay_dx = 400 - boss_x
    local relay_dy = 302 - boss_y
    local relay_distance = math.sqrt(relay_dx * relay_dx + relay_dy * relay_dy)
    if not boss_attack_relay_hit
        and previous_attack_radius < relay_distance
        and boss_attack_radius >= relay_distance then
      boss_attack_relay_hit = true
      set_relay_integrity(relay_integrity - 12)
      spawn_impact(400, 302, 62, 0.34, boss_elapsed)
      spawn_burst(400, 302, 1.0, 0.20, 0.72, 8)
    end
    if boss_attack_radius > 235 then
      boss_attack_active = false
    end
  end
end

function love.load(args)
  if args ~= nil then
    for i = 1, #args do
      local kernel_prefix = "--signal-kernel-frames="
      if string.sub(args[i], 1, #kernel_prefix) == kernel_prefix then
        local frame_total = tonumber(string.sub(args[i], #kernel_prefix + 1))
        assert(frame_total ~= nil and frame_total >= 1 and frame_total <= 100000,
          "signal kernel frames must be between 1 and 100000")
        run_signal_kernel(math.floor(frame_total))
        return
      end
      if args[i] == "--texture-probe" then
        local probe_chunk = love.filesystem.load("texture_probe.lua")
        local install_probe = probe_chunk()
        install_probe()
        return
      end
      if args[i] == "--composition-probe" then
        local probe_chunk = love.filesystem.load("composition_probe.lua")
        local install_probe = probe_chunk()
        install_probe()
        return
      end
      if args[i] == "--asset-probe" then
        local probe_chunk = love.filesystem.load("asset_probe.lua")
        probe_chunk()
        love.load()
        return
      end
    end
  end

  ensure_signal_lattice()

  love.graphics.setBackgroundColor(0.015, 0.02, 0.05)
  love.graphics.setLineStyle("rough")

  arena_image = love.graphics.newImage("art/neon_relay_arena.png", { linear = true, mipmaps = true })
  player_image = love.graphics.newImage("art/neon_relay_player.png", { linear = true, mipmaps = true })
  drone_image = love.graphics.newImage("art/neon_relay_drone.png", { linear = true, mipmaps = true })
  beacon_image = love.graphics.newImage("art/neon_relay_beacon.png", { linear = true, mipmaps = true })
  core_image = love.graphics.newImage("art/neon_relay_core.png", { linear = true, mipmaps = true })
  core_damaged_image = love.graphics.newImage("art/neon_relay_core_damaged.png", { linear = true, mipmaps = true })
  cell_image = love.graphics.newImage("art/neon_relay_cell.png", { linear = true, mipmaps = true })
  sentinel_image = love.graphics.newImage("art/neon_relay_sentinel.png", { linear = true, mipmaps = true })
  bolt_image = love.graphics.newImage("art/neon_relay_bolt.png", { linear = true, mipmaps = true })
  shield_image = love.graphics.newImage("art/neon_relay_shield.png", { linear = true, mipmaps = true })
  overdrive_image = love.graphics.newImage("art/neon_relay_overdrive.png", { linear = true, mipmaps = true })
  impact_image = love.graphics.newImage("art/neon_relay_impact.png", { linear = true, mipmaps = true })
  arena_image:setFilter("linear", "linear")
  player_image:setFilter("linear", "linear")
  drone_image:setFilter("linear", "linear")
  beacon_image:setFilter("linear", "linear")
  core_image:setFilter("linear", "linear")
  core_damaged_image:setFilter("linear", "linear")
  cell_image:setFilter("linear", "linear")
  sentinel_image:setFilter("linear", "linear")
  bolt_image:setFilter("linear", "linear")
  shield_image:setFilter("linear", "linear")
  overdrive_image:setFilter("linear", "linear")
  impact_image:setFilter("linear", "linear")

  drone_origin_x = drone_image:getWidth() * 0.5
  drone_origin_y = drone_image:getHeight() * 0.5
  cell_origin_x = cell_image:getWidth() * 0.5
  cell_origin_y = cell_image:getHeight() * 0.5
  sentinel_origin_x = sentinel_image:getWidth() * 0.5
  sentinel_origin_y = sentinel_image:getHeight() * 0.5
  bolt_origin_x = bolt_image:getWidth() * 0.5
  bolt_origin_y = bolt_image:getHeight() * 0.5
  shield_origin_x = shield_image:getWidth() * 0.5
  shield_origin_y = shield_image:getHeight() * 0.5
  overdrive_origin_x = overdrive_image:getWidth() * 0.5
  overdrive_origin_y = overdrive_image:getHeight() * 0.5
  impact_origin_x = impact_image:getWidth() * 0.5
  impact_origin_y = impact_image:getHeight() * 0.5
  core_origin_x = core_image:getWidth() * 0.5
  core_origin_y = core_image:getHeight() * 0.5
  core_damaged_origin_x = core_damaged_image:getWidth() * 0.5
  core_damaged_origin_y = core_damaged_image:getHeight() * 0.5

  drone_batch = love.graphics.newSpriteBatch(drone_image, ENEMY_COUNT, "dynamic")
  for i = 1, ENEMY_COUNT do
    drone_batch:add(
      enemy_x[i], enemy_y[i], enemy_phase[i],
      0.105, 0.105,
      drone_origin_x, drone_origin_y
    )
  end

  cell_batch = love.graphics.newSpriteBatch(cell_image, CELL_COUNT, "dynamic")
  for i = 1, CELL_COUNT do
    cell_batch:add(
      cell_x[i], cell_y[i], cell_phase[i],
      0.042, 0.042,
      cell_origin_x, cell_origin_y
    )
  end


  bolt_batch = love.graphics.newSpriteBatch(bolt_image, BOLT_COUNT, "dynamic")
  for i = 1, BOLT_COUNT do
    bolt_batch_index[i] = bolt_batch:add(-200, -200, 0, 0.04, 0.04)
  end

  shield_batch = love.graphics.newSpriteBatch(shield_image, SHIELD_PICKUP_COUNT, "dynamic")
  for i = 1, SHIELD_PICKUP_COUNT do
    shield_batch_index[i] = shield_batch:add(
      shield_x[i], shield_y[i], shield_phase[i],
      0.043, 0.043,
      shield_origin_x, shield_origin_y
    )
  end

  target_mesh = love.graphics.newMesh({
    { "VertexPosition", "float", 2 },
    { "VertexColor", "float", 4 },
  }, {
    { 0, -18, 0.20, 0.95, 1.0, 0.90 },
    { -16, 14, 0.90, 0.15, 0.95, 0.90 },
    { 16, 14, 1.0, 0.38, 0.75, 0.90 },
  }, "fan")

  reset_game()
  if args ~= nil then
    for i = 1, #args do
      if args[i] == "--parity-freeze" then
        freeze_parity_scene()
        break
      elseif args[i] == "--signal-lab" then
        activate_signal_lab()
        break
      end
    end
  end
end

function love.update(dt)
  if signal_kernel_only or parity_scene_frozen then
    return
  end

  dt = math.min(dt, 0.05)
  elapsed = elapsed + dt
  frame_count = frame_count + 1
  fps_timer = fps_timer + dt
  if fps_timer >= 0.5 then
    fps = frame_count / fps_timer
    hud_fps = string.format("FPS %03d", math.floor(fps + 0.5))
    frame_count = 0
    fps_timer = 0
  end


  if signal_lab_active then
    local checksum = signal_lattice.step(signal_state)
    neon_relay_signal_tick = signal_state.tick
    neon_relay_signal_checksum = checksum
    hud_signal = string.format(
      "SIM %03d x %02d  CRC %06d",
      signal_lattice.node_count,
      signal_lattice.substeps_per_frame,
      checksum
    )
    return
  end

  local move_x = 0
  local move_y = 0
  if love.keyboard.isDown("a", "left") then move_x = move_x - 1 end
  if love.keyboard.isDown("d", "right") then move_x = move_x + 1 end
  if love.keyboard.isDown("w", "up") then move_y = move_y - 1 end
  if love.keyboard.isDown("s", "down") then move_y = move_y + 1 end
  local move_length = math.sqrt(move_x * move_x + move_y * move_y)
  if move_length > 0 then
    move_x = move_x / move_length
    move_y = move_y / move_length
    local move_speed = overdrive_timer > 0 and 310 or 250
    player_x = clamp(player_x + move_x * move_speed * dt, 70, SCREEN_W - 70)
    player_y = clamp(player_y + move_y * move_speed * dt, 92, SCREEN_H - 92)
    player_angle = math.atan(move_y, move_x) + math.pi * 0.5
    energy = math.max(0, energy - dt * 3)
  end

  local aim_x, aim_y = pointer_in_world()
  if aim_x >= 0 and aim_x <= SCREEN_W and aim_y >= 0 and aim_y <= SCREEN_H then
    player_angle = math.atan(aim_y - player_y, aim_x - player_x) + math.pi * 0.5
  end

  fire_cooldown = math.max(0, fire_cooldown - dt)
  if energy >= 2 and fire_cooldown <= 0 and (love.keyboard.isDown("space") or love.mouse.isDown(1)) then
    fire_shot(aim_x, aim_y)
    energy = math.max(0, energy - (overdrive_timer > 0 and 1 or 2))
    fire_cooldown = overdrive_timer > 0 and 0.07 or 0.13
  end

  damage_flash = math.max(0, damage_flash - dt)
  update_enemies(dt)
  update_shots(dt)
  update_particles(dt)
  if impact_active_count > 0 then update_impacts(dt) end
  update_cells(dt)
  update_shields(dt)
  update_overdrive(dt)
  update_boss(dt)
  update_bolts(dt)
end

function love.keypressed(key)
  if key == "r" then
    parity_scene_frozen = false
    reset_game()
  elseif key == "b" then
    parity_scene_frozen = false
    reset_game()
    activate_boss()
  elseif key == "v" then
    freeze_parity_scene()
  elseif key == "c" then
    parity_scene_frozen = false
    activate_signal_lab()
  end
end

local function draw_arena()
  local arena_scale = SCREEN_W / arena_image:getWidth()
  love.graphics.setColor(0.68, 0.78, 0.92, 0.72)
  love.graphics.draw(arena_image, 0, -100, 0, arena_scale, arena_scale)

  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.10, 0.72, 0.95, 0.16)
  for x = 40, SCREEN_W - 40, 40 do
    love.graphics.line(x, 80, x, SCREEN_H - 70)
  end
  for y = 80, SCREEN_H - 70, 40 do
    love.graphics.line(40, y, SCREEN_W - 40, y)
  end

  love.graphics.setColor(0.05, 0.10, 0.22, 0.54)
  love.graphics.rectangle("fill", 34, 38, 732, 48, 8, 8)
  love.graphics.rectangle("fill", 34, SCREEN_H - 62, 732, 34, 8, 8)

  local pulse = 0.5 + 0.5 * math.sin(elapsed * 2.4)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.20, 0.92, 1.0, 0.45 + pulse * 0.2)
  love.graphics.arc("line", "open", 400, 302, 54 + pulse * 5, 0, math.pi * 2)
  love.graphics.setColor(0.96, 0.18, 0.72, 0.65)
  love.graphics.arc("line", "open", 400, 302, 68, elapsed * 0.8, elapsed * 0.8 + math.pi * 0.72)
  love.graphics.setColor(0.65, 0.95, 1.0, 0.16)
  love.graphics.circle("fill", 400, 302, 28 + pulse * 4)
  love.graphics.setColor(1.0, 1.0, 1.0, 0.78 + pulse * 0.14)
  love.graphics.draw(
    beacon_image,
    400, 302,
    elapsed * 0.16,
    0.074 + pulse * 0.004,
    0.074 + pulse * 0.004,
    beacon_image:getWidth() * 0.5,
    beacon_image:getHeight() * 0.5
  )
  local core_scale = 0.070 + pulse * 0.0025
  local relay_image = relay_integrity <= 45 and core_damaged_image or core_image
  local relay_origin_x = relay_integrity <= 45 and core_damaged_origin_x or core_origin_x
  local relay_origin_y = relay_integrity <= 45 and core_damaged_origin_y or core_origin_y
  love.graphics.setColor(1.0, 1.0, 1.0, 0.98)
  love.graphics.draw(
    relay_image,
    400, 302,
    -elapsed * 0.08,
    core_scale, core_scale,
    relay_origin_x, relay_origin_y
  )
  love.graphics.setColor(0.75, 0.98, 1.0, 0.95)
  love.graphics.circle("fill", 400, 302, 7 + pulse * 2)
end

local function draw_signal_lattice()
  if not signal_lab_active then return end

  local stride = math.floor(signal_lattice.node_count / SIGNAL_DISPLAY_NODE_COUNT)
  love.graphics.setLineWidth(1)
  for sample = 1, SIGNAL_DISPLAY_NODE_COUNT do
    local index = 1 + (sample - 1) * stride
    local next_sample = sample + 1
    if next_sample > SIGNAL_DISPLAY_NODE_COUNT then next_sample = 1 end
    local next_index = 1 + (next_sample - 1) * stride
    local strength = signal_state.signal[index]

    love.graphics.setColor(0.16, 0.68 + strength * 0.28, 1.0, 0.22 + strength * 0.24)
    love.graphics.line(
      signal_state.x[index], signal_state.y[index],
      signal_state.x[next_index], signal_state.y[next_index]
    )
    love.graphics.setColor(1.0, 0.16 + strength * 0.42, 0.78, 0.68)
    love.graphics.circle(
      "fill",
      signal_state.x[index], signal_state.y[index],
      2.5 + strength * 2.5
    )
  end
end

local function draw_projectiles()
  love.graphics.setLineWidth(3)
  for i = 1, SHOT_COUNT do
    if shot_life[i] > 0 then
      love.graphics.setColor(0.24, 0.92, 1.0, clamp(shot_life[i] * 2, 0.25, 1))
      love.graphics.line(
        shot_x[i], shot_y[i],
        shot_x[i] - shot_vx[i] * 0.018,
        shot_y[i] - shot_vy[i] * 0.018
      )
    end
  end
end

local function draw_bolts()
  for i = 1, BOLT_COUNT do
    if bolt_life[i] > 0 then
      local pulse = 0.5 + 0.5 * math.sin(elapsed * 12 + i)
      love.graphics.setColor(0.98, 0.12, 0.72, 0.10 + pulse * 0.07)
      love.graphics.circle("fill", bolt_x[i], bolt_y[i], 15 + pulse * 3)
    end
  end
  love.graphics.setColor(1, 1, 1, 0.98)
  if bolt_batch ~= nil then
    love.graphics.draw(bolt_batch)
  end
end

local function draw_particles()
  for i = 1, PARTICLE_COUNT do
    if particle_life[i] > 0 then
      local alpha = clamp(particle_life[i] / particle_max_life[i], 0, 1)
      love.graphics.setColor(particle_r[i], particle_g[i], particle_b[i], alpha)
      love.graphics.circle("fill", particle_x[i], particle_y[i], particle_size[i] * alpha)
    end
  end
end

local function draw_impacts()
  if impact_active_count <= 0 then return end
  for i = 1, IMPACT_COUNT do
    if impact_life[i] > 0 then
      local remaining = impact_life[i] / impact_max_life[i]
      local scale = impact_size[i] / impact_image:getWidth()
      scale = scale * (1.25 - remaining * 0.25)
      love.graphics.setColor(1, 1, 1, remaining * remaining)
      love.graphics.draw(
        impact_image,
        impact_x[i], impact_y[i], impact_angle[i],
        scale, scale,
        impact_origin_x, impact_origin_y
      )
    end
  end
end

local function draw_cells()
  for i = 1, CELL_COUNT do
    if cell_active[i] then
      local pulse = 0.5 + 0.5 * math.sin(elapsed * 4.2 + cell_phase[i])
      love.graphics.setColor(0.12, 0.88, 1.0, 0.10 + pulse * 0.10)
      love.graphics.circle("fill", cell_x[i], cell_y[i], 26 + pulse * 6)
    end
  end
  love.graphics.setColor(1, 1, 1, 0.94)
  if cell_batch ~= nil then
    love.graphics.draw(cell_batch)
  end
end

local function draw_shields()
  for i = 1, SHIELD_PICKUP_COUNT do
    if shield_active[i] then
      local pulse = 0.5 + 0.5 * math.sin(elapsed * 3.8 + shield_phase[i])
      love.graphics.setColor(0.20, 0.92, 1.0, 0.08 + pulse * 0.10)
      love.graphics.circle("fill", shield_x[i], shield_y[i], 31 + pulse * 7)
      love.graphics.setColor(0.76, 0.98, 1.0, 0.34 + pulse * 0.18)
      love.graphics.circle("line", shield_x[i], shield_y[i], 34 + pulse * 4)
    end
  end
  love.graphics.setColor(1, 1, 1, 0.96)
  if shield_batch ~= nil then
    love.graphics.draw(shield_batch)
  end
end

local function draw_overdrive()
  if not overdrive_active then return end
  local pulse = 0.5 + 0.5 * math.sin(elapsed * 4.8 + overdrive_phase)
  love.graphics.setColor(1.0, 0.42, 0.08, 0.08 + pulse * 0.10)
  love.graphics.circle("fill", overdrive_x, overdrive_y, 35 + pulse * 8)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.24, 0.92, 1.0, 0.36 + pulse * 0.20)
  love.graphics.arc(
    "line", "open", overdrive_x, overdrive_y, 38 + pulse * 3,
    -elapsed * 1.1, -elapsed * 1.1 + math.pi * 1.45
  )
  love.graphics.setColor(1, 1, 1, 0.98)
  local scale = 0.044 + pulse * 0.003
  love.graphics.draw(
    overdrive_image,
    overdrive_x, overdrive_y,
    elapsed * 0.28 + overdrive_phase,
    scale, scale,
    overdrive_origin_x, overdrive_origin_y
  )
end

local function draw_enemy_readouts()
  love.graphics.setLineWidth(1)
  for i = 1, ENEMY_COUNT do
    if enemy_alive[i] then
      local health_fraction = enemy_health[i] / (i <= 4 and 3 or 2)
      love.graphics.setColor(0.96, 0.18, 0.72, 0.75)
      love.graphics.arc("line", "open", enemy_x[i], enemy_y[i], enemy_radius[i] + 10, -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2 * health_fraction)
      love.graphics.setColor(1.0, 0.36, 0.68, 0.55)
      love.graphics.circle("line", enemy_x[i], enemy_y[i], enemy_radius[i] + 18 + math.sin(elapsed * 3 + enemy_phase[i]) * 2)
    end
  end
end

local function draw_boss()
  if not boss_active then return end

  local pulse = 0.5 + 0.5 * math.sin(boss_elapsed * 5.4)
  if boss_attack_active then
    love.graphics.setLineWidth(3)
    love.graphics.setColor(1.0, 0.14, 0.72, 0.72)
    love.graphics.circle("line", boss_x, boss_y, boss_attack_radius)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.24, 0.92, 1.0, 0.28)
    love.graphics.circle("line", boss_x, boss_y, boss_attack_radius + 7)
  end

  love.graphics.setColor(0.98, 0.12, 0.72, 0.14 + pulse * 0.10)
  love.graphics.circle("fill", boss_x, boss_y, 92 + pulse * 10)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.98, 0.18, 0.76, 0.72)
  love.graphics.arc("line", "open", boss_x, boss_y, 84, boss_elapsed * 0.7, boss_elapsed * 0.7 + math.pi * 1.45)

  local hit = boss_hit_flash > 0 and 0.65 or 0
  love.graphics.setColor(1.0, 1.0 - hit * 0.35, 1.0, 1.0)
  love.graphics.draw(
    sentinel_image,
    boss_x, boss_y, boss_angle,
    0.145, 0.145,
    sentinel_origin_x, sentinel_origin_y
  )

  local health_fraction = boss_health / BOSS_MAX_HEALTH
  love.graphics.setColor(0.14, 0.04, 0.20, 0.92)
  love.graphics.rectangle("fill", boss_x - 74, boss_y + 92, 148, 7, 3, 3)
  love.graphics.setColor(0.98, 0.16, 0.72, 0.94)
  love.graphics.rectangle("fill", boss_x - 74, boss_y + 92, 148 * health_fraction, 7, 3, 3)
  love.graphics.setColor(1.0, 0.58, 0.86, 0.92)
  love.graphics.print("SENTINEL " .. string.format("%02d", boss_health), boss_x - 48, boss_y + 103)
end

local function draw_player(aim_x, aim_y)
  local thrust = 0.5 + 0.5 * math.sin(elapsed * 16)
  if shield_timer > 0 then
    local shield_pulse = 0.5 + 0.5 * math.sin(elapsed * 8)
    local hit_alpha = shield_hit_flash > 0 and 0.28 or 0
    love.graphics.setColor(0.18, 0.90, 1.0, 0.10 + shield_pulse * 0.06 + hit_alpha)
    love.graphics.circle("fill", player_x, player_y, 48 + shield_pulse * 3)
    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.62, 0.98, 1.0, 0.72 + shield_pulse * 0.18)
    love.graphics.arc("line", "open", player_x, player_y, 52, elapsed * 1.4, elapsed * 1.4 + math.pi * 1.5)
  end
  love.graphics.setColor(0.15, 0.88, 1.0, 0.24)
  love.graphics.circle("fill", player_x, player_y + 18, 30 + thrust * 8)
  love.graphics.setColor(1.0, 0.42, 0.12, 0.48)
  love.graphics.circle("fill", player_x, player_y + 26, 14 + thrust * 6)

  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.24, 0.92, 1.0, 0.72)
  love.graphics.line(player_x, player_y, aim_x, aim_y)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(
    player_image,
    player_x, player_y, player_angle,
    0.145, 0.145,
    player_image:getWidth() * 0.5, player_image:getHeight() * 0.5
  )
end

local function draw_hud()
  love.graphics.setColor(0.72, 0.94, 1.0, 0.95)
  love.graphics.print("NEON RELAY  //  SECTOR 07", 52, 52)
  love.graphics.setColor(0.96, 0.28, 0.72, 0.90)
  love.graphics.print(signal_lab_active and "SIGNAL LAB" or "LIVE COMBAT", 625, 52)
  if signal_lab_active then
    love.graphics.setColor(0.38, 0.94, 1.0, 0.90)
    love.graphics.print(hud_signal, 292, 52)
  end
  love.graphics.setColor(0.42, 0.92, 1.0, 0.88)
  love.graphics.print(hud_cells, 672, 102)
  love.graphics.setColor(0.72, 0.98, 1.0, 0.90)
  love.graphics.print(hud_shield, 650, 118)
  love.graphics.setColor(1.0, 0.62, 0.24, 0.90)
  love.graphics.print(hud_overdrive, 650, 134)
  love.graphics.setColor(0.58, 0.96, 1.0, 0.90)
  love.graphics.print(hud_relay, 650, 150)

  love.graphics.setColor(0.70, 0.86, 0.95, 0.88)
  love.graphics.print("WAVE " .. string.format("%02d", wave), 52, SCREEN_H - 52)
  love.graphics.print("SCORE " .. string.format("%05d", score), 150, SCREEN_H - 52)
  love.graphics.print(hud_fps, 668, SCREEN_H - 52)

  love.graphics.setColor(0.10, 0.25, 0.42, 0.85)
  love.graphics.rectangle("fill", 280, SCREEN_H - 53, 265, 9, 4, 4)
  love.graphics.setColor(0.20, 0.92, 1.0, 0.9)
  love.graphics.rectangle("fill", 280, SCREEN_H - 53, 265 * (energy / 100), 9, 4, 4)
  love.graphics.setColor(0.70, 0.86, 0.95, 0.85)
  love.graphics.print("ENERGY", 552, SCREEN_H - 55)

  love.graphics.setColor(0.63, 0.79, 0.92, 0.8)
  love.graphics.print("WASD / ARROWS MOVE    SPACE / CLICK FIRE    R RESET", 52, 102)
  love.graphics.setColor(0.30, 0.72, 0.92, 0.7)
  love.graphics.print("FIXED ARRAYS / B BOSS / C SIGNAL LAB / V PARITY FREEZE", 52, 118)
end

function love.draw()
  if signal_kernel_only then return end
  local scale, offset_x, offset_y = screen_transform()
  local aim_x, aim_y = pointer_in_world()
  aim_x = clamp(aim_x, 0, SCREEN_W)
  aim_y = clamp(aim_y, 0, SCREEN_H)

  love.graphics.push()
  love.graphics.translate(offset_x, offset_y)
  love.graphics.scale(scale, scale)

  draw_arena()
  draw_signal_lattice()

  draw_cells()
  draw_shields()
  draw_overdrive()

  love.graphics.setColor(1, 1, 1, 1)
  if drone_batch ~= nil then
    love.graphics.draw(drone_batch)
  end
  draw_boss()
  draw_enemy_readouts()
  draw_bolts()
  draw_projectiles()
  draw_particles()
  if impact_active_count > 0 then draw_impacts() end

  love.graphics.setColor(0.24, 0.92, 1.0, 0.55)
  love.graphics.circle("line", aim_x, aim_y, 13 + math.sin(elapsed * 5) * 2)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.draw(target_mesh, aim_x, aim_y, elapsed * 0.7)
  draw_player(aim_x, aim_y)

  draw_hud()
  if damage_flash > 0 then
    love.graphics.setColor(1.0, 0.1, 0.25, damage_flash * 0.2)
    love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
  end

  love.graphics.setColor(0.28, 0.82, 1.0, 0.65)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", 34, 38, 732, 524, 8, 8)
  love.graphics.pop()
end
