-- Local variable basics: declaration, assignment, scope
local a = 10
local b = 20
local c = a + b
a = 30
local d = a + b + c
return a, b, c, d
