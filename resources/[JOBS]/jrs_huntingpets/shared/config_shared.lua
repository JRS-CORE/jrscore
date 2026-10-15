-- ==========================================================================
--  JRS CORE  |  jrs_huntingpets  |  shared/config_shared.lua
--  hunting pets - hunting dogs and birds with training, tracking and scavenging
-- ==========================================================================

Config = Config or {}

Config.Language = 'en'          -- 'en' or 'ar'

-- Load the the JRS kit locale for this resource (server picks the language via the
-- 'ox:locale' convar, e.g. `setr ox:locale "de"` in server.cfg; defaults to 'en').
-- Must run before any L() calls below/in the other shared config files.
---------------------------------
-- General Settings
---------------------------------
Config.Debug = false
Config.FadeIn = true
Config.DistanceSpawn = 20.0
Config.AnimalFood = 'raw_meat'          -- Food item for both dogs and birds

---------------------------------
-- Opening Hours
---------------------------------
Config.AlwaysOpen = true               -- if false, configure open/close times
Config.OpenTime = 8                     -- store opens
Config.CloseTime = 20                   -- store closes

---------------------------------
-- Blip Settings
---------------------------------
Config.Blip = {
    blipName = 'Hunting Pets',
    blipSprite = -699499938,
    blipScale = 0.6,
}

---------------------------------
-- Shop Locations
---------------------------------
Config.Shops = {
    {
        prompt = 'valentine-jrs_huntingpets',
        Name = 'Hunting Pets',
        Ring = true,
        ActiveDistance = 1.5,
        Coords = vector3(-282.77, 673.02, 113.53),
        Spawndog = vector4(-285.44, 675.36, 113.53, 111.79),
        npcmodel = `mbh_rhodesrancher_females_01`,
        npccoords = vector4(-282.77, 673.02, 113.53, 111.79),
        scenario = 'MP_LOBBY_STANDING_D',
        showblip = true,
        -- Bird shop display position
        birdstandpos = {x = -283.97, y = 666.14, z = 113.44, h = 29.13},
    },
    {
        prompt = 'blackwater-jrs_huntingpets',
        Name = 'Hunting Pets',
        Ring = true,
        ActiveDistance = 1.5,
        Coords = vector3(-945.7324, -1226.065, 52.751701),
        Spawndog = vector4(-947.0184, -1225.372, 52.836936, 192.60287),
        npcmodel = `u_m_m_bwmstablehand_01`,
        npccoords = vector4(-945.7324, -1226.065, 52.751701, 185.14344),
        scenario = 'MP_LOBBY_STANDING_C',
        showblip = true,
        birdstandpos = {x = -946.50, y = -1227.50, z = 52.75, h = 180.0},
    },
}

---------------------------------
-- Checkpoint Colours
---------------------------------
Config.Checkpoints = {
    shop = {128, 200, 0},
}
