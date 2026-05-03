local helper = require "memory_profiles.memory_profile_helpers"

helper.run("register_write_churn", function()
  local anchors = {}
  for i = 1, 650 do
    anchors[i] = { stable = i }
  end

  helper.full_collect("register_write_churn:aged-anchors")

  local checksum = 0
  for round = 1, 24 do
    for i = 1, #anchors do
      local value = { round = round, index = i, sum = round + i }
      anchors[i].current = value
      checksum = checksum + anchors[i].current.sum
      anchors[i].current = nil
    end

    if round % 10 == 0 then
      collectgarbage("step")
    end
  end

  anchors = nil
  assert(checksum > 0)
end)
