-- Protocolo binário versão 1. Pacotes têm tamanhos e limites explícitos.
local protocol = { VERSION = 1, MAX_PLAYERS = 10 }

local state_names = { "AQUECIMENTO", "SAQUE_INICIAL", "JOGO", "LATERAL", "TIRO_DE_META", "ESCANTEIO", "GOL", "INTERVALO", "FIM" }
local kind_names = { "kickoff", "lateral", "goal_kick", "corner" }
protocol.state_code, protocol.kind_code = {}, {}
for i = 1, #state_names do protocol.state_code[state_names[i]] = i end
for i = 1, #kind_names do protocol.kind_code[kind_names[i]] = i end
protocol.team_code = { red = 1, blue = 2 }
protocol.state_names, protocol.kind_names = state_names, kind_names

local snapshot_format = "<c1I2I2I1i2i2i2i2I1I1I1I2I1I1I1i2i2I1I2I2"
for _ = 1, protocol.MAX_PLAYERS do snapshot_format = snapshot_format .. "i2i2I1" end
protocol.INPUT_SIZE = love.data.getPackedSize("<c1I2i1i1I1i1i1")
protocol.SNAPSHOT_SIZE = love.data.getPackedSize(snapshot_format)

local function clamp(value, low, high)
    value = tonumber(value) or 0
    if value < low then return low end
    if value > high then return high end
    if value >= 0 then return math.floor(value + 0.5) end
    return math.ceil(value - 0.5)
end

function protocol.pack_hello()
    return love.data.pack("string", "<c1I1", "H", protocol.VERSION)
end

function protocol.pack_welcome(player_index)
    return love.data.pack("string", "<c1I1I1", "W", protocol.VERSION, clamp(player_index, 0, protocol.MAX_PLAYERS))
end

function protocol.pack_error(code)
    return love.data.pack("string", "<c1I1", "E", clamp(code, 1, 255))
end

function protocol.unpack_handshake(packet)
    if type(packet) ~= "string" or #packet < 2 then return nil, "pacote inválido" end
    if packet:sub(1, 1) == "W" and #packet == 3 then
        local ok, _, version, player_index = pcall(love.data.unpack, "<c1I1I1", packet)
        if ok then return "welcome", version, player_index end
        return nil, "pacote inválido"
    end
    if #packet ~= 2 then return nil, "pacote inválido" end
    local ok, tag, version = pcall(love.data.unpack, "<c1I1", packet)
    if not ok then return nil, "pacote inválido" end
    if tag == "H" then return "hello", version end
    if tag == "E" then return "error", version end
    return nil, "pacote inválido"
end

function protocol.pack_input(sequence, command)
    return love.data.pack("string", "<c1I2i1i1I1i1i1", "I", clamp(sequence, 0, 65535),
        clamp(command.moveX, -1, 1), clamp(command.moveY, -1, 1), command.kick and 1 or 0,
        clamp((command.spinX or 0) * 127, -127, 127), clamp((command.spinY or 0) * 127, -127, 127))
end

function protocol.unpack_input(packet, out)
    if type(packet) ~= "string" or #packet ~= protocol.INPUT_SIZE then return false end
    local ok, tag, sequence, move_x, move_y, kick, spin_x, spin_y = pcall(love.data.unpack,
        "<c1I2i1i1I1i1i1", packet)
    if not ok or tag ~= "I" or kick > 1 or math.abs(move_x) > 1 or math.abs(move_y) > 1 then return false end
    out.seq, out.moveX, out.moveY = sequence, move_x, move_y
    out.kick, out.spinX, out.spinY = kick == 1, spin_x / 127, spin_y / 127
    return true
end

function protocol.pack_team(team)
    return love.data.pack("string", "<c1I1", "T", protocol.team_code[team] or 0)
end

function protocol.unpack_team(packet)
    if type(packet) ~= "string" or #packet ~= 2 then return nil end
    local ok, tag, code = pcall(love.data.unpack, "<c1I1", packet)
    if not ok or tag ~= "T" or code > 3 then return nil end
    return code
end

function protocol.pack_snapshot(game, sequence, acknowledged_sequence)
    local r, ball = game.referee, game.ball
    local values = { "S", clamp(sequence, 0, 65535), clamp(acknowledged_sequence, 0, 65535),
        math.min(#game.players, protocol.MAX_PLAYERS),
        clamp(ball.x * 16, -32768, 32767), clamp(ball.y * 16, -32768, 32767),
        clamp(ball.vx * 8, -32768, 32767), clamp(ball.vy * 8, -32768, 32767),
        clamp(game.score_p1, 0, 255), clamp(game.score_p2, 0, 255), clamp(r.half, 1, 2),
        clamp(r.halfRemaining * 10, 0, 65535), protocol.state_code[r.state] or 1,
        protocol.kind_code[r.restartType] or 1, protocol.team_code[r.restartTeam] or 0,
        clamp(r.restartX * 16, -32768, 32767), clamp(r.restartY * 16, -32768, 32767),
        r.ballFrozen and 1 or 0,
        r.restartType == "corner" and clamp(game.config.referee.cornerZoneRadius * 16, 0, 65535) or 0,
        clamp(math.max(0, r.restartRemaining) * 10, 0, 65535) }
    for i = 1, protocol.MAX_PLAYERS do
        local p = game.players[i]
        values[#values + 1] = p and clamp(p.x * 16, -32768, 32767) or 0
        values[#values + 1] = p and clamp(p.y * 16, -32768, 32767) or 0
        values[#values + 1] = p and (p.team == "red" and 1 or 2) or 0
    end
    local packet = love.data.pack("string", snapshot_format, unpack(values))
    return packet
end

function protocol.new_snapshot()
    local players = {}
    for i = 1, protocol.MAX_PLAYERS do players[i] = { x = 0, y = 0, teamCode = 0 } end
    return { players = players, playerCount = 0 }
end

function protocol.unpack_snapshot(packet, out)
    if type(packet) ~= "string" or #packet ~= protocol.SNAPSHOT_SIZE then return false end
    local ok, values = pcall(function() return { love.data.unpack(snapshot_format, packet) } end)
    if not ok or values[1] ~= "S" then return false end
    local s = out
    s.sequence, s.acknowledgedSequence, s.playerCount = values[2], values[3], values[4]
    if s.playerCount > protocol.MAX_PLAYERS then return false end
    s.ballX, s.ballY = values[5] / 16, values[6] / 16
    s.ballVX, s.ballVY = values[7] / 8, values[8] / 8
    s.scoreRed, s.scoreBlue, s.half, s.clockTenths = values[9], values[10], values[11], values[12]
    s.stateCode, s.kindCode, s.teamCode = values[13], values[14], values[15]
    s.restartX, s.restartY = values[16] / 16, values[17] / 16
    s.ballFrozen, s.zoneRadius, s.restartRemaining = values[18] == 1, values[19] / 16, values[20] / 10
    local offset = 21
    for i = 1, protocol.MAX_PLAYERS do
        s.players[i].x, s.players[i].y, s.players[i].teamCode = values[offset] / 16, values[offset + 1] / 16, values[offset + 2]
        offset = offset + 3
    end
    return true
end

function protocol.pack_event(event_code, state_code, team_code, score_red, score_blue, player_index)
    return love.data.pack("string", "<c1I1I1I1I1I1I1", "V", event_code or 0, state_code or 0,
        team_code or 0, score_red or 0, score_blue or 0, player_index or 0)
end

function protocol.unpack_event(packet)
    if type(packet) ~= "string" or #packet ~= love.data.getPackedSize("<c1I1I1I1I1I1I1") then return nil end
    local ok, tag, code, state, team, score_red, score_blue, player_index = pcall(love.data.unpack,
        "<c1I1I1I1I1I1I1", packet)
    if not ok or tag ~= "V" then return nil end
    return code, state, team, score_red, score_blue, player_index
end

return protocol
