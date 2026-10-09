local menu = {}

function menu.new()
    return { screen = "home", selection = 1, address = "", input = false, room_index = 1,
        error = "", title_font = love.graphics.newFont(36), font = love.graphics.newFont(20), small = love.graphics.newFont(15) }
end

local function center(text, y, font, color)
    love.graphics.setFont(font)
    love.graphics.setColor(color or { 0.94, 0.96, 0.98, 1 })
    love.graphics.printf(text, 30, y, love.graphics.getWidth() - 60, "center")
end

function menu.draw(m, browser, connection, network_error)
    local w, h = love.graphics.getDimensions()
    love.graphics.clear(0.055, 0.075, 0.09, 1)
    center("HAXBALL LOCAL — REAL SOCCER", h * 0.13, m.title_font, { 0.55, 0.88, 0.62, 1 })
    if m.screen == "home" then
        local rows = { "Criar sala", "Entrar", "Teste de conexão", "Sair" }
        for i = 1, #rows do center((i == m.selection and "▶  " or "   ") .. rows[i], h * 0.35 + i * 48,
            m.font, i == m.selection and { 1, 0.86, 0.35, 1 } or nil) end
        center("↑/↓ navegam • Enter confirma", h * 0.78, m.small, { 0.72, 0.78, 0.82, 1 })
    elseif m.screen == "join" then
        center("SALAS NA REDE LOCAL", h * 0.27, m.font)
        local rooms = browser and browser.rooms or {}
        for i = 1, #rooms do
            local row = rooms[i]
            center((i == m.room_index and "▶ " or "  ") .. row.name .. "  |  " .. row.address ..
                "  |  " .. row.players .. "/10  " .. row.mode, h * 0.36 + (i - 1) * 30, m.small,
                i == m.room_index and { 1, 0.86, 0.35, 1 } or nil)
        end
        if #rooms == 0 then center("Procurando anúncios...", h * 0.43, m.small, { 0.7, 0.75, 0.78, 1 }) end
        center("IP:porta: " .. (m.address == "" and "(digite aqui)" or m.address) .. (m.input and "▏" or ""),
            h * 0.68, m.font, { 0.8, 0.9, 1, 1 })
        center("Enter entra na sala selecionada ou no IP digitado • M edita IP • Esc volta",
            h * 0.78, m.small, { 0.72, 0.78, 0.82, 1 })
    elseif m.screen == "connection" then
        center("TESTE DE CONEXÃO UDP", h * 0.28, m.font)
        center("R: abrir receptor nesta máquina (porta " .. m.port .. ")", h * 0.40, m.small)
        center("C: medir contra um receptor • IP: " .. (m.address == "" and "(digite aqui)" or m.address),
            h * 0.46, m.small)
        center(m.input and "Digite o IPv4 do receptor e pressione Enter" or "M: editar IPv4  •  Esc: voltar",
            h * 0.53, m.small, { 0.72, 0.78, 0.82, 1 })
        if connection then
            if connection.role == "receiver" then
                center("RECEPTOR PRONTO — informe seu IPv4 e porta " .. connection.port,
                    h * 0.64, m.font, { 0.55, 0.88, 0.62, 1 })
                if m.addresses and #m.addresses > 0 then
                    center(table.concat(m.addresses, "   ") .. ":" .. connection.port,
                        h * 0.69, m.small, { 0.8, 0.9, 1, 1 })
                end
                center("Pacotes recebidos: " .. connection.received, h * 0.70, m.small)
            else
                center("Ping: " .. (connection.ping and string.format("%.1f ms", connection.ping) or "aguardando") ..
                    "  •  perda estimada: " .. string.format("%.0f%%", connection:packet_loss()),
                    h * 0.65, m.font, { 0.55, 0.88, 0.62, 1 })
                center("Enviados: " .. connection.sent .. "  •  recebidos: " .. connection.received ..
                    "  •  porta UDP " .. connection.port, h * 0.71, m.small)
            end
            if connection.lastError then center("Falha UDP: " .. tostring(connection.lastError), h * 0.83, m.small,
                { 1, 0.4, 0.35, 1 }) end
        end
    end
    if network_error and network_error ~= "" then center(network_error, h * 0.88, m.small, { 1, 0.4, 0.35, 1 }) end
end

return menu
