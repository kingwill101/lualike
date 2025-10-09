a = {}
local limit = 5000

function check (a, f)
  f = f or function (x,y) return x<y end;
  for n = #a, 2, -1 do
    assert(not f(a[n], a[n-1]))
  end
end


AA = {"\xE1lo", "\0first :-)", "alo", "then this one", "45", "and a new"}
table.sort(AA)
check(AA)

table.sort(AA, function (x, y)
          load(string.format("AA[%q] = ''", x), "")()
          collectgarbage()
          return x<y
        end)

_G.AA = nil

local tt = {__lt = function (a,b) return a.val < b.val end}
a = {}
for i=1,10 do  a[i] = {val=math.random(100)}; setmetatable(a[i], tt); end
table.sort(a)
check(a, tt.__lt)
check(a)

print"OK"