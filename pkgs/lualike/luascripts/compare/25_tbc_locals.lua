-- Locals with to-be-closed attribute
local function wrap(v)
  return setmetatable({v}, {
    __close = function(t, err)
      t[1] = t[1] + 1
    end
  })
end

local function test()
  local values = {}
  do
    local x <close> = wrap(10)
    values[1] = x[1]
  end
  -- x was closed here
  do
    local a <close> = wrap(1)
    local b <close> = wrap(2)
    values[2] = a[1]
    values[3] = b[1]
  end
  return table.unpack(values)
end

return test()
