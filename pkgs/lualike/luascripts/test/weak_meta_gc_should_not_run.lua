-- Repro of gc.lua lines 630–642: __gc set under weak-values metatable must not run
local ran = false
local logging = logging or {}
if logging and logging.enable then logging.enable("FINE") end

local u = setmetatable({}, { __gc = true })
setmetatable(getmetatable(u), { __mode = 'v' })
getmetatable(u).__gc = function(o)
  ran = true
  print('DEBUG: __gc SHOULD NOT RUN but ran')
end
u = nil
collectgarbage()

if logging and logging.disable then logging.disable() end

assert(ran == false)
print('OK')

