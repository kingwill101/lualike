-- Test each byte from the UTF-8 string individually
print("Testing individual bytes from UTF-8 string...")

-- Create the UTF-8 string: [230,177,137,229,173,151,47,230,188,162,229,173,151]
local utf8_bytes = {230,177,137,229,173,151,47,230,188,162,229,173,151}
local s = string.char(table.unpack(utf8_bytes))

print("Original string:", s)
print("String length:", #s)

-- Check each byte and test pattern matching
local pattern = "[\x80-\xBF]"
print("\nTesting each byte individually:")

local expected_continuations = 0
for i = 1, #s do
    local byte = string.byte(s, i)
    local is_continuation = (byte >= 0x80 and byte <= 0xBF)
    if is_continuation then
        expected_continuations = expected_continuations + 1
    end

    -- Test pattern on this single byte
    local single_char = string.sub(s, i, i)
    local result, count = string.gsub(single_char, pattern, "X")

    print(string.format("  [%d] = %d (0x%02X) %s -> gsub count: %d",
        i, byte, byte,
        is_continuation and "CONTINUATION" or "",
        count))
end

print("\nExpected continuation bytes:", expected_continuations)

-- Now test the full string
local full_result, full_count = string.gsub(s, pattern, "X")
print("Full string gsub count:", full_count)

-- Expected: bytes 177,137,173,151,188,162,173,151 = 8 continuation bytes
print("Expected full count: 8")
print("Actual full count:", full_count)