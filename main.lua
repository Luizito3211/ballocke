-- main.lua: Orquestrador principal do HaxBall Local (loop de passo fixo, comandos determinísticos e HUD)
local config = require "src.config"
local game_mod = require "src.game"
local ui_mod = require "src.ui"
local input_mod = require "src.input"

local game_inst
local ui_inst

local accumulator = 0
local scale = 1
local offset_x = 0
local offset_y = 0
local show_debug = true
local last_dt = 0.016
local spin_keyboard_enabled = false
local mouse_just_pressed = false

function love.load(arg)
    pcall(function() io.stdout:setvbuf("no") end)

    -- Verificação do modo de testes (--test)
    if arg then
        for i = 1, #arg do
            if arg[i] == "--test" then
                local test_mod = require "tests.test_physics"
                local all_passed = test_mod.run()
                io.flush()
                os.exit(all_passed and 0 or 1)
                return
            end
        end
    end

    spin_keyboard_enabled = (config.spin_selector and config.spin_selector.local_keyboard_enabled) or false

    -- Inicialização do jogo e interface
    game_inst = game_mod.new(config, config.default_preset, #config.players)
    ui_inst = ui_mod.new(config)
    ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)

    love.resize(love.graphics.getDimensions())
end

function love.resize(w, h)
    if not game_inst or not game_inst.current_preset then return end
    local vw = game_inst.current_preset.virtual_width
    local vh = game_inst.current_preset.virtual_height
    local scale_x = w / vw
    local scale_y = h / vh
    scale = math.min(scale_x, scale_y)
    offset_x = math.floor((w - vw * scale) / 2)
    offset_y = math.floor((h - vh * scale) / 2)
end

function love.update(dt)
    if not game_inst then return end
    last_dt = dt

    -- 1. Captura e processamento do mouse no seletor de efeito (coordenadas virtuais)
    local win_mx, win_my = love.mouse.getPosition()
    local vmx = (win_mx - offset_x) / scale
    local vmy = (win_my - offset_y) / scale
    local is_mouse_down = love.mouse.isDown(1)

    local target_p = game_inst.possessor_player or (game_inst.players and game_inst.players[1])
    local vw = game_inst.current_preset.virtual_width
    local vh = game_inst.current_preset.virtual_height
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

    -- 4. Camada de apresentação: calcula linha de trajetória da posse e placar
    game_inst:update_presentation()
    ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
end

function love.draw()
    if not game_inst or not game_inst.current_preset then return end
    local vw = game_inst.current_preset.virtual_width
    local vh = game_inst.current_preset.virtual_height

    -- Limpa fundo exterior
    love.graphics.clear(config.colors.clear)

    -- Renderização com escala proporcional e centralizada nas coordenadas virtuais
    love.graphics.push()
    love.graphics.translate(offset_x, offset_y)
    love.graphics.scale(scale, scale)

    love.graphics.setScissor(offset_x, offset_y, vw * scale, vh * scale)

    -- Desenha campo, traves, jogadores, linha de trajetória e bola
    game_inst:draw()

    -- Desenha HUD, placar e seletor de efeito
    ui_inst:draw_hud(game_inst, config.colors, vw, vh)

    love.graphics.setScissor()
    love.graphics.pop()

    -- Overlay de debug (F3)
    ui_inst:draw_debug(last_dt, show_debug, game_inst)
end

function love.mousepressed(x, y, button)
    if button == 1 then
        mouse_just_pressed = true
    end
end

function love.keypressed(key)
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
    elseif key == config.keys.cycle_preset then
        if game_inst then
            local current = game_inst.preset_name
            local next_p = "1v1"
            if current == "1v1" then next_p = "2v2"
            elseif current == "2v2" then next_p = "3v3"
            else next_p = "1v1" end

            game_inst:set_preset(next_p, #config.players)
            love.resize(love.graphics.getDimensions())
            ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
        end
    elseif key == (config.spin_selector and config.spin_selector.reset_key) then
        -- Tecla de reset do efeito (padrão C)
        local target_p = game_inst and (game_inst.possessor_player or game_inst.players[1])
        if target_p then target_p:reset_spin() end
    elseif key == config.keys.toggle_spin_keyboard then
        spin_keyboard_enabled = not spin_keyboard_enabled
    end
end
