-- src/physics.lua: Motor de física customizado, otimizado para passo fixo, zero GC e mecânica de curva
local physics = {}

-- Atualiza atrito/damping e limita velocidade máxima de uma entidade (escalar)
function physics.apply_damping_and_limit(entity, damping, max_speed)
    entity.vx = entity.vx * damping
    entity.vy = entity.vy * damping

    local speed_sq = entity.vx * entity.vx + entity.vy * entity.vy
    if speed_sq > max_speed * max_speed then
        local speed = math.sqrt(speed_sq)
        local inv_speed = max_speed / speed
        entity.vx = entity.vx * inv_speed
        entity.vy = entity.vy * inv_speed
    elseif speed_sq < 0.0001 then
        entity.vx = 0
        entity.vy = 0
    end
end

-- Aplica o efeito de curva (spinX) e variação de atrito (spinY) na bola
function physics.apply_spin_and_damping(ball, spin_config)
    spin_config = spin_config or {}
    local turn_rate = spin_config.max_turn_rate_per_tick or 0.020
    local decay = spin_config.decay or 0.985
    local top_factor = spin_config.top_spin_factor or 0.006
    local back_factor = spin_config.back_spin_factor or 0.018

    local speed_sq = ball.vx * ball.vx + ball.vy * ball.vy

    -- 1. Curva lateral (spinX): rotação angular da velocidade da bola
    -- spinX > 0 curva para a direita da direção do chute (sentido horário no espaço 2D)
    if (ball.spin_x and ball.spin_x ~= 0) and speed_sq > 0.0001 then
        local d_theta = ball.spin_x * turn_rate
        local cos_t = math.cos(d_theta)
        local sin_t = math.sin(d_theta)

        local new_vx = ball.vx * cos_t - ball.vy * sin_t
        local new_vy = ball.vx * sin_t + ball.vy * cos_t
        ball.vx = new_vx
        ball.vy = new_vy
    end

    -- 2. Efeito longitudinal (spinY): topo (cima) conserva velocidade, recuo (baixo) perde mais rápido
    local effective_damping = ball.damping
    if ball.spin_y and ball.spin_y ~= 0 then
        if ball.spin_y > 0 then
            effective_damping = effective_damping + ball.spin_y * top_factor
        else
            effective_damping = effective_damping - (-ball.spin_y) * back_factor
        end
    end

    -- Aplica atrito e limite de velocidade máxima
    physics.apply_damping_and_limit(ball, effective_damping, ball.max_speed)

    -- 3. Decaimento exponencial do spin por tick
    if ball.spin_x and ball.spin_x ~= 0 then
        ball.spin_x = ball.spin_x * decay
        if math.abs(ball.spin_x) < 0.0001 then ball.spin_x = 0 end
    end
    if ball.spin_y and ball.spin_y ~= 0 then
        ball.spin_y = ball.spin_y * decay
        if math.abs(ball.spin_y) < 0.0001 then ball.spin_y = 0 end
    end
end

-- Integra posição pelo dt fixo
function physics.integrate(entity, dt)
    entity.x = entity.x + entity.vx * dt
    entity.y = entity.y + entity.vy * dt
end

-- Resolução de colisão Círculo x Círculo com massas arbitrárias (ex: 2:1 entre jogador e bola)
function physics.resolve_circle_circle(c1, c2, restitution)
    local dx = c2.x - c1.x
    local dy = c2.y - c1.y
    local dist_sq = dx * dx + dy * dy
    local min_dist = c1.radius + c2.radius

    if dist_sq < min_dist * min_dist then
        local dist = math.sqrt(dist_sq)
        local nx, ny

        if dist > 0.0001 then
            nx = dx / dist
            ny = dy / dist
        else
            -- Tratamento para círculos concêntricos exatos (evita divisão por zero)
            nx = 1
            ny = 0
            dist = 0
        end

        local penetration = min_dist - dist

        -- Separação proporcional ao inverso das massas (evita penetração)
        local inv_m1 = 1 / c1.mass
        local inv_m2 = 1 / c2.mass
        local total_inv_m = inv_m1 + inv_m2

        local ratio1 = inv_m1 / total_inv_m
        local ratio2 = inv_m2 / total_inv_m

        c1.x = c1.x - nx * penetration * ratio1
        c1.y = c1.y - ny * penetration * ratio1
        c2.x = c2.x + nx * penetration * ratio2
        c2.y = c2.y + ny * penetration * ratio2

        -- Velocidade relativa ao longo da normal
        local rel_vx = c2.vx - c1.vx
        local rel_vy = c2.vy - c1.vy
        local vel_normal = rel_vx * nx + rel_vy * ny

        -- Se estiverem se aproximando, aplica impulso de restituição
        if vel_normal < 0 then
            local impulse = -(1 + restitution) * vel_normal / total_inv_m
            c1.vx = c1.vx - (impulse * inv_m1) * nx
            c1.vy = c1.vy - (impulse * inv_m1) * ny
            c2.vx = c2.vx + (impulse * inv_m2) * nx
            c2.vy = c2.vy + (impulse * inv_m2) * ny
        end
        return true
    end
    return false
end

-- Colisão Círculo x Trave (Poste estático: massa infinita, com prevenção de tunelamento além do centro)
function physics.resolve_circle_post(c, post, restitution)
    local dx = c.x - post.x
    local dy = c.y - post.y
    local dist_sq = dx * dx + dy * dy
    local min_dist = c.radius + post.radius

    if dist_sq < min_dist * min_dist then
        local dist = math.sqrt(dist_sq)
        local nx, ny

        if dist > 0.0001 then
            nx = dx / dist
            ny = dy / dist
        else
            nx = 0
            ny = 1
            dist = 0
        end

        -- Se a velocidade for alta e a entidade atravessou o centro do poste no frame,
        -- a normal geométrica inverte. Detectamos isso pela aproximação da velocidade:
        local vel_normal = c.vx * nx + c.vy * ny
        local speed_sq = c.vx * c.vx + c.vy * c.vy
        if vel_normal > 0 and speed_sq > 0.001 then
            local speed = math.sqrt(speed_sq)
            nx = -c.vx / speed
            ny = -c.vy / speed
            vel_normal = c.vx * nx + c.vy * ny
        end

        -- Posiciona a entidade na borda externa do poste
        c.x = post.x + nx * min_dist
        c.y = post.y + ny * min_dist

        if vel_normal < 0 then
            local factor = -(1 + restitution) * vel_normal
            c.vx = c.vx + factor * nx
            c.vy = c.vy + factor * ny
        end
        return true
    end
    return false
end

-- Colisão Círculo x Segmento de Reta com normal orientada para dentro (unilateral)
function physics.resolve_circle_segment(c, seg, restitution)
    local seg_vx = seg.x2 - seg.x1
    local seg_vy = seg.y2 - seg.y1
    local seg_len_sq = seg_vx * seg_vx + seg_vy * seg_vy

    if seg_len_sq < 0.000001 then return false end

    -- Projeção do centro do círculo sobre o segmento
    local c_vx = c.x - seg.x1
    local c_vy = c.y - seg.y1
    local t = (c_vx * seg_vx + c_vy * seg_vy) / seg_len_sq

    -- Clamping aos limites do segmento
    if t < 0 then t = 0 elseif t > 1 then t = 1 end

    local closest_x = seg.x1 + t * seg_vx
    local closest_y = seg.y1 + t * seg_vy

    local dx = c.x - closest_x
    local dy = c.y - closest_y

    -- Segmentos com normal unilateral (apontando para o interior)
    if seg.nx and seg.ny then
        local dist_along_normal = dx * seg.nx + dy * seg.ny

        if dist_along_normal < c.radius and dist_along_normal > -30 then
            if t > 0 and t < 1 then
                c.x = closest_x + seg.nx * c.radius
                c.y = closest_y + seg.ny * c.radius

                local vel_normal = c.vx * seg.nx + c.vy * seg.ny
                if vel_normal < 0 then
                    local factor = -(1 + restitution) * vel_normal
                    c.vx = c.vx + factor * seg.nx
                    c.vy = c.vy + factor * seg.ny
                end
                return true
            else
                local dist_sq = dx * dx + dy * dy
                if dist_sq < c.radius * c.radius then
                    local dist = math.sqrt(dist_sq)
                    local nx = (dist > 0.000001) and (dx / dist) or seg.nx
                    local ny = (dist > 0.000001) and (dy / dist) or seg.ny

                    c.x = closest_x + nx * c.radius
                    c.y = closest_y + ny * c.radius

                    local vel_normal = c.vx * nx + c.vy * ny
                    if vel_normal < 0 then
                        local factor = -(1 + restitution) * vel_normal
                        c.vx = c.vx + factor * nx
                        c.vy = c.vy + factor * ny
                    end
                    return true
                end
            end
        end
    else
        local dist_sq = dx * dx + dy * dy
        if dist_sq < c.radius * c.radius then
            local dist = math.sqrt(dist_sq)
            local nx = (dist > 0.000001) and (dx / dist) or 0
            local ny = (dist > 0.000001) and (dy / dist) or -1

            c.x = closest_x + nx * c.radius
            c.y = closest_y + ny * c.radius

            local vel_normal = c.vx * nx + c.vy * ny
            if vel_normal < 0 then
                local factor = -(1 + restitution) * vel_normal
                c.vx = c.vx + factor * nx
                c.vy = c.vy + factor * ny
            end
            return true
        end
    end

    return false
end

-- Simula um tick de física para a bola e colisões (reutilizado identicamente na linha de trajetória)
function physics.simulate_ball_tick(b, dt, field, spin_config)
    -- 1. Curva e atrito
    physics.apply_spin_and_damping(b, spin_config)

    -- 2. Movimento
    physics.integrate(b, dt)

    local is_bounce = false

    -- 3. Traves
    for i = 1, #field.posts do
        if physics.resolve_circle_post(b, field.posts[i], b.post_restitution) then
            is_bounce = true
        end
    end

    -- 4. Paredes
    for i = 1, #field.walls do
        if physics.resolve_circle_segment(b, field.walls[i], b.wall_restitution) then
            is_bounce = true
        end
    end

    -- 5. Amortecimento de spin no impacto com paredes/traves
    if is_bounce and spin_config then
        local wd = spin_config.wall_damping or 0.5
        if b.spin_x then b.spin_x = b.spin_x * wd end
        if b.spin_y then b.spin_y = b.spin_y * wd end
    end

    -- 6. Verificação de gol
    local is_goal = false
    if (b.x + b.radius < field.left and b.y >= field.goal_top and b.y <= field.goal_bottom) or
       (b.x - b.radius > field.right and b.y >= field.goal_top and b.y <= field.goal_bottom) then
        is_goal = true
    end

    return is_bounce, is_goal
end

-- Mecânica de Chute (Kick): impulso instantâneo com efeito (spin) e penalidade de potência
function physics.try_kick(player, ball, kick_margin, kick_strength, speed_ratio, spin_x, spin_y, spin_config)
    local dx = ball.x - player.x
    local dy = ball.y - player.y
    local dist_sq = dx * dx + dy * dy
    local max_kick_dist = player.radius + ball.radius + kick_margin

    if dist_sq <= max_kick_dist * max_kick_dist and dist_sq > 0.000001 then
        local dist = math.sqrt(dist_sq)
        local dir_x = dx / dist
        local dir_y = dy / dist

        -- Penalidade de potência conforme distância do centro do seletor
        spin_x = spin_x or 0
        spin_y = spin_y or 0
        local offset_sq = spin_x * spin_x + spin_y * spin_y
        if offset_sq > 1 then offset_sq = 1 end
        local offset = math.sqrt(offset_sq)

        local max_penalty = (spin_config and spin_config.max_power_penalty) or 0.15
        local power_factor = 1.0 - (offset * max_penalty)
        local effective_kick = kick_strength * power_factor

        ball.vx = dir_x * effective_kick + player.vx * (speed_ratio or 0)
        ball.vy = dir_y * effective_kick + player.vy * (speed_ratio or 0)

        -- Atribuição de efeito à bola
        ball.spin_x = spin_x
        ball.spin_y = spin_y

        return true
    end
    return false
end

return physics
