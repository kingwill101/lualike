local PathUtils = {}

local function isAbsolute(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function normalize(path)
  local raw = path:gsub("\\", "/")
  local prefix = ""
  if raw:sub(1, 1) == "/" then
    prefix = "/"
  elseif raw:match("^%a:/") then
    prefix = raw:sub(1, 3)
    raw = raw:sub(4)
  end

  local parts = {}
  for segment in raw:gmatch("[^/]+") do
    if segment == ".." then
      if #parts > 0 and parts[#parts] ~= ".." then
        table.remove(parts)
      elseif prefix == "" then
        parts[#parts + 1] = segment
      end
    elseif segment ~= "." and segment ~= "" then
      parts[#parts + 1] = segment
    end
  end

  local joined = table.concat(parts, "/")
  if prefix ~= "" then
    if joined == "" then
      return prefix
    end
    if prefix:sub(-1) == "/" then
      return prefix .. joined
    end
    return prefix .. "/" .. joined
  end
  if joined == "" then
    return "."
  end
  return joined
end

function PathUtils.join(a, b)
  if b == nil or b == "" then
    return normalize(a)
  end
  if isAbsolute(b) then
    return normalize(b)
  end
  return normalize(a .. "/" .. b)
end

return PathUtils
