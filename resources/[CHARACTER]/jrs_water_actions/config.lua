-- ==========================================================================
--  JRS CORE  |  jrs_water_actions  |  config.lua
--  water actions - wash and drink in rivers and lakes
-- ==========================================================================

Config = {}

Config.Language   = 'en'          -- 'en' or 'ar'
Config.WashKey    = 0x760A9C6F    -- G (hold)
Config.DrinkKey   = 0xC7B5340A    -- ENTER (hold)
Config.Thirst     = 150           -- jrs_metabolism thirst gained per drink (0 - 1000)
Config.DrinkTime  = 8000
Config.WashTime   = 7000
Config.ToggleCommand = 'toggleriver'  -- hide / show the river prompts

-- Swamp water is dirty: chance to get sick when drinking it
Config.SwampSickChance = 60
Config.SwampDamage     = 40

Config.WaterTypes = {
    [-247856387]  = 'lake',  [-1504425495] = 'river', [-1369817450] = 'lake',  [-1356490953] = 'lake',
    [-1781130443] = 'river', [-1300497193] = 'river', [-1276586360] = 'river', [-1410384421] = 'river',
    [370072007]   = 'river', [650214731]   = 'river', [592454541]   = 'lake',  [-804804953]  = 'lake',
    [1245451421]  = 'river', [-218679770]  = 'river', [-1817904483] = 'lake',  [-811730579]  = 'lake',
    [-1229593481] = 'river', [-105598602]  = 'lake',  [1755369577]  = 'swamp', [-557290573]  = 'swamp',
    [-2040708515] = 'river', [231313522]   = 'river', [2005774838]  = 'river', [-1287619521] = 'river',
    [-1308233316] = 'river', [-196675805]  = 'river',
}
