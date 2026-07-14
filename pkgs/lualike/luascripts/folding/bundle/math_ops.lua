-- Transitive import and module export tree shaking.
local constants = require("constants")
local M = {}

function M.compute(value)
    local doubled = value * 2
    return doubled + constants.answer
end

function M.unused(value)
    return value * constants.lookup
end

M.folded_offset = math.abs(-5) + 10

return M
