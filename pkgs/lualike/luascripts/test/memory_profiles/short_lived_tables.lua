local helper = require "memory_profiles.memory_profile_helpers"

helper.run("short_lived_tables", function()
  local checksum = 0
  for round = 1, 28 do
    local batch = {}
    for i = 1, 420 do
      local row = {
        index = i,
        round = round,
        tag = "row-" .. round .. "-" .. i,
      }
      for j = 1, 10 do
        row[j] = i * j + round
      end
      batch[i] = row
    end

    for i = 1, #batch do
      checksum = checksum + batch[i][3]
    end
    batch = nil

    if round % 7 == 0 then
      collectgarbage("step")
    end
  end

  assert(checksum > 0)
end)
