-- Simple pattern debugging test
print("Testing pattern conversion with logging...")

-- Test our problematic pattern
local x80 = string.char(0x80)
local test_string = "hello" .. x80 .. "world"
local pattern = "[\x80-\xBF]"

print("Pattern:", pattern)
print("Pattern bytes:")
for i = 1, #pattern do
    local byte = string.byte(pattern, i)
    print(string.format("  [%d] = %d (0x%02X)", i, byte, byte))
end

print("\nTest string bytes:")
for i = 1, #test_string do
    local byte = string.byte(test_string, i)
    print(string.format("  [%d] = %d (0x%02X)", i, byte, byte))
end

print("\nTesting pattern...")
local ok, result, count = pcall(string.gsub, test_string, pattern, "X")

if ok then
    print("Pattern worked!")
    print("Result:", result)
    print("Count:", count)
else
    print("Pattern failed:", result)
end