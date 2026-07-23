-- A simple greeting module.
local M = {}

function M.greet(name)
    return "Hello, " .. name .. "!"
end

function M.add(a, b)
    return a + b
end

return M
