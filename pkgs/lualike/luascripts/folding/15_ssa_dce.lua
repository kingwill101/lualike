-- SSA Dead Code Elimination
-- DCE removes stores to registers that are never consumed
-- Function is too large to inline (>20 AST nodes) so real IR is preserved

local function heavy(x, y)
  local a = x + y
  local b = a * 2
  local c = b - 1
  local d = b + c
  local e = d * a
  return e
end

local function dce_demo(a, b, c, d, e)
  -- Dead stores: r1, r2, r5 are never read → eliminated by SSA DCE
  local r1 = a + b        -- DEAD (never used)
  local r2 = b * c        -- DEAD
  local r3 = c + d        -- used
  local r4 = heavy(r3, e) -- used
  local r5 = a - e        -- DEAD
  local r6 = r4 * 2       -- used
  return r6
end

local x = tonumber(arg and arg[1] or "3")
return dce_demo(x, x+1, x+2, x+3, x+4)
