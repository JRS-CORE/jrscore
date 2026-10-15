-- jrs_mining | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_mining | client
-- Finds a mineable rock next to the player, equips the pickaxe, and runs swing + skill bar until the
-- server's swing count is used up. The server decides everything that has value.

local Text = Config.Text[Config.Language] or Config.Text.en
local TextEn = Config.Text.en

local group = GetRandomIntInRange(0, 0xffffff)
local startPrompt, swingPrompt, stopPrompt
local busy = false                    -- a mine is in progress (including waiting for the server)
local rock                            -- { at = vector3 } for the rock in reach

local pickaxe                             -- the prop in the player's hand
local rockHash = {}                   -- model hash -> true
for _, name in ipairs(Config.Rocks) do rockHash[joaat(name)] = true end

local forbidden = {}                  -- town hash -> true
for _, name in ipairs(Config.ForbiddenTowns) do forbidden[joaat(name)] = true end

-- ------------------------------------------------------------------ finding a rock

local function rockNear(here)
    local set = CreateItemset(true)
    local count = Citizen.InvokeNative(0x59B57C4B06531E1E, here, Config.RockReach, set, 3, Citizen.ResultAsInteger())
    local found

    for i = 0, count - 1 do
        local entity = GetIndexedItemInItemset(i, set)
        if rockHash[GetEntityModel(entity)] then
            found = { at = GetEntityCoords(entity) }
            break
        end
    end

    if IsItemsetValid(set) then DestroyItemset(set) end
    return found
end

local function canMineHere(ped)
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
    startPrompt = makePrompt(Config.StartKey, TextEn.mine, 500, true)
    UiPromptSetGroup(startPrompt, group, 0)
    finishPrompt(startPrompt)
end

-- ------------------------------------------------------------------ the pickaxe in hand

local function holdPickaxe()
    Citizen.InvokeNative(0x6A2F820452017EA2)                              -- clear prompts on screen
    local ped = PlayerPedId()
    local at = GetEntityCoords(ped)
    local model = joaat('p_pickaxe01x')
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    pickaxe = CreateObject(model, at.x, at.y, at.z, true, false, false, false)
    AttachEntityToEntity(pickaxe, ped, GetPedBoneIndex(ped, 7966), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true, false, false)
    Citizen.InvokeNative(0x923583741DC87BCE, ped, 'arthur_healthy')
    Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'carry_pitchfork')
    Citizen.InvokeNative(0x2208438012482A1A, ped, true, true)
    ForceEntityAiAndAnimationUpdate(pickaxe, true)
    Citizen.InvokeNative(0x3A50753042B6891B, ped, 'PITCH_FORKS')

    swingPrompt = makePrompt(Config.SwingKey, TextEn.usePickaxe, nil, true)
    finishPrompt(swingPrompt)
    stopPrompt = makePrompt(Config.CancelKey, TextEn.stop, 1000, true)
    finishPrompt(stopPrompt)
end

local function dropPickaxe()
    local ped = PlayerPedId()
    if pickaxe then
        Citizen.InvokeNative(0xED00D72F81CF7278, pickaxe, 1, 1)
        DeleteObject(pickaxe)
        pickaxe = nil
        Citizen.InvokeNative(0x58F7DB5BD8FA2288, ped)                     -- cancel walk style
        ClearPedDesiredLocoForModel(ped)
        ClearPedDesiredLocoMotionType(ped)
    end
    showPrompt(swingPrompt, false)
    showPrompt(stopPrompt, false)
    FreezeEntityPosition(ped, false)
end

-- ------------------------------------------------------------------ the mine

local SWING_DICT = 'amb_work@world_human_pickaxe_new@working@male_a@trans'
local SWING_CLIP = 'pre_swing_trans_after_swing'

local function playSwing(ped)
    RequestAnimDict(SWING_DICT)
    local limit = GetGameTimer() + 1500
    while not HasAnimDictLoaded(SWING_DICT) and GetGameTimer() < limit do Wait(0) end
    TaskPlayAnim(ped, SWING_DICT, SWING_CLIP, 1.0, 1.0, -1, 0, 1, false, 0, false, '', true)
end

local function mine(at, swings)
    holdPickaxe()
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
                TriggerServerEvent('jrs_mining:swing')
            else
                local lines = Text.slips
                TriggerEvent('jrs:TipRight', lines[math.random(#lines)], 3000)
            end
            Wait(500)
            showPrompt(swingPrompt, true)
        end
        Wait(0)
    end

    TriggerServerEvent('jrs_mining:stop')
    Wait(2000)
    dropPickaxe()
    busy = false
end

RegisterNetEvent('jrs_mining:go', function(at, swings) CreateThread(function() mine(at, swings) end) end)
RegisterNetEvent('jrs_mining:refused', function() busy = false end)

-- ------------------------------------------------------------------ main loops

CreateThread(function()                                       -- look for a rock
    while not LocalPlayer.state.IsInSession do Wait(5000) end
    while true do
        if not busy then
            local ped = PlayerPedId()
            rock = canMineHere(ped) and rockNear(GetEntityCoords(ped)) or nil
            if rock and startPrompt then
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
        if not busy and rock then
            wait = 0
            UiPromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', TextEn.mineTitle), 0, 0, 0, 0)
            if UiPromptHasHoldModeCompleted(startPrompt) then
                busy = true
                SetCurrentPedWeapon(PlayerPedId(), joaat('WEAPON_UNARMED'), true, 0, false, false)
                Wait(500)
                TriggerServerEvent('jrs_mining:start', rock.at)
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    dropPickaxe()
    showPrompt(startPrompt, false)
end)
