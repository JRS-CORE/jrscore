-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_passports | client helpers: prompts, blips and the clerk

local group = GetRandomIntInRange(0, 0xffffff)
local prompts = {}                              -- list of { prompt, type }

function RegisterActionPrompts()
    for kind, action in pairs(Config.PromptKeys) do
        local prompt = PromptRegisterBegin()
        PromptSetControlAction(prompt, action.key)
        PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', action.label))
        PromptSetEnabled(prompt, 1)
        PromptSetVisible(prompt, 1)
        PromptSetStandardMode(prompt, 1)
        PromptSetHoldMode(prompt, 1000)
        PromptSetGroup(prompt, group)
        Citizen.InvokeNative(0xC5F428EE08FA7F2C, prompt, true)
        PromptRegisterEnd(prompt)
        prompts[#prompts + 1] = { prompt = prompt, type = kind }
    end
end

function GetPromptData() return group, prompts end

function AddBlip(index, status)
    local office = Config.Locations[index]
    local data = office.BlipData
    if not data then return end

    local sprite, modifier = data.Sprite, data.OpenBlipModifier or 'BLIP_MODIFIER_MP_COLOR_32'
    if status == 'CLOSED' then
        sprite, modifier = data.DisplayClosedHours.Sprite, data.DisplayClosedHours.BlipModifier
    end

    local blip = N_0x554d9d53f696d002(1664425300, office.Coords.x, office.Coords.y, office.Coords.z)
    SetBlipSprite(blip, sprite, 1)
    SetBlipScale(blip, 0.2)
    Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(modifier))
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, data.Title)
    office.BlipHandle, office.BlipHandleModifier = blip, modifier
end

function LoadModel(name)
    local hash = joaat(name)
    repeat RequestModel(hash) Wait(10) until HasModelLoaded(hash)
end

function RemoveEntityProperly(entity, modelHash)
    DeleteEntity(entity)
    DeletePed(entity)
    SetEntityAsNoLongerNeeded(entity)
    if modelHash then SetModelAsNoLongerNeeded(modelHash) end
end

function SpawnNPC(index)
    local office = Config.Locations[index]
    LoadModel(office.NPCData.Model)

    local at = office.NPCData.Coords
    local npc = CreatePed(office.NPCData.Model, at.x, at.y, at.z, at.h, false, true, true, true)
    Citizen.InvokeNative(0x283978A15512B2FE, npc, true)
    SetEntityNoCollisionEntity(PlayerPedId(), npc, false)
    SetEntityCanBeDamaged(npc, false)
    SetEntityInvincible(npc, true)
    Wait(1000)
    FreezeEntityPosition(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    office.NPC = npc
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Citizen.InvokeNative(0x00EDE88D4D13CF59, group)
    for _, office in pairs(Config.Locations) do
        if office.BlipHandle then RemoveBlip(office.BlipHandle) end
        if office.NPC then RemoveEntityProperly(office.NPC) end
    end
end)
