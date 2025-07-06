-- Test really basic patterns
print("Testing very basic patterns...")

-- Test literal character
local ok1, result1 = pcall(string.gsub, "test", "t", "X")
print("Literal 't':", ok1 and result1 or "FAILED")

-- Test dot (any character)
local ok2, result2 = pcall(string.gsub, "test", ".", "X")
print("Dot '.':", ok2 and result2 or "FAILED")

-- Test simple magic character
local ok3, result3 = pcall(string.gsub, "test", "%a", "X")
print("Magic '%a':", ok3 and result3 or "FAILED")

-- Test simple quantifier
local ok4, result4 = pcall(string.gsub, "test", "t*", "X")
print("Quantifier 't*':", ok4 and result4 or "FAILED")

-- Test why character classes fail
print("\nDebug character class processing...")
local pattern = "[abc]"
print("Testing pattern:", pattern)
-- Try to see actual error
local success, err = pcall(string.gsub, "test", pattern, "X")
print("Success:", success)
print("Error:", err)