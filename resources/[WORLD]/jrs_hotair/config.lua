-- ==========================================================================
--  JRS CORE  |  jrs_hotair  |  config.lua
--  hot air balloons - hire, fly and carry passengers
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'

-- Balloon vehicle model
Config.Model = 'hotAirBalloon01'

-- Flat hire fee (cash). No timers, no cooldowns, no fuel.
Config.HirePrice = 50

-- Balloon basket seats (offsets relative to the balloon entity)
-- pilot uses the driver seat (-1), passengers attach at these offsets
Config.PassengerOffsets = {
    vector3(0.5, 0.5, 1.1),   -- front-right
    vector3(-0.5, 0.5, 1.1),  -- front-left
    vector3(0.5, -0.5, 1.1),  -- back-right
    vector3(-0.5, -0.5, 1.1), -- back-left
}

-- Flight tuning (momentum drift, applied per tick while input held)
Config.CruiseSpeed = 0.05  -- drift added per tick
Config.BoostSpeed  = 0.15  -- drift added per tick while boost held
Config.MaxAltitudeAGL = 150.0 -- ceiling above ground level

-- Store / board limits
Config.StoreMaxSpeed     = 3.0 -- m/s, balloon must be near-stationary to store
Config.StoreMaxHeightAGL = 4.0 -- must be close to the ground to store
Config.BoardMaxSpeed     = 3.0 -- same limits for boarding / piloting
Config.BoardMaxHeightAGL = 4.0
Config.TargetDistance    = 6.0 -- prompt distance (balloon is a large entity)

-- Balloon storage (JRS storage per character, slots)
Config.StorageMaxWeight = 100000
Config.StorageMaxSlots  = 20

-- Add as many docks as you like, one NPC + blip + target is
-- created per entry automatically. Ground Z is resolved at runtime.
Config.Docks = {
    {
        label = 'Valentine Meadow',
        npcModel = 'A_M_M_RANCHER_01',
        npcCoords = vector4(-151.93, 669.44, 115.37, 187.32),
        spawnCoords = vector3(-148.78, 664.59, 115.26),
        spawnHeading = 45.0,
        blip = { sprite = -1258576797, scale = 0.2, name = 'Balloon Hire' },
    },
    
}
