local TILE = 12
local GRID_WIDTH = 20
local GRID_HEIGHT = 26
local BOARD_WIDTH = GRID_WIDTH * TILE
local BOARD_HEIGHT = GRID_HEIGHT * TILE
local SCREEN_WIDTH = 320
local SCREEN_HEIGHT = 480
local BOARD_X = math.floor((SCREEN_WIDTH - BOARD_WIDTH) / 2)
local BOARD_Y = 74
local SAVE_PATH = "snake_3310_save.lua"

local palette = {
  bg = { 0.03, 0.06, 0.03, 1.0 },
  panel = { 0.06, 0.10, 0.06, 1.0 },
  grid = { 0.15, 0.22, 0.15, 0.25 },
  border = { 0.52, 0.92, 0.28, 1.0 },
  text = { 0.74, 1.00, 0.45, 1.0 },
  textDim = { 0.50, 0.76, 0.34, 1.0 },
  snake = { 0.78, 1.00, 0.47, 1.0 },
  snakeDark = { 0.38, 0.58, 0.20, 1.0 },
  food = { 1.00, 1.00, 0.70, 1.0 },
  scan = { 0.00, 0.00, 0.00, 0.08 },
}

local state = "menu"
local score = 0
local bestScore = 0
local stepInterval = 0.16
local accumulator = 0
local pendingDirection = { x = 1, y = 0 }
local direction = { x = 1, y = 0 }
local snake = {}
local food = { x = 0, y = 0 }
local gameOverReason = ""
local progressDirty = false
local snakeCells = {}

local function cellKey(x, y)
  return x .. ':' .. y
end

local function copyDirection(dir)
  return { x = dir.x, y = dir.y }
end

local function sameCell(a, b)
  return a.x == b.x and a.y == b.y
end

local function setDirection(dx, dy)
  if dx == -direction.x and dy == -direction.y then
    return
  end
  pendingDirection.x = dx
  pendingDirection.y = dy
  if state == "menu" then
    state = "playing"
  end
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
  local best = tonumber(content:match("bestScore=(%d+)"))
  if best then
    bestScore = best
  end
end

local function saveProgress()
  love.filesystem.write(SAVE_PATH, string.format("bestScore=%d\n", bestScore))
end

local function resetSnake()
  snake = {
    { x = 8, y = 13 },
    { x = 7, y = 13 },
    { x = 6, y = 13 },
  }
  snakeCells = {}
  for _, segment in ipairs(snake) do
    snakeCells[cellKey(segment.x, segment.y)] = true
  end
  direction = { x = 1, y = 0 }
  pendingDirection = copyDirection(direction)
  score = 0
  stepInterval = 0.16
  accumulator = 0
  gameOverReason = ""
  state = "playing"
end

local function spawnFood()
  local chosen = nil
  local freeCount = 0
  for y = 1, GRID_HEIGHT do
    for x = 1, GRID_WIDTH do
      if not snakeCells[cellKey(x, y)] then
        freeCount = freeCount + 1
        if love.math.random(freeCount) == 1 then
          chosen = { x = x, y = y }
        end
      end
    end
  end
  if chosen == nil then
    food = { x = -1, y = -1 }
    state = "victory"
    return
  end
  food = chosen
end

local function restart()
  if progressDirty then
    saveProgress()
    progressDirty = false
  end
  resetSnake()
  spawnFood()
end

local function die(reason)
  state = "gameover"
  gameOverReason = reason or ""
  if score > bestScore then
    bestScore = score
    progressDirty = true
  end
  if progressDirty then
    saveProgress()
    progressDirty = false
  end
end

local function step()
  direction = copyDirection(pendingDirection)

  local head = snake[1]
  local nextHead = {
    x = head.x + direction.x,
    y = head.y + direction.y,
  }

  if nextHead.x < 1 or nextHead.x > GRID_WIDTH or nextHead.y < 1 or nextHead.y > GRID_HEIGHT then
    die("hit the wall")
    return
  end

  local tail = snake[#snake]
  local tailKey = tail and cellKey(tail.x, tail.y) or nil
  local nextKey = cellKey(nextHead.x, nextHead.y)
  local willGrow = sameCell(nextHead, food)

  if snakeCells[nextKey] and not (not willGrow and nextKey == tailKey) then
    die("bit the snake")
    return
  end

  table.insert(snake, 1, nextHead)
  snakeCells[nextKey] = true
  if willGrow then
    score = score + 1
    stepInterval = math.max(0.06, stepInterval * 0.96)
    spawnFood()
    if score > bestScore then
      bestScore = score
      progressDirty = true
    end
  else
    table.remove(snake)
    if tailKey and tailKey ~= nextKey then
      snakeCells[tailKey] = nil
    end
  end
end

local function drawCell(x, y, color, inset)
  local pad = inset or 0
  love.graphics.setColor(color)
  love.graphics.rectangle(
    "fill",
    BOARD_X + (x - 1) * TILE + pad,
    BOARD_Y + (y - 1) * TILE + pad,
    TILE - pad * 2,
    TILE - pad * 2,
    2,
    2
  )
end

local function drawTextCentered(text, y, color, scale)
  love.graphics.setColor(color)
  local font = love.graphics.getFont()
  local width = font:getWidth(text) * (scale or 1)
  love.graphics.print(text, math.floor((SCREEN_WIDTH - width) / 2), y, 0, scale or 1, scale or 1)
end

function love.load()
  love.graphics.setBackgroundColor(palette.bg)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setFont(love.graphics.newFont(12))
  love.math.setRandomSeed(os.time())
  loadProgress()
  restart()
end

function love.keypressed(key)
  if key == "up" or key == "w" then
    setDirection(0, -1)
  elseif key == "down" or key == "s" then
    setDirection(0, 1)
  elseif key == "left" or key == "a" then
    setDirection(-1, 0)
  elseif key == "right" or key == "d" then
    setDirection(1, 0)
  elseif key == "return" or key == "space" then
    if state == "menu" or state == "gameover" or state == "victory" then
      restart()
    end
  elseif key == "r" then
    restart()
  end
end

function love.touchpressed(_, x, y)
  if state == "menu" or state == "gameover" or state == "victory" then
    restart()
    return
  end

  local centerX = SCREEN_WIDTH * 0.5
  local centerY = SCREEN_HEIGHT * 0.82
  local dx = x - centerX
  local dy = y - centerY
  if math.abs(dx) > math.abs(dy) then
    setDirection(dx < 0 and -1 or 1, 0)
  else
    setDirection(0, dy < 0 and -1 or 1)
  end
end

function love.update(dt)
  if state ~= "playing" then
    return
  end

  accumulator = accumulator + dt
  while accumulator >= stepInterval and state == "playing" do
    accumulator = accumulator - stepInterval
    step()
  end
end

local function drawBoard()
  love.graphics.setColor(palette.panel)
  love.graphics.rectangle("fill", BOARD_X - 4, BOARD_Y - 4, BOARD_WIDTH + 8, BOARD_HEIGHT + 8, 6, 6)
  love.graphics.setColor(palette.border)
  love.graphics.rectangle("line", BOARD_X - 4, BOARD_Y - 4, BOARD_WIDTH + 8, BOARD_HEIGHT + 8, 6, 6)

  love.graphics.setColor(palette.grid)
  for x = 1, GRID_WIDTH - 1 do
    local px = BOARD_X + x * TILE
    love.graphics.line(px, BOARD_Y, px, BOARD_Y + BOARD_HEIGHT)
  end
  for y = 1, GRID_HEIGHT - 1 do
    local py = BOARD_Y + y * TILE
    love.graphics.line(BOARD_X, py, BOARD_X + BOARD_WIDTH, py)
  end

  love.graphics.setColor(palette.food)
  love.graphics.circle(
    "fill",
    BOARD_X + (food.x - 0.5) * TILE,
    BOARD_Y + (food.y - 0.5) * TILE,
    TILE * 0.28
  )

  for index = #snake, 1, -1 do
    local segment = snake[index]
    local color = index == 1 and palette.snake or palette.snakeDark
    local inset = index == 1 and 1 or 2
    drawCell(segment.x, segment.y, color, inset)
  end
end

local function drawScanlines()
  love.graphics.setColor(palette.scan)
  for y = 0, SCREEN_HEIGHT, 4 do
    love.graphics.rectangle("fill", 0, y, SCREEN_WIDTH, 1)
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

  drawTextCentered("SNAKE 3310", 16, palette.text, 1.6)
  drawTextCentered(string.format("SCORE %02d   BEST %02d", score, bestScore), 36, palette.textDim, 1)

  drawBoard()

  if state == "menu" then
    drawTextCentered("PRESS ANY ARROW", 400, palette.text, 1)
    drawTextCentered("OLD-SCHOOL SNAKE", 418, palette.textDim, 1)
  elseif state == "gameover" then
    drawTextCentered("GAME OVER", 398, palette.text, 1.2)
    drawTextCentered(gameOverReason, 418, palette.textDim, 1)
    drawTextCentered("PRESS ENTER TO RESTART", 438, palette.textDim, 1)
  elseif state == "victory" then
    drawTextCentered("YOU WIN", 398, palette.text, 1.2)
    drawTextCentered("THE BOARD IS FULL", 418, palette.textDim, 1)
    drawTextCentered("PRESS ENTER TO PLAY AGAIN", 438, palette.textDim, 1)
  else
    drawTextCentered("ARROWS / WASD", 410, palette.textDim, 1)
    drawTextCentered("TAP SIDES TO TURN", 428, palette.textDim, 1)
  end

  drawScanlines()
end
