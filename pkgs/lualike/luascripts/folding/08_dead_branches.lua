-- Level 8: Dead branch elimination
-- Compile time: if true then A else B end → only A compiled
--               if false then A else B end → only B compiled

local function pick(hour)
    -- This if/elseif chain is resolved at compile time
    if hour < 12 then
        return "morning"
    elseif hour < 18 then
        return "afternoon"
    else
        return "evening"
    end
end

-- Constant-folded if-conditions in the caller get dead-branch eliminated
local greeting1 <const> = pick(9)
local greeting2 <const> = pick(14)
local greeting3 <const> = pick(20)

-- Direct dead branches at top level (condition is compile-time constant)
local x
if true then
    x = "this branch is kept"
else
    x = "this branch is eliminated"
end

local y
if false then
    y = "this branch is eliminated"
else
    y = "this branch is kept"
end

local z
if 42 then              -- truthy constant
    z = "kept"
else
    z = "eliminated"
end

print("pick(9)  =", greeting1)      -- morning
print("pick(14) =", greeting2)      -- afternoon
print("pick(20) =", greeting3)      -- evening
print("x =", x)                     -- this branch is kept
print("y =", y)                     -- this branch is kept
print("z =", z)                     -- kept
