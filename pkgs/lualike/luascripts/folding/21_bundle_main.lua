-- Whole-program folding across a transitive static require graph.
-- Run: dart run tool/compare.dart disasm --bundle <this file>

local math_ops = require("bundle/math_ops")
local constants = require("bundle/constants")
local constants_again = require("bundle/constants")

return math_ops.compute(5), constants.answer, constants.banner,
    constants == constants_again
