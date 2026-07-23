-- Locals with const attribute
local function test()
  local x <const> = 42
  local y <const> = "hello"
  local z <const> = true
  return x, y, z
end
return test()
