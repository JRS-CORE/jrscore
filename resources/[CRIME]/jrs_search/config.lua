-- ==========================================================================
--  JRS CORE  |  jrs_search  |  config.lua
--  search - search players who surrendered, are restrained or hogtied
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'

-- law jobs can search anyone in reach; everybody else only players with their hands up / restrained
Config.LawJobs = { 'Police', 'Valentine', 'Strawberry', 'Blackwater', 'Rhodes', 'SaintDenis', 'Tumbleweed', 'Annesburg', 'Armadillo' }

Config.PromptKey = { key = 0x760A9C6F, label = 'Search' }

-----------------------------------------------------------
--[[ General Settings ]]--
-----------------------------------------------------------

Config.CheckNearestPlayersDistance = 1.5

Config.SearchDead       = false
Config.SearchHogtie     = true
Config.SearchHandcuffed = true
Config.SearchHandsUp    = true

-- For how long should a new character be safe?
-- Set to 0 for disabling this option.
Config.NewCharacterSafeDuration = 180 -- time in minutes

-- The following jobs can bypass the safe duration in case a player becomes criminal in the
-- first hours while protected.
Config.NewCharacterSafeDurationJobBypass = { 'Police' }

-- (!) Set @Config.SearchByJobsOnly to false to disable or set to {}
-- If not enabled, everyone can search other players (except if this player has a blacklisted job)
Config.SearchByJobsOnly = false -- {'police', 'detective' }

-- What jobs cannot be searched by others?
Config.BlacklistedJobs = { 'Police', 'doctor' }

-- If an option @allow is false, the bypassjobs are always allowed.
Config.StealByPlayers = { -- TODO
    Cash    = { allow = true,  bypassjobs = { 'police', 'detective'} }, 
    Gold    = { allow = true,  bypassjobs = { 'police', 'detective'} }, 
    Items   = { allow = true,  bypassjobs = { 'police', 'detective'} }, 
    Weapons = { allow = false, bypassjobs = { 'police', 'detective'} }, 
}

Config.BlacklistedItems = {
    ['example1'] = true,
}

Config.BlacklistedWeapons = {
    ['WEAPON_EXAMPLE'] = true,
}

Config.PlaySearchAnimation = { 

    Enabled = true, 
    
    ['male'] = {
        dict = "amb_work@world_human_crouch_inspect@male_c@idle_a", 
        name = "idle_c",
        blendInSpeed = 8.0, 
        blendOutSpeed = 8.0, 
        duration = -1, 
        flag = 1, 
        playBackRate = 0, 
    },

    ['female'] = {
        dict = "amb_work@world_human_crouch_inspect@female_a@idle_a", 
        name = "idle_b",
        blendInSpeed = 8.0, 
        blendOutSpeed = 8.0, 
        duration = -1, 
        flag = 1, 
        playBackRate = 0, 
    },
}

-----------------------------------------------------------
--[[ Notification Functions  ]]--
-----------------------------------------------------------

-- @param source is always null when called from client.
function SendNotification(source, message, notifyType, duration)

    if duration == nil then 
        duration = 5 -- notify stays 5 seconds by default.
    end

    -- @param search : The icon name to be used on the TP Notify.
    if not source then
        TriggerEvent(GetCurrentResourceName() .. ':notify', message, duration * 1000)
    else
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', source, message, duration * 1000)
    end
  
end

-----------------------------------------------------------
--[[ Webhooking (Only DevTools - Injection Cheat Logs) ]]--
-----------------------------------------------------------
-- Discord webhooks are not used in the JRS edition.
Config.Webhooks = {
    
    ['DEVTOOLS_INJECTION_CHEAT'] = { -- Warnings and Logs about players who used or atleast tried to use devtools injection.
        Enabled = false, 
        Color = 10038562,
    },

}


