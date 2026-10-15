-- jrs_fishing | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_fishing | client
-- The game runs the fishing mini game as a script task. This file reads that task's state every frame
-- (see client_js.js for the bridge), reacts to the phase the player is in and nudges the task:
-- cast -> wait for a bite (fish are lured towards the bobber) -> fight the fish -> keep or release it.

local Core = exports.jrs_core:GetCore()
local T = Translation.Langs[Config.Lang] or Translation.Langs.English
local TE = Translation.Langs.English          -- prompts stay in English: the game font has no Arabic glyphs

-- ------------------------------------------------------------------ the task struct

-- phases of the mini game
local READY, WAITING, HOOKED, LANDED = 1, 6, 7, 12

-- slots of the struct that hold floats; the other slots hold integers
local isFloat = {}
for _, slot in ipairs({ 1, 2, 3, 4, 8, 9, 13, 14, 15, 17, 20, 21, 22, 23, 24, 25, 26, 27 }) do isFloat[slot] = true end

-- the slots we use
local SLOT = { STATE = 0, LINE = 2, FLAG = 6, FISH = 7, WEIGHT = 8, BOBBER = 11, HOOK = 12, ROD_WEIGHT = 18, ROD_SIDE = 22, ROD_UP = 23 }

local task = { running = false, slot = {} }

local function readTask()
    local result = exports.jrs_fishing:GET_TASK_FISHING_DATA_EXTRA()
    task.running = result[1]
    for i = 0, 27 do
        local from = isFloat[i] and result[3] or result[2]
        task.slot[i] = from[tostring(2 * i)]
    end
end

local function pushTask()
    if task.slot[0] == nil then return end
    local out = {}
    for i = 0, 27 do out['f_' .. i] = task.slot[i] end
    exports.jrs_fishing:SET_TASK_FISHING_DATA_EXTRA(out)
end

local function slot(i) return task.slot[i] end
local function setSlot(i, value) task.slot[i] = value; pushTask() end

local function phase() return slot(SLOT.STATE) end

-- ------------------------------------------------------------------ fish knowledge

local fishName = {}                       -- model hash -> display name
for model, row in pairs(FishData) do fishName[joaat(model)] = row[1] end

-- weight range in kg, by how big the fish is
local sizes = {
    small  = { 0.5, 5.0,   { 'BLUEGIL_01_SM', 'BULLHEADCAT_01_SM', 'REDFINPICKEREL_01_SM', 'PERCH_01_SM', 'CHAINPICKEREL_01_SM', 'ROCKBASS_01_SM' } },
    medium = { 6.0, 10.0,  { 'BLUEGIL_01_MS', 'BULLHEADCAT_01_MS', 'CHAINPICKEREL_01_MS', 'PERCH_01_MS', 'LARGEMOUTHBASS_01_MS', 'REDFINPICKEREL_01_MS',
                             'RAINBOWTROUT_01_MS', 'ROCKBASS_01_MS', 'SALMONSOCKEYE_01_MS', 'SMALLMOUTHBASS_01_MS' } },
    large  = { 14.0, 20.0, { 'SALMONSOCKEYE_01_ML', 'CHANNELCATFISH_01_LG', 'LAKESTURGEON_01_LG', 'LONGNOSEGAR_01_LG', 'MUSKIE_01_LG', 'NORTHERNPIKE_01_LG' } },
    legend = { 20.0, 25.0, { 'LARGEMOUTHBASS_01_LG', 'RAINBOWTROUT_01_LG', 'SALMONSOCKEYE_01_LG', 'SMALLMOUTHBASS_01_LG' } },
}
local weightRange = {}                    -- model hash -> { min, max }
for _, size in pairs(sizes) do
    for _, short in ipairs(size[3]) do weightRange[joaat('A_C_FISH' .. short)] = size end
end

local function rollWeight(model)
    local size = weightRange[model]
    if not size then return 0.0 end
    return math.random() * (size[2] - size[1]) + size[1]
end

local function likesBait(model, bait)
    for _, name in ipairs(BaitsPerFish[bait] or {}) do
        if fishName[model] == FishData[name][1] then return true end
    end
    return false
end

-- live fish and fish-like animals within `radius` of `at`
local function fishAround(at, radius)
    local found = {}
    local set = CreateItemset(true)
    local count = Citizen.InvokeNative(0x59B57C4B06531E1E, at, radius, set, 1, Citizen.ResultAsInteger())
    for i = 0, count - 1 do
        local entity = GetIndexedItemInItemset(i, set)
        local kind = GetEntityPopulationType(entity)
        if (kind == 6 or kind == 8) and not IsPedDeadOrDying(entity, false) then found[#found + 1] = entity end
    end
    if IsItemsetValid(set) then DestroyItemset(set) end
    return found
end

-- ------------------------------------------------------------------ prompts

local groups = {}
local layout = {
    ready   = { { 'change_bait', joaat('INPUT_AIM'), 'PrepRod' },          { 'throw_hook', 0x07CE1E61, 'ThrowHook' } },
    waiting = { { 'hook_fish', joaat('INPUT_ATTACK'), 'HookFish' },        { 'cancel', 0x8FFC75D6, 'Cancel' }, { 'reel_lure', 0xDB096B85, 'ReelLure' } },
    hooked  = { { 'reel', 0xFBD7B3E6, 'ReelIn' },                          { 'cancel', 0x8FFC75D6, 'Cancel' } },
    finish  = { { 'keep_fish', joaat('INPUT_ATTACK'), 'KeepFish' },        { 'throw_fish', joaat('INPUT_AIM'), 'ThrowFish' } },
}

local function buildPrompts()
    if next(groups) then return end
    for name, prompts in pairs(layout) do
        local group = { id = GetRandomIntInRange(0, 0xffffff), handles = {} }
        for _, def in ipairs(prompts) do
            local prompt = UiPromptRegisterBegin()
            UiPromptSetControlAction(prompt, def[2])
            UiPromptSetText(prompt, VarString(10, 'LITERAL_STRING', TE[def[3]]))
            UiPromptSetEnabled(prompt, true)
            UiPromptSetVisible(prompt, true)
            UiPromptSetHoldMode(prompt, 0)
            UiPromptSetGroup(prompt, group.id, 0)
            UiPromptRegisterEnd(prompt)
            group.handles[#group.handles + 1] = prompt
        end
        groups[name] = group
    end
end

local function title(group, text)
    UiPromptSetActiveGroupThisFrame(groups[group].id, VarString(10, 'LITERAL_STRING', text), 0, 0, 0, 0)
end

local caught = { weight = 0 }

CreateThread(function()
    buildPrompts()
    while true do
        Wait(0)
        local now = phase()
        if now == READY then
            title('ready', TE.ReadyToFish)
        elseif now == WAITING then
            title('waiting', TE.Fishing)
        elseif now == HOOKED then
            caught.weight = slot(SLOT.WEIGHT)
            title('hooked', TE.MiniGame)
        elseif now == LANDED then
            local name = fishName[GetEntityModel(slot(SLOT.FISH))]
            if name then
                title('finish', ('%s : %s // %s : %s'):format(TE.FishName, name, TE.FishWeight,
                    (string.format('%.2f%%', caught.weight * 54.25):gsub('%%', '')) .. 'Kg'))
            end
        end
    end
end)

-- ------------------------------------------------------------------ fishing state

local fishing, bait = false, nil
local fight = { force = 0.6, mood = 0, nextChange = 0, side = 0 }       -- mood: 0 calm, 1 fighting
local lureCooldown = 0
local HOLD, ESCAPE = joaat('INPUT_GAME_MENU_OPTION'), 0x8FFC75D6
local SET_BAIT_ON_ROD = 0x9B0C7FA063E67629

local function resetState()
    fishing, bait = false, nil
    fight.force, fight.mood, fight.nextChange, fight.side = 0.6, 0, 0, 0
end
AddEventHandler('jrs_fishing:resetFishing', resetState)

local function clearRodBait()
    Citizen.InvokeNative(SET_BAIT_ON_ROD, PlayerPedId(), '', 0, 1)
end

local function dropFish(fish)
    SetEntityAsMissionEntity(fish, true, true)
    Wait(3000)
    DeleteEntity(fish)
end

-- the server asks before it spends the bait: is the rod in hand, and is this bait new?
Core.Callback.Register('jrs_fishing:checkRodAndBait', function(reply, offered)
    local _, weapon = GetCurrentPedWeapon(PlayerPedId(), true, 0, false)
    if weapon ~= joaat('WEAPON_FISHINGROD') then
        Core.NotifyRightTip(T.NoFishingRodEquipped, 4000)
        return reply({ false })
    end
    if bait then
        if bait == offered then
            Core.NotifyRightTip(T.AlreadyHaveBait, 4000)
            return reply({ false })
        end
        fishing = false
        Core.NotifyRightTip(T.ChangeBait, 4000)
    end
    bait = offered
    reply({ true, bait })
end)

-- ------------------------------------------------------------------ phase handlers

-- a lured fish close enough to the hook gets "hooked" with a roll
local function startFight(ped, fish)
    Citizen.InvokeNative(0xF0FBF193F1F5C0EA, fish)
    SetPedConfigFlag(fish, 17, true)
    Citizen.InvokeNative(0x1F298C7BD30D1240, ped)
    ClearPedTasksImmediately(fish, false, true)
    TaskSetBlockingOfNonTemporaryEvents(fish, true)
    Citizen.InvokeNative(0x1A52076D26E09004, ped, fish)

    setSlot(SLOT.FISH, fish)
    local pounds = rollWeight(GetEntityModel(fish))
    setSlot(SLOT.WEIGHT, pounds / 54.25)
    caught.weight = pounds / 54.25
    setSlot(SLOT.ROD_WEIGHT, 2)

    fight.force = 0.6
    setSlot(SLOT.FLAG, 4)
end

local function whileWaiting(ped)
    if IsControlJustPressed(0, ESCAPE) then setSlot(SLOT.FLAG, 128) end

    local bobber, hook = slot(SLOT.BOBBER), slot(SLOT.HOOK)
    local hookAt = GetEntityCoords(hook)

    if IsControlPressed(0, joaat('INPUT_DUCK')) then
        local pull = hookAt + (GetEntityCoords(ped, true, true) - hookAt) * Config.ReelSpeed
        SetEntityCoords(hook, pull.x, pull.y, pull.z, false, false, false, false)
    end

    setSlot(14, slot(SLOT.LINE) < 4.0 and 1.0 or 0.4)                    -- slot 14: line tension

    local biting, anyLured = nil, false
    for _, fish in ipairs(fishAround(hookAt, 50.0)) do
        local model = GetEntityModel(fish)
        if not fishName[model] then
            if Config.Debug then print('Ignoring non-mapped fish model:', model) end
        else
            local at = GetEntityCoords(fish)
            if Config.Debug then Citizen.InvokeNative(joaat('DRAW_LINE') & 0xFFFFFFFF, at, at + vec3(0, 0, 2.0), 255, 255, 0, 255) end

            if lureCooldown <= GetGameTimer() then
                if #(hookAt - at) <= 1.6 then
                    biting = fish
                elseif likesBait(model, bait) then
                    TaskGoToEntity(fish, bobber, 100, 1, 1.0, 2.0, 0)
                end
                anyLured = true
            end
        end
    end
    if anyLured then lureCooldown = GetGameTimer() + 1000 end

    if biting then
        local roll = math.random()
        if roll > 0.9 or roll < 0.2 then startFight(ped, biting) end
    end
end

local function splash(fish)
    local at = GetEntityCoords(fish)
    RequestNamedPtfxAsset(joaat('scr_mg_fishing'))
    while not HasNamedPtfxAssetLoaded(joaat('scr_mg_fishing')) do Wait(5) end
    UseParticleFxAsset('scr_mg_fishing')
    StartParticleFxNonLoopedAtCoord('scr_mg_fish_struggle', at.x, at.y, at.z, 0.0, 0.0, math.random(0, 360) + 0.0001, 1.5, false, false, false)
end

-- the fish picks a new mood: fight (3-5 s) or rest (6-10 s)
local function chooseMood(fish)
    local roll = math.random()
    if roll > 0.8 or roll < 0.2 then
        fight.force, fight.mood = 0.8, 1
        fight.nextChange = GetGameTimer() + math.random(3, 5) * 1000
        local x, y, z = table.unpack(GetEntityCoords(fish))
        exports.jrs_fishing:VERTICAL_PROBE(x, y, z, 1)
        splash(fish)
    else
        fight.force, fight.mood = 0, 0
        fight.nextChange = GetGameTimer() + math.random(6, 10) * 1000
    end
end

local function whileFighting(ped)
    caught.weight = slot(SLOT.WEIGHT)
    if IsControlJustPressed(0, ESCAPE) then setSlot(SLOT.FLAG, 11) end

    local fish = slot(SLOT.FISH)

    -- the mouse sweeps the rod left and right
    local sweep = GetControlNormal(0, 0x390948DC)
    if sweep ~= 0 then fight.side = math.max(0, math.min(1, fight.side - 0.05 * sweep)) end
    setSlot(SLOT.ROD_SIDE, fight.side)

    if slot(SLOT.LINE) < 4.0 then setSlot(SLOT.FLAG, 12) end
    setSlot(14, 1.0)

    if GetGameTimer() >= fight.nextChange then chooseMood(fish) end

    if fight.mood == 1 then
        -- the fish pulls away: holding the key fights back but can snap the line
        if IsControlPressed(0, HOLD) then
            setSlot(SLOT.ROD_WEIGHT, 4)
            fight.force = fight.force + 0.005
        else
            fight.force = fight.force - 0.005
        end
        if IsControlJustReleased(0, HOLD) then setSlot(SLOT.ROD_WEIGHT, 2) end

        if fight.force >= 1.4 then setSlot(SLOT.FLAG, 11)
        elseif fight.force < 0.8 then fight.force = 0.8 end

        TaskSmartFleeCoord(fish, GetEntityCoords(ped), 40.0, 50, 8, 1077936128)
        splash(fish)
    else
        -- the fish is calm: reel it in
        if IsControlJustPressed(0, HOLD) or (IsControlPressed(0, HOLD) and GetGameTimer() % 25 == 0) then
            setSlot(SLOT.ROD_WEIGHT, 4)
            TaskGoToEntity(fish, ped, Config.Difficulty, 1.0, 1.5, 0.0, 0)
        end
        if IsControlJustReleased(0, HOLD) then setSlot(SLOT.ROD_WEIGHT, 2) end
    end

    local flag = slot(SLOT.FLAG)
    if flag ~= 11 and flag ~= 12 then
        setSlot(13, fight.force)
        setSlot(21, fight.force)
    end

    if IsControlJustPressed(0, joaat('INPUT_ATTACK')) then setSlot(SLOT.ROD_UP, 0.6) end
    if IsControlJustReleased(0, joaat('INPUT_ATTACK')) then setSlot(SLOT.ROD_UP, 0.0) end
end

local function keepFish()
    setSlot(SLOT.FLAG, 32)
    fishing, bait = false, nil

    local fish = slot(SLOT.FISH)
    if not NetworkGetEntityIsNetworked(fish) then return print('Fish Entity is not networked') end

    TriggerServerEvent('jrs_fishing:FishToInventory', NetworkGetNetworkIdFromEntity(fish), GetEntityModel(fish), caught.weight, 'keep')
    SetEntityAsMissionEntity(fish, true, true)
    Wait(3000)
    DeleteEntity(fish)
    clearRodBait()
end

local function releaseFish()
    fishing, bait = false, nil
    local fish = slot(SLOT.FISH)
    clearRodBait()
    setSlot(SLOT.FLAG, 64)
    dropFish(fish)
end

local function whileLanded()
    if IsControlJustPressed(0, joaat('INPUT_ATTACK')) and fishing then return keepFish() end
    if IsControlJustPressed(0, joaat('INPUT_AIM')) and fishing then return releaseFish() end

    -- the game ended the fight on its own
    if slot(5) == 96 and slot(SLOT.FLAG) == 0 then
        fishing = false
        clearRodBait()
        dropFish(slot(SLOT.FISH))
    end
end

-- ------------------------------------------------------------------ the loop while a bait is on the line

RegisterNetEvent('jrs_fishing:UseBait', function(offered)
    if fishing then return end

    local ped = PlayerPedId()
    if Citizen.InvokeNative(0xDC88D06719070C39, ped) and not IsPedSwimming(ped) then
        Core.NotifyRightTip(T.StandNearSide, 4000)
    end

    Citizen.InvokeNative(0x1096603B519C905F, 'MMFSH')
    buildPrompts()
    fishing = true
    local armed = false

    while fishing do
        Wait(0)
        readTask()

        if phase() == READY and not armed then
            armed = true
            if Config.Debug then print('Current bait: ' .. bait) end
            TaskSwapFishingBait(PlayerPedId(), bait, false)
            Citizen.InvokeNative(SET_BAIT_ON_ROD, PlayerPedId(), bait, 0, 1)
        end

        if task.running then
            local now = phase()
            ped = PlayerPedId()
            if now == WAITING then whileWaiting(ped)
            elseif now == HOOKED then whileFighting(ped)
            elseif now == LANDED then whileLanded() end

            if IsControlJustPressed(0, joaat('INPUT_TOGGLE_HOLSTER')) then
                fishing = false
                setSlot(SLOT.FLAG, 8)
                clearRodBait()
            end
        end
    end
    TriggerServerEvent('jrs_fishing:stopFishing')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, group in pairs(groups) do
        for _, prompt in ipairs(group.handles) do UiPromptDelete(prompt) end
    end
end)
