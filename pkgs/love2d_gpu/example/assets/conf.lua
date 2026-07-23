function love.conf(t)
  t.identity = "love2d_gpu_demo"
  t.window.title = "love2d_gpu demo"
  t.window.width = 800
  t.window.height = 600
  t.window.vsync = 1
  t.window.resizable = true
  t.window.highdpi = true
  t.modules.physics = false
  t.modules.joystick = false
  t.modules.audio = false
end
