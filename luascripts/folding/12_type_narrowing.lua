-- Type narrowing: after type(x) == "number", x is known to be a number
local function process(v)
    if type(v) == "number" then
        return v * 2 + 1   -- v narrowed to number
    elseif type(v) == "string" then
        return "got: " .. v  -- v narrowed to string
    else
        return nil
    end
end

print(process(42))      -- 85
print(process("hi"))    -- got: hi
print(process(true))    -- nil
