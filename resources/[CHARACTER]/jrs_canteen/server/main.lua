-- jrs_canteen | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local Core = exports.jrs_core:GetCore()

-- source -> { item = name, at = GetGameTimer() } : one canteen action at a time
local pending = {}

local function hasItem(src, item)
    return (tonumber(exports.jrs_inventory:getItemCount(src, nil, item)) or 0) >= 1
end

local function swapItem(src, from, to)
    if not exports.jrs_inventory:subItem(src, from, 1) then return false end
    if not exports.jrs_inventory:canCarryItem(src, to, 1) or not exports.jrs_inventory:addItem(src, to, 1) then
        exports.jrs_inventory:addItem(src, from, 1)
        return false
    end
    return true
end

for _, item in ipairs(Config.CanteenItems) do
    exports.jrs_inventory:registerUsableItem(item, function(data)
        local src = data.source
        if pending[src] then
            return Core.NotifyRightTip(src, L('busy'), 3000)
        end
        exports.jrs_inventory:closeInventory(src)
        pending[src] = { item = item, at = GetGameTimer() }
        TriggerClientEvent('jrs_canteen:client:use', src, item)
    end)
end

-- The client finished the animation. refill = true when the player was kneeling
-- in fresh water, false for a sip, nil when it was cancelled.
RegisterNetEvent('jrs_canteen:server:finish', function(item, refill)
    local src = source
    local p = pending[src]
    pending[src] = nil
    if not p or p.item ~= item or refill == nil then return end

    local minTime = (refill and Config.RefillTime or Config.DrinkTime) - 750
    if GetGameTimer() - p.at < minTime then return end
    if not hasItem(src, item) then return end

    if refill then
        if item ~= Config.FullCanteen and swapItem(src, item, Config.FullCanteen) then
            -- kneeling at fresh water: drink your fill while refilling
            TriggerClientEvent('jrsmetabolism:changeValue', src, 'Thirst', Config.RefillThirst)
            Core.NotifyRightTip(src, L('refilled'), 3000)
        end
        return
    end

    local nextItem = Config.Canteens[item]
    if not nextItem then
        return Core.NotifyRightTip(src, L('empty'), 4000)
    end
    if swapItem(src, item, nextItem) then
        TriggerClientEvent('jrsmetabolism:changeValue', src, 'Thirst', Config.DrinkThirst)
        Core.NotifyRightTip(src, L('drank'), 3000)
    end
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)
