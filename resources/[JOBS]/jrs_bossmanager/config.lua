-- ==========================================================================
--  JRS CORE  |  jrs_bossmanager  |  config.lua
--  boss menu - bosses hire, promote, demote and fire people of their job
-- ==========================================================================

Config = {}

Config.Language    = 'en'          -- 'en' or 'ar'

-- ─── Opening the menu ──────────────────────────────────────────────────────
Config.Key         = 0x446258B6    -- PAGE UP (jrs_admin uses the default key)
Config.Command     = 'boss'        -- /boss opens the menu too (false = off)

-- ─── Rules ─────────────────────────────────────────────────────────────────
Config.MaxGrade    = 10            -- highest grade a boss can give
Config.HireRange   = 4.0           -- the new employee must stand this close
Config.Unemployed  = 'unemployed'  -- job given when someone is fired

-- ─── Admin commands (admins / players with the "command" ace) ──────────────
-- /givelicense <id> <job>   make a player boss of a job
-- /revokelicense <id>       take the boss license back
Config.GiveLicenseCommand   = 'givelicense'
Config.RevokeLicenseCommand = 'revokelicense'
