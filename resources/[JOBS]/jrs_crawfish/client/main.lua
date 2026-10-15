-- jrs_crawfish | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_crawfish | client
-- Prompt at every hole, the animation and the progress bar. The server decides everything that matters.

local Core = exports.jrs_core:GetCore()
local busy = false                       -- searching or harvesting right now

local function bar()
    return GetResourceState('jrs_progressbar') == 'started' and exports.jrs_progressbar:initiate() or nil
end

local function dead() return IsPedDeadOrDying(PlayerPedId(), false) end

local function complain(result)
    if result and result.why then Core.NotifyObjective(result.why, 5000) end
end

-- Runs one timed job: ask the server to begin, play the animation, wait out the bar, ask it to finish.
local function runJob(kind, hole, label, playAnimation, stopAnimation)
    if busy then return end
    busy = true

    local started = Core.Callback.TriggerAwait('jrs_crawfish:begin', kind, hole)
    if not (started and started.ok) then
        complain(started)
        busy = false
        return
    end
    if dead() then
        TriggerServerEvent('jrs_crawfish:abort')
        busy = false
        return
    end

    playAnimation(started.time)

    local progress = bar()
    local look = Config.Bar
    local settled = promise.new()
    if progress then
        progress.start(label, started.time, function() settled:resolve(true) end, look.theme, look.color, look.width, look.focus)
    else
        SetTimeout(started.time, function() settled:resolve(true) end)
    end
    Citizen.Await(settled)

    if dead() then
        TriggerServerEvent('jrs_crawfish:abort')
    else
        complain(Core.Callback.TriggerAwait('jrs_crawfish:finish'))
    end
    stopAnimation()
    busy = false
end

local function search(hole)
    runJob('search', hole, Say('searching'),
        function(ms) TaskStartScenarioInPlaceHash(PlayerPedId(), joaat('WORLD_HUMAN_CROUCH_INSPECT'), ms, true, '', 0, false) end,
        function() ClearPedTasksImmediately(PlayerPedId()) end)
end

local ANIM_DICT, ANIM_NAME = 'mech_skin@chicken@field_dress', 'success'

RegisterNetEvent('jrs_crawfish:harvest', function()
    runJob('harvest', nil, Say('harvesting'),
        function()
            RequestAnimDict(ANIM_DICT)
            while not HasAnimDictLoaded(ANIM_DICT) do Wait(0) end
            TaskPlayAnim(PlayerPedId(), ANIM_DICT, ANIM_NAME, 1.0, 1.0, Config.HarvestTime - 1000, 16, 0.0, false, 0, false, '', false)
        end,
        function()
            ClearPedTasksImmediately(PlayerPedId())
            RemoveAnimDict(ANIM_DICT)
        end)
end)

-- ------------------------------------------------------------------ hole prompt

local function makePrompt()
    local group = GetRandomIntInRange(0, 0xffffff)
    local prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, Config.PromptKey)
    UiPromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', Config.Text.en.prompt))   -- game font: English only
    UiPromptSetEnabled(prompt, true)
    UiPromptSetStandardMode(prompt, true)
    UiPromptSetGroup(prompt, group, 0)
    UiPromptRegisterEnd(prompt)
    return prompt, group
end

CreateThread(function()
    while not LocalPlayer.state.IsInSession do Wait(2000) end
    local prompt, group = makePrompt()

    while true do
        local wait = 1000
        local ped = PlayerPedId()

        if not busy and not dead() and not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped, true) then
            local here = GetEntityCoords(ped)
            for index, at in ipairs(Config.Holes) do
                if #(here - at) <= Config.HoleReach then
                    wait = 0
                    UiPromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', Config.Text.en.search), 0, 0, 0, 0)
                    if UiPromptHasStandardModeCompleted(prompt, 0) then
                        CreateThread(function() search(index) end)
                    end
                    break
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and busy then
        TriggerServerEvent('jrs_crawfish:abort')
    end
end)
