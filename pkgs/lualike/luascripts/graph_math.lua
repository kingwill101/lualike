-- Math extension module: requires utils internally
local utils = require("graph_utils")
local M = {}

M.PI_TIMES_2 = utils.double(3.14159)  -- foldable: 6.28318

function M.complex_calc(x)
    local a = utils.double(x)
    local b = utils.half(x)
    local c = a + b
    return c
end

function M.power_sum(n)
    local s = 0
    for i = 1, n do
        s = s + i * i
    end
    return s
end

return M
