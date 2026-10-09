-- Descoberta de salas locais por broadcast UDP (LuaSocket embutido no LÖVE).
local discovery = {}
local Discovery = {}
Discovery.__index = Discovery

local DEFAULT_PORT = 47778
local MAX_ROOMS = 16
local ROOM_TTL = 5

local function load_socket()
    local ok, socket = pcall(require, "socket")
    if not ok then return nil, "O suporte UDP do LÖVE não está disponível." end
    return socket
end

function discovery.new(role, port)
    local socket, err = load_socket()
    if not socket then return nil, err end
    local self = setmetatable({ socket = socket, role = role, port = port or DEFAULT_PORT,
        rooms = {}, elapsed = 1, closed = false }, Discovery)
    if role == "host" then
        local ok, udp = pcall(socket.udp)
        if not ok or not udp then return nil, "Não foi possível iniciar o anúncio UDP da sala." end
        self.sender = udp
        pcall(udp.setoption, udp, "broadcast", true)
        pcall(udp.settimeout, udp, 0)
    else
        local ok, udp = pcall(socket.udp)
        if not ok or not udp then return nil, "Não foi possível escutar anúncios de salas." end
        self.listener = udp
        pcall(udp.setoption, udp, "reuseaddr", true)
        pcall(udp.settimeout, udp, 0)
        local bound, bind_error = udp:setsockname("*", self.port)
        if not bound then udp:close(); return nil, "Não foi possível escutar a descoberta UDP: " .. tostring(bind_error) end
    end
    return self
end

local function valid_ipv4(ip, allow_loopback)
    if type(ip) ~= "string" or not ip:match("^%d+%.%d+%.%d+%.%d+$") or (not allow_loopback and ip:match("^127%.")) then return false end
    for part in ip:gmatch("%d+") do if tonumber(part) > 255 then return false end end
    return true
end

function discovery.local_ipv4_addresses(port)
    local socket = load_socket()
    if not socket then return { "127.0.0.1" } end
    local found, seen = {}, {}
    local function add(ip)
        if valid_ipv4(ip) and not seen[ip] then seen[ip] = true; found[#found + 1] = ip end
    end
    local host = socket.dns.gethostname()
    if host and socket.dns.getaddrinfo then
        local ok, infos = pcall(socket.dns.getaddrinfo, host)
        if ok and type(infos) == "table" then
            for i = 1, #infos do add(infos[i].addr) end
        end
    end
    local ok, udp = pcall(socket.udp)
    if ok and udp then
        pcall(udp.settimeout, udp, 0)
        local connected = pcall(udp.setpeername, udp, "255.255.255.255", port or DEFAULT_PORT)
        if connected then
            local ip = udp:getsockname()
            add(ip)
        end
        udp:close()
    end
    if #found == 0 then found[1] = "127.0.0.1" end
    return found
end

function Discovery:announce(name, room_port, players, mode)
    if not self.sender or self.closed then return false end
    name = tostring(name or "Sala RS"):gsub("[^%w _%-]", ""):sub(1, 24)
    local packet = string.format("HBRS|1|%d|%d|%s|%s", room_port, players or 1, mode or "2v2", name)
    local sent = self.sender:sendto(packet, "255.255.255.255", self.port)
    return sent ~= nil
end

function Discovery:update(dt, room_port, players, mode)
    if self.closed then return end
    if self.role == "host" then
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 1 then
            self.elapsed = 0
            self:announce("Sala RS", room_port, players, mode)
        end
        return
    end
    for i = #self.rooms, 1, -1 do
        self.rooms[i].age = self.rooms[i].age + dt
        if self.rooms[i].age > ROOM_TTL then table.remove(self.rooms, i) end
    end
    if not self.listener then return end
    for _ = 1, MAX_ROOMS do
        local packet, ip = self.listener:receivefrom()
        if not packet then break end
        local version, room_port_s, players_s, mode_s, name = packet:match("^HBRS|(%d+)|(%d+)|(%d+)|([%w]+)|([%w _%-]+)$")
        local room_port, player_count = tonumber(room_port_s), tonumber(players_s)
        if version == "1" and room_port and room_port > 0 and room_port <= 65535 and
           player_count and player_count >= 1 and player_count <= 10 then
            local address = ip .. ":" .. room_port
            local existing
            for i = 1, #self.rooms do if self.rooms[i].address == address then existing = self.rooms[i]; break end end
            if existing then
                existing.players, existing.mode, existing.name, existing.age = player_count, mode_s, name, 0
            elseif #self.rooms < MAX_ROOMS then
                self.rooms[#self.rooms + 1] = { address = address, players = player_count,
                    mode = mode_s, name = name, age = 0 }
            end
        end
    end
end

function Discovery:close()
    if self.closed then return end
    self.closed = true
    if self.sender then self.sender:close() end
    if self.listener then self.listener:close() end
    self.sender, self.listener = nil, nil
end

function discovery.valid_address(address)
    if type(address) ~= "string" then return false end
    local ip, port = address:match("^([%d%.]+):(%d+)$")
    if not ip or not valid_ipv4(ip, true) then return false end
    port = tonumber(port)
    return port and port >= 1 and port <= 65535
end

return discovery
