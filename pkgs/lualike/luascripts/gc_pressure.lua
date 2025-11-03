local unpack = table.unpack

local maxI = math.maxinteger
local minI = math.mininteger

local function checkerror (msg, f, ...)
  local s, err = pcall(f, ...)
  assert(not s and string.find(err, msg))
end

-- test checks for invalid order functions
local function check (t)
  local function f(a, b) assert(a and b); return true end
  checkerror("invalid order function", table.sort, t, f)
end


local function perm (s, n)
  n = n or #s
  if n == 1 then
    local t = {unpack(s)}
    table.sort(t)
    check(t)
  else
    for i = 1, n do
      s[i], s[n] = s[n], s[i]
      perm(s, n - 1)
      s[i], s[n] = s[n], s[i]
    end
  end
end

print("perm{}")
perm{}
print("perm{1}")
perm{1}
print("perm{1,2}")
perm{1,2}
print("perm{1,2,3}")
perm{1,2,3}
print("perm{1,2,3,4}")
perm{1,2,3,4}
print("perm{2,2,3,4}")
perm{2,2,3,4}
print("perm{1,2,3,4,5}")
perm{1,2,3,4,5}
print("perm{1,2,3,3,5}")
perm{1,2,3,3,5}
print("perm{1,2,3,4,5,6}")
perm{1,2,3,4,5,6}
print("perm{2,2,3,3,5,6}")
perm{2,2,3,3,5,6}

print("done")
