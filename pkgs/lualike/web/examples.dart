// Lua examples for the web interface
class LuaExamples {
  static const Map<String, String> examples = {
    'hello': '''-- Hello World Example
print("Hello, World!")
print("Welcome to LuaLike!")

-- Variables and basic operations
local name = "LuaLike"
local version = 5.4
print("Running " .. name .. " " .. version)''',

    'fibonacci': '''-- Fibonacci Sequence
function fibonacci(n)
    if n <= 1 then
        return n
    else
        return fibonacci(n - 1) + fibonacci(n - 2)
    end
end

-- Calculate first 10 fibonacci numbers
print("Fibonacci sequence:")
for i = 0, 9 do
    print("F(" .. i .. ") = " .. fibonacci(i))
end''',

    'table': '''-- Table Operations
-- Create a table
local fruits = {"apple", "banana", "cherry"}

-- Add elements
fruits[4] = "date"
fruits["favorite"] = "mango"

-- Iterate through table
print("Fruits list:")
for i, fruit in ipairs(fruits) do
    print(i .. ": " .. fruit)
end

-- Table as a map
local person = {
    name = "Alice",
    age = 30,
    city = "New York"
}

print("\\nPerson info:")
for key, value in pairs(person) do
    print(key .. ": " .. value)
end''',

    'functions': '''-- Functions and Closures
-- Function with multiple return values
function divmod(a, b)
    local quotient = math.floor(a / b)
    local remainder = a % b
    return quotient, remainder
end

local q, r = divmod(17, 5)
print("17 ÷ 5 = " .. q .. " remainder " .. r)

-- Closure example
function makeCounter(start)
    local count = start or 0
    return function()
        count = count + 1
        return count
    end
end

local counter = makeCounter(10)
print("Counter: " .. counter()) -- 11
print("Counter: " .. counter()) -- 12
print("Counter: " .. counter()) -- 13''',

    'goto': '''-- Goto and Labels
print("Starting goto demo")

local total = 0
local i = 1

::loop::
if i > 5 then
    goto finish
end

total = total + i
i = i + 1
goto loop

::finish::
print("Sum of the first five integers is " .. total)

local message = "before"
goto skip
message = "this line is skipped"
::skip::
print("Final message: " .. message)''',

    'metatable': '''-- Metatables Example
-- Create a vector class
Vector = {}
Vector.__index = Vector

function Vector.new(x, y)
    local v = {x = x or 0, y = y or 0}
    setmetatable(v, Vector)
    return v
end

function Vector:__add(other)
    return Vector.new(self.x + other.x, self.y + other.y)
end

function Vector:__tostring()
    return "(" .. self.x .. ", " .. self.y .. ")"
end

-- Create and use vectors
local v1 = Vector.new(3, 4)
local v2 = Vector.new(1, 2)
local v3 = v1 + v2

print("v1 = " .. tostring(v1))
print("v2 = " .. tostring(v2))
print("v1 + v2 = " .. tostring(v3))''',

    'string': '''-- String Manipulation
local text = "  Hello, LuaLike World!  "

-- String functions
print("Original: '" .. text .. "'")
print("Length: " .. #text)
print("Upper: " .. string.upper(text))
print("Lower: " .. string.lower(text))
print("Trimmed: '" .. string.gsub(text, "^%s*(.-)%s*\$", "%1") .. "'")

-- Pattern matching
local sentence = "The quick brown fox jumps over the lazy dog"
print("\\nPattern matching:")
print("Words starting with 't': " .. string.gsub(sentence, "%f[%a][Tt]%w*", "[%0]"))

-- String formatting
local name, age = "Alice", 25
print(string.format("\\nHello, %s! You are %d years old.", name, age))''',

    'math': '''-- Math Operations
print("Basic Math:")
print("π = " .. math.pi)
print("e = " .. math.exp(1))
print("sqrt(16) = " .. math.sqrt(16))
print("sin(π/2) = " .. math.sin(math.pi/2))
print("log(e) = " .. math.log(math.exp(1)))

-- Random numbers
math.randomseed(os.time and os.time() or 12345)
print("\\nRandom numbers:")
for i = 1, 5 do
    print("Random " .. i .. ": " .. math.random(1, 100))
end

-- Calculations
local function factorial(n)
    if n <= 1 then
        return 1
    else
        return n * factorial(n - 1)
    end
end

print("\\nFactorials:")
for i = 1, 8 do
    print(i .. "! = " .. factorial(i))
end''',

    'coroutines': '''-- Coroutines Example
-- Create a simple coroutine
function numberGenerator()
    for i = 1, 5 do
        coroutine.yield(i)
    end
end

local co = coroutine.create(numberGenerator)

print("Coroutine values:")
while coroutine.status(co) ~= "dead" do
    local success, value = coroutine.resume(co)
    if success then
        print("Yielded: " .. value)
    end
end

-- Producer-consumer pattern
function producer()
    for i = 1, 3 do
        print("Producing: " .. i)
        coroutine.yield(i)
    end
end

function consumer()
    local co = coroutine.create(producer)
    while coroutine.status(co) ~= "dead" do
        local success, value = coroutine.resume(co)
        if success then
            print("Consuming: " .. value)
        end
    end
end

print("\\nProducer-Consumer:")
consumer()''',

    'oop': '''-- Object-Oriented Programming
-- Simple class implementation
Person = {}
Person.__index = Person

function Person.new(name, age)
    local self = setmetatable({}, Person)
    self.name = name
    self.age = age
    return self
end

function Person:greet()
    return "Hello, I'm " .. self.name .. " and I'm " .. self.age .. " years old."
end

function Person:birthday()
    self.age = self.age + 1
    return self.name .. " is now " .. self.age .. " years old!"
end

-- Create and use objects
local alice = Person.new("Alice", 25)
local bob = Person.new("Bob", 30)

print(alice:greet())
print(bob:greet())
print(alice:birthday())
print(bob:birthday())''',

    'error_handling': '''-- Error Handling with pcall
-- Function that might fail
function riskyOperation(n)
    if n < 0 then
        error("Cannot handle negative numbers")
    end
    return n * 2
end

-- Safe execution with pcall
print("Testing error handling:")
local success, result = pcall(riskyOperation, 5)
if success then
    print("Success: " .. result)
else
    print("Error: " .. result)
end

success, result = pcall(riskyOperation, -3)
if success then
    print("Success: " .. result)
else
    print("Error: " .. result)
end

-- Custom error handler
function safeDivide(a, b)
    if b == 0 then
        error("Division by zero")
    end
    return a / b
end

print("\\nSafe division:")
local results = {pcall(safeDivide, 10, 2), pcall(safeDivide, 10, 0)}
for i, result in ipairs(results) do
    print("Result " .. i .. ": " .. tostring(result))
end''',

    'file_io': '''-- File I/O Operations
-- Write to a file
local file = io.open("test.txt", "w")
if file then
    file:write("Hello from LuaLike!\\n")
    file:write("This is a test file.\\n")
    file:close()
    print("File written successfully")
else
    print("Could not open file for writing")
end

-- Read from a file
file = io.open("test.txt", "r")
if file then
    print("\\nFile contents:")
    for line in file:lines() do
        print(line)
    end
    file:close()
else
    print("Could not open file for reading")
end

-- Working with strings as files
local data = "line1\\nline2\\nline3"
local stringFile = io.open("data", "w")
stringFile:write(data)
stringFile:close()

stringFile = io.open("data", "r")
print("\\nString file contents:")
for line in stringFile:lines() do
    print("Read: " .. line)
end
stringFile:close()''',
  };

  // Display names for the examples
  static const Map<String, String> displayNames = {
    'hello': 'Hello World',
    'goto': 'Goto and Labels',
    'fibonacci': 'Fibonacci Sequence',
    'table': 'Table Operations',
    'functions': 'Functions & Closures',
    'metatable': 'Metatables',
    'string': 'String Manipulation',
    'math': 'Math Operations',
    'coroutines': 'Coroutines',
    'oop': 'Object-Oriented Programming',
    'error_handling': 'Error Handling',
    'file_io': 'File I/O Operations',
  };

  // Get all example keys
    static List<String> get keys => examples.keys.toList()..sort();

  // Get example code by key
  static String? getExample(String key) => examples[key];

  // Get display name by key
  static String? getDisplayName(String key) => displayNames[key];

  // Get all examples as a list of key-value pairs
  static List<MapEntry<String, String>> get allExamples =>
      examples.entries.toList();
}
