-- Debug UTF-8 string bytes
print("Debugging UTF-8 string bytes...")

local s = "汉字/漢字"
print("String:", s)
print("Length:", #s)

print("\nActual bytes in string:")
for i = 1, #s do
    local byte = string.byte(s, i)
    local is_continuation = (byte >= 0x80 and byte <= 0xBF)
    print(string.format("  [%d] = %d (0x%02X) %s",
        i, byte, byte, is_continuation and "CONTINUATION" or ""))
end

-- Test the pattern directly on individual bytes
print("\nTesting pattern on individual bytes:")
local pattern = "[\x80-\xBF]"

for i = 1, #s do
    local char = string.sub(s, i, i)
    local matches = string.gsub(char, pattern, "X")
    local byte = string.byte(s, i)
    print(string.format("  Byte %d (0x%02X): '%s' -> '%s'",
        byte, byte, char, matches))
end

-- Test specific continuation byte values
print("\nTesting specific bytes:")
local test_bytes = {0x80, 0x90, 0xA0, 0xB0, 0xBF}
for _, byte_val in ipairs(test_bytes) do
    local char = string.char(byte_val)
    local result = string.gsub(char, pattern, "X")
    print(string.format("  0x%02X -> '%s'", byte_val, result))
end