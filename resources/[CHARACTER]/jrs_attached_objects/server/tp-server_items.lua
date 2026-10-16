-- jrs_attached_objects | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_attached_objects | server: every item set is a usable item

CreateThread(function()
    for item in pairs(Config.AttachedItemSets) do
        JRS.UsableData(item, 'jrs_attached_objects', function(data)
            TriggerClientEvent('jrs_attached_objects:client:attach', data.source, item)
            TriggerClientEvent('jrs_inventory:CloseInv', data.source)
        end)
    end
end)
