-- Testes unitários de física e geometria da quadra RS.
local physics = require "src.physics"
local config = require "src.config"
local field_mod = require "src.field"
local game_mod = require "src.game"
local camera_mod = require "src.camera"
local calibration_mod = require "src.calibration"
local preferences_mod = require "src.preferences"

local tests = {}

local function new_ball(x, y, vx, vy)
    return {
        x = x, y = y, vx = vx, vy = vy,
        spin_x = 0, spin_y = 0,
        radius = config.ball.radius,
        mass = config.ball.mass,
        damping = config.ball.damping,
        max_speed = config.ball.max_speed,
        wall_restitution = config.ball.wall_restitution,
        post_restitution = config.ball.post_restitution,
        player_restitution = config.ball.player_restitution,
    }
end

function tests.run()
    io.write("\n=======================================================\n")
    io.write("      HAXBALL LOCAL - TESTES DA QUADRA RS             \n")
    io.write("=======================================================\n\n")

    local total, passed = 0, 0
    local function assert_test(name, condition, info)
        total = total + 1
        if condition then
            passed = passed + 1
            io.write(string.format("[PASS] %02d. %s\n", total, name))
        else
            io.write(string.format("[FAIL] %02d. %s\n", total, name))
            if info then io.write(string.format("       Motivo: %s\n", tostring(info))) end
        end
    end

    local f = field_mod.new(config.field)

    do
        local default = config.camera.viewWidth
        local function fake_filesystem(present, contents, second_result)
            return {
                getInfo = function() return present and { type = "file" } or nil, "missing" end,
                read = function() return contents, second_result or "metadata" end,
            }
        end
        local scenarios = {
            { "saves vazios", fake_filesystem(false), default },
            { "arquivo vazio", fake_filesystem(true, ""), default },
            { "arquivo corrompido", fake_filesystem(true, "zoom=perto"), default },
            { "zoom abaixo do mínimo", fake_filesystem(true, "1"), config.camera.viewWidthMin },
            { "zoom acima do máximo", fake_filesystem(true, "999999999"), config.camera.viewWidthMax },
            { "zoom válido", fake_filesystem(true, "1750"), 1750 },
        }
        local loaded_all = true
        for i = 1, #scenarios do
            local scenario = scenarios[i]
            local fake = scenario[2]
            local initialized = love.initialize_game({ getInfo = fake.getInfo, read = fake.read })
            if not initialized or initialized.camera.viewWidth ~= scenario[3] then loaded_all = false end
            io.write(string.format("       Inicialização: %s -> zoom %.0f\n", scenario[1],
                initialized and initialized.camera.viewWidth or -1))
        end
        config.camera.viewWidth = default
        local corrupt_read = {
            getInfo = function() return { type = "file" } end,
            read = function() error("arquivo indisponível") end,
        }
        local read_error_defaulted = preferences_mod.read_view_width(config, corrupt_read) == default
        assert_test("love.load inicializa com save vazio/corrompido, limita valores e restaura zoom válido",
                    loaded_all and read_error_defaulted)
    end

    do
        local cc = config.camera
        local view_h = cc.viewWidth * config.viewport.height / config.viewport.width
        local ok, min_margin = true, 1
        local function check_camera(px, py, tx, ty)
            local cx, cy = camera_mod.solve(tx, ty, px, py, cc.viewWidth, view_h,
                f, cc.cameraPadding, cc.edgeMarginFraction, config.player.radius, cc.safeZoneFraction)
            local nx = (px - (cx - cc.viewWidth * 0.5)) / cc.viewWidth
            local ny = (py - (cy - view_h * 0.5)) / view_h
            local margin_x = math.min(nx, 1 - nx)
            local margin_y = math.min(ny, 1 - ny) * view_h / cc.viewWidth
            local body_margin_x = margin_x - config.player.radius / cc.viewWidth
            local body_margin_y = margin_y - config.player.radius / cc.viewWidth
            if body_margin_x < cc.edgeMarginFraction - 0.0001 or body_margin_y < cc.edgeMarginFraction - 0.0001 then ok = false end
            if cx - cc.viewWidth * 0.5 < f.outer_left - cc.cameraPadding - 0.001 or
               cx + cc.viewWidth * 0.5 > f.outer_right + cc.cameraPadding + 0.001 or
               cy - view_h * 0.5 < f.outer_top - cc.cameraPadding - 0.001 or
               cy + view_h * 0.5 > f.outer_bottom + cc.cameraPadding + 0.001 then ok = false end
            min_margin = math.min(min_margin, body_margin_x, body_margin_y)
        end
        local edge = config.player.radius
        check_camera(f.outer_left + edge, f.outer_top + edge, f.right, f.bottom)
        check_camera(f.outer_right - edge, f.outer_top + edge, f.left, f.bottom)
        check_camera(f.outer_left + edge, f.outer_bottom - edge, f.right, f.top)
        check_camera(f.outer_right - edge, f.outer_bottom - edge, f.left, f.top)
        for i = 1, 4 do
            local wall = f.outer_walls[i]
            for j = -10, 10 do
                local t = (j + 10) / 20
                check_camera(wall.x1 + (wall.x2 - wall.x1) * t + wall.nx * edge,
                    wall.y1 + (wall.y2 - wall.y1) * t + wall.ny * edge, 0, 0)
            end
        end
        local seed = 8675309
        for i = 1, 2500 do
            seed = (seed * 48271) % 2147483647
            local px = f.outer_left + edge + (seed / 2147483647) * (f.outer_width - edge * 2)
            seed = (seed * 48271) % 2147483647
            local py = f.outer_top + edge + (seed / 2147483647) * (f.outer_height - edge * 2)
            seed = (seed * 48271) % 2147483647
            local tx = f.outer_left + (seed / 2147483647) * f.outer_width
            seed = (seed * 48271) % 2147483647
            local ty = f.outer_top + (seed / 2147483647) * f.outer_height
            check_camera(px, py, tx, ty)
        end
        assert_test("Câmera mantém disco do jogador a 5% da borda: cantos, paredes e entradas aleatórias",
                    ok, string.format("menor margem equivalente=%.4f da largura", min_margin))
    end

    do
        local g = game_mod.new(config, "1v1", 2)
        local before_accel, before_kick = config.player.acceleration, config.player.kick_strength
        local cal = calibration_mod.new(config, g, true)
        local default_time, default_distance, default_percent, default_ratio, default_speed = calibration_mod.metrics(cal)
        io.write(string.format("       Fisica padrao: travessia %.2f s; chute %.0f unidades (%.1f%%); razao %.2f; velocidade sustentada %.1f u/s\n",
            default_time, default_distance, default_percent, default_ratio, default_speed))
        cal.accelerationFactor, cal.kickFactor = 1.5, 1.25
        cal.ballDamping, cal.playerDamping = 0.98, 0.94
        cal.viewWidth, cal.cameraWeight = 1700, 0.7
        cal:apply()
        local t, d, pct, ratio = calibration_mod.metrics(cal)
        local values_ok = g.players[1].acceleration == before_accel * 1.5 and
            g.players[1].kick_strength == before_kick * 1.25 and g.ball.damping == 0.98 and
            g.camera.viewWidth == 1700 and g.camera.weight == 0.7 and t > 0 and d > 0 and pct > 0 and ratio > 1
        cal:apply()
        assert_test("Painel de calibração altera instâncias sem mudar padrões globais da física", values_ok and
            config.player.acceleration == before_accel and config.player.kick_strength == before_kick)
    end

    do
        local scale1280 = config.viewport.width / config.camera.viewWidth
        local scale1920 = 1920 / config.camera.viewWidth
        local sustained_speed = math.min(config.player.max_speed,
            config.player.acceleration * config.fixed_dt * config.player.damping / (1 - config.player.damping))
        assert_test("Escala da câmera produz diâmetros e velocidade de tela esperados",
            math.abs(config.player.radius * 2 * scale1280 - 25.6) < 0.001 and
            math.abs(config.ball.radius * 2 * scale1280 - 17.0667) < 0.001 and
            math.abs(config.player.radius * 2 * scale1920 - 38.4) < 0.001 and
            math.abs(config.ball.radius * 2 * scale1920 - 25.6) < 0.001 and
            math.abs(sustained_speed * scale1280 - 153.6) < 0.01)
        io.write(string.format("       viewWidth %.0f: jogador/bola %.2f/%.2f px (1280x720), %.2f/%.2f px (1920x1080); jogador %.1f px/s\n",
            config.camera.viewWidth, config.player.radius * 2 * scale1280,
            config.ball.radius * 2 * scale1280, config.player.radius * 2 * scale1920,
            config.ball.radius * 2 * scale1920, sustained_speed * scale1280))
    end

    -- Origem central e limites simétricos em pontos do mundo.
    do
        local centered = f.cx == 0 and f.cy == 0 and
            f.left == -1500 and f.right == 1500 and f.top == -750 and f.bottom == 750 and
            f.outer_left == -1650 and f.outer_right == 1650 and
            f.outer_top == -900 and f.outer_bottom == 900
        assert_test("Origem central e dimensões simétricas (3000 x 1500; paredes 3300 x 1800)", centered)
    end

    -- As coordenadas transmitidas como int16 x16 incluem toda a parede externa.
    do
        local fixed_scale = 16
        local max_fixed = math.max(math.abs(f.outer_left), math.abs(f.outer_right),
                                   math.abs(f.outer_top), math.abs(f.outer_bottom)) * fixed_scale
        assert_test("Limites externos em x16 cabem em int16", max_fixed <= 32767,
            string.format("extremo fixo=%d, limite=32767", max_fixed))
    end

    -- Raio, profundidade e abertura dos gols derivam apenas da configuração.
    do
        local geometry_ok = #f.posts == 4 and #f.outer_walls == 4 and #f.net_walls == 6 and
            math.abs(f.goal_top + config.field.goal_mouth_width / 2) < 0.001 and
            f.goal_back_left == -1620 and f.goal_back_right == 1620 and
            config.player.radius == 15 and config.ball.radius == 10
        assert_test("Geometria de gols, traves, paredes e escala de entidades", geometry_ok)
    end

    -- Todas as quadras têm a mesma geometria; cada modo declara sua capacidade.
    do
        local modes_ok = true
        for i = 1, #config.mode_names do
            local mode = config.mode_names[i]
            local g = game_mod.new(config, mode, #config.players)
            local capacity = tonumber((string.sub(mode, 1, 1)))
            local expected_players = math.min(4, capacity * 2)
            if g.team_capacity ~= capacity or #g.players ~= expected_players or
               g.field.outer_width ~= f.outer_width or g.field.outer_height ~= f.outer_height then
                modes_ok = false
            end
        end
        assert_test("Modos 1v1 a 5v5 mantêm arena e alteram capacidade/formação", modes_ok)
    end

    -- velocidade máxima e velocidade real gerada pelo chute máximo, em cada segmento.
    do
        local walls_ok = true
        local failure = ""
        local angles = { -0.5, 0, 0.5 }
        for wi = 1, #f.walls do
            local wall = f.walls[wi]
            local mx = (wall.x1 + wall.x2) * 0.5
            local my = (wall.y1 + wall.y2) * 0.5
            local tx, ty = -wall.ny, wall.nx
            for ai = 1, #angles do
                local a = angles[ai]
                local dir_x = -wall.nx * math.cos(a) + tx * math.sin(a)
                local dir_y = -wall.ny * math.cos(a) + ty * math.sin(a)
                for speed_case = 1, 2 do
                    local b = new_ball(mx + wall.nx * 80, my + wall.ny * 80,
                                       dir_x * config.ball.max_speed, dir_y * config.ball.max_speed)
                    if speed_case == 2 then
                        local kick_range = b.radius + config.player.radius + config.player.kick_margin - 0.5
                        local p = {
                            x = b.x - dir_x * kick_range, y = b.y - dir_y * kick_range,
                            vx = 0, vy = 0, radius = config.player.radius,
                        }
                        local kicked = physics.try_kick(p, b, config.player.kick_margin, config.player.kick_strength,
                                                        config.player.kick_player_speed_ratio, 0, 0, config.spin)
                        if not kicked then
                            walls_ok = false
                            failure = string.format("chute de teste falhou na parede %d", wi)
                            break
                        end
                    end
                    local target_field = {
                        walls = { wall }, posts = {}, left = f.left, right = f.right,
                        goal_top = f.goal_top, goal_bottom = f.goal_bottom,
                    }
                    local hit = false
                    for _ = 1, 20 do
                        local bounced = physics.simulate_ball_tick(b, config.fixed_dt, target_field, config.spin)
                        if bounced then hit = true end
                        local signed_distance = wall.nx * (b.x - mx) + wall.ny * (b.y - my)
                        if signed_distance < b.radius - 0.01 then
                            walls_ok = false
                            failure = string.format("parede %d tipo %s, distância %.3f", wi, wall.kind, signed_distance)
                            break
                        end
                    end
                    if not hit then
                        walls_ok = false
                        failure = string.format("sem impacto na parede %d (%s)", wi, wall.kind)
                    end
                    if not walls_ok then break end
                end
                if not walls_ok then break end
            end
            if not walls_ok then break end
        end
        assert_test("Bola não atravessa cada parede externa/rede em vários ângulos, inclusive chute máximo",
                    walls_ok, failure)
    end

    -- Cada poste é uma circunferência real: testar oito direções à velocidade limite.
    do
        local posts_ok = true
        local failure = ""
        for pi = 1, #f.posts do
            local post = f.posts[pi]
            for ai = 0, 7 do
                local angle = ai * math.pi / 4
                local ux, uy = math.cos(angle), math.sin(angle)
                local min_dist = post.radius + config.ball.radius
                local b = new_ball(post.x + ux * (min_dist + 80), post.y + uy * (min_dist + 80),
                                   -ux * config.ball.max_speed, -uy * config.ball.max_speed)
                local hit = false
                for _ = 1, 20 do
                    physics.apply_spin_and_damping(b, config.spin)
                    physics.integrate(b, config.fixed_dt)
                    if physics.resolve_circle_post(b, post, config.ball.post_restitution) then hit = true end
                    local dx, dy = b.x - post.x, b.y - post.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < min_dist - 0.01 then
                        posts_ok = false
                        failure = string.format("trave %d, ângulo %d, distância %.3f", pi, ai, dist)
                        break
                    end
                end
                if not hit then posts_ok = false; failure = "impacto ausente na trave " .. pi end
                if not posts_ok then break end
            end
            if not posts_ok then break end
        end
        assert_test("Bola não atravessa cada trave circular em vários ângulos a 850 unidades/s",
                    posts_ok, failure)
    end

    -- Jogadores podem ocupar a margem fora das linhas, mas nunca atravessar as paredes externas.
    do
        local players_ok = true
        local g = game_mod.new(config, "1v1", 2)
        local p = g.players[1]
        local tests_walls = g.field.outer_walls
        for wi = 1, #tests_walls do
            local wall = tests_walls[wi]
            local mx, my = (wall.x1 + wall.x2) * 0.5, (wall.y1 + wall.y2) * 0.5
            p.x = mx + wall.nx * (p.radius + 80)
            p.y = my + wall.ny * (p.radius + 80)
            p.vx = -wall.nx * p.max_speed
            p.vy = -wall.ny * p.max_speed
            for _ = 1, 80 do
                physics.apply_damping_and_limit(p, p.damping, p.max_speed)
                physics.integrate(p, config.fixed_dt)
                physics.resolve_circle_segment(p, wall, 0.1)
                local distance = wall.nx * (p.x - mx) + wall.ny * (p.y - my)
                if distance < p.radius - 0.01 then players_ok = false end
            end
        end
        p.x, p.y = f.left - 50, 0
        local outside_lines = p.x < f.left and p.x > f.outer_left + p.radius
        assert_test("Jogadores saem das linhas e permanecem contidos pelas paredes externas", players_ok and outside_lines)
    end

    -- Interação base entre jogadores e bola e colisão circular.
    do
        local p = { x = 100, y = 100, vx = 50, vy = 0, radius = 15, mass = 2 }
        local b = { x = 120, y = 100, vx = 0, vy = 0, radius = 10, mass = 1 }
        local collided = physics.resolve_circle_circle(p, b, 0.5)
        local distance = b.x - p.x
        assert_test("Colisão círculo-círculo conserva separação e razão de massas 2:1",
                    collided and distance >= 24.99 and b.vx > p.vx)
    end

    -- Chute máximo gera a velocidade configurada e não excede o limite físico.
    do
        local p = { x = -29, y = 0, vx = 0, vy = 0, radius = config.player.radius,
                    kick_margin = config.player.kick_margin, kick_strength = config.player.kick_strength,
                    kick_player_speed_ratio = 0 }
        local b = new_ball(0, 0, 0, 0)
        local kicked = physics.try_kick(p, b, p.kick_margin, p.kick_strength, 0, 0, 0, config.spin)
        local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
        assert_test("Chute máximo central usa 540 e fica sob o limite de 850", kicked and speed <= b.max_speed and math.abs(speed - 540) < 0.01)
    end

    -- Atrito aplicado uma vez por tick.
    do
        local p = { vx = 100, vy = 0 }
        physics.apply_damping_and_limit(p, config.player.damping, config.player.max_speed)
        local b = { vx = 200, vy = 0 }
        physics.apply_damping_and_limit(b, config.ball.damping, config.ball.max_speed)
        assert_test("Atrito permanece igual ao da física-base", math.abs(p.vx - 96) < 0.001 and math.abs(b.vx - 198) < 0.001)
    end

    -- Spin zero continua exatamente igual à simulação sem efeito.
    do
        local plain = new_ball(0, 0, 400, 0)
        local zero_spin = new_ball(0, 0, 400, 0)
        for _ = 1, 60 do
            physics.apply_damping_and_limit(plain, plain.damping, plain.max_speed)
            physics.integrate(plain, config.fixed_dt)
            physics.apply_spin_and_damping(zero_spin, config.spin)
            physics.integrate(zero_spin, config.fixed_dt)
        end
        assert_test("Spin zero mantém a trajetória de referência", math.abs(plain.x - zero_spin.x) < 0.001 and math.abs(plain.y - zero_spin.y) < 0.001)
    end

    -- SpinX dá curva para os lados esperados; spinY diferencia topo e recuo.
    do
        local right = new_ball(0, 0, 400, 0); right.spin_x = 0.8
        local left = new_ball(0, 0, 400, 0); left.spin_x = -0.8
        local straight = new_ball(0, 0, 400, 0)
        local top = new_ball(0, 0, 400, 0); top.spin_y = 1
        local back = new_ball(0, 0, 400, 0); back.spin_y = -1
        for _ = 1, 50 do
            for _, b in ipairs({ right, left, straight, top, back }) do
                physics.apply_spin_and_damping(b, config.spin)
                physics.integrate(b, config.fixed_dt)
            end
        end
        local top_speed = math.sqrt(top.vx * top.vx + top.vy * top.vy)
        local back_speed = math.sqrt(back.vx * back.vx + back.vy * back.vy)
        assert_test("Spin lateral e longitudinal mantêm direção e efeito", right.y > straight.y and left.y < straight.y and top_speed > back_speed)
    end

    -- Trajetória prevista e simulação real continuam compartilhando a física da bola.
    do
        local g = game_mod.new(config, "1v1", 2)
        local p, b = g.players[1], g.ball
        p.x, p.y = -25, 0
        p:set_spin(0.6, 0.4)
        g:update_presentation()
        local n = math.min(30, g.trajectory_count)
        local px, py = g.trajectory_points[n].x, g.trajectory_points[n].y
        local kicked = physics.try_kick(p, b, p.kick_margin, p.kick_strength, 0, p.spin_x, p.spin_y, config.spin)
        for _ = 1, n do physics.simulate_ball_tick(b, config.fixed_dt, g.field, config.spin) end
        local error_distance = math.sqrt((b.x - px) ^ 2 + (b.y - py) ^ 2)
        assert_test("Previsão e bola real usam a mesma simulação", kicked and n > 10 and error_distance < 0.05,
                    string.format("erro=%.5f", error_distance))
    end

    -- Clamp do spin e reinício do ponto.
    do
        local p = require("src.entities.player").new(config.players[1], config, 0, 0)
        p:set_spin(2, 2)
        local mag = math.sqrt(p.spin_x * p.spin_x + p.spin_y * p.spin_y)
        p:reset_spin()
        assert_test("Seletor limita spin ao círculo e volta ao centro", mag <= 1.0001 and p.spin_x == 0 and p.spin_y == 0)
    end

    -- Alcance teórico livre de um chute máximo, sem quique: soma geométrica do damping.
    do
        local b = new_ball(0, 0, config.player.kick_strength, 0)
        local distance = 0
        for _ = 1, 2000 do
            physics.apply_spin_and_damping(b, config.spin)
            physics.integrate(b, config.fixed_dt)
            distance = b.x
            if b.vx == 0 then break end
        end
        local percent = distance / config.field.play_width * 100
        assert_test("Alcance livre do chute máximo calculável", distance > 0)
        io.write(string.format("       Medida: %.1f unidades (%.1f%% da quadra)\n", distance, percent))
    end

    -- Distância real percorrida no comando máximo usando os coeficientes intactos da v1.0.
    do
        local p = require("src.entities.player").new(config.players[1], config, f.left, 0)
        local traveled = 0
        local ticks = 0
        while traveled < config.field.play_width and ticks < 10000 do
            p:step_physics(config.fixed_dt, 1, 0, false, nil, nil, physics, nil, config.spin)
            traveled = p.x - f.left
            ticks = ticks + 1
        end
        assert_test("Tempo de travessia mensurável com a física-base", traveled >= config.field.play_width)
        io.write(string.format("       Medida: %.2f s na velocidade de movimento sustentada (%.1f unidades/s)\n",
                              ticks * config.fixed_dt, traveled / (ticks * config.fixed_dt)))
    end

    -- Exercita a simulação e confirma que a previsão conserva todos os buffers pré-alocados.
    do
        local sim = game_mod.new(config, "2v2", 4)
        for _ = 1, 10000 do sim:step_fixed(config.fixed_dt, sim.commands) end

        local predictor = game_mod.new(config, "1v1", 2)
        predictor.players[1].x, predictor.players[1].y = -20, 0
        predictor:update_presentation()
        local points = predictor.trajectory_points
        local first_point, last_point = points[1], points[#points]
        local recorded_count = predictor.trajectory_count
        for _ = 1, 10000 do
            predictor:update_presentation()
        end
        local stable_buffers = predictor.trajectory_points == points and
            predictor.trajectory_points[1] == first_point and
            predictor.trajectory_points[#predictor.trajectory_points] == last_point and
            #predictor.trajectory_points == config.trajectory.max_ticks and
            predictor.trajectory_count == recorded_count
        assert_test("10.000 ticks mantêm estáveis os buffers pré-alocados da simulação e previsão", stable_buffers)
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r, field, ball = g.referee, g.field, g.ball
        local ok = true
        referee.begin_restart(r, "kickoff", "red", 0, 0)
        local cases = {
            { "lateral", 0, field.top - ball.radius - 1, "blue", field.top },
            { "lateral", 0, field.bottom + ball.radius + 1, "blue", field.bottom },
        }
        for i = 1, #cases do
            local c = cases[i]
            r.state, r.lastTouchTeam = referee.STATE_PLAY, "red"
            ball.x, ball.y = c[2], c[3]
            local kind, team, x, y = referee.detect_exit(r, ball, field)
            if kind ~= c[1] or team ~= c[4] or y ~= c[5] or x ~= 0 then ok = false end
        end
        r.state, r.lastTouchTeam = referee.STATE_PLAY, "red"
        ball.x, ball.y = field.left - ball.radius - 1, -200
        local kind, team, x, y = referee.detect_exit(r, ball, field)
        ok = ok and kind == "corner" and team == "blue" and x == field.left and y == field.top
        r.lastTouchTeam = "blue"
        kind, team = referee.detect_exit(r, ball, field)
        ok = ok and kind == "goal_kick" and team == "red"
        ball.x, ball.y = field.right + ball.radius + 1, -200
        r.lastTouchTeam = "red"
        kind, team = referee.detect_exit(r, ball, field)
        ok = ok and kind == "goal_kick" and team == "blue"
        r.lastTouchTeam = "blue"
        kind, team = referee.detect_exit(r, ball, field)
        ok = ok and kind == "corner" and team == "red"
        assert_test("Árbitro classifica laterais e fundos dos dois lados com atribuição correta", ok)
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r, f, b = g.referee, g.field, g.ball
        r.state, r.lastTouchTeam = referee.STATE_PLAY, "red"
        b.x, b.y = f.right + b.radius + 1, 0
        local kind, scoring = referee.detect_exit(r, b, f)
        local goal_ok = kind == "goal" and scoring == "red"
        referee.begin_goal(r, scoring)
        referee.clock_tick(r, config.game.goalCelebrationSeconds + 0.01)
        goal_ok = goal_ok and r.state == referee.STATE_KICKOFF and r.restartTeam == "blue" and r.ballFrozen
        referee.begin_restart(r, "lateral", "red", 0, f.top)
        local stopped_x, stopped_y = b.x, b.y
        g:step_fixed(config.fixed_dt, g.commands)
        goal_ok = goal_ok and b.x == stopped_x and b.y == stopped_y
        assert_test("Gol independe do último toque, pausa e reinicia pelo time que sofreu; bola parada congela", goal_ok)
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r, p, b, f = g.referee, g.players[1], g.ball, g.field
        referee.begin_restart(r, "kickoff", "red", 0, 0)
        p.x, p.y = b.x - p.radius - b.radius - 1, b.y
        local before = b.x
        local commands = g.commands
        commands[1].kick = false
        g:step_fixed(config.fixed_dt, commands)
        local frozen_ok = r.ballFrozen and b.x == before
        commands[1].kick = true
        p.x, p.y, p.vx, p.vy = b.x - p.radius - b.radius + 1, b.y, 0, 0
        g:step_fixed(config.fixed_dt, commands)
        commands[1].kick = false
        frozen_ok = frozen_ok and not r.ballFrozen and r.state == referee.STATE_PLAY and r.noRetouch
        -- Sem time autorizado: liberação automática após ~2 s.
        referee.begin_restart(r, "lateral", "red", 0, f.top)
        p.team = "blue"
        for _ = 1, 121 do g:step_fixed(config.fixed_dt, commands) end
        frozen_ok = frozen_ok and not r.ballFrozen
        assert_test("Bola congelada só sai em chute autorizado e libera após 2 s sem cobrador", frozen_ok)
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r, f, p = g.referee, g.field, g.players[2]
        local ok = true
        referee.begin_restart(r, "corner", "red", f.left, f.top)
        referee.resolve_violation(r)
        ok = ok and r.restartType == "goal_kick" and r.restartTeam == "blue"
        referee.begin_restart(r, "goal_kick", "red", f.left + 75, -100)
        referee.resolve_violation(r)
        ok = ok and r.restartType == "corner" and r.restartTeam == "blue"
        referee.begin_restart(r, "lateral", "red", f.left + 100, f.top)
        referee.timeout_restart(r)
        ok = ok and r.restartType == "lateral" and r.restartTeam == "blue" and r.restartRemaining == config.referee.restartTimeouts.lateral
        referee.begin_restart(r, "corner", "red", f.left, f.top)
        p.x, p.y = f.outer_left + p.radius + 1, f.outer_top + p.radius + 1
        local tx, ty = referee.restriction_target(r, p)
        ok = ok and (tx ~= p.x or ty ~= p.y) and tx >= f.outer_left + p.radius and ty >= f.outer_top + p.radius
        local tx2, ty2 = referee.restriction_target(r, { x = tx, y = ty, radius = p.radius, team = "blue" })
        ok = ok and tx2 == tx and ty2 == ty
        p.x, p.y, p.vx, p.vy = f.outer_left + p.radius + 1, f.outer_top + p.radius + 1, 0, 0
        local before_x, before_y = p.x, p.y
        g:step_fixed(config.fixed_dt, g.commands)
        ok = ok and math.abs(p.x - before_x) < 8 and math.abs(p.y - before_y) < 8
        for _ = 1, 120 do g:step_fixed(config.fixed_dt, g.commands) end
        local progress = math.sqrt((p.x - before_x) ^ 2 + (p.y - before_y) ^ 2)
        ok = ok and progress > 100
        assert_test("Timeout, cobrança incorreta e zona de escanteio junto ao canto encontram saída", ok,
            string.format("alvo=(%.1f, %.1f), legal=(%.1f, %.1f), deslocamento=%.1f", tx, ty, tx2, ty2, progress))
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r = g.referee
        local player = g.players[1]
        referee.begin_restart(r, "kickoff", "red", 0, 0)
        referee.begin_play(r, player.id)
        local kicker_cannot_retouch = referee.note_touch(r, player)
        local opponent = g.players[2]
        local other_touch_ok = not referee.note_touch(r, opponent) and not r.noRetouch
        referee.begin_restart(r, "lateral", "red", 0, g.field.top)
        local timings = config.referee.restartTimeouts.lateral == 0 and
            config.referee.restartTimeouts.goal_kick == 0 and
            config.referee.restartTimeouts.corner == 0 and
            config.referee.restartTimeouts.kickoff == 0 and
            config.game.halfDuration == 300 and config.game.testHalfDuration == 60
        assert_test("Toque duplo, toque de outro jogador e tempos padrão/teste", kicker_cannot_retouch and other_touch_ok and timings)
    end

    do
        local referee = require "src.referee"
        local checkpoints = {
            0,
            f.left + config.referee.cornerMargin,
            f.left + config.field.penalty_area_depth,
            f.right - config.referee.cornerMargin,
            f.right - config.field.penalty_area_depth,
        }
        local ok, details = config.referee.cornerZoneRadius == 350, ""
        for side_index = 1, 2 do
            local restart_y = side_index == 1 and f.top or f.bottom
            for point_index = 1, #checkpoints do
                local g = game_mod.new(config, "1v1", 2)
                local r, field = g.referee, g.field
                local x = checkpoints[point_index]
                referee.begin_restart(r, "lateral", "red", x, restart_y)
                local x1, x2, line_y, zone_top, zone_bottom = referee.throw_in_geometry(r)
                local expected_line = side_index == 1 and field.top + config.referee.throwInLineOffset or
                    field.bottom - config.referee.throwInLineOffset
                if x1 ~= field.outer_left or x2 ~= field.outer_right or
                   math.abs(line_y - expected_line) > 0.001 or zone_top >= zone_bottom then ok = false end

                local taker, opponent = g.players[1], g.players[2]
                taker.x, taker.y, taker.vx, taker.vy = field.right - 500, 0, 0, 0
                local start_y = side_index == 1 and field.outer_top + opponent.radius + 1 or
                    field.outer_bottom - opponent.radius - 1
                opponent.x, opponent.y, opponent.vx, opponent.vy = x, start_y, 0, 0
                if not referee.is_point_restricted(r, opponent) then ok = false end
                local target_x, target_y = referee.restriction_target(r, opponent)
                if referee.is_point_restricted(r, opponent, target_x, target_y) then ok = false end
                local start_x, start_y_check = opponent.x, opponent.y
                g:step_fixed(config.fixed_dt, g.commands)
                if math.sqrt((opponent.x - start_x)^2 + (opponent.y - start_y_check)^2) > 8 then ok = false end
                for _ = 1, 359 do g:step_fixed(config.fixed_dt, g.commands) end
                if referee.is_point_restricted(r, opponent) then
                    ok = false
                    details = string.format("adversário preso em lado=%d, ponto=%.1f; alvo=(%.1f, %.1f), posição=(%.1f, %.1f), v=(%.1f, %.1f)",
                        side_index, x, target_x, target_y, opponent.x, opponent.y, opponent.vx, opponent.vy)
                end

                taker.x, taker.y = x, (zone_top + zone_bottom) * 0.5
                local allowed_x, allowed_y = referee.restriction_target(r, taker)
                if allowed_x ~= taker.x or allowed_y ~= taker.y then ok = false end
            end
        end
        assert_test("Lateral usa barreira retangular parede a parede, deslocamento suave e cobrador liberado",
            ok, details)
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r = g.referee
        referee.begin_play(r, nil)
        r.halfRemaining = config.fixed_dt
        g:step_fixed(config.fixed_dt, g.commands)
        local grace_started = r.regulationExpired and r.state == referee.STATE_PLAY and r.graceRemaining == config.referee.regulationGrace
        local stoppage_ends_now = referee.ball_stopped(r) and r.state == referee.STATE_INTERVAL
        referee.start_second_half(r)
        referee.begin_play(r, nil)
        r.halfRemaining = config.fixed_dt
        g:step_fixed(config.fixed_dt, g.commands)
        local maximum_grace = referee.clock_tick(r, config.referee.regulationGrace + config.fixed_dt)
        assert_test("Relógio encerra na próxima parada ou no limite de 15 s", grace_started and stoppage_ends_now and
            maximum_grace == "period_end" and r.state == referee.STATE_FINISHED)
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r = g.referee
        r.testOneMinute = true
        r.halfDuration, r.halfRemaining = config.game.testHalfDuration, config.game.testHalfDuration
        referee.begin_play(r, nil)
        local ticks = 0
        while r.state ~= referee.STATE_FINISHED and ticks < 12000 do
            g:step_fixed(config.fixed_dt, g.commands)
            ticks = ticks + 1
        end
        local full_match = r.state == referee.STATE_FINISHED and r.half == 2 and not r.redAttacksRight and ticks < 12000
        assert_test("Partida simulada completa: dois tempos, intervalo, troca de lado e fim sem travar", full_match,
            string.format("estado=%s, tempo=%d ticks", r.state, ticks))
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r, b = g.referee, g.ball
        referee.begin_restart(r, "lateral", "red", 0, g.field.top)
        r.halfDuration, r.halfRemaining = 1200, 1200
        local frozen_x, frozen_y = b.x, b.y
        for _ = 1, 600 * 60 do g:step_fixed(config.fixed_dt, g.commands) end
        assert_test("Timeout zero mantém bola parada congelada por 10 minutos simulados",
            r.state == referee.STATE_LATERAL and r.ballFrozen and b.x == frozen_x and b.y == frozen_y)
    end

    do
        local referee = require "src.referee"
        local kinds = { "lateral", "corner", "goal_kick", "kickoff" }
        local all_blocked, all_evacuated, authorized = true, true, true
        local barrier_details = ""
        for i = 1, #kinds do
            local g = game_mod.new(config, "2v2", 4)
            local r, f, enemy = g.referee, g.field, g.players[4]
            local x, y
            if kinds[i] == "lateral" then x, y = 0, f.top
            elseif kinds[i] == "corner" then x, y = f.left, f.top
            elseif kinds[i] == "goal_kick" then x, y = f.left + 100, 0
            else x, y = 0, 0 end
            referee.begin_restart(r, kinds[i], "red", x, y)
            if kinds[i] == "lateral" then enemy.x, enemy.y = 0, f.outer_top + enemy.radius + 1
            elseif kinds[i] == "corner" then enemy.x, enemy.y = f.left + 10, f.top + 10
            elseif kinds[i] == "goal_kick" then enemy.x, enemy.y = f.left + 100, 0
            else enemy.x, enemy.y = 0, 0 end
            enemy.prev_x, enemy.prev_y = enemy.x, enemy.y
            for _ = 1, 300 do g:step_fixed(config.fixed_dt, g.commands) end
            if referee.is_point_restricted(r, enemy) then all_evacuated = false; barrier_details = barrier_details .. kinds[i] .. " não evacuou; " end
            local start_x, start_y = enemy.x, enemy.y
            local dir_x, dir_y = 0, 0
            if kinds[i] == "lateral" then dir_y = r.restartY < 0 and -1 or 1
            elseif kinds[i] == "corner" then dir_x, dir_y = (x < 0 and -1 or 1), (y < 0 and -1 or 1)
            elseif kinds[i] == "goal_kick" then dir_x = x < 0 and -1 or 1
            else dir_x = r.restartTeam == "red" and 1 or -1 end
            if kinds[i] == "corner" then
                local dx, dy = x - enemy.x, y - enemy.y
                local length = math.sqrt(dx * dx + dy * dy)
                dir_x, dir_y = dx / length, dy / length
            end
            g.commands[4].moveX, g.commands[4].moveY = dir_x, dir_y
            for _ = 1, 120 do
                g:step_fixed(config.fixed_dt, g.commands)
                if referee.is_point_restricted(r, enemy) then all_blocked = false; barrier_details = barrier_details .. kinds[i] .. " atravessou; " end
            end
            g.commands[4].moveX, g.commands[4].moveY = 0, 0
            local taker = g.players[1]
            if referee.is_point_restricted(r, taker, r.restartX, r.restartY) then authorized = false end
        end
        assert_test("Barreiras sólidas bloqueiam velocidade máxima, evacuam sem travar e liberam cobrador",
            all_blocked and all_evacuated and authorized,
            barrier_details .. "bloqueado=" .. tostring(all_blocked) .. ", evacuado=" .. tostring(all_evacuated) .. ", cobrador=" .. tostring(authorized))
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "2v2", 4)
        local r, f = g.referee, g.field
        local enemy, teammate = g.players[4], g.players[3]
        referee.begin_restart(r, "lateral", "red", 400, f.top)
        enemy.x, enemy.y, enemy.vx, enemy.vy = 400, f.top + config.referee.throwInLineOffset + enemy.radius + 1, 0, 0
        teammate.x, teammate.y, teammate.vx, teammate.vy = enemy.x, enemy.y + 36, 0, -teammate.max_speed
        local held = true
        for _ = 1, 90 do
            g:step_fixed(config.fixed_dt, g.commands)
            if referee.is_point_restricted(r, enemy) then held = false end
        end
        assert_test("Barreira de lateral bloqueia adversário empurrado por colega", held)
    end

    do
        local EventLog = require "src.event_log"
        local saved = ""
        local fake_fs = {
            getInfo = function() return nil end,
            write = function(_, contents) saved = contents; return true end,
        }
        local logger = EventLog.new(fake_fs, { path = "arbitro.log", capacity = 2000, flushInterval = 3 })
        for i = 1, 2005 do logger:record(i, 1, 300, "ESTADO", "JOGO", "LATERAL", "motivo " .. i, i, -i) end
        logger:flush()
        local lines, count = 0, 0
        for line in saved:gmatch("[^\r\n]+") do lines = lines + 1; if lines == 1 and line:find("motivo 6", 1, true) then count = count + 1 end end
        assert_test("arbitro.log conserva só as 2000 linhas mais recentes e descarrega em lote", lines == 2000 and count == 1)
    end

    do
        local referee = require "src.referee"
        local g = game_mod.new(config, "1v1", 2)
        local r = g.referee
        local logged = 0
        referee.attach_event_log(r, { record = function() logged = logged + 1 end })
        referee.begin_goal(r, "red")
        g.is_goal_delay, g.players[1].vx = true, 120
        local initial_x = g.players[1].x
        local celebration_events = logged
        for _ = 1, 100 do
            g:step_fixed(config.fixed_dt, g.commands)
        end
        local moved_during_celebration = g.players[1].x ~= initial_x and not r.ballFrozen and
            r.state == referee.STATE_GOAL and logged == celebration_events
        for _ = 101, math.floor(config.game.goalCelebrationSeconds / config.fixed_dt) + 1 do
            g:step_fixed(config.fixed_dt, g.commands)
        end
        local reset_after = r.state == referee.STATE_KICKOFF and r.ballFrozen and g.players[1].x == g.players[1].spawn_x
        local active = moved_during_celebration and reset_after and logged == celebration_events + 3 and
            g.score_p1 == 0 and g.score_p2 == 0
        referee.begin_goal(r, "blue")
        r.halfRemaining = config.fixed_dt
        for _ = 1, math.floor(config.game.goalCelebrationSeconds / config.fixed_dt) + 1 do
            g:step_fixed(config.fixed_dt, g.commands)
        end
        local ends_match = r.state == referee.STATE_INTERVAL and r.regulationExpired and
            g.players[1].x == g.players[1].spawn_x
        assert_test("Comemoração de 7 s mantém movimento sem eventos/gols duplicados, repõe tudo e encerra tempo expirado", active and ends_match)
    end

    do
        local training = love.initialize_game({ getInfo = function() return nil end, read = function() return nil end })
        local ok = training and #training.players == 2 and training.players[1].team == "red" and
            training.players[2].team == "blue" and training.players[1].allow_spin and not training.players[2].allow_spin and
            training.players[2].keys.kick == "return"
        assert_test("Treino solo inicia exatamente dois jogadores: WASD vermelho e IJKL/Enter azul sem efeito",
            ok)
    end

    do
        local referee = require "src.referee"
        local test_config = {}
        for key, value in pairs(config) do test_config[key] = value end
        test_config.game = {}
        for key, value in pairs(config.game) do test_config.game[key] = value end
        test_config.game.halfDuration = 600
        test_config.referee = {}
        for key, value in pairs(config.referee) do test_config.referee[key] = value end
        test_config.referee.testRestartTimeout = 0.25
        local g = game_mod.new(test_config, "1v1", 2)
        local r = g.referee
        r.halfDuration, r.halfRemaining, r.testShortRestarts = 600, 600, true
        referee.begin_play(r, nil)
        local seed, events, reasons_ok = 1234567, 0, true
        local memory_log = { record = function(_, _, _, _, _, _, _, reason) events = events + 1; if not reason or reason == "" then reasons_ok = false end end }
        referee.attach_event_log(r, memory_log)
        local ticks = 0
        while r.state ~= referee.STATE_FINISHED and ticks < 80000 do
            for i = 1, #g.commands do
                seed = (seed * 48271) % 2147483647
                local cmd = g.commands[i]
                cmd.moveX = seed % 3 - 1
                seed = (seed * 48271) % 2147483647
                cmd.moveY = seed % 3 - 1
                seed = (seed * 48271) % 2147483647
                cmd.kick = seed % 47 == 0
            end
            g:step_fixed(config.fixed_dt, g.commands)
            ticks = ticks + 1
        end
        assert_test("Simulação aleatória de 20 minutos registra motivo em toda transição", r.state == referee.STATE_FINISHED and
            r.matchElapsed >= 1200 and events > 0 and reasons_ok,
            string.format("estado=%s; tempo=%.1f; eventos=%d", r.state, r.matchElapsed, events))
        io.write(string.format("       Simulação longa: %.1f s de partida; %d registros; motivos presentes em todos.\n",
            r.matchElapsed, events))
    end

    do
        local referee = require "src.referee"
        local smoke_call_ok, smoke_ok, smoke_result = xpcall(function()
            local empty_saves = {
                getInfo = function() return nil, "save inexistente" end,
                read = function() return nil, "save inexistente" end,
            }
            local state_names = {
                referee.STATE_WARMUP, referee.STATE_KICKOFF, referee.STATE_PLAY,
                referee.STATE_LATERAL, referee.STATE_GOAL_KICK, referee.STATE_CORNER,
                referee.STATE_GOAL, referee.STATE_INTERVAL, referee.STATE_FINISHED,
            }
            local resolutions = { {1280, 720}, {1920, 1080} }
            local player_counts = { 1, 10 }
            local completed = 0
            for count_index = 1, #player_counts do
                local player_count = player_counts[count_index]
                local smoke_config = {}
                for key, value in pairs(config) do smoke_config[key] = value end
                smoke_config.players = {}
                for i = 1, player_count do
                    local source = config.players[(i - 1) % #config.players + 1]
                    smoke_config.players[i] = {
                        id = "smoke" .. i, name = source.name, team = i <= player_count / 2 and "red" or "blue",
                        number = source.number, color = source.color, inner_color = source.inner_color,
                        keys = source.keys, spin_keys = source.spin_keys,
                    }
                end
                local active_game = love.initialize_game(empty_saves, player_count, smoke_config)
                love.configure_smoke_overlays(true)
                for resolution_index = 1, #resolutions do
                    local width, height = resolutions[resolution_index][1], resolutions[resolution_index][2]
                    local canvas = love.graphics.newCanvas(width, height)
                    love.resize(width, height)
                    love.graphics.setCanvas(canvas)
                    for state_index = 1, #state_names do
                        local state = state_names[state_index]
                        local r, f = active_game.referee, active_game.field
                        if state == referee.STATE_WARMUP then
                            referee.reset_match(r)
                        elseif state == referee.STATE_KICKOFF then
                            referee.begin_restart(r, "kickoff", "red", 0, 0)
                        elseif state == referee.STATE_PLAY then
                            referee.begin_play(r, nil)
                        elseif state == referee.STATE_LATERAL then
                            referee.begin_restart(r, "lateral", "blue", 0, f.top)
                        elseif state == referee.STATE_GOAL_KICK then
                            referee.begin_restart(r, "goal_kick", "blue", f.left + config.field.goal_area_depth / 2, 0)
                        elseif state == referee.STATE_CORNER then
                            referee.begin_restart(r, "corner", "red", f.right, f.bottom)
                        elseif state == referee.STATE_GOAL then
                            referee.begin_goal(r, "red")
                            active_game.is_goal_delay, active_game.last_scorer = true, "p1"
                        elseif state == referee.STATE_INTERVAL then
                            r.half = 1
                            referee.end_period(r)
                        else
                            r.half = 2
                            referee.end_period(r)
                        end
                        for frame = 1, 300 do
                            local frame_ok, frame_error = xpcall(function()
                                love.update(config.fixed_dt)
                                love.draw()
                            end, debug.traceback)
                            if not frame_ok then
                                error(string.format("Fumaça: jogadores=%d, resolução=%dx%d, estado=%s, quadro=%d\n%s",
                                    player_count, width, height, state, frame, tostring(frame_error)), 0)
                            end
                        end
                        completed = completed + 1
                    end
                    love.graphics.setCanvas()
                    canvas:release()
                end
            end
            love.configure_smoke_overlays(false)
            return completed == 36, completed
        end, debug.traceback)
        assert_test("Fumaça update/draw: 9 estados × 1/10 jogadores × 1280/1920, 300 quadros e F3/F4/F5/F6",
            smoke_call_ok and smoke_ok, smoke_call_ok and (tostring(smoke_result) .. " cenários") or smoke_ok)
    end


    io.write("\n=======================================================\n")
    io.write(string.format("RESULTADO FINAL: %d / %d TESTES APROVADOS\n", passed, total))
    io.write("=======================================================\n\n")
    return passed == total
end

return tests
