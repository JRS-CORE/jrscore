-- jrs_bathing | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_bathing | client
-- Bath houses: walk to the tub, pay, and the game's bathing animation scene plays. A regular bath is scrubbed
-- by holding a key; the deluxe bath adds a maid who does the scrubbing. The server only handles money and
-- who is in which room.

BathingPed = nil                    -- the maid of a deluxe bath

local scene, camera, town           -- the running anim scene, the bath camera, the town the player is in
local me = PlayerPedId

local ANIM_SCENE_CREATE, ANIM_SCENE_READY, ANIM_SCENE_PLAYING, ANIM_SCENE_DELETE = 0x1FCA98E33C1437B3, 0x477122B8D05E7968, 0x25557E324489393C, 0x84EEDB2C6E650000
local ANIM_SCENE_PHASE, ANIM_SCENE_DONE = 0x3FBC3F51BF12DFBF, 0xD8254CB2C586412B
local SET_BATH_MUSIC = nil

local CLEAN_SIGNALS <const> = { 'Cleanliness_Right_Arm', 'Cleanliness_Left_Arm', 'Cleanliness_Left_Leg', 'Cleanliness_Right_Leg', 'Cleanliness_Head' }

exports('IsBathingActive', function() return LocalPlayer.state.isBathingActive end)

RegisterNetEvent('jrs_bathing:client:ToggleInvincibility', function(on)
    LocalPlayer.state.invincible = on
end)

-- ------------------------------------------------------------------ streaming

local DICTS <const> = { 'MINI_GAMES@BATHING@REGULAR@ARTHUR', 'MINI_GAMES@BATHING@REGULAR@RAG', 'MINI_GAMES@BATHING@DELUXE@ARTHUR', 'MINI_GAMES@BATHING@DELUXE@MAID' }
local NETWORKS <const> = { 'Script_Mini_Game_Bathing_Regular', 'Script_Mini_Game_Bathing_Deluxe' }

function LoadModel(model)
    while not HasModelLoaded(model) do RequestModel(model) Wait(10) end
end

local function streamIn()
    for _, dict in ipairs(DICTS) do
        RequestAnimDict(dict)
        RequestClipSet('CLIPSET@' .. dict)
    end
    for _, name in ipairs(NETWORKS) do Citizen.InvokeNative(0x2B6529C54D29037A, name) end
end

local function streamOut()
    for _, dict in ipairs(DICTS) do
        RemoveAnimDict(dict)
        RemoveClipSet('CLIPSET@' .. dict)
    end
    for _, name in ipairs(NETWORKS) do Citizen.InvokeNative(0x57A197AD83F66BBF, name) end
end

-- ------------------------------------------------------------------ prompts

local prompts = {}                  -- id -> prompt handle
local promptsOn = false

local function setPrompt(prompt, state)
    Citizen.InvokeNative(0x8A0FB4D03A630D21, prompt, state)
    Citizen.InvokeNative(0x71215ACCFDE075EE, prompt, state)
end

-- ids = list of prompt ids, or nil for all of them
function TogglePrompts(ids, state)
    if ids == 'ALL' or ids == nil then
        for _, prompt in pairs(prompts) do setPrompt(prompt, state) end
    else
        for _, id in ipairs(ids) do
            if prompts[id] then setPrompt(prompts[id], state) end
        end
    end
    promptsOn = state
end

local function promptDone(id) return prompts[id] and Citizen.InvokeNative(0xE0F65F0640EF0617, prompts[id]) or false end
local function promptActive(id) return prompts[id] and PromptIsEnabled(prompts[id]) or false end

local function createPrompts()
    for _, def in ipairs(Config.Prompts) do
        local prompt = Citizen.InvokeNative(0x04F97DE45A519419, Citizen.ResultAsInteger())
        Citizen.InvokeNative(0x5DD02A8318420DD7, prompt, CreateVarString(10, 'LITERAL_STRING', def.label))
        Citizen.InvokeNative(0xB5352B7494A08258, prompt, def.control or 0xDFF812F9)
        Citizen.InvokeNative(0x94073D5CA3F16B7B, prompt, def.time or 1000)
        Citizen.InvokeNative(0xF7AA2696A22AD8B9, prompt)
        setPrompt(prompt, false)
        table.insert(Config.CreatedEntries, { type = 'PROMPT', handle = prompt })
        prompts[def.id] = prompt
    end
end

-- ------------------------------------------------------------------ anim scenes

local function newScene(zone, name, withMaid)
    local s = Citizen.InvokeNative(ANIM_SCENE_CREATE, zone.dict, 0, name, false, true)
    SetAnimSceneEntity(s, 'ARTHUR', me(), 0)
    if withMaid then SetAnimSceneEntity(s, 'Female', BathingPed, 0) end
    SetAnimSceneEntity(s, 'Door', GetEntityByDoorhash(zone.door, 0), 0)
    return s
end

local function loadScene(s)
    LoadAnimScene(s)
    while not Citizen.InvokeNative(ANIM_SCENE_READY, s, 1, 0) do Wait(10) end
end

local function endScene(s)
    if s and Citizen.InvokeNative(ANIM_SCENE_PLAYING, s) then Citizen.InvokeNative(ANIM_SCENE_DELETE, s) end
end

local function waitSceneEnd(s)
    while not Citizen.InvokeNative(ANIM_SCENE_DONE, s, true) do Wait(10) end
end

local function waitScenePhase(s, phase)
    while Citizen.InvokeNative(ANIM_SCENE_PHASE, s, Citizen.ResultAsFloat()) <= phase do Wait(0) end
end

-- ------------------------------------------------------------------ cleaning

-- the dirt, blood and damage marks on a ped; every way out of a bath ends with this
function FullyCleanPed(ped)
    if not DoesEntityExist(ped) then return end
    ClearPedEnvDirt(ped)
    ClearPedBloodDamage(ped)
    SetPedDirtCleaned(ped, 0.0, -1, 1, 1)
    ClearPedDamageDecalByZone(ped, 10, 'ALL')
    Citizen.InvokeNative(0x7F5D88333EE8A86F, ped, 1)
end

-- how clean the body looks, on the player, the rag and (deluxe) the maid
local function showCleanliness(rag, value)
    local who = { me(), rag }
    if DoesEntityExist(BathingPed) then who[#who + 1] = BathingPed end
    for _, ped in ipairs(who) do
        for _, signal in ipairs(CLEAN_SIGNALS) do SetTaskMoveNetworkSignalFloat(ped, signal, value) end
    end
end

local function partner(rag)
    return DoesEntityExist(BathingPed) and BathingPed or rag
end

local function moveBoth(rag, stateName)
    RequestTaskMoveNetworkStateTransition(me(), stateName)
    RequestTaskMoveNetworkStateTransition(partner(rag), stateName)
end

local function undress()
    SetPedAllWeaponsVisibility(me(), false)
    if GetResourceState('jrs_clothing') == 'started' then
        exports.jrs_clothing:RemoveAllClothesExceptEssentials(me())
    end
end

local function redress()
    local ped = me()
    local health = GetEntityHealth(ped)
    local stamina = Citizen.InvokeNative(0x775A1CA7893AA8B5, ped, Citizen.ResultAsFloat()) / Citizen.InvokeNative(0xCB42AFE2B613EE55, ped, Citizen.ResultAsFloat()) * 100
    TriggerEvent('jrs_clothes:reloadCurrentClothes')
    Wait(1000)
    Citizen.InvokeNative(0x9C720776DAA43E7E, ped, 0.0)
    Citizen.InvokeNative(0x44CB6447D2571AA0, ped, -1.0)
    SetPedAllWeaponsVisibility(ped, true)
    SetEntityHealth(ped, health)
    Citizen.InvokeNative(0xC3D4B754C0E86B9E, ped, stamina)
end

-- ------------------------------------------------------------------ leaving

local function leaveDeluxe(hideScrub)
    local zone = Config.BathingZones[town]
    local outro = Citizen.InvokeNative(ANIM_SCENE_CREATE, zone.dict, 0, 's_deluxe_outro', false, true)
    SetAnimSceneEntity(outro, 'ARTHUR', me(), 0)
    SetAnimSceneEntity(outro, 'Female', BathingPed, 0)
    SetAnimSceneEntity(outro, 'Door', Citizen.InvokeNative(0xF7424890E4A094C0, zone.door, 0), 0)

    loadScene(outro)
    StartAnimScene(outro)
    RenderScriptCams(false, false, 0, true, false, 0)
    waitSceneEnd(outro)
    endScene(outro)

    local regular = Config.BathingModes
    TriggerEvent('jrs_bathing:TASK_MOVE_NETWORK_BY_NAME_WITH_INIT_PARAMS', { me(), 'Script_Mini_Game_Bathing_Regular', `CLIPSET@MINI_GAMES@BATHING@REGULAR@ARTHUR`, `DEFAULT`, 'BATHING' })
    TriggerEvent('jrs_bathing:TASK_MOVE_NETWORK_BY_NAME_WITH_INIT_PARAMS', { BathingPed, 'Script_Mini_Game_Bathing_Deluxe', `CLIPSET@MINI_GAMES@BATHING@REGULAR@MAID`, `DEFAULT`, 'BATHING' })

    TogglePrompts({ 'STOP_BATHING', 'SCRUB' }, true)
    if hideScrub and promptActive('SCRUB') then TogglePrompts({ 'SCRUB' }, false) end

    RenderScriptCams(true, true, 0, true, false, 0)
    DeletePed(BathingPed)
    BathingPed = nil
end

local function leaveBath()
    if DoesEntityExist(BathingPed) then return leaveDeluxe() end

    local zone, cam = Config.BathingZones[town], camera
    endScene(scene)

    local outro = newScene(zone, 's_regular_outro')
    loadScene(outro)
    StartAnimScene(outro)

    if DoesCamExist(cam) then
        RenderScriptCams(false, false, 0, true, false, 0)
        DestroyCam(cam)
        camera = nil
    end

    waitScenePhase(outro, 0.35)
    waitSceneEnd(outro)
    endScene(outro)

    FullyCleanPed(me())
    redress()
    streamOut()
    RequestLetterBoxNow(false, false)
    TriggerMusicEvent('MG_BATHING_STOP')
    Citizen.InvokeNative(0x704C908E9C405136, me())
    TriggerServerEvent('jrs_bathing:server:setBathAsFree', town)

    SetPedCanLegIk(me(), true)
    SetPedLegIkMode(me(), 2)
    LocalPlayer.state.isBathingActive = false
end

-- ------------------------------------------------------------------ the scrubbing loop

local SCRUB_KEY <const> = `INPUT_CONTEXT_X`

local function scrub(rag, level)
    -- level = { mode, hold }, returns the new level
    local modes = Config.BathingModes
    while GetTaskMoveNetworkState(me()) ~= 'Scrub_Idle' do
        moveBoth(rag, 'Scrub_Idle')
        Wait(200)
    end

    while IsControlPressed(0, SCRUB_KEY) do
        if promptDone('SCRUB') then
            FullyCleanPed(me())
            if DoesEntityExist(BathingPed) and not modes[level.mode].deluxe then level.mode = level.mode + 1 end

            local mode = modes[level.mode]
            level.hold = level.hold + (mode.hold_power or 0.05)

            if GetTaskMoveNetworkState(me()) ~= mode.transition then
                showCleanliness(rag, 0.0)
                moveBoth(rag, mode.transition)
            end
            SetTaskMoveNetworkSignalFloat(me(), 'scrub_freq', mode.scrub_freq)
            SetTaskMoveNetworkSignalFloat(partner(rag), 'scrub_freq', mode.scrub_freq)
            showCleanliness(rag, level.hold)

            if level.hold >= 1.0 then
                level.hold = 0.0
                if level.mode + 1 > #modes then
                    TogglePrompts({ 'REQUEST_DELUXE_BATHING', 'SCRUB' }, false)
                    FullyCleanPed(me())
                    level.mode = #modes + 1
                    if DoesEntityExist(BathingPed) then Wait(750) leaveDeluxe(true) end
                else
                    level.mode = level.mode + 1
                end
                break
            end
        end
        Wait(100)
    end

    while not IsTaskMoveNetworkReadyForTransition(me()) do Wait(10) end

    local target = ((level.mode == #modes + 1) or DoesEntityExist(BathingPed)) and 'Bathing' or 'Scrub_Idle'
    while GetTaskMoveNetworkState(me()) ~= target do
        showCleanliness(rag, 1.0)
        while GetTaskMoveNetworkState(me()) ~= 'Scrub_Idle' do
            moveBoth(rag, 'Scrub_Idle')
            Wait(200)
        end

        if target ~= 'Scrub_Idle' then
            local keyHeld = IsControlPressed(0, SCRUB_KEY)
            if not DoesEntityExist(BathingPed) or not keyHeld then moveBoth(rag, 'Bathing') else target = 'Scrub_Idle' end
        end
        Wait(500)
    end
    return level
end

-- ------------------------------------------------------------------ starting a bath

RegisterNetEvent('jrs_bathing:client:StartBath', function(where)
    LocalPlayer.state.isBathingActive = true
    town = where
    local zone = Config.BathingZones[where]
    if not zone then return end

    local ped = me()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true, 0, true, true)
    Citizen.InvokeNative(0x4820A6939D7CEF28, ped, true)
    HolsterPedWeapons(ped, false, false, false, true)
    streamIn()

    LoadModel(`P_CS_RAG02X`)
    local rag = CreateObject(`P_CS_RAG02X`, GetEntityCoords(ped), false, false, false, false, true)
    table.insert(Config.CreatedEntries, { type = 'PED', handle = rag })
    SetModelAsNoLongerNeeded(`P_CS_RAG02X`)

    SetPedCanLegIk(ped, false)
    SetPedLegIkMode(ped, 0)
    ClearPedTasksImmediately(ped, true, true)

    scene = newScene(zone, 's_regular_intro')
    loadScene(scene)
    TriggerMusicEvent('MG_BATHING_START')
    StartAnimScene(scene)
    waitScenePhase(scene, 0.3)

    undress()
    waitSceneEnd(scene)

    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', 1)
    table.insert(Config.CreatedEntries, { type = 'CAM', handle = camera })
    RequestLetterBoxNow(true, true)
    SetCamCoord(camera, GetFinalRenderedCamCoord(), 0.0, 0.4, 0.5)
    SetCamRot(camera, GetFinalRenderedCamRot(1), 1)
    SetCamFov(camera, GetFinalRenderedCamFov())
    RenderScriptCams(true, true, 0, true, false, 0)

    TogglePrompts({ 'STOP_BATHING', 'REQUEST_DELUXE_BATHING', 'SCRUB' }, true)

    TriggerEvent('jrs_bathing:TASK_MOVE_NETWORK_BY_NAME_WITH_INIT_PARAMS', { ped, 'Script_Mini_Game_Bathing_Regular', `CLIPSET@MINI_GAMES@BATHING@REGULAR@ARTHUR`, `DEFAULT`, 'BATHING' })
    TriggerEvent('jrs_bathing:TASK_MOVE_NETWORK_BY_NAME_WITH_INIT_PARAMS', { rag, 'Script_Mini_Game_Bathing_Regular', `CLIPSET@MINI_GAMES@BATHING@REGULAR@RAG`, `DEFAULT`, 'BATHING' })
    ForceEntityAiAndAnimationUpdate(rag, true)
    Citizen.InvokeNative(0x55546004A244302A, ped)

    local level = { mode = 1, hold = 0 }
    while DoesCamExist(camera) do
        while not IsTaskMoveNetworkReadyForTransition(me()) do Wait(100) end

        if promptActive('SCRUB') and level.mode == #Config.BathingModes + 1 then TogglePrompts({ 'SCRUB' }, false) end

        if IsControlPressed(0, SCRUB_KEY) and promptActive('SCRUB') then
            if promptActive('REQUEST_DELUXE_BATHING') then TogglePrompts({ 'REQUEST_DELUXE_BATHING' }, false) end
            level = scrub(rag, level)
        end

        if promptDone('REQUEST_DELUXE_BATHING') then TriggerEvent('jrs_bathing:ask', 'REQUEST_DELUXE_BATHING') end
        if promptDone('STOP_BATHING') then TriggerEvent('jrs_bathing:ask', 'STOP_BATHING') end
        Wait(10)
    end
end)

RegisterNetEvent('jrs_bathing:client:StartDeluxeBath', function(where)
    if not scene or not Citizen.InvokeNative(ANIM_SCENE_PLAYING, scene) then return end
    Citizen.InvokeNative(ANIM_SCENE_DELETE, scene)

    local zone = Config.BathingZones[where]
    local model = IsPedMale(me()) and zone.lady or zone.guy
    LoadModel(model)
    BathingPed = CreatePed(model, GetEntityCoords(me()) - vector3(0.0, 0.0, -5.0), 0.0, false, false, true, true)
    table.insert(Config.CreatedEntries, { type = 'PED', handle = BathingPed })
    Citizen.InvokeNative(0x283978A15512B2FE, BathingPed, true)
    SetModelAsNoLongerNeeded(model)

    scene = newScene(zone, 's_deluxe_intro', true)
    loadScene(scene)
    PlaySoundFrontend('BATHING_DOOR_KNOCK_MASTER', 0, true, 0)
    Wait(1000)
    StartAnimScene(scene)
    RenderScriptCams(false, false, 0, true, false, 0)
    waitSceneEnd(scene)
    endScene(scene)

    TriggerEvent('jrs_bathing:TASK_MOVE_NETWORK_BY_NAME_WITH_INIT_PARAMS', { me(), 'Script_Mini_Game_Bathing_Deluxe', `CLIPSET@MINI_GAMES@BATHING@DELUXE@ARTHUR`, `DEFAULT`, 'BATHING' })
    TriggerEvent('jrs_bathing:TASK_MOVE_NETWORK_BY_NAME_WITH_INIT_PARAMS', { BathingPed, 'Script_Mini_Game_Bathing_Deluxe', `CLIPSET@MINI_GAMES@BATHING@DELUXE@MAID`, `DEFAULT`, 'BATHING' })

    TogglePrompts({ 'STOP_BATHING', 'SCRUB' }, true)
    RenderScriptCams(true, true, 0, true, false, 0)
end)

RegisterNetEvent('jrs_bathing:client:HideDeluxePrompt', function()
    TogglePrompts({ 'REQUEST_DELUXE_BATHING' }, false)
    TogglePrompts({ 'STOP_BATHING', 'SCRUB' }, true)
end)

-- a prompt press that has to be answered by the server (money, room) or ends the bath
AddEventHandler('jrs_bathing:ask', function(what)
    TogglePrompts('ALL', false)
    if what == 'START_BATHING' then TriggerServerEvent('jrs_bathing:server:canEnterBath', town)
    elseif what == 'REQUEST_DELUXE_BATHING' then TriggerServerEvent('jrs_bathing:server:canEnterDeluxeBath', town)
    elseif what == 'STOP_BATHING' then leaveBath() end
    Wait(500)
end)

-- ------------------------------------------------------------------ world: blips, doors, entering

local function nearestTub()
    local here = GetEntityCoords(me())
    for name, zone in pairs(Config.BathingZones) do
        if #(here - zone.consumer) < 1.0 then return name end
    end
end

CreateThread(function()
    LocalPlayer.state.isBathingActive = false

    for _, zone in pairs(Config.BathingZones) do
        Wait(10)
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 0xB04092F8, zone.consumer)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, 'blip_bath_house'))
        SetBlipSprite(blip, `blip_bath_house`)
        table.insert(Config.CreatedEntries, { type = 'BLIP', handle = blip })
    end

    for _, zone in pairs(Config.BathingZones) do
        if zone.door and not IsDoorRegisteredWithSystem(zone.door) then
            Citizen.InvokeNative(0xD99229FE93B46286, zone.door, 1, 1, 0, 0, 0, 0)
            DoorSystemSetDoorState(zone.door, 1)
        end
    end

    createPrompts()

    while true do
        local tub = nearestTub()
        if tub and not LocalPlayer.state.isBathingActive then
            if not promptsOn then TogglePrompts({ 'START_BATHING' }, true) end
            if promptDone('START_BATHING') then
                town = tub
                TriggerEvent('jrs_bathing:ask', 'START_BATHING')
            end
        else
            if promptsOn then TogglePrompts({ 'START_BATHING' }, false) end
            Wait(250)
        end
        Wait(100)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    LocalPlayer.state.isBathingActive = false

    for _, entry in ipairs(Config.CreatedEntries) do
        if entry.type == 'PED' then
            if DoesEntityExist(entry.handle) then DeleteEntity(entry.handle) end
        elseif entry.type == 'BLIP' then
            RemoveBlip(entry.handle)
        elseif entry.type == 'PROMPT' then
            Citizen.InvokeNative(0x00EDE88D4D13CF59, entry.handle)
        elseif entry.type == 'CAM' and DoesCamExist(entry.handle) then
            RenderScriptCams(false, false, 0, false, false, false)
            DestroyCam(entry.handle)
        end
    end
    Config.CreatedEntries = {}
end)
