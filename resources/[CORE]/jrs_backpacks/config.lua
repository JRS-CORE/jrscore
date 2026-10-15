-- ==========================================================================
--  JRS CORE  |  jrs_backpacks  |  config.lua
--  backpacks - wearable backpacks, each with its own storage
-- ==========================================================================

Config = {}

Config.Language        = 'en'   -- 'en' or 'ar'
Config.OneBackpackOnly = true   -- carrying two backpacks blocks opening them
Config.UseCooldown     = 2      -- seconds between two opens
Config.WearCheck       = 10     -- seconds: the prop on your back follows what you carry

-- item = inventory item, slots = storage size, model/position/rotation = the prop on the back
Config.Backpacks = {
    { item = 'backpack_simple',  slots = 20,  model = 'p_ambpack05x',             position = vector3(-0.5, 0.0, 0.08),   rotation = vector3(-80.0, 0.0, -90.0) },
    { item = 'backpack_ammo',    slots = 20,  model = 'p_cs_baglevin01x',         position = vector3(0.13, -0.20, -0.05), rotation = vector3(0.0, 70.0, 0.0) },
    { item = 'backpack_trapper', slots = 30,  model = 'p_trapperbackpack01x',     position = vector3(0.0, 0.0, 0.0),     rotation = vector3(0.0, -20.0, 90.0) },
    { item = 'backpack_fish',    slots = 30,  model = 'p_fishcolectorsatchel01x', position = vector3(0.5, 0.3, 0.5),     rotation = vector3(0.0, 90.0, 0.0) },
    { item = 'backpack_nat',     slots = 40,  model = 'p_ambpack01x',             position = vector3(-0.5, 0.0, 0.08),   rotation = vector3(-80.0, 0.0, -90.0) },
    { item = 'backpack_normal',  slots = 50,  model = 'p_ambpack02x',             position = vector3(-0.35, 0.0, 0.08),  rotation = vector3(-80.0, 0.0, -90.0) },
    { item = 'backpack_big',     slots = 80,  model = 'p_ambpack04x',             position = vector3(-0.2, -0.10, 0.0),  rotation = vector3(0.0, -20.0, -90.0) },
}

Config.ByItem = {}
for _, b in ipairs(Config.Backpacks) do Config.ByItem[b.item] = b end
