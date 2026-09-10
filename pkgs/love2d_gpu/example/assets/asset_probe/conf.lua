function love.conf(t)
  t.identity = "love2d_gpu_asset_probe"
  t.window.title = "LOVE asset parity probe"
  t.window.width = 800
  t.window.height = 600
  t.window.vsync = 1
  t.window.resizable = false
  t.window.highdpi = true
  t.modules.audio = false
  t.modules.joystick = false
  t.modules.physics = false
end
