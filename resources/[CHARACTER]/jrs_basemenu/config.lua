-- ==========================================================================
--  JRS CORE  |  jrs_basemenu  |  config.lua
--  base menu - a simple player menu: who you are, your money, your jobs and the server links
-- ==========================================================================

Config = {}

Config.Language = 'en'            -- 'en' or 'ar'
Config.Command  = 'menu'          -- /menu opens the base menu
Config.Key      = 0xA8E3F467      -- F1 opens it too. false = command only

Config.ServerName = 'JRS Core'    -- title of the menu

-- Extra lines at the bottom of the menu (rules, discord, website ...). Leave empty for none.
-- Picking a line shows its text as a notification.
Config.Links = {
    { label = 'Discord', text = 'discord.gg/your-invite' },
    { label = 'Rules',   text = 'Be respectful. No cheating. Stay in character.' },
}
