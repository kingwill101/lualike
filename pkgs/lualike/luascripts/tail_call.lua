---
--- Created by kingwill101.
--- DateTime: 10/11/25 4:54 PM
---
limit = os.getenv("LIMIT") or 1
print("usinmg limit", limit)
function deep (n) if n>0 then return deep(n-1) else return 101 end end
logging.enable()
deep(tonumber(limit))
logging.disable()
