-- main.lua: Orquestrador principal do HaxBall Local (loop de passo fixo, comandos determinísticos e HUD)
local config = require "src.config"
local game_mod = require "src.game"
local ui_mod = require "src.ui"
local input_mod = require "src.input"
local camera_mod = require "src.camera"
local calibration_mod = require "src.calibration"
local preferences = require "src.preferences"
local referee_mod = require "src.referee"
local EventLog = require "src.event_log"
local net_lobby = require "net.lobby"
local net_session_mod = require "net.session"
local connection_test_mod = require "net.connection_test"
local menu_mod = require "src.menu"

local game_inst
local ui_inst
local calibration_inst
local referee_panel_open = false
local referee_test_touch = 1
local event_log
local network_session
local app_screen = "menu"
local network_error = ""
local menu_state = menu_mod.new()
local room_browser
local connection_test
local show_ping = false
local network_command = { moveX = 0, moveY = 0, kick = false, spinX = 0, spinY = 0 }

local accumulator = 0
local screen_scale = 1
local offset_x = 0
local offset_y = 0
local show_debug = true
local show_colliders = false
local last_dt = 0.016
local spin_keyboard_enabled = false
local mouse_just_pressed = false

local function set_short_restarts(r, enabled)
    r.testShortRestarts = enabled
    if referee_mod.is_restart_state(r.state) then
        r.restartRemaining = enabled and config.referee.testRestartTimeout or config.referee.restartTimeouts[r.restartType]
    end
end

local function set_test_half(r, one_minute)
    r.testOneMinute = one_minute
    r.halfDuration = one_minute and config.game.testHalfDuration or config.game.halfDuration
    r.halfRemaining = r.halfDuration
    r.regulationExpired, r.graceRemaining = false, config.referee.regulationGrace
end

function love.initialize_game(filesystem, num_players, game_config, no_event_log)
    local active_config = game_config or config
    config.camera.viewWidth = preferences.read_view_width(config, filesystem)
    local mode = num_players == 1 and "1v1" or (num_players == 10 and "5v5" or active_config.default_mode)
    local requested_players = num_players or 2
    game_inst = game_mod.new(active_config, mode, requested_players)
    game_inst.is_training = true
    ui_inst = ui_mod.new(active_config)
    calibration_inst = calibration_mod.new(active_config, game_inst)
    ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
    ui_inst:update_referee(game_inst.referee)
    if filesystem == nil and not no_event_log then
        event_log = EventLog.new(love.filesystem, active_config.eventLog)
        referee_mod.attach_event_log(game_inst.referee, event_log)
    end
    love.resize(love.graphics.getDimensions())
    return game_inst
end

function love.start_host(port)
    if room_browser then room_browser:close(); room_browser = nil end
    if connection_test then connection_test:close(); connection_test = nil end
    port = tonumber(port) or config.network.defaultPort
    local room, err = net_lobby.host(port, "Sala RS", config.network.discoveryPort)
    if not room then network_error, app_screen = err, "menu"; return false end
    love.initialize_game(nil, 1, nil, true)
    game_inst:set_mode("2v2", 1)
    game_inst.is_training = false
    calibration_inst.presentationOnly = true
    calibration_inst:apply()
    calibration_inst:refresh()
    event_log = EventLog.new(love.filesystem, config.eventLog)
    referee_mod.attach_event_log(game_inst.referee, event_log)
    network_session = net_session_mod.new_host(room, game_inst, config)
    network_session.localCommand = network_command
    app_screen, network_error = "host", ""
    ui_inst:update_referee(game_inst.referee)
    return true
end

function love.start_join(address)
    if room_browser then room_browser:close(); room_browser = nil end
    if connection_test then connection_test:close(); connection_test = nil end
    local room, err = net_lobby.join(address)
    if not room then network_error, app_screen = err, "menu"; return false end
    love.initialize_game(nil, 10, nil, true)
    game_inst.is_training = false
    network_session = net_session_mod.new_client(room, game_inst, config)
    network_session.localCommand = network_command
    app_screen, network_error = "client", ""
    return true
end

local function enter_menu(screen)
    if room_browser then room_browser:close(); room_browser = nil end
    if connection_test then connection_test:close(); connection_test = nil end
    menu_state.screen, menu_state.input, menu_state.error = screen or "home", false, ""
    app_screen = "menu"
    if menu_state.screen == "join" then
        room_browser, network_error = net_lobby.browser(config.network.discoveryPort)
        if not room_browser then menu_state.screen = "home" end
    end
end

local function launch_connection_test()
    local address = menu_state.address
    local ip, port_text = address:match("^([%d%.]+):(%d+)$")
    if not ip then ip, port_text = address, tostring(config.network.connectionTestPort) end
    if not require("net.discovery").valid_address(ip .. ":" .. port_text) then
        network_error = "Digite um IPv4 válido do receptor."
        return
    end
    connection_test, network_error = connection_test_mod.client(ip, tonumber(port_text), config.network)
end

local function menu_keypressed(key)
    if menu_state.screen == "home" then
        if key == "up" then menu_state.selection = math.max(1, menu_state.selection - 1)
        elseif key == "down" then menu_state.selection = math.min(4, menu_state.selection + 1)
        elseif key == "return" or key == "kpenter" then
            if menu_state.selection == 1 then love.start_host(config.network.defaultPort)
            elseif menu_state.selection == 2 then enter_menu("join")
            elseif menu_state.selection == 3 then menu_state.screen = "connection"
            else love.event.quit() end
        elseif key == "escape" then love.event.quit() end
    elseif menu_state.screen == "join" then
        local rooms = room_browser and room_browser.rooms or {}
        if menu_state.input then
            if key == "escape" then menu_state.input = false
            elseif key == "backspace" then menu_state.address = menu_state.address:sub(1, -2)
            elseif key == "return" or key == "kpenter" then
                local address = menu_state.address
                if address == "" and rooms[menu_state.room_index] then address = rooms[menu_state.room_index].address end
                if address ~= "" then love.start_join(address) end
            end
        elseif key == "escape" then enter_menu("home")
        elseif key == "m" then menu_state.input, menu_state.address = true, ""
        elseif key == "up" then menu_state.room_index = math.max(1, menu_state.room_index - 1)
        elseif key == "down" then menu_state.room_index = math.min(math.max(1, #rooms), menu_state.room_index + 1)
        elseif key == "return" or key == "kpenter" then
            if rooms[menu_state.room_index] then love.start_join(rooms[menu_state.room_index].address) end
        end
    elseif menu_state.screen == "connection" then
        if menu_state.input then
            if key == "escape" then menu_state.input = false
            elseif key == "backspace" then menu_state.address = menu_state.address:sub(1, -2)
            elseif key == "return" or key == "kpenter" then launch_connection_test() end
        elseif key == "escape" then enter_menu("home")
        elseif key == "r" then
            if connection_test then connection_test:close() end
            connection_test, network_error = connection_test_mod.receiver(config.network.connectionTestPort, config.network)
            menu_state.addresses = require("net.discovery").local_ipv4_addresses(config.network.connectionTestPort)
        elseif key == "m" then menu_state.input, menu_state.address = true, ""
        elseif key == "c" then menu_state.input = true end
    end
end

-- Harness usado somente por --test para renderizar overlays sem alterar o jogo normal.
function love.configure_smoke_overlays(enabled)
    if enabled then app_screen = "host" end
    show_debug = enabled
    show_colliders = enabled
    if calibration_inst then calibration_inst.open = enabled end
    referee_panel_open = enabled
end

function love.load(arg, unfiltered_arg)
    pcall(function() io.stdout:setvbuf("no") end)
    -- Verificação do modo de testes (--test)
    if arg or unfiltered_arg or _G.arg then
        for _, arguments in ipairs({ arg or {}, unfiltered_arg or {}, _G.arg or {} }) do
        for i = 1, #arguments do
            if arguments[i] == "--test" then
                local test_mod = require "tests.test_physics"
                local ok, all_passed = xpcall(test_mod.run, debug.traceback)
                if not ok then io.stderr:write("ERRO NO TESTE:\n", tostring(all_passed), "\n") end
                all_passed = ok and all_passed == true
                io.flush()
                os.exit(all_passed and 0 or 1)
                return
            end
        end
        end
    end

    spin_keyboard_enabled = (config.spin_selector and config.spin_selector.local_keyboard_enabled) or false
    menu_state.port = config.network.connectionTestPort

    -- Inicialização do jogo e interface
    local arguments = arg or unfiltered_arg or _G.arg or {}
    for i = 1, #arguments do
        if arguments[i] == "--host" then love.start_host(arguments[i + 1] or config.network.defaultPort); return end
        if arguments[i] == "--join" then love.start_join(arguments[i + 1] or ""); return end
    end
    app_screen = "menu"
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
    if app_screen == "menu" then
        if room_browser then room_browser:update(dt) end
        if connection_test then connection_test:update(dt) end
        return
    end
    if not game_inst then return end
    if event_log then event_log:update(dt) end
    last_dt = dt
    if referee_panel_open then return end

    local target_index = network_session and network_session.role == "client" and network_session.localPlayerIndex > 0 and
        network_session.localPlayerIndex or 1
    local target_p = game_inst.players and game_inst.players[target_index]
    game_inst.local_player_index = network_session and network_session.role == "client" and
        network_session.localPlayerIndex or 1
    if network_session and network_session.role == "client" and target_p then target_p.allow_spin = true end
    if network_session and network_session.role == "host" then network_session:update(dt) end
    if network_session and network_session.role == "client" and network_session.failed then
        network_error = network_session.message
        network_session:close()
        network_session = nil
        enter_menu("home")
        return
    end

    if calibration_inst and calibration_inst.open and not network_session then
        local alpha = accumulator / config.fixed_dt
        local px = target_p and (target_p.prev_x + (target_p.x - target_p.prev_x) * alpha) or game_inst.ball.x
        local py = target_p and (target_p.prev_y + (target_p.y - target_p.prev_y) * alpha) or game_inst.ball.y
        local bx = game_inst.ball.prev_x + (game_inst.ball.x - game_inst.ball.prev_x) * alpha
        local by = game_inst.ball.prev_y + (game_inst.ball.y - game_inst.ball.prev_y) * alpha
        camera_mod.update(game_inst.camera, px, py, bx, by, dt)
        return
    end

    local win_mx, win_my = love.mouse.getPosition()
    local vmx = (win_mx - offset_x) / screen_scale
    local vmy = (win_my - offset_y) / screen_scale
    local is_mouse_down = love.mouse.isDown(1)
    local vw, vh = config.viewport.width, config.viewport.height
    local r = config.spin_selector.radius
    local widget_cx, widget_cy = vw - 60, vh - 60
    local btn_x, btn_y, btn_r = widget_cx - r - 16, widget_cy + r * 0.4, 10
    input_mod.handle_mouse_spin(target_p, vmx, vmy, is_mouse_down, mouse_just_pressed,
        widget_cx, widget_cy, r, btn_x, btn_y, btn_r)
    mouse_just_pressed = false

    input_mod.update_keyboard_spin(target_p, dt, config.spin_selector.move_speed, spin_keyboard_enabled)
    if network_session and network_session.role == "client" then
        local mx, my, kick = input_mod.get_movement_and_kick(config.players[1].keys)
        if network_session.teamMenuOpen then mx, my, kick = 0, 0, false end
        network_command.moveX, network_command.moveY, network_command.kick = mx, my, kick
        network_command.spinX, network_command.spinY = target_p.spin_x, target_p.spin_y
        network_session:update(dt, network_command)
        network_session:apply_snapshot()
        accumulator = 0
    else
        accumulator = accumulator + math.min(dt, config.max_dt_acc)
        local steps = 0
        while accumulator >= config.fixed_dt and steps < config.max_physics_steps do
            input_mod.poll_player_command(game_inst.players[1], game_inst.commands[1])
            if network_session and network_session.localTeamMenuOpen then
                local command = game_inst.commands[1]
                command.moveX, command.moveY, command.kick, command.spinX, command.spinY = 0, 0, false, 0, 0
            end
            if network_session then network_session:apply_host_inputs() end
            game_inst:step_fixed(config.fixed_dt, game_inst.commands)
            if network_session then network_session:after_host_tick() end
            accumulator = accumulator - config.fixed_dt
            steps = steps + 1
        end
    end

    local follow_index = network_session and network_session.role == "client" and network_session.localPlayerIndex or 1
    local followed = follow_index > 0 and game_inst.players[follow_index] or nil
    local alpha = accumulator / config.fixed_dt
    local px = followed and (followed.prev_x + (followed.x - followed.prev_x) * alpha) or game_inst.ball.x
    local py = followed and (followed.prev_y + (followed.y - followed.prev_y) * alpha) or game_inst.ball.y
    local bx = game_inst.ball.prev_x + (game_inst.ball.x - game_inst.ball.prev_x) * alpha
    local by = game_inst.ball.prev_y + (game_inst.ball.y - game_inst.ball.prev_y) * alpha
    camera_mod.update(game_inst.camera, px, py, bx, by, dt)

    if not network_session or network_session.role == "host" then game_inst:update_presentation() end
    ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
    ui_inst:update_referee(game_inst.referee)
end

function love.quit()
    if network_session then network_session:close() end
    if event_log then event_log:flush() end
end

function love.draw()
    if app_screen == "menu" then
        menu_mod.draw(menu_state, room_browser and room_browser.discovery, connection_test, network_error)
        return
    end
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
    ui_inst:draw_referee(vw, vh)

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
            local tint
            if game_inst.referee.ballFrozen and referee_mod.is_restart_state(game_inst.referee.state) then
                tint = game_inst.referee.restartTeam == "red" and config.colors.score_p1 or config.colors.score_p2
            end
            ui_inst:draw_ball_arrow(vw * 0.5 + dx * factor, vh * 0.5 + dy * factor, dx, dy, tint)
        end
    end
    if calibration_inst and calibration_inst.open then calibration_inst:draw(vw, vh) end
    if referee_panel_open then ui_inst:draw_test_panel(vw, vh) end
    if network_session and network_session.role == "host" then
        love.graphics.setFont(ui_inst.font_ref)
        love.graphics.setColor(1, 0.95, 0.65, 1)
        love.graphics.printf("SALA RS  |  " .. tostring(network_session.room.port) .. "  |  MODO " .. game_inst.mode_name,
            30, 158, vw - 60, "center")
        for i = 1, #network_session.room.addresses do
            love.graphics.printf(network_session.room.addresses[i] .. ":" .. tostring(network_session.room.port),
                30, 184 + (i - 1) * 24, vw - 60, "center")
        end
        love.graphics.printf(network_session.message, 30, 184 + #network_session.room.addresses * 24,
            vw - 60, "center")
        love.graphics.setFont(ui_inst.font_hud)
    elseif network_session and network_session.role == "client" and not network_session.hasSnapshot then
        love.graphics.setColor(1, 0.95, 0.65, 1)
        love.graphics.printf(network_session.message, 60, 160, vw - 120, "center")
    end
    if network_session and ((network_session.role == "host" and network_session.localTeamMenuOpen) or
       (network_session.role == "client" and network_session.teamMenuOpen)) then
        love.graphics.setColor(0, 0, 0, 0.82)
        love.graphics.rectangle("fill", 220, vh * 0.36, vw - 440, 126, 10, 10)
        love.graphics.setColor(1, 0.9, 0.38, 1)
        love.graphics.setFont(ui_inst.font_ref)
        love.graphics.printf("ESCOLHA SEU TIME", 230, vh * 0.39, vw - 460, "center")
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(ui_inst.font_hud)
        love.graphics.printf("1 — Vermelho     2 — Azul     3 — Espectador", 230, vh * 0.48, vw - 460, "center")
        love.graphics.printf("Seu jogador fica parado até confirmar", 230, vh * 0.54, vw - 460, "center")
    end
    if network_session then
        love.graphics.setColor(0.8, 0.85, 0.9, 0.7)
        love.graphics.printf("TAB: ping  •  F2: modo (host)  •  1/2/3: time/espectador", 12, vh - 26, vw - 24, "center")
    end
    if show_ping and network_session then
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", vw - 330, 36, 310, math.max(55, #network_session:ping_rows() * 22 + 16), 6, 6)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(ui_inst.font_hud)
        local rows = network_session:ping_rows()
        for i = 1, #rows do love.graphics.print(rows[i], vw - 318, 44 + (i - 1) * 22) end
    end
    love.graphics.setScissor()
    love.graphics.pop()
end

function love.mousepressed(x, y, button)
    if button == 1 then
        mouse_just_pressed = true
    end
end

function love.keypressed(key)
    if app_screen == "menu" then menu_keypressed(key); return end
    if referee_panel_open then
        local r = game_inst.referee
        if key == "f6" or key == "escape" then referee_panel_open = false
        elseif key == "up" then ui_inst.test_selection = math.max(1, ui_inst.test_selection - 1)
        elseif key == "down" then ui_inst.test_selection = math.min(#ui_inst.test_rows, ui_inst.test_selection + 1)
        elseif (key == "left" or key == "right") and ui_inst.test_selection == 5 then
            referee_test_touch = referee_test_touch + (key == "right" and 1 or -1)
            if referee_test_touch < 1 then referee_test_touch = 3 elseif referee_test_touch > 3 then referee_test_touch = 1 end
            ui_inst:refresh_test_panel(r.testShortRestarts, r.testOneMinute, referee_test_touch)
        elseif key == "left" or key == "right" then
            local direction = key == "right"
            if ui_inst.test_selection == 6 then set_short_restarts(r, direction)
            elseif ui_inst.test_selection == 7 then
                set_test_half(r, direction)
            end
            ui_inst:refresh_test_panel(r.testShortRestarts, r.testOneMinute, referee_test_touch)
        elseif key == "f7" then
            local p, b, f = game_inst.players[1], game_inst.ball, game_inst.field
            p.x = math.max(f.outer_left + p.radius,
                math.min(f.outer_right - p.radius, b.x - p.radius - b.radius - config.testPanel.playerBallGap))
            p.y = math.max(f.outer_top + p.radius,
                math.min(f.outer_bottom - p.radius, b.y))
            p.prev_x, p.prev_y, p.vx, p.vy = p.x, p.y, 0, 0
            referee_mod.record_reposition(r, "jogadores", "reposicionamento manual F7")
        elseif key == "return" or key == "kpenter" then
            local row = ui_inst.test_selection
            if row >= 1 and row <= 4 then
                local f, b = game_inst.field, game_inst.ball
                if r.lastTouchTeam then r.lastTouchTeam = nil end
                local old_state = r.state
                r.state, r.restartKickerId, r.noRetouch = referee_mod.STATE_PLAY, nil, false
                referee_mod.record_state_change(r, old_state, r.state, "estado alterado para teste manual F6")
                if referee_test_touch == 2 then r.lastTouchTeam = "red"
                elseif referee_test_touch == 3 then r.lastTouchTeam = "blue" end
                local o = config.testPanel.outOffset
                if row == config.testPanel.lateralTop then b.x, b.y = 0, f.top - b.radius - o
                elseif row == config.testPanel.lateralBottom then b.x, b.y = 0, f.bottom + b.radius + o
                elseif row == config.testPanel.endLeft then b.x, b.y = f.left - b.radius - o, -(config.field.goal_mouth_width / 2 + config.field.post_radius + b.radius + o)
                else b.x, b.y = f.right + b.radius + o, -(config.field.goal_mouth_width / 2 + config.field.post_radius + b.radius + o) end
                b.prev_x, b.prev_y, b.vx, b.vy = b.x, b.y, 0, 0
                referee_mod.record_reposition(r, "bola", "teleporte manual pelo painel F6")
                r.ballFrozen = false
                referee_panel_open = false
            elseif row == 6 then set_short_restarts(r, not r.testShortRestarts)
            elseif row == 7 then set_test_half(r, not r.testOneMinute)
            elseif row == 8 then referee_mod.end_period(r); referee_panel_open = false end
            ui_inst:refresh_test_panel(r.testShortRestarts, r.testOneMinute, referee_test_touch)
        end
        return
    end
    if calibration_inst and calibration_inst.open then
        if key == "f5" then calibration_inst.open = false
        elseif key == "s" then calibration_inst:save()
        else calibration_inst:adjust(key) end
        return
    end
    if key == "f5" and game_inst and (game_inst.is_training or network_session) then calibration_inst.open = true; return end
    if key == "f6" and game_inst and game_inst.is_training then
        referee_panel_open = true
        ui_inst:refresh_test_panel(game_inst.referee.testShortRestarts, game_inst.referee.testOneMinute, referee_test_touch)
        return
    end
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
    if key == "tab" then show_ping = true; return end
    if network_session and (key == "1" or key == "2" or key == "3") then
        local team = key == "1" and "red" or (key == "2" and "blue" or nil)
        if network_session.role == "client" then network_session:set_team(team)
        elseif team then network_session:set_team(team, 1) end
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
            local next_index = current_index < 2 and 2 or (current_index >= #config.mode_names and 2 or current_index + 1)
            if network_session and network_session.role == "host" then
                network_session:set_mode(config.mode_names[next_index])
            else
                game_inst:set_mode(config.mode_names[next_index], 2)
            end
            if event_log then
                referee_mod.attach_event_log(game_inst.referee, event_log)
                referee_mod.record_reposition(game_inst.referee, "jogadores", "reposicionamento manual ao trocar modo F2")
                referee_mod.record_reposition(game_inst.referee, "bola", "reposicionamento manual ao trocar modo F2")
            end
            calibration_inst:apply()
            love.resize(love.graphics.getDimensions())
            ui_inst:update_score(game_inst.score_p1, game_inst.score_p2)
        end
    elseif key == (config.spin_selector and config.spin_selector.reset_key) then
        -- Tecla de reset do efeito (padrão C)
        local target_p = game_inst and game_inst.players[1]
        if target_p then target_p:reset_spin() end
    end
end

function love.keyreleased(key)
    if key == "tab" then show_ping = false end
end

function love.textinput(text)
    if app_screen == "menu" and menu_state.input and #menu_state.address < 64 then
        menu_state.address = menu_state.address .. text
    end
end
