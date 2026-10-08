-- Registro circular de eventos do árbitro. Escrita apenas ao descarregar o buffer.
local EventLog = {}
EventLog.__index = EventLog

function EventLog.new(filesystem, config)
    local capacity = config.capacity or 2000
    local self = setmetatable({
        fs = filesystem or love.filesystem, path = config.path or "arbitro.log",
        capacity = capacity, lines = {}, count = 0, first = 1,
        dirty = false, elapsed = 0, flushInterval = config.flushInterval or 3,
        parts = {},
    }, EventLog)
    if self.fs.getInfo and self.fs.getInfo(self.path) then
        local ok, content = pcall(self.fs.read, self.path)
        if ok and type(content) == "string" then
            for line in content:gmatch("[^\r\n]+") do self:append(line) end
            self.dirty = false
        end
    end
    return self
end

function EventLog.append(self, line)
    local index
    if self.count < self.capacity then
        index = (self.first + self.count - 1) % self.capacity + 1
        self.count = self.count + 1
    else
        index = self.first
        self.first = self.first % self.capacity + 1
    end
    self.lines[index] = line
    self.dirty = true
end

function EventLog.record(self, match_time, half, half_remaining, kind, old_state,
                         new_state, reason, ball_x, ball_y)
    if not reason or reason == "" then reason = "motivo não informado" end
    self:append(string.format("t=%.3f; tempo=%dº/%.3f; tipo=%s; %s -> %s; motivo=%s; bola=(%.2f,%.2f)",
        match_time or 0, half or 1, half_remaining or 0, kind or "ESTADO",
        old_state or "-", new_state or "-", reason, ball_x or 0, ball_y or 0))
end

function EventLog.update(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= self.flushInterval then
        self.elapsed = 0
        self:flush()
    end
end

function EventLog.flush(self)
    if not self.dirty then return true end
    local parts, count = self.parts, 0
    for i = 0, self.count - 1 do
        count = count + 1
        parts[count] = self.lines[(self.first + i - 1) % self.capacity + 1]
    end
    for i = count + 1, #parts do parts[i] = nil end
    local ok, written = pcall(self.fs.write, self.path, table.concat(parts, "\n", 1, count) .. "\n")
    if ok and written ~= false and written ~= nil then self.dirty = false end
    return ok
end

return EventLog
