-- jrs_bathing | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- town -> source using that bath room
local sessions = {}

local function nearBath(src, town)
    local zone = Config.BathingZones[town]
    return zone and JRS.Near(src, zone.consumer, 3.0)
end

RegisterNetEvent('jrs_bathing:server:canEnterBath', function(town)
    local src = source
    if type(town) ~= 'string' or not nearBath(src, town) or not JRS.Char(src) then return end
    for _, who in pairs(sessions) do
        if who == src then return end
    end
    if sessions[town] then
        return JRS.Notify(src, L('notify_occupied'))
    end
    if not JRS.TakeMoney(src, Config.NormalBathPrice) then
        return JRS.Notify(src, L('notify_not_enough_money'))
    end
    sessions[town] = src
    TriggerClientEvent('jrs_bathing:client:ToggleInvincibility', src, true)
    TriggerClientEvent('jrs_bathing:client:StartBath', src, town)
end)

RegisterNetEvent('jrs_bathing:server:canEnterDeluxeBath', function(town)
    local src = source
    if sessions[town] ~= src or not nearBath(src, town) then return end
    if not JRS.TakeMoney(src, Config.DeluxeBathPrice) then
        JRS.Notify(src, L('notify_not_enough_money'))
        return TriggerClientEvent('jrs_bathing:client:HideDeluxePrompt', src)
    end
    TriggerClientEvent('jrs_bathing:client:StartDeluxeBath', src, town)
end)

RegisterNetEvent('jrs_bathing:server:setBathAsFree', function(town)
    local src = source
    if sessions[town] == src then
        sessions[town] = nil
        TriggerClientEvent('jrs_bathing:client:ToggleInvincibility', src, false)
    end
end)

AddEventHandler('playerDropped', function()
    for town, who in pairs(sessions) do
        if who == source then sessions[town] = nil end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, who in pairs(sessions) do
        TriggerClientEvent('jrs_bathing:client:ToggleInvincibility', who, false)
    end
    sessions = {}
end)
