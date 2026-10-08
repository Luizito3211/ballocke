-- conf.lua: Configurações de inicialização e otimização do LÖVE2D
function love.conf(t)
    t.identity = "haxball_local"
    t.version = "11.5"

    t.window.title = "HaxBall Local"
    t.window.icon = nil
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 360
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.window.highdpi = false

    -- Desativação obrigatória de módulos não utilizados para máxima performance e baixo consumo de RAM
    t.modules.physics = false   -- Usamos motor físico procedural próprio (sem Box2D)
    t.modules.joystick = false  -- Fase 1 focada em teclado
    t.modules.touch = false     -- Não usado em desktop
    t.modules.video = false     -- Sem vídeos
    t.modules.thread = false    -- Sem multi-threading
    t.modules.audio = false     -- Áudio desativado na Fase 1 (gráficos e física puros)
    t.modules.sound = false
end
