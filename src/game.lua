-- src/game.lua: Regras, simulação determinística, N jogadores e previsão de trajetória
local game = {}
local physics = require "src.physics"
local field_mod = require "src.field"
local player_mod = require "src.entities.player"
local ball_mod = require "src.entities.ball"
local input_mod = require "src.input"
local camera_mod = require "src.camera"
local referee_mod = require "src.referee"

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
    g.referee = referee_mod.new(cfg, g.field, g.ball, g.players)
    if g.camera then g.camera.field = g.field; g.camera.initialized = false end
end

-- Reinicia posições para o início da jogada (kick-off)
function game.reset_positions(g, swap_sides, reason)
    if swap_sides then
        for i = 1, #g.players do g.players[i].spawn_x = -g.players[i].spawn_x end
    end
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
    if g.referee and g.referee.eventLog then
        referee_mod.record_reposition(g.referee, "bola", reason or "reposicionamento de jogadores/bola")
        referee_mod.record_reposition(g.referee, "jogadores", reason or "reposicionamento de jogadores/bola")
    end
end

-- Reinicia partida inteira (placar zerado)
function game.reset_match(g)
    g.score_p1 = 0
    g.score_p2 = 0
    g:reset_positions(false, "reinício solicitado pelo jogador")
    referee_mod.reset_match(g.referee)
end

local function resolve_frozen_ball_player(p, ball)
    local dx, dy = p.x - ball.x, p.y - ball.y
    local min_distance = p.radius + ball.radius
    local distance_sq = dx * dx + dy * dy
    if distance_sq >= min_distance * min_distance then return end
    local distance, nx, ny
    if distance_sq > 0.000001 then
        distance = math.sqrt(distance_sq)
        nx, ny = dx / distance, dy / distance
    else
        distance, nx, ny = 0, 1, 0
    end
    p.x = ball.x + nx * min_distance
    p.y = ball.y + ny * min_distance
    local into_obstacle = p.vx * nx + p.vy * ny
    if into_obstacle < 0 then
        p.vx = p.vx - nx * into_obstacle
        p.vy = p.vy - ny * into_obstacle
    end
end

local function evacuating_from_barrier(r, p)
    return referee_mod.is_restart_state(r.state) and p.team ~= r.restartTeam and
        referee_mod.is_point_restricted(r, p, p.x, p.y)
end

local function record_goal(g, scoring_team)
    if scoring_team == "red" then
        g.score_p1 = g.score_p1 + 1
        g.last_scorer = "p1"
    else
        g.score_p2 = g.score_p2 + 1
        g.last_scorer = "p2"
    end
    g.is_goal_delay = true
    g.goal_delay_timer = g.config.game.goalCelebrationSeconds
    referee_mod.begin_goal(g.referee, scoring_team)
end

-- Passo fixo de jogo e arbitragem. Todas as coleções usadas aqui são pré-alocadas.
function game.step_fixed(g, dt, commands)
    local cfg, f, b, r = g.config, g.field, g.ball, g.referee
    local players, num_p = g.players, #g.players
    commands = commands or g.commands
    b.prev_x, b.prev_y = b.x, b.y
    for i = 1, num_p do players[i].prev_x, players[i].prev_y = players[i].x, players[i].y end

    local was_celebrating = r.state == referee_mod.STATE_GOAL
    local transition = referee_mod.clock_tick(r, dt)
    if transition == "second_half" then
        g:reset_positions(true, "troca de lados no intervalo")
        referee_mod.start_second_half(r)
    elseif transition == "goal_kickoff" then
        if cfg.game.kickOffReset == "full" then g:reset_positions(false, "reposicionamento kickOffReset após comemoração") end
        g.is_goal_delay = false
        g.goal_delay_timer = 0
    elseif transition == "period_end" then
        if was_celebrating and cfg.game.kickOffReset == "full" then
            g:reset_positions(false, "reposicionamento kickOffReset após fim de tempo")
        end
        g.is_goal_delay = false
        return
    end

    if r.state == referee_mod.STATE_WARMUP or
       r.state == referee_mod.STATE_INTERVAL or r.state == referee_mod.STATE_FINISHED then
        g.is_goal_delay = false
        g.goal_delay_timer = 0
        return
    end

    local celebration = r.state == referee_mod.STATE_GOAL

    local frozen_at_start = r.ballFrozen
    if referee_mod.is_restart_state(r.state) then
        r.restartElapsed = r.restartElapsed + dt
        if not referee_mod.has_team_player(players, r.restartTeam) then
            r.noPlayerElapsed = r.noPlayerElapsed + dt
            if r.noPlayerElapsed >= cfg.referee.noPlayerAutoRelease then
                referee_mod.begin_play(r, nil, "time da cobrança sem jogadores por 2 segundos")
                frozen_at_start = false
            end
        end
        if r.ballFrozen and r.restartRemaining > 0 then
            r.restartRemaining = r.restartRemaining - dt
            if r.restartRemaining <= 0 then
                referee_mod.timeout_restart(r)
                if referee_mod.ball_stopped(r) then return end
                frozen_at_start = r.ballFrozen
            end
        end
    end

    local illegal_touch = false
    if frozen_at_start then
        for i = 1, num_p do
            local p, cmd = players[i], commands[i]
            p:step_physics(dt, cmd.moveX, cmd.moveY, false, cmd.spinX, cmd.spinY,
                           physics, nil, cfg.spin)
            if not evacuating_from_barrier(r, p) then resolve_frozen_ball_player(p, b) end
        end

        -- Apenas um jogador do time autorizado pode liberar a bola com chute.
        for i = 1, num_p do
            local p, cmd = players[i], commands[i]
            if p.team == r.restartTeam and cmd.kick then
                if physics.try_kick(p, b, p.kick_margin, p.kick_strength,
                    p.kick_player_speed_ratio, p.spin_x, p.spin_y, cfg.spin) then
                    p.is_kicking = true
                    referee_mod.begin_play(r, p.id)
                    r.lastTouchTeam, r.lastToucherId = p.team, p.id
                    frozen_at_start = false
                    b:step_physics(dt, physics, cfg.spin)
                    break
                end
            end
        end
    else
        for i = 1, num_p do
            local p, cmd = players[i], commands[i]
            local kicked = p:step_physics(dt, cmd.moveX, cmd.moveY, cmd.kick,
                cmd.spinX, cmd.spinY, physics, b, cfg.spin)
            if kicked and referee_mod.note_touch(r, p) then illegal_touch = true end
        end
        b:step_physics(dt, physics, cfg.spin)
    end

    for i = 1, g.num_player_pairs do
        local pair = g.player_pairs[i]
        physics.resolve_circle_circle(pair.p1, pair.p2, pair.p1.restitution)
    end

        if frozen_at_start then
            for i = 1, num_p do
                if not evacuating_from_barrier(r, players[i]) then resolve_frozen_ball_player(players[i], b) end
            end
        end

    if not frozen_at_start then
        if r.noRetouch and r.restartKickerId then
            local initial_player
            for i = 1, num_p do
                if players[i].id == r.restartKickerId then initial_player = players[i]; break end
            end
            if initial_player then
                local dx, dy = b.x - initial_player.x, b.y - initial_player.y
                local contact = initial_player.radius + b.radius + cfg.referee.restartTouchSeparationPadding
                if dx * dx + dy * dy > contact * contact then r.restartKickerSeparated = true end
            end
        end
        for i = 1, num_p do
            local p = players[i]
            if physics.resolve_circle_circle(p, b, b.player_restitution) then
                if r.noRetouch and p.id == r.restartKickerId and not r.restartKickerSeparated then
                    -- O contato do chute inicial ainda não é um segundo toque.
                elseif referee_mod.note_touch(r, p) then
                    illegal_touch = true
                end
            end
        end
    end

    for i = 1, #f.posts do
        local post = f.posts[i]
        if not frozen_at_start and physics.resolve_circle_post(b, post, b.post_restitution) then
            local wd = cfg.spin.wall_damping
            b.spin_x, b.spin_y = b.spin_x * wd, b.spin_y * wd
        end
        for j = 1, num_p do physics.resolve_circle_post(players[j], post, 0.2) end
    end

    if not frozen_at_start then
        for i = 1, #f.walls do
            local wall = f.walls[i]
            if physics.resolve_circle_segment(b, wall, b.wall_restitution) then
                local wd = cfg.spin.wall_damping
                b.spin_x, b.spin_y = b.spin_x * wd, b.spin_y * wd
            end
        end
    end
    for i = 1, #f.outer_walls do
        local wall = f.outer_walls[i]
        for j = 1, num_p do physics.resolve_circle_segment(players[j], wall, 0.1) end
    end

    if celebration then
        -- A física segue ativa durante a comemoração; o árbitro ignora gols e saídas.
    elseif illegal_touch and not frozen_at_start then
        referee_mod.resolve_violation(r)
        if referee_mod.ball_stopped(r) then return end
    elseif not frozen_at_start then
        referee_mod.record_field_entry(r, b, f)
        local kind, team, place_x, place_y, reason = referee_mod.detect_exit(r, b, f)
        if kind == "goal" then
            record_goal(g, team)
        elseif kind then
            referee_mod.begin_restart(r, kind, team, place_x, place_y, reason)
            if referee_mod.ball_stopped(r) then return end
        end
    end

    -- A barreira é resolvida por último, depois dos contatos com jogadores, bola e paredes.
    if referee_mod.is_restart_state(r.state) then
        local evacuated_inside = false
        for i = 1, num_p do
            local p = players[i]
            if p.team ~= r.restartTeam and referee_mod.is_point_restricted(r, p, p.x, p.y) then
                local was_inside = referee_mod.is_point_restricted(r, p, p.prev_x, p.prev_y)
                if was_inside and not r.barrierEvacuationLogged then evacuated_inside = true end
                local tx, ty = referee_mod.restriction_target(r, p)
                local dx, dy = tx - p.x, ty - p.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 0.0001 then
                    if was_inside then
                        local step = math.min(dist, cfg.referee.barrierEvacuationSpeed * dt)
                        p.x, p.y = p.x + dx / dist * step, p.y + dy / dist * step
                    else
                        p.x, p.y = tx, ty
                    end
                    local into = p.vx * dx + p.vy * dy
                    if into < 0 then p.vx, p.vy = p.vx - dx / dist * into / dist, p.vy - dy / dist * into / dist end
                end
            end
        end
        if evacuated_inside then
            referee_mod.record_reposition(r, "jogadores", "evacuação suave ao surgir a barreira da bola parada")
            r.barrierEvacuationLogged = true
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
    if g.possessor_player and g.possessor_player.allow_spin and (not g.is_goal_delay) then
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
    referee_mod.draw_zone(g.referee, colors)
    if show_colliders then
        field_mod.draw_colliders(g.field, colors, cfg)
    end

    -- 2. Linha de trajetória pontilhada (apenas para o jogador na posse)
    if g.trajectory_count > 0 and g.possessor_player and g.possessor_player.allow_spin then
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
    referee_mod.draw_frozen_ring(g.referee, colors)
end

return game
