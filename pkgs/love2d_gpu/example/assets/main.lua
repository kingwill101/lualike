-- Neon Relay: a deterministic, asset-backed LOVE scene for renderer parity.
--
-- The hot paths deliberately use fixed-capacity arrays.  The game is small,
-- but it is busy enough to expose frame pacing, texture filtering, batching,
-- alpha blending, mesh colors, input, and text in both render backends. Four
-- generated textures keep the asset path real without allocating per frame.

local SCREEN_W = 800
local SCREEN_H = 600
local ENEMY_COUNT = 8
local SHOT_COUNT = 24
local PARTICLE_COUNT = 72

local arena_image = nil
local player_image = nil
local drone_image = nil
local beacon_image = nil
local drone_batch = nil
local target_mesh = nil

local elapsed = 0
local frame_count = 0
local fps_timer = 0
local fps = 0
local hud_fps = "FPS --"
local score = 0
local wave = 1
local energy = 100
local kills = 0
local fire_cooldown = 0
local damage_flash = 0

local player_x = 400
local player_y = 470
local player_angle = 0

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

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
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

local function reset_game()
  player_x = 400
  player_y = 470
  player_angle = 0
  score = 0
  wave = 1
  energy = 100
  kills = 0
  fire_cooldown = 0
  damage_flash = 0

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
  for i = 1, ENEMY_COUNT do
    enemy_alive[i] = true
    enemy_respawn[i] = 0
    enemy_health[i] = i <= 4 and 3 or 2
  end
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
          drone_image:getWidth() * 0.5, drone_image:getHeight() * 0.5
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

function love.load()
  love.graphics.setBackgroundColor(0.015, 0.02, 0.05)
  love.graphics.setLineStyle("rough")

  arena_image = love.graphics.newImage("art/neon_relay_arena.png", { linear = true })
  player_image = love.graphics.newImage("art/neon_relay_player.png", { linear = true })
  drone_image = love.graphics.newImage("art/neon_relay_drone.png", { linear = true })
  beacon_image = love.graphics.newImage("art/neon_relay_beacon.png", { linear = true })
  arena_image:setFilter("linear", "linear")
  player_image:setFilter("linear", "linear")
  drone_image:setFilter("linear", "linear")
  beacon_image:setFilter("linear", "linear")

  drone_batch = love.graphics.newSpriteBatch(drone_image, ENEMY_COUNT, "dynamic")
  for i = 1, ENEMY_COUNT do
    drone_batch:add(
      enemy_x[i], enemy_y[i], enemy_phase[i],
      0.105, 0.105,
      drone_image:getWidth() * 0.5, drone_image:getHeight() * 0.5
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
end

function love.update(dt)
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
    player_x = clamp(player_x + move_x * 250 * dt, 70, SCREEN_W - 70)
    player_y = clamp(player_y + move_y * 250 * dt, 92, SCREEN_H - 92)
    player_angle = math.atan(move_y, move_x) + math.pi * 0.5
  end

  local aim_x, aim_y = pointer_in_world()
  if aim_x >= 0 and aim_x <= SCREEN_W and aim_y >= 0 and aim_y <= SCREEN_H then
    player_angle = math.atan(aim_y - player_y, aim_x - player_x) + math.pi * 0.5
  end

  fire_cooldown = math.max(0, fire_cooldown - dt)
  if fire_cooldown <= 0 and (love.keyboard.isDown("space") or love.mouse.isDown(1)) then
    fire_shot(aim_x, aim_y)
    fire_cooldown = 0.13
  end

  damage_flash = math.max(0, damage_flash - dt)
  update_enemies(dt)
  update_shots(dt)
  update_particles(dt)

  if kills >= 8 then
    wave = 2
  end
end

function love.keypressed(key)
  if key == "r" then
    reset_game()
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
  love.graphics.setColor(0.75, 0.98, 1.0, 0.95)
  love.graphics.circle("fill", 400, 302, 7 + pulse * 2)
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

local function draw_particles()
  for i = 1, PARTICLE_COUNT do
    if particle_life[i] > 0 then
      local alpha = clamp(particle_life[i] / particle_max_life[i], 0, 1)
      love.graphics.setColor(particle_r[i], particle_g[i], particle_b[i], alpha)
      love.graphics.circle("fill", particle_x[i], particle_y[i], particle_size[i] * alpha)
    end
  end
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

local function draw_player(aim_x, aim_y)
  local thrust = 0.5 + 0.5 * math.sin(elapsed * 16)
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
  love.graphics.print("LIVE COMBAT", 625, 52)

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
  love.graphics.print("FIXED ARRAYS  /  DYNAMIC SPRITE BATCH  /  MSAA COMPARISON", 52, 118)
end

function love.draw()
  local scale, offset_x, offset_y = screen_transform()
  local aim_x, aim_y = pointer_in_world()
  aim_x = clamp(aim_x, 0, SCREEN_W)
  aim_y = clamp(aim_y, 0, SCREEN_H)

  love.graphics.push()
  love.graphics.translate(offset_x, offset_y)
  love.graphics.scale(scale, scale)

  draw_arena()

  love.graphics.setColor(1, 1, 1, 1)
  if drone_batch ~= nil then
    love.graphics.draw(drone_batch)
  end
  draw_enemy_readouts()
  draw_projectiles()
  draw_particles()

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
