-- Debug pattern processing internally
print("Testing pattern processing step by step...")

-- First, let's see what the pattern string actually contains
local pattern = "[\x80-\xBF]"
print("Pattern string: '" .. pattern .. "'")
print("Pattern length: " .. #pattern)

-- Check each byte in the pattern
print("\nPattern bytes:")
for i = 1, #pattern do
    local byte = string.byte(pattern, i)
    print(string.format("  [%d] = %d (0x%02X) '%s'", i, byte, byte,
          (byte >= 32 and byte <= 126) and string.char(byte) or "?"))
end

-- Now test if the bytes are what we expect
local expected_80 = string.char(0x80)
local expected_BF = string.char(0xBF)

print("\nExpected bytes:")
print("\\x80 should be:", string.byte(expected_80))
print("\\xBF should be:", string.byte(expected_BF))

-- Test with manually constructed pattern
local manual_pattern = "[" .. expected_80 .. "-" .. expected_BF .. "]"
print("\nManual pattern bytes:")
for i = 1, #manual_pattern do
    local byte = string.byte(manual_pattern, i)
    print(string.format("  [%d] = %d (0x%02X)", i, byte, byte))
end

-- Test both patterns
local test_string = "hello" .. expected_80 .. "world"
print("\nTest string contains 0x80 at position:", string.find(test_string, expected_80))

print("\nTesting original pattern...")
local ok1, result1, count1 = pcall(string.gsub, test_string, pattern, "X")
if ok1 then
    print("Success - Result:", result1, "Count:", count1)
else
    print("Failed:", result1)
end

print("\nTesting manual pattern...")
local ok2, result2, count2 = pcall(string.gsub, test_string, manual_pattern, "X")
if ok2 then
    print("Success - Result:", result2, "Count:", count2)
else
    print("Failed:", result2)
end