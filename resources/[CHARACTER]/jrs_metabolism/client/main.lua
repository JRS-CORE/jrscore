-- jrs_metabolism | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
gNeedsIsActived, isShowingHud = false, false
status = { hunger = 0, thirst = 0, health = {core = 100, normal = 200}, stamina = {core = 100, normal = 1} }
horseStatus = {}
local loadedCharacter, requestedAt, healthSentAt, damageAt = nil, -10000, 0, 0
local blockers, manuallyVisible, nuiReady = {}, true, false
local position = HUD_POSITION
local wasDead = false
function MetabolismCharacterId()
    if GetResourceState('jrs_core') ~= 'started' or not LocalPlayer or not LocalPlayer.state then return end
    if LocalPlayer.state.CharacterReady ~= true and LocalPlayer.state.jrsCharacterReady ~= true then return end
    return tonumber(LocalPlayer.state.CharacterId)
end
function MetabolismReady()
    return gNeedsIsActived and loadedCharacter ~= nil and MetabolismCharacterId() == loadedCharacter
end
local function number(value, default, low, high)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return default end
    return math.max(low, math.min(high, n))
end
function PrepareUpdateFrameFromStatus(value)
    local ped = PlayerPedId()
    return json.encode({
        hunger = value.hunger, thirst = value.thirst,
        health = { core = value.health.core, normal = number(value.health.normal / math.max(1, GetPedMaxHealth(ped)), 0, 0, 1) },
        stamina = { core = value.stamina.core, normal = number(value.stamina.normal, 0, 0, 1) },
    })
end
local function visibility()
    local visible = MetabolismReady() and manuallyVisible and next(blockers) == nil and not IsPauseMenuActive()
        and not IsEntityDead(PlayerPedId()) and not IsNuiFocused() and LocalPlayer.state.jrsHudBlocked ~= true
    if isShowingHud ~= visible or nuiReady then
        isShowingHud = visible
        SendNUIMessage({action = visible and 'open' or 'close'})
        nuiReady = false
    end
    return visible
end
local function sendFrame()
    if not MetabolismReady() then return end
    local ped = PlayerPedId()
    local mount = getLastMount(ped)
    local near = mount and mount ~= 0 and DoesEntityExist(mount) and #(GetEntityCoords(ped) - GetEntityCoords(mount)) < 2.0
    horseStatus = {}
    if near then
        horseStatus = {
            horseHealthCore = GetAttributeCoreValue(mount, 0), horseHealthNormal = GetEntityHealth(mount),
            horseHealthMax = math.max(1, GetPedMaxHealth(mount)), horseStaminaCore = GetAttributeCoreValue(mount, 1),
            horseStaminaNormal = Citizen.InvokeNative(0x22F2A386D43048A9, mount, Citizen.ResultAsFloat()),
        }
    end
    SendNUIMessage({action = 'updateNeeds', horse = near == true, horseStatus = json.encode(horseStatus),
        data = PrepareUpdateFrameFromStatus(status),
        showVoice = Config.ShowVoice, language = JrsLang.Current()})
end
local function reset()
    gNeedsIsActived, loadedCharacter, isShowingHud = false, nil, false
    requestedAt = -10000
    horseStatus = {}
    SendNUIMessage({action = 'close'})
    if ResetConsumableEffects then ResetConsumableEffects() end
end
RegisterNetEvent('jrs_core:client:characterLoaded', function() reset() end)
RegisterNetEvent('jrs_core:client:characterUnloaded', reset)
RegisterNetEvent('metabolism.UpdateStatus', function(data, charId)
    charId = tonumber(charId)
    if not charId or charId ~= MetabolismCharacterId() or type(data) ~= 'table' then return end
    loadedCharacter, gNeedsIsActived = charId, true
    status.hunger = number(data.hunger, 0, 0, 100)
    status.thirst = number(data.thirst, 0, 0, 100)
    -- Character health and stamina belong to the core/game, never replay old HUD snapshots.
    status.health = {core = GetAttributeCoreValue(PlayerPedId(), 0), normal = GetEntityHealth(PlayerPedId())}
    status.stamina = {core = GetAttributeCoreValue(PlayerPedId(), 1), normal = Citizen.InvokeNative(0x22F2A386D43048A9, PlayerPedId(), Citizen.ResultAsFloat())}
    SendNUIMessage({action = 'position', position = position})
    visibility()
    sendFrame()
end)
RegisterNetEvent('metabolism.update', function(hunger, thirst, charId)
    if not MetabolismReady() or tonumber(charId) ~= loadedCharacter then return end
    status.hunger = number(hunger, status.hunger, 0, 100)
    status.thirst = number(thirst, status.thirst, 0, 100)
    sendFrame()
end)
RegisterNUICallback('ready', function(_, cb)
    nuiReady = true
    SendNUIMessage({action = 'position', position = position})
    visibility()
    sendFrame()
    cb({ok = true})
end)
RegisterNetEvent('jrs_metabolism:setHudBlocked', function(blocked, owner)
    local key = type(owner) == 'string' and owner or 'external'
    blockers[key] = blocked == true and true or nil
    visibility()
end)
RegisterNetEvent('hud:client:display', function(show) manuallyVisible = show == true; visibility() end)
RegisterNetEvent('hud.client:disable', reset)
for _, event in ipairs({'hud.increase', 'hud.decrease'}) do
    local name = event
    RegisterNetEvent(name, function(field, amount)
        if MetabolismReady() and (field == 'hunger' or field == 'thirst') then TriggerServerEvent(name, field, amount) end
    end)
end
RegisterNetEvent('metabolism.restoreAll', function()
    if MetabolismReady() then TriggerServerEvent('metabolism.restoreAll') end
end)
RegisterNetEvent('jrs_metabolism:AdminRevive', function() TriggerServerEvent('metabolism.restoreAll') end)
AddEventHandler('jrsmetabolism:changeValue', function(field, amount)
    local key = tostring(field):lower()
    local value = number(amount, nil, -1000, 1000)
    if value and (key == 'hunger' or key == 'thirst') then TriggerServerEvent('hud.decrease', key, value / 10) end
end)
for command, target in pairs({hud1 = HUD_POSITION2, hud2 = HUD_POSITION3, hud3 = HUD_POSITION}) do
    local value = target
    RegisterCommand(command, function()
        position, manuallyVisible = value, true
        SendNUIMessage({action = 'position', position = value})
        visibility()
    end, false)
end
CreateThread(function()
    while true do
        Wait(500)
        local charId = MetabolismCharacterId()
        if loadedCharacter and charId ~= loadedCharacter then reset() end
        local now = GetGameTimer()
        if charId and not MetabolismReady() and now - requestedAt >= 3000 then
            requestedAt = now
            TriggerServerEvent('jrs_metabolism:server:initialize')
        end
        if MetabolismReady() then
            local ped = PlayerPedId()
            local dead = IsEntityDead(ped)
            if dead and not wasDead and ResetConsumableEffects then ResetConsumableEffects() end
            wasDead = dead
            status.health = {core = GetAttributeCoreValue(ped, 0), normal = GetEntityHealth(ped)}
            status.stamina = {core = GetAttributeCoreValue(ped, 1), normal = Citizen.InvokeNative(0x22F2A386D43048A9, ped, Citizen.ResultAsFloat())}
            if visibility() then sendFrame() end
            if now - healthSentAt >= 10000 then
                healthSentAt = now
                TriggerServerEvent('hud:server:UpdateHealthSistem', {health = status.health, stamina = status.stamina}, loadedCharacter)
            end
            if canApplyDamage and not IsEntityDead(ped) and now - damageAt >= Config.DamageInterval
                and (status.hunger >= Config.DamageThreshold or status.thirst >= Config.DamageThreshold) then
                damageAt = now
                NativeApplyDamageToPed(ped, (status.hunger >= Config.DamageThreshold and 1 or 0) + (status.thirst >= Config.DamageThreshold and 1 or 0))
            end
        else visibility() end
    end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'jrs_core' then reset() end
end)
