-- Ciclo de vida da sala; a lógica do jogo consome endpoint e metadados sem saber de ENet.
local transport = require "net.transport"
local discovery = require "net.discovery"

local lobby = {}
local Room = {}
Room.__index = Room

function lobby.host(port, room_name, discovery_port)
    local endpoint, err = transport.host(port, 16, 2)
    if not endpoint then return nil, err end
    local beacon, beacon_error = discovery.new("host", discovery_port)
    if not beacon then endpoint:close(); return nil, beacon_error end
    return setmetatable({ role = "host", endpoint = endpoint, discovery = beacon,
        port = port, name = room_name or "Sala RS", mode = "2v2", player_count = 1,
        addresses = discovery.local_ipv4_addresses(discovery_port), closed = false }, Room)
end

function lobby.browser(discovery_port)
    local browser, err = discovery.new("browser", discovery_port)
    if not browser then return nil, err end
    return setmetatable({ role = "browser", discovery = browser, rooms = browser.rooms, closed = false }, Room)
end

function lobby.join(address)
    if not discovery.valid_address(address) then
        return nil, "Endereço inválido. Digite um IPv4 e uma porta, como 192.168.1.20:7777."
    end
    local endpoint, err = transport.connect(address, 2)
    if not endpoint then return nil, err end
    return setmetatable({ role = "client", endpoint = endpoint, address = address,
        state = "connecting", closed = false }, Room)
end

function Room:update(dt)
    if self.closed then return end
    if self.discovery then
        self.discovery:update(dt, self.port, self.player_count, self.mode)
        self.rooms = self.discovery.rooms
    end
end

function Room:set_lobby_state(player_count, mode)
    if self.role ~= "host" then return end
    self.player_count = math.max(1, math.min(10, player_count or 1))
    if mode == "2v2" or mode == "3v3" or mode == "4v4" or mode == "5v5" then self.mode = mode end
end

function Room:close()
    if self.closed then return end
    self.closed = true
    if self.discovery then self.discovery:close() end
    if self.endpoint then self.endpoint:close() end
end

return lobby
