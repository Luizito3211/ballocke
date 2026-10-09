-- Sessão host autoritativa, com INPUT não confiável e SNAPSHOT a 30 Hz.
local protocol = require "net.protocol"
local interpolation = require "net.interpolation"
local physics = require "src.physics"
local session = {}
local Session = {}
Session.__index = Session
local ZERO_COMMAND = { moveX = 0, moveY = 0, kick = false, spinX = 0, spinY = 0 }
local SNAPSHOT_BUFFER_SIZE = 8

local function new_snapshot_buffer()
    local buffer = {}
    for i = 1, SNAPSHOT_BUFFER_SIZE do
        buffer[i] = { state = protocol.new_snapshot(), time = 0 }
    end
    return buffer
end

local function copy_command(dst, src)
    dst.moveX, dst.moveY, dst.kick = src.moveX, src.moveY, src.kick
    dst.spinX, dst.spinY = src.spinX, src.spinY
end

local function sequence_is_newer(sequence, previous)
    local delta = (sequence - previous) % 65536
    return delta > 0 and delta < 32768
end

function session.new_host(room, game, config)
    game.is_training, game.is_online_host = false, true
    return setmetatable({ role = "host", room = room, game = game, config = config,
        peers = {}, elapsed = 0, snapshotElapsed = 0, sequence = 0,
        lastState = game.referee.state, localPlayerIndex = 1, closed = false,
        message = "Aguardando jogadores" }, Session)
end

function session.new_client(room, game, config)
    game.is_training, game.is_online_client = false, true
    for i = 1, #game.players do game.players[i].online_visible = false end
    return setmetatable({ role = "client", room = room, game = game, config = config,
        elapsed = 0, connectElapsed = 0, inputElapsed = 0, inputSequence = 0,
        lastInput = { moveX = 99, moveY = 99, kick = false, spinX = 99, spinY = 99 },
        snapshots = new_snapshot_buffer(), snapshotWrite = 0, snapshotCount = 0,
        latest = protocol.new_snapshot(), sampled = protocol.new_snapshot(), hasSnapshot = false, connected = false,
        predictionAccumulator = 0, predictionDt = config.fixed_dt, lastCommand = { moveX = 0, moveY = 0, kick = false, spinX = 0, spinY = 0 },
        localPlayerIndex = 0,
        message = "Conectando...", closed = false }, Session)
end

local function peer_row(s, peer)
    return s.peers[peer]
end

function Session:_send(peer, packet, reliable)
    self.room.endpoint:send(peer, packet, reliable)
end

function Session:_host_accept(peer, version)
    if version ~= protocol.VERSION or version ~= self.config.network.protocolVersion then
        self:_send(peer, protocol.pack_error(1), true)
        return
    end
    if self.peers[peer] then return end
    local red, blue = 0, 0
    for i = 1, #self.game.players do
        if self.game.players[i].team == "red" then red = red + 1 else blue = blue + 1 end
    end
    local team = red <= blue and "red" or "blue"
    local index = self.game:add_player(team)
    if not index then index = 0 end -- sala cheia: entrada como espectador.
    self.peers[peer] = { index = index, command = { moveX = 0, moveY = 0, kick = false, spinX = 0, spinY = 0 },
        lastSequence = -1, lastSeen = self.elapsed }
    self:_send(peer, protocol.pack_welcome(index), true)
    if index > 0 then self.room:set_lobby_state(#self.game.players, self.game.mode_name) end
end

function Session:_host_disconnect(peer)
    local row = self.peers[peer]
    if not row then return end
    local removed = row.index
    self.peers[peer] = nil
    if removed > 1 then
        self.game:remove_player(removed)
        for other, other_row in pairs(self.peers) do
            if other_row.index > removed then
                other_row.index = other_row.index - 1
                self:_send(other, protocol.pack_event(2, 0, 0, 0, 0, other_row.index), true)
            end
        end
        self.room:set_lobby_state(#self.game.players, self.game.mode_name)
    end
end

function Session:_host_packet(peer, packet)
    if type(packet) ~= "string" or #packet == 0 then return end
    local tag = packet:sub(1, 1)
    if tag == "H" then
        local kind, version = protocol.unpack_handshake(packet)
        if kind == "hello" then self:_host_accept(peer, version) end
    elseif tag == "I" then
        local row = peer_row(self, peer)
        if row and row.index > 0 and protocol.unpack_input(packet, row.command) then
            if row.lastSequence < 0 or sequence_is_newer(row.command.seq, row.lastSequence) then
                row.lastSequence, row.lastSeen = row.command.seq, self.elapsed
            end
        end
    end
end

function Session:_client_packet(event, packet)
    if event == "disconnect" then
        self.connected = false
        self.message = "O host encerrou a sala ou a conexão caiu."
        return
    end
    if type(packet) ~= "string" or #packet == 0 then return end
    local tag = packet:sub(1, 1)
    if tag == "W" or tag == "E" then
        local kind, version, player_index = protocol.unpack_handshake(packet)
        if kind == "error" then
            self.message = version == 1 and "Versão de protocolo diferente. Atualize o jogo." or "O host recusou a conexão."
            self.failed = true
        elseif kind == "welcome" then
            if version ~= protocol.VERSION or version ~= self.config.network.protocolVersion then
                self.message, self.failed = "Versão de protocolo diferente. Atualize o jogo.", true
            else
                self.localPlayerIndex, self.connected = player_index or 0, true
                self.message = self.localPlayerIndex == 0 and "Conectado como espectador." or "Conectado."
                self.lastSnapshotAt = self.elapsed
            end
        end
    elseif tag == "S" then
        self.snapshotWrite = self.snapshotWrite % SNAPSHOT_BUFFER_SIZE + 1
        local row = self.snapshots[self.snapshotWrite]
        if protocol.unpack_snapshot(packet, row.state) then
            row.time = self.elapsed
            self.latest = row.state
            self.snapshotCount = math.min(self.snapshotCount + 1, SNAPSHOT_BUFFER_SIZE)
            self.hasSnapshot, self.lastSnapshotAt = true, self.elapsed
        end
        self.message = "Conectado."
    elseif tag == "V" then
        local code, state, team, red, blue, new_index = protocol.unpack_event(packet)
        if code == 1 and protocol.state_names[state] then
            local r = self.game.referee
            local state_name = protocol.state_names[state]
            r.state = state_name
            if state_name == protocol.state_names[7] then
                r.scoringTeam = team == 1 and "red" or "blue"
                r.message = self.config.referee.messages.goal
            elseif state_name == protocol.state_names[4] or state_name == protocol.state_names[5] or
                   state_name == protocol.state_names[6] or state_name == protocol.state_names[2] then
                r.restartTeam = team == 1 and "red" or "blue"
                local key = state_name == protocol.state_names[4] and (team == 1 and "lateralRed" or "lateralBlue") or
                    state_name == protocol.state_names[5] and (team == 1 and "goalKickRed" or "goalKickBlue") or
                    state_name == protocol.state_names[6] and (team == 1 and "cornerRed" or "cornerBlue") or
                    (team == 1 and "kickoffRed" or "kickoffBlue")
                r.message = self.config.referee.messages[key]
            end
            r.decisionNotice, r.noticeTimer = r.message, self.config.referee.decisionNoticeSeconds
            self.game.score_p1, self.game.score_p2 = red, blue
            self.game.is_goal_delay = state_name == protocol.state_names[7]
        elseif code == 2 then
            self.localPlayerIndex = new_index or self.localPlayerIndex
        end
    end
end

function Session:_service_host()
    for _ = 1, 64 do
        local event, peer, _, packet = self.room.endpoint:receive(0)
        if not event then break end
        if event == "receive" then self:_host_packet(peer, packet)
        elseif event == "disconnect" then self:_host_disconnect(peer) end
    end
    for peer, row in pairs(self.peers) do
        if self.elapsed - row.lastSeen > self.config.network.timeoutSeconds then
            self.room.endpoint:disconnect(peer)
            self:_host_disconnect(peer)
        end
    end
end

function Session:_service_client()
    for _ = 1, 64 do
        local event, _, _, packet = self.room.endpoint:receive(0)
        if not event then break end
        if event == "connect" then
            self.room.endpoint:send(protocol.pack_hello(), true)
        elseif event == "receive" then
            self:_client_packet(event, packet)
        elseif event == "disconnect" then
            self:_client_packet(event)
        end
    end
    if not self.connected and not self.failed and self.connectElapsed > 5 then
        self.message, self.failed = "Tempo esgotado ao conectar. Confira IP, porta e rede.", true
        self.room.endpoint:disconnect()
    elseif self.connected and self.elapsed - (self.lastSnapshotAt or 0) > self.config.network.timeoutSeconds then
        self.message, self.failed, self.connected = "Tempo esgotado: conexão com o host perdida.", true, false
    end
end

local function same_command(a, b)
    return a.moveX == b.moveX and a.moveY == b.moveY and a.kick == b.kick and
        a.spinX == b.spinX and a.spinY == b.spinY
end

function Session:update(dt, local_command)
    if self.closed then return end
    self.elapsed = self.elapsed + dt
    if self.role == "host" then
        self:_service_host()
        if self.room.discovery then self.room:update(dt, #self.game.players, self.game.mode_name) end
    else
        self.connectElapsed = self.connectElapsed + dt
        self:_service_client()
        self.room:update(dt)
        self.inputElapsed = self.inputElapsed + dt
        local_command = local_command or ZERO_COMMAND
        copy_command(self.lastCommand, local_command)
        self.predictionDt = math.min(dt, self.config.max_dt_acc)
        if self.connected and self.localPlayerIndex > 0 and
           (not same_command(local_command, self.lastInput) or self.inputElapsed >= self.config.network.inputKeepalive) then
            self.inputSequence = (self.inputSequence + 1) % 65536
            self.room.endpoint:send(protocol.pack_input(self.inputSequence, local_command), false)
            copy_command(self.lastInput, local_command)
            self.inputElapsed = 0
        end
        if self.connected and self.localPlayerIndex > 0 then
            self.predictionAccumulator = self.predictionAccumulator + self.predictionDt
            local steps = 0
            local p = self.game.players[self.localPlayerIndex]
            while p and self.predictionAccumulator >= self.config.fixed_dt and steps < self.config.max_physics_steps do
                p.prev_x, p.prev_y = p.x, p.y
                p:step_physics(self.config.fixed_dt, self.lastCommand.moveX, self.lastCommand.moveY,
                    self.lastCommand.kick, self.lastCommand.spinX, self.lastCommand.spinY,
                    physics, nil, self.config.spin)
                local f = self.game.field
                p.x = math.max(f.outer_left + p.radius, math.min(f.outer_right - p.radius, p.x))
                p.y = math.max(f.outer_top + p.radius, math.min(f.outer_bottom - p.radius, p.y))
                self.predictionAccumulator = self.predictionAccumulator - self.config.fixed_dt
                steps = steps + 1
            end
        end
    end
end

function Session:apply_snapshot()
    if self.role ~= "client" or not self.hasSnapshot then return false end
    local g, s, r = self.game, self.latest, self.game.referee
    if self.snapshotCount >= 2 then
        local target = self.elapsed - self.config.network.interpolationDelay
        local before, after
        local oldest = (self.snapshotWrite - self.snapshotCount) % SNAPSHOT_BUFFER_SIZE + 1
        local previous = self.snapshots[oldest]
        before, after = previous, previous
        for offset = 1, self.snapshotCount - 1 do
            local index = (oldest + offset - 1) % SNAPSHOT_BUFFER_SIZE + 1
            local row = self.snapshots[index]
            if row.time <= target then before = row end
            if row.time >= target then after = row; break end
            after = row
        end
        local span = after.time - before.time
        local alpha = span > 0 and (target - before.time) / span or 1
        interpolation.sample(before.state, after.state, alpha, self.sampled)
        s = self.sampled
    end
    g.score_p1, g.score_p2 = s.scoreRed, s.scoreBlue
    g.ball.prev_x, g.ball.prev_y = g.ball.x, g.ball.y
    g.ball.x, g.ball.y, g.ball.vx, g.ball.vy = s.ballX, s.ballY, s.ballVX, s.ballVY
    r.half, r.halfRemaining = s.half, s.clockTenths / 10
    r.state = protocol.state_names[s.stateCode] or r.state
    r.restartType = protocol.kind_names[s.kindCode] or r.restartType
    r.restartTeam = s.teamCode == 1 and "red" or (s.teamCode == 2 and "blue" or r.restartTeam)
    r.restartX, r.restartY = s.restartX, s.restartY
    r.restartRemaining, r.ballFrozen = s.restartRemaining, s.ballFrozen
    if r.restartType == "corner" then r.config.referee.cornerZoneRadius = s.zoneRadius end
    g.is_goal_delay = r.state == protocol.state_names[7]
    for i = 1, #g.players do
        local p = g.players[i]
        p.online_visible = i <= s.playerCount
        if i <= s.playerCount then
            p.prev_x, p.prev_y = p.x, p.y
            if i == self.localPlayerIndex then
                -- Suaviza erro de predição em vez de teletransportar o jogador.
                local blend = math.min(1, math.max(0, self.predictionDt) * 8)
                p.x = p.x + (s.players[i].x - p.x) * blend
                p.y = p.y + (s.players[i].y - p.y) * blend
            else
                p.x, p.y = s.players[i].x, s.players[i].y
            end
        end
    end
    return true
end

function Session:apply_host_inputs()
    if self.role ~= "host" then return end
    for i = 2, #self.game.commands do
        local command = self.game.commands[i]
        command.moveX, command.moveY, command.kick, command.spinX, command.spinY = 0, 0, false, 0, 0
    end
    for _, row in pairs(self.peers) do
        if row.index > 0 and row.index <= #self.game.commands and self.elapsed - row.lastSeen <= self.config.network.timeoutSeconds then
            copy_command(self.game.commands[row.index], row.command)
        end
    end
end

function Session:after_host_tick()
    if self.role ~= "host" then return end
    self.snapshotElapsed = self.snapshotElapsed + self.config.fixed_dt
    local state = self.game.referee.state
    if state ~= self.lastState then
        local r = self.game.referee
        local event_team = state == protocol.state_names[7] and r.scoringTeam or r.restartTeam
        local team = protocol.team_code[event_team] or 0
        local event = protocol.pack_event(1, protocol.state_code[state] or 0, team,
            self.game.score_p1, self.game.score_p2, 0)
        for peer in pairs(self.peers) do self:_send(peer, event, true) end
        self.lastState = state
    end
    if self.snapshotElapsed >= 1 / self.config.network.snapshotRate then
        self.snapshotElapsed = self.snapshotElapsed - 1 / self.config.network.snapshotRate
        self.sequence = (self.sequence + 1) % 65536
        local packet = protocol.pack_snapshot(self.game, self.sequence, 0)
        for peer in pairs(self.peers) do self:_send(peer, packet, false) end
    end
end

function Session:set_mode(mode)
    if self.role ~= "host" or (mode ~= "2v2" and mode ~= "3v3" and mode ~= "4v4" and mode ~= "5v5") then return false end
    local count = #self.game.players
    self.game:set_mode(mode, count)
    self.lastState = self.game.referee.state
    self.room:set_lobby_state(count, mode)
    return true
end

function Session:close()
    if self.closed then return end
    self.closed = true
    self.room:close()
end

return session
