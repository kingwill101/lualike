-- Enable debug logging first
package.loadlib = package.loadlib or function() end

-- Access the debug object to enable logging
debug = debug or {}
debug.enable_logging = function()
    -- This will be called from Dart side
end

-- First enable debug mode (this will be handled by the Dart side via Logger.setEnabled)
print("Testing pattern with debug logging enabled...")

-- Test our problematic pattern
local x80 = string.char(0x80)
local test_string = "hello" .. x80 .. "world"
local pattern = "[\x80-\xBF]"

print("\nTest data:")
print("  Pattern:", pattern)
print("  Pattern length:", #pattern)
print("  Test string length:", #test_string)
print("  x80 position:", string.find(test_string, x80))

print("\nTesting pattern conversion...")
local ok, result, count = pcall(string.gsub, test_string, pattern, "X")

if ok then
    print("  Pattern succeeded")
    print("  Result:", result)
    print("  Count:", count)
    print("  Expected count: 1")
else
    print("  Pattern failed:", result)
end

-- Also test a working pattern for comparison
print("\nTesting working ASCII pattern [A-Z]...")
local test_ascii = "hello WORLD"
local ascii_pattern = "[A-Z]"
local ok2, result2, count2 = pcall(string.gsub, test_ascii, ascii_pattern, "X")

if ok2 then
    print("  ASCII pattern succeeded")
    print("  Result:", result2)
    print("  Count:", count2)
else
    print("  ASCII pattern failed:", result2)
end