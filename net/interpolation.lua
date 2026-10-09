-- Operações sem dependências de transporte para amostrar estados recebidos.
local interpolation = {}

function interpolation.lerp(a, b, alpha)
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    return a + (b - a) * alpha
end

function interpolation.sample(before, after, alpha, out)
    out.sequence, out.acknowledgedSequence = after.sequence, after.acknowledgedSequence
    out.scoreRed, out.scoreBlue = after.scoreRed, after.scoreBlue
    out.half, out.clockTenths = after.half, after.clockTenths
    out.stateCode, out.kindCode, out.teamCode = after.stateCode, after.kindCode, after.teamCode
    out.restartX, out.restartY = after.restartX, after.restartY
    out.restartRemaining, out.zoneRadius = after.restartRemaining, after.zoneRadius
    out.ballFrozen = after.ballFrozen
    out.ballX = interpolation.lerp(before.ballX, after.ballX, alpha)
    out.ballY = interpolation.lerp(before.ballY, after.ballY, alpha)
    out.ballVX = interpolation.lerp(before.ballVX, after.ballVX, alpha)
    out.ballVY = interpolation.lerp(before.ballVY, after.ballVY, alpha)
    out.playerCount = after.playerCount
    for i = 1, after.playerCount do
        out.players[i].x = interpolation.lerp(before.players[i].x, after.players[i].x, alpha)
        out.players[i].y = interpolation.lerp(before.players[i].y, after.players[i].y, alpha)
    end
    return out
end

return interpolation
