-- Save system for high score persistence

local save = {}

local SAVE_FILE = "highscore.dat"

-- Load high score from file
function save.loadHighScore()
    if love.filesystem.getInfo(SAVE_FILE) then
        local content, err = love.filesystem.read(SAVE_FILE)
        if content then
            local score = tonumber(content)
            if score then
                return score
            end
        end
    end
    return 0
end

-- Save high score to file
function save.saveHighScore(score)
    love.filesystem.write(SAVE_FILE, tostring(score))
end

-- Check and update high score if needed
function save.updateHighScore(currentScore)
    local highScore = save.loadHighScore()
    if currentScore > highScore then
        save.saveHighScore(currentScore)
        return currentScore, true -- New high score
    end
    return highScore, false
end

return save
