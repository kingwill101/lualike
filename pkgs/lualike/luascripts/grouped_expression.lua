-- tgrouped_expressions.lua
-- A comprehensive test of grouped expressions in different assignment contexts

-- Define helper functions that return multiple values
function returns_three_values()
  return 1, 2, 3
end

function returns_one_value()
  return 42
end

-- Initialize a table for testing
local t = {x = 10, y = 20, z = 30}

print("====== Regular variable assignment ======")
print("\n1. Multiple variables, direct function call:")
local a, b, c = returns_three_values()
print("a =", a, "b =", b, "c =", c)  -- Should be: a = 1, b = 2, c = 3

print("\n2. Multiple variables, grouped function call:")
local d, e, f = (returns_three_values())
print("d =", d, "e =", e, "f =", f)  -- Should be: d = 1, e = nil, f = nil

print("\n3. Single variable, direct function call:")
local g = returns_three_values()
print("g =", g)  -- Should be: g = 1 (first return value only)

print("\n4. Single variable, grouped function call:")
local h = (returns_three_values())
print("h =", h)  -- Should be: h = 1 (first return value only)

print("\n====== Local declaration ======")
print("\n5. Multiple locals, direct function call:")
local i, j, k = returns_three_values()
print("i =", i, "j =", j, "k =", k)  -- Should be: i = 1, j = 2, k = 3

print("\n6. Multiple locals, grouped function call:")
local l, m, n = (returns_three_values())
print("l =", l, "m =", m, "n =", n)  -- Should be: l = 1, m = nil, n = nil

print("\n7. Single local, direct function call:")
local o = returns_three_values()
print("o =", o)  -- Should be: o = 1

print("\n8. Single local, grouped function call:")
local p = (returns_three_values())
print("p =", p)  -- Should be: p = 1

print("\n====== Table index assignment ======")
print("\n9. Table field, direct function call:")
t.field = returns_three_values()
print("t.field =", t.field)  -- Should be: t.field = 1

print("\n10. Table field, grouped function call:")
t.field2 = (returns_three_values())
print("t.field2 =", t.field2)  -- Should be: t.field2 = 1

print("\n11. Table index, direct function call:")
t[1] = returns_three_values()
print("t[1] =", t[1])  -- Should be: t[1] = 1

print("\n12. Table index, grouped function call:")
t[2] = (returns_three_values())
print("t[2] =", t[2])  -- Should be: t[2] = 1

print("\n====== Mixed and complex assignments ======")
print("\n13. Multiple return values mixed with regular values:")
local q, r, s = returns_one_value(), returns_three_values()
print("q =", q, "r =", r, "s =", s)  -- Should be: q = 42, r = 1, s = 2

print("\n14. Grouped expressions mixed with regular values:")
local u, v, w = returns_one_value(), (returns_three_values())
print("u =", u, "v =", v, "w =", w)  -- Should be: u = 42, v = 1, w = nil

print("\n15. Assignment with expressions:")
local x = 10 + (returns_one_value())
print("x =", x)  -- Should be: x = 52 (10 + 42)

print("\n16. Multiple assignments with expressions:")
local y, z = (returns_one_value() + 5), (returns_three_values() + 10)
print("y =", y, "z =", z)  -- Should be: y = 47, z = 11

print("\n17. Nested grouped expressions:")
local result = ((returns_three_values()))
print("result =", result)  -- Should be: result = 1

print("\n====== Table constructors with function returns ======")
print("\n18. Table constructor with direct function call:")
local tab1 = {returns_three_values()}
print("tab1[1] =", tab1[1], "tab1[2] =", tab1[2], "tab1[3] =", tab1[3])  -- Should include all values

print("\n19. Table constructor with grouped function call:")
local tab2 = {(returns_three_values())}
print("tab2[1] =", tab2[1], "tab2[2] =", tab2[2])  -- Should include only the first value

print("\n20. Complex table constructor:")
local tab3 = {10, returns_three_values(), 20}
print("tab3[1] =", tab3[1], "tab3[2] =", tab3[2], "tab3[3] =", tab3[3], "tab3[4] =", tab3[4])  -- Should include the first return value only in the middle

print("\n21. Complex table constructor with grouped call:")
local tab4 = {10, (returns_three_values()), 20}
print("tab4[1] =", tab4[1], "tab4[2] =", tab4[2], "tab4[3] =", tab4[3])  -- Should have three elements
