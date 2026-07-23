-- Table construction and field access
local t = {10, 20, 30, x = 1, y = 2}
t[1] = 99
t.z = 3
return t.x, t[2], t.z
