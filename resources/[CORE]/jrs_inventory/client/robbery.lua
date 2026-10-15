-- Integrated JRS player robbery/search client.
-- Uses the real jrs_inventory dual-container UI and the existing @uiprompt dependency.

local robberyActive = false
local searchedServerId = nil
local searchPrompt = nil
local promptTargetPed = 0
local Core = exports['jrs_core']:getCoreApi()

local function cfg()
    return (Config and Config.Robbery) or {}
end

local function restrictions()
    return (cfg().Restrictions or {})
end

local function currentGameHour()
    local hour = nil
    if type(GetClockHours) == 'function' then
        local ok, result = pcall(GetClockHours)
        if ok then hour = tonumber(result) end
    end
    if hour == nil then
        local ok, result = pcall(Citizen.InvokeNative, 0xC82CF208C2B19199)
        if ok then hour = tonumber(result) end
    end
    if hour == nil then return -1 end
    return math.floor(hour) % 24
end

local function isAllowedNightHour(hour)
    local settings = restrictions().NightOnly or {}
    if settings.Enabled ~= true then return true end
    hour = tonumber(hour)
    if not hour or hour < 0 or hour > 23 then return false end

    local startHour = math.floor(tonumber(settings.StartHour) or 20) % 24
    local endHour = math.floor(tonumber(settings.EndHour) or 6) % 24
    if startHour == endHour then return true end
    if startHour < endHour then return hour >= startHour and hour < endHour end
    return hour >= startHour or hour < endHour
end

local function protectedZoneAt(coords)
    local settings = restrictions().ProtectedZones or {}
    if settings.Enabled ~= true or not coords then return nil end
    for _, zone in ipairs(settings.Zones or {}) do
        local zx, zy, zz = tonumber(zone.x), tonumber(zone.y), tonumber(zone.z)
        local radius = math.max(0.0, tonumber(zone.radius) or 0.0)
        if zx and zy and zz and radius > 0.0 then
            local dx = (coords.x or 0.0) - zx
            local dy = (coords.y or 0.0) - zy
            local dz = (coords.z or 0.0) - zz
            if (dx * dx + dy * dy + dz * dz) <= radius * radius then
                return tostring(zone.name or 'Protected Zone')
            end
        end
    end
    return nil
end

local function localRestrictionsAllow(playerPed, targetPed)
    local r = restrictions()
    local zones = r.ProtectedZones or {}
    if zones.Enabled == true then
        if zones.BlockSearcherInside == true and protectedZoneAt(GetEntityCoords(playerPed)) then return false end
        if targetPed and targetPed ~= 0 and zones.BlockTargetInside == true and protectedZoneAt(GetEntityCoords(targetPed)) then return false end
    end
    return isAllowedNightHour(currentGameHour())
end

local function deleteSearchPrompt()
    if searchPrompt then
        pcall(function() searchPrompt:delete() end)
        searchPrompt = nil
    end
    promptTargetPed = 0
end

local function ensureSearchPrompt(targetPed)
    if searchPrompt and promptTargetPed == targetPed then return end
    deleteSearchPrompt()
    if not targetPed or targetPed == 0 then return end
    local group = PromptGetGroupIdForTargetEntity(targetPed)
    searchPrompt = Uiprompt:new(tonumber(cfg().PromptControlHash) or 0x27D1C284, _U('searching'), group)
    promptTargetPed = targetPed
end

local function closeLocalSearch(notifyServer, closeInventory)
    if closeInventory == true then
        TriggerEvent('jrs_inventory:closeRobbery')
    end
    ClearPedTasks(PlayerPedId())
    robberyActive = false
    searchedServerId = nil
    deleteSearchPrompt()
    if notifyServer == true then
        TriggerServerEvent('jrs_inventory:robbery:closeSearch')
    end
end

local function playCustomAnim(dict, name, time, flag)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Citizen.Wait(0) end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(PlayerPedId(), dict, name, 1.0, 1.0, time, flag, 0, true, 0, false, 0, false)
    end
end

local function getClosestPlayer()
    local players = GetActivePlayers()
    if #players <= 1 then return -1, -1, nil, nil, #players end
    local closestDistanceSq, closestPlayer = math.huge, -1
    local targetServerId, targetPed = nil, nil
    local playerPed, playerId = PlayerPedId(), PlayerId()
    local coords = GetEntityCoords(playerPed)

    for i = 1, #players do
        local player = players[i]
        if player ~= playerId then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local targetCoords = GetEntityCoords(ped)
                local dx, dy, dz = coords.x - targetCoords.x, coords.y - targetCoords.y, coords.z - targetCoords.z
                local distanceSq = (dx * dx) + (dy * dy) + (dz * dz)
                if distanceSq < closestDistanceSq then
                    closestPlayer = player
                    closestDistanceSq = distanceSq
                    targetServerId = GetPlayerServerId(player)
                    targetPed = ped
                end
            end
        end
    end

    if closestPlayer == -1 then return -1, -1, nil, nil, #players end
    return closestPlayer, math.sqrt(closestDistanceSq), targetServerId, targetPed, #players
end

Citizen.CreateThread(function()
    while true do
        local perf = Config.Performance or {}
        local waitMs = math.max(0, tonumber(perf.RobberyIdleScanMs) or 750)

        if not inventoryCharacterReady or guiEnabled or cfg().Enabled == false or robberyActive then
            deleteSearchPrompt()
            Citizen.Wait(robberyActive and 1000 or waitMs)
        else
            local closestPlayer, closestDistance, targetServerId, targetPed, playerCount = getClosestPlayer()

            if (playerCount or 0) <= 1 then
                deleteSearchPrompt()
                waitMs = math.max(0, tonumber(perf.RobberyNoPlayersMs) or 1500)
            elseif closestPlayer ~= -1 and closestDistance <= (tonumber(cfg().PromptDistance) or 0.75) then
                local playerPed = PlayerPedId()
                local selfDead = GetEntityHealth(playerPed) <= 0
                local targetDead = targetPed and GetEntityHealth(targetPed) <= 0
                local onFoot = GetVehiclePedIsIn(playerPed, false) == 0 and GetMount(playerPed) == 0
                local hogtied = targetPed and Citizen.InvokeNative(0x3AA24CCC0D451379, targetPed) or false
                local holding = Citizen.InvokeNative(0xD806CD2A4F2C2996, playerPed)

                if (hogtied or targetDead) and not holding and onFoot and not selfDead and localRestrictionsAllow(playerPed, targetPed) then
                    waitMs = math.max(0, tonumber(perf.RobberyNearMs) or 15)
                    ensureSearchPrompt(targetPed)
                    local control = tonumber(cfg().PromptControlHash) or 0x27D1C284
                    if Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, control) then
                        searchedServerId = targetServerId
                        playCustomAnim('mech_pickup@loot@body@long', 'l_neck_loot', 6100, 1)
                        TriggerServerEvent('jrs_inventory:robbery:search', targetServerId, currentGameHour())
                        Citizen.Wait(1000)
                    end
                else
                    deleteSearchPrompt()
                end
            elseif closestPlayer ~= -1 and closestDistance <= math.max(0.0, tonumber(perf.RobberyMidDistance) or 3.0) then
                deleteSearchPrompt()
                waitMs = math.max(0, tonumber(perf.RobberyMidScanMs) or 150)
            else
                deleteSearchPrompt()
            end

            Citizen.Wait(waitMs)
        end
    end
end)

local robberyAnimThreadRunning = false
local function ensureRobberyAnimLoop()
    if robberyAnimThreadRunning then return end
    robberyAnimThreadRunning = true
    Citizen.CreateThread(function()
        while robberyActive do
            playCustomAnim('mech_pickup@loot@body@long', 'l_neck_loot', 6000, 1)
            Citizen.Wait(6000)
        end
        robberyAnimThreadRunning = false
    end)
end

RegisterNetEvent('jrs_inventory:robbery:notify')
AddEventHandler('jrs_inventory:robbery:notify', function(message)
    pcall(function() Core.NotifyRightTip(tostring(message), 3000) end)
end)

RegisterNetEvent('jrs_inventory:robbery:forceClose')
AddEventHandler('jrs_inventory:robbery:forceClose', function()
    closeLocalSearch(false, true)
end)

RegisterNetEvent('jrs_inventory:robbery:inventoryClosed')
AddEventHandler('jrs_inventory:robbery:inventoryClosed', function()
    closeLocalSearch(false, false)
end)

RegisterNetEvent('jrs_inventory:robbery:search')
AddEventHandler('jrs_inventory:robbery:search', function(payload)
    payload = type(payload) == 'table' and payload or {}
    searchedServerId = tonumber(payload.targetId) or searchedServerId
    robberyActive = true
    ensureRobberyAnimLoop()
    deleteSearchPrompt()
    TriggerEvent('jrs_inventory:openRobbery', payload)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        closeLocalSearch(false, true)
    end
end)
