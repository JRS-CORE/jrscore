connectedPlayers = connectedPlayers or {}
local Dev = Config.DevMode

local function collectConnectionIdentifiers(src)
    local steamIdentifier = nil
    local licenseIdentifier = nil

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 6) == "steam:" then
            steamIdentifier = identifier
        elseif identifier:sub(1, 8) == "license:" then
            licenseIdentifier = identifier
        end
    end

    return steamIdentifier, licenseIdentifier
end

-- Connection rejection is handled only by connection.lua. Tracking the player
-- here after joining prevents a second deferral handler from finishing early.
AddEventHandler("playerJoining", function()
    local src = source
    local steamIdentifier, licenseIdentifier = collectConnectionIdentifiers(src)

    connectedPlayers[src] = {
        steam = steamIdentifier,
        license = licenseIdentifier,
        lastActive = os.time()
    }
end)

AddEventHandler("playerDropped", function(reason)
    local src = source

    if connectedPlayers[src] then
        if Dev then
            print(_U('player_dropped', connectedPlayers[src].steam or connectedPlayers[src].license))
        end
        connectedPlayers[src] = nil
    end
end)

CreateThread(function()
    while true do
        Citizen.Wait(30000)
        for playerId, identifiers in pairs(connectedPlayers) do
            if not GetPlayerName(playerId) then
				if Dev then
					print(_U('removing_inactive', identifiers.steam or identifiers.license))
				end
                connectedPlayers[playerId] = nil
            end
        end
    end
end)

RegisterServerEvent("playerActivity")
AddEventHandler("playerActivity", function()
    local src = source
    if connectedPlayers[src] then
        connectedPlayers[src].lastActive = os.time()
    end
end)
