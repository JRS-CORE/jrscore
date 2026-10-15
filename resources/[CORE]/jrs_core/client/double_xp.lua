local doubleXpReady = false
local doubleXpActive = false
local nextSyncAt = 0
local lastTabSyncAt = 0

local function isCharacterReady()
    if doubleXpReady then return true end
    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.jrsCharacterReady == true or LocalPlayer.state.CharacterReady == true then
            return true
        end
    end
    local ped = PlayerPedId()
    if DoesEntityExist(ped) and not IsEntityDead(ped) and not IsScreenFadedOut() then
        return true
    end
    return false
end

local function hideDoubleXp()
    doubleXpActive = false
    SendNUIMessage({
        action = 'jrsDoubleXP:hide'
    })
end

local function requestDoubleXpState(force)
    if not isCharacterReady() then return end
    local now = GetGameTimer()
    if force then
        if now < lastTabSyncAt + 3000 then return end
        lastTabSyncAt = now
    else
        if now < nextSyncAt then return end
    end
    TriggerServerEvent('jrs_core:requestDoubleXpState')
    nextSyncAt = now + 20000
end

RegisterNetEvent('jrs_core:client:requestDoubleXp', function()
    requestDoubleXpState(true)
end)

RegisterNetEvent('jrs_core:doubleXpState', function(state)
    state = type(state) == 'table' and state or {}

    local active = state.active == true and (tonumber(state.remainingSeconds) or 0) > 0
    doubleXpActive = active

    SendNUIMessage({
        action = 'jrsDoubleXP:set',
        active = active,
        multiplier = tonumber(state.multiplier) or 1.0,
        remainingSeconds = math.max(0, math.floor(tonumber(state.remainingSeconds) or 0)),
        durationSeconds = math.max(0, math.floor(tonumber(state.durationSeconds) or 0)),
        endsAt = tonumber(state.endsAt) or 0,
    })
end)

local function markReady()
    doubleXpReady = true
    requestDoubleXpState(true)
end

RegisterNetEvent('jrs_core:client:characterReady', markReady)
RegisterNetEvent('jrs:isPlayerready', markReady)
RegisterNetEvent('jrs:isPlayerReady', markReady)
RegisterNetEvent('jrscore:sett', markReady)

RegisterNetEvent('jrs_core:client:characterUnloaded', function()
    doubleXpReady = false
    hideDoubleXp()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(500)
    doubleXpReady = isCharacterReady()
    requestDoubleXpState(true)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    hideDoubleXp()
end)

CreateThread(function()
    while true do
        local readyNow = isCharacterReady()

        if readyNow and not doubleXpReady then
            doubleXpReady = true
            requestDoubleXpState(true)
        elseif not readyNow and doubleXpReady then
            doubleXpReady = false
            hideDoubleXp()
        elseif readyNow and doubleXpActive and GetGameTimer() >= nextSyncAt then
            requestDoubleXpState(false)
        end

        Wait(doubleXpActive and 1000 or 2500)
    end
end)
