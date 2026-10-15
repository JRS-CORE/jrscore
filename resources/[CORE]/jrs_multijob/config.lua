-- ==========================================================================
--  JRS CORE  |  jrs_multijob  |  config.lua
--  multi-job - hold several jobs and switch with /myjobs
-- ==========================================================================

Config = {}

Config.Language = 'en'              -- 'en' or 'ar'
Config.Command  = 'myjobs'
Config.AdminRemoveCommand = 'removejob'   -- /removejob <id> <job>  (admins)

-- Every job a player is given (by a boss menu, an admin or a script) is remembered
-- automatically, so they can switch back to it later from /myjobs.
Config.CaptureJobChanges = true

-- Jobs that are never stored in the list (the default job is always kept by jrs_core)
Config.IgnoreJobs = { unemployed = true }

-- Max jobs and the switch cooldown live in jrs_core/config/character_service.lua
-- (MaxJobs, JobSwitchCooldownSeconds).
