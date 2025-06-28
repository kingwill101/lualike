local function foo (i) return coroutine.yield(i) end
      local f = coroutine.wrap(function ()
        for i=1,10 do
          assert(foo(i) == _G.x)
        end
        return 'a'
      end)
      for i=1,10 do _G.x = i; assert(f(i) == i) end
_G.x = 'xuxu';
result = f('xuxu')

print(result)
