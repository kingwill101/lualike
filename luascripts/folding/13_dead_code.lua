-- Dead code elimination: unused module exports are tree-shaken
-- (this simulates what the bundler + DCE would produce)
local M = {}

function M.used_func(x)
    return x * 2
end

function M.unused_func(x)
    return x * 3    -- never read → eliminated
end

M.used_field = 42
M.unused_field = "gone"  -- never read → eliminated

local result = M.used_func(M.used_field)
print("result =", result)  -- 84
