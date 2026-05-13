-- Utility functions

local utils = {}

-- Clamp a value between min and max
function utils.clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

-- Linear interpolation
function utils.lerp(a, b, t)
    return a + (b - a) * t
end

-- Check if two rectangles overlap
function utils.rectsOverlap(x1, y1, w1, h1, x2, y2, w2, h2)
    return x1 < x2 + w2 and x1 + w1 > x2 and y1 < y2 + h2 and y1 + h1 > y2
end

-- Get grid coordinates from world position
function utils.worldToGrid(x, y, tileSize, offsetX, offsetY)
    local col = math.floor((x - offsetX) / tileSize) + 1
    local row = math.floor((y - offsetY) / tileSize) + 1
    return col, row
end

-- Get world position from grid coordinates (center of tile)
function utils.gridToWorld(col, row, tileSize, offsetX, offsetY)
    local x = offsetX + (col - 1) * tileSize + tileSize / 2
    local y = offsetY + (row - 1) * tileSize + tileSize / 2
    return x, y
end

-- Distance between two points
function utils.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- Manhattan distance (for grid)
function utils.manhattan(x1, y1, x2, y2)
    return math.abs(x2 - x1) + math.abs(y2 - y1)
end

-- Round to nearest integer
function utils.round(n)
    return math.floor(n + 0.5)
end

-- Check if value is in table
function utils.contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

-- Deep copy a table
function utils.deepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in next, orig, nil do
            copy[utils.deepCopy(k)] = utils.deepCopy(v)
        end
        setmetatable(copy, utils.deepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

return utils
