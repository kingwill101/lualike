local helper = require "memory_profiles.memory_profile_helpers"

helper.run("coroutine_churn", function()
  local checksum = 0

  for round = 1, 16 do
    local threads = {}
    for i = 1, 220 do
      threads[i] = coroutine.create(function()
        local payload = {
          round = round,
          index = i,
          text = "co-" .. round .. "-" .. i,
        }
        coroutine.yield(payload.index)
        return payload.round + payload.index
      end)
    end

    for i = 1, #threads do
      local ok, yielded = coroutine.resume(threads[i])
      assert(ok)
      checksum = checksum + yielded
      ok, yielded = coroutine.resume(threads[i])
      assert(ok)
      checksum = checksum + yielded
    end
    threads = nil

    if round % 4 == 0 then
      collectgarbage("step")
    end
  end

  assert(checksum > 0)
end)
