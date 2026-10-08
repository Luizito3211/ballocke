-- src/field.lua: Geometria do campo derivada integralmente do preset selecionado
local field = {}

function field.new(preset)
    local f = {}
    f.preset = preset
    f.virtual_width = preset.virtual_width
    f.virtual_height = preset.virtual_height

    -- Centro do campo nas coordenadas virtuais do preset
    local cx = preset.virtual_width / 2
    local cy = preset.virtual_height / 2 + 12 -- Espaço superior para o placar e HUD

    f.cx = cx
    f.cy = cy
    f.w = preset.width
    f.h = preset.height
    f.left = cx - preset.width / 2
    f.right = cx + preset.width / 2
    f.top = cy - preset.height / 2
    f.bottom = cy + preset.height / 2

    f.goal_top = cy - preset.goal_height / 2
    f.goal_bottom = cy + preset.goal_height / 2
    f.goal_w = preset.goal_width
    f.center_radius = preset.center_radius
    f.post_radius = preset.post_radius

    -- Traves circulares estáticas
    f.posts = {
        { x = f.left,  y = f.goal_top,    radius = f.post_radius },
        { x = f.left,  y = f.goal_bottom, radius = f.post_radius },
        { x = f.right, y = f.goal_top,    radius = f.post_radius },
        { x = f.right, y = f.goal_bottom, radius = f.post_radius },
    }

    -- Paredes perimetrais do campo e caixas de rede (normais para o interior)
    f.walls = {
        -- Paredes principais do campo (superior e inferior)
        { x1 = f.left,  y1 = f.top,    x2 = f.right, y2 = f.top,    nx = 0,  ny = 1 },
        { x1 = f.left,  y1 = f.bottom, x2 = f.right, y2 = f.bottom, nx = 0,  ny = -1 },

        -- Laterais esquerdas (acima e abaixo da trave esquerda)
        { x1 = f.left,  y1 = f.top,         x2 = f.left,  y2 = f.goal_top,    nx = 1,  ny = 0 },
        { x1 = f.left,  y1 = f.goal_bottom, x2 = f.left,  y2 = f.bottom,      nx = 1,  ny = 0 },

        -- Laterais direitas (acima e abaixo da trave direita)
        { x1 = f.right, y1 = f.top,         x2 = f.right, y2 = f.goal_top,    nx = -1, ny = 0 },
        { x1 = f.right, y1 = f.goal_bottom, x2 = f.right, y2 = f.bottom,      nx = -1, ny = 0 },

        -- Rede do Gol Esquerdo
        { x1 = f.left - f.goal_w, y1 = f.goal_top,    x2 = f.left,             y2 = f.goal_top,    nx = 0,  ny = 1 },
        { x1 = f.left - f.goal_w, y1 = f.goal_top,    x2 = f.left - f.goal_w, y2 = f.goal_bottom, nx = 1,  ny = 0 },
        { x1 = f.left - f.goal_w, y1 = f.goal_bottom, x2 = f.left,             y2 = f.goal_bottom, nx = 0,  ny = -1 },

        -- Rede do Gol Direito
        { x1 = f.right,            y1 = f.goal_top,    x2 = f.right + f.goal_w, y2 = f.goal_top,    nx = 0,  ny = 1 },
        { x1 = f.right + f.goal_w, y1 = f.goal_top,    x2 = f.right + f.goal_w, y2 = f.goal_bottom, nx = -1, ny = 0 },
        { x1 = f.right,            y1 = f.goal_bottom, x2 = f.right + f.goal_w, y2 = f.goal_bottom, nx = 0,  ny = -1 },
    }

    return f
end

-- Renderização procedural adaptativa ao preset
function field.draw(f, colors)
    -- Gramado
    love.graphics.setColor(colors.pitch)
    love.graphics.rectangle("fill", f.left, f.top, f.w, f.h)

    -- Caixas das redes dos gols
    love.graphics.setColor(colors.goal_box)
    love.graphics.rectangle("fill", f.left - f.goal_w, f.goal_top, f.goal_w, f.goal_bottom - f.goal_top)
    love.graphics.rectangle("fill", f.right, f.goal_top, f.goal_w, f.goal_bottom - f.goal_top)

    -- Linhas do campo
    love.graphics.setColor(colors.lines)
    love.graphics.setLineWidth(3)

    -- Contorno do campo
    love.graphics.rectangle("line", f.left, f.top, f.w, f.h)

    -- Meio-campo
    love.graphics.line(f.cx, f.top, f.cx, f.bottom)

    -- Círculo central
    love.graphics.circle("line", f.cx, f.cy, f.center_radius)
    love.graphics.circle("fill", f.cx, f.cy, 4)

    -- Redes dos gols
    love.graphics.setLineWidth(2)
    -- Gol Esquerdo
    love.graphics.line(f.left, f.goal_top, f.left - f.goal_w, f.goal_top)
    love.graphics.line(f.left - f.goal_w, f.goal_top, f.left - f.goal_w, f.goal_bottom)
    love.graphics.line(f.left - f.goal_w, f.goal_bottom, f.left, f.goal_bottom)

    -- Gol Direito
    love.graphics.line(f.right, f.goal_top, f.right + f.goal_w, f.goal_top)
    love.graphics.line(f.right + f.goal_w, f.goal_top, f.right + f.goal_w, f.goal_bottom)
    love.graphics.line(f.right + f.goal_w, f.goal_bottom, f.right, f.goal_bottom)

    -- Traves (postes estáticos)
    love.graphics.setColor(colors.posts)
    for i = 1, #f.posts do
        local p = f.posts[i]
        love.graphics.circle("fill", p.x, p.y, p.radius)
        love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
        love.graphics.circle("line", p.x, p.y, p.radius)
        love.graphics.setColor(colors.posts)
    end
end

return field
