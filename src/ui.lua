-- src/ui.lua: Interface do usuário (HUD, placar, seletor de efeito 8-Ball Pool e overlay F3)
local ui = {}
local referee_mod = require "src.referee"

function ui.new(config)
    local u = {}
    local colors = config.colors

    -- Fontes do LÖVE
    u.font_score = love.graphics.newFont(38)
    u.font_hud = love.graphics.newFont(14)
    u.font_debug = love.graphics.newFont(12)
    u.font_mini = love.graphics.newFont(10)

    -- Textos estáticos / pré-alocados (zero GC por frame)
    u.text_score = love.graphics.newText(u.font_score, "0  -  0")
    u.text_p1_label = love.graphics.newText(u.font_hud, "VERMELHO")
    u.text_p2_label = love.graphics.newText(u.font_hud, "AZUL")
    u.text_goal_banner = love.graphics.newText(u.font_score, "GOL!")
    u.text_instructions = love.graphics.newText(u.font_hud, "VERMELHO: WASD + Espaço | AZUL: IJKL + Enter | Setas/C: efeito vermelho | F2: modo | F3: debug | F4: colisores")
    u.text_debug = love.graphics.newText(u.font_debug, "FPS: 60  |  Lua RAM: 0 KB  |  Modo: 1v1 (2/2 jogadores)")
    u.text_spin_label = love.graphics.newText(u.font_mini, "EFEITO (C)")
    u.text_reset_icon = love.graphics.newText(u.font_mini, "C")
    u.font_ref = love.graphics.newFont(18)
    u.font_notice = love.graphics.newFont(34)
    u.font_panel = love.graphics.newFont(16)
    u.text_referee = love.graphics.newText(u.font_ref, "AQUECIMENTO")
    u.text_clock = love.graphics.newText(u.font_hud, "1º TEMPO  05:00")
    u.text_restart_clock = love.graphics.newText(u.font_hud, "")
    u.text_decision_notice = love.graphics.newText(u.font_notice, "")
    u.notice_color = { 1, 1, 1 }
    u.notice_visible = false
    u.ref_second = -1
    u.test_selection = 1
    u.test_touch = 1
    u.test_rows = {
        love.graphics.newText(u.font_panel, "Lateral superior: 1"),
        love.graphics.newText(u.font_panel, "Lateral inferior: 2"),
        love.graphics.newText(u.font_panel, "Fundo esquerdo: 3"),
        love.graphics.newText(u.font_panel, "Fundo direito: 4"),
        love.graphics.newText(u.font_panel, "Último toque: [Nenhum] Vermelho Azul (←/→)"),
        love.graphics.newText(u.font_panel, "Tempos curtos: desligado"),
        love.graphics.newText(u.font_panel, "Duração teste: 5 min"),
        love.graphics.newText(u.font_panel, "Forçar fim do tempo: Enter"),
    }
    u.text_test_help = love.graphics.newText(u.font_hud, "↑/↓ selecionar | ←/→ ajustar | Enter aplicar | F6 fechar | F7 levar jogador à bola")

    u.last_score_p1 = -1
    u.last_score_p2 = -1
    u.debug_timer = 0

    return setmetatable(u, { __index = ui })
end

function ui.update_referee(u, r)
    if u.current_notice ~= r.decisionNotice then
        u.current_notice = r.decisionNotice
        u.text_decision_notice:set(r.decisionNotice or "")
    end
    u.notice_visible = r.noticeTimer > 0 and u.text_decision_notice:getWidth() > 0
    if r.noticeTeam == "red" then
        u.notice_color[1], u.notice_color[2], u.notice_color[3] = 1, 0.35, 0.30
    elseif r.noticeTeam == "blue" then
        u.notice_color[1], u.notice_color[2], u.notice_color[3] = 0.40, 0.68, 1
    else
        u.notice_color[1], u.notice_color[2], u.notice_color[3] = 1, 1, 1
    end
    local sec = math.floor(math.max(0, r.halfRemaining) + 0.999)
    local clock_running = referee_mod.isClockRunning(r)
    if sec ~= u.ref_second or clock_running ~= u.clock_running then
        u.ref_second = sec
        u.clock_running = clock_running
        local minute, second = math.floor(sec / 60), sec % 60
        local half = r.half == 1 and "1º TEMPO" or "2º TEMPO"
        local indicator = clock_running and "" or "  PAUSADO"
        u.text_clock:set(string.format("%s  %02d:%02d%s", half, minute, second, indicator))
    end
    local msg = r.message or ""
    if u.current_ref_message ~= msg then
        u.current_ref_message = msg
        u.text_referee:set(msg)
    end
    local remaining = math.ceil(math.max(0, r.restartRemaining))
    if r.restartRemaining > 0 and u.restart_second ~= remaining then
        u.restart_second = remaining
        u.text_restart_clock:set("Cobrança: " .. remaining .. " s")
    elseif r.restartRemaining <= 0 and u.restart_second ~= 0 then
        u.restart_second = 0
        u.text_restart_clock:set("")
    end
end

function ui.refresh_test_panel(u, short_restarts, one_minute, last_touch)
    local row = u.test_rows[5]
    local touch = last_touch == 1 and "[Nenhum] Vermelho Azul" or
        (last_touch == 2 and "Nenhum [Vermelho] Azul" or "Nenhum Vermelho [Azul]")
    row:set("Último toque: " .. touch .. " (←/→)")
    u.test_rows[6]:set("Tempos curtos: " .. (short_restarts and "ligado" or "desligado"))
    u.test_rows[7]:set("Duração teste: " .. (one_minute and "1 minuto" or "5 minutos"))
end

function ui.draw_referee(u, virtual_width, virtual_height)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", virtual_width / 2 - 220, 70, 440, 64, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    local w = u.text_referee:getWidth()
    love.graphics.draw(u.text_referee, virtual_width / 2 - w / 2, 76)
    if u.clock_running then love.graphics.setColor(0.92, 0.92, 0.92, 1)
    else love.graphics.setColor(0.62, 0.68, 0.72, 1) end
    love.graphics.draw(u.text_clock, virtual_width / 2 - u.text_clock:getWidth() / 2, 108)
    love.graphics.setColor(1, 1, 1, 1)
    if u.text_restart_clock:getWidth() > 0 then
        love.graphics.draw(u.text_restart_clock, virtual_width / 2 - u.text_restart_clock:getWidth() / 2, 136)
    end
    if u.notice_visible then
        local nw, nh = u.text_decision_notice:getWidth(), u.text_decision_notice:getHeight()
        local text_scale = math.min(1, (virtual_width - 64) / math.max(nw, 1))
        local display_w, display_h = nw * text_scale, nh * text_scale
        local box_w = math.min(virtual_width - 48, display_w + 56)
        local box_y = virtual_height * 0.5 - display_h * 0.5 - 18
        love.graphics.setColor(0, 0, 0, 0.88)
        love.graphics.rectangle("fill", (virtual_width - box_w) * 0.5, box_y, box_w, display_h + 36, 10, 10)
        love.graphics.setColor(u.notice_color[1], u.notice_color[2], u.notice_color[3], 1)
        love.graphics.draw(u.text_decision_notice, (virtual_width - display_w) * 0.5, box_y + 18, 0, text_scale, text_scale)
    end
end

function ui.draw_test_panel(u, virtual_width, virtual_height)
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.rectangle("fill", virtual_width / 2 - 340, virtual_height / 2 - 205, 680, 410, 10, 10)
    love.graphics.setColor(1, 0.9, 0.3, 1)
    love.graphics.printf("PAINEL DE TESTE DO ÁRBITRO (TREINO SOLO)", virtual_width / 2 - 320, virtual_height / 2 - 185, 640, "center")
    for i = 1, #u.test_rows do
        if i == u.test_selection then love.graphics.setColor(1, 0.9, 0.3, 1)
        else love.graphics.setColor(0.92, 0.94, 0.97, 1) end
        love.graphics.draw(u.test_rows[i], virtual_width / 2 - 300, virtual_height / 2 - 145 + (i - 1) * 32)
    end
    love.graphics.setColor(0.75, 0.8, 0.85, 1)
    love.graphics.draw(u.text_test_help,
        virtual_width / 2 - u.text_test_help:getWidth() / 2, virtual_height / 2 + 145)
end

-- Atualiza o texto do placar SOMENTE quando houver alteração de pontos
function ui.update_score(u, score_p1, score_p2)
    if score_p1 ~= u.last_score_p1 or score_p2 ~= u.last_score_p2 then
        u.last_score_p1 = score_p1
        u.last_score_p2 = score_p2
        u.text_score:set(score_p1 .. "   -   " .. score_p2)
    end
end

-- Renderização do HUD do jogo
function ui.draw_hud(u, game_state, colors, virtual_width, virtual_height)
    local cx = virtual_width / 2

    -- 1. Placar central no topo
    local score_w = u.text_score:getWidth()
    local score_h = u.text_score:getHeight()
    local score_x = cx - score_w / 2
    local score_y = 16

    -- Fundo do placar
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", score_x - 70, score_y - 4, score_w + 140, score_h + 8, 6, 6)

    -- Rótulo e cor do time Vermelho
    love.graphics.setColor(colors.p1 or {0.88, 0.22, 0.22})
    love.graphics.circle("fill", score_x - 45, score_y + score_h / 2, 7)
    love.graphics.draw(u.text_p1_label, score_x - 30, score_y + score_h / 2 - u.text_p1_label:getHeight() / 2)

    -- Rótulo e cor do time Azul
    love.graphics.setColor(colors.p2 or {0.22, 0.48, 0.88})
    love.graphics.circle("fill", score_x + score_w + 45, score_y + score_h / 2, 7)
    love.graphics.draw(u.text_p2_label, score_x + score_w + 10, score_y + score_h / 2 - u.text_p2_label:getHeight() / 2)

    -- Texto numérico do placar
    love.graphics.setColor(colors.hud_text)
    love.graphics.draw(u.text_score, score_x, score_y)

    -- 2. Banner de GOL
    if game_state.is_goal_delay then
        local banner_w = u.text_goal_banner:getWidth()
        local banner_h = u.text_goal_banner:getHeight()
        local banner_y = virtual_height / 2 - 30

        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", cx - banner_w / 2 - 24, banner_y - 8, banner_w + 48, banner_h + 16, 8, 8)

        if game_state.referee.scoringTeam == "red" then
            love.graphics.setColor(colors.score_p1)
        else
            love.graphics.setColor(colors.score_p2)
        end
        love.graphics.draw(u.text_goal_banner, cx - banner_w / 2, banner_y)
    end

    -- 3. Seletor de Efeito Estilo 8-Ball Pool (canto inferior direito)
    u:draw_spin_selector(game_state, colors, virtual_width, virtual_height)

    -- 4. Instruções na barra inferior
    love.graphics.setColor(0.7, 0.7, 0.7, 0.75)
    local inst_w = u.text_instructions:getWidth()
    love.graphics.draw(u.text_instructions, cx - inst_w / 2 - 40, virtual_height - 24)
end

-- Renderização do Seletor de Efeito (círculo maior de raio ~40 com ponto de contato móvel)
function ui.draw_spin_selector(u, game_state, colors, virtual_width, virtual_height)
    local cfg = game_state.config
    local sel_cfg = cfg.spin_selector or { radius = 40, cue_radius = 8 }
    local r = sel_cfg.radius or 40
    local cue_r = sel_cfg.cue_radius or 8

    local widget_cx = virtual_width - 60
    local widget_cy = virtual_height - 60
    local btn_x = widget_cx - r - 16
    local btn_y = widget_cy + r * 0.4
    local btn_r = 10

    -- Identifica o jogador a exibir (prioriza quem está na posse ou P1)
    local active_player = game_state.players and game_state.players[1]
    if not active_player or not active_player.allow_spin then return end
    local sx = (active_player and active_player.spin_x) or 0
    local sy = (active_player and active_player.spin_y) or 0

    -- Fundo do seletor
    love.graphics.setColor(0.08, 0.10, 0.14, 0.85)
    love.graphics.circle("fill", widget_cx, widget_cy, r + 4)

    -- Bola branca (área de contato do chute)
    love.graphics.setColor(0.93, 0.94, 0.96, 1.0)
    love.graphics.circle("fill", widget_cx, widget_cy, r)

    -- Mira central em cruz sutil
    love.graphics.setColor(0.65, 0.70, 0.75, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.line(widget_cx - r * 0.7, widget_cy, widget_cx + r * 0.7, widget_cy)
    love.graphics.line(widget_cx, widget_cy - r * 0.7, widget_cx, widget_cy + r * 0.7)

    -- Borda externa do seletor
    love.graphics.setColor(0.25, 0.30, 0.35, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", widget_cx, widget_cy, r)

    -- Ponto de contato menor (vermelho) - representa ponto teórico de impacto
    local max_offset = r - cue_r
    local dot_x = widget_cx + sx * max_offset
    local dot_y = widget_cy - sy * max_offset -- sy > 0 (topo) desenha acima

    -- Sombra do ponto
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.circle("fill", dot_x + 1, dot_y + 1, cue_r)

    -- Ponto de contato
    love.graphics.setColor(0.90, 0.22, 0.22, 0.95)
    love.graphics.circle("fill", dot_x, dot_y, cue_r)
    love.graphics.setColor(0.2, 0.05, 0.05, 0.9)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", dot_x, dot_y, cue_r)

    -- Botão de Reset ao lado (pequeno ícone clicável)
    love.graphics.setColor(0.18, 0.22, 0.28, 0.9)
    love.graphics.circle("fill", btn_x, btn_y, btn_r)
    love.graphics.setColor(0.7, 0.75, 0.8, 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", btn_x, btn_y, btn_r)
    love.graphics.setColor(0.9, 0.9, 0.9, 0.9)
    love.graphics.draw(u.text_reset_icon, btn_x - 3.5, btn_y - 6.5)

    -- Rótulo do seletor
    love.graphics.setColor(0.75, 0.80, 0.85, 0.8)
    local lbl_w = u.text_spin_label:getWidth()
    love.graphics.draw(u.text_spin_label, widget_cx - lbl_w / 2, widget_cy - r - 16)
end

-- Overlay de debug acionado por F3 (mostra FPS, RAM e Preset ativo)
function ui.draw_debug(u, dt, show_debug, game_state)
    if not show_debug then return end

    u.debug_timer = u.debug_timer + dt
    if u.debug_timer >= 0.25 then
        u.debug_timer = 0
        local fps = love.timer.getFPS()
        local mem_kb = math.floor(collectgarbage("count"))
        local preset_str = (game_state and game_state.mode_name) or "2v2"
        local p_count = (game_state and #game_state.players) or 4
        local capacity = (game_state and game_state.team_capacity) or 2
        u.text_debug:set(string.format("FPS: %d  |  Lua RAM: %d KB  |  Modo: %s (%d/%d jogadores locais)", fps, mem_kb, preset_str, p_count, capacity * 2))
    end

    local text_w = u.text_debug:getWidth()
    local text_h = u.text_debug:getHeight()

    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 10, 10, text_w + 16, text_h + 8, 4, 4)

    love.graphics.setColor(0.2, 1.0, 0.4, 1.0)
    love.graphics.draw(u.text_debug, 18, 14)
end

function ui.draw_ball_arrow(u, x, y, dx, dy, tint)
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then return end
    dx, dy = dx / length, dy / length
    local px, py = -dy, dx
    tint = tint or { 1, 0.88, 0.22 }
    love.graphics.setColor(tint[1], tint[2], tint[3], 0.95)
    love.graphics.polygon("fill", x + dx * 12, y + dy * 12,
        x - dx * 8 + px * 7, y - dy * 8 + py * 7,
        x - dx * 8 - px * 7, y - dy * 8 - py * 7)
end

return ui
