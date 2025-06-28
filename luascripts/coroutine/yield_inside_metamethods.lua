-- Create a metatable with metamethods that yield
local mt = {
    __eq = function(a, b)
        coroutine.yield(nil, "eq"); return a.x == b.x
    end,
    __lt = function(a, b)
        coroutine.yield(nil, "lt"); return a.x < b.x
    end,
    __le = function(a, b)
        coroutine.yield(nil, "le"); return a - b <= 0
    end,
    __add = function(a, b)
        coroutine.yield(nil, "add"); return a.x + b.x
    end,
    __sub = function(a, b)
        coroutine.yield(nil, "sub"); return a.x - b.x
    end,
    __mul = function(a, b)
        coroutine.yield(nil, "mul"); return a.x * b.x
    end,
    __div = function(a, b)
        coroutine.yield(nil, "div"); return a.x / b.x
    end,
    __idiv = function(a, b)
        coroutine.yield(nil, "idiv"); return a.x // b.x
    end,
    __pow = function(a, b)
        coroutine.yield(nil, "pow"); return a.x ^ b.x
    end,
    __mod = function(a, b)
        coroutine.yield(nil, "mod"); return a.x % b.x
    end
}

local function new(x)
    return setmetatable({ x = x, k = {} }, mt)
end

local a = new(10)
local b = new(12)

local function run(f, t)
    local i = 1
    local c = coroutine.wrap(f)
    while true do
        local res, stat = c()
        if res then return res, t end
        assert(stat == t[i])
        i = i + 1
    end
end

lt_result = run(function() if (a < b) then return "<" else return ">=" end end, { "lt" })
gt_result = run(function() if (a > b) then return ">" else return "<=" end end, { "lt" })
add_result = run(function() return a + b end, { "add" })
mul_result = run(function() return a * b end, { "mul" })

print("lt_result:", lt_result)
print("gt_result:", gt_result)
print("add_result:", add_result)
print("mul_result:", mul_result)
