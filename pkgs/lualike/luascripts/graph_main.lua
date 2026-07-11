-- Top-level: requires utils and math_extras
local utils = require("graph_utils")
local mathx = require("graph_math")

local result = mathx.complex_calc(utils.double(5))
print("complex_calc(double(5)) =", result)
print("PI times 2 =", mathx.PI_TIMES_2)
