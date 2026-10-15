-- ==========================================================================
--  JRS CORE  |  jrs_essentials  |  config.lua
--  essentials - AFK kick, pointing, eagle eye per job, first-person aiming and small fixes
-- ==========================================================================

Config = {}

Config.Language = 'en'                  -- 'en' or 'ar'

-- AFK kick (staff groups are never kicked)
Config.Afk = {
    enabled = true,
    seconds = 1800,
    warnAt  = { 900, 600, 300, 60, 30, 10 },
    exempt  = { admin = true, superadmin = true, moderator = true, mod = true },
}

-- Hold B to point
Config.Pointing = { enabled = true, key = 0x4CC0E2FE }

-- Eagle eye: everyone = true leaves it to jrs_core (gameplay.EagleEye); false = only the jobs listed
Config.EagleEye = {
    everyone = true,
    jobs     = { police = true, sheriff = true, hunter = true },
}

Config.FirstPersonAiming   = false      -- force first person while free-aiming
Config.HideChallengeEvents = true       -- hide RDO challenge / reward pop-ups
Config.StopAutoShuffle     = true       -- passenger does not slide into the driver seat
Config.DrownFix            = true       -- stops peds drowning / boats sinking on spawn
