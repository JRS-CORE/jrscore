-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_passports | server callbacks

-- the passport row of a character, or nil
function PassportOf(charIdentifier)
    return MySQL.single.await('SELECT * FROM `passports` WHERE `charidentifier` = ?', { charIdentifier })
end

JRS.CreateCallback('jrs_passports:callbacks:isRegistered', function(src, reply)
    local player = JRS.MethodPlayer(src)
    local row = player and PassportOf(player.getCharacterIdentifier())
    reply({ registered = row ~= nil, data = row or {} })
end)
