-- _ENV manipulation
global _G
local mt = {_G = _G}
local old = _ENV
_ENV = mt
global A
global function foo (x)
  A = x
  do local _ENV = _G; A = 1000 end
  return function (x) return A .. x end
end
_ENV = old
local result = foo('hi')
return mt.A, result('*')
