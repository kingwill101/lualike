local SCREEN_WIDTH = 320
local SCREEN_HEIGHT = 480
local HUD_HEIGHT = 64
local PLAY_TOP = 56
local PLAY_LEFT = 18
local PLAY_RIGHT = SCREEN_WIDTH - 18
local PLAYER_Y = 428
local PLAYER_SPEED = 175
local PLAYER_W = 20
local PLAYER_H = 10
local PLAYER_COOLDOWN = 0.22
local PLAYER_BULLET_SPEED = 300
local ENEMY_BULLET_SPEED = 160
local SAVE_PATH = "space_invaders_save.lua"

local palette = {
  bg = { 0.03, 0.05, 0.02, 1.0 },
  panel = { 0.05, 0.09, 0.04, 1.0 },
  border = { 0.52, 0.92, 0.28, 1.0 },
  text = { 0.78, 1.00, 0.52, 1.0 },
  textDim = { 0.48, 0.74, 0.32, 1.0 },
  player = { 0.82, 1.00, 0.44, 1.0 },
  playerDark = { 0.38, 0.60, 0.20, 1.0 },
  invader1 = { 0.82, 1.00, 0.44, 1.0 },
  invader2 = { 0.70, 0.96, 0.36, 1.0 },
  invader3 = { 0.58, 0.90, 0.28, 1.0 },
  bullet = { 0.98, 1.00, 0.68, 1.0 },
  enemyBullet = { 0.98, 0.63, 0.32, 1.0 },
  shield = { 0.58, 0.92, 0.34, 1.0 },
  shieldDark = { 0.22, 0.40, 0.14, 1.0 },
  star = { 0.70, 0.92, 0.50, 0.55 },
  scan = { 0.00, 0.00, 0.00, 0.08 },
}

local state = "menu"
local score = 0
local bestScore = 0
local lives = 3
local wave = 1
local progressDirty = false
local gameOverReason = ""

local player = { x = SCREEN_WIDTH / 2, y = PLAYER_Y, cooldown = 0 }
local playerBullet = nil
local enemyBullets = {}
local invaders = {}
local bunkers = {}
local stars = {}
local invaderFormation = { x = 0, y = 0, dir = 1 }
local moveTimer = 0
local shootTimer = 0
local moveInterval = 0.52
local invaderStepPx = 6
local invaderDropPx = 12
local inputLeft = false
local inputRight = false
local inputFire = false

local INVADER_COLS = 11
local INVADER_ROWS = 5
local INVADER_W = 16
local INVADER_H = 12
local INVADER_X_GAP = 20
local INVADER_Y_GAP = 18
local INVADER_START_X = 48
local INVADER_START_Y = 104
local BUNKER_BASE_Y = 338
local BUNKER_COUNT = 4
local BUNKER_CELL = 6
local BUNKER_COLS = 6
local BUNKER_ROWS = 4

local function randomRange(min, max)
  return min + love.math.random() * (max - min)
end

local function cellKey(x, y)
  return x .. ':' .. y
end

local function setColor(color)
  love.graphics.setColor(color)
end

local function loadProgress()
  local info = love.filesystem.getInfo(SAVE_PATH)
  if not info then
    return
  end
  local content = love.filesystem.read(SAVE_PATH)
  if not content then
    return
  end
  local best = tonumber(content:match('bestScore=(%d+)'))
  if best then
    bestScore = best
  end
end

local function saveProgress()
  love.filesystem.write(SAVE_PATH, string.format('bestScore=%d\n', bestScore))
end

local function resetPlayer()
  player.x = SCREEN_WIDTH / 2
  player.cooldown = 0
  playerBullet = nil
  enemyBullets = {}
end

local function makeStars()
  stars = {}
  for _ = 1, 28 do
    stars[#stars + 1] = {
      x = love.math.random(0, SCREEN_WIDTH - 1),
      y = love.math.random(PLAY_LEFT, PLAYER_Y - 64),
      r = randomRange(0.6, 1.6),
    }
  end
end

local function buildBunkers()
  bunkers = {}
  local bunkerWidth = BUNKER_COLS * BUNKER_CELL
  local gap = 18
  local totalWidth = BUNKER_COUNT * bunkerWidth + (BUNKER_COUNT - 1) * gap
  local startX = math.floor((SCREEN_WIDTH - totalWidth) / 2)

  for bunkerIndex = 1, BUNKER_COUNT do
    local baseX = startX + (bunkerIndex - 1) * (bunkerWidth + gap)
    local baseY = BUNKER_BASE_Y
    for row = 1, BUNKER_ROWS do
      for col = 1, BUNKER_COLS do
        local hp = 3
        if row == 1 and (col == 1 or col == BUNKER_COLS) then
          hp = 2
        end
        bunkers[#bunkers + 1] = {
          x = baseX + (col - 1) * BUNKER_CELL,
          y = baseY + (row - 1) * BUNKER_CELL,
          w = BUNKER_CELL,
          h = BUNKER_CELL,
          hp = hp,
        }
      end
    end
  end
end

local function spawnWave()
  invaders = {}
  local centerWidth = (INVADER_COLS - 1) * INVADER_X_GAP + INVADER_W
  invaderFormation.x = math.floor((SCREEN_WIDTH - centerWidth) / 2)
  invaderFormation.y = 0
  invaderFormation.dir = 1
  moveTimer = 0
  shootTimer = 0
  moveInterval = math.max(0.14, 0.52 - (wave - 1) * 0.03)
  invaderStepPx = math.min(9, 6 + math.floor((wave - 1) / 2))
  invaderDropPx = 12

  for row = 1, INVADER_ROWS do
    for col = 1, INVADER_COLS do
      invaders[#invaders + 1] = {
        row = row,
        col = col,
        x = INVADER_START_X + (col - 1) * INVADER_X_GAP,
        y = INVADER_START_Y + (row - 1) * INVADER_Y_GAP,
        w = INVADER_W,
        h = INVADER_H,
        alive = true,
      }
    end
  end

  buildBunkers()
end

local function restartGame()
  inputFire = false
  if progressDirty then
    saveProgress()
    progressDirty = false
  end
  score = 0
  lives = 3
  wave = 1
  gameOverReason = ""
  resetPlayer()
  spawnWave()
  state = "playing"
end

local function enemyBounds()
  local minX, maxX, maxY = nil, nil, nil
  for _, invader in ipairs(invaders) do
    if invader.alive then
      local x = invaderFormation.x + invader.x
      local y = invaderFormation.y + invader.y
      minX = minX and math.min(minX, x) or x
      maxX = maxX and math.max(maxX, x + invader.w) or (x + invader.w)
      maxY = maxY and math.max(maxY, y + invader.h) or (y + invader.h)
    end
  end
  return minX, maxX, maxY
end

local function anyInvadersAlive()
  for _, invader in ipairs(invaders) do
    if invader.alive then
      return true
    end
  end
  return false
end

local function chooseShooter()
  local bottomByColumn = {}
  for _, invader in ipairs(invaders) do
    if invader.alive then
      local current = bottomByColumn[invader.col]
      if current == nil or invader.row > current.row then
        bottomByColumn[invader.col] = invader
      end
    end
  end

  local choices = {}
  for _, invader in pairs(bottomByColumn) do
    choices[#choices + 1] = invader
  end
  if #choices == 0 then
    return nil
  end
  return choices[love.math.random(#choices)]
end

local function firePlayerBullet()
  if player.cooldown > 0 or playerBullet ~= nil then
    return
  end
  playerBullet = {
    x = player.x,
    y = player.y - PLAYER_H * 0.5 - 2,
    vy = -PLAYER_BULLET_SPEED,
  }
  player.cooldown = PLAYER_COOLDOWN
end

local function fireEnemyBullet()
  local shooter = chooseShooter()
  if shooter == nil then
    return
  end
  enemyBullets[#enemyBullets + 1] = {
    x = invaderFormation.x + shooter.x + shooter.w * 0.5,
    y = invaderFormation.y + shooter.y + shooter.h + 2,
    vy = ENEMY_BULLET_SPEED + wave * 4,
  }
end

local function rectsOverlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function pointInRect(px, py, rect)
  return px >= rect.x and px <= rect.x + rect.w and py >= rect.y and py <= rect.y + rect.h
end

local function damageBunkers(x, y)
  for index = #bunkers, 1, -1 do
    local bunker = bunkers[index]
    if pointInRect(x, y, bunker) then
      bunker.hp = bunker.hp - 1
      if bunker.hp <= 0 then
        table.remove(bunkers, index)
      end
      return true
    end
  end
  return false
end

local function loseLife(reason)
  lives = lives - 1
  gameOverReason = reason or ""
  playerBullet = nil
  enemyBullets = {}
  resetPlayer()
  if lives <= 0 then
    state = "gameover"
    if score > bestScore then
      bestScore = score
      progressDirty = true
    end
    if progressDirty then
      saveProgress()
      progressDirty = false
    end
  end
end

local function clearWaveIfNeeded()
  if anyInvadersAlive() then
    return
  end
  wave = wave + 1
  spawnWave()
end

local function updatePlayer(dt)
  local moveAxis = 0
  if inputLeft then
    moveAxis = moveAxis - 1
  end
  if inputRight then
    moveAxis = moveAxis + 1
  end
  player.x = math.max(PLAY_LEFT + PLAYER_W * 0.5, math.min(PLAY_RIGHT - PLAYER_W * 0.5, player.x + moveAxis * PLAYER_SPEED * dt))
  if player.cooldown > 0 then
    player.cooldown = math.max(0, player.cooldown - dt)
  end
  if inputFire then
    inputFire = false
    firePlayerBullet()
  end
end

local function updatePlayerBullet(dt)
  if playerBullet == nil then
    return
  end

  playerBullet.y = playerBullet.y + playerBullet.vy * dt
  if playerBullet.y < PLAY_TOP then
    playerBullet = nil
    return
  end

  if damageBunkers(playerBullet.x, playerBullet.y) then
    playerBullet = nil
    return
  end

  for _, invader in ipairs(invaders) do
    if invader.alive then
      local ix = invaderFormation.x + invader.x
      local iy = invaderFormation.y + invader.y
      if rectsOverlap(playerBullet.x - 1, playerBullet.y - 4, 2, 8, ix, iy, invader.w, invader.h) then
        invader.alive = false
        playerBullet = nil
        local points = (INVADER_ROWS - invader.row + 1) * 10
        score = score + points
        if score > bestScore then
          bestScore = score
          progressDirty = true
        end
        clearWaveIfNeeded()
        return
      end
    end
  end
end

local function updateEnemyBullets(dt)
  for index = #enemyBullets, 1, -1 do
    local bullet = enemyBullets[index]
    bullet.y = bullet.y + bullet.vy * dt
    if bullet.y > SCREEN_HEIGHT + 12 then
      table.remove(enemyBullets, index)
    elseif damageBunkers(bullet.x, bullet.y) then
      table.remove(enemyBullets, index)
    elseif rectsOverlap(bullet.x - 1, bullet.y - 4, 2, 8, player.x - PLAYER_W * 0.5, player.y - PLAYER_H * 0.5, PLAYER_W, PLAYER_H) then
      table.remove(enemyBullets, index)
      loseLife("hit by laser")
      return
    end
  end
end

local function updateInvaders(dt)
  moveTimer = moveTimer + dt
  shootTimer = shootTimer + dt

  if moveTimer >= moveInterval then
    moveTimer = moveTimer - moveInterval
    local minX, maxX, maxY = enemyBounds()
    if minX == nil then
      clearWaveIfNeeded()
      return
    end

    local nextX = invaderFormation.x + invaderFormation.dir * invaderStepPx
    if nextX + minX < PLAY_LEFT or nextX + maxX > PLAY_RIGHT then
      invaderFormation.dir = -invaderFormation.dir
      invaderFormation.y = invaderFormation.y + invaderDropPx
      if invaderFormation.y + maxY > PLAYER_Y - 24 then
        loseLife("the swarm reached the base")
        return
      end
    else
      invaderFormation.x = nextX
    end
  end

  if shootTimer >= math.max(0.2, 1.15 - (wave - 1) * 0.05) then
    shootTimer = 0
    fireEnemyBullet()
  end
end

local function updateGameplay(dt)
  updatePlayer(dt)
  updatePlayerBullet(dt)
  if state ~= "playing" then
    return
  end
  updateEnemyBullets(dt)
  if state ~= "playing" then
    return
  end
  updateInvaders(dt)
end

local function drawTextCentered(text, y, color, scale)
  setColor(color)
  local font = love.graphics.getFont()
  local width = font:getWidth(text) * (scale or 1)
  love.graphics.print(text, math.floor((SCREEN_WIDTH - width) / 2), y, 0, scale or 1, scale or 1)
end

local function drawStarfield()
  setColor(palette.star)
  for _, star in ipairs(stars) do
    love.graphics.points(star.x, star.y)
  end
end

local function drawBunkers()
  for _, bunker in ipairs(bunkers) do
    local color = bunker.hp >= 3 and palette.shield or palette.shieldDark
    setColor(color)
    love.graphics.rectangle("fill", bunker.x, bunker.y, bunker.w, bunker.h, 1, 1)
  end
end

local function drawInvaders()
  for _, invader in ipairs(invaders) do
    if invader.alive then
      local x = invaderFormation.x + invader.x
      local y = invaderFormation.y + invader.y
      local color = (invader.row <= 2) and palette.invader1 or (invader.row <= 4 and palette.invader2 or palette.invader3)
      setColor(color)
      love.graphics.rectangle("fill", x, y, invader.w, invader.h, 2, 2)
      love.graphics.rectangle("fill", x + 3, y + 3, invader.w - 6, 3, 1, 1)
      if invader.row >= 4 then
        love.graphics.rectangle("fill", x + 2, y + invader.h - 3, 3, 3, 1, 1)
        love.graphics.rectangle("fill", x + invader.w - 5, y + invader.h - 3, 3, 3, 1, 1)
      end
    end
  end
end

local function drawPlayer()
  setColor(palette.player)
  love.graphics.rectangle("fill", player.x - PLAYER_W * 0.5, player.y - PLAYER_H * 0.5, PLAYER_W, PLAYER_H, 2, 2)
  setColor(palette.playerDark)
  love.graphics.rectangle("fill", player.x - 6, player.y - 3, 12, 3, 1, 1)
end

local function drawBullets()
  if playerBullet ~= nil then
    setColor(palette.bullet)
    love.graphics.rectangle("fill", playerBullet.x - 1, playerBullet.y - 5, 2, 8, 1, 1)
  end
  setColor(palette.enemyBullet)
  for _, bullet in ipairs(enemyBullets) do
    love.graphics.rectangle("fill", bullet.x - 1, bullet.y - 5, 2, 8, 1, 1)
  end
end

local function drawPlayfield()
  setColor(palette.panel)
  love.graphics.rectangle("fill", 10, 56, SCREEN_WIDTH - 20, SCREEN_HEIGHT - 70, 6, 6)
  setColor(palette.border)
  love.graphics.rectangle("line", 10, 56, SCREEN_WIDTH - 20, SCREEN_HEIGHT - 70, 6, 6)
  drawStarfield()
  drawBunkers()
  drawInvaders()
  drawBullets()
  drawPlayer()
end

local function drawScanlines()
  setColor(palette.scan)
  for y = 0, SCREEN_HEIGHT, 4 do
    love.graphics.rectangle("fill", 0, y, SCREEN_WIDTH, 1)
  end
end

function love.load()
  love.graphics.setBackgroundColor(palette.bg)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setFont(love.graphics.newFont(12))
  love.math.setRandomSeed(os.time())
  loadProgress()
  makeStars()
  restartGame()
  state = "menu"
end

function love.keypressed(key)
  if key == "left" or key == "a" then
    inputLeft = true
    if state == "menu" then
      restartGame()
    end
  elseif key == "right" or key == "d" then
    inputRight = true
    if state == "menu" then
      restartGame()
    end
  elseif key == "space" or key == "return" then
    if state ~= "playing" then
      restartGame()
      return
    end
    inputFire = true
  elseif key == "r" then
    restartGame()
  end
end

function love.keyreleased(key)
  if key == "left" or key == "a" then
    inputLeft = false
  elseif key == "right" or key == "d" then
    inputRight = false
  end
end

function love.touchpressed(_, _, _)
  if state ~= "playing" then
    restartGame()
    return
  end
  inputFire = true
end

function love.update(dt)
  if state == "playing" then
    updateGameplay(dt)
  elseif state == "gameover" then
    if score > bestScore then
      bestScore = score
      progressDirty = true
    end
  end
end

function love.quit()
  if progressDirty then
    saveProgress()
    progressDirty = false
  end
end

function love.draw()
  love.graphics.clear(palette.bg)
  drawPlayfield()

  setColor(palette.text)
  love.graphics.print(string.format("SCORE %04d", score), 16, 14)
  love.graphics.print(string.format("BEST %04d", bestScore), 124, 14)
  love.graphics.print(string.format("LIVES %d", lives), 236, 14)
  love.graphics.print(string.format("WAVE %02d", wave), 16, 30)

  if state == "menu" then
    drawTextCentered("SPACE INVADERS", 198, palette.text, 1.5)
    drawTextCentered("PRESS FIRE OR ARROW KEYS", 222, palette.textDim, 1)
    drawTextCentered("OLD-SCHOOL ARCADE MODE", 242, palette.textDim, 1)
  elseif state == "gameover" then
    drawTextCentered("GAME OVER", 200, palette.text, 1.5)
    drawTextCentered(gameOverReason, 224, palette.textDim, 1)
    drawTextCentered("PRESS ENTER TO RESTART", 246, palette.textDim, 1)
  else
    drawTextCentered("ARROWS / WASD TO MOVE", 438, palette.textDim, 1)
    drawTextCentered("SPACE TO FIRE", 456, palette.textDim, 1)
  end

  drawScanlines()
end
