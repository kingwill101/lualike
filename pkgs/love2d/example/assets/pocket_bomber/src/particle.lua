-- Visual effects system

local G = require("src.globals")
local Utils = require("src.utils")

local particle = {}

-- Particle types
particle.TYPE_FLOAT_TEXT = 1
particle.TYPE_DEBRIS = 2

function particle.spawnText(x, y, text, color)
    local p = {
        type = particle.TYPE_FLOAT_TEXT,
        x = x,
        y = y,
        text = text,
        color = color or {1, 1, 1},
        life = 1.0,
        maxLife = 1.0,
        vy = -30
    }
    table.insert(G.particles, p)
end

function particle.spawnDebris(x, y, color)
    for i = 1, 4 do
        local p = {
            type = particle.TYPE_DEBRIS,
            x = x,
            y = y,
            vx = (math.random() - 0.5) * 100,
            vy = (math.random() - 0.5) * 100,
            size = 4 + math.random() * 4,
            color = color,
            life = 0.5 + math.random() * 0.5,
            maxLife = 1.0,
            rotation = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 10
        }
        table.insert(G.particles, p)
    end
end

function particle.update(dt)
    for i = #G.particles, 1, -1 do
        local p = G.particles[i]
        p.life = p.life - dt

        if p.type == particle.TYPE_FLOAT_TEXT then
            p.y = p.y + p.vy * dt
        elseif p.type == particle.TYPE_DEBRIS then
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy + 200 * dt -- Gravity
            p.rotation = p.rotation + p.rotSpeed * dt
        end

        if p.life <= 0 then
            table.remove(G.particles, i)
        end
    end
end

function particle.draw()
    for _, p in ipairs(G.particles) do
        local progress = 1 - (p.life / p.maxLife)
        local alpha = 1 - progress

        love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)

        if p.type == particle.TYPE_FLOAT_TEXT then
            love.graphics.print(p.text, p.x, p.y)
        elseif p.type == particle.TYPE_DEBRIS then
            love.graphics.push()
            love.graphics.translate(p.x, p.y)
            love.graphics.rotate(p.rotation)
            love.graphics.rectangle("fill", -p.size/2, -p.size/2, p.size, p.size)
            love.graphics.pop()
        end
    end
end

return particle
