-- Basic string method calls using OOP syntax (colon notation)
local s = "Hello World"

-- Get the length of the string
local len = s:len()
print("String length: " .. len)

-- Convert string to uppercase
local upper = s:upper()
print("Uppercase: " .. upper)

-- Get the byte (ASCII) value of the first character
local first_char_code = s:byte(1)
print("First character code: " .. first_char_code)

-- Extract a substring (first 5 characters)
local sub = s:sub(1, 5)
print("Substring: " .. sub)

-- Method call is syntactic sugar for:
-- local sub = string.sub(s, 1, 5)
-- The colon syntax automatically passes the object as the first parameter

print("s=" .. s)
print("len=" .. len)
print("upper=" .. upper)
print("first_char_code=" .. first_char_code)
print("sub=" .. sub)
