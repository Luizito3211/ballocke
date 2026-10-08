-- Ajustes temporários de treino. Não modifica config.lua nem seus padrões.
local calibration = {}

function calibration.new(config, game, without_graphics)
    local c = config.calibration
    local state = {
        open = false, selected = 1,
        accelerationFactor = c.accelerationFactor, kickFactor = c.kickFactor,
        ballDamping = config.ball.damping, playerDamping = config.player.damping,
        viewWidth = config.camera.viewWidth, cameraWeight = config.camera.weight,
        text = {}, metric_text = {}, config = config, game = game,
    }
    if not without_graphics then
        state.font = love.graphics.newFont(16)
        for i = 1, 7 do state.text[i] = love.graphics.newText(state.font, "") end
        for i = 1, 3 do state.metric_text[i] = love.graphics.newText(state.font, "") end
    end
    setmetatable(state, { __index = calibration })
    state:apply()
    state:refresh()
    return state
end

function calibration.apply(s)
    local cfg, g = s.config, s.game
    for i = 1, #g.players do
        local p = g.players[i]
        p.acceleration = cfg.player.acceleration * s.accelerationFactor
        p.max_speed = cfg.player.max_speed
        p.damping = s.playerDamping
        p.kick_strength = cfg.player.kick_strength * s.kickFactor
    end
    g.ball.damping = s.ballDamping
    g.scratch_ball.damping = s.ballDamping
    g.camera.viewWidth = s.viewWidth
    g.camera.viewHeight = s.viewWidth * cfg.viewport.height / cfg.viewport.width
    g.camera.weight = s.cameraWeight
end

function calibration.metrics(s)
    local cfg = s.config
    local acceleration = cfg.player.acceleration * s.accelerationFactor
    local player_speed = math.min(cfg.player.max_speed,
        acceleration * cfg.fixed_dt * s.playerDamping / math.max(1 - s.playerDamping, 0.0001))
    local kick_speed = math.min(cfg.ball.max_speed, cfg.player.kick_strength * s.kickFactor)
    local vx, ticks, distance = 0, 0, 0
    local target = cfg.field.play_width
    while distance < target and ticks < 36000 do
        vx = (vx + acceleration * cfg.fixed_dt) * s.playerDamping
        if vx > player_speed then vx = player_speed end
        distance = distance + vx * cfg.fixed_dt
        ticks = ticks + 1
    end
    local travel_time = ticks * cfg.fixed_dt
    local ball_v = kick_speed
    local kick_distance = 0
    for _ = 1, 20000 do
        ball_v = ball_v * s.ballDamping
        if ball_v * ball_v < 0.0001 then break end
        kick_distance = kick_distance + ball_v * cfg.fixed_dt
    end
    return travel_time, kick_distance, kick_distance / cfg.field.play_width * 100,
           kick_speed / player_speed, player_speed
end

function calibration.refresh(s)
    if not s.font then return end
    s.text[1]:set(string.format("Aceleracao: %.2fx", s.accelerationFactor))
    s.text[2]:set(string.format("Forca do chute: %.2fx", s.kickFactor))
    s.text[3]:set(string.format("Atrito bola: %.3f", s.ballDamping))
    s.text[4]:set(string.format("Atrito jogador: %.3f", s.playerDamping))
    s.text[5]:set(string.format("viewWidth: %.0f", s.viewWidth))
    s.text[6]:set(string.format("Peso da camera: %.2f", s.cameraWeight))
    s.text[7]:set("Setas: selecionar/ajustar | S: salvar | F5: fechar")
    local time, dist, pct, ratio = calibration.metrics(s)
    s.metric_text[1]:set(string.format("Travessia estimada: %.2f s", time))
    s.metric_text[2]:set(string.format("Chute maximo: %.0f unidades (%.1f%% da quadra)", dist, pct))
    s.metric_text[3]:set(string.format("Velocidade bola/jogador: %.2f%s", ratio,
        ratio < 1.3 and "  AVISO: abaixo de 1.3" or ""))
end

function calibration.adjust(s, key)
    if key == "up" then s.selected = math.max(1, s.selected - 1)
    elseif key == "down" then s.selected = math.min(6, s.selected + 1)
    elseif key ~= "left" and key ~= "right" then return end
    if key == "left" or key == "right" then
        local direction, c = key == "right" and 1 or -1, s.config.calibration
        if s.selected == 1 then s.accelerationFactor = math.max(0.25, math.min(3, s.accelerationFactor + direction * c.accelerationStep))
        elseif s.selected == 2 then s.kickFactor = math.max(0.25, math.min(3, s.kickFactor + direction * c.kickStep))
        elseif s.selected == 3 then s.ballDamping = math.max(0.90, math.min(0.999, s.ballDamping + direction * c.ballDampingStep))
        elseif s.selected == 4 then s.playerDamping = math.max(0.80, math.min(0.999, s.playerDamping + direction * c.playerDampingStep))
        elseif s.selected == 5 then s.viewWidth = math.max(s.config.camera.viewWidthMin, math.min(s.config.camera.viewWidthMax, s.viewWidth + direction * c.viewWidthStep))
        elseif s.selected == 6 then s.cameraWeight = math.max(0, math.min(1, s.cameraWeight + direction * c.cameraWeightStep)) end
        s:apply()
        if s.selected == 5 then love.filesystem.write("view_width.txt", tostring(s.viewWidth)) end
    end
    s:refresh()
end

function calibration.save(s)
    local data = string.format(
        "config.player.acceleration = %.4f -- padrao %.4f, fator %.4f\nconfig.player.kick_strength = %.4f -- padrao %.4f, fator %.4f\nconfig.ball.damping = %.4f\nconfig.player.damping = %.4f\nconfig.camera.viewWidth = %.0f\nconfig.camera.weight = %.3f\n",
        s.config.player.acceleration * s.accelerationFactor, s.config.player.acceleration, s.accelerationFactor,
        s.config.player.kick_strength * s.kickFactor, s.config.player.kick_strength, s.kickFactor,
        s.ballDamping, s.playerDamping, s.viewWidth, s.cameraWeight)
    local ok, err = love.filesystem.write("calibracao.txt", data)
    if ok then io.write("Calibracao salva em love.filesystem (calibracao.txt):\n", data)
    else io.write("Falha ao salvar calibracao.txt: ", tostring(err), "\n") end
end

function calibration.draw(s, width, height)
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.rectangle("fill", 230, 105, width - 460, height - 210, 10, 10)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("CALIBRACAO DO TREINO (F5)", 260, 125)
    for i = 1, 6 do
        love.graphics.setColor(i == s.selected and 1 or 0.78, i == s.selected and 0.85 or 0.82, i == s.selected and 0.25 or 0.9)
        love.graphics.draw(s.text[i], 270, 165 + (i - 1) * 30)
    end
    love.graphics.setColor(0.72, 0.78, 0.82)
    love.graphics.draw(s.text[7], 270, 355)
    love.graphics.setColor(0.94, 0.94, 0.94)
    for i = 1, 3 do love.graphics.draw(s.metric_text[i], 270, 405 + (i - 1) * 27) end
    love.graphics.print("S: gravar calibracao.txt e imprimir valores para config.lua", 270, height - 145)
end

return calibration
