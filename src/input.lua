-- src/input.lua: Leitura de comandos desacoplada, suporte a mouse, teclas e zero alocação de GC
local input = {}

-- Retorna (move_x, move_y, is_kicking) usando registradores Lua, sem criar tabelas
function input.get_movement_and_kick(keys)
    local is_down = love.keyboard.isDown
    local mx = 0
    local my = 0

    if is_down(keys.left) or (keys.left_alt and is_down(keys.left_alt)) then mx = mx - 1 end
    if is_down(keys.right) or (keys.right_alt and is_down(keys.right_alt)) then mx = mx + 1 end
    if is_down(keys.up) or (keys.up_alt and is_down(keys.up_alt)) then my = my - 1 end
    if is_down(keys.down) or (keys.down_alt and is_down(keys.down_alt)) then my = my + 1 end

    local kick = is_down(keys.kick) or (keys.kick_alt and is_down(keys.kick_alt))

    return mx, my, kick
end

-- Preenche um comando reutilizável para um jogador específico (preparação determinística para online)
function input.poll_player_command(player, out_cmd)
    local mx, my, kick = input.get_movement_and_kick(player.keys)
    out_cmd.moveX = mx
    out_cmd.moveY = my
    out_cmd.kick = kick
    out_cmd.spinX = player.spin_x or 0
    out_cmd.spinY = player.spin_y or 0
end

-- Atualiza o spin do jogador via teclas configuradas
function input.update_keyboard_spin(player, dt, speed, is_enabled)
    if not is_enabled or not player.spin_keys then return end

    local is_down = love.keyboard.isDown
    local k = player.spin_keys

    if k.reset and is_down(k.reset) then
        player:reset_spin()
        return
    end

    local sx = player.spin_x or 0
    local sy = player.spin_y or 0
    local step = speed * dt

    if is_down(k.left) then sx = sx - step end
    if is_down(k.right) then sx = sx + step end
    if is_down(k.up) then sy = sy + step end
    if is_down(k.down) then sy = sy - step end

    player:set_spin(sx, sy)
end

-- Processa interação do mouse com o seletor de efeito e botão de reset
function input.handle_mouse_spin(player, vmx, vmy, mouse_down, mouse_clicked, cx, cy, radius, rbx, rby, r_radius)
    if not player then return false end

    -- 1. Clique no botão de reset (ícone ao lado do círculo)
    local r_dx = vmx - rbx
    local r_dy = vmy - rby
    if mouse_clicked and (r_dx * r_dx + r_dy * r_dy <= (r_radius + 4) * (r_radius + 4)) then
        player:reset_spin()
        return true
    end

    -- 2. Clique ou arraste dentro da área do seletor
    local dx = vmx - cx
    local dy = vmy - cy
    local dist_sq = dx * dx + dy * dy
    if mouse_down and (dist_sq <= (radius + 8) * (radius + 8)) then
        local sx = dx / radius
        -- No espaço virtual da tela, Y para baixo é positivo; por convenção, efeito de topo (cima) é sy > 0
        local sy = -dy / radius
        player:set_spin(sx, sy)
        return true
    end

    return false
end

return input
