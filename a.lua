
local debug = require'debug'

X = 20; B = 30

print("After first assignment:", X, B)
_ENV = setmetatable({}, {__index=_G})

collectgarbage()

X = X+10
print("X After second assignment:", X)
print("X",  X, "_G.X" , _G.X)

B = false
print("B After assignment: ", B)
_ENV["B"] = undef
print("B After  ENV assignment: ", B)
assert(B == 30)