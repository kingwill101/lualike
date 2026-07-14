-- luac55 keeps these requires; lualike --bundle emits one combined chunk.
local math_ops = require("../folding/bundle/math_ops")
local constants = require("../folding/bundle/constants")
local constants_again = require("../folding/bundle/constants")

return math_ops.compute(5), constants.answer, constants.banner,
    constants == constants_again
