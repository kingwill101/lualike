-- Debug pattern conversion in extreme detail
print("Testing Dart LuaPattern conversion...")

-- Try to manually inspect the pattern conversion
local pattern_str = "[a-z]"
print("Original pattern:", pattern_str)

-- Test some basic string functions first to ensure they work
print("\nBasic string test:")
print("String length of 'hello':", #"hello")
print("String byte of 'a':", string.byte("a"))

-- Try a super simple pattern
print("\nTesting super simple patterns...")
local ok1, result1 = pcall(string.match, "abc", "a")
if ok1 then
  print("Simple 'a' pattern works:", result1)
else
  print("Simple 'a' pattern error:", result1)
end

-- Try dot pattern
local ok2, result2 = pcall(string.match, "abc", ".")
if ok2 then
  print("Dot '.' pattern works:", result2)
else
  print("Dot '.' pattern error:", result2)
end

-- Try simple alternation
local ok3, result3 = pcall(string.match, "abc", "a|b")
if ok3 then
  print("Alternation 'a|b' pattern works:", result3)
else
  print("Alternation 'a|b' pattern error:", result3)
end