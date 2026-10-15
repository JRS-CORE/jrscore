-- ==========================================================================
--  JRS CORE  |  jrs_radius  |  server.lua
--  Sets every player's culling radius from how crowded their surroundings are.
--  Written by the JRS TEAM.
-- ==========================================================================

local lastSent = {}   -- [source] = radius last applied to that player

-- A quiet area gets the full radius; the more players around, the closer it
-- shrinks towards the minimum. At `CrowdedAt` neighbours it sits on the minimum.
local function radiusForNeighbours(count)
    local crowd = math.min(count / Config.CrowdedAt, 1.0)
    return Config.MaxRadius - (Config.MaxRadius - Config.MinRadius) * crowd
end

local function onlinePositions()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local source = tonumber(id)
        local ped = source and GetPlayerPed(source)
        if ped and ped ~= 0 then
            list[#list + 1] = { source = source, coords = GetEntityCoords(ped) }
        end
    end
    return list
end

local function refresh()
    local players = onlinePositions()
    local reach = Config.CrowdRadius * Config.CrowdRadius
    local neighbours = {}
    for i = 1, #players do neighbours[i] = 0 end

    -- Count each close pair once and credit both sides.
    for i = 1, #players - 1 do
        local a = players[i].coords
        for j = i + 1, #players do
            local b = players[j].coords
            local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
            if dx * dx + dy * dy + dz * dz <= reach then
                neighbours[i] = neighbours[i] + 1
                neighbours[j] = neighbours[j] + 1
            end
        end
    end

    for i = 1, #players do
        local source = players[i].source
        local radius = radiusForNeighbours(neighbours[i])
        -- Skip tiny changes so the network is not touched every cycle for nothing.
        if not lastSent[source] or math.abs(lastSent[source] - radius) >= 1.0 then
            lastSent[source] = radius
            SetPlayerCullingRadius(source, radius + 0.0)
        end
    end
end

CreateThread(function()
    local interval = math.max(1, tonumber(Config.RefreshSecond) or 20) * 1000
    while true do
        Wait(interval)
        refresh()
    end
end)

AddEventHandler('playerDropped', function()
    lastSent[source] = nil
end)
