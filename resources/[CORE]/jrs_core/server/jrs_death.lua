-- ===================================================================
-- JRS CORE | Native Death & Hospital Respawn (Server)
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local DeadPlayers = {}

local function isPlayerDead(source)
    local src = tonumber(source)
    if not src then return false end
    return DeadPlayers[src] == true
end

local function setPlayerDead(source, isDead)
    local src = tonumber(source)
    if not src or not GetPlayerName(src) then return end

    if isDead then
        DeadPlayers[src] = true
        Player(src).state:set('isDead', true, true)
        TriggerEvent('jrs_core:server:onPlayerDeath', src)
    else
        DeadPlayers[src] = nil
        Player(src).state:set('isDead', false, true)
        TriggerEvent('jrs_core:server:onPlayerRevived', src)
    end
end

RegisterNetEvent('jrs_core:death:playerDied', function(killerSource, cause)
    local src = source
    setPlayerDead(src, true)
end)

RegisterNetEvent('jrs_core:death:requestHospitalRespawn', function()
    local src = source
    if not DeadPlayers[src] then return end

    setPlayerDead(src, false)
    TriggerClientEvent('jrs_core:death:executeHospitalRespawn', src)
end)

local function revivePlayer(source)
    local src = tonumber(source)
    if not src or not GetPlayerName(src) then return false end

    setPlayerDead(src, false)
    TriggerClientEvent('jrs_core:death:executeRevive', src)
    return true
end

local function respawnPlayer(source)
    local src = tonumber(source)
    if not src or not GetPlayerName(src) then return false end

    setPlayerDead(src, false)
    TriggerClientEvent('jrs_core:death:executeHospitalRespawn', src)
    return true
end

AddEventHandler('playerDropped', function()
    DeadPlayers[source] = nil
end)

-- Server Exports
exports('IsPlayerDead', isPlayerDead)
exports('RevivePlayer', revivePlayer)
exports('RespawnPlayer', respawnPlayer)
