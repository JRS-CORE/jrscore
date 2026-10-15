-- ==========================================================================
--  JRS CORE  |  jrs_radius  |  config.lua
--  Player culling radius: the fewer players around you, the further you see them.
-- ==========================================================================

Config = {}

Config.MaxRadius     = 350.0   -- radius in a quiet area (nobody around)
Config.MinRadius     = 120.0   -- radius in a crowded area
Config.CrowdRadius   = 250.0   -- a player counts as "around" when closer than this
Config.CrowdedAt     = 28      -- this many players around = MinRadius
Config.RefreshSecond = 20      -- seconds between recalculations
