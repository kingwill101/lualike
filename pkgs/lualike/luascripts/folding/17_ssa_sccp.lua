-- Sparse Conditional Constant Propagation
-- Demonstrates: constants flowing through phis across blocks
-- SCCP detects that both incoming phi values are the same constant
-- and eliminates the phi, propagating the constant downstream

local function demo_sccp(n)
  local x = 42
  if n > 0 then
    x = 42          -- same as initializer
  end
  -- phi(x) merges {42, 42} → SCCP sees it's always 42
  -- This eliminates the phi node and the redundant store
  return x + 1      -- folds to 43
end

return demo_sccp(5)
