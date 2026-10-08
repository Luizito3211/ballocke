-- src/entities/player.lua: Entidade de jogador com suporte a comandos determinísticos e efeito (spin)
local player = {}

function player.new(data, config, spawn_x, spawn_y)
    local p = {
        id = data.id,
        name = data.name or data.id,
        team = data.team, -- "red" ou "blue"
        number = data.number or 1,
        keys = data.keys,
        spin_keys = data.spin_keys,
        color = data.color,
        inner_color = data.inner_color,
        x = spawn_x,
        y = spawn_y,
        spawn_x = spawn_x,
        spawn_y = spawn_y,
        vx = 0,
        vy = 0,
        spin_x = 0, -- Em [-1, 1], persiste entre chutes até intervenção do jogador
        spin_y = 0, -- Em [-1, 1], cima = topo, baixo = recuo
        radius = config.player.radius,
        mass = config.player.mass,
        damping = config.player.damping,
        acceleration = config.player.acceleration,
        max_speed = config.player.max_speed,
        restitution = config.player.restitution,
        kick_margin = config.player.kick_margin,
        kick_strength = config.player.kick_strength,
        kick_player_speed_ratio = config.player.kick_player_speed_ratio,
        is_kicking = false,
    }
    return setmetatable(p, { __index = player })
end

function player.reset(p)
    p.x = p.spawn_x
    p.y = p.spawn_y
    p.vx = 0
    p.vy = 0
    p.is_kicking = false
    -- Nota: spin_x e spin_y persistem propositalmente entre chutes conforme especificação
end

function player.set_spin(p, sx, sy)
    local len_sq = sx * sx + sy * sy
    if len_sq > 1.0 then
        local len = math.sqrt(len_sq)
        sx = sx / len
        sy = sy / len
    end
    p.spin_x = sx
    p.spin_y = sy
end

function player.reset_spin(p)
    p.spin_x = 0
    p.spin_y = 0
end

-- Passo físico determinístico dependente apenas de escalares passados por comando
function player.step_physics(p, dt, move_x, move_y, kick_pressed, spin_x, spin_y, physics, ball, spin_config)
    p.is_kicking = kick_pressed

    -- Atualiza spin registrado se fornecido pelo comando
    if spin_x then p.spin_x = spin_x end
    if spin_y then p.spin_y = spin_y end

    -- 1. Aceleração por input direcional
    if move_x ~= 0 or move_y ~= 0 then
        local len = math.sqrt(move_x * move_x + move_y * move_y)
        local inv_len = 1 / len
        local ax = (move_x * inv_len) * p.acceleration
        local ay = (move_y * inv_len) * p.acceleration
        p.vx = p.vx + ax * dt
        p.vy = p.vy + ay * dt
    end

    -- 2. Atrito e velocidade máxima aplicados uma única vez
    physics.apply_damping_and_limit(p, p.damping, p.max_speed)

    -- 3. Integração de posição
    physics.integrate(p, dt)

    -- 4. Ação de chute com aplicação do spin atual
    if kick_pressed and ball then
        physics.try_kick(p, ball, p.kick_margin, p.kick_strength, p.kick_player_speed_ratio, p.spin_x, p.spin_y, spin_config)
    end
end

function player.draw(p, colors)
    -- Sombra
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.circle("fill", p.x + 2, p.y + 2, p.radius)

    -- Glow/anel branco quando estiver chutando
    if p.is_kicking then
        love.graphics.setColor(colors.kicking_glow)
        love.graphics.circle("fill", p.x, p.y, p.radius + 3)
    end

    -- Disco externo principal
    love.graphics.setColor(p.color)
    love.graphics.circle("fill", p.x, p.y, p.radius)

    -- Contorno escuro
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", p.x, p.y, p.radius)

    -- Círculo interno (estilo HaxBall)
    love.graphics.setColor(p.inner_color)
    love.graphics.circle("fill", p.x, p.y, p.radius * 0.45)
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", p.x, p.y, p.radius * 0.45)
end

return player
