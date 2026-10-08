-- main.lua: Orquestrador principal do HaxBall Local (loop de passo fixo, comandos determinísticos e HUD)
local config = require "src.config"
local game_mod = require "src.game"
local ui_mod = require "src.ui"
local input_mod = require "src.input"
local camera_mod = require "src.camera"
local calibration_mod = require "src.calibration"
local preferences = require "src.preferences"

local game_inst
local ui_inst
local calibration_inst

local accumulator = 0
local screen_scale = 1
local offset_x = 0
local offset_y = 0
local show_debug = true
local show_colliders = false
local last_dt = 0.016
local spin_keyboard_enabled = false
local mouse_just_pressed = false

function love.initialize_game(filesystem)
    config.camera.viewWidth = preferences.read_view_width(config, filesystem)
    game_inst = game_mod.new(config, config.default_mode, #config.players)
    ui_inst = ui_mod.new(config)
    calibration_inst = calibration_mod.new(config, game_inst)
    ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
    love.resize(love.graphics.getDimensions())
    return game_inst
end

function love.load(arg)
    pcall(function() io.stdout:setvbuf("no") end)

    -- Verificação do modo de testes (--test)
    if arg then
        for i = 1, #arg do
            if arg[i] == "--test" then
                local test_mod = require "tests.test_physics"
                local ok, all_passed = pcall(test_mod.run)
                if not ok then io.stderr:write("ERRO NO TESTE: ", tostring(all_passed), "\n") end
                all_passed = ok and all_passed == true
                io.flush()
                os.exit(all_passed and 0 or 1)
                return
            end
        end
    end

    spin_keyboard_enabled = (config.spin_selector and config.spin_selector.local_keyboard_enabled) or false

    -- Inicialização do jogo e interface
    love.initialize_game()
end

function love.resize(w, h)
    if not game_inst or not game_inst.field then return end
    local vw = config.viewport.width
    local vh = config.viewport.height
    local scale_x = w / vw
    local scale_y = h / vh
    screen_scale = math.min(scale_x, scale_y)
    offset_x = math.floor((w - vw * screen_scale) / 2)
    offset_y = math.floor((h - vh * screen_scale) / 2)
end

function love.update(dt)
    if not game_inst then return end
    last_dt = dt
    if calibration_inst and calibration_inst.open then
    local followed = game_inst.players[1]
    local alpha = accumulator / config.fixed_dt
    local px = followed.prev_x + (followed.x - followed.prev_x) * alpha
    local py = followed.prev_y + (followed.y - followed.prev_y) * alpha
    local bx = game_inst.ball.prev_x + (game_inst.ball.x - game_inst.ball.prev_x) * alpha
    local by = game_inst.ball.prev_y + (game_inst.ball.y - game_inst.ball.prev_y) * alpha
    camera_mod.update(game_inst.camera, px, py, bx, by, dt)
        return
    end

    -- 1. Captura e processamento do mouse no seletor de efeito (coordenadas virtuais)
    local win_mx, win_my = love.mouse.getPosition()
    local vmx = (win_mx - offset_x) / screen_scale
    local vmy = (win_my - offset_y) / screen_scale
    local is_mouse_down = love.mouse.isDown(1)

    local target_p = game_inst.possessor_player or (game_inst.players and game_inst.players[1])
    local vw = config.viewport.width
    local vh = config.viewport.height
    local r = (config.spin_selector and config.spin_selector.radius) or 40
    local widget_cx = vw - 60
    local widget_cy = vh - 60
    local btn_x = widget_cx - r - 16
    local btn_y = widget_cy + r * 0.4
    local btn_r = 10

    input_mod.handle_mouse_spin(target_p, vmx, vmy, is_mouse_down, mouse_just_pressed, widget_cx, widget_cy, r, btn_x, btn_y, btn_r)
    mouse_just_pressed = false

    -- 2. Atualização opcional de efeito pelo teclado
    local spd = (config.spin_selector and config.spin_selector.move_speed) or 2.0
    input_mod.update_keyboard_spin(target_p, dt, spd, spin_keyboard_enabled)

    -- 3. Acumulador de tempo fixo (1/60s)
    accumulator = accumulator + math.min(dt, config.max_dt_acc)

    local steps = 0
    while accumulator >= config.fixed_dt and steps < config.max_physics_steps do
        -- Polling dos comandos para cada jogador (separação estrita de simulação e input)
        for i = 1, #game_inst.players do
            input_mod.poll_player_command(game_inst.players[i], game_inst.commands[i])
        end

        -- Execução da simulação determinística
        game_inst:step_fixed(config.fixed_dt, game_inst.commands)

        accumulator = accumulator - config.fixed_dt
        steps = steps + 1
    end

    local followed = game_inst.players[1]
    local alpha = accumulator / config.fixed_dt
    local px = followed.prev_x + (followed.x - followed.prev_x) * alpha
    local py = followed.prev_y + (followed.y - followed.prev_y) * alpha
    local bx = game_inst.ball.prev_x + (game_inst.ball.x - game_inst.ball.prev_x) * alpha
    local by = game_inst.ball.prev_y + (game_inst.ball.y - game_inst.ball.prev_y) * alpha
    camera_mod.update(game_inst.camera, px, py, bx, by, dt)

    -- 4. Camada de apresentação: calcula linha de trajetória da posse e placar
    game_inst:update_presentation()
    ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
end

function love.draw()
    if not game_inst or not game_inst.field then return end
    local vw = config.viewport.width
    local vh = config.viewport.height

    -- Limpa fundo exterior
    love.graphics.clear(config.colors.clear)

    -- Renderização com escala proporcional e centralizada nas coordenadas virtuais
    love.graphics.push()
    love.graphics.setScissor(offset_x, offset_y, vw * screen_scale, vh * screen_scale)
    love.graphics.translate(offset_x, offset_y)
    love.graphics.scale(screen_scale, screen_scale)

    -- Enquadramento provisório: arena inteira, com a origem (0,0) no centro.
    love.graphics.push()
    love.graphics.translate(vw * 0.5, vh * 0.5)
    love.graphics.scale(vw / game_inst.camera.viewWidth)
    love.graphics.translate(-game_inst.camera.x, -game_inst.camera.y)
    game_inst:draw(show_colliders, accumulator / config.fixed_dt)
    love.graphics.pop()

    -- Desenha HUD, placar e seletor de efeito
    ui_inst:draw_hud(game_inst, config.colors, vw, vh)

    -- Overlay de debug (F3)
    ui_inst:draw_debug(last_dt, show_debug, game_inst)
    if config.camera.showBallArrow then
        local sc = vw / game_inst.camera.viewWidth
        local bx = vw * 0.5 + (game_inst.ball.x - game_inst.camera.x) * sc
        local by = vh * 0.5 + (game_inst.ball.y - game_inst.camera.y) * sc
        if bx < 12 or bx > vw - 12 or by < 12 or by > vh - 12 then
            local dx, dy = bx - vw * 0.5, by - vh * 0.5
            local factor = math.min((vw * 0.5 - 28) / math.max(math.abs(dx), 0.001),
                                    (vh * 0.5 - 28) / math.max(math.abs(dy), 0.001))
            ui_inst:draw_ball_arrow(vw * 0.5 + dx * factor, vh * 0.5 + dy * factor, dx, dy)
        end
    end
    if calibration_inst and calibration_inst.open then calibration_inst:draw(vw, vh) end
    love.graphics.setScissor()
    love.graphics.pop()
end

function love.mousepressed(x, y, button)
    if button == 1 then
        mouse_just_pressed = true
    end
end

function love.keypressed(key)
    if calibration_inst and calibration_inst.open then
        if key == "f5" then calibration_inst.open = false
        elseif key == "s" then calibration_inst:save()
        else calibration_inst:adjust(key) end
        return
    end
    if key == "f5" and game_inst and game_inst.is_training then calibration_inst.open = true; return end
    if key == "=" or key == "kp+" or key == "-" or key == "kp-" then
        local delta = (key == "=" or key == "kp+") and -config.camera.viewWidthStep or config.camera.viewWidthStep
        config.camera.viewWidth = math.max(config.camera.viewWidthMin,
            math.min(config.camera.viewWidthMax, game_inst.camera.viewWidth + delta))
        game_inst.camera.viewWidth = config.camera.viewWidth
        game_inst.camera.viewHeight = config.camera.viewWidth * config.viewport.height / config.viewport.width
        love.filesystem.write("view_width.txt", tostring(config.camera.viewWidth))
        if calibration_inst then calibration_inst.viewWidth = config.camera.viewWidth; calibration_inst:refresh() end
        return
    end
    if key == config.keys.quit then
        love.event.quit()
    elseif key == config.keys.reset then
        if game_inst then
            game_inst:reset_match()
            ui_inst:update_score(0, 0)
        end
    elseif key == config.keys.debug then
        show_debug = not show_debug
    elseif key == config.keys.fullscreen then
        love.window.setFullscreen(not love.window.getFullscreen())
        love.resize(love.graphics.getDimensions())
    elseif key == config.keys.debug_colliders then
        show_colliders = not show_colliders
    elseif key == config.keys.cycle_mode then
        if game_inst then
            local current_index = 1
            for i = 1, #config.mode_names do
                if config.mode_names[i] == game_inst.mode_name then current_index = i; break end
            end
            local next_index = current_index % #config.mode_names + 1
            game_inst:set_mode(config.mode_names[next_index], #config.players)
            calibration_inst:apply()
            love.resize(love.graphics.getDimensions())
            ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
        end
    elseif key == (config.spin_selector and config.spin_selector.reset_key) then
        -- Tecla de reset do efeito (padrão C)
        local target_p = game_inst and (game_inst.possessor_player or game_inst.players[1])
        if target_p then target_p:reset_spin() end
    end
end
