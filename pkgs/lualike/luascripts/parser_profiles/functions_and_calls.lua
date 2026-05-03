local function pair(a, b)
  return a + b, a - b
end

local function fold(seed, ...)
  local total = seed
  for _, value in ipairs({...}) do
    total = total + value
  end
  return total
end

local plus, minus = pair(10, 4)
return fold(plus, minus, pair(3, 1))
