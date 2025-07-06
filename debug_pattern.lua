-- Debug pattern handling in detail
print("Testing detailed pattern handling...")

-- Create the pattern string step by step
print("Building pattern components...")
local left_bracket = "["
local x80 = "\x80"
local dash = "-"
local xBF = "\xBF"
local right_bracket = "]"

print("Individual components:")
print("x80 byte value:", string.byte(x80))
print("xBF byte value:", string.byte(xBF))

-- Build the full pattern
local pattern = left_bracket .. x80 .. dash .. xBF .. right_bracket
print("\nFull pattern length:", #pattern)

-- Print each byte of the pattern
print("Pattern bytes:")
for i = 1, #pattern do
  print(i, string.byte(pattern, i))
end

-- Test with a simpler case first
print("\nTesting simple pattern [a-z]...")
local ok1, result1 = pcall(string.gsub, "hello", "[a-z]", "X")
if ok1 then
  print("Simple pattern works:", result1)
else
  print("Simple pattern error:", result1)
end

-- Test with hex range that should work
print("\nTesting ASCII hex range [\\x41-\\x5A]...")
local ok2, result2 = pcall(string.gsub, "ABC", "[\x41-\x5A]", "X")
if ok2 then
  print("ASCII hex range works:", result2)
else
  print("ASCII hex range error:", result2)
end