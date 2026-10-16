-- jrs_goldclaim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_goldclaim | client helpers (loaded first): messages, streaming, timed actions, who am I, blips

function Notify(title, description, _, _, duration)
    JRS.Notify(description and (title .. ': ' .. description) or title, duration or Config.NotifyDuration)
end

function LoadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local limit = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < limit do Wait(10) end
    return HasModelLoaded(hash)
end

function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local limit = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < limit do Wait(10) end
    return HasAnimDictLoaded(dict)
end

-- ------------------------------------------------------------------ timed actions

local working = false

-- true (and a notice) while another action is running
function IsBusy()
    if working then Notify(L('rocker_processing_busy'), nil, nil, nil, 3000) end
    return working
end

local function setWorking(on)
    working = on
    LocalPlayer.state:set('inv_busy', on, true)
end

local CANCEL <const> = 0x156F7119                       -- backspace / esc
local DISABLED <const> = { 0x07CE1E61, 0xF84FA74F, 0xB2F377E8, 0xAC4BD4F1 }          -- attack, aim, melee, wheel
local WALK <const> = { 0x8FD015D8, 0xD27782E3, 0x7065027D, 0xB4E465B4 }               -- W S A D
local WALK_AWAY <const> = 1.0

local function walking()
    for _, key in ipairs(WALK) do
        if IsControlJustPressed(0, key) or IsDisabledControlJustPressed(0, key) then return true end
    end
    return false
end

-- waits `duration` ms; false when the ped died or (if allowed) the player cancelled or walked away
local function wait(ped, duration, cancellable)
    local start, finish = GetEntityCoords(ped), GetGameTimer() + duration
    while GetGameTimer() < finish do
        Wait(0)
        for _, key in ipairs(DISABLED) do DisableControlAction(0, key, true) end
        if IsEntityDead(ped) then return false end
        if cancellable and (IsControlJustPressed(0, CANCEL) or walking() or #(GetEntityCoords(ped) - start) > WALK_AWAY) then
            return false
        end
    end
    return true
end

-- A scenario for opts.duration ms, no progress bar, the player is not frozen.
-- opts = { duration, scenario?, canCancel?, onCleanup? }; returns true when it ran to the end
function DoTimedAction(opts)
    if working then return false end
    setWorking(true)

    local ped = PlayerPedId()
    if opts.scenario then TaskStartScenarioInPlace(ped, opts.scenario, 0, true) end

    -- pcall: the cleanup below runs even if something fails in the middle
    local ok, finished = pcall(wait, ped, opts.duration, opts.canCancel ~= false)

    if finished then ClearPedTasks(ped) else ClearPedTasksImmediately(ped) end
    if opts.onCleanup then pcall(opts.onCleanup, ped) end
    setWorking(false)
    return ok and finished
end

-- ------------------------------------------------------------------ who am I

local me = { id = nil, job = nil, refreshAt = 0 }

local function refresh()
    if GetGameTimer() < me.refreshAt then return end
    me.refreshAt = GetGameTimer() + 30000
    local info = JRS.Await('jrs_goldclaim:server:me')
    if info then me.id, me.job = info.id, info.job end
end

function MyCharId() refresh() return me.id end
function IsLeo() refresh() return me.job ~= nil and Config.LeoJobs[me.job] == true end

function HasItem(item, amount)
    return JRS.Await('jrs_goldclaim:server:hasitem', item, amount or 1) == true
end

RegisterNetEvent('jrs:SelectedCharacter', function() me.refreshAt = 0 end)

function CreateNamedBlip(at, sprite, scale, name, colour)
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, at.x, at.y, at.z)
    SetBlipSprite(blip, joaat(sprite), true)
    SetBlipScale(blip, scale)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name)
    if colour then Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(colour)) end
    return blip
end
