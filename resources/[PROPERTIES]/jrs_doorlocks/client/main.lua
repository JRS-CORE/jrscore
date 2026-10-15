-- jrs_doorlocks | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_doorlocks | client
-- Registers the doors with the game, shows the open/close prompt at the doors this player may use, plays
-- the key and lockpick animations. The server decides every state change.

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local byId = {}
for _, d in ipairs(Config.Doors) do
    byId[d.id] = d
    d.state = d.closed and 1 or 0
    d.allowed = false
end

local group = GetRandomIntInRange(0, 0xffffff)
local prompt
local running = false

-- ------------------------------------------------------------------ game door state

local function apply(d, value)
    d.state = value
    if value == 1 then
        DoorSystemForceShut(d.id, true)
        DoorSystemSetOpenRatio(d.id, 0.0, true)
    end
    DoorSystemSetDoorState(d.id, value)
end

local function register()
    for _, d in ipairs(Config.Doors) do
        if not IsDoorRegisteredWithSystem(d.id) then
            AddDoorToSystemNew(d.id, true, true, false, 0, 0, false)
        end
        DoorSystemSetDoorState(d.id, d.state)
        SetDoorNetworked(d.id)
    end
end

-- ------------------------------------------------------------------ who may use which door (for the prompt)

local function recompute()
    local info = LocalPlayer.state.Character
    for _, d in ipairs(Config.Doors) do
        local ok = false
        if info then
            local needed = d.perm and Config.Permissions[d.perm] and Config.Permissions[d.perm][info.Job]
            if needed and (tonumber(info.Grade) or 0) >= needed then ok = true end

            local list = d.unique and Config.Unique[d.unique]
            for _, id in ipairs(list or {}) do
                if id == info.CharId then ok = true end
            end
        end
        if d.override ~= nil then ok = d.override end
        d.allowed = ok
    end
end

RegisterNetEvent('jrs_doorlocks:perms', function(change)
    if not LocalPlayer.state.IsInSession then return end
    if change and byId[change.door] then
        byId[change.door].override = change.allowed
        byId[change.door].allowed = change.allowed
        return
    end
    Wait(1000)
    recompute()
end)

-- ------------------------------------------------------------------ states from the server

RegisterNetEvent('jrs_doorlocks:state', function(id, value, twin)
    if twin and byId[twin] then apply(byId[twin], value) end
    if byId[id] then apply(byId[id], value) end
end)

-- ------------------------------------------------------------------ animations

local function load(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do Wait(0) end
    end
end

local function keyAnimation(ped)
    local at = GetEntityCoords(ped)
    local model, dict = joaat('p_key02x'), 'script_common@jail_cell@unlock@key'
    RequestModel(model, false)
    while not HasModelLoaded(model) do Wait(0) end
    load(dict)

    local key = CreateObject(model, at.x, at.y, at.z + 0.2, false, false, false, false, false)
    repeat Wait(0) until DoesEntityExist(key)
    SetModelAsNoLongerNeeded(model)
    SetEntityVisible(key, false)
    TaskPlayAnim(ped, dict, 'action', 8.0, -8.0, 2500, 8, 0, true, false, false)
    Wait(750)
    SetEntityVisible(key, true)
    AttachEntityToEntity(key, ped, GetEntityBoneIndexByName(ped, 'SKEL_R_Finger12'), 0.02, 0.012, -0.0085,
        0.024, -160.0, 200.0, true, true, false, true, 1, true, false, false)
    Wait(1750)
    DeleteEntity(key)
    RemoveAnimDict(dict)
end

-- ------------------------------------------------------------------ the prompt

local function makePrompt()
    prompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(prompt, `INPUT_INTERACT_LOCKON_ANIMAL`)       -- G
    UiPromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', Text.open))
    UiPromptSetEnabled(prompt, true)
    UiPromptSetVisible(prompt, true)
    UiPromptSetStandardMode(prompt, true)
    UiPromptSetGroup(prompt, group, 0)
    UiPromptRegisterEnd(prompt)
end

local function useDoor(d)
    local wanted = d.state == 0 and 1 or 0
    if Core.Callback.TriggerAwait('jrs_doorlocks:use', d.id, wanted) then
        local ped = PlayerPedId()
        HidePedWeapons(ped, 2, true)
        keyAnimation(ped)
        ClearPedTasksImmediately(ped)
        d.state = wanted
    end
end

local function watch()
    if running then return end
    running = true
    CreateThread(function()
        while true do
            local wait = 1000
            local here = GetEntityCoords(PlayerPedId())
            for _, d in ipairs(Config.Doors) do
                if d.allowed and #(here - d.at) < Config.Reach then
                    wait = 0
                    UiPromptSetActiveGroupThisFrame(group,
                        CreateVarString(10, 'LITERAL_STRING', d.name .. ' ' .. (d.state == 0 and Text.opened or Text.closed)), 0, 0, 0, 0)
                    UiPromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', d.state == 1 and Text.open or Text.close))
                    if UiPromptIsJustPressed(prompt) then useDoor(d) end
                    break
                end
            end
            Wait(wait)
        end
    end)
end

local function start()
    recompute()
    makePrompt()
    register()
    watch()
end

RegisterNetEvent('jrs_doorlocks:sync', function(packed)
    for id, value in pairs(msgpack.unpack(packed)) do
        if byId[id] then apply(byId[id], value) end
    end
    while not LocalPlayer.state.Character do Wait(2000) end
    start()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() or not Config.DevMode then return end
    while not LocalPlayer.state.IsInSession do Wait(2000) end
    start()
end)

-- ------------------------------------------------------------------ lockpicking

local function doorForPick(item)
    local here = GetEntityCoords(PlayerPedId())
    for _, d in ipairs(Config.Doors) do
        if d.lockpick == item and #(here - d.at) < Config.PickReach then return d end
    end
end

local function pickAnimation()
    local ped = PlayerPedId()
    load('script_proc@rustling@unapproved@gate_lockpick')
    TaskPlayAnim(ped, 'script_proc@rustling@unapproved@gate_lockpick', 'enter', 1.0, -1.0, 3500, 1, 0, true, 0, false, '', false)
    Wait(3500)
    load('script_ca@carust@02@ig@ig1_rustlerslockpickingconv01')
    TaskPlayAnim(ped, 'script_ca@carust@02@ig@ig1_rustlerslockpickingconv01', 'idle_01_smhthug_01', 1.0, -1.0, -1, 1, 0, true, 0, false, '', false)
end

local function pickAnimationEnd()
    Wait(1000)
    TaskPlayAnim(PlayerPedId(), 'script_proc@rustling@unapproved@gate_lockpick', 'exit', 1.0, -1.0, 2500, 1, 0, true, 0, false, '', false)
    Wait(2500)
    RemoveAnimDict('script_ca@carust@02@ig@ig1_rustlerslockpickingconv01')
    RemoveAnimDict('script_proc@rustling@unapproved@gate_lockpick')
end

-- answers true when the lockpick is used up (the attempt failed)
Core.Callback.Register('jrs_doorlocks:pick', function(cb, item)
    local d = doorForPick(item)
    if not d then
        Core.NotifyObjective(Text.notNear, 2000)
        return cb(false)
    end
    if d.state == 0 then
        Core.NotifyObjective(Text.alreadyOpen, 5000)
        return cb(false)
    end

    pickAnimation()
    local opened = exports.jrs_lockpick:startLockpick(d.tries)
    if opened then
        TriggerServerEvent('jrs_doorlocks:picked', d.id)
        CreateThread(pickAnimationEnd)
        Wait(1000)                                     -- let the new state arrive
        return cb(false)
    end
    CreateThread(pickAnimationEnd)
    cb(true)
end)

-- ------------------------------------------------------------------ for other resources

exports('getDoorIdByDistance', function(range)
    local here = GetEntityCoords(PlayerPedId())
    for _, d in ipairs(Config.Doors) do
        if #(here - d.at) < (range or 1.5) then return d.id end
    end
end)

exports('getDoorIdByDoorCoords', function(x, y, z)
    for _, d in ipairs(Config.Doors) do
        if d.at.x == x and d.at.y == y and d.at.z == z then return d.id end
    end
end)

exports('getDoorIdByName', function(name)
    for _, d in ipairs(Config.Doors) do
        if d.name:match(name) then return d.id end
    end
end)

exports('getDoorState', function(id)
    return byId[id] and byId[id].state
end)

exports('setDoorState', function(id, value)
    local d = byId[id]
    if not d then return print('[jrs_doorlocks] no door with id', id) end
    if d.state == value then return print('[jrs_doorlocks] the door already has this state', value) end
    return Core.Callback.TriggerAwait('jrs_doorlocks:use', id, value)
end)
