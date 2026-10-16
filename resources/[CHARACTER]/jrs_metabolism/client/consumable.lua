-- jrs_metabolism | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
statusDrunk = 0
local epoch, using, alcoholRunning = 0, false, false
local props, activePed = {}, nil
local effect = 'MP_BountyLagrasSwamp'
local function current(token, charId)
    return token == epoch and MetabolismReady() and MetabolismCharacterId() == charId and not IsEntityDead(PlayerPedId())
end
local function waitFor(test, request, token, charId)
    local deadline = GetGameTimer() + 3000
    request()
    while not test() do
        if not current(token, charId) or GetGameTimer() >= deadline then return false end
        Wait(10)
    end
    return current(token, charId)
end
local function prop(model, token, charId)
    local hash = GetHashKey(model)
    if not waitFor(function() return HasModelLoaded(hash) end, function() RequestModel(hash) end, token, charId) then return end
    local coords = GetEntityCoords(PlayerPedId())
    local object = CreateObject(hash, coords.x, coords.y, coords.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    if object and object ~= 0 then props[object] = true; return object end
end
local function remove(object)
    if object and DoesEntityExist(object) then DeleteObject(object) end
    if object then props[object] = nil end
end
function SetAsDrunkAnimation(enabled, amount)
    local ped = PlayerPedId()
    if enabled then
        Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'very_drunk')
        Citizen.InvokeNative(0x406CCF555B04FAD3, ped, true, amount)
    else
        Citizen.InvokeNative(0x58F7DB5BD8FA2288, ped)
        Citizen.InvokeNative(0x406CCF555B04FAD3, ped, false, 0.0)
    end
    Citizen.InvokeNative(0xCB9401F918CB0F75, ped, 'IsDrunk', enabled, -1)
    Citizen.InvokeNative(0x437C08DB4FEBE2BD, ped, 'Drunkness', amount, -1)
end
function SetScreenEffect(enabled, amount)
    if enabled then
        AnimpostfxPlay(effect)
        Citizen.InvokeNative(0xCAB4DD2D5B2B7246, effect, amount)
    else AnimpostfxStop(effect) end
    Citizen.InvokeNative(0xCB9401F918CB0F75, PlayerPedId(), 'BLOCK_CAMERA_DRUNK_SLUMP_BEHAVIOUR', enabled, -1)
end
function ResetConsumableEffects()
    epoch = epoch + 1
    local hadTask = next(props) ~= nil
    local hadAlcohol = alcoholRunning or statusDrunk > 0
    for object in pairs(props) do remove(object) end
    if hadTask and activePed == PlayerPedId() then ClearPedTasks(activePed) end
    activePed, using, statusDrunk, alcoholRunning = nil, false, 0, false
    if hadAlcohol then
        SetAsDrunkAnimation(false, 0.0)
        SetScreenEffect(false, 0.0)
    end
end
function AlcoolDrink(amount)
    statusDrunk = math.min(1.0, math.max(0, statusDrunk + amount))
    if alcoholRunning then return end
    alcoholRunning = true
    local token, charId = epoch, MetabolismCharacterId()
    CreateThread(function()
        while current(token, charId) and statusDrunk > 0 do
            SetAsDrunkAnimation(true, statusDrunk)
            SetScreenEffect(true, statusDrunk)
            Wait(2000)
            if not current(token, charId) then return end
            statusDrunk = math.max(0, statusDrunk - 0.005)
        end
        if token == epoch then
            SetAsDrunkAnimation(false, 0.0)
            SetScreenEffect(false, 0.0)
            alcoholRunning = false
        end
    end)
end
local function animate(dict, anim, model, offsets, duration)
    local token, charId = epoch, MetabolismCharacterId()
    if not current(token, charId) then return end
    if not waitFor(function() return HasAnimDictLoaded(dict) end, function() RequestAnimDict(dict) end, token, charId) then return end
    local object = prop(model, token, charId)
    if not object then return end
    local ped = PlayerPedId()
    activePed = ped
    AttachEntityToEntity(object, ped, GetEntityBoneIndexByName(ped, 'SKEL_R_HAND'),
        offsets[1], offsets[2], offsets[3], offsets[4], offsets[5], offsets[6], true, true, false, true, 1, true)
    TaskPlayAnim(ped, dict, anim, 1.0, 8.0, duration, 31, 0, false, false, false)
    local finish = GetGameTimer() + duration
    while current(token, charId) and GetGameTimer() < finish do Wait(100) end
    remove(object)
    RemoveAnimDict(dict)
    if current(token, charId) then ClearPedTasks(ped) end
    if activePed == ped then activePed = nil end
end
function Eat()
    animate('mech_inventory@eating@multi_bite@sphere_d8-2_sandwich', 'quick_right_hand', 'P_BREAD05X',
        {0.1,-0.01,-0.07,-90.0,100.0,0.0}, 2000)
end
function Drink()
    animate('amb_rest_drunk@world_human_drinking@male_a@idle_a', 'idle_a', 'P_BOTTLE008X',
        {0.05,-0.07,-0.05,-75.0,60.0,0.0}, 4000)
end
function Coffee() Drink() end
local function alcohol(amount)
    local token, charId = epoch, MetabolismCharacterId()
    Drink()
    if current(token, charId) then AlcoolDrink(amount) end
end
function Shampan() alcohol(0.3) end
function Beer() alcohol(0.3) end
function Whisky() alcohol(0.5) end
function Moonshine() alcohol(1.0) end
function Wine() alcohol(0.35) end
RegisterNetEvent('jrs_metabolism:client:consumable', function(name, charId)
    local item = type(name) == 'string' and ConsumableItems[name]
    if not item or not MetabolismReady() or tonumber(charId) ~= MetabolismCharacterId() or using then return end
    using = true
    local token = epoch
    CreateThread(function()
        local ok, err = pcall(item.ClientAction)
        if token == epoch then using = false end
        if not ok then
            for object in pairs(props) do remove(object) end
            print(('[jrs_metabolism] Animation failed: %s'):format(err))
        end
    end)
end)
