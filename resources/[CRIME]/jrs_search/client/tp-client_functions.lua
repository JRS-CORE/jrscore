-- jrs_search | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_search | client helpers: the hold-to-search prompt and finding nearby players

local group = GetRandomIntInRange(0, 0xffffff)
local searchPrompt

function RegisterActionPrompt()
    searchPrompt = PromptRegisterBegin()
    PromptSetControlAction(searchPrompt, Config.PromptKey.key)
    PromptSetText(searchPrompt, CreateVarString(10, 'LITERAL_STRING', Config.PromptKey.label))
    PromptSetEnabled(searchPrompt, 1)
    PromptSetVisible(searchPrompt, 1)
    PromptSetStandardMode(searchPrompt, 1)
    PromptSetHoldMode(searchPrompt, 1000)
    PromptSetGroup(searchPrompt, group)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, searchPrompt, true)
    PromptRegisterEnd(searchPrompt)
end

function GetPromptData()
    return group, searchPrompt
end

-- every other player closer than `radius`
function GetNearestPlayers(radius)
    local me = PlayerPedId()
    local here = GetEntityCoords(me, true, true)
    local near = {}
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= me and #(GetEntityCoords(ped, true, true) - here) < radius then
            near[#near + 1] = player
        end
    end
    return near
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Citizen.InvokeNative(0x00EDE88D4D13CF59, group) end
end)
