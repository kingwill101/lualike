error_message = nil
      pcall(function()
        local co
        co = coroutine.create(
          function()
            local x = func2close(function()
              coroutine.close(co) -- try to close it again
            end)
            coroutine.yield(20)
          end)
        local st, msg = coroutine.resume(co)
        assert(st and msg == 20)
        local ok, err = pcall(coroutine.close, co)
        error_message = err
      end)
print(error_message)
