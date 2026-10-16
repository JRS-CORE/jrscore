-- jrs_basemenu | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Everything shown in the menu comes from the server: the client only asks for its own data.
JRS.Callback('jrs_basemenu:info', function(src)
    local char = JRS.Char(src)
    if not char then return nil end
    local job, grade = JRS.Job(src)
    return {
        id      = src,
        name    = JRS.Name(src),
        job     = char.jobLabel or job or '-',
        grade   = grade,
        money   = JRS.Money(src, 0),
        gold    = JRS.Money(src, 1),
        players = #GetPlayers(),
        max     = GetConvarInt('sv_maxclients', 48),
    }
end)
