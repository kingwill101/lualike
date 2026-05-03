-- Color palette from GDD

local colors = {}

-- Convert hex to RGB (0-1 range)
local function hex(hexStr)
    hexStr = hexStr:gsub("#", "")
    local r = tonumber(hexStr:sub(1, 2), 16) / 255
    local g = tonumber(hexStr:sub(3, 4), 16) / 255
    local b = tonumber(hexStr:sub(5, 6), 16) / 255
    return {r, g, b}
end

-- GDD Color Palette
colors.BACKGROUND = hex("#1a1c2c")
colors.WALL_PERMANENT = hex("#29366f")
colors.WALL_BREAKABLE = hex("#b13e53")
colors.FLOOR = hex("#1a1c2c")
colors.PLAYER = hex("#38b764")
colors.ENEMY_BASIC = hex("#ef7d57")
colors.ENEMY_FAST = hex("#ffcd75")
colors.ENEMY_TANK = hex("#a7f070")
colors.BOMB = hex("#257179")
colors.BOMB_LIT = hex("#3b5dc9")
colors.EXPLOSION_CENTER = hex("#ff0044")
colors.EXPLOSION_ARM = hex("#ffccaa")
colors.TEXT = hex("#f4f4f4")
colors.TEXT_DIM = hex("#a7f070")
colors.HIGHLIGHT = hex("#ffcd75")
colors.BUTTON_BG = hex("#29366f")
colors.BUTTON_HOVER = hex("#3b5dc9")
colors.PAUSE_OVERLAY = {0.1, 0.1, 0.15, 0.85}

return colors
