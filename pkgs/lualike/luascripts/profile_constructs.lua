local function createcases(basiccases, level)
  local binops = {
    {" and ", function (a,b) if not a then return a else return b end end},
    {" or ", function (a,b) if a then return a else return b end end},
  }

  local cases = {}
  cases[1] = basiccases

  local function createcases_internal(n)
    local res = {}
    for i = 1, n - 1 do
      for _, v1 in ipairs(cases[i]) do
        for _, v2 in ipairs(cases[n - i]) do
          for _, op in ipairs(binops) do
            local t = {
              "(" .. v1[1] .. op[1] .. v2[1] .. ")",
              op[2](v1[2], v2[2])
            }
            res[#res + 1] = t
            res[#res + 1] = {"not" .. t[1], not t[2]}
          end
        end
      end
    end
    return res
  end

  local build_start = os.clock()
  for i = 2, level do
    cases[i] = createcases_internal(i)
  end
  local build_time = os.clock() - build_start

  return cases, build_time
end

local basiccases = {
  {"true", true},
  {"false", false},
  {"1 < 2", true},
  {"1 > 2", false},
}

local skip_load = os.getenv("SKIP_LOAD") == "1"

local function run(level)
  local cases, build_time = createcases(basiccases, level)
  local prog = [[
    local k10 <const> = 10
    if %s then IX = true end
    return %s
  ]]
  local count = 0
  local eval_start = os.clock()
  for n = 1, level do
    for _, v in pairs(cases[n]) do
      if skip_load then
        count = count + 1
      else
        local s = v[1]
        local p = load(string.format(prog, s, s), "")
        IX = false
        assert(p() == v[2] and IX == not not v[2])
        count = count + 1
      end
    end
  end
  local eval_time = os.clock() - eval_start
  return count, build_time, eval_time
end

local level = tonumber(arg[1] or "4")
local count, build_time, eval_time = run(level)
print(string.format(
  "level=%d iterations=%d build_time=%.3fs eval_time=%.3fs skip_load=%s",
  level,
  count,
  build_time,
  eval_time,
  skip_load and "true" or "false"
))
