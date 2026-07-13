-- Global variable access and assignment
global x
x = 100
y = 200
global function f(a, b)
  return a + b
end
return x, y, f(3, 4), _ENV.x, _ENV.y
