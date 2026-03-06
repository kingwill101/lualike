---
--- Count allocations during tail calls
---
function deep (n) if n>0 then return deep(n-1) else return 101 end end

logging.enable()
local val = deep(100)  
logging.disable()
print("Result:", val)

