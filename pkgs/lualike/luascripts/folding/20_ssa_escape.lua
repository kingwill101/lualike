-- Escape Analysis + Scalar Replacement
-- Demonstrates: eliminating table allocations when table doesn't escape
-- A table created, used locally, and never passed to external code
-- can be replaced with individual registers for each field

local function demo_escape(x, y)
  -- This table is created and used only within this function
  -- It never escapes: not stored in globals, not passed to calls
  local t = {}
  t.a = x + 1
  t.b = y + 2
  -- Escape analysis proves t doesn't escape this function
  -- Scalar replacement converts t.a/t.b to individual registers
  return t.a + t.b
end

local function demo_escape2(n)
  local acc = {}
  acc.sum = 0
  for i = 1, n do
    acc.sum = acc.sum + i
  end
  return acc.sum
end

return demo_escape(5, 10) + demo_escape2(10)
