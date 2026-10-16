-- jrs_usable_items | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_usable_items | client helpers: the three prompts, animations, models and the ped's worn parts

-- ------------------------------------------------------------------ prompts

local prompts = { putaway = nil, use = nil, change = nil }
local KEYS <const> = { putaway = 0x3B24C470, use = 0x07B8BEAF, change = 0xD51B784F }

-- a prompt that stays hidden until the item scripts turn it on
local function register(which, text, hold)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, KEYS[which])
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', text))
    PromptSetEnabled(prompt, false)
    PromptSetVisible(prompt, false)
    PromptSetHoldMode(prompt, hold or false)
    PromptRegisterEnd(prompt)
    prompts[which] = prompt
end

function RegisterPutAwayPrompt(text, hold) register('putaway', text, hold) end
function RegisterUsePrompt(text, hold) register('use', text, hold) end
function RegisterChangePrompt(text, hold) register('change', text, hold) end

function GetPromptPutAway() return prompts.putaway end
function GetPromptUse() return prompts.use end
function GetPromptChange() return prompts.change end

-- ------------------------------------------------------------------ animations

-- plays `body` of `dict` on `actor` once the dictionary is loaded (gives up after 1.5 s)
function Anim(actor, dict, body, duration, flags, introTiming, exitTiming)
    CreateThread(function()
        RequestAnimDict(dict)
        local tries = 5
        while not HasAnimDictLoaded(dict) and tries > 0 do
            tries = tries - 1
            if tries == 0 then print('Animation Failed to Load') end
            Wait(300)
        end
        TaskPlayAnim(actor, dict, body, tonumber(introTiming) or 1.0, tonumber(exitTiming) or 1.0, duration or -1, flags or 1, 1, false, false, false, 0, true)
    end)
end

function StopAnim(dict, body)
    CreateThread(function() StopAnimTask(PlayerPedId(), dict, body, 1.0) end)
end

-- ------------------------------------------------------------------ models

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

-- ------------------------------------------------------------------ what the ped wears

local function nativeComponentCount(ped) return Citizen.InvokeNative(0x90403E8107B60E81, ped) end
local function nativeMetaPedType(ped) return Citizen.InvokeNative(0xEC9A1261BF0CE510, ped) end
local function nativeComponentAt(ped, index, struct) return Citizen.InvokeNative(0x77BA37622E22023B, ped, index, true, struct, struct) end
local function nativeComponentCategory(component, pedType) return Citizen.InvokeNative(0x5FF9A878C3D115B8, component, pedType, true) end

-- the component hash worn in `category` (e.g. 'hair'), or every worn component as category -> hash
function GetCurrentPedComponent(ped, category)
    local count = nativeComponentCount(ped)
    if not count then return 0 end

    local pedType = nativeMetaPedType(ped)
    local struct = DataView.ArrayBuffer(6 * 8)
    local worn = {}
    for i = 0, count do
        local component = nativeComponentAt(ped, i, struct:Buffer())
        if component then
            local group = nativeComponentCategory(component, pedType)
            if category == nil then worn[group] = component
            elseif joaat(category) == group then return component end
        end
    end
    return category and 0 or worn
end

function GetNumComponentsInPed(ped) return nativeComponentCount(ped) end
function GetMetaPedType(ped) return nativeMetaPedType(ped) end
function GetShopPedComponentAtIndex(ped, index, flag, a, b) return Citizen.InvokeNative(0x77BA37622E22023B, ped, index, flag, a, b) end
function GetShopPedComponentCategory(component, pedType, flag) return Citizen.InvokeNative(0x5FF9A878C3D115B8, component, pedType, flag) end
