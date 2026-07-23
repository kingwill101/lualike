-- Utility module: basic math and string helpers
local M = {}

function M.double(x)
    return x * 2
end

function M.triple(x)
    return x * 3
end

function M.half(x)
    return x / 2
end

function M.greet(name)
    return "Hello, " .. name .. "!"
end

-- Uses a constant that folding can optimize
M.PI = 3.14159
M.E = 2.71828

return M
