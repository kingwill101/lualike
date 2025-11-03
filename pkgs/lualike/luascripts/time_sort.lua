---
--- Created by kingwill101.
--- DateTime: 10/8/25 11:39 AM
---

a = {}
local limit = 5000

function check (a, f)
  f = f or function (x,y) return x<y end;
  for n = #a, 2, -1 do
    assert(not f(a[n], a[n-1]))
  end
end


local function timesort(a, n, func, msg, pre)
    local x = os.clock()
    table.sort(a, func)
    x = (os.clock() - x) * 1000
    pre = pre or ""
    print(string.format("%ssorting %d %s elements in %.2f msec.", pre, n, msg, x))
    check(a, func)
end

for i=1,limit do a[i] = false end
timesort(a, limit,  function(x,y) return nil end, "equal")