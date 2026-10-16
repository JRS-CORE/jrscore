-- jrs_metabolism | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local busy, usedAt = {}, {}
local J = JRSMetabolism
local function use(src, name, data)
    src = tonumber(src)
    local session = src and J.session(src)
    local item = ConsumableItems[name]
    local id = type(data) == 'table' and tonumber(data.itemId)
    local now = GetGameTimer()
    if not session or not item or not id or busy[src] or (usedAt[src] and now - usedAt[src] < Config.ConsumableCooldown) then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then return end
    local token = {}
    busy[src] = token
    local ok, err = pcall(function()
        local owned = exports.jrs_inventory:getItemById(src, id)
        if not owned or tostring(owned.item):lower() ~= name:lower() or (tonumber(owned.count) or 0) < 1 then return end
        if J.session(src) ~= session then return end
        if exports.jrs_inventory:subItemByID(src, id, 1) ~= true then return end
        for _, field in ipairs({'hunger', 'thirst'}) do
            session.status[field] = J.number(session.status[field] - J.number(item[field], 0, -100, 100), 0, 0, 100)
        end
        J.save(session)
        if J.session(src) ~= session then return end
        usedAt[src] = now
        J.send(src)
        exports.jrs_inventory:CloseInv(src)
        TriggerClientEvent('jrs_metabolism:client:consumable', src, name, session.charId)
    end)
    if busy[src] == token then busy[src] = nil end
    if not ok then print(('[jrs_metabolism] Consumable failed: %s'):format(err)) end
end
local function register()
    for name in pairs(ConsumableItems) do
        local key = name
        exports.jrs_inventory:RegisterUsableItem(key, function(data) use(data.source, key, data) end)
    end
end
register()
AddEventHandler('onResourceStart', function(resource)
    if resource == 'jrs_inventory' then register() end
end)
AddEventHandler('playerDropped', function() busy[tonumber(source)], usedAt[tonumber(source)] = nil, nil end)
AddEventHandler('jrs_core:server:characterUnloaded', function(src) busy[tonumber(src)], usedAt[tonumber(src)] = nil, nil end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and GetResourceState('jrs_inventory') == 'started' then
        for name in pairs(ConsumableItems) do exports.jrs_inventory:RegisterUsableItem(name, nil) end
    end
end)
