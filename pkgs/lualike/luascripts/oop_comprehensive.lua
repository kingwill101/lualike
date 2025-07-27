-- Comprehensive OOP Example in Lua

-- Simple class for a Point in 2D space
local Point = {}
Point.__index = Point

-- Constructor
function Point.new(x, y)
    local self = setmetatable({}, Point)
    self.x = x or 0
    self.y = y or 0
    return self
end

-- Methods
function Point:move(dx, dy)
    self.x = self.x + dx
    self.y = self.y + dy
    return self
end

function Point:distance(other)
    local dx = self.x - other.x
    local dy = self.y - other.y
    return math.sqrt(dx*dx + dy*dy)
end

-- String representation
function Point:__tostring()
    return string.format("Point(%d, %d)", self.x, self.y)
end

-- Addition metamethod
function Point.__add(a, b)
    return Point.new(a.x + b.x, a.y + b.y)
end

-- Equality metamethod
function Point.__eq(a, b)
    return a.x == b.x and a.y == b.y
end

-- Inheritance example: ColorPoint extends Point
local ColorPoint = {}
ColorPoint.__index = ColorPoint
setmetatable(ColorPoint, {__index = Point})  -- Set Point as parent

function ColorPoint.new(x, y, color)
    local self = setmetatable(Point.new(x, y), ColorPoint)
    self.color = color or "black"
    return self
end

-- Override toString
function ColorPoint:__tostring()
    return string.format("ColorPoint(%d, %d, %s)", self.x, self.y, self.color)
end

-- Additional method
function ColorPoint:changeColor(newColor)
    self.color = newColor
    return self
end

-- Shape class with protected attributes
local Shape = {}
Shape.__index = Shape

function Shape.new(name)
    local self = setmetatable({}, Shape)
    -- "Private" fields convention using underscores
    self._name = name
    self._visible = true
    return self
end

-- Getter/setter methods
function Shape:getName()
    return self._name
end

function Shape:setName(name)
    self._name = name
    return self
end

function Shape:isVisible()
    return self._visible
end

function Shape:setVisible(visible)
    self._visible = visible
    return self
end

function Shape:__tostring()
    return string.format("Shape('%s', visible=%s)", 
                        self._name, 
                        self._visible and "true" or "false")
end

-- Test all the OOP features
print("== Testing OOP Features ==")

print("\n-- Basic class instantiation and methods --")
local p1 = Point.new(10, 20)
local p2 = Point.new(30, 40)
print("p1:", p1)
print("p2:", p2)
p1:move(5, 5)
print("p1 after move:", p1)
print("Distance between p1 and p2:", p1:distance(p2))

print("\n-- Testing metamethods --")
local p3 = p1 + p2
print("p3 = p1 + p2:", p3)
print("p1 == p2:", p1 == p2)
local p4 = Point.new(15, 25)
print("p1 == p4:", p1 == p4)

print("\n-- Testing inheritance --")
local cp1 = ColorPoint.new(50, 60, "red")
print("cp1:", cp1)
cp1:move(10, 10)  -- Inherited method
print("cp1 after move:", cp1)
cp1:changeColor("blue")  -- Subclass method
print("cp1 after color change:", cp1)

print("\n-- Testing encapsulation --")
local shape = Shape.new("Rectangle")
print("shape:", shape)
print("shape name:", shape:getName())
shape:setName("Square"):setVisible(false)  -- Method chaining
print("shape after changes:", shape)