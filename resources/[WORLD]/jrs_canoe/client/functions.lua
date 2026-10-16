-- jrs_canoe | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_canoe | client helpers: blips, the store clerk, prompts and carrying a canoe

local shopGroup, shopPrompt = GetRandomIntInRange(0, 0xffffff), nil
local dropGroup, dropPrompt = GetRandomIntInRange(0, 0xffffff), nil

local function makePrompt(group, text, key, hold)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, key)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', text))
    PromptSetEnabled(prompt, 1)
    PromptSetVisible(prompt, 1)
    PromptSetStandardMode(prompt, 1)
    if hold then PromptSetHoldMode(prompt, hold) end
    PromptSetGroup(prompt, group)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, prompt, true)
    PromptRegisterEnd(prompt)
    return prompt
end

function CreatePromptRegistration()
    shopPrompt = makePrompt(shopGroup, LocalesEN['PROMPT_TEXT'], Config.PromptAction.Key, Config.PromptAction.HoldMode)
end

function RegisterCanoeDropActionPrompt()
    dropPrompt = makePrompt(dropGroup, Config.CanoeActionPrompt.Label, Config.CanoeActionPrompt.Key)
end

function GetPromptData() return shopGroup, shopPrompt end
function GetCanoeActionPromptData() return dropGroup, dropPrompt end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if shopPrompt then PromptDelete(shopPrompt) end
    if dropPrompt then PromptDelete(dropPrompt) end
    if GetPlayerData().IsBusy then ClearPedTasksImmediately(PlayerPedId()) end

    for _, store in pairs(Config.Stores) do
        if store.BlipHandle then RemoveBlip(store.BlipHandle) end
        if store.NPC then
            DeleteEntity(store.NPC)
            DeletePed(store.NPC)
            SetEntityAsNoLongerNeeded(store.NPC)
        end
    end
    if Config.UseInteractPrompt then JRS.RemoveModelTarget(Config.Models, Config.ModelsTargetOptions) end
end)

-- ------------------------------------------------------------------ blips

function AddBlip(id, status)
    local store = Config.Stores[id]
    local data = store.BlipData
    if not data then return end

    local sprite, modifier = data.Sprite, data.OpenBlipModifier or 'BLIP_MODIFIER_MP_COLOR_32'
    if status == 'CLOSED' then
        sprite, modifier = data.DisplayClosedHours.Sprite, data.DisplayClosedHours.BlipModifier
    end

    local blip = N_0x554d9d53f696d002(1664425300, store.Coords.x, store.Coords.y, store.Coords.z)
    SetBlipSprite(blip, sprite, 1)
    SetBlipScale(blip, 0.2)
    Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(modifier))
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, data.Name)
    store.BlipHandle, store.BlipHandleModifier = blip, modifier
end

-- ------------------------------------------------------------------ text on screen

local function drawText(text, x, y, scale, r, g, b, a)
    SetTextScale(scale, scale)
    SetTextColor(r, g, b, a)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 255)
    Citizen.InvokeNative(0xADA9255D, 10)
    DisplayText(CreateVarString(10, 'LITERAL_STRING', text, Citizen.ResultAsLong()), x, y)
end

-- shows `message` for `frames` frames (default 200)
function ShowNotification(message, colour, frames)
    local c = colour or { r = 161, g = 3, b = 0, a = 255 }
    for _ = 1, (frames and frames > 0) and frames or 200 do
        drawText(message, 0.50, 0.90, 0.6, c.r, c.g, c.b, c.a)
        Wait(0)
    end
end

-- ------------------------------------------------------------------ the clerk

function LoadModel(model)
    model = type(model) == 'string' and joaat(model) or model
    local limit = GetGameTimer() + 8000
    repeat
        RequestModel(model)
        Wait(100)
    until HasModelLoaded(model) or GetGameTimer() > limit
    return HasModelLoaded(model)
end

function SpawnNPC(id)
    local store = Config.Stores[id]
    LoadModel(store.NPCData.Model)

    local at = store.NPCData.Coords
    local npc = CreatePed(store.NPCData.Model, at.x, at.y, at.z, at.h, false, true, true, true)
    Citizen.InvokeNative(0x283978A15512B2FE, npc, true)
    SetEntityNoCollisionEntity(PlayerPedId(), npc, false)
    SetEntityCanBeDamaged(npc, false)
    SetEntityInvincible(npc, true)
    Wait(1000)
    FreezeEntityPosition(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    store.NPC = npc

    if Config.UseInteractPrompt then
        JRS.AddEntityTarget(npc, { {
            label = store.PromptName, icon = store.TargetIcon, distance = store.TargetDistance, description = '',
            onSelect = function() OpenCanoeRentingShop(id, store.City) end,
        } })
    end
end

-- ------------------------------------------------------------------ finding a canoe

local sphere = Citizen.InvokeNative(0xB3FB80A32BAE3065, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0)

-- some vehicle inside a 2 m sphere around `at`, or nil
function GetClosestVehicle(at)
    local set = CreateItemset(true)
    local found
    if sphere then
        Citizen.InvokeNative(0x541B8576615C33DE, sphere, at.x, at.y, at.z)
        local count = Citizen.InvokeNative(0x886171A12F400B89, sphere, set, 2)
        if count and count > 0 then found = GetIndexedItemInItemset(0, set) end
    end
    if IsItemsetValid(set) then Citizen.InvokeNative(0x20A4BF0E09BEE146, set) end
    return found
end

function IsModelCanoe(model)
    for _, name in pairs(Config.Models) do
        if model == joaat(name) then return true end
    end
    return false
end

-- the vehicle entity (and its network id) of the canoe near `at`, if it is one
local function canoeNear(at)
    local vehicle = GetClosestVehicle(at)
    local netId = Citizen.InvokeNative(0xB4C94523F023419C, vehicle)
    local entity = Citizen.InvokeNative(0x367B936610BA360C, netId)
    return entity, netId
end

function IsCarryingCanoe()
    local ped = PlayerPedId()
    if not IsPedCarryingSomething(ped) then return false end

    local entity = canoeNear(GetEntityCoords(ped))
    if DoesEntityExist(entity) and IsEntityAttached(entity) and IsModelCanoe(GetEntityModel(entity)) then
        return true, entity
    end
    return false, 0
end

function DropCarriedCanoe()
    local ped = PlayerPedId()
    local carrying, canoe = IsCarryingCanoe()
    if not carrying then return end

    FreezeEntityPosition(ped, true)
    TaskStandStill(ped, -1)
    DetachEntity(canoe, nil, nil)
    SetEntityHeading(canoe, GetEntityHeading(ped))
    ClearPedTasksImmediately(ped)
    PickedUpCanoe = false

    Wait(1000)
    FreezeEntityPosition(ped, false)
    TaskStandStill(ped, 1)
end

function PickupClosestCanoe()
    local ped = PlayerPedId()
    if IsCarryingCanoe() then return end

    local canoe, netId = canoeNear(GetEntityCoords(ped))
    if not IsModelCanoe(GetEntityModel(canoe)) or not NetworkDoesNetworkIdExist(netId) then return end

    SetVehicleAsNoLongerNeeded(canoe)
    NetworkRequestControlOfNetworkId(netId)
    NetworkRequestControlOfEntity(canoe)
    SetVehicleHasBeenOwnedByPlayer(canoe, true)
    SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true, 0, false, false)
    Wait(1000)

    JRS.PlayAnimation(ped, { dict = 'mech_carry_box', name = 'idle', blendInSpeed = 1.0, blendOutSpeed = 8.0, duration = -1, flag = 31, playbackRate = 0.0 })
    Citizen.InvokeNative(0x6B9BBD38AB0796DF, canoe, ped, GetEntityBoneIndexByName(ped, 'SKEL_L_Finger12'), 0.20, 0.00, -0.05, 240.0, 190.0, 0.0, true, true, false, true, 1, true)
    Wait(500)
    TriggerEvent('jrs_canoe:client:tasks')
end
