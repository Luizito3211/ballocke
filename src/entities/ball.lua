-- src/entities/ball.lua: Entidade da bola (física pura, zero alocação e suporte a curva/spin)
local ball = {}

function ball.new(config, spawn_x, spawn_y)
    local b = {
        x = spawn_x,
        y = spawn_y,
        spawn_x = spawn_x,
        spawn_y = spawn_y,
        vx = 0,
        vy = 0,
        spin_x = 0,
        spin_y = 0,
        radius = config.ball.radius,
        mass = config.ball.mass,
        damping = config.ball.damping,
        max_speed = config.ball.max_speed,
        wall_restitution = config.ball.wall_restitution,
        post_restitution = config.ball.post_restitution,
        player_restitution = config.ball.player_restitution,
    }
    return setmetatable(b, { __index = ball })
end

function ball.reset(b)
    b.x = b.spawn_x
    b.y = b.spawn_y
    b.vx = 0
    b.vy = 0
    b.spin_x = 0
    b.spin_y = 0
end

-- Passo físico: rotação por spinX, amortecimento adaptativo por spinY e integração de posição
function ball.step_physics(b, dt, physics, spin_config)
    physics.apply_spin_and_damping(b, spin_config)
    physics.integrate(b, dt)
end

function ball.draw(b, colors)
    -- Sombra sutil da bola
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.circle("fill", b.x + 1.5, b.y + 1.5, b.radius)

    -- Corpo da bola
    love.graphics.setColor(colors.ball)
    love.graphics.circle("fill", b.x, b.y, b.radius)

    -- Borda escura
    love.graphics.setColor(colors.ball_outline)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", b.x, b.y, b.radius)

    -- Efeito visual do spin na bola (marcador sutil indicando a rotação ativa)
    if b.spin_x and b.spin_y and (math.abs(b.spin_x) > 0.05 or math.abs(b.spin_y) > 0.05) then
        love.graphics.setColor(0.9, 0.3, 0.3, 0.8)
        local dot_x = b.x + b.spin_x * (b.radius * 0.5)
        local dot_y = b.y - b.spin_y * (b.radius * 0.5)
        love.graphics.circle("fill", dot_x, dot_y, 2.5)
    end

    -- Ponto de luz interno procedural (efeito 3D suave)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.circle("fill", b.x - b.radius * 0.3, b.y - b.radius * 0.3, b.radius * 0.25)
end

return ball
