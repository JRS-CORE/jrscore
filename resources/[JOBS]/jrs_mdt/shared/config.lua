-- ==========================================================================
--  JRS CORE  |  jrs_mdt  |  shared/config.lua
--  MDT - records, warrants, reports, charges and fines for the law
-- ==========================================================================

-- JRS MDT Configuration
Config = Config or {}

Config.Language = 'en'          -- 'en' or 'ar' (locales/*.json)

-- ============================================
-- Law Enforcement Jobs
-- Jobs that can access the MDT system
-- ============================================
-- Same job names as jrs_police (configs/config.lua -> Config.PoliceJobs)
Config.LawJobs = {
    ['Police'] = {
        label = 'Police Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['Valentine'] = {
        label = 'Valentine Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['Strawberry'] = {
        label = 'Strawberry Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['Blackwater'] = {
        label = 'Blackwater Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['Rhodes'] = {
        label = 'Rhodes Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['SaintDenis'] = {
        label = 'SaintDenis Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['Tumbleweed'] = {
        label = 'Tumbleweed Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['Annesburg'] = {
        label = 'Annesburg Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
    ['Armadillo'] = {
        label = 'Armadillo Law',
        grades = {
            [0] = { label = 'Deputy',   canCreateRecords = true, canDeleteRecords = false, canManageWarrants = true },
            [1] = { label = 'Sheriff',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
            [2] = { label = 'Marshal',  canCreateRecords = true, canDeleteRecords = true,  canManageWarrants = true, isAdmin = true },
        }
    },
}

-- ============================================
-- MDT Settings
-- ============================================
Config.Settings = {
    command = 'mdt',
    keybind = nil,
    requireOnDuty = false,       -- jrs_police handles duty itself
    maxSearchResults = 50,
    recordRetentionDays = 0,
    warrantExpirationDays = 0,
    debug = false
}

-- ============================================
-- Report Incident Types
-- Add or remove types based on server needs
-- label: Display name shown in UI
-- value: Stored in database (use lowercase, no spaces)
-- color: Tailwind classes for badge styling
-- ============================================
Config.IncidentTypes = {
    { value = 'incident', label = 'Incident', color = 'bg-red-950/50 text-red-400 border-red-900' },
    { value = 'arrest', label = 'Arrest', color = 'bg-orange-950/50 text-orange-400 border-orange-900' },
    { value = 'investigation', label = 'Investigation', color = 'bg-blue-950/50 text-blue-400 border-blue-900' },
    { value = 'traffic', label = 'Traffic', color = 'bg-green-950/50 text-green-400 border-green-900' },
    { value = 'witness', label = 'Witness Statement', color = 'bg-purple-950/50 text-purple-400 border-purple-900' },
    { value = 'evidence', label = 'Evidence Log', color = 'bg-cyan-950/50 text-cyan-400 border-cyan-900' },
}

-- ============================================
-- Default Values
-- ============================================
Config.Defaults = {
    jobGrade = {
        label = 'Unknown',
        canCreateRecords = false,
        canDeleteRecords = false,
        canManageWarrants = false,
        isAdmin = false
    }
}

-- ============================================
-- Fines System
-- ============================================
Config.Fines = {
    enabled = true,
    gracePeriodDays = 7,
    paymentLocations = {
        { name = 'Valentine Sheriff', coords = vector3(-277.44, 801.34, 119.37), heading = 189.50 },
        { name = 'Rhodes Sheriff', coords = vector3(1359.42, -1310.35, 76.93), heading = 167.26 },
        { name = 'Blackwater Sheriff', coords = vector3(-756.42, -1272.22, 44.03), heading = 270.23 },
        { name = 'Saint Denis Police', coords = vector3(2492.52, -1313.66, 48.87), heading = 101.96 },
        { name = 'Strawberry Sheriff', coords = vector3(-1805.19, -348.85, 164.20), heading = 255.00 },
    }
}

Config.Jail = {
    enabled = true,
    delaySeconds = 5,
    maxDistance = 10.0,
    jailCoords = vector3(2761.44, -1460.54, 46.54),
    jailHeading = 90.0,
    minutesPerMonth = 1
}
