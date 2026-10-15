-- ==========================================================================
--  JRS CORE  |  jrs_smelting  |  config.lua
--  smelting - turn ore from jrs_mining into bars at smelters
-- ==========================================================================

Config = {}

Config.Language      = 'en'     -- 'en' or 'ar'
Config.SpawnDistance = 50.0     -- smelter NPC appears inside this radius
Config.UseDistance   = 2.5      -- prompt radius
Config.MaxBatch      = 20       -- bars per smelt
Config.Job           = nil      -- e.g. 'blacksmith' to lock smelting to one job (nil = everyone)

-- add more: { label, model, coords = vector4(x, y, z, heading), scenario, blip }
Config.Smelters = {
    { label = 'Valentine Smelter',  model = 'a_m_m_asbminer_01', coords = vector4(499.53, 678.62, 117.44, 114.44),  scenario = 'WORLD_HUMAN_SMOKE', blip = true },
}
Config.BlipSprite = 'blip_shop_blacksmith'

-- Uses the items jrs_mining gives. time = ms per bar.
Config.Recipes = {
    { output = 'goldbar',   time = 10000, inputs = { { item = 'coal', amount = 1 }, { item = 'goldnugget', amount = 5 } } },
    { output = 'ironbar',   time = 8000,  inputs = { { item = 'coal', amount = 1 }, { item = 'iron',       amount = 3 } } },
    { output = 'copperbar', time = 8000,  inputs = { { item = 'coal', amount = 1 }, { item = 'copper',     amount = 3 } } },
    { output = 'silverbar', time = 9000,  inputs = { { item = 'coal', amount = 1 }, { item = 'silver',     amount = 3 } } },
    { output = 'steelbar',  time = 12000, inputs = { { item = 'coal', amount = 2 }, { item = 'iron',       amount = 2 }, { item = 'sulfur', amount = 1 } } },
}
