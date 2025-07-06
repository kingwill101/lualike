-- Test manually constructed pattern
print("Testing manually constructed pattern...")

local x80 = string.char(0x80)
local xBF = string.char(0xBF)
local manual_pattern = "[" .. x80 .. "-" .. xBF .. "]"

print("Manual pattern:", manual_pattern)

-- Test with string that doesn't contain continuation bytes
local test1 = "hello"
print("\nTesting with 'hello':")
local result1, count1 = string.gsub(test1, manual_pattern, "X")
print("Result:", result1)
print("Count:", count1)

-- Test with string that contains continuation byte
local test2 = "hello" .. string.char(0x80) .. "world"
print("\nTesting with string containing \\x80:")
local result2, count2 = string.gsub(test2, manual_pattern, "X")
print("Result:", result2)
print("Count:", count2)