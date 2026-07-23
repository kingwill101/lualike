-- Comprehensive test exercising all Lua features across the compiler pipeline
-- Run: dart run tool/compare.dart ir luascripts/compare/99_comprehensive.lua
-- Run: dart run bin/main.dart luascripts/compare/99_comprehensive.lua

-- ============================================================================
-- 1.  MATH & NUMBERS
-- ============================================================================
local a, b, c = 10, 3, 7
local res = {}

-- Basic arithmetic
res.ADD  = a + b
res.SUB  = a - b
res.MUL  = a * b
res.DIV  = a / b
res.MOD  = a % b
res.POW  = a ^ b
res.IDIV = a // b
res.NEG  = -a

-- Arithmetic with immediates (ADDI, SUBI)
res.ADDI = a + 5
res.SUBI = a - 3

-- Arithmetic with constants (ADDK, SUBK, MULK, DIVK, MODK, POWK, IDIVK)
local big = 100
res.ADDK = a + big
res.SUBK = a - big
res.MULK = a * big
res.DIVK = a / big
res.MODK = a % big
res.POWK = a ^ 2
res.IDIVK = a // 3

-- Increment / loop counter patterns
local sum = 0
for i = 1, 5 do
  sum = sum + i
end
res.FOR_SUM = sum

-- Float / NaN / Inf
res.FLOAT_PI = 3.14159
local inf = 1/0
res.IS_INF = inf > 999
res.NEG_ZERO = -0.0

-- ============================================================================
-- 2.  BITWISE OPS
-- ============================================================================
local x, y = 0xFF, 0x0F

res.BAND  = x & y
res.BOR   = x | y
res.BXOR  = x ~ y
res.BNOT  = ~x
res.SHL   = 1 << 3
res.SHR   = 8 >> 2
res.SHLI  = 1 << 4
res.SHRI  = 16 >> 2

-- Bitwise with constants (BANDK, BORK, BXORK)
local z = 0xAA
res.BANDK = z & 0x0F
res.BORK  = z | 0x01
res.BXORK = z ~ 0xFF

-- ============================================================================
-- 3.  BOOLEANS, NIL, COMPARISONS
-- ============================================================================
res.TRUE   = true
res.FALSE  = false
res.NIL    = nil

-- Not
res.NOT_TRUE  = not true
res.NOT_FALSE = not false
res.NOT_NIL   = not nil
res.NOT_NUM   = not 0     -- in Lua, only false/nil are falsy

-- Comparisons
res.EQ  = 5 == 5
res.NEQ = 5 ~= 3
res.LT  = 3 < 5
res.LE  = 3 <= 3
res.GT  = 5 > 3
res.GE  = 5 >= 5

-- Comparison with immediates
res.EQI  = 5 == 5
res.LTI  = 3 < 7
res.LEI  = 3 <= 7
res.GTI  = 7 > 3
res.GEI  = 7 >= 7

-- Comparison with constants
local target = 42
res.EQK  = 42 == target

-- ============================================================================
-- 4.  STRINGS & CONCAT
-- ============================================================================
local hello = "hello"
local world = "world"
res.CONCAT = hello .. " " .. world
res.STR_LEN = #hello

-- String comparisons
res.STR_EQ = "abc" == "abc"
res.STR_LT = "abc" < "def"

-- Long strings
local long = [[multi
line
string]]
res.LONG_STR = #long > 10

-- ============================================================================
-- 5.  TABLES
-- ============================================================================
-- Table literal (sequential)
local t = {10, 20, 30}
res.TBL_IDX1 = t[1]
res.TBL_IDX2 = t[2]
res.TBL_IDX3 = t[3]

-- Table with field keys (GETFIELD / SETFIELD)
local t2 = {a = 1, b = 2, c = 3}
res.FIELD_A = t2.a
res.FIELD_B = t2.b

-- Table insert / update
t2.d = 4
res.FIELD_D = t2.d

-- Nested tables
local t3 = {inner = {x = 100}}
res.NESTED = t3.inner.x

-- Table length
res.TBL_LEN = #t
res.TBL_LEN2 = #t2

-- GETI / SETI (integer key access)
local ti = {}
ti[1] = 100
ti[5] = 500
res.GETI_1 = ti[1]
res.GETI_5 = ti[5]

-- SETLIST (table constructor with array elements)
local large = {1, 2, 3, 4, 5, 6, 7, 8}
res.LARGE_1 = large[1]
res.LARGE_8 = large[8]

-- Table as map
local map = {name = "test", value = 42}
res.MAP_NAME = map.name
res.MAP_VALUE = map.value

-- ============================================================================
-- 6.  CONTROL FLOW
-- ============================================================================
-- if / elseif / else
local branch_res = ""
if false then
  branch_res = "never"
elseif 3 > 5 then
  branch_res = "never2"
else
  branch_res = "else"
end
res.BRANCH = branch_res

-- While loop
local wsum = 0
local wi = 1
while wi <= 5 do
  wsum = wsum + wi
  wi = wi + 1
end
res.WHILE_SUM = wsum

-- Repeat until
local rsum = 0
local ri = 1
repeat
  rsum = rsum + ri
  ri = ri + 1
until ri > 5
res.REPEAT_SUM = rsum

-- Numeric for loop (FORPREP / FORLOOP)
local nsum = 0
for i = 1, 10, 2 do
  nsum = nsum + i
end
res.NFOR_STEP2 = nsum

-- Generic for loop (TFORPREP / TFORCALL / TFORLOOP)
local gsum = 0
for k, v in pairs({a = 10, b = 20, c = 30}) do
  gsum = gsum + v
end
res.GFOR_SUM = gsum

-- ipairs generic for
local ipsum = 0
for i, v in ipairs({100, 200, 300}) do
  ipsum = ipsum + v
end
res.IPAIRS_SUM = ipsum

-- Break
local found = false
for i = 1, 100 do
  if i == 7 then
    found = true
    break
  end
end
res.BREAK = found

-- ============================================================================
-- 7.  FUNCTIONS & CALLS
-- ============================================================================
-- Simple function
local function add(x, y)
  return x + y
end
res.FN_ADD = add(3, 4)

-- Function with default / multi-return
local function sum_and_count(...)
  local s = 0
  local n = 0
  for i, v in ipairs({...}) do
    s = s + v
    n = i
  end
  return s, n
end
local s, n = sum_and_count(1, 2, 3, 4, 5)
res.VARARG_SUM = s
res.VARARG_CNT = n

-- Tail call
local function tail_fact(n, acc)
  if n <= 1 then return acc end
  return tail_fact(n - 1, acc * n)
end
res.TAIL_FACT = tail_fact(5, 1)

-- Closure
local function make_counter()
  local count = 0
  return function()
    count = count + 1
    return count
  end
end
local c1 = make_counter()
res.CLOSURE_1 = c1()
res.CLOSURE_2 = c1()
res.CLOSURE_3 = c1()

-- Method call sugar (SELF)
local obj = {val = 42}
function obj:get()
  return self.val
end
res.METHOD = obj:get()

-- Anonymous function
local double = function(x) return x * 2 end
res.ANON = double(21)

-- ============================================================================
-- 8.  UPVALUES
-- ============================================================================
local function make_accumulator()
  local total = 0
  return {
    add = function(v)
      total = total + v
      return total
    end,
    get = function()
      return total
    end,
  }
end
local acc = make_accumulator()
res.UPV_ADD1 = acc.add(10)
res.UPV_ADD2 = acc.add(20)
res.UPV_GET  = acc.get()

-- ============================================================================
-- 9.  VARARGS
-- ============================================================================
local function vararg_fn(...)
  local args = {...}
  return #args, args[1], args[#args]
end
local vn, vfirst, vlast = vararg_fn(10, 20, 30, 40)
res.VARARG_N     = vn
res.VARARG_FIRST = vfirst
res.VARARG_LAST  = vlast

-- GETVARG (single vararg by index)
local function get_third(...)
  local arg3 = select(3, ...)
  return arg3
end
res.SELECT_3 = get_third("a", "b", "c", "d")

-- ============================================================================
-- 10. METATABLES & METAMETHODS (mmBin* path)
-- ============================================================================
-- Vector with __add metamethod
local Vector = {}
Vector.__index = Vector

function Vector:new(x, y)
  return setmetatable({x = x, y = y}, Vector)
end

function Vector.__add(a, b)
  return Vector:new(a.x + b.x, a.y + b.y)
end

local v1 = Vector:new(1, 2)
local v2 = Vector:new(3, 4)
local v3 = v1 + v2
res.META_ADD_X = v3.x
res.META_ADD_Y = v3.y

-- __sub metamethod
function Vector.__sub(a, b)
  return Vector:new(a.x - b.x, a.y - b.y)
end
local v4 = v2 - v1
res.META_SUB_X = v4.x
res.META_SUB_Y = v4.y

-- __tostring
function Vector.__tostring(v)
  return "Vector(" .. v.x .. ", " .. v.y .. ")"
end
res.META_TOSTR = tostring(v1)

-- __len
local function make_string_wrapper(s)
  return setmetatable({str = s}, {
    __len = function(self) return #self.str end
  })
end
local w = make_string_wrapper("hello")
res.META_LEN = #w

-- __index / __newindex (proxy table)
local default_tbl = setmetatable({}, {
  __index = function(_, k) return "default_" .. k end
})
res.META_INDEX = default_tbl.unknown_key

-- __eq metamethod
local function make_box(v)
  return setmetatable({value = v}, {
    __eq = function(a, b) return a.value == b.value end
  })
end
local box1 = make_box(42)
local box2 = make_box(42)
res.META_EQ = box1 == box2

-- ============================================================================
-- 11. GLOBALS
-- ============================================================================
-- Read / write globals (GETTABUP / SETTABUP)
_GLOBAL_TEST = 77
res.GLOBAL_READ = _GLOBAL_TEST

-- ============================================================================
-- 12. MISCELLANEOUS
-- ============================================================================
-- Do-block
do
  local x_in_block = 42
  res.DO_BLOCK = x_in_block
end

-- Multiple assignment
local ma, mb, mc = 1, 2, 3
res.MULTI_A = ma
res.MULTI_C = mc

-- Multi-return from function
local function multi_ret()
  return 10, 20, 30
end
local ra, rb, rc = multi_ret()
res.MRET_A = ra
res.MRET_B = rb
res.MRET_C = rc

-- Short-circuit and/or
res.AND_TRUE  = true and 42
res.AND_FALSE = false and 42
res.OR_TRUE   = true or 99
res.OR_FALSE  = false or 99

-- Nested expressions
res.COMPLEX = (1 + 2) * (3 + 4) / (5 - 2) ^ 2

-- ============================================================================
-- 13. ASSERTIONS — verify against expected values
-- ============================================================================
local function assert_eq(got, expected, label)
  if got ~= expected then
    error(string.format("FAIL %s: expected %s, got %s", label, tostring(expected), tostring(got)))
  end
end

assert_eq(res.ADD, 13, "ADD")
assert_eq(res.SUB, 7, "SUB")
assert_eq(res.MUL, 30, "MUL")
assert_eq(res.DIV, 10/3, "DIV")
assert_eq(res.MOD, 1, "MOD")
assert_eq(res.POW, 1000, "POW")
assert_eq(res.IDIV, 3, "IDIV")
assert_eq(res.NEG, -10, "NEG")
assert_eq(res.ADDI, 15, "ADDI")
assert_eq(res.SUBI, 7, "SUBI")
assert_eq(res.BAND, 0x0F, "BAND")
assert_eq(res.BOR, 0xFF, "BOR")
assert_eq(res.BXOR, 0xF0, "BXOR")
assert_eq(res.BNOT, -256, "BNOT")
assert_eq(res.SHL, 8, "SHL")
assert_eq(res.SHR, 2, "SHR")
assert_eq(res.TRUE, true, "TRUE")
assert_eq(res.NOT_TRUE, false, "NOT_TRUE")
assert_eq(res.NOT_FALSE, true, "NOT_FALSE")
assert_eq(res.NOT_NIL, true, "NOT_NIL")
assert_eq(res.NOT_NUM, false, "NOT_NUM")
assert_eq(res.EQ, true, "EQ")
assert_eq(res.NEQ, true, "NEQ")
assert_eq(res.CONCAT, "hello world", "CONCAT")
assert_eq(res.METHOD, 42, "METHOD")
assert_eq(res.ANON, 42, "ANON")
assert_eq(res.META_ADD_X, 4, "META_ADD_X")
assert_eq(res.META_ADD_Y, 6, "META_ADD_Y")
assert_eq(res.META_SUB_X, 2, "META_SUB_X")
assert_eq(res.META_SUB_Y, 2, "META_SUB_Y")
assert_eq(res.META_LEN, 5, "META_LEN")
assert_eq(res.BREAK, true, "BREAK")
assert_eq(res.VARARG_N, 4, "VARARG_N")
assert_eq(res.TAIL_FACT, 120, "TAIL_FACT")
assert_eq(res.GLOBAL_READ, 77, "GLOBAL_READ")
assert_eq(res.COMPLEX, 3 * 7 / (9), "COMPLEX") -- (1+2)*(3+4)/(5-2)^2 = 3*7/9

print("ALL TESTS PASSED")
return res
