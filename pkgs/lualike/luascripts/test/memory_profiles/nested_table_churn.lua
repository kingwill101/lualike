local helper = require "memory_profiles.memory_profile_helpers"

helper.run("nested_table_churn", function()
  local checksum = 0

  for round = 1, 18 do
    local roots = {}
    for i = 1, 180 do
      local leaf = { value = i + round }
      local mid = { leaf = leaf, index = i }
      roots[i] = {
        mid = mid,
        payload = {
          round,
          i,
          round * i,
          "payload-" .. round .. "-" .. i,
        },
      }
    end

    for i = 1, #roots do
      checksum = checksum + roots[i].mid.leaf.value
    end
    roots = nil

    if round % 3 == 0 then
      collectgarbage("step")
    end
  end

  assert(checksum > 0)
end)
