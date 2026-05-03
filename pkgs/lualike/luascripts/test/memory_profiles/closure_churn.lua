local helper = require "memory_profiles.memory_profile_helpers"

helper.run("closure_churn", function()
  local checksum = 0

  for round = 1, 18 do
    local funcs = {}
    for i = 1, 320 do
      local captured = {
        base = i,
        round = round,
        payload = "closure-" .. round .. "-" .. i,
      }
      funcs[i] = function(delta)
        captured.base = captured.base + delta
        return captured.base + captured.round
      end
    end

    for i = 1, #funcs, 5 do
      checksum = checksum + funcs[i](round)
    end
    funcs = nil

    if round % 6 == 0 then
      collectgarbage("step")
    end
  end

  assert(checksum > 0)
end)
