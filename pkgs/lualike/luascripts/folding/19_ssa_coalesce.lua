-- Register Coalescing
-- Demonstrates: MOVE instruction elimination via register forwarding
-- The compiler emits MOVE instructions to copy values between registers
-- Coalescing replaces uses of the destination with the source

local function demo_coalesce(x, y)
  local a = x + y      -- result in temp register
  local b = a          -- MOVE a → b
  local c = b          -- MOVE b → c
  -- After coalescing: c directly references a's computation
  -- The MOVEs are eliminated
  return c
end

local function demo_coalesce2(t)
  local a = t.x        -- load field
  local b = a          -- MOVE (eliminated)
  local c = b + 1      -- uses a directly
  return c
end

return demo_coalesce(3, 4) + demo_coalesce2({x = 10})
