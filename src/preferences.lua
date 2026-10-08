-- Leitura defensiva das preferencias armazenadas pelo LÖVE.
local preferences = {}

function preferences.read_view_width(config, filesystem)
    local default = config.camera.viewWidthDefault
    filesystem = filesystem or love.filesystem

    local ok_info, info = pcall(filesystem.getInfo, "view_width.txt", "file")
    if not ok_info or not info or (type(info) == "table" and info.type ~= "file") then
        return default
    end

    local ok_read, contents = pcall(filesystem.read, "view_width.txt")
    if not ok_read or type(contents) ~= "string" or contents == "" then
        return default
    end

    -- As parênteses descartam qualquer segundo retorno, caso a fonte mude.
    local value = tonumber((contents))
    if not value or value ~= value then return default end
    return math.max(config.camera.viewWidthMin, math.min(config.camera.viewWidthMax, value))
end

return preferences
