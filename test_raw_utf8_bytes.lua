-- Test UTF-8 pattern with raw bytes (like the real UTF-8 test would do)
print("Testing UTF-8 pattern with raw bytes...")

-- Create UTF-8 string using raw bytes like the real test would
-- "汉字/漢字" in UTF-8 bytes: [230,177,137,229,173,151,47,230,188,162,229,173,151]
local s = string.char(230,177,137,229,173,151,47,230,188,162,229,173,151)
print("Raw byte string:", s)
print("String length:", #s)
print("UTF-8 character count:", utf8.len(s))

-- The pattern that removes UTF-8 continuation bytes (0x80-0xBF)
local pattern = "[\x80-\xBF]"
print("\nTesting pattern:", pattern)

-- This should remove continuation bytes, leaving only start bytes + ASCII
local result, count = string.gsub(s, pattern, "")
print("After removing continuation bytes:", result)
print("Continuation bytes removed:", count)

-- Test the helper len function from UTF-8 tests
local function len(s)
  return #string.gsub(s, "[\x80-\xBF]", "")
end

local helper_len = len(s)
print("Helper len result:", helper_len)
print("UTF8 len result:", utf8.len(s))

-- These should match for the UTF-8 test to pass
if helper_len == utf8.len(s) then
    print("✅ SUCCESS: Pattern matching now works correctly!")
    print("✅ UTF-8 tests should now pass!")
else
    print("❌ FAILED: Pattern matching still not working")
    print("Expected helper_len == utf8.len(s):", utf8.len(s))
    print("Got helper_len:", helper_len)
end

-- Additional debug: check expected vs actual
print("\nDetailed analysis:")
print("Original bytes: [230,177,137,229,173,151,47,230,188,162,229,173,151]")
print("Continuation bytes (0x80-0xBF): positions 2,3,5,6,9,10,12,13 = 8 bytes")
print("After removal should have: [230,229,47,230,229] = 5 bytes")
print("This matches utf8.len = 5 characters")
print("Expected pattern count: 8, got:", count)