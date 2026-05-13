-- Global constants and shared state

local globals = {}

-- Screen dimensions (logical)
globals.SCREEN_WIDTH = 960
globals.SCREEN_HEIGHT = 540

-- Grid settings
globals.GRID_COLS = 13
globals.GRID_ROWS = 9
globals.TILE_SIZE = 60  -- Will be calculated dynamically
globals.GRID_OFFSET_X = 0
globals.GRID_OFFSET_Y = 0

-- Game timing
globals.FUSE_TIME = 2.0
globals.EXPLOSION_DURATION = 0.5
globals.GRACE_WINDOW = 0.12
globals.NEAR_MISS_TIME = 0.20
globals.BLINK_RATE_START = 0.3
globals.BLINK_RATE_END = 0.05

-- Movement speeds (pixels per second)
globals.PLAYER_SPEED = 180
globals.ENEMY_SPEED_SLOW = 40
globals.ENEMY_SPEED_MEDIUM = 55
globals.ENEMY_SPEED_FAST = 70

-- Player animation
globals.WOBBLE_SPEED = 12
globals.WOBBLE_AMP_WALK = 0.08
globals.WOBBLE_AMP_IDLE = 0.03
globals.BOUNCE_SPEED = 8

-- Enemy wobble
globals.ENEMY_WOBBLE_SPEED = 8
globals.ENEMY_WOBBLE_AMP = 0.05

-- Cornering assist
globals.CORNER_ASSIST_PX = 12

-- Colors (will be populated from colors.lua)
globals.COLORS = nil

-- Game state
globals.state = nil
globals.highScore = 0
globals.currentScore = 0
globals.currentLevel = 1

-- Entity containers
globals.bombs = {}
globals.explosions = {}
globals.enemies = {}
globals.particles = {}

-- Input state
globals.input = {
    dx = 0,
    dy = 0,
    bombPressed = false,
    pausePressed = false
}

return globals
