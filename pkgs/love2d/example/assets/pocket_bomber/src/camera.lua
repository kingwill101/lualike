-- Camera module for filling the viewport

local G = require("src.globals")

local camera = {}

-- Current scale factors (stretch to fill)
camera.scaleX = 1
camera.scaleY = 1

function camera.update(windowWidth, windowHeight)
    -- Calculate scale to fill the screen (stretch to fit)
    camera.scaleX = windowWidth / G.SCREEN_WIDTH
    camera.scaleY = windowHeight / G.SCREEN_HEIGHT

    -- Calculate tile size in LOGICAL coordinates to fill the logical screen
    -- Leave space at top for HUD
    local hudHeight = 80  -- Logical pixels for HUD
    local availableHeight = G.SCREEN_HEIGHT - hudHeight

    -- Calculate tile size to fit grid in logical coordinates
    local tileW = G.SCREEN_WIDTH / G.GRID_COLS
    local tileH = availableHeight / G.GRID_ROWS
    G.TILE_SIZE = math.min(tileW, tileH)

    -- Center the grid horizontally, position below HUD vertically
    G.GRID_OFFSET_X = (G.SCREEN_WIDTH - (G.GRID_COLS * G.TILE_SIZE)) / 2
    G.GRID_OFFSET_Y = hudHeight + (availableHeight - (G.GRID_ROWS * G.TILE_SIZE)) / 2
end

function camera.apply()
    love.graphics.push()
    love.graphics.scale(camera.scaleX, camera.scaleY)
end

function camera.remove()
    love.graphics.pop()
end

-- Convert screen coordinates to game (logical) coordinates
function camera.toGame(x, y)
    return x / camera.scaleX, y / camera.scaleY
end

-- Convert game coordinates to screen coordinates
function camera.toScreen(x, y)
    return x * camera.scaleX, y * camera.scaleY
end

-- Get current screen dimensions in game coordinates
function camera.getGameDimensions()
    local ww, wh = love.graphics.getDimensions()
    return ww / camera.scaleX, wh / camera.scaleY
end

return camera
