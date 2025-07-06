-- Debug UTF-8 length calculations
print("Testing basic UTF-8 functions...")

-- Test with simple string first
local s = "hello World"
print("String: '" .. s .. "'")
print("utf8.len(s):", utf8.len(s))
print("Direct string length (#s):", #s)

-- Test with UTF-8 string
local s2 = "汉字"
print("\nString: '" .. s2 .. "'")
print("utf8.len(s2):", utf8.len(s2))
print("Direct string length (#s2):", #s2)

-- Test UTF-8 offset
print("\nutf8.offset tests:")
print("utf8.offset('alo', 1):", utf8.offset("alo", 1))
print("utf8.offset('alo', 2):", utf8.offset("alo", 2))
print("utf8.offset('alo', 0):", utf8.offset("alo", 0))

-- Test invalid offsets
print("utf8.offset('alo', 5):", utf8.offset("alo", 5))
print("utf8.offset('alo', -4):", utf8.offset("alo", -4))