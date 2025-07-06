-- Minimal test for the problematic pattern
print("Testing pattern issue...")

-- Test the problematic pattern directly
local s = "hello"
print("String:", s)
print("#s =", #s)
print("utf8.len(s) =", utf8.len(s))

-- Test the pattern that's causing issues
print("\nTesting string.gsub...")
local result, count = string.gsub(s, "[\x80-\xBF]", "")
print("After gsub:", result)
print("Count:", count)
print("#result =", #result)

-- Manual calculation like in the test
local function len(s)
  return #string.gsub(s, "[\x80-\xBF]", "")
end

print("\nManual len function:")
print("len(s) =", len(s))

-- Test what the check function is doing
local function check(s, p, c)
  print("\ncheck function debug:")
  print("s =", s and ("'" .. s .. "'") or "nil")
  print("p =", p)
  print("#s =", s and #s or "nil")

  if s then
    local t = {string.byte(s, 1, -1)}
    print("#t =", #t)
    print("utf8.len(s) =", utf8.len(s))
    local manual_len = len(s)
    print("manual len(s) =", manual_len)
    print("Are they equal?", #t == manual_len)
  end
end

-- Test with simple strings
check("hello", 1, 1)
check("a", 1, 1)