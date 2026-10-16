-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_passports | server: using the passport item shows it to everybody close by

JRS.UsableData(Config.PassportItem, 'jrs_passports', function(data)
    local src = data.source
    local row = MySQL.single.await('SELECT * FROM `passports` WHERE `identityId` = ?', { data.metadata.identityId })
    if not row then return end

    -- the expiry date is shown in the server's year
    row.expiration_date = os.date('%Y-%m-%d %H:%M:%S', row.expiration_date):gsub('^%d%d%d%d', Config.Year)

    local here = GetEntityCoords(GetPlayerPed(src))
    for _, player in pairs(JRS.Players().players) do
        local target = tonumber(player.source)
        if #(here - GetEntityCoords(GetPlayerPed(target))) <= Config.DisplayPassportCardDistance then
            TriggerClientEvent('jrs_inventory:CloseInv', target)
            Wait(500)
            TriggerClientEvent('jrs_passports:client:onPassportItemUse', target, row)
        end
    end
end)
