-- jrs_canoe | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_canoe | server callbacks

JRS.CreateCallback('jrs_canoe:getStoreStatus', function(_, reply, data)
    reply(GetBusyStoresList()[data.index] == true)
end)

JRS.CreateCallback('jrs_canoe:canRentSelectedBoat', function(src, reply, data)
    local player = JRS.MethodPlayer(src)
    local store = type(data) == 'table' and Config.Stores[data.index]
    local canoe = store and store.Canoes and store.Canoes[data.vehicle_index]
    if not player or not canoe then return reply(false) end
    if not JRS.Near(src, store.Coords, (store.DistanceOpenStore or 3.0) + 5.0) then return reply(false) end

    if player.getAccount(0) < canoe.Cost then
        SendNotification(src, Locales['NOT_ENOUGH_MONEY'])
        return reply(false)
    end

    player.removeAccount(0, canoe.Cost)
    SendNotification(src, Locales['SUCCESSFULLY_RENTED'])
    TriggerClientEvent('jrs_canoe:client:close', src)
    reply(true)
end)
