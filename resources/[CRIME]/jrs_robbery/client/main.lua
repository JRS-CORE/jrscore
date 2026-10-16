-- jrs_robbery | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local HANDS_DICT = 'script_proc@robberies@homestead@lonnies_shack@deception'
local HANDS_ANIM = 'hands_up_loop'

local handsUp, cuffed = false, false
local handsUpSince = 0

local function loadDict(dict)
    RequestAnimDict(dict)
    local t = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(50) end
    return HasAnimDictLoaded(dict)
end

---------------------------------------------------------------- hands up
local function setHandsUp(state)
    local ped = PlayerPedId()
    if state and (cuffed or IsEntityDead(ped) or IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false)) then return end
    handsUp = state
    handsUpSince = GetGameTimer()
    LocalPlayer.state:set('jrs_handsup', state, true)
    if state then
        if loadDict(HANDS_DICT) then
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true, 0, false, false)
            TaskPlayAnim(ped, HANDS_DICT, HANDS_ANIM, 2.0, -2.0, -1, 31, 0.0, false, 0, false, 'UpperbodyFixup_filter', false)
        end
    else
        StopAnimTask(ped, HANDS_DICT, HANDS_ANIM, 2.0)
    end
end

if Config.HandsUpCommand then
    RegisterCommand(Config.HandsUpCommand, function() setHandsUp(not handsUp) end, false)
    TriggerEvent('chat:addSuggestion', '/' .. Config.HandsUpCommand, L('handsup_help'))
end

-- the animation can be broken by ragdoll, mounting, death... drop the state with it
CreateThread(function()
    while true do
        Wait(1000)
        if handsUp and GetGameTimer() - handsUpSince > 1500 and not IsEntityPlayingAnim(PlayerPedId(), HANDS_DICT, HANDS_ANIM, 3) then
            setHandsUp(false)
        end
    end
end)

if Config.HandsUpKey then
    CreateThread(function()
        while true do
            Wait(0)
            if IsControlJustPressed(0, Config.HandsUpKey) and not IsPauseMenuActive() then
                setHandsUp(not handsUp)
                Wait(500)
            end
        end
    end)
end

---------------------------------------------------------------- restrained
-- same set jrs_robbery blocks: attack, aim, melee, jump, mount, weapon wheel, satchel, horse
local BLOCKED = {
    0x295175BF, 0x6E9734E8, 0xD8F73058, 0x4CC0E2FE, 0x5966D52A,
    0xCEFD9220, 0x41AC83D1, 0x9D2AEA88, 0xE474F150,
}

RegisterNetEvent('jrs_robbery:client:setCuffed', function(state)
    local ped = PlayerPedId()
    cuffed = state
    if state then
        setHandsUp(false)
        ClearPedTasksImmediately(ped)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true, 0, false, false)
        SetEnableHandcuffs(ped, true, false)
        DisablePlayerFiring(PlayerId(), true)
        CreateThread(function()
            while cuffed do
                for _, c in ipairs(BLOCKED) do DisableControlAction(0, c, true) end
                Wait(0)
            end
        end)
    else
        SetEnableHandcuffs(ped, false, false)
        DisablePlayerFiring(PlayerId(), false)
        ClearPedTasks(ped)
    end
end)

---------------------------------------------------------------- prompts (no the JRS interaction prompt)
local group = GetRandomIntInRange(0, 0xffffff)
local robPrompt, uncuffPrompt

local function makePrompt(text)
    local p = UiPromptRegisterBegin()
    UiPromptSetControlAction(p, Config.PromptKey)
    UiPromptSetText(p, VarString(10, 'LITERAL_STRING', text))
    UiPromptSetEnabled(p, true)
    UiPromptSetVisible(p, true)
    UiPromptSetHoldMode(p, 1000)
    UiPromptSetGroup(p, group, 0)
    UiPromptRegisterEnd(p)
    return p
end

CreateThread(function()
    robPrompt = makePrompt(L('rob'))
    uncuffPrompt = makePrompt(L('uncuff'))
end)

local function closestPlayer(maxDist)
    local me = PlayerPedId()
    local myPos = GetEntityCoords(me)
    local best, bestDist
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            local d = #(GetEntityCoords(ped) - myPos)
            if d <= maxDist and (not bestDist or d < bestDist) and not IsEntityDead(ped) then
                best, bestDist = pid, d
            end
        end
    end
    return best
end

CreateThread(function()
    while true do
        local wait = 400
        local me = PlayerPedId()
        if robPrompt and not cuffed and not IsEntityDead(me) and IsPedOnFoot(me) then
            local pid = closestPlayer(Config.RobDistance)
            if pid then
                local serverId = GetPlayerServerId(pid)
                local st = Player(serverId).state
                local canUncuff = st.jrs_robbery_cuffed == true
                local canRob = not canUncuff and st.jrs_handsup == true and IsPedOnFoot(GetPlayerPed(pid))
                if canUncuff or canRob then
                    wait = 0
                    UiPromptSetVisible(robPrompt, canRob)
                    UiPromptSetVisible(uncuffPrompt, canUncuff)
                    -- the group title must be a fresh VarString every frame
                    UiPromptSetActiveGroupThisFrame(group, VarString(10, 'LITERAL_STRING', L('group')), 0, 0, 0, 0)
                    if canRob and UiPromptHasHoldModeCompleted(robPrompt) then
                        TriggerServerEvent('jrs_robbery:server:rob', serverId)
                        Wait(1500)
                    elseif canUncuff and UiPromptHasHoldModeCompleted(uncuffPrompt) then
                        TriggerServerEvent('jrs_robbery:server:uncuff', serverId)
                        Wait(1500)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if handsUp then StopAnimTask(PlayerPedId(), HANDS_DICT, HANDS_ANIM, 2.0) end
    LocalPlayer.state:set('jrs_handsup', false, true)
    if cuffed then
        SetEnableHandcuffs(PlayerPedId(), false, false)
        DisablePlayerFiring(PlayerId(), false)
    end
    if robPrompt then UiPromptDelete(robPrompt) end
    if uncuffPrompt then UiPromptDelete(uncuffPrompt) end
end)
