-- jrs_wildhorse | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_wildhorse | client
-- Trainers (NPC + blip + sell prompt) and remembering which horse this player broke in. The server pays.

local Core = exports.jrs_core:GetCore()
local brokenIn = {}                       -- horse entity -> true, for horses this player broke in

local function say(text) Core.NotifyRightTip(text, 4000) end
RegisterNetEvent('jrs_wildhorse:notify', say)

-- ------------------------------------------------------------------ trainers

local function loadModel(name)
    local model = type(name) == 'string' and joaat(name) or name
    if not IsModelValid(model) then return end
    RequestModel(model)
    local limit = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < limit do Wait(50) end
    if HasModelLoaded(model) then return model end
end

local function showTrainer(trainer)
    local model = loadModel(trainer.npcmodel)
    if not model then
        print(('[jrs_wildhorse] invalid trainer model %s'):format(tostring(trainer.npcmodel)))
        trainer.skip = true
        return
    end
    local at = trainer.coords
    local ped = CreatePed(model, at.x, at.y, at.z, trainer.heading, false, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 then return end

    SetRandomOutfitVariation(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    trainer.ped = ped
end

local function hideTrainer(trainer)
    if trainer.ped and DoesEntityExist(trainer.ped) then DeleteEntity(trainer.ped) end
    trainer.ped = nil
end

local function addBlips()
    for _, trainer in ipairs(Config.trainers) do
        local at = trainer.coords
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, at.x, at.y, at.z)
        SetBlipSprite(blip, trainer.blip, true)
        SetBlipScale(blip, 0.2)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, trainer.trainername or LE('blip'))
        trainer.blipHandle = blip
    end
end

-- ------------------------------------------------------------------ noticing a horse being broken in

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(2000) end
    addBlips()

    while true do
        Wait(0)
        for i = 0, GetNumberOfEvents(0) - 1 do
            if GetEventAtIndex(0, i) == `EVENT_HORSE_BROKEN` then
                local mount = GetMount(PlayerPedId())
                if mount ~= 0 and not brokenIn[mount] and NetworkGetEntityIsNetworked(mount) then
                    brokenIn[mount] = true
                    TriggerServerEvent('jrs_sellhorse:brokeHorse', NetworkGetNetworkIdFromEntity(mount))
                end
            end
        end
    end
end)

-- ------------------------------------------------------------------ selling

local function sell(index)
    local ped = PlayerPedId()
    local horse = GetMount(ped)

    if horse == 0 then return say(L('no_mount')) end
    if not NetworkGetEntityIsNetworked(horse) then return say(L('not_net')) end

    local model = GetEntityModel(horse)
    if not Config.Animals[model] then return say(L('not_wanted')) end
    if not brokenIn[horse] then return say(L('not_broken')) end

    TriggerServerEvent('jrs_sellhorse:giveReward', { index = index, model = model, netid = NetworkGetNetworkIdFromEntity(horse) })
    TaskDismountAnimal(ped, 17, 0, 0, 0, horse)
    brokenIn[horse] = nil
end

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(2000) end

    local group = GetRandomIntInRange(0, 0x7FFFFFFF)
    local prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, Config.SellKey)
    UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', LE('prompt')))
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, true)
    UiPromptSetHoldMode(prompt, 1000)
    UiPromptSetGroup(prompt, group, 0)
    UiPromptRegisterEnd(prompt)

    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() then UiPromptDelete(prompt) end
    end)

    while true do
        local wait = 1000
        local here = GetEntityCoords(PlayerPedId())

        for index, trainer in ipairs(Config.trainers) do
            local away = #(here - trainer.coords)

            if Config.aiTrainerped and not trainer.skip then
                if away < 80.0 and not trainer.ped then showTrainer(trainer)
                elseif away >= 90.0 and trainer.ped then hideTrainer(trainer) end
            end

            if away <= trainer.radius then
                wait = 0
                UiPromptSetActiveGroupThisFrame(group, VarString(10, 'LITERAL_STRING', trainer.trainername), 0, 0, 0, 0)
                if UiPromptHasHoldModeCompleted(prompt) then
                    sell(index)
                    Wait(1500)
                end
            elseif away < 30.0 then
                wait = math.min(wait, 250)
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, trainer in ipairs(Config.trainers) do
        hideTrainer(trainer)
        if trainer.blipHandle then RemoveBlip(trainer.blipHandle) end
    end
end)
