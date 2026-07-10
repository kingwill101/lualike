-- Speed benchmark: compiled bytecode (Lua VM) vs IR VM vs no-fold
-- This same script runs in all modes

local N <const> = 50000
local S <const> = 2000

print("N=" .. N .. " S=" .. S)
print("")

local t1 = os.clock()
local s1 = 0
for i = 1, N do s1 = s1 + 2 + 3 * 4 - 1 end
t1 = os.clock() - t1
print(string.format("arithmetic: sum=%d time=%.2fms", s1, t1 * 1000))

local t2 = os.clock()
local s2 = ""
for i = 1, S do s2 = s2 .. "hello" .. " " .. "world" end
t2 = os.clock() - t2
print(string.format("strings: len=%d time=%.2fms", #s2, t2 * 1000))

local t3 = os.clock()
local s3 = 0
for i = 1, N do if true and not false then s3 = s3 + 1 end end
t3 = os.clock() - t3
print(string.format("logic: count=%d time=%.2fms", s3, t3 * 1000))

local COLOR <const> = {r = 255, g = 128, b = 64}
local t4 = os.clock()
local s4 = 0
for i = 1, N do s4 = s4 + COLOR.r + COLOR.g + COLOR.b end
t4 = os.clock() - t4
print(string.format("table_access: sum=%d time=%.2fms", s4, t4 * 1000))

local function add(a, b) return a + b end
local function mul(a, b) return a * b end
local t5 = os.clock()
local s5 = 0
for i = 1, N do s5 = s5 + add(mul(2, 3), mul(4, 5)) end
t5 = os.clock() - t5
print(string.format("inlined_add: sum=%d time=%.2fms", s5, t5 * 1000))
