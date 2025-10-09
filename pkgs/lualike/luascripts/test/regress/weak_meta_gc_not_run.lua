--
-- Regression: __gc added after weak-values metatable should not run
--
local u = setmetatable({}, { __gc = true })
setmetatable(getmetatable(u), { __mode = 'v' })
getmetatable(u).__gc = function(o)
  -- If this runs, the collector is wrong. Exit non-zero to fail test.
  os.exit(1)
end
u = nil
collectgarbage()
print('OK')
