-- String OOP method examples

-- Basic string methods using colon notation
local s = "Hello World"
print("Original string: " .. s)

-- Length method
local len = s:len()
print("Length: " .. len)

-- Uppercase method
local upper = s:upper()
print("Uppercase: " .. upper)

-- Lowercase method
local lower = s:lower()
print("Lowercase: " .. lower)

-- Substring method
local sub = s:sub(1, 5)
print("Substring (1,5): " .. sub)

-- Get byte value of first character
local first_char_code = s:byte(1)
print("First char code: " .. first_char_code)

-- Replace method
local replaced = s:gsub("World", "Lua")
print("After gsub: " .. replaced)

-- Find method
local position = s:find("World")
print("Position of 'World': " .. position)

-- Multiple method calls in sequence
local transformed = s:upper():sub(1, 5):gsub("H", "J")
print("Transformed: " .. transformed)

-- String format with method call
local formatted = ("Pi = %.2f"):format(math.pi)
print(formatted)

-- Split a string using patterns
local csv = "apple,orange,banana,grape"
print("CSV string: " .. csv)
for fruit in csv:gmatch("[^,]+") do
    print("Fruit: " .. fruit)
end