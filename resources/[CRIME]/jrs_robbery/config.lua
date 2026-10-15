-- ==========================================================================
--  JRS CORE  |  jrs_robbery  |  config.lua
--  robbery - rob players with their hands up
-- ==========================================================================

Config = {}

Config.Language = 'en'              -- 'en' or 'ar'

Config.RobDistance      = 2.5       -- metres to start a robbery
Config.SearchDistance   = 4.0       -- the search closes if the robber walks further than this
Config.HandcuffItem     = 'handcuffs'
Config.ConsumeHandcuffs = false     -- true = the cuffs are used up
Config.RobCooldown      = 60        -- seconds between two robberies by the same player
Config.AutoUncuffTime   = 120       -- seconds before the victim breaks free (0 = never)

-- Hands up: /handsup or the key below (X). nil = command only.
Config.HandsUpCommand = 'handsup'
Config.HandsUpKey     = 0x8CC9CD42

-- Prompts (G = rob / uncuff)
Config.PromptKey = 0x760A9C6F

-- Jobs that can never be robbed while on duty (none by default)
Config.ProtectedJobs = {}
