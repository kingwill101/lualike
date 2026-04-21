function love.conf(t)
  t.identity = "lualike_love_test_bed"
  t.appendidentity = true
  t.audio.mixwithsystem = true
  t.window.title = "LuaLike LOVE test bed"
  t.window.width = 1280
  t.window.height = 720
  t.window.vsync = 1
  t.window.msaa = 2
  t.window.resizable = true
  t.window.minwidth = 960
  t.window.minheight = 600
  t.window.highdpi = true
  t.modules.physics = false
end
