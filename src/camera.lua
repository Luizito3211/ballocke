-- Câmera local: cálculo escalar, sem tabelas temporárias durante a partida.
local camera = {}

function camera.new(cfg, field, width, height, viewport_width)
    viewport_width = viewport_width or 1280
    return {
        x = 0, y = 0, viewWidth = width or cfg.viewWidth,
        viewHeight = (width or cfg.viewWidth) * height / viewport_width,
        weight = cfg.weight, initialized = false, cfg = cfg, field = field,
    }
end

function camera.solve(cx, cy, px, py, width, height, field, padding, margin, radius, safe_fraction)
    local half_w, half_h = width * 0.5, height * 0.5
    local min_x = field.outer_left - padding + half_w
    local max_x = field.outer_right + padding - half_w
    local min_y = field.outer_top - padding + half_h
    local max_y = field.outer_bottom + padding - half_h
    if min_x > max_x then min_x, max_x = (min_x + max_x) * 0.5, (min_x + max_x) * 0.5 end
    if min_y > max_y then min_y, max_y = (min_y + max_y) * 0.5, (min_y + max_y) * 0.5 end
    cx = math.max(min_x, math.min(max_x, cx))
    cy = math.max(min_y, math.min(max_y, cy))

    -- Mantém o alvo dentro da margem da tela sempre que a geometria permitir.
    if px then
        local central_x = width * safe_fraction * 0.5 - (radius or 0)
        local central_y = height * safe_fraction * 0.5 - (radius or 0)
        local cmin_x, cmax_x = math.max(min_x, px - central_x), math.min(max_x, px + central_x)
        local cmin_y, cmax_y = math.max(min_y, py - central_y), math.min(max_y, py + central_y)
        if cmin_x <= cmax_x then cx = math.max(cmin_x, math.min(cmax_x, cx)) end
        if cmin_y <= cmax_y then cy = math.max(cmin_y, math.min(cmax_y, cy)) end
        local safe_half_x = half_w - width * margin - (radius or 0)
        local safe_half_y = half_h - width * margin - (radius or 0)
        cx = math.max(px - safe_half_x, math.min(px + safe_half_x, cx))
        cy = math.max(py - safe_half_y, math.min(py + safe_half_y, cy))
        cx = math.max(min_x, math.min(max_x, cx))
        cy = math.max(min_y, math.min(max_y, cy))
    end
    return cx, cy
end

function camera.update(c, player_x, player_y, ball_x, ball_y, dt)
    local cfg, f = c.cfg, c.field
    local width, height = c.viewWidth, c.viewHeight
    local tx, ty
    if player_x then
        tx = player_x + (ball_x - player_x) * c.weight
        ty = player_y + (ball_y - player_y) * c.weight
    else
        tx, ty = ball_x, ball_y
    end
    tx, ty = camera.solve(tx, ty, player_x, player_y, width, height, f,
                          cfg.cameraPadding, cfg.edgeMarginFraction, cfg.playerRadius, cfg.safeZoneFraction)
    if not c.initialized then
        c.x, c.y, c.initialized = tx, ty, true
    else
        local blend = 1 - math.exp(-cfg.damping * dt)
        c.x = c.x + (tx - c.x) * blend
        c.y = c.y + (ty - c.y) * blend
        c.x, c.y = camera.solve(c.x, c.y, player_x, player_y, width, height, f,
                                cfg.cameraPadding, cfg.edgeMarginFraction, cfg.playerRadius, cfg.safeZoneFraction)
    end
    c.x = math.floor(c.x + 0.5)
    c.y = math.floor(c.y + 0.5)
end

function camera.player_screen(c, x, y, vw, vh)
    local scale = vw / c.viewWidth
    return vw * 0.5 + (x - c.x) * scale, vh * 0.5 + (y - c.y) * scale
end

return camera
