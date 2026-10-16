-- jrs_npcs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local spawned, blips, audioPlayed = {}, {}, {}

local function hasXsound()
    return GetResourceState('xsound') == 'started'
end

local function loadModel(model)
    if not IsModelValid(model) then return false end
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(50) end
    return HasModelLoaded(model)
end

local function fade(ped, from, to)
    if not Config.FadeIn then return end
    local step = from < to and 51 or -51
    for a = from, to, step do
        if not DoesEntityExist(ped) then return end
        SetEntityAlpha(ped, a, false)
        Wait(50)
    end
end

local function spawn(i, data)
    local model = joaat(data.model)
    if not loadModel(model) then
        print(('[jrs_npcs] invalid model %s (entry %d)'):format(tostring(data.model), i))
        spawned[i] = false
        return
    end
    local c = data.coords
    local ped = CreatePed(model, c.x, c.y, c.z - 1.0, c.w, false, false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetRandomOutfitVariation(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanBeTargetted(ped, false)
    if data.scenario then
        TaskStartScenarioInPlace(ped, joaat(data.scenario), -1, true, false, false, false)
    end
    spawned[i] = ped
    if Config.FadeIn then
        SetEntityAlpha(ped, 0, false)
        CreateThread(function() fade(ped, 0, 255) end)
    end
end

local function despawn(i)
    local ped = spawned[i]
    spawned[i] = nil
    audioPlayed[i] = nil
    if not ped then return end
    CreateThread(function()
        fade(ped, 255, 0)
        if DoesEntityExist(ped) then DeletePed(ped) end
    end)
end

local function playAudio(i, data, dist)
    local a = data.audio
    if not a or not a.url or not hasXsound() then return end
    if dist <= (a.distance or 4.0) and not audioPlayed[i] then
        audioPlayed[i] = true
        local name = ('jrs_npcs_%d'):format(i)
        exports.xsound:PlayUrlPos(name, a.url, a.volume or 0.6, data.coords.xyz, false)
        exports.xsound:Distance(name, (a.distance or 4.0) * 3)
    elseif dist > (a.distance or 4.0) + 3.0 then
        audioPlayed[i] = nil
    end
end

CreateThread(function()
    for _, data in ipairs(Config.Peds) do
        if data.blip then
            local c = data.coords
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, c.x, c.y, c.z) -- BlipAddForCoords
            SetBlipSprite(blip, joaat(data.blip.sprite or 'blip_ambient_npc'), true)
            SetBlipScale(blip, data.blip.scale or 0.2)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, tostring(data.blip.name or 'NPC')) -- SetBlipName
            blips[#blips + 1] = blip
        end
    end

    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for i, data in ipairs(Config.Peds) do
            local dist = #(pos - data.coords.xyz)
            if dist < Config.SpawnDistance then
                if spawned[i] == nil then spawn(i, data) end
                if spawned[i] then playAudio(i, data, dist) end
            elseif spawned[i] then
                despawn(i)
            elseif spawned[i] == false and dist > Config.SpawnDistance * 2 then
                spawned[i] = nil -- retry a broken model later
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for i, ped in pairs(spawned) do
        if ped and DoesEntityExist(ped) then DeletePed(ped) end
        if hasXsound() then pcall(exports.xsound.Destroy, exports.xsound, ('jrs_npcs_%d'):format(i)) end
    end
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
end)
