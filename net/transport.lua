-- Adaptador ENet isolado para permitir trocar o transporte sem alterar o jogo.
local transport = {}
local Endpoint = {}
Endpoint.__index = Endpoint

local function enet_module()
    local ok, enet = pcall(require, "enet")
    if not ok then return nil, "O módulo ENet não está disponível nesta instalação do LÖVE." end
    return enet
end

function transport.host(port, max_peers, channels)
    local enet, err = enet_module()
    if not enet then return nil, err end
    local ok, host = pcall(enet.host_create, "*:" .. tostring(port), max_peers or 16, channels or 2)
    if not ok or not host then
        return nil, "Não foi possível abrir a porta UDP " .. tostring(port) .. ". Ela pode estar ocupada ou bloqueada."
    end
    return setmetatable({ host = host, role = "host", peer = nil, closed = false }, Endpoint)
end

function transport.connect(address, channels)
    local enet, err = enet_module()
    if not enet then return nil, err end
    local ok, host = pcall(enet.host_create)
    if not ok or not host then return nil, "Não foi possível criar o cliente de rede." end
    local peer_ok, peer = pcall(host.connect, host, address, channels or 2)
    if not peer_ok or not peer then
        host:destroy()
        return nil, "Endereço inválido. Use IPv4:porta, por exemplo 192.168.1.20:7777."
    end
    return setmetatable({ host = host, role = "client", peer = peer, closed = false }, Endpoint)
end

function Endpoint:send(peer, payload, reliable)
    if self.closed then return false end
    if self.role == "client" then
        reliable = payload
        payload = peer
        peer = self.peer
    end
    if not peer or type(payload) ~= "string" then return false end
    local channel = reliable and 1 or 0
    local flags = reliable and "reliable" or nil
    local ok, sent = pcall(peer.send, peer, payload, channel, flags)
    return ok and sent ~= false
end

function Endpoint:receive(timeout)
    if self.closed then return nil end
    local event, peer, channel, data = self.host:service(timeout or 0)
    if not event then return nil end
    -- lua-enet (bundled by LÖVE) normally returns one event table. Accept tuple
    -- returns too, so the adapter remains easy to fake in tests.
    if type(event) == "table" then
        local row = event
        return row.type, row.peer, row.channel, row.data
    end
    return event, peer, channel, data
end

function Endpoint:flush()
    if not self.closed then self.host:flush() end
end

function Endpoint:disconnect(peer, data)
    if self.closed then return end
    if self.role == "client" then
        data = peer
        peer = self.peer
    end
    if peer then peer:disconnect(data or 0) end
end

function Endpoint:close()
    if self.closed then return end
    self.closed = true
    if self.host then self.host:destroy() end
    self.host, self.peer = nil, nil
end

return transport
