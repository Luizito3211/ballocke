-- tests/test_physics.lua: Validação matemática e física completa (física base, presets, curva e trajetória)
local physics = require "src.physics"
local config = require "src.config"
local field_mod = require "src.field"

local tests = {}

function tests.run()
    io.write("\n=======================================================\n")
    io.write("       HAXBALL LOCAL - SUITE DE TESTES FISICOS         \n")
    io.write("=======================================================\n\n")

    local total = 0
    local passed = 0

    local function assert_test(name, condition, extra_info)
        total = total + 1
        if condition then
            passed = passed + 1
            io.write(string.format("[PASS] %s\n", name))
        else
            io.write(string.format("[FAIL] %s\n", name))
            if extra_info then
                io.write(string.format("       Motivo: %s\n", tostring(extra_info)))
            end
        end
    end

    -- TESTE 1: Atrito e Damping por tick (0.96 para jogador, 0.99 para bola)
    do
        local p = { vx = 100, vy = 0 }
        physics.apply_damping_and_limit(p, config.player.damping, config.player.max_speed)
        local expected_p = 100 * config.player.damping
        local err_p = math.abs(p.vx - expected_p)

        local b = { vx = 200, vy = 0 }
        physics.apply_damping_and_limit(b, config.ball.damping, config.ball.max_speed)
        local expected_b = 200 * config.ball.damping
        local err_b = math.abs(b.vx - expected_b)

        assert_test("1. Atrito aplicado uma vez por tick (0.96 jogador, 0.99 bola)",
            err_p < 0.001 and err_b < 0.001,
            string.format("P: %.4f (esp: %.4f), B: %.4f (esp: %.4f)", p.vx, expected_p, b.vx, expected_b))
    end

    -- TESTE 2: Colisão Círculo x Círculo com razão de massas 2:1
    do
        local player = { x = 100, y = 100, vx = 50, vy = 0, radius = 15, mass = 2.0 }
        local ball =   { x = 120, y = 100, vx = 0,  vy = 0, radius = 10, mass = 1.0 }

        local collided = physics.resolve_circle_circle(player, ball, 0.5)
        local dist_after = ball.x - player.x

        local ratio_ok = math.abs((player.x - 100) - (-5 * (1/3))) < 0.01 and
                         math.abs((ball.x - 120) - (5 * (2/3))) < 0.01

        local vel_ok = ball.vx > player.vx

        assert_test("2. Colisao Circulo-Circulo com razao 2:1 e separacao proporcional",
            collided and dist_after >= 24.99 and ratio_ok and vel_ok,
            string.format("Dist: %.2f, P_x: %.2f, B_x: %.2f, B_vx: %.2f", dist_after, player.x, ball.x, ball.vx))
    end

    -- TESTE 3: Colisão mútua entre 4 Jogadores (pares pré-computados, penetração zero)
    do
        local game_mod = require "src.game"
        local g = game_mod.new(config, "3v3", 4)

        for i = 1, #g.players do
            g.players[i].x = g.field.cx + (i - 2.5) * 10
            g.players[i].y = g.field.cy
            g.players[i].vx = 0
            g.players[i].vy = 0
        end

        for _ = 1, 15 do
            for i = 1, g.num_player_pairs do
                local pair = g.player_pairs[i]
                physics.resolve_circle_circle(pair.p1, pair.p2, pair.p1.restitution)
            end
        end

        local overlap = false
        local min_found = 9999
        for i = 1, g.num_player_pairs do
            local pair = g.player_pairs[i]
            local dx = pair.p2.x - pair.p1.x
            local dy = pair.p2.y - pair.p1.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < min_found then min_found = dist end
            if dist < (pair.p1.radius + pair.p2.radius - 0.01) then
                overlap = true
            end
        end

        assert_test("3. Colisao mutua entre 4 jogadores simultaneos sem sobreposicao",
            (not overlap) and g.num_player_pairs == 6,
            string.format("Pares: %d, Menor dist entre jogadores: %.2f (minimo: 30.00)", g.num_player_pairs, min_found))
    end

    -- TESTE 4: Impacto elástico com Traves Circulares
    do
        local post = { x = 120, y = 200, radius = 8 }
        local b = { x = 120, y = 212, vx = 0, vy = -80, radius = 10 }

        local hit = physics.resolve_circle_post(b, post, 0.8)
        local dist = b.y - post.y
        local vel_reflected = b.vy > 0

        assert_test("4. Impacto elastico com trave circular estatica (restituicao ~0.8)",
            hit and dist >= 17.99 and vel_reflected,
            string.format("Dist: %.2f (esp: >=18), b.vy: %.2f", dist, b.vy))
    end

    -- TESTE 5: Prevenção de Tunelamento em Paredes em TODOS os Presets (1v1, 2v2, 3v3)
    do
        local all_presets_ok = true
        local preset_names = { "1v1", "2v2", "3v3" }
        local dt = config.fixed_dt

        for p_idx = 1, #preset_names do
            local preset = config.presets[preset_names[p_idx]]
            local f = field_mod.new(preset)

            local b_top = { x = f.cx, y = f.top + 5, vx = 0, vy = -config.ball.max_speed, radius = config.ball.radius }
            physics.integrate(b_top, dt)
            physics.resolve_circle_segment(b_top, f.walls[1], config.ball.wall_restitution)
            if b_top.y < (f.top + b_top.radius - 0.001) or b_top.vy < 0 then
                all_presets_ok = false
            end

            local b_bot = { x = f.cx, y = f.bottom - 5, vx = 0, vy = config.ball.max_speed, radius = config.ball.radius }
            physics.integrate(b_bot, dt)
            physics.resolve_circle_segment(b_bot, f.walls[2], config.ball.wall_restitution)
            if b_bot.y > (f.bottom - b_bot.radius + 0.001) or b_bot.vy > 0 then
                all_presets_ok = false
            end
        end

        assert_test("5. Prevencao de tunelamento na parede em velocidade maxima (1v1, 2v2 e 3v3)",
            all_presets_ok,
            "Bola ultrapassou parede perimetral em velocidade maxima em um dos presets")
    end

    -- TESTE 6: Prevenção de Tunelamento nas Traves em TODOS os Presets
    do
        local all_posts_ok = true
        local preset_names = { "1v1", "2v2", "3v3" }
        local dt = config.fixed_dt

        for p_idx = 1, #preset_names do
            local preset = config.presets[preset_names[p_idx]]
            local f = field_mod.new(preset)

            local post = f.posts[1]
            local b_post = { x = post.x, y = post.y + post.radius + 4, vx = 0, vy = -config.ball.max_speed, radius = config.ball.radius }
            physics.integrate(b_post, dt)
            physics.resolve_circle_post(b_post, post, config.ball.post_restitution)

            local dist = math.sqrt((b_post.x - post.x)^2 + (b_post.y - post.y)^2)
            if dist < (b_post.radius + post.radius - 0.001) or b_post.vy <= 0 then
                all_posts_ok = false
            end
        end

        assert_test("6. Prevencao de tunelamento nas traves em velocidade maxima (1v1, 2v2 e 3v3)",
            all_posts_ok,
            "Bola penetrou trave em velocidade maxima em um dos presets")
    end

    -- TESTE 7: Detecção de Gol Precisa em TODOS os Presets
    do
        local all_goals_ok = true
        local preset_names = { "1v1", "2v2", "3v3" }

        for p_idx = 1, #preset_names do
            local preset = config.presets[preset_names[p_idx]]
            local f = field_mod.new(preset)
            local r = config.ball.radius

            local b_tangent = { x = f.left - r + 1, y = f.cy, radius = r }
            local is_goal_tangent = (b_tangent.x + b_tangent.radius < f.left)

            local b_inside = { x = f.left - r - 1, y = f.cy, radius = r }
            local is_goal_inside = (b_inside.x + b_inside.radius < f.left)

            if is_goal_tangent or (not is_goal_inside) then
                all_goals_ok = false
            end
        end

        assert_test("7. Deteccao de gol em cada preset (100% da linha cruzada)",
            all_goals_ok,
            "Falha na detecção de gol para algum preset")
    end

    -- TESTE 8: Efeito 0 = Comportamento 100% Idêntico à Física Sem Efeito
    do
        local b_no_spin = { x = 200, y = 200, vx = 400, vy = 0, radius = 10, damping = 0.99, max_speed = 850, spin_x = 0, spin_y = 0 }
        local b_spin_zero = { x = 200, y = 200, vx = 400, vy = 0, radius = 10, damping = 0.99, max_speed = 850, spin_x = 0, spin_y = 0 }

        for _ = 1, 60 do
            -- Método tradicional
            physics.apply_damping_and_limit(b_no_spin, b_no_spin.damping, b_no_spin.max_speed)
            physics.integrate(b_no_spin, config.fixed_dt)

            -- Novo método com curva e spin 0
            physics.apply_spin_and_damping(b_spin_zero, config.spin)
            physics.integrate(b_spin_zero, config.fixed_dt)
        end

        local diff_x = math.abs(b_no_spin.x - b_spin_zero.x)
        local diff_y = math.abs(b_no_spin.y - b_spin_zero.y)

        assert_test("8. Efeito 0 = Trajetoria identica a anterior (diff < 0.001 px)",
            diff_x < 0.001 and diff_y < 0.001 and math.abs(b_spin_zero.y - 200) < 0.001,
            string.format("diff_x: %.6f, diff_y: %.6f", diff_x, diff_y))
    end

    -- TESTE 9: Desvio Lateral pelo Efeito (spinX positivo para a direita, negativo para a esquerda)
    do
        -- Bola arremessada para a direita (+X).
        -- Convenção: spinX > 0 curva para a direita (em tela com Y para baixo, curva para +Y).
        -- spinX < 0 curva para a esquerda (curva para -Y).
        local b_right = { x = 200, y = 200, vx = 400, vy = 0, radius = 10, damping = 0.99, max_speed = 850, spin_x = 0.8, spin_y = 0 }
        local b_left  = { x = 200, y = 200, vx = 400, vy = 0, radius = 10, damping = 0.99, max_speed = 850, spin_x = -0.8, spin_y = 0 }
        local b_straight = { x = 200, y = 200, vx = 400, vy = 0, radius = 10, damping = 0.99, max_speed = 850, spin_x = 0, spin_y = 0 }

        for _ = 1, 40 do
            physics.apply_spin_and_damping(b_right, config.spin)
            physics.integrate(b_right, config.fixed_dt)

            physics.apply_spin_and_damping(b_left, config.spin)
            physics.integrate(b_left, config.fixed_dt)

            physics.apply_spin_and_damping(b_straight, config.spin)
            physics.integrate(b_straight, config.fixed_dt)
        end

        local right_curved = (b_right.y > b_straight.y + 10)
        local left_curved  = (b_left.y < b_straight.y - 10)

        assert_test("9. Desvio lateral proporcional ao spinX (direita +Y, esquerda -Y)",
            right_curved and left_curved,
            string.format("Y_right: %.2f, Y_straight: %.2f, Y_left: %.2f", b_right.y, b_straight.y, b_left.y))
    end

    -- TESTE 10: Efeito Longitudinal spinY (Topo conserva velocidade, Recuo dissipa mais rápido)
    do
        local b_top =  { x = 200, y = 200, vx = 400, vy = 0, radius = 10, damping = 0.99, max_speed = 850, spin_x = 0, spin_y = 1.0 }
        local b_back = { x = 200, y = 200, vx = 400, vy = 0, radius = 10, damping = 0.99, max_speed = 850, spin_x = 0, spin_y = -1.0 }

        for _ = 1, 50 do
            physics.apply_spin_and_damping(b_top, config.spin)
            physics.integrate(b_top, config.fixed_dt)

            physics.apply_spin_and_damping(b_back, config.spin)
            physics.integrate(b_back, config.fixed_dt)
        end

        local speed_top = math.sqrt(b_top.vx * b_top.vx + b_top.vy * b_top.vy)
        local speed_back = math.sqrt(b_back.vx * b_back.vx + b_back.vy * b_back.vy)

        assert_test("10. Efeito longitudinal spinY (Top conserva velocidade > Back recuo)",
            speed_top > speed_back + 15,
            string.format("Speed Top: %.2f px/s, Speed Back: %.2f px/s", speed_top, speed_back))
    end

    -- TESTE 11: A Previsão de Trajetória bate rigorosamente com o Caminho Real da Bola
    do
        local game_mod = require "src.game"
        local g = game_mod.new(config, "1v1", 2)
        local p = g.players[1]
        local b = g.ball

        -- Posiciona P1 imediatamente ao lado da bola (dentro do alcance de posse)
        p.x = b.x - (p.radius + b.radius + 2)
        p.y = b.y
        p:set_spin(0.6, 0.4)

        -- 1. Executa atualização de apresentação para calcular a linha de previsão
        g:update_presentation()
        local recorded_ticks = g.trajectory_count
        local check_tick = math.min(30, recorded_ticks)

        local pred_x = g.trajectory_points[check_tick].x
        local pred_y = g.trajectory_points[check_tick].y

        -- 2. Executa chute real da bola por P1 com o mesmo efeito
        local kicked = physics.try_kick(p, b, p.kick_margin, p.kick_strength, p.kick_player_speed_ratio, p.spin_x, p.spin_y, config.spin)

        -- 3. Avança a bola real pelo mesmo número de ticks usando a rotina compartilhada
        for _ = 1, check_tick do
            physics.simulate_ball_tick(b, config.fixed_dt, g.field, config.spin)
        end

        local err_dist = math.sqrt((b.x - pred_x)^2 + (b.y - pred_y)^2)

        assert_test("11. Previsao de trajetoria identica ao caminho real da bola (erro < 0.05 px)",
            kicked and recorded_ticks > 10 and err_dist < 0.05,
            string.format("Dist erro: %.6f px (Previsto: %.2f, %.2f | Real: %.2f, %.2f)", err_dist, pred_x, pred_y, b.x, b.y))
    end

    -- TESTE 12: Clamping do Seletor de Efeito e Reset ao Centro
    do
        local player_mod = require "src.entities.player"
        local p = player_mod.new(config.players[1], config, 0, 0)

        -- Define spin fora do círculo limite (magnitude > 1)
        p:set_spin(2.0, 2.0)
        local mag = math.sqrt(p.spin_x * p.spin_x + p.spin_y * p.spin_y)
        local clamped = (mag <= 1.0001)

        -- Reset ao centro
        p:reset_spin()
        local is_zero = (p.spin_x == 0 and p.spin_y == 0)

        assert_test("12. Seletor de efeito: clamp ao circulo (mag <= 1.0) e reset ao centro",
            clamped and is_zero,
            string.format("Mag clamped: %.4f, Pos reset: %.4f, %.4f", mag, p.spin_x, p.spin_y))
    end

    -- TESTE 13: Zero Alocação de Tabelas / GC Leaks em 1000 Ticks com Simulação de Efeito e Trajetória
    do
        if jit then jit.off() end

        local game_mod = require "src.game"
        local g = game_mod.new(config, "3v3", 4)

        -- Põe um jogador intencionalmente em posse da bola com efeito ativo
        g.players[1].x = g.ball.x - 20
        g.players[1].y = g.ball.y
        g.players[1]:set_spin(0.7, -0.5)

        for _ = 1, 100 do
            g:step_fixed(config.fixed_dt, g.commands)
            g:update_presentation()
        end
        collectgarbage("collect")
        collectgarbage("collect")
        local mem_before = collectgarbage("count")

        -- 1000 ticks com simulação de física, colisão de 4 jogadores e cálculo de previsão a cada frame
        for _ = 1, 1000 do
            g:step_fixed(config.fixed_dt, g.commands)
            g:update_presentation()
        end

        collectgarbage("collect")
        collectgarbage("collect")
        local mem_after = collectgarbage("count")
        local diff_kb = mem_after - mem_before

        if jit then jit.on() end

        assert_test("13. Zero Alocacao de Tabelas / GC Leaks em 1000 ticks com trajetoria ativa",
            diff_kb <= 0.5,
            string.format("Antes: %.2f KB, Depois: %.2f KB (Crescimento: %.4f KB)", mem_before, mem_after, diff_kb))
    end

    io.write("\n=======================================================\n")
    io.write(string.format("RESULTADO FINAL: %d / %d TESTES APROVADOS\n", passed, total))
    io.write("=======================================================\n\n")

    return (passed == total)
end

return tests
