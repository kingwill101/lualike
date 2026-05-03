local helper = require "memory_profiles.memory_profile_helpers"

helper.run("weak_table_cleanup", function()
  local weak_keys = setmetatable({}, { __mode = "k" })
  local weak_values = setmetatable({}, { __mode = "v" })
  local weak_both = setmetatable({}, { __mode = "kv" })
  local anchors = {}

  for i = 1, 2600 do
    local key = { kind = "key", i = i }
    local value = { kind = "value", i = i, data = "weak-" .. i }
    weak_keys[key] = value
    weak_values[i] = value
    weak_both[key] = value
    anchors[i] = { key, value }
  end

  assert(helper.count_entries(weak_keys) == 2600)
  assert(helper.count_entries(weak_values) == 2600)
  assert(helper.count_entries(weak_both) == 2600)

  anchors = nil
  helper.full_collect("weak_table_cleanup:after-drop")

  assert(helper.count_entries(weak_keys) == 0)
  assert(helper.count_entries(weak_values) == 0)
  assert(helper.count_entries(weak_both) == 0)
end)
