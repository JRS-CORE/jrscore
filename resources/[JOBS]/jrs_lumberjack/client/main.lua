-- jrs_lumberjack | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_lumberjack | client
-- Finds a choppable tree next to the player, equips the axe, and runs swing + skill bar until the
-- server's swing count is used up. The server decides everything that has value.

local Text = Config.Text[Config.Language] or Config.Text.en
local TextEn = Config.Text.en

local group = GetRandomIntInRange(0, 0xffffff)
local startPrompt, swingPrompt, stopPrompt
local busy = false                    -- a chop is in progress (including waiting for the server)
local tree                            -- { at = vector3 } for the tree in reach

local axe                             -- the prop in the player's hand
local treeHash = {}                   -- model hash -> true
for _, name in ipairs(Config.Trees) do treeHash[joaat(name)] = true end

local forbidden = {}                  -- town hash -> true
for _, name in ipairs(Config.ForbiddenTowns) do forbidden[joaat(name)] = true end

-- ------------------------------------------------------------------ finding a tree

local function treeNear(here)
    local set = CreateItemset(true)
    local count = Citizen.InvokeNative(0x59B57C4B06531E1E, here, Config.TreeReach, set, 3, Citizen.ResultAsInteger())
    local found

    for i = 0, count - 1 do
        local entity = GetIndexedItemInItemset(i, set)
        if treeHash[GetEntityModel(entity)] then
            found = { at = GetEntityCoords(entity) }
            break
        end
    end

    if IsItemsetValid(set) then DestroyItemset(set) end
    return found
end

local function canChopHere(ped)
    return not (IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) or IsPedDeadOrDying(ped, false)
        or IsEntityInWater(ped) or IsPedClimbing(ped)) and IsPedOnFoot(ped)
end

local function inForbiddenTown(at)
    local town = Citizen.InvokeNative(0x43AD8FC02B429D33, at.x, at.y, at.z, 1)
    return town and forbidden[town] == true
end

-- ------------------------------------------------------------------ prompts

local function makePrompt(key, label, hold, enabled)
    local p = UiPromptRegisterBegin()
    UiPromptSetControlAction(p, key)
    UiPromptSetText(p, CreateVarString(10, 'LITERAL_STRING', label))      -- game font: English only
    UiPromptSetEnabled(p, enabled)
    UiPromptSetVisible(p, enabled)
    if hold then UiPromptSetHoldMode(p, hold) end
    return p
end

local function finishPrompt(p) UiPromptRegisterEnd(p) end

local function showPrompt(p, on)
    if p then
        UiPromptSetEnabled(p, on)
        UiPromptSetVisible(p, on)
    end
end

local function buildPrompts()
    startPrompt = makePrompt(Config.StartKey, TextEn.cut, 500, true)
    UiPromptSetGroup(startPrompt, group, 0)
    finishPrompt(startPrompt)
end

-- ------------------------------------------------------------------ the axe in hand

local function holdAxe()
    Citizen.InvokeNative(0x6A2F820452017EA2)                              -- clear prompts on screen
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    local model = joaat('p_axe02x')
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    axe = CreateObject(model, at.x, at.y, at.z, true, false, false, false)
    AttachEntityToEntity(axe, ped, GetPedBoneIndex(ped, 7966), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true, false, false)
    Citizen.InvokeNative(0x923583741DC87BCE, ped, 'arthur_healthy')
    Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'carry_pitchfork')
    Citizen.InvokeNative(0x2208438012482A1A, ped, true, true)
    ForceEntityAiAndAnimationUpdate(axe, true)
    Citizen.InvokeNative(0x3A50753042B6891B, ped, 'PITCH_FORKS')

    swingPrompt = makePrompt(Config.SwingKey, TextEn.useAxe, nil, true)
    finishPrompt(swingPrompt)
    stopPrompt = makePrompt(Config.CancelKey, TextEn.stop, 1000, true)
    finishPrompt(stopPrompt)
end

local function dropAxe()
    local ped = PlayerPedId()
    if axe then
        Citizen.InvokeNative(0xED00D72F81CF7278, axe, 1, 1)
        DeleteObject(axe)
        axe = nil
        Citizen.InvokeNative(0x58F7DB5BD8FA2288, ped)                     -- cancel walk style
        ClearPedDesiredLocoForModel(ped)
        ClearPedDesiredLocoMotionType(ped)
    end
    showPrompt(swingPrompt, false)
    showPrompt(stopPrompt, false)
    FreezeEntityPosition(ped, false)
end

-- ------------------------------------------------------------------ the chop

local SWING_DICT = 'amb_work@world_human_tree_chop_new@working@pre_swing@male_a@trans'
local SWING_CLIP = 'pre_swing_trans_after_swing'

local function playSwing(ped)
    RequestAnimDict(SWING_DICT)
    local limit = GetGameTimer() + 1500
    while not HasAnimDictLoaded(SWING_DICT) and GetGameTimer() < limit do Wait(0) end
    TaskPlayAnim(ped, SWING_DICT, SWING_CLIP, 1.0, 1.0, -1, 0, 1, false, 0, false, '', true)
end

local function chop(at, swings)
    holdAxe()
    Wait(500)

    local ped = PlayerPedId()
    local used = 0
    while used < swings do
        FreezeEntityPosition(ped, true)

        if IsControlJustReleased(0, Config.CancelKey) or IsPedDeadOrDying(ped, false) then break end

        if IsControlJustPressed(0, Config.SwingKey) then
            used = used + 1
            showPrompt(swingPrompt, false)
            playSwing(ped)

            local time = math.random(Config.BarTime.hardest, Config.BarTime.easiest)
            if exports.jrs_minigame:taskBar(time, Config.BarGap) == 100 then
                TriggerServerEvent('jrs_lumberjack:swing')
            else
                local lines = Text.slips
                TriggerEvent('jrs:TipRight', lines[math.random(#lines)], 3000)
            end
            Wait(500)
            showPrompt(swingPrompt, true)
        end
        Wait(0)
    end

    TriggerServerEvent('jrs_lumberjack:stop')
    Wait(2000)
    dropAxe()
    busy = false
end

RegisterNetEvent('jrs_lumberjack:go', function(at, swings) CreateThread(function() chop(at, swings) end) end)
RegisterNetEvent('jrs_lumberjack:refused', function() busy = false end)

-- ------------------------------------------------------------------ main loops

CreateThread(function()                                       -- look for a tree
    while not LocalPlayer.state.IsInSession do Wait(5000) end
    while true do
        if not busy then
            local ped = PlayerPedId()
            tree = canChopHere(ped) and treeNear(GetEntityCoords(ped)) or nil
            if tree and startPrompt then
                local allowed = not inForbiddenTown(GetEntityCoords(ped))
                UiPromptSetEnabled(startPrompt, allowed)
            end
        end
        Wait(1000)
    end
end)

CreateThread(function()                                       -- start prompt
    while not LocalPlayer.state.IsInSession do Wait(5000) end
    buildPrompts()

    while true do
        local wait = 1000
        if not busy and tree then
            wait = 0
            UiPromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', TextEn.cutTitle), 0, 0, 0, 0)
            if UiPromptHasHoldModeCompleted(startPrompt) then
                busy = true
                SetCurrentPedWeapon(PlayerPedId(), joaat('WEAPON_UNARMED'), true, 0, false, false)
                Wait(500)
                TriggerServerEvent('jrs_lumberjack:start', tree.at)
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    dropAxe()
    showPrompt(startPrompt, false)
end)
