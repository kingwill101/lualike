local function func()
    return 3, 4
end

local function func2(...)
    return ...
end

local function print_table_contents(tbl)
    local t = '{'
    for k, v in pairs(tbl) do
        t = t .. tostring(k) .. ' = ' ..tostring(v) .. '  '
    end
    return t .. '}'
end

local a = { func()}
local b = { func(), 1, 2}
local c = { 1,func(), 2, func()}
local d = {func2(1,2,3,4)}
local e = {func2()}
local f = {func2(1,2)}
local g = {func2(1,2), 3}
local h = {1, func2(2,3), func()}
local i = {1, func2(2,3), inside =print_table_contents({111})}

--- print all the table contents
print( "a = " .. print_table_contents(a))
print( "b = " .. print_table_contents(b))
print( "c = " .. print_table_contents(c))
print( "d = " .. print_table_contents(d))
print( "e = " .. print_table_contents(e))
print( "f = " .. print_table_contents(f))
print( "g = " .. print_table_contents(g))
print( "h = " .. print_table_contents(h))
print( "i = " .. print_table_contents(i))

--[[
prints out
lua luascripts/table_constructors.lua
a = 1 = 3  2 = 4
b = 1 = 3  2 = 1  3 = 2
c = 1 = 1  2 = 3  3 = 2  4 = 3  5 = 4
d = 1 = 1  2 = 2  3 = 3  4 = 4
e =
f = 1 = 1  2 = 2
g = 1 = 1  2 = 3
h = 1 = 1  2 = 2  3 = 3  4 = 4
i = 1 = 1  2 = 2  inside = table: 0x568fb069a250
]]
