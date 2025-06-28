local f = function (a, b) a = coroutine.yield(a); error{a + b} end
      local function g(x) return x[1]*2 end

      co = coroutine.wrap(function ()
        coroutine.yield(xpcall(f, g, 10, 20))
      end)

first_result = co()
pcall_result, error_msg = co(100)

print(first_result)
print(pcall_result)
print(error_msg)
