-- jrs_samples | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_samples | client
-- Animals that were sedated get a "take sample" hold prompt while the player is close. An animal that
-- stays sedated too long wakes up and runs away.

local SEDATED <const> = 580            -- ped config flag
local CONTROL <const> = 0x956C2A0E
local RANGE <const>   = 2.0

local tracked = {}                     -- ped -> { prompt, since }
local done = {}                        -- ped -> true once sampled or woken, so it is never offered twice

local function forget(ped)
    local entry = tracked[ped]
    if entry then PromptDelete(entry.prompt) end
    tracked[ped] = nil
end

-- the server needs a network id; gives up after a second
local function networked(ped)
    for _ = 1, 10 do
        if NetworkGetEntityIsNetworked(ped) and NetworkDoesNetworkIdExist(NetworkGetNetworkIdFromEntity(ped)) then return true end
        NetworkRegisterEntityAsNetworked(ped)
        Wait(100)
    end
    return false
end

local function offer(ped)
    if not networked(ped) or not DoesEntityExist(ped) then done[ped] = true return end

    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, CONTROL)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', LE('prompt_take_sample')))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, false)
    PromptSetHoldMode(prompt, Config.SampleHoldTime)
    PromptSetGroup(prompt, UiPromptGetGroupIdForTargetEntity(ped))
    PromptRegisterEnd(prompt)
    tracked[ped] = { prompt = prompt, since = GetGameTimer() }
end

local function wake(ped)
    forget(ped)
    done[ped] = true
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    SetPedConfigFlag(ped, SEDATED, false)
    ClearPedTasksImmediately(ped)
    local at = GetEntityCoords(ped)
    TaskFleeCoord(ped, at.x + 100.0, at.y + 100.0, at.z, 2, 0, -1.0, 5000, 0)
end

-- find newly sedated animals, drop the dead, gone or expired ones
CreateThread(function()
    while true do
        local now = GetGameTimer()

        for _, ped in ipairs(GetGamePool('CPed')) do
            if not tracked[ped] and not done[ped] and not IsPedAPlayer(ped) and not IsEntityDead(ped) and GetPedConfigFlag(ped, SEDATED, true) then
                offer(ped)
            end
        end

        for ped, entry in pairs(tracked) do
            if not DoesEntityExist(ped) or IsEntityDead(ped) then forget(ped)
            elseif now - entry.since > Config.AnimalCleanupTime then wake(ped) end
        end

        for ped in pairs(done) do
            if not DoesEntityExist(ped) or IsEntityDead(ped) or not GetPedConfigFlag(ped, SEDATED, true) then done[ped] = nil end
        end
        Wait(1000)
    end
end)

-- show the prompt when close, send the sample when the hold completes
CreateThread(function()
    while true do
        if next(tracked) == nil then
            Wait(500)
        else
            local here = GetEntityCoords(PlayerPedId())
            for ped, entry in pairs(tracked) do
                if DoesEntityExist(ped) then
                    local near = #(GetEntityCoords(ped) - here) < RANGE
                    PromptSetVisible(entry.prompt, near)
                    if near and PromptHasHoldModeCompleted(entry.prompt) then
                        forget(ped)                      -- first, so the next frame cannot send it twice
                        done[ped] = true
                        SetPedQuality(ped, -1)
                        TriggerServerEvent('jrs_samples:server:sampleAnimal', NetworkGetNetworkIdFromEntity(ped))
                    end
                end
            end
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for ped in pairs(tracked) do forget(ped) end
end)
