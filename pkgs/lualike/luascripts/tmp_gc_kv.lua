-- minimal reproduction of weak kv behavior with strings
collectgarbage('stop')
local a = {}
setmetatable(a, { __mode = 'kv' })
local x,y,z = {}, {}, {}
a[1], a[2], a[3] = x, y, z
local s = string.rep('$', 11)
a[s] = s
-- make more garbage keys/values
for i=1,50 do a[{}] = {} end
collectgarbage('collect')
-- count entries
local c=0
for k,v in pairs(a) do c=c+1 end
print('after first collect count', c)
x,y,z = nil,nil,nil
collectgarbage('collect')
local first = next(a)
print('after second collect first', tostring(first))
print('equals s?', first==s)
print('size after second', (function() local n=0 for _ in pairs(a) do n=n+1 end return n end)())
