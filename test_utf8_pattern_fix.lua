-- Test the UTF-8 pattern fix
print("Testing UTF-8 pattern fix...")

-- Test the pattern that was failing in UTF-8 tests
local s = "汉字/漢字"  -- UTF-8 string with continuation bytes
print("Original string:", s)
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