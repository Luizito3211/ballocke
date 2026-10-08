-- Quadra RS. A origem (0, 0) é o centro; linhas e paredes são simétricas.
local field = {}

local function add_wall(list, x1, y1, x2, y2, nx, ny, kind)
    list[#list + 1] = {
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        nx = nx, ny = ny, kind = kind,
    }
end

function field.new(cfg)
    local f = {}
    f.config = cfg
    f.play_width = cfg.play_width
    f.play_height = cfg.play_height
    f.half_width = cfg.play_width * 0.5
    f.half_height = cfg.play_height * 0.5
    f.outer_width = cfg.play_width + cfg.containment_margin * 2
    f.outer_height = cfg.play_height + cfg.containment_margin * 2
    f.left = -f.half_width
    f.right = f.half_width
    f.top = -f.half_height
    f.bottom = f.half_height
    f.outer_left = -f.outer_width * 0.5
    f.outer_right = f.outer_width * 0.5
    f.outer_top = -f.outer_height * 0.5
    f.outer_bottom = f.outer_height * 0.5
    f.cx = 0
    f.cy = 0
    f.goal_top = -cfg.goal_mouth_width * 0.5
    f.goal_bottom = cfg.goal_mouth_width * 0.5
    f.goal_depth = cfg.goal_depth
    f.goal_back_left = f.left - cfg.goal_depth
    f.goal_back_right = f.right + cfg.goal_depth
    f.center_radius = cfg.center_circle_radius
    f.post_radius = cfg.post_radius
    f.posts = {
        { x = f.left, y = f.goal_top, radius = cfg.post_radius, kind = "post" },
        { x = f.left, y = f.goal_bottom, radius = cfg.post_radius, kind = "post" },
        { x = f.right, y = f.goal_top, radius = cfg.post_radius, kind = "post" },
        { x = f.right, y = f.goal_bottom, radius = cfg.post_radius, kind = "post" },
    }

    f.walls = {}
    f.outer_walls = {}
    f.net_walls = {}
    local outer = f.outer_walls
    add_wall(outer, f.outer_left, f.outer_top, f.outer_right, f.outer_top, 0, 1, "boundary")
    add_wall(outer, f.outer_right, f.outer_top, f.outer_right, f.outer_bottom, -1, 0, "boundary")
    add_wall(outer, f.outer_right, f.outer_bottom, f.outer_left, f.outer_bottom, 0, -1, "boundary")
    add_wall(outer, f.outer_left, f.outer_bottom, f.outer_left, f.outer_top, 1, 0, "boundary")

    for i = 1, #outer do f.walls[#f.walls + 1] = outer[i] end

    local net = f.net_walls
    -- Laterais e fundo da rede esquerda; as normais apontam para dentro do gol.
    add_wall(net, f.left, f.goal_top, f.goal_back_left, f.goal_top, 0, 1, "net")
    add_wall(net, f.goal_back_left, f.goal_top, f.goal_back_left, f.goal_bottom, 1, 0, "net")
    add_wall(net, f.goal_back_left, f.goal_bottom, f.left, f.goal_bottom, 0, -1, "net")
    -- Laterais e fundo da rede direita.
    add_wall(net, f.right, f.goal_top, f.goal_back_right, f.goal_top, 0, 1, "net")
    add_wall(net, f.goal_back_right, f.goal_top, f.goal_back_right, f.goal_bottom, -1, 0, "net")
    add_wall(net, f.goal_back_right, f.goal_bottom, f.right, f.goal_bottom, 0, -1, "net")
    for i = 1, #net do f.walls[#f.walls + 1] = net[i] end

    return f
end

local function draw_net(f, cfg, left_side)
    local x1 = left_side and f.goal_back_left or f.right
    local x2 = left_side and f.left or f.goal_back_right
    local y1, y2 = f.goal_top, f.goal_bottom
    love.graphics.setColor(cfg.colors.goal_box)
    love.graphics.rectangle("fill", x1, y1, x2 - x1, y2 - y1)
    love.graphics.setColor(cfg.colors.lines)
    love.graphics.setLineWidth(cfg.field.goal_line_width)
    love.graphics.rectangle("line", x1, y1, x2 - x1, y2 - y1)

    local spacing = cfg.field.net_grid_spacing
    love.graphics.setColor(cfg.colors.lines[1], cfg.colors.lines[2], cfg.colors.lines[3], 0.28)
    for x = x1 + spacing, x2 - spacing, spacing do
        love.graphics.line(x, y1, x, y2)
    end
    for y = y1 + spacing, y2 - spacing, spacing do
        love.graphics.line(x1, y, x2, y)
    end
end

function field.draw(f, colors, cfg)
    local fc = cfg.field
    love.graphics.setColor(colors.pitch)
    love.graphics.rectangle("fill", f.left, f.top, f.play_width, f.play_height)

    draw_net(f, cfg, true)
    draw_net(f, cfg, false)

    love.graphics.setColor(colors.lines)
    love.graphics.setLineWidth(fc.pitch_line_width)
    love.graphics.rectangle("line", f.left, f.top, f.play_width, f.play_height)
    love.graphics.line(0, f.top, 0, f.bottom)
    love.graphics.circle("line", 0, 0, fc.center_circle_radius)
    love.graphics.circle("fill", 0, 0, fc.pitch_line_width)

    local area_y = fc.penalty_area_width * 0.5
    local goal_area_y = fc.goal_area_width * 0.5
    local left_penalty_x = f.left + fc.penalty_area_depth
    local right_penalty_x = f.right - fc.penalty_area_depth
    local left_goal_x = f.left + fc.goal_area_depth
    local right_goal_x = f.right - fc.goal_area_depth
    love.graphics.setLineWidth(fc.goal_line_width)
    love.graphics.rectangle("line", f.left, -area_y, fc.penalty_area_depth, fc.penalty_area_width)
    love.graphics.rectangle("line", right_penalty_x, -area_y, fc.penalty_area_depth, fc.penalty_area_width)
    love.graphics.rectangle("line", f.left, -goal_area_y, fc.goal_area_depth, fc.goal_area_width)
    love.graphics.rectangle("line", right_goal_x, -goal_area_y, fc.goal_area_depth, fc.goal_area_width)
    love.graphics.circle("fill", f.left + fc.penalty_spot_distance, 0, fc.goal_line_width)
    love.graphics.circle("fill", f.right - fc.penalty_spot_distance, 0, fc.goal_line_width)

    local r = fc.corner_arc_radius
    local segments = fc.corner_arc_segments
    love.graphics.arc("line", f.left, f.top, r, 0, math.pi * 0.5, segments)
    love.graphics.arc("line", f.right, f.top, r, math.pi * 0.5, math.pi, segments)
    love.graphics.arc("line", f.right, f.bottom, r, math.pi, math.pi * 1.5, segments)
    love.graphics.arc("line", f.left, f.bottom, r, math.pi * 1.5, math.pi * 2, segments)

    love.graphics.setColor(colors.pitch_border)
    love.graphics.setLineWidth(fc.goal_line_width)
    love.graphics.rectangle("line", f.outer_left, f.outer_top, f.outer_width, f.outer_height)

    love.graphics.setColor(colors.posts)
    for i = 1, #f.posts do
        local p = f.posts[i]
        love.graphics.circle("fill", p.x, p.y, p.radius)
        love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
        love.graphics.circle("line", p.x, p.y, p.radius)
        love.graphics.setColor(colors.posts)
    end
end

function field.draw_colliders(f, colors, cfg)
    love.graphics.setLineWidth(cfg.field.debug_collider_line_width)
    for i = 1, #f.walls do
        local wall = f.walls[i]
        love.graphics.setColor(wall.kind == "boundary" and colors.collider_boundary or colors.collider_net)
        love.graphics.line(wall.x1, wall.y1, wall.x2, wall.y2)
    end
    love.graphics.setColor(colors.collider_post)
    love.graphics.setLineWidth(cfg.field.debug_post_line_width)
    for i = 1, #f.posts do
        local p = f.posts[i]
        love.graphics.circle("line", p.x, p.y, p.radius)
    end
end

return field
