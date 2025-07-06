-- Debug the actual bytes in the pattern string
print("Debugging pattern bytes...")

local pattern = "[\x80-\xBF]"
print("Pattern string: '" .. pattern .. "'")
print("Pattern length: " .. #pattern)

print("\nPattern bytes:")
for i = 1, #pattern do
  local byte = string.byte(pattern, i)
  local char = string.sub(pattern, i, i)
  print(string.format("  [%d] = %d (0x%02x) '%s'", i, byte, byte, char))
end

-- Test what we get when we construct the hex bytes manually
local x80 = string.char(0x80)
local xBF = string.char(0xBF)
print("\nManual hex bytes:")
print("\\x80 byte:", string.byte(x80))
print("\\xBF byte:", string.byte(xBF))

-- Try to construct the pattern manually
local manual_pattern = "[" .. x80 .. "-" .. xBF .. "]"
print("\nManual pattern: '" .. manual_pattern .. "'")
print("Manual pattern length: " .. #manual_pattern)

print("\nManual pattern bytes:")
for i = 1, #manual_pattern do
  local byte = string.byte(manual_pattern, i)
  local char = string.sub(manual_pattern, i, i)
  print(string.format("  [%d] = %d (0x%02x) '%s'", i, byte, byte, char))
end