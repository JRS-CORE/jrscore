-- ==========================================================================
--  JRS CORE  |  jrs_radialmenu  |  config.lua
--  radial menu - hold F6 for quick actions
-- ==========================================================================

Config = {}

Config.Language   = 'en'          -- 'en' or 'ar'
Config.Key        = 0x3C0A40F2    -- F6
Config.HoldToOpen = true          -- true: hold the key, release to close | false: tap to open

-- jobs that get the work section
Config.LawJobs   = { police = true, sheriff = true, marshal = true }
Config.MedicJobs = { doctor = true, medic = true }

---------------------------------------------------------------------
-- builders
---------------------------------------------------------------------
local function cmd(id, title, icon, command)
    return { id = id, title = title, icon = icon, type = 'command', event = command, shouldClose = true }
end

---------------------------------------------------------------------
-- menu (titles are locale keys, resolved when the menu opens)
-- type = 'command' | 'client' (TriggerEvent) | 'server' (TriggerServerEvent)
---------------------------------------------------------------------
Config.MenuItems = {
    {
        id = 'me', title = 'menu_me', icon = 'user',
        items = {
            cmd('info',     'menu_info',     'book',             'info'),
            cmd('jobs',     'menu_jobs',     'circle-user',      'myjobs'),
            cmd('walk',     'menu_walk',     'person-walking',   'walkanim'),
            cmd('handsup',  'menu_handsup',  'hand',             'handsup'),
            cmd('loadskin', 'menu_fix',      'recycle',          'mc'),
        },
    },
    {
        id = 'help', title = 'menu_help', icon = 'bell',
        items = {
            cmd('callpolice', 'menu_call_police', 'shield-halved', 'callpolice'),
            cmd('calldoctor', 'menu_call_doctor', 'user-doctor',   'calldoctor'),
        },
    },
}

Config.JobInteractions = {
    law = {
        cmd('policemenu', 'law_menu', 'id-badge',   'policeMenu'),
        cmd('drag',       'law_drag', 'user-group', 'Drag'),
    },
    medic = {
        cmd('doctormenu', 'medic_menu', 'kit-medical', 'doctormenu'),
    },
}
