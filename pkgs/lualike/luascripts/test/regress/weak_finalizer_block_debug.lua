-- Debug reproduction of gc.lua weak/finalizer block (around 430–452)
-- Turn on detailed logging just for this block.

local logging = logging or {}
if logging and logging.enable then logging.enable("FINE") end

local a = { x = false }
local t = {}
local C = setmetatable({ key = t }, { __mode = 'v' })
local C1 = setmetatable({ [t] = 1 }, { __mode = 'k' })
a.x = t -- this should not prevent 't' from being removed from C by finalizer time

setmetatable(a, {
  __gc = function(u)
    print('DEBUG: __gc entered; C.key=', C.key, ' next(C1)=', next(C1))
    assert(C.key == nil)
    assert(type(next(C1)) == 'table')
  end
})

a, t = nil
collectgarbage()
collectgarbage()
assert(next(C) == nil and next(C1) == nil)

if logging and logging.disable then logging.disable() end
print('OK')

