-- SSA Global Value Numbering (runtime values prevent inlining)
-- Demonstrates: same computation detected across different branches

local function helper(x)
  return x * x
end

local function gvn_demo(a, b, flag)
  -- Both branches compute same subexpression → GVN merges them
  local r
  if flag > 0 then
    r = a * b + helper(a)     -- computes a*b
  else
    r = a * b - helper(b)     -- computes a*b again (same operands!)
  end
  -- After GVN: a*b computed once before the branch
  return r
end

local n = tonumber(arg and arg[1] or "5")
return gvn_demo(n, n + 1, 1)
