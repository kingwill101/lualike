-- Global declarations and const globals
global <const> *
global a, b, c = 10, 20, 30
global function add(x, y)
  return x + y
end
global none
global X
X = 99
return a, b, c, add(5, 6), _ENV.X
