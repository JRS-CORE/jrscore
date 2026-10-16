-- jrs_goldclaim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_goldclaim | client: placing a gold rocker. A see-through copy floats in front of the player;
-- arrow keys turn it, holding the place key confirms, holding the cancel key stops.

local group = GetRandomIntInRange(0, 0xffffff)
local prompts = {}
local placing = false

local KEY = { cancel = 0xF84FA74F, place = 0x07CE1E61, left = 0xA65EBAB4, right = 0xDEB34313 }

local function makePrompt(key, text, hold)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, key)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', text))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    if hold then PromptSetHoldMode(prompt, true) else PromptSetStandardMode(prompt, true) end
    PromptSetGroup(prompt, group)
    PromptRegisterEnd(prompt)
    return prompt
end

CreateThread(function()
    prompts.cancel = makePrompt(KEY.cancel, L('prompt_cancel'), true)
    prompts.place = makePrompt(KEY.place, L('prompt_place'), true)
    prompts.left = makePrompt(KEY.left, L('prompt_rotate_left'), false)
    prompts.right = makePrompt(KEY.right, L('prompt_rotate_right'), false)
end)

local function startPlacing()
    if placing or IsBusy() then return end
    local model = Config.GoldRocker
    if not LoadModel(model) then return end
    placing = true

    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

    -- attach offsets are in the ped's own space, so "in front" is +Y
    local ahead = Config.ForwardDistance
    local at = GetEntityCoords(ped)

    -- `ghost` is what the player sees, the invisible `anchor` is read for the final position
    local ghost = CreateObject(model, at.x, at.y, at.z, false, false, false)
    local anchor = CreateObject(model, at.x, at.y, at.z, false, false, false)
    SetEntityAlpha(ghost, 180, false)
    SetEntityAlpha(anchor, 0, false)
    SetEntityCollision(ghost, false, false)
    SetEntityCollision(anchor, false, false)
    AttachEntityToEntity(anchor, ped, 0, 0.0, ahead, 0.5, 0.0, 0.0, 0.0, true, false, false, false, 0, false)

    local title = CreateVarString(10, 'LITERAL_STRING', L('prompt_group'))
    local turn = 0.0

    local function stop()
        DeleteEntity(anchor)
        DeleteEntity(ghost)
        placing = false
    end

    while true do
        Wait(0)
        PromptSetActiveGroupThisFrame(group, title)

        if IsControlPressed(0, KEY.left) then turn = turn - 1.0 end
        if IsControlPressed(0, KEY.right) then turn = turn + 1.0 end
        AttachEntityToEntity(ghost, ped, 0, 0.0, ahead, -0.8, 0.0, 0.0, turn, true, false, false, false, 0, false)

        if PromptHasHoldModeCompleted(prompts.place) then
            local spot, facing = GetEntityCoords(anchor), GetEntityHeading(ghost)
            stop()
            TriggerEvent('jrs_goldclaim:rocker:client:placeNewProp', spot, facing)
            break
        end
        if PromptHasHoldModeCompleted(prompts.cancel) or IsEntityDead(ped) then
            stop()
            break
        end
    end

    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('jrs_goldclaim:rocker:client:createprop', startPlacing)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, prompt in pairs(prompts) do PromptDelete(prompt) end
end)
