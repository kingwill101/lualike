-- Function that returns multiple values
local function f()
    return 10, 20, 30
end

local function g()
    return 40, 50, f()
end

-- Test cases for function return values in print statements
print(5, f())
print(5, (f()))
print(f(), 5)
print(1 + f())
a = 1 + f()
b = f() + f()
print("result of 1 +f() = " .. a)
print("result of f() + f() = " .. b)
print(g())

-- Result should show:
-- 5 10 20 30  (all results from f are printed)
-- 5 10        (only first result when using parentheses)
-- 10 5        (first result when f is first argument)
-- 11          (1 added to first result, which is 10)
-- 40 50 10 20 30  (all results from f are printed)
--
