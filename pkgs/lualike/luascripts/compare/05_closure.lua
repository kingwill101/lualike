-- Closures and upvalues
local function make_counter()
  local count = 0
  return function()
    count = count + 1
    return count
  end
end
local c1 = make_counter()
return c1(), c1(), make_counter()()
