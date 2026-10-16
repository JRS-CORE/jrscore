-- jrs_usable_items | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_usable_items | server
-- Every item in Config.UsableItems is a usable item. Using one may need another item (matches), costs
-- durability, and then tells the client to play the routine.

RegisterNetEvent('jrs_usable_items:remove', function(name)
    if Config.UsableItems[name] then JRS.Remove(source, name, 1) end
end)

CreateThread(function()
    for item, spec in pairs(Config.UsableItems) do
        JRS.UsableData(item, 'jrs_usable_items', function(data)
            local src = data.source

            local need = spec.RequiredItemUse
            if need.Enabled and JRS.Count(src, need.Item) < need.Quantity then
                return SendNotification(src, need.Warning, 'error')
            end

            local wear = spec.RemoveDurabilityOnUse
            if wear.Enabled then
                JRS.Noop(src, item, math.random(wear.RemoveValue.min, wear.RemoveValue.max), item.itemId, true)
            end
            if need.Enabled and need.Remove then JRS.Remove(src, need.Item, need.Quantity) end

            TriggerClientEvent('jrs_usable_items:client:use', src, item)
            TriggerClientEvent('jrs_inventory:CloseInv', src)
        end)
    end
end)
