-- Level 9: Combined — real-world scenario
-- All folding levels working together

local TAU <const> = 2 * math.pi
local SCREEN_W <const> = 1920
local SCREEN_H <const> = 1080
local ASPECT <const> = SCREEN_W / SCREEN_H
local DEG_TO_RAD <const> = math.pi / 180

local COLOR_RED <const> = {1, 0, 0, 1}
local COLOR_GREEN <const> = {0, 1, 0, 1}

-- Inlined function with table access and arithmetic
local function scale_color(color, factor)
    return {color[1] * factor, color[2] * factor, color[3] * factor, color[4]}
end

-- Table access folding: COLOR_RED[1] → 1
-- Arithmetic: 1 * 0.5 → 0.5
local dim_red <const> = scale_color(COLOR_RED, 0.5)

-- Builtin + string folding
local function describe_color(name, r, g, b)
    return name .. "(" .. tostring(r) .. ", " .. tostring(g) .. ", " .. tostring(b) .. ")"
end

-- All args const → full inline
local desc <const> = describe_color("red", COLOR_RED[1], COLOR_RED[2], COLOR_RED[3])

-- Combined const-math for game math
local function world_to_screen(wx, wy, aspect, deg)
    local rad = deg * DEG_TO_RAD
    local sx = wx * math.cos(rad) - wy * math.sin(rad)
    local sy = wx * math.sin(rad) + wy * math.cos(rad)
    return sx * aspect, sy * aspect
end

-- world_to_screen is NOT inlined here since args vary; but DEG_TO_RAD and
-- ASPECT are const-folded inside the function body when it IS called with consts.

print("TAU =", TAU)                              -- 6.283185307179586
print("ASPECT =", ASPECT)                        -- 1.7777777777777777
print("dim_red =", dim_red[1], dim_red[2], dim_red[3], dim_red[4])
print("desc =", desc)                            -- red(1, 0, 0)
