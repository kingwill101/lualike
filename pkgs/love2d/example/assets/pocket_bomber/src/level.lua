-- Level management

local G = require("src.globals")
local Grid = require("src.grid")
local LevelData = require("src.level_data")

local level = {}

function level.load(levelNum)
    local data = LevelData.getLevel(levelNum)
    if not data then
        return nil
    end

    -- Create grid
    local grid = Grid.create(G.GRID_COLS, G.GRID_ROWS)

    -- Parse layout
    for row, line in ipairs(data.layout) do
        for col = 1, #line do
            local char = line:sub(col, col)
            if char == "#" then
                Grid.set(grid, col, row, Grid.WALL_PERMANENT)
            end
        end
    end

    -- Add breakable walls
    for _, pos in ipairs(data.breakableWalls) do
        Grid.set(grid, pos[1], pos[2], Grid.WALL_BREAKABLE)
    end

    -- Convert enemy data
    local enemies = {}
    for _, e in ipairs(data.enemies) do
        table.insert(enemies, {
            type = e.type,
            col = e.col,
            row = e.row
        })
    end

    return {
        num = levelNum,
        grid = grid,
        enemies = enemies,
        playerStart = data.playerStart,
        timeLimit = data.timeLimit,
        timeRemaining = data.timeLimit
    }
end

function level.update(levelData, dt)
    if levelData then
        levelData.timeRemaining = levelData.timeRemaining - dt
        if levelData.timeRemaining < 0 then
            levelData.timeRemaining = 0
        end
    end
end

function level.isComplete(levelData)
    return #G.enemies == 0
end

function level.isTimeUp(levelData)
    return levelData.timeRemaining <= 0
end

return level
