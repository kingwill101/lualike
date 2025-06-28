-- Table method examples

-- Create a simple table with methods
local calculator = {
    value = 0,
    add = function(self, x)
        self.value = self.value + x
        return self  -- Return self for method chaining
    end,
    subtract = function(self, x)
        self.value = self.value - x
        return self
    end,
    multiply = function(self, x)
        self.value = self.value * x
        return self
    end,
    divide = function(self, x)
        self.value = self.value / x
        return self
    end,
    reset = function(self)
        self.value = 0
        return self
    end,
    getValue = function(self)
        return self.value
    end
}

-- Use the calculator object with method calls
print("Calculator demo:")
calculator:add(10)
print("After adding 10: " .. calculator:getValue())

calculator:subtract(3)
print("After subtracting 3: " .. calculator:getValue())

calculator:multiply(2)
print("After multiplying by 2: " .. calculator:getValue())

calculator:divide(7)
print("After dividing by 7: " .. calculator:getValue())

-- Method chaining
print("\nMethod chaining:")
calculator:reset():add(5):multiply(3):subtract(2)
print("Result after chaining: " .. calculator:getValue())

-- Create a table factory function (like a class)
local function createPerson(name, age)
    return {
        name = name,
        age = age,
        greet = function(self)
            return "Hello, my name is " .. self.name
        end,
        birthday = function(self)
            self.age = self.age + 1
            return self.age
        end
    }
end

-- Create and use person objects
print("\nPerson objects:")
local alice = createPerson("Alice", 30)
local bob = createPerson("Bob", 25)

print(alice:greet())
print(bob:greet())

print(alice.name .. " is now " .. alice:birthday() .. " years old")
print(bob.name .. " is now " .. bob:birthday() .. " years old")

-- Table with __index metamethod
local defaultPerson = {
    name = "Unknown",
    age = 0,
    greet = function(self)
        return "Hello, I am " .. self.name
    end
}

local meta = {
    __index = defaultPerson
}

-- Create a person with the metatable
local person = setmetatable({}, meta)
print("\nMetatable example:")
print("Default greeting: " .. person:greet())

-- Now customize the person
person.name = "Charlie"
print("Custom greeting: " .. person:greet())