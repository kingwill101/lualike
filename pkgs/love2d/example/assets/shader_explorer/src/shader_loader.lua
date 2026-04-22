local ShaderLoader = {}

local shaderAssetRoots = {
  "shaders",
  "assets/shader_explorer/shaders",
}

local function flutterAssetKeyFor(filename)
  return string.format("assets/shader_explorer/shaders/%s", filename)
end

local function readShaderText(filename)
  for _, root in ipairs(shaderAssetRoots) do
    local path = string.format("%s/%s", root, filename)
    local data = love.filesystem.read(path)
    if data ~= nil then
      return data, path
    end
  end

  return nil, nil
end

function ShaderLoader.load(filename)
  local raw, sourcePath = readShaderText(filename)
  if raw == nil then
    return nil, string.format("Shader source not found for '%s'", filename)
  end

  local compiled, shaderOrError = pcall(function()
    return love.graphics._newRegisteredFragmentShader(
      flutterAssetKeyFor(filename),
      raw
    )
  end)

  if not compiled then
    local errorMessage = string.format("Failed to compile %s\n%s", sourcePath, tostring(shaderOrError))
    return nil, errorMessage
  end

  return {
    shader = shaderOrError,
    sourcePath = sourcePath,
  }, nil
end

return ShaderLoader
