local function f()
    return 10, 20, 30
end

local function g()
    print("result of 1 +f() = ", 1 +f())
    print("result of f() + f() = ", f() + f())
end


print("result of 1 +f() = ", 1 +f())
print("result of f() + f() = ", f() + f())
