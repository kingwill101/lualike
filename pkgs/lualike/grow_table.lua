---
--- Created by kingwill101.
--- DateTime: 10/8/25 1:01 PM
---
local limit = 5000

a = {}
for i = 1, limit do
    if i == 2 then
        logging.enable()
    end

    a[i] = math.random()

    if i == 2 then
        logging.disable()
    end

    print("> ", i, "\n")

end
