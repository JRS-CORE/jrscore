-- ==========================================================================
--  JRS CORE  |  jrs_city  |  config/config.lua
--  jrs core native zone notifications for jrs_core
-- ==========================================================================

Config = {}

Config.CoreResource = 'jrs_core'
Config.Debug = false

-- Detection mirrors RedM's own zone hierarchy. The UI is shown only when
-- the resolved location actually changes.
Config.Detection = {
    Interval = 500,
    WaitForCharacter = true,
    CharacterReadyTimeout = 10000,
    NotifyOnInitialDetection = true,
    PauseWhenDead = true,
    PauseWhenPauseMenuOpen = true,

    -- Highest priority first.
    Priority = {
        1,  -- TOWN
        11, -- TEXT_PRINTED
        12, -- TEXT_WRITTEN
        2,  -- LAKE
        3,  -- RIVER
        5,  -- SWAMP
        6,  -- OCEAN
        7,  -- CREEK
        8,  -- POND
        9,  -- GLACIER
        10, -- DISTRICT
        0,  -- STATE
    }
}

Config.Notification = {
    Duration = 4000,

    Sound = {
        Enabled = true,
        File = 'assets/zone_open.mp3',
        Volume = 0.35, -- 0.0 to 1.0
    },

    UI = {
        Enabled = true,
        Top = '1.8vh',
        -- The supplied background is 432x100. It is intentionally rendered
        -- smaller than its native size.
        Width = '340px',
        MaxWidth = '82vw',
        FadeInMs = 180,
        FadeOutMs = 260,
    }
}

Config.Details = {
    ShowDistrict = true,
    ShowState = true,
    ShowDay = false,
    ShowTime = true,
    ShowTemperature = true,
    ShowWind = true,

    Use24Hour = false,
    TemperatureUnit = 'C', -- 'C' or 'F'
    WindUnit = 'auto',     -- 'auto', 'kph', or 'mph'
}

Config.Days = {
    [0] = 'SUN',
    [1] = 'MON',
    [2] = 'TUE',
    [3] = 'WED',
    [4] = 'THU',
    [5] = 'FRI',
    [6] = 'SAT',
}

-- Add a native zone hash here to disable it without editing the large zone table.
Config.DisabledZoneHashes = {
    -- [123456789] = true,
}

-- Override any zone's display name by native hash.
Config.NameOverrides = {
    -- [459833523] = 'Valentine',
}

-- Extra custom native entries can be added here.
Config.CustomNativeZones = {
    -- [123456789] = { ZoneName = 'My Location', ZoneTypeId = 11, ZoneTypeName = 'TEXT_PRINTED' },
}
