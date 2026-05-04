local<const> limit = 4
local total = 0

::again::
total = total + limit
if total < 16 then
  goto again
end

return total
