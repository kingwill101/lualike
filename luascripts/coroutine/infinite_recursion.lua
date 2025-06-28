 recursion_error_detected = false
 pcall(function()
   local a = function(a) coroutine.wrap(a)(a) end
   a(a)
 end, function(err)
   recursion_error_detected = true
   return err
 end)
