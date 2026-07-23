-- Literal, arithmetic, string, logic, and table folding inside a module.
local M = {}

M.answer = 6 * 7
M.banner = "fold" .. "ed"
M.enabled = true and not false
M.lookup = ({10, 20, 30})[2]

-- The bundled DCE pass should remove these unused exports.
M.unused_number = (100 + 23) * 4
M.unused_string = string.upper("remove me")

return M
