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

local function team_label(r, team)
    return r.config.referee.teamName[team] or string.upper(team or "")
end

local function restart_notice(r, kind, team, cause)
    local base = message_for(r.config, kind, team)
    if cause and cause ~= "" then return base .. ": " .. cause end
    return base
end

local function announce(r, message, team)
    r.decisionNotice = message
    r.noticeTimer = r.config.referee.decisionNoticeSeconds
    r.noticeTeam = team
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
        matchElapsed = 0, eventLog = nil, scoringTeam = nil,
        barrierEvacuationLogged = false,
        decisionNotice = "", noticeTimer = 0, noticeTeam = nil,
        restartBallTraveled = false,
    }
    set_frozen_ball(ball, 0, 0)
    return r
end

local function record(r, kind, old_state, new_state, reason)
    if r.eventLog then
        r.eventLog:record(r.matchElapsed, r.half, r.halfRemaining, kind,
            old_state, new_state, reason, r.ball.x, r.ball.y)
    end
end

function referee.attach_event_log(r, log)
    r.eventLog = log
    record(r, "ESTADO", "INÍCIO", r.state, "inicialização da partida")
end

function referee.record_reposition(r, subject, reason)
    record(r, subject == "bola" and "REPOSICIONAMENTO_BOLA" or "REPOSICIONAMENTO_JOGADORES",
        r.state, r.state, reason)
end

function referee.record_state_change(r, old_state, new_state, reason)
    record(r, "ESTADO", old_state, new_state, reason)
end

function referee.is_restart_state(state)
    return state == STATE_LATERAL or state == STATE_GOAL_KICK or
           state == STATE_CORNER or state == STATE_KICKOFF
end

function referee.begin_restart(r, kind, team, x, y, reason)
    local cfg, ball = r.config, r.ball
    local old_state, old_x, old_y = r.state, ball.x, ball.y
    local state
    if kind == "lateral" then state = STATE_LATERAL
    elseif kind == "goal_kick" then state = STATE_GOAL_KICK
    elseif kind == "corner" then state = STATE_CORNER
    else kind, state = "kickoff", STATE_KICKOFF end
    r.state, r.restartType, r.restartTeam = state, kind, team
    r.restartX, r.restartY = x, y
    r.restartRemaining = r.testShortRestarts and cfg.referee.testRestartTimeout or cfg.referee.restartTimeouts[kind]
    r.restartElapsed, r.noPlayerElapsed = 0, 0
    r.barrierEvacuationLogged = false
    r.restartEnteredField = false
    r.restartBallTraveled = false
    r.restartKickerId, r.noRetouch, r.restartKickerSeparated = nil, false, false
    r.lastTouchTeam, r.lastToucherId = team, nil
    r.ballFrozen = true
    r.message = message_for(cfg, kind, team)
    local notice
    if reason and (reason:find("TOQUE DUPLO", 1, true) == 1 or reason:find("COBRANÇA INCORRETA", 1, true) == 1) then
        notice = reason
    else
        notice = restart_notice(r, kind, team, reason)
    end
    announce(r, notice, team)
    set_frozen_ball(ball, x, y)
    record(r, "ESTADO", old_state, state, notice)
    if old_x ~= x or old_y ~= y then record(r, "REPOSICIONAMENTO_BOLA", state, state, notice) end
end

function referee.begin_play(r, kicker_id, reason)
    local old_state = r.state
    r.state = STATE_PLAY
    r.message = ""
    r.ballFrozen = false
    r.restartKickerId, r.restartKickerSeparated = kicker_id, false
    local rule = r.config.referee.doubleTouchRule
    local applies = rule == "all" or (rule == "restarts" and r.restartType ~= "kickoff")
    r.noRetouch = kicker_id ~= nil and applies
    r.restartBallTraveled = false
    r.restartEnteredField = false
    r.restartRemaining, r.restartElapsed, r.noPlayerElapsed = 0, 0, 0
    r.barrierEvacuationLogged = false
    record(r, "ESTADO", old_state, STATE_PLAY, reason or "cobrança executada")
    for i = 1, #r.players do r.players[i].barrierEscaping = false end
end

function referee.begin_goal(r, scoring_team)
    local old_state = r.state
    r.state = STATE_GOAL
    r.scoringTeam = scoring_team
    r.message = r.config.referee.messages.goal
    announce(r, r.message, scoring_team)
    r.stateTimer = r.config.game.goalCelebrationSeconds
    r.pendingKickoffTeam = other_team(scoring_team)
    r.ballFrozen = false
    r.restartKickerId, r.noRetouch, r.restartKickerSeparated = nil, false, false
    r.restartRemaining, r.restartElapsed, r.noPlayerElapsed = 0, 0, 0
    record(r, "ESTADO", old_state, STATE_GOAL, r.decisionNotice)
end

function referee.end_period(r)
    local old_state = r.state
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
    announce(r, r.message, nil)
    set_frozen_ball(r.ball, 0, 0)
    record(r, "ESTADO", old_state, r.state, r.decisionNotice)
    record(r, "REPOSICIONAMENTO_BOLA", r.state, r.state, r.decisionNotice)
end

function referee.start_second_half(r)
    r.half = 2
    r.redAttacksRight = not r.redAttacksRight
    r.halfDuration = r.testOneMinute and r.config.game.testHalfDuration or r.config.game.halfDuration
    r.halfRemaining = r.halfDuration
    r.regulationExpired = false
    r.graceRemaining = r.config.referee.regulationGrace
    referee.begin_restart(r, "kickoff", other_team(r.firstKickoffTeam), 0, 0, "início do 2º tempo após troca de lados")
end

function referee.reset_match(r)
    local old_state = r.state
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
    record(r, "ESTADO", old_state, STATE_WARMUP, "reinício solicitado pelo jogador")
end

function referee.note_touch(r, player)
    if r.noRetouch and player.id == r.restartKickerId then
        local dx, dy = r.ball.x - r.restartX, r.ball.y - r.restartY
        local grace = r.config.referee.doubleTouchGraceDistance
        if dx * dx + dy * dy > grace * grace then r.restartBallTraveled = true end
        return r.restartBallTraveled
    end
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
    local cause = "COBRANÇA INCORRETA"
    if r.restartBallTraveled then cause = "TOQUE DUPLO" end
    local notice = cause .. " - SAQUE PARA " .. team_label(r, team)
    referee.begin_restart(r, kind, team, x, y, notice)
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
        return "lateral", other_team(last), px, field.top, "bola cruzou linha lateral superior"
    elseif y - rad > field.bottom then
        local px = math.max(field.left + r.config.referee.cornerMargin,
                            math.min(field.right - r.config.referee.cornerMargin, x))
        if r.state == STATE_PLAY and r.restartKickerId and not r.restartEnteredField then
            return "lateral", other_team(r.restartTeam), r.restartX, r.restartY
        end
        return "lateral", other_team(last), px, field.bottom, "bola cruzou linha lateral inferior"
    end

    local side
    if x + rad < field.left then side = "left"
    elseif x - rad > field.right then side = "right"
    else return nil end

    local goal_team = goal_side_team(r, side)
    local goal_top = field.goal_top + field.post_radius + rad
    local goal_bottom = field.goal_bottom - field.post_radius - rad
    if y >= goal_top and y <= goal_bottom then return "goal", other_team(goal_team), x, y, "bola cruzou linha de gol" end

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
    return kind, kind == "goal_kick" and defending_team or attacking_team, place_x, place_y, "bola cruzou linha de fundo"
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
        referee.begin_play(r, nil, "timeout do saque inicial; bola liberada")
        return
    end
    referee.begin_restart(r, kind, team, x, y, "timeout da bola parada")
end

function referee.clock_tick(r, dt)
    r.matchElapsed = r.matchElapsed + dt
    r.noticeTimer = math.max(0, r.noticeTimer - dt)
    if r.state == STATE_GOAL then
        if not r.regulationExpired then
            r.halfRemaining = math.max(0, r.halfRemaining - dt)
            if r.halfRemaining <= 0 then r.regulationExpired = true; r.graceRemaining = r.config.referee.regulationGrace end
        end
        r.stateTimer = r.stateTimer - dt
        if r.stateTimer > 0 then return nil end
        if r.regulationExpired then referee.end_period(r); return "period_end" end
        referee.begin_restart(r, "kickoff", r.pendingKickoffTeam, 0, 0, "fim da comemoração do gol")
        return "goal_kickoff"
    end
    if r.state == STATE_WARMUP or r.state == STATE_INTERVAL then
        r.stateTimer = r.stateTimer - dt
        if r.stateTimer > 0 then return nil end
        if r.state == STATE_WARMUP then
            referee.begin_restart(r, "kickoff", r.firstKickoffTeam, 0, 0, "fim do aquecimento")
            return "restart"
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
    if r.restartType == "lateral" then
        local x1, x2, _, zone_top, zone_bottom = referee.throw_in_geometry(r)
        local min_x, max_x = x1 - p.radius - cfg.barrierMargin, x2 + p.radius + cfg.barrierMargin
        local min_y, max_y = zone_top - p.radius - cfg.barrierMargin,
                             zone_bottom + p.radius + cfg.barrierMargin
        if x >= min_x and x <= max_x and y >= min_y and y <= max_y then return true end
    elseif r.restartType == "corner" then
        local dx, dy = x - r.restartX, y - r.restartY
        local radius = cfg.cornerZoneRadius + p.radius + cfg.barrierMargin
        if dx * dx + dy * dy < radius * radius then return true end
    elseif r.restartType == "goal_kick" then
        local left_side = r.restartX < 0
        local margin = cfg.barrierMargin
        local min_x = left_side and f.left - p.radius - margin or f.right - field_cfg.penalty_area_depth - p.radius - margin
        local max_x = left_side and f.left + field_cfg.penalty_area_depth + p.radius + margin or f.right + p.radius + margin
        local half_y = field_cfg.penalty_area_width * 0.5 + p.radius + margin
        if x >= min_x and x <= max_x and y >= -half_y and y <= half_y then return true end
    elseif r.restartType == "kickoff" then
        local dx, dy = x - r.restartX, y - r.restartY
        local radius = f.center_radius + p.radius + cfg.barrierMargin
        if dx * dx + dy * dy < radius * radius then return true end
        local red_own_sign = r.redAttacksRight and -1 or 1
        local restart_own_sign = r.restartTeam == "red" and red_own_sign or -red_own_sign
        if p.team ~= r.restartTeam and x * restart_own_sign > -p.radius - cfg.barrierMargin then return true end
    end
    return false
end

function referee.throw_in_geometry(r)
    local f, cfg = r.field, r.config.referee
    local x1, x2 = f.outer_left, f.outer_right
    local line_y = r.restartY < 0 and f.top + cfg.throwInLineOffset or f.bottom - cfg.throwInLineOffset
    local zone_top = r.restartY < 0 and f.outer_top or line_y
    local zone_bottom = r.restartY < 0 and line_y or f.outer_bottom
    return x1, x2, line_y, zone_top, zone_bottom
end

function referee.is_point_restricted(r, p, x, y)
    if p.team == r.restartTeam then return false end
    return point_forbidden(r, p, x or p.x, y or p.y)
end

local function consider(r, p, x, y, best_x, best_y, best_d)
    if x < r.field.outer_left + p.radius or x > r.field.outer_right - p.radius or
       y < r.field.outer_top + p.radius or y > r.field.outer_bottom - p.radius then
        return best_x, best_y, best_d
    end
    if point_forbidden(r, p, x, y) then return best_x, best_y, best_d end
    local dx, dy = x - p.x, y - p.y
    local d = dx * dx + dy * dy
    if d < best_d then return x, y, d end
    return best_x, best_y, best_d
end

local function clear_of_frozen_ball(r, p, x, y, margin)
    if not r.ballFrozen then return true end
    local dx, dy = x - p.x, y - p.y
    local length_sq = dx * dx + dy * dy
    if length_sq < 0.000001 then return true end
    local t = ((r.ball.x - p.x) * dx + (r.ball.y - p.y) * dy) / length_sq
    t = math.max(0, math.min(1, t))
    local near_x, near_y = p.x + dx * t, p.y + dy * t
    local bx, by = near_x - r.ball.x, near_y - r.ball.y
    local clearance = p.radius + r.ball.radius + margin
    return bx * bx + by * by >= clearance * clearance
end

function referee.restriction_target(r, p)
    if not referee.is_restart_state(r.state) or p.team == r.restartTeam or
       not point_forbidden(r, p, p.x, p.y) then return p.x, p.y end
    local best_x, best_y, best_d = p.x, p.y, math.huge
    local f, cfg, field_cfg = r.field, r.config.referee, r.config.field
    if r.restartType == "lateral" then
        local x1, x2, _, zone_top, zone_bottom = referee.throw_in_geometry(r)
        local min_x, max_x = x1 + p.radius + cfg.barrierMargin, x2 - p.radius - cfg.barrierMargin
        local min_y, max_y = zone_top - p.radius - cfg.barrierMargin,
                             zone_bottom + p.radius + cfg.barrierMargin
        local inward_y = r.restartY < 0 and max_y + cfg.zoneTargetMargin or min_y - cfg.zoneTargetMargin
        local edge_x = math.max(min_x, math.min(max_x, p.x))
        if clear_of_frozen_ball(r, p, edge_x, inward_y, cfg.zoneTargetMargin) then
            best_x, best_y, best_d = consider(r, p, edge_x, inward_y, best_x, best_y, best_d)
        end
        local bypass = (p.radius + r.ball.radius + cfg.zoneTargetMargin + cfg.barrierMargin) *
            cfg.barrierEvacuationClearanceScale
        local alternate_x = math.max(min_x, math.min(max_x, p.x - bypass))
        if clear_of_frozen_ball(r, p, alternate_x, inward_y, cfg.zoneTargetMargin) then
            best_x, best_y, best_d = consider(r, p, alternate_x, inward_y, best_x, best_y, best_d)
        end
        alternate_x = math.max(min_x, math.min(max_x, p.x + bypass))
        if clear_of_frozen_ball(r, p, alternate_x, inward_y, cfg.zoneTargetMargin) then
            best_x, best_y, best_d = consider(r, p, alternate_x, inward_y, best_x, best_y, best_d)
        end
        if best_d == math.huge then
            best_x, best_y, best_d = consider(r, p, edge_x, inward_y, best_x, best_y, best_d)
        end
    elseif r.restartType == "corner" or r.restartType == "kickoff" then
        local radius = r.restartType == "kickoff" and f.center_radius or cfg.cornerZoneRadius
        radius = radius + p.radius + cfg.barrierMargin + cfg.zoneTargetMargin
        local radial_x, radial_y = p.x - r.restartX, p.y - r.restartY
        local radial_length = math.sqrt(radial_x * radial_x + radial_y * radial_y)
        if radial_length > 0.0001 then
            best_x, best_y, best_d = consider(r, p,
                r.restartX + radial_x / radial_length * radius,
                r.restartY + radial_y / radial_length * radius,
                best_x, best_y, best_d)
        end
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
            local edge_x = side_sign * (p.radius + cfg.barrierMargin + cfg.zoneTargetMargin)
            local edge_y = math.max(f.outer_top + p.radius,
                math.min(f.outer_bottom - p.radius, p.y))
            best_x, best_y, best_d = consider(r, p, edge_x, edge_y, best_x, best_y, best_d)
            edge_y = math.max(f.outer_top + p.radius,
                math.min(f.outer_bottom - p.radius, r.restartY + side_sign * (f.center_radius + p.radius + cfg.barrierMargin + cfg.zoneTargetMargin)))
            best_x, best_y, best_d = consider(r, p, edge_x, edge_y, best_x, best_y, best_d)
        end
    elseif r.restartType == "goal_kick" then
        local left_side = r.restartX < 0
        local margin = cfg.zoneTargetMargin
        local total_margin = p.radius + cfg.barrierMargin + margin
        local min_x = left_side and f.left - total_margin or f.right - field_cfg.penalty_area_depth - total_margin
        local max_x = left_side and f.left + field_cfg.penalty_area_depth + total_margin or f.right + total_margin
        local min_y, max_y = -field_cfg.penalty_area_width * 0.5 - total_margin,
                              field_cfg.penalty_area_width * 0.5 + total_margin
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
    if r.restartType == "lateral" then
        local x1, x2, line_y, zone_top, zone_bottom = referee.throw_in_geometry(r)
        love.graphics.rectangle("fill", x1, zone_top, x2 - x1, zone_bottom - zone_top)
        love.graphics.setColor(tint[1], tint[2], tint[3], cfg.referee.zoneLineAlpha)
        love.graphics.setLineWidth(cfg.referee.zoneLineWidth)
        love.graphics.line(x1, line_y, x2, line_y)
        local cap = cfg.referee.throwInLineEndMarkLength * 0.5
        love.graphics.line(x1, line_y - cap, x1, line_y + cap)
        love.graphics.line(x2, line_y - cap, x2, line_y + cap)
    elseif r.restartType == "corner" then
        love.graphics.circle("fill", r.restartX, r.restartY, cfg.referee.cornerZoneRadius)
        love.graphics.setColor(tint[1], tint[2], tint[3], cfg.referee.zoneLineAlpha)
        love.graphics.setLineWidth(cfg.referee.zoneLineWidth)
        love.graphics.circle("line", r.restartX, r.restartY, cfg.referee.cornerZoneRadius)
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
    local radius = cfg.frozenRingRadius + math.sin(pulse * cfg.frozenRingPulseRate) * cfg.frozenRingPulseAmplitude
    love.graphics.setColor(tint[1], tint[2], tint[3], cfg.frozenRingAlpha)
    love.graphics.setLineWidth(cfg.frozenRingLineWidth)
    love.graphics.circle("line", r.ball.x, r.ball.y, radius)
    love.graphics.setColor(tint[1], tint[2], tint[3], cfg.frozenRingFillAlpha)
    love.graphics.circle("fill", r.ball.x, r.ball.y, radius - 4)
end

return referee
