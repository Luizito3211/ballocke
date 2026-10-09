-- Agendador opcional de atraso/perda para exercitar o protocolo sem mudar ENet.
local simulator = {}
local Simulator = {}
Simulator.__index = Simulator

local function deliver(endpoint, client, peer, packet, reliable)
    if client then return endpoint:send(packet, reliable) end
    return endpoint:send(peer, packet, reliable)
end

function simulator.new(latency_ms, loss_percent, capacity, seed)
    capacity = capacity or 512
    local queue = {}
    for i = 1, capacity do queue[i] = { due = 0, peer = nil, packet = nil, reliable = false } end
    return setmetatable({ latency = math.max(0, latency_ms or 0) / 1000,
        loss = math.max(0, math.min(100, loss_percent or 0)), queue = queue,
        capacity = capacity, head = 1, count = 0, random = seed or 2463534242,
        dropped = 0, delivered = 0 }, Simulator)
end

function Simulator:_drop()
    self.random = (self.random * 16807) % 2147483647
    return self.random / 2147483647 * 100 < self.loss
end

function Simulator:send(now, endpoint, client, peer, packet, reliable)
    if not reliable and self:_drop() then self.dropped = self.dropped + 1; return false end
    if self.latency <= 0 then
        local ok = deliver(endpoint, client, peer, packet, reliable)
        if ok then self.delivered = self.delivered + 1 end
        return ok
    end
    if self.count == self.capacity then
        local old = self.queue[self.head]
        old.packet, old.peer = nil, nil
        self.head = self.head % self.capacity + 1
        self.count = self.count - 1
        self.dropped = self.dropped + 1
    end
    local index = (self.head + self.count - 1) % self.capacity + 1
    local row = self.queue[index]
    row.due, row.peer, row.packet, row.reliable = now + self.latency, peer, packet, reliable
    self.count = self.count + 1
    return true
end

function Simulator:flush(now, endpoint, client)
    while self.count > 0 do
        local row = self.queue[self.head]
        if row.due > now then break end
        local ok = deliver(endpoint, client, row.peer, row.packet, row.reliable)
        if ok then self.delivered = self.delivered + 1 end
        row.packet, row.peer = nil, nil
        self.head = self.head % self.capacity + 1
        self.count = self.count - 1
    end
end

return simulator
