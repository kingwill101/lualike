-- Loop Invariant Code Motion
-- Demonstrates: hoisting loop-invariant computations out of loops
-- LICM detects that x*y doesn't change inside the loop and hoists it

local function demo_licm(x, y, n)
  local sum = 0
  local product = x * y    -- loop invariant → hoisted before loop
  for i = 1, n do
    sum = sum + product    -- no recomputation each iteration
  end
  return sum
end

local function demo_licm2(a, b, n)
  local s = 0
  for i = 1, n do
    s = s + a + b          -- a+b invariant → hoisted before loop
  end
  return s
end

return demo_licm(3, 4, 100) + demo_licm2(10, 20, 5)
