-- Árbitro determinístico: máquina de estados e regras puras compartilhadas pelo treino e pelo host.
local referee = {}

local STATE_WARMUP = "AQUECIMENTO"
local STATE_PLAY = "JOGO"
local STATE_LATERAL = "LATERAL"
local STATE_GOAL_KICK = "TIRO_DE_META"
local STATE_CORNER = "ESCANTEIO"
local STATE_KICKOFF = "SAQUE_INICIAL"
local STATE_GOAL = "GOL"
local STATE_INTERVAL = "INTERVALO"
local STATE_FINISHED = "FIM"

referee.STATE_WARMUP = STATE_WARMUP
referee.STATE_PLAY = STATE_PLAY
referee.STATE_LATERAL = STATE_LATERAL
referee.STATE_GOAL_KICK = STATE_GOAL_KICK
referee.STATE_CORNER = STATE_CORNER
referee.STATE_KICKOFF = STATE_KICKOFF
referee.STATE_GOAL = STATE_GOAL
referee.STATE_INTERVAL = STATE_INTERVAL
referee.STATE_FINISHED = STATE_FINISHED

local function other_team(team)
    if team == "red" then return "blue" end
    return "red"
end

local function message_for(cfg, kind, team)
    local key
    if kind == "lateral" then key = team == "red" and "lateralRed" or "lateralBlue"
    elseif kind == "goal_kick" then key = team == "red" and "goalKickRed" or "goalKickBlue"
    elseif kind == "corner" then key = team == "red" and "cornerRed" or "cornerBlue"
    else key = team == "red" and "kickoffRed" or "kickoffBlue" end
    return cfg.referee.messages[key]
end

local function set_frozen_ball(ball, x, y)
    ball.x, ball.y = x, y
    ball.prev_x, ball.prev_y = x, y
    ball.vx, ball.vy = 0, 0
    ball.spin_x, ball.spin_y = 0, 0
end

function referee.new(config, field, ball, players)
    local first = config.referee.firstKickoffTeam
    local r = {
        config = config, field = field, ball = ball, players = players,
        state = STATE_WARMUP, message = config.referee.messages.warmup,
        stateTimer = config.referee.warmupDuration,
        half = 1, halfRemaining = config.game.halfDuration,
        halfDuration = config.game.halfDuration, regulationExpired = false,
        graceRemaining = config.referee.regulationGrace,
        redAttacksRight = true, firstKickoffTeam = first,
        restartType = "kickoff", restartTeam = first,
        restartX = 0, restartY = 0, restartRemaining = 0,
        restartElapsed = 0, restartEnteredField = false,
        noPlayerElapsed = 0, ballFrozen = true,
        lastTouchTeam = nil, lastToucherId = nil,
        restartKickerId = nil, noRetouch = false, restartKickerSeparated = false,
        testShortRestarts = false, testOneMinute = false,
        displayedSeconds = -1,
    }
    set_frozen_ball(ball, 0, 0)
    return r
end

function referee.is_restart_state(state)
    return state == STATE_LATERAL or state == STATE_GOAL_KICK or
           state == STATE_CORNER or state == STATE_KICKOFF
end

function referee.begin_restart(r, kind, team, x, y)
    local cfg, ball = r.config, r.ball
    local state
    if kind == "lateral" then state = STATE_LATERAL
    elseif kind == "goal_kick" then state = STATE_GOAL_KICK
    elseif kind == "corner" then state = STATE_CORNER
    else kind, state = "kickoff", STATE_KICKOFF end
    r.state, r.restartType, r.restartTeam = state, kind, team
    r.restartX, r.restartY = x, y
    r.restartRemaining = r.testShortRestarts and cfg.referee.testRestartTimeout or cfg.referee.restartTimeouts[kind]
    r.restartElapsed, r.noPlayerElapsed = 0, 0
    r.restartEnteredField = false
    r.restartKickerId, r.noRetouch, r.restartKickerSeparated = nil, false, false
    r.lastTouchTeam, r.lastToucherId = team, nil
    r.ballFrozen = true
    r.message = message_for(cfg, kind, team)
    set_frozen_ball(ball, x, y)
end

function referee.begin_play(r, kicker_id)
    r.state = STATE_PLAY
    r.message = ""
    r.ballFrozen = false
    r.restartKickerId, r.restartKickerSeparated = kicker_id, false
    r.noRetouch = kicker_id ~= nil
    r.restartEnteredField = false
    r.restartRemaining, r.restartElapsed, r.noPlayerElapsed = 0, 0, 0
end

function referee.begin_goal(r, scoring_team)
    r.state = STATE_GOAL
    r.message = r.config.referee.messages.goal
    r.stateTimer = r.config.referee.goalPause
    r.pendingKickoffTeam = other_team(scoring_team)
    r.ballFrozen = true
    r.restartKickerId, r.noRetouch, r.restartKickerSeparated = nil, false, false
    r.restartRemaining, r.restartElapsed, r.noPlayerElapsed = 0, 0, 0
    set_frozen_ball(r.ball, 0, 0)
end

function referee.end_period(r)
    r.ballFrozen = true
    r.restartKickerId, r.noRetouch, r.restartKickerSeparated = nil, false, false
    r.restartRemaining, r.restartElapsed, r.noPlayerElapsed = 0, 0, 0
    r.stateTimer = r.config.referee.intermissionDuration
    if r.half == 1 then
        r.state = STATE_INTERVAL
        r.message = r.config.referee.messages.halftime
    else
        r.state = STATE_FINISHED
        r.message = r.config.referee.messages.fulltime
        r.stateTimer = 0
    end
    set_frozen_ball(r.ball, 0, 0)
end

function referee.start_second_half(r)
    r.half = 2
    r.redAttacksRight = not r.redAttacksRight
    r.halfDuration = r.testOneMinute and r.config.game.testHalfDuration or r.config.game.halfDuration
    r.halfRemaining = r.halfDuration
    r.regulationExpired = false
    r.graceRemaining = r.config.referee.regulationGrace
    referee.begin_restart(r, "kickoff", other_team(r.firstKickoffTeam), 0, 0)
end

function referee.reset_match(r)
    r.half = 1
    r.redAttacksRight = true
    r.firstKickoffTeam = r.config.referee.firstKickoffTeam
    r.halfDuration = r.testOneMinute and r.config.game.testHalfDuration or r.config.game.halfDuration
    r.halfRemaining = r.halfDuration
    r.regulationExpired = false
    r.graceRemaining = r.config.referee.regulationGrace
    r.state, r.message = STATE_WARMUP, r.config.referee.messages.warmup
    r.stateTimer = r.config.referee.warmupDuration
    r.restartType, r.restartTeam = "kickoff", r.firstKickoffTeam
    r.restartX, r.restartY = 0, 0
    r.restartRemaining, r.restartElapsed, r.noPlayerElapsed = 0, 0, 0
    r.restartEnteredField, r.ballFrozen = false, true
    r.lastTouchTeam, r.lastToucherId = nil, nil
    r.restartKickerId, r.noRetouch, r.restartKickerSeparated = nil, false, false
    r.pendingKickoffTeam = nil
    set_frozen_ball(r.ball, 0, 0)
end

function referee.note_touch(r, player)
    if r.noRetouch and player.id == r.restartKickerId then return true end
    r.lastTouchTeam = player.team
    r.lastToucherId = player.id
    if r.noRetouch and player.id ~= r.restartKickerId then r.noRetouch = false end
    return false
end

function referee.resolve_violation(r)
    local kind, team = r.restartType, other_team(r.restartTeam)
    local x, y = r.restartX, r.restartY
    if kind == "corner" then
        local side = x < 0 and "left" or "right"
        x = side == "left" and r.field.left + r.config.field.goal_area_depth * 0.5 or
            r.field.right - r.config.field.goal_area_depth * 0.5
        y = math.max(-r.config.field.goal_area_width * 0.5,
            math.min(r.config.field.goal_area_width * 0.5, y))
        kind = "goal_kick"
    elseif kind == "goal_kick" then
        local side = x < 0 and "left" or "right"
        x = side == "left" and r.field.left or r.field.right
        y = y < 0 and r.field.top or r.field.bottom
        kind = "corner"
    elseif kind == "kickoff" then kind, x, y = "kickoff", 0, 0
    else kind = "lateral" end
    referee.begin_restart(r, kind, team, x, y)
end

local function goal_side_team(r, side)
    if side == "right" then return r.redAttacksRight and "blue" or "red" end
    return r.redAttacksRight and "red" or "blue"
end

function referee.detect_exit(r, ball, field)
    local x, y, rad = ball.x, ball.y, ball.radius
    local last = r.lastTouchTeam or r.restartTeam or r.firstKickoffTeam
    if y + rad < field.top then
        local px = math.max(field.left + r.config.referee.cornerMargin,
                            math.min(field.right - r.config.referee.cornerMargin, x))
        if r.state == STATE_PLAY and r.restartKickerId and not r.restartEnteredField then
            return "lateral", other_team(r.restartTeam), r.restartX, r.restartY
        end
        return "lateral", other_team(last), px, field.top
    elseif y - rad > field.bottom then
        local px = math.max(field.left + r.config.referee.cornerMargin,
                            math.min(field.right - r.config.referee.cornerMargin, x))
        if r.state == STATE_PLAY and r.restartKickerId and not r.restartEnteredField then
            return "lateral", other_team(r.restartTeam), r.restartX, r.restartY
        end
        return "lateral", other_team(last), px, field.bottom
    end

    local side
    if x + rad < field.left then side = "left"
    elseif x - rad > field.right then side = "right"
    else return nil end

    local goal_team = goal_side_team(r, side)
    local goal_top = field.goal_top + field.post_radius + rad
    local goal_bottom = field.goal_bottom - field.post_radius - rad
    if y >= goal_top and y <= goal_bottom then return "goal", other_team(goal_team), x, y end

    if r.state == STATE_PLAY and r.restartKickerId and not r.restartEnteredField then
        if r.restartType == "corner" then return "goal_kick", other_team(r.restartTeam), r.restartX, r.restartY end
        if r.restartType == "goal_kick" then return "corner", other_team(r.restartTeam), r.restartX, r.restartY end
        if r.restartType == "kickoff" then return "kickoff", other_team(r.restartTeam), 0, 0 end
        return "lateral", other_team(r.restartTeam), r.restartX, r.restartY
    end

    local defending_team = goal_side_team(r, side)
    local attacking_team = other_team(defending_team)
    local kind = last == attacking_team and "goal_kick" or "corner"
    local place_x, place_y
    if kind == "corner" then
        place_x = side == "left" and field.left or field.right
        place_y = y < 0 and field.top or field.bottom
    else
        local depth = r.config.field.goal_area_depth * 0.5
        place_x = side == "left" and field.left + depth or field.right - depth
        local half = r.config.field.goal_area_width * 0.5
        place_y = math.max(-half, math.min(half, y))
    end
    return kind, kind == "goal_kick" and defending_team or attacking_team, place_x, place_y
end

function referee.record_field_entry(r, ball, field)
    if r.state ~= STATE_PLAY or not r.restartKickerId or r.restartEnteredField then return end
    if ball.x >= field.left and ball.x <= field.right and
       ball.y >= field.top and ball.y <= field.bottom then
        r.restartEnteredField = true
    end
end

function referee.timeout_restart(r)
    local kind, team = r.restartType, other_team(r.restartTeam)
    local x, y = r.restartX, r.restartY
    if kind == "corner" then
        local side = x < 0 and "left" or "right"
        local depth = r.config.field.goal_area_depth * 0.5
        x = side == "left" and r.field.left + depth or r.field.right - depth
        y = math.max(-r.config.field.goal_area_width * 0.5,
            math.min(r.config.field.goal_area_width * 0.5, y))
        kind = "goal_kick"
    elseif kind == "goal_kick" then
        local side = x < 0 and "left" or "right"
        x = side == "left" and r.field.left or r.field.right
        y = y < 0 and r.field.top or r.field.bottom
        kind = "corner"
    elseif kind == "kickoff" then
        referee.begin_play(r, nil)
        return
    end
    referee.begin_restart(r, kind, team, x, y)
end

function referee.clock_tick(r, dt)
    if r.state == STATE_WARMUP or r.state == STATE_GOAL or r.state == STATE_INTERVAL then
        r.stateTimer = r.stateTimer - dt
        if r.stateTimer > 0 then return nil end
        if r.state == STATE_WARMUP then
            referee.begin_restart(r, "kickoff", r.firstKickoffTeam, 0, 0)
            return "restart"
        elseif r.state == STATE_GOAL then
            referee.begin_restart(r, "kickoff", r.pendingKickoffTeam, 0, 0)
            return "goal_kickoff"
        elseif r.state == STATE_INTERVAL then
            return "second_half"
        end
    end

    if r.state == STATE_PLAY or referee.is_restart_state(r.state) then
        if not r.regulationExpired then
            r.halfRemaining = r.halfRemaining - dt
            if r.halfRemaining <= 0 then
                r.halfRemaining = 0
                r.regulationExpired = true
                r.graceRemaining = r.config.referee.regulationGrace
                if referee.is_restart_state(r.state) then referee.end_period(r); return "period_end" end
            end
        else
            r.graceRemaining = r.graceRemaining - dt
            if r.graceRemaining <= 0 then referee.end_period(r); return "period_end" end
        end
    end
    return nil
end

function referee.ball_stopped(r)
    if r.regulationExpired and (r.state == STATE_PLAY or referee.is_restart_state(r.state)) then
        referee.end_period(r)
        return true
    end
    return false
end

local function point_forbidden(r, p, x, y)
    local f, cfg, field_cfg = r.field, r.config.referee, r.config.field
    if x < f.outer_left + p.radius or x > f.outer_right - p.radius or
       y < f.outer_top + p.radius or y > f.outer_bottom - p.radius then return true end
    if r.restartType == "lateral" or r.restartType == "corner" then
        local dx, dy = x - r.restartX, y - r.restartY
        local radius = cfg.restartZoneRadius + p.radius
        if dx * dx + dy * dy < radius * radius then return true end
    elseif r.restartType == "goal_kick" then
        local left_side = r.restartX < 0
        local min_x = left_side and f.left - p.radius or f.right - field_cfg.penalty_area_depth - p.radius
        local max_x = left_side and f.left + field_cfg.penalty_area_depth + p.radius or f.right + p.radius
        local half_y = field_cfg.penalty_area_width * 0.5 + p.radius
        if x >= min_x and x <= max_x and y >= -half_y and y <= half_y then return true end
    elseif r.restartType == "kickoff" then
        local dx, dy = x - r.restartX, y - r.restartY
        local radius = f.center_radius + p.radius
        if dx * dx + dy * dy < radius * radius then return true end
        local red_own_sign = r.redAttacksRight and -1 or 1
        local restart_own_sign = r.restartTeam == "red" and red_own_sign or -red_own_sign
        if p.team ~= r.restartTeam and x * restart_own_sign > -p.radius then return true end
    end
    return false
end

local function consider(r, p, x, y, best_x, best_y, best_d)
    if point_forbidden(r, p, x, y) then return best_x, best_y, best_d end
    local dx, dy = x - p.x, y - p.y
    local d = dx * dx + dy * dy
    if d < best_d then return x, y, d end
    return best_x, best_y, best_d
end

function referee.restriction_target(r, p)
    if not referee.is_restart_state(r.state) or p.team == r.restartTeam or
       not point_forbidden(r, p, p.x, p.y) then return p.x, p.y end
    local best_x, best_y, best_d = p.x, p.y, math.huge
    local f, cfg, field_cfg = r.field, r.config.referee, r.config.field
    if r.restartType == "lateral" or r.restartType == "corner" or r.restartType == "kickoff" then
        local radius = r.restartType == "kickoff" and f.center_radius or cfg.restartZoneRadius
        radius = radius + p.radius + cfg.zoneTargetMargin
        local count = cfg.zoneDirections
        for i = 0, count - 1 do
            local angle = (i / count) * math.pi * 2
            local x = r.restartX + math.cos(angle) * radius
            local y = r.restartY + math.sin(angle) * radius
            best_x, best_y, best_d = consider(r, p, x, y, best_x, best_y, best_d)
        end
        if r.restartType == "kickoff" then
            local red_own_sign = r.redAttacksRight and -1 or 1
            local restart_own_sign = r.restartTeam == "red" and red_own_sign or -red_own_sign
            local side_sign = -restart_own_sign
            local edge_x = side_sign * (p.radius + cfg.zoneTargetMargin)
            local edge_y = math.max(f.outer_top + p.radius,
                math.min(f.outer_bottom - p.radius, p.y))
            best_x, best_y, best_d = consider(r, p, edge_x, edge_y, best_x, best_y, best_d)
            edge_y = math.max(f.outer_top + p.radius,
                math.min(f.outer_bottom - p.radius, r.restartY + side_sign * (f.center_radius + p.radius + cfg.zoneTargetMargin)))
            best_x, best_y, best_d = consider(r, p, edge_x, edge_y, best_x, best_y, best_d)
        end
    elseif r.restartType == "goal_kick" then
        local left_side = r.restartX < 0
        local margin = cfg.zoneTargetMargin
        local min_x = left_side and f.left - p.radius - margin or f.right - field_cfg.penalty_area_depth - p.radius - margin
        local max_x = left_side and f.left + field_cfg.penalty_area_depth + p.radius + margin or f.right + p.radius + margin
        local min_y, max_y = -field_cfg.penalty_area_width * 0.5 - p.radius - margin,
                              field_cfg.penalty_area_width * 0.5 + p.radius + margin
        local edge_y = math.max(min_y, math.min(max_y, p.y))
        best_x, best_y, best_d = consider(r, p, min_x, edge_y, best_x, best_y, best_d)
        best_x, best_y, best_d = consider(r, p, max_x, edge_y, best_x, best_y, best_d)
        local edge_x = math.max(min_x, math.min(max_x, p.x))
        best_x, best_y, best_d = consider(r, p, edge_x, min_y, best_x, best_y, best_d)
        best_x, best_y, best_d = consider(r, p, edge_x, max_y, best_x, best_y, best_d)
    end
    return best_x, best_y
end

function referee.has_team_player(players, team)
    for i = 1, #players do if players[i].team == team then return true end end
    return false
end

function referee.draw_zone(r, colors)
    if not referee.is_restart_state(r.state) then return end
    local f, cfg = r.field, r.config
    local tint = r.restartTeam == "red" and colors.score_p1 or colors.score_p2
    love.graphics.setColor(tint[1], tint[2], tint[3], cfg.referee.zoneFillAlpha)
    if r.restartType == "lateral" or r.restartType == "corner" then
        love.graphics.circle("fill", r.restartX, r.restartY, cfg.referee.restartZoneRadius)
        love.graphics.setColor(tint[1], tint[2], tint[3], cfg.referee.zoneLineAlpha)
        love.graphics.setLineWidth(cfg.referee.zoneLineWidth)
        love.graphics.circle("line", r.restartX, r.restartY, cfg.referee.restartZoneRadius)
    elseif r.restartType == "goal_kick" then
        local left_side = r.restartX < 0
        local x = left_side and f.left or f.right - cfg.field.penalty_area_depth
        love.graphics.rectangle("fill", x, -cfg.field.penalty_area_width * 0.5,
            cfg.field.penalty_area_depth, cfg.field.penalty_area_width)
    else
        love.graphics.circle("fill", 0, 0, f.center_radius)
        local red_own_sign = r.redAttacksRight and -1 or 1
        local own_sign = r.restartTeam == "red" and red_own_sign or -red_own_sign
        if own_sign < 0 then
            love.graphics.rectangle("fill", f.left, f.top, -f.left, f.play_height)
        else
            love.graphics.rectangle("fill", 0, f.top, f.right, f.play_height)
        end
    end
end

function referee.draw_frozen_ring(r, colors)
    if not r.ballFrozen or not referee.is_restart_state(r.state) then return end
    local tint = r.restartTeam == "red" and colors.score_p1 or colors.score_p2
    local pulse = love.timer.getTime()
    local cfg = r.config.referee
    local radius = r.ball.radius + cfg.frozenRingOffset + math.sin(pulse * cfg.frozenRingPulseRate) * cfg.frozenRingPulseAmplitude
    love.graphics.setColor(tint[1], tint[2], tint[3], cfg.frozenRingAlpha)
    love.graphics.setLineWidth(cfg.frozenRingLineWidth)
    love.graphics.circle("line", r.ball.x, r.ball.y, radius)
    love.graphics.setColor(tint[1], tint[2], tint[3], cfg.frozenRingFillAlpha)
    love.graphics.circle("fill", r.ball.x, r.ball.y, radius - 4)
end

return referee
