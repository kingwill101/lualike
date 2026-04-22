function love.conf(t)
  t.identity = "lualike_love_shader_explorer"
  t.appendidentity = true
  t.audio.mixwithsystem = true
  t.window.title = "LOVE Shader Explorer"
  t.window.width = 1280
  t.window.height = 720
  t.window.vsync = 1
  t.window.msaa = 0
  t.window.resizable = true
  t.window.minwidth = 900
  t.window.minheight = 560
  t.window.highdpi = true
  t.modules.physics = false
end
