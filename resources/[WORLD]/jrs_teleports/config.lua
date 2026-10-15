-- ==========================================================================
--  JRS CORE  |  jrs_teleports  |  config.lua
--  teleports - enter / leave doors that use a teleport, optionally job-locked
-- ==========================================================================

Config = {}

Config.Language  = 'en'          -- 'en' or 'ar'
Config.PromptKey = 0xCEFD9220    -- E (hold)

-- Each entry: label, enter / exit = vector4(x, y, z, heading), distance, jobs = { 'job' } or false
Config.Locations = {
    { label = 'Valentine Clothing Store', enter = vector4(-296.012, 800.5844, 118.28, 197.02), exit = vector4(-296.287, 801.9831, 118.26, 12.45), distance = 1.2, jobs = false },
    { label = 'Valentine Church',         enter = vector4(-231.671, 796.5175, 123.62, 126.43), exit = vector4(-231.183, 800.2444, 125.03, 33.55), distance = 1.3, jobs = false },
}
