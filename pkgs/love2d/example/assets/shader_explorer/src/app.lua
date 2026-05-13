local ShaderLoader = require("src.shader_loader")
local ShaderCatalog = require("src.shader_catalog")

local App = {
  index = 1,
  shaders = {},
  time = 0,
  paused = false,
  control = 0.5,
  showList = true,
  mouseX = 0,
  mouseY = 0,
  canvas = nil,
  fontSmall = nil,
  fontLarge = nil,
}

local compileShaderAt

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function sendIfPresent(shader, name, value)
  return pcall(function()
    shader:send(name, value)
  end)
end

local function currentSpec()
  return ShaderCatalog[App.index]
end

local function currentShaderBundle()
  local spec = currentSpec()
  return App.shaders[spec.id]
end

local function currentShaderUsesInputTexture()
  local spec = currentSpec()
  return spec ~= nil and spec.usesInputTexture == true
end

local function restartPlayback()
  App.time = 0
end

local function ensureCompiled(index)
  local spec = ShaderCatalog[index]
  if spec == nil then
    return
  end
  if App.shaders[spec.id] == nil then
    compileShaderAt(index)
  end
end

local function createOrResizeCanvas()
  local w, h = love.graphics.getDimensions()
  if App.canvas == nil then
    App.canvas = love.graphics.newCanvas(w, h)
    return
  end
  local cw, ch = App.canvas:getDimensions()
  if cw ~= w or ch ~= h then
    App.canvas = love.graphics.newCanvas(w, h)
  end
end

local function drawSceneToCanvas()
  if App.canvas == nil then
    return
  end
  local w, h = App.canvas:getDimensions()

  love.graphics.setCanvas(App.canvas)
  love.graphics.clear(0.04, 0.05, 0.1, 1)

  local t = App.time
  local stripes = 18
  for i = 1, stripes do
    local p = i / stripes
    local hue = (t * 0.1 + p * 0.35) % 1.0
    local r = 0.25 + 0.65 * math.sin(hue * math.pi * 2.0)
    local g = 0.25 + 0.65 * math.sin((hue + 0.33) * math.pi * 2.0)
    local b = 0.25 + 0.65 * math.sin((hue + 0.66) * math.pi * 2.0)
    love.graphics.setColor(r, g, b, 0.3)
    local y = (i - 1) * (h / stripes)
    love.graphics.rectangle("fill", 0, y, w, h / stripes + 1)
  end

  love.graphics.setColor(0.98, 0.98, 0.98, 0.9)
  for i = 0, 5 do
    local x = w * 0.1 + i * w * 0.16
    local y = h * (0.2 + 0.08 * math.sin(t + i * 0.7))
    love.graphics.circle("fill", x, y, 18 + i * 6)
  end

  love.graphics.setColor(0.0, 0.0, 0.0, 0.35)
  love.graphics.rectangle("fill", 28, h - 132, w - 56, 92, 14, 14)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setFont(App.fontLarge)
  love.graphics.print("Shader Explorer Input Layer", 42, h - 120)
  love.graphics.setFont(App.fontSmall)
  love.graphics.print("This canvas is fed to iChannel0/uTexture/tInput shaders.", 42, h - 86)

  love.graphics.setCanvas()
end

local function applyCommonUniforms(shader)
  local w, h = love.graphics.getDimensions()
  local mx, my = App.mouseX, App.mouseY

  sendIfPresent(shader, "iTime", App.time)
  sendIfPresent(shader, "time", App.time)

  sendIfPresent(shader, "iResolution", { w, h })
  sendIfPresent(shader, "resolution", { w, h })
  sendIfPresent(shader, "u_surfaceSize", { w, h })
  sendIfPresent(shader, "uSize", { w, h })

  sendIfPresent(shader, "iMouse", { mx, my })

  local hue = (App.time * 0.05) % 1.0
  local r = 0.5 + 0.5 * math.sin((hue + 0.00) * math.pi * 2.0)
  local g = 0.5 + 0.5 * math.sin((hue + 0.33) * math.pi * 2.0)
  local b = 0.5 + 0.5 * math.sin((hue + 0.66) * math.pi * 2.0)
  sendIfPresent(shader, "uColor", { r, g, b, 1.0 })

  local pixelX = 20 + App.control * 180
  local pixelY = 20 + App.control * 180
  sendIfPresent(shader, "uPixels", { pixelX, pixelY })

  sendIfPresent(shader, "delta", App.control)
  sendIfPresent(shader, "uAmount", App.control)
end

local function applyInputTextureUniforms(shader)
  if App.canvas == nil or not currentShaderUsesInputTexture() then
    return
  end
  sendIfPresent(shader, "iChannel0", App.canvas)
  sendIfPresent(shader, "uTexture", App.canvas)
  sendIfPresent(shader, "tInput", App.canvas)
end

local function drawCurrentShader()
  local bundle = currentShaderBundle()
  if bundle == nil or bundle.shader == nil then
    return
  end

  local spec = currentSpec()
  local shader = bundle.shader
  applyCommonUniforms(shader)
  applyInputTextureUniforms(shader)

  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
  love.graphics.setShader()
end

local function drawUi()
  local w, h = love.graphics.getDimensions()
  local spec = currentSpec()
  local bundle = currentShaderBundle()
  local playbackLabel
  if App.paused then
    playbackLabel = "Playback paused"
  else
    playbackLabel = string.format("Playback %.2fs", App.time)
  end

  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 16, 16, 520, 148, 14, 14)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setFont(App.fontLarge)
  love.graphics.print(string.format("%02d/%02d  %s", App.index, #ShaderCatalog, spec.title), 30, 28)
  love.graphics.setFont(App.fontSmall)
  love.graphics.print(spec.file .. "  |  " .. spec.note, 30, 62)
  love.graphics.print("Left/Right: switch  |  R: reload  |  Tab: list  |  Space: pause time", 30, 84)
  love.graphics.print(playbackLabel, 30, 106)
  love.graphics.print(string.format("Up/Down or Wheel: control %.2f", App.control), 30, 128)

  if bundle ~= nil and bundle.error ~= nil then
    love.graphics.setColor(0.55, 0.08, 0.08, 0.9)
    love.graphics.rectangle("fill", 16, h - 178, w - 32, 162, 10, 10)
    love.graphics.setColor(1, 0.84, 0.84, 1)
    love.graphics.setFont(App.fontSmall)
    love.graphics.printf(bundle.error, 30, h - 162, w - 56)
  end

  if App.showList then
    local listW = 360
    local listH = h - 32
    local x = w - listW - 16
    local y = 16
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", x, y, listW, listH, 14, 14)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(App.fontLarge)
    love.graphics.print("Shader List", x + 16, y + 12)
    love.graphics.setFont(App.fontSmall)

    local rowY = y + 50
    for i, item in ipairs(ShaderCatalog) do
      if i == App.index then
        love.graphics.setColor(0.2, 0.35, 0.75, 0.9)
        love.graphics.rectangle("fill", x + 10, rowY - 2, listW - 20, 24, 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
      else
        love.graphics.setColor(0.87, 0.87, 0.9, 1)
      end
      local label = string.format("%02d  %s", i, item.title)
      love.graphics.print(label, x + 18, rowY)
      rowY = rowY + 26
      if rowY > y + listH - 28 then
        break
      end
    end
  end
end

compileShaderAt = function(index)
  local spec = ShaderCatalog[index]
  if spec == nil then
    return
  end
  local loaded, err = ShaderLoader.load(spec.file)
  if loaded == nil then
    App.shaders[spec.id] = {
      shader = nil,
      error = err,
    }
    return
  end
  App.shaders[spec.id] = {
    shader = loaded.shader,
    sourcePath = loaded.sourcePath,
    error = nil,
  }
end

local function switchBy(delta)
  local count = #ShaderCatalog
  local nextIndex = ((App.index - 1 + delta) % count) + 1
  App.index = nextIndex
  restartPlayback()
  ensureCompiled(App.index)
end

function App.load()
  App.fontSmall = love.graphics.newFont(13)
  App.fontLarge = love.graphics.newFont(22)
  ensureCompiled(App.index)
  if currentShaderUsesInputTexture() then
    createOrResizeCanvas()
  end

  local w, h = love.graphics.getDimensions()
  App.mouseX, App.mouseY = w * 0.5, h * 0.5
end

function App.update(dt)
  if dt > 0.1 then
    dt = 0.1
  end
  if not App.paused then
    App.time = App.time + dt
  end
  if currentShaderUsesInputTexture() then
    createOrResizeCanvas()
    drawSceneToCanvas()
  end
end

function App.draw()
  drawCurrentShader()
  drawUi()
end

function App.keypressed(key)
  if key == "left" or key == "a" then
    switchBy(-1)
  elseif key == "right" or key == "d" then
    switchBy(1)
  elseif key == "up" or key == "w" then
    App.control = clamp(App.control + 0.05, 0.0, 1.0)
  elseif key == "down" or key == "s" then
    App.control = clamp(App.control - 0.05, 0.0, 1.0)
  elseif key == "space" then
    App.paused = not App.paused
  elseif key == "tab" then
    App.showList = not App.showList
  elseif key == "r" then
    restartPlayback()
    compileShaderAt(App.index)
  elseif key == "escape" then
    love.event.quit()
  end
end

function App.mousemoved(x, y)
  App.mouseX = x
  App.mouseY = y
end

function App.wheelmoved(_, y)
  App.control = clamp(App.control + y * 0.03, 0.0, 1.0)
end

function App.resize()
  if currentShaderUsesInputTexture() then
    createOrResizeCanvas()
  end
end

return App
