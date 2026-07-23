-- Upvalues and closures
local function make_counter(step)
  local count = 0
  return function()
    count = count + step
    return count
  end
end

local function make_accumulator()
  local sum = 0
  local function add(v) sum = sum + v; return sum end
  local function reset() sum = 0 end
  return add, reset
end

local c1 = make_counter(1)
local c2 = make_counter(10)
local add, reset = make_accumulator()

return c1(), c2(), add(5), add(3), c1(), reset(), add(2)
