local M = {}

local function can_mark()
  return type(dart_mark) == "function"
end

function M.mark(label)
  if can_mark() then
    dart_mark(label)
  end
end

function M.full_collect(label)
  M.mark(label .. ":collect:start")
  collectgarbage("collect")
  collectgarbage("collect")
  collectgarbage("collect")
  M.mark(label .. ":collect:end")
end

function M.count_entries(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

function M.run(label, body)
  print("[memory_profile] " .. label .. " start")
  M.full_collect(label .. ":baseline")
  local before_kb = collectgarbage("count")

  M.mark(label .. ":alloc:start")
  local result = body()
  M.mark(label .. ":alloc:end")

  local peak_kb = collectgarbage("count")
  result = nil
  M.full_collect(label .. ":cleanup")
  local after_kb = collectgarbage("count")

  print(string.format(
    "[memory_profile] %s before=%.1fKB peak=%.1fKB after=%.1fKB delta=%.1fKB",
    label,
    before_kb,
    peak_kb,
    after_kb,
    after_kb - before_kb
  ))
end

return M
