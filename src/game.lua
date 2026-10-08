-- src/game.lua: Regras, simulação determinística, N jogadores e previsão de trajetória
local game = {}
local physics = require "src.physics"
local field_mod = require "src.field"
local player_mod = require "src.entities.player"
local ball_mod = require "src.entities.ball"
local input_mod = require "src.input"
local camera_mod = require "src.camera"

function game.new(config, preset_name, num_players)
    local g = {}
    g.config = config
    g.is_training = true

    g.score_p1 = 0
    g.score_p2 = 0
    g.is_goal_delay = false
    g.goal_delay_timer = 0
    g.last_scorer = nil

    -- Estruturas pré-alocadas para a previsão de trajetória (Zero GC)
    local max_ticks = (config.trajectory and config.trajectory.max_ticks) or 120
    g.trajectory_points = {}
    for i = 1, max_ticks do
        g.trajectory_points[i] = { x = 0, y = 0 }
    end
    g.trajectory_count = 0
    g.possessor_player = nil

    -- Bola de rascunho para simulação física de previsão (reutiliza mesma lógica da bola real)
    g.scratch_ball = {
        x = 0, y = 0, vx = 0, vy = 0,
        spin_x = 0, spin_y = 0,
        radius = config.ball.radius,
        mass = config.ball.mass,
        damping = config.ball.damping,
        max_speed = config.ball.max_speed,
        wall_restitution = config.ball.wall_restitution,
        post_restitution = config.ball.post_restitution,
    }

    setmetatable(g, { __index = game })
    g:set_mode(preset_name or config.default_mode or "2v2", num_players or #config.players)
    g.camera = camera_mod.new(config.camera, g.field, config.camera.viewWidth,
                              config.viewport.height, config.viewport.width)

    return g
end

-- Configura ou troca o preset de campo e reconstrói jogadores e colisores
function game.set_mode(g, mode_name, num_players)
    local cfg = g.config
    local formation = cfg.formations[mode_name] or cfg.formations[cfg.default_mode]
    mode_name = cfg.formations[mode_name] and mode_name or cfg.default_mode
    g.formation = formation
    g.mode_name = mode_name
    g.team_capacity = formation.capacity

    -- 1. Geometria do campo
    g.field = field_mod.new(cfg.field)

    -- 2. Bola no centro do campo
    g.ball = ball_mod.new(cfg, 0, 0)
    g.ball.prev_x, g.ball.prev_y = g.ball.x, g.ball.y

    -- 3. Inicialização dos Jogadores e Comandos Pré-Alocados
    num_players = math.min(num_players or #cfg.players, #cfg.players, formation.capacity * 2)
    g.players = {}
    g.commands = {}

    local red_count = 0
    local blue_count = 0

    for i = 1, num_players do
        local p_data = cfg.players[i]
        local spawn_x, spawn_y

        if p_data.team == "red" then
            red_count = red_count + 1
            local sp = formation.red[red_count]
            spawn_x = sp.x
            spawn_y = sp.y
        else
            blue_count = blue_count + 1
            local sp = formation.blue[blue_count]
            spawn_x = sp.x
            spawn_y = sp.y
        end

        g.players[i] = player_mod.new(p_data, cfg, spawn_x, spawn_y)
        g.players[i].prev_x, g.players[i].prev_y = spawn_x, spawn_y
        g.commands[i] = { moveX = 0, moveY = 0, kick = false, spinX = 0, spinY = 0 }
    end

    -- 4. Pré-computação dos pares de colisão jogador x jogador (Zero alocação no update)
    g.player_pairs = {}
    local pair_idx = 0
    for i = 1, #g.players - 1 do
        for j = i + 1, #g.players do
            pair_idx = pair_idx + 1
            g.player_pairs[pair_idx] = { p1 = g.players[i], p2 = g.players[j] }
        end
    end
    g.num_player_pairs = pair_idx

    g:reset_positions()
    if g.camera then g.camera.field = g.field; g.camera.initialized = false end
end

-- Reinicia posições para o início da jogada (kick-off)
function game.reset_positions(g)
    g.ball:reset()
    g.ball.prev_x, g.ball.prev_y = g.ball.x, g.ball.y
    for i = 1, #g.players do
        g.players[i]:reset()
        g.players[i].prev_x, g.players[i].prev_y = g.players[i].x, g.players[i].y
    end
    g.is_goal_delay = false
    g.goal_delay_timer = 0
    g.last_scorer = nil
    g.trajectory_count = 0
    g.possessor_player = nil
end

-- Reinicia partida inteira (placar zerado)
function game.reset_match(g)
    g.score_p1 = 0
    g.score_p2 = 0
    g:reset_positions()
end

-- Passo de física determinístico: depende estritamente do estado 'g' e da lista 'commands'
function game.step_fixed(g, dt, commands)
    local cfg = g.config
    local f = g.field
    local b = g.ball
    local players = g.players
    local num_p = #players
    b.prev_x, b.prev_y = b.x, b.y
    for i = 1, num_p do
        players[i].prev_x, players[i].prev_y = players[i].x, players[i].y
    end
    commands = commands or g.commands

    -- 1. Tratamento do intervalo após gol
    if g.is_goal_delay then
        g.goal_delay_timer = g.goal_delay_timer - dt
        if g.goal_delay_timer <= 0 then
            g:reset_positions()
            return
        end
        -- Durante a comemoração pós-gol, a bola apenas desacelera suavemente
        physics.apply_damping_and_limit(b, b.damping, b.max_speed)
        physics.integrate(b, dt)
    else
        -- 2. Atualização física de cada jogador orientada por comandos
        for i = 1, num_p do
            local p = players[i]
            local cmd = commands[i]
            p:step_physics(dt, cmd.moveX, cmd.moveY, cmd.kick, cmd.spinX, cmd.spinY, physics, b, cfg.spin)
        end

        -- 3. Atualização física da bola (curva lateral + atrito longitudinal + movimento)
        b:step_physics(dt, physics, cfg.spin)

        -- 4. Colisão Jogador x Jogador (usando pares pré-computados)
        for i = 1, g.num_player_pairs do
            local pair = g.player_pairs[i]
            physics.resolve_circle_circle(pair.p1, pair.p2, pair.p1.restitution)
        end

        -- 5. Colisão Jogador x Bola (razão de massa 2:1, sem gerar efeito na bola em condução)
        for i = 1, num_p do
            physics.resolve_circle_circle(players[i], b, b.player_restitution)
        end
    end

    -- 6. Colisões com Traves (postes estáticos)
    for i = 1, #f.posts do
        local post = f.posts[i]
        if physics.resolve_circle_post(b, post, b.post_restitution) then
            -- Amortecimento de spin na trave (x0.5)
            local wd = (cfg.spin and cfg.spin.wall_damping) or 0.5
            if b.spin_x then b.spin_x = b.spin_x * wd end
            if b.spin_y then b.spin_y = b.spin_y * wd end
        end
        for j = 1, num_p do
            physics.resolve_circle_post(players[j], post, 0.2)
        end
    end

    -- 7. Colisões da bola com paredes e redes
    for i = 1, #f.walls do
        local wall = f.walls[i]
        if physics.resolve_circle_segment(b, wall, b.wall_restitution) then
            -- Amortecimento de spin na parede (x0.5)
            local wd = (cfg.spin and cfg.spin.wall_damping) or 0.5
            if b.spin_x then b.spin_x = b.spin_x * wd end
            if b.spin_y then b.spin_y = b.spin_y * wd end
        end
    end

    -- 8. Jogadores podem sair das linhas, mas ficam contidos pelas quatro paredes externas.
    for i = 1, #f.outer_walls do
        local wall = f.outer_walls[i]
        for j = 1, num_p do
            physics.resolve_circle_segment(players[j], wall, 0.1)
        end
    end

    -- 9. Detecção de Gol (apenas quando a bola cruza a linha inteira)
    if not g.is_goal_delay then
        -- Gol no lado esquerdo -> Ponto para Azul (P2)
        if (b.x + b.radius < f.left) and (b.y >= f.goal_top and b.y <= f.goal_bottom) then
            g.score_p2 = g.score_p2 + 1
            g.is_goal_delay = true
            g.goal_delay_timer = cfg.game.goal_reset_delay
            g.last_scorer = "p2"
        -- Gol no lado direito -> Ponto para Vermelho (P1)
        elseif (b.x - b.radius > f.right) and (b.y >= f.goal_top and b.y <= f.goal_bottom) then
            g.score_p1 = g.score_p1 + 1
            g.is_goal_delay = true
            g.goal_delay_timer = cfg.game.goal_reset_delay
            g.last_scorer = "p1"
        end
    end
end

-- Atualização da camada de apresentação (posse e linha de trajetória com zero alocações)
function game.update_presentation(g)
    local cfg = g.config
    local b = g.ball
    local players = g.players

    -- Determina qual jogador está na posse da bola
    g.possessor_player = nil
    local min_dist_sq = 9999999

    for i = 1, #players do
        local p = players[i]
        local dx = b.x - p.x
        local dy = b.y - p.y
        local dist_sq = dx * dx + dy * dy
        local max_dist = p.radius + b.radius + p.kick_margin

        if dist_sq <= max_dist * max_dist and dist_sq < min_dist_sq then
            min_dist_sq = dist_sq
            g.possessor_player = p
        end
    end

    -- Se há jogador na posse e o jogo não está pausado por gol, calcula trajetória prevista
    if g.possessor_player and (not g.is_goal_delay) then
        local p = g.possessor_player
        local sb = g.scratch_ball
        local pts = g.trajectory_points
        local max_ticks = (cfg.trajectory and cfg.trajectory.max_ticks) or 120
        local max_bounces = (cfg.trajectory and cfg.trajectory.max_bounces) or 2

        -- 1. Inicializa a bola de rascunho na posição atual
        sb.x = b.x
        sb.y = b.y
        sb.radius = b.radius
        sb.mass = b.mass
        sb.damping = b.damping
        sb.max_speed = b.max_speed
        sb.wall_restitution = b.wall_restitution
        sb.post_restitution = b.post_restitution

        -- 2. Direção e força do chute hipotético com penalidade de potência
        local dx = b.x - p.x
        local dy = b.y - p.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local dir_x = (dist > 0.0001) and (dx / dist) or 1
        local dir_y = (dist > 0.0001) and (dy / dist) or 0

        local sx = p.spin_x or 0
        local sy = p.spin_y or 0
        local offset_sq = sx * sx + sy * sy
        if offset_sq > 1 then offset_sq = 1 end
        local offset = math.sqrt(offset_sq)

        local max_penalty = (cfg.spin and cfg.spin.max_power_penalty) or 0.15
        local power_factor = 1.0 - (offset * max_penalty)
        local effective_kick = p.kick_strength * power_factor

        sb.vx = dir_x * effective_kick + p.vx * p.kick_player_speed_ratio
        sb.vy = dir_y * effective_kick + p.vy * p.kick_player_speed_ratio
        sb.spin_x = sx
        sb.spin_y = sy

        -- 3. Simula passos da trajetória reutilizando a mesma rotina física
        local recorded = 0
        local bounces = 0

        for step = 1, max_ticks do
            local bounce, is_goal = physics.simulate_ball_tick(sb, cfg.fixed_dt, g.field, cfg.spin)
            recorded = step
            pts[step].x = sb.x
            pts[step].y = sb.y

            if bounce then
                bounces = bounces + 1
                if bounces >= max_bounces then break end
            end
            if is_goal then break end
        end

        g.trajectory_count = recorded
    else
        g.trajectory_count = 0
    end
end

function game.draw(g, show_colliders, alpha)
    alpha = alpha or 1
    local colors = g.config.colors
    local cfg = g.config

    -- 1. Campo, traves e redes
    field_mod.draw(g.field, colors, cfg)
    if show_colliders then
        field_mod.draw_colliders(g.field, colors, cfg)
    end

    -- 2. Linha de trajetória pontilhada (apenas para o jogador na posse)
    if g.trajectory_count > 0 and g.possessor_player then
        local pts = g.trajectory_points
        local count = g.trajectory_count
        local stride = (cfg.trajectory and cfg.trajectory.step_stride) or 2

        for i = 1, count, stride do
            local pt = pts[i]
            local alpha = (1.0 - (i / count) * 0.85)
            love.graphics.setColor(1.0, 1.0, 0.35, alpha * 0.8)
            love.graphics.circle("fill", pt.x, pt.y, 2.2)
        end
    end

    -- 3. Jogadores
    for i = 1, #g.players do
        local p = g.players[i]
        p:draw(colors, p.prev_x + (p.x - p.prev_x) * alpha, p.prev_y + (p.y - p.prev_y) * alpha)
    end

    -- 4. Bola
    g.ball:draw(colors, g.ball.prev_x + (g.ball.x - g.ball.prev_x) * alpha,
                g.ball.prev_y + (g.ball.y - g.ball.prev_y) * alpha)
end

return game
