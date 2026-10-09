-- Verificação UDP simples para medir alcance, RTT e perdas antes do evento.
local connection_test = {}
local Test = {}
Test.__index = Test

function connection_test.loss_percent(sent, lost)
    if sent <= 0 then return 0 end
    return math.min(100, math.max(0, lost) / sent * 100)
end

local function socket_module()
    local ok, socket = pcall(require, "socket")
    if not ok then return nil, "O suporte UDP do LÖVE não está disponível." end
    return socket
end

function connection_test.receiver(port, settings)
    local socket, err = socket_module()
    if not socket then return nil, err end
    local udp = socket.udp()
    udp:settimeout(0)
    local ok, why = udp:setsockname("*", port)
    if not ok then udp:close(); return nil, "Não foi possível abrir a porta UDP " .. port .. ": " .. tostring(why) end
    local _, bound_port = udp:getsockname()
    return setmetatable({ role = "receiver", udp = udp, port = bound_port or port, received = 0,
        maxPackets = settings and settings.connectionTestMaxPacketsPerFrame or 32 }, Test)
end

function connection_test.client(address, port, settings)
    local socket, err = socket_module()
    if not socket then return nil, err end
    local udp = socket.udp()
    udp:settimeout(0)
    return setmetatable({ role = "client", udp = udp, address = address, port = port,
        elapsed = 0, interval = settings and settings.connectionTestInterval or 0.5,
        sendInterval = settings and settings.connectionTestInterval or 0.5,
        timeout = settings and settings.connectionTestTimeout or 2,
        slots = settings and settings.connectionTestSlots or 16,
        maxPackets = settings and settings.connectionTestMaxPacketsPerFrame or 32,
        nonce = 0, sent = 0, received = 0, lost = 0,
        pending = {}, pending_count = 0, ping = nil }, Test)
end

function Test:update(dt)
    if self.closed then return end
    if self.role == "receiver" then
        for _ = 1, self.maxPackets do
            local data, ip, port = self.udp:receivefrom()
            if not data then break end
            self.lastPacket = data
            self.lastPeer = ip .. ":" .. tostring(port)
            if data:sub(1, 5) == "HBPT|" then
                local _, send_error = self.udp:sendto(data, ip, port)
                self.lastError = send_error
                self.received = self.received + 1
            end
        end
        return
    end
    self.elapsed = self.elapsed + dt
    for i = 1, self.pending_count do
        local row = self.pending[i]
        if row.active and self.elapsed - row.time > self.timeout then row.active = false; self.lost = self.lost + 1 end
    end
    self.interval = self.interval + dt
    if self.interval >= self.sendInterval then
        self.interval = self.interval - self.sendInterval
        self.nonce = self.nonce + 1
        self.sent = self.sent + 1
        local slot = (self.nonce - 1) % self.slots + 1
        local row = self.pending[slot] or {}
        self.pending[slot] = row
        row.nonce, row.time, row.active = self.nonce, self.elapsed, true
        self.pending_count = math.min(self.slots, math.max(self.pending_count, slot))
        local _, send_error = self.udp:sendto("HBPT|" .. self.nonce, self.address, self.port)
        self.lastError = send_error
    end
    for _ = 1, self.maxPackets do
        local data = self.udp:receivefrom()
        if not data then break end
        local nonce = tonumber(data:match("^HBPT|(%d+)$"))
        if nonce then
            local row = self.pending[(nonce - 1) % self.slots + 1]
            if row and row.active and row.nonce == nonce then
                self.ping = (self.elapsed - row.time) * 1000
                row.active = false
                self.received = self.received + 1
            end
        end
    end
end

function Test:packet_loss()
    return connection_test.loss_percent(self.sent, self.lost)
end

function Test:close()
    if self.closed then return end
    self.closed = true
    if self.udp then self.udp:close() end
    self.udp = nil
end

return connection_test
