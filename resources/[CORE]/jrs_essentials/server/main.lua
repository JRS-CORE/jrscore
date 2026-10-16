-- jrs_essentials | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- AFK: the client reports, the server decides (staff are exempt, and the report is
-- only honoured once the player has been connected for at least the AFK time).
local joinedAt = {}

AddEventHandler('playerJoining', function()
    joinedAt[source] = os.time()
end)

AddEventHandler('playerDropped', function()
    joinedAt[source] = nil
end)

JRS.Callback('jrs_essentials:afkExempt', function(src)
    return Config.Afk.exempt[JRS.Group(src)] == true
end)

RegisterNetEvent('jrs_essentials:server:afk', function()
    local src = source
    if not Config.Afk.enabled or Config.Afk.exempt[JRS.Group(src)] then return end
    local since = joinedAt[src]
    if since and os.time() - since < Config.Afk.seconds then return end
    DropPlayer(src, L('afk_kick'))
end)

JRS.Callback('jrs_essentials:job', function(src)
    return (JRS.Job(src))
end)
