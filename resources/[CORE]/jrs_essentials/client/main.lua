-- jrs_essentials | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
---------------------------------------------------------------- AFK kick
if Config.Afk.enabled then
    CreateThread(function()
        Wait(30000)
        if JRS.Await('jrs_essentials:afkExempt') then return end
        local warn = {}
        for _, s in ipairs(Config.Afk.warnAt) do warn[s] = true end

        local lastPos, left = nil, Config.Afk.seconds
        while true do
            Wait(1000)
            local pos = GetEntityCoords(PlayerPedId())
            if lastPos and #(pos - lastPos) < 0.05 and not IsPauseMenuActive() then
                left = left - 1
                if warn[left] then
                    JRS.Notify(left >= 60 and L('afk_warn_min', math.ceil(left / 60)) or L('afk_warn_sec', left), 6000)
                end
                if left <= 0 then
                    TriggerServerEvent('jrs_essentials:server:afk')
                    left = Config.Afk.seconds
                end
            else
                left = Config.Afk.seconds
            end
            lastPos = pos
        end
    end)
end

---------------------------------------------------------------- pointing
if Config.Pointing.enabled then
    local DICT = 'script_common@other@unapproved'
    CreateThread(function()
        local pointing = false
        while true do
            Wait(0)
            local ped = PlayerPedId()
            local held = IsControlPressed(0, Config.Pointing.key) and IsPedOnFoot(ped) and not IsPauseMenuActive()
            if held and not pointing then
                pointing = true
                if JRS.LoadDict(DICT) then
                    TaskPlayAnim(ped, DICT, 'loop_0', 1.0, -1.0, -1, 30, 0, true, 0, false, 0, false)
                end
            elseif not held and pointing then
                pointing = false
                ClearPedSecondaryTask(ped)
            end
            if not pointing then Wait(50) end
        end
    end)
end

---------------------------------------------------------------- eagle eye per job
-- jrs_core owns eagle eye (gameplay.EagleEye). We only step in when it is locked to jobs.
if not Config.EagleEye.everyone then
    CreateThread(function()
        Wait(10000)
        while true do
            local job = JRS.Await('jrs_essentials:job')
            Citizen.InvokeNative(0xA63FCAD3A6FEC6D2, PlayerId(), job ~= nil and Config.EagleEye.jobs[job] == true)
            Wait(60000)
        end
    end)
end

---------------------------------------------------------------- first person while aiming
if Config.FirstPersonAiming then
    CreateThread(function()
        local forced = false
        while true do
            if IsPlayerFreeAiming(PlayerId()) then
                Citizen.InvokeNative(0x90DA5BA5C2635416) -- force first person (this frame)
                forced = true
                Wait(0)
            else
                if forced then
                    Citizen.InvokeNative(0x1CFB749AD4317BDE) -- back to third person
                    forced = false
                end
                Wait(100)
            end
        end
    end)
end

---------------------------------------------------------------- RDO challenge pop-ups
if Config.HideChallengeEvents then
    local HIDE = {
        [`EVENT_CHALLENGE_GOAL_COMPLETE`] = true,
        [`EVENT_CHALLENGE_REWARD`] = true,
        [`EVENT_CHALLENGE_GOAL_UPDATE`] = true,
        [`EVENT_DAILY_CHALLENGE_STREAK_COMPLETED`] = true,
    }
    CreateThread(function()
        while true do
            Wait(50)
            local size = GetNumberOfEvents(0)
            for i = 0, size - 1 do
                if HIDE[GetEventAtIndex(0, i)] then
                    Citizen.InvokeNative(0x6035E8FBCA32AC5E) -- clear UI feed
                end
            end
        end
    end)
end

---------------------------------------------------------------- small fixes (re-applied: the ped changes on respawn)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if Config.StopAutoShuffle then SetPedConfigFlag(ped, 65, true) end
        Wait(5000)
    end
end)

if Config.DrownFix then
    CreateThread(function()
        while true do
            Wait(0)
            SetPedResetFlag(PlayerPedId(), 364, true)
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and not Config.EagleEye.everyone then
        Citizen.InvokeNative(0xA63FCAD3A6FEC6D2, PlayerId(), true)
    end
end)
