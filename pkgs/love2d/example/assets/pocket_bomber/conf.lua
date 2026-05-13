function love.conf(t)
    t.window.title = "Pocket Bomber"
    t.window.width = 960
    t.window.height = 540
    t.window.resizable = true
    t.version = "11.5"
    t.console = true

    -- Identity for save files
    t.identity = "pocket-bomber"

    -- Disable unused modules
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
    t.modules.thread = false
end
