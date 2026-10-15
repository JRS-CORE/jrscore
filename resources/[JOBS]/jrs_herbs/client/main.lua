-- jrs_herbs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_herbs | client
-- Finds the plant the player is standing at (a world plant by model, or a fixed spot from the config),
-- shows a hold-to-pick prompt, and asks the server to pay out.

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local WILD, SPOTS = Config.WildPlants, Config.Spots
local picking, dead = false, false
local spawned = {}                       -- spot index -> object entity

-- model hashes of the wild plants, so one scan can look for all of them
local wildHash = {}
for i, def in ipairs(WILD) do wildHash[i] = joaat(def.model) end

-- ------------------------------------------------------------------ prompt

local prompt, group
local function makePrompt()
    group = GetRandomIntInRange(0, 0xffffff)
    prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, Config.PromptKey)
    UiPromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', Text.pick))
    UiPromptSetHoldMode(prompt, Config.HoldTime)
    UiPromptSetGroup(prompt, group, 0)
    UiPromptRegisterEnd(prompt)
end

-- ------------------------------------------------------------------ what is here?

-- returns plant number (wild first, then spots), its position and its name
local function findPlant(here)
    for i, hash in ipairs(wildHash) do
        local obj = GetClosestObjectOfType(here.x, here.y, here.z, Config.Reach + 0.5, hash, false, false, false)
        if obj ~= 0 and DoesEntityExist(obj) then
            return i, GetEntityCoords(obj), WILD[i].label
        end
    end
    for i, spot in ipairs(SPOTS) do
        if #(here - spot.at) <= Config.Reach then
            return #WILD + i, spot.at, spot.label
        end
    end
end

-- fixed spots that want a model: create it when close, remove it when far
local function syncSpots(here)
    for i, spot in ipairs(SPOTS) do
        if spot.spawn then
            local near = #(here - spot.at) <= Config.SpotRange
            if near and not spawned[i] then
                local model = joaat(spot.model)
                RequestModel(model)
                local limit = GetGameTimer() + 3000
                while not HasModelLoaded(model) and GetGameTimer() < limit do Wait(0) end
                if HasModelLoaded(model) then
                    local obj = CreateObject(model, spot.at.x, spot.at.y, spot.at.z, false, false, false)
                    PlaceObjectOnGroundProperly(obj)
                    FreezeEntityPosition(obj, true)
                    SetModelAsNoLongerNeeded(model)
                    spawned[i] = obj
                end
            elseif not near and spawned[i] then
                DeleteEntity(spawned[i])
                spawned[i] = nil
            end
        end
    end
end

-- ------------------------------------------------------------------ picking

local ANIM = 'mech_ransack@shelf@h150cm@d80cm@reach_up@pickup@vertical@right_50cm@a'

local function pick(index, at)
    picking = true
    local result = Core.Callback.TriggerAwait('jrs_herbs:pick', index, at)

    if result and result.ok then
        local ped = PlayerPedId()
        TaskTurnPedToFaceCoord(ped, at.x, at.y, at.z, -1)
        Wait(2000)
        ClearPedTasks(ped)
        RequestAnimDict(ANIM)
        while not HasAnimDictLoaded(ANIM) do Wait(0) end
        TaskPlayAnim(ped, ANIM, 'enter_rf', 8.0, 8.0, -1, 1, 0, false, false, false)
        TaskPlayAnim(ped, ANIM, 'base', 8.0, 8.0, -1, 1, 0, false, false, false)
        Wait(700)
        ClearPedTasks(ped)
        RemoveAnimDict(ANIM)
    elseif result and result.why then
        Core.NotifyRightTip(result.why, 4000)
    end

    Wait(1000)
    picking = false
end

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(5000) end
    makePrompt()

    local scanAt = 0
    local index, at, label
    while true do
        local wait = 700
        if not dead and not picking then
            local here = GetEntityCoords(PlayerPedId())

            if GetGameTimer() >= scanAt then
                scanAt = GetGameTimer() + 700
                syncSpots(here)
                index, at, label = findPlant(here)
            end

            if index then
                wait = 0
                UiPromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', label), 0, 0, 0, 0)
                if UiPromptHasHoldModeCompleted(prompt) then
                    local i, p = index, at
                    index = nil
                    CreateThread(function() pick(i, p) end)
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('jrs_core:Client:OnPlayerDeath', function() dead = true end)
RegisterNetEvent('jrs_core:Client:OnPlayerRevive', function() dead = false end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, obj in pairs(spawned) do DeleteEntity(obj) end
end)
