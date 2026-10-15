-- ==========================================================================
--  JRS CORE  |  jrs_npcs  |  config.lua
--  ambient NPCs - place townsfolk with scenarios, blips and optional voice lines
-- ==========================================================================

Config = {}

Config.SpawnDistance = 40.0     -- NPC appears inside this radius, disappears outside it
Config.FadeIn        = true

--[[ One entry per NPC:
    model       = 's_m_m_barber_01',
    coords      = vector4(x, y, z, heading),
    scenario    = 'WORLD_HUMAN_WRITE_NOTEBOOK',   -- optional
    blip        = { name = 'Barber', sprite = 'blip_shop_barber', scale = 0.2 },   -- optional
    audio       = { url = 'nui://my_sounds/hello.ogg', distance = 4.0, volume = 0.6 }, -- optional, needs xsound
]]
Config.Peds = {
    -- {
    --     model    = 's_m_m_barber_01',
    --     coords   = vector4(-307.96, 814.16, 118.99, 190.93),
    --     scenario = 'WORLD_HUMAN_WRITE_NOTEBOOK',
    --     blip     = { name = 'Barber Valentine', sprite = 'blip_shop_barber', scale = 0.2 },
    -- },
}
