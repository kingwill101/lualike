-- Tile grid system

local G = require("src.globals")
local Utils = require("src.utils")

local grid = {}

-- Tile types
grid.EMPTY = 0
grid.WALL_PERMANENT = 1
grid.WALL_BREAKABLE = 2

function grid.create(cols, rows)
    local g = {
        cols = cols,
        rows = rows,
        tiles = {}
    }

    for r = 1, rows do
        g.tiles[r] = {}
        for c = 1, cols do
            g.tiles[r][c] = grid.EMPTY
        end
    end

    return g
end

function grid.clear(g)
    for r = 1, g.rows do
        for c = 1, g.cols do
            g.tiles[r][c] = grid.EMPTY
        end
    end
end

function grid.set(g, col, row, tileType)
    if col >= 1 and col <= g.cols and row >= 1 and row <= g.rows then
        g.tiles[row][col] = tileType
    end
end

function grid.get(g, col, row)
    if not g then return grid.WALL_PERMANENT end
    if col >= 1 and col <= g.cols and row >= 1 and row <= g.rows then
        return g.tiles[row][col]
    end
    return grid.WALL_PERMANENT
end

function grid.isSolid(g, col, row)
    if not g then return true end
    local tile = grid.get(g, col, row)
    return tile == grid.WALL_PERMANENT or tile == grid.WALL_BREAKABLE
end

function grid.isWalkable(g, col, row)
    return grid.get(g, col, row) == grid.EMPTY
end

function grid.destroyBlock(g, col, row)
    if grid.get(g, col, row) == grid.WALL_BREAKABLE then
        g.tiles[row][col] = grid.EMPTY
        return true
    end
    return false
end

function grid.worldToTile(g, x, y)
    if not g then return 1, 1 end
    return Utils.worldToGrid(x, y, G.TILE_SIZE, G.GRID_OFFSET_X, G.GRID_OFFSET_Y)
end

function grid.tileToWorld(g, col, row)
    if not g then return 0, 0 end
    return Utils.gridToWorld(col, row, G.TILE_SIZE, G.GRID_OFFSET_X, G.GRID_OFFSET_Y)
end

function grid.draw(g, colors)
    for r = 1, g.rows do
        for c = 1, g.cols do
            local tile = g.tiles[r][c]
            local x = G.GRID_OFFSET_X + (c - 1) * G.TILE_SIZE
            local y = G.GRID_OFFSET_Y + (r - 1) * G.TILE_SIZE

            if tile == grid.WALL_PERMANENT then
                love.graphics.setColor(colors.WALL_PERMANENT)
                love.graphics.rectangle("fill", x, y, G.TILE_SIZE, G.TILE_SIZE)
                -- Border
                love.graphics.setColor(colors.WALL_PERMANENT[1] * 1.2, colors.WALL_PERMANENT[2] * 1.2, colors.WALL_PERMANENT[3] * 1.2)
                love.graphics.rectangle("line", x, y, G.TILE_SIZE, G.TILE_SIZE)
            elseif tile == grid.WALL_BREAKABLE then
                love.graphics.setColor(colors.WALL_BREAKABLE)
                love.graphics.rectangle("fill", x + 2, y + 2, G.TILE_SIZE - 4, G.TILE_SIZE - 4)
                -- Detail
                love.graphics.setColor(colors.WALL_BREAKABLE[1] * 0.8, colors.WALL_BREAKABLE[2] * 0.8, colors.WALL_BREAKABLE[3] * 0.8)
                love.graphics.rectangle("fill", x + 10, y + 10, 8, 8)
                love.graphics.rectangle("fill", x + G.TILE_SIZE - 18, y + G.TILE_SIZE - 18, 8, 8)
            end
        end
    end
end

return grid
