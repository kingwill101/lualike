-- Lexical scoping with do blocks
local x = 10
do
  local x = 20
  do
    local x = 30
    assert(x == 30)
  end
  assert(x == 20)
end
assert(x == 10)
return x
