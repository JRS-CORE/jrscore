-- ==========================================================================
--  JRS CORE  |  jrs_playerinfo  |  config.lua
--  player info - /info shows your character, job and money
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'
Config.Command  = 'info'
Config.Align    = 'top-right'
Config.Cooldown = 3             -- seconds between two /info

-- rows shown in the menu
Config.Show = {
    job        = true,
    cash       = true,
    gold       = true,
    dirtyMoney = true,
    banks      = true,          -- one row per bank account (jrs_banking)
    charId     = true,
    serverId   = true,
}
