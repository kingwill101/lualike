-- Test what our pattern processor generates
print("Testing pattern processing...")

-- Test the problematic pattern with logging enabled
local pattern = "[\x80-\xBF]"
print("Input pattern: '" .. pattern .. "'")

-- Use pcall to catch the error and see what happens
local ok, result = pcall(string.gsub, "test", pattern, "X")
if ok then
  print("Pattern worked! Result:", result)
else
  print("Pattern failed with error:", result)
end

-- Test other patterns to see if they work
print("\nTesting other patterns:")

-- Simple character class
local ok2, result2 = pcall(string.gsub, "test", "[abc]", "X")
if ok2 then
  print("[abc] worked:", result2)
else
  print("[abc] failed:", result2)
end

-- ASCII byte range
local ok3, result3 = pcall(string.gsub, "test", "[a-z]", "X")
if ok3 then
  print("[a-z] worked:", result3)
else
  print("[a-z] failed:", result3)
end