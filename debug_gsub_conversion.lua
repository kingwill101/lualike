-- Debug string.gsub conversion specifically
print("Debugging string.gsub conversion...")

-- Create a simple test string with a known continuation byte
local test_byte = string.char(0xB1)  -- This is 177, a continuation byte
print("Test byte value:", string.byte(test_byte))
print("Test byte is continuation:", string.byte(test_byte) >= 0x80 and string.byte(test_byte) <= 0xBF)

-- Test pattern matching on this single byte
local pattern = "[\x80-\xBF]"
print("Pattern:", pattern)

-- Test with string.gsub
local result, count = string.gsub(test_byte, pattern, "X")
print("Single byte gsub result:", result)
print("Single byte gsub count:", count)

-- Now test with a simple string containing the byte
local simple_string = "a" .. test_byte .. "b"
print("\nSimple string length:", #simple_string)
print("Simple string bytes:")
for i = 1, #simple_string do
    local byte = string.byte(simple_string, i)
    print(string.format("  [%d] = %d (0x%02X)", i, byte, byte))
end

-- Test gsub on this simple string
local result2, count2 = string.gsub(simple_string, pattern, "X")
print("Simple string gsub result:", result2)
print("Simple string gsub count:", count2)

-- Test creating the string using string.char vs literal
local char_string = string.char(97, 177, 98)  -- a + continuation + b
local result3, count3 = string.gsub(char_string, pattern, "X")
print("\nstring.char created string gsub result:", result3)
print("string.char created string gsub count:", count3)