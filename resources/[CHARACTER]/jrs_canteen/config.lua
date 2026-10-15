-- ==========================================================================
--  JRS CORE  |  jrs_canteen  |  config.lua
--  canteen - drink and refill at rivers and lakes
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'

-- Thirst uses the jrs_metabolism scale (0 - 1000)
Config.DrinkThirst  = 250       -- thirst gained per sip
Config.RefillThirst = 1000      -- thirst set to full when drinking straight from fresh water
Config.DrinkTime    = 5000      -- ms the drinking animation lasts
Config.RefillTime   = 8000      -- ms kneeling at the water to refill

-- every canteen item (all usable)
Config.CanteenItems = { 'canteen100', 'canteen75', 'canteen50', 'canteen25', 'canteen0' }

-- canteen item -> what it becomes after one sip (missing = empty, cannot drink)
Config.Canteens = {
    canteen100 = 'canteen75',
    canteen75  = 'canteen50',
    canteen50  = 'canteen25',
    canteen25  = 'canteen0',
}
Config.FullCanteen  = 'canteen100'
Config.EmptyCanteen = 'canteen0'

-- Fresh water you can refill from (salt water is excluded on purpose)
Config.FreshWater = {
    [-1504425495] = 'San Luis River',
    [-1369817450] = 'Lake Don Julio',
    [-1356490953] = 'Flat Iron Lake',
    [-1781130443] = 'Upper Montana River',
    [-1300497193] = 'Owanjila',
    [-1276586360] = 'HawkEye Creek',
    [-1410384421] = 'Little Creek River',
    [370072007]   = 'Dakota River',
    [650214731]   = 'Beartooth Beck',
    [592454541]   = 'Lake Isabella',
    [-804804953]  = 'Cattail Pond',
    [1245451421]  = 'Deadboot Creek',
    [-218679770]  = 'Spider Gorge',
    [-1817904483] = "O'Creagh's Run",
    [-811730579]  = 'Moonstone Pond',
    [-1229593481] = 'Roanoke Valley',
    [-105598602]  = 'Elysian Pool',
    [-2040708515] = 'Lannahechee River',
    [231313522]   = 'Creek',
    [2005774838]  = 'Creek',
    [-1287619521] = 'Creek',
    [-1308233316] = 'Creek',
    [-196675805]  = 'Creek',
    [-49694339]   = 'Arroyo De La Vibora',
}
