-- Debug what our pattern conversion is producing
print("Testing pattern conversion...")

-- First test a simple known-working pattern
local simple_ok, simple_result, simple_count = pcall(string.gsub, "abc", "[abc]", "X")
if simple_ok then
    print("Simple [abc] pattern works - Result:", simple_result, "Count:", simple_count)
else
    print("Simple [abc] pattern failed:", simple_result)
end

-- Test with printable ASCII range
local ascii_ok, ascii_result, ascii_count = pcall(string.gsub, "ABC", "[A-C]", "X")
if ascii_ok then
    print("ASCII [A-C] pattern works - Result:", ascii_result, "Count:", ascii_count)
else
    print("ASCII [A-C] pattern failed:", ascii_result)
end

-- Test with our problematic high-byte range
local x80 = string.char(0x80)
local test_string = "hello" .. x80 .. "world"
print("\nTest string has 0x80 at position:", string.find(test_string, x80))

local pattern = "[\x80-\xBF]"
local high_ok, high_result, high_count = pcall(string.gsub, test_string, pattern, "X")
if high_ok then
    print("High-byte pattern result:", high_result)
    print("High-byte pattern count:", high_count)
    print("Expected to replace 1 byte, got count:", high_count)
else
    print("High-byte pattern failed:", high_result)
end

-- Test individual byte matching
local single_ok, single_result, single_count = pcall(string.gsub, test_string, x80, "X")
if single_ok then
    print("Single byte replacement works - Count:", single_count)
else
    print("Single byte replacement failed:", single_result)
end