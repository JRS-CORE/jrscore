-- ==========================================================================
--  JRS CORE  |  jrs_railroad  |  shared/config.lua
--  railroad - buy and run trains, companies, cargo, passengers and tickets
-- ==========================================================================

-- Loads locales/<lang>.json (falls back to en.json) and exposes the
-- global L(key, ...) function used throughout this resource.
Config = {}


Config.Language = 'en'          -- 'en' or 'ar'
---------------------------------------------------------------
-- GENERAL SETTINGS
---------------------------------------------------------------
Config.Debug = false

Config.AutoInstallDatabase = true        -- automatically creates/verifies all required MySQL tables on resource start (from install/railroad.sql). Set to false if you prefer to import the .sql file yourself.

Config.MaxTrainsPerCompany = 5           -- max trains a company can own
Config.MaxTrainsPerPlayer = 5            -- max trains a single player can personally own (bug fix: was referenced but never defined)
Config.SellBackPercent = 0.60            -- 60% of purchase price on resale
Config.TrainDespawnDist = 250            -- despawn if player is far from their train
Config.StationInteractRadius = 3.0       -- how close to station marker to interact
Config.HUDKeybind = 0x760A9C6F          -- G key (hold) to open HUD while driving
Config.NotifyRadius = 20.0
Config.TicketItem = 'trainticket'
Config.TicketPrice = 20.00
Config.MarkupPrice = 25.00

---------------------------------------------------------------
-- DISCORD WEBHOOK LOGGING
-- Each category can point at a different Discord webhook URL (or share
-- the same one). Leave a URL blank ('') to disable that category.
---------------------------------------------------------------
Config.Webhooks = {
    Enabled     = true,
    BotName     = 'JRS Railroad',
    BotAvatar   = '', -- optional image URL shown as the webhook's avatar

    -- Per-category webhook URLs. Paste your Discord webhook URLs below.
    URLs = {
        economy   = '', -- train/company purchases, sales, withdrawals, upgrades, mission payouts
        robbery   = '', -- train robbery outcomes
        employees = '', -- driver applications, approvals, rejections, firings, rank-ups
        admin     = '', -- fallback / anything not covered above
    },

    -- Embed colors (decimal, not hex -- e.g. 0x2ECC71 = 3066993)
    Colors = {
        success = 3066993,  -- green
        error   = 15158332, -- red
        info    = 3447003,  -- blue
        warn    = 15105570, -- orange
    },

    -- Mission completions fire very frequently -- off by default so the
    -- economy channel isn't flooded. Turn on if you want every delivery
    -- / maintenance job logged too.
    LogMissionCompletions = false,
}

---------------------------------------------------------------
-- CONTINUOUS PASSENGER SYSTEM
---------------------------------------------------------------
Config.PassengerSystem = {
    Enabled           = true,
    MaxBoardPerStop   = 10,
    MinBoardPerStop   = 1,
    SearchRadius      = 120.0,
    TicketPrice       = 15.0,
    TicketXP          = 5,
    DisembarkChance   = 50,
    MinBoardedToKeep  = 1,
    BoardingWindowMs  = 38000,
    BoardWalkSpeed    = 5.0,      -- walk speed to train
    BoardDistance     = 5.0,      -- within this distance (m) counts as boarded
    StationStopRadius = 135.0,
    TrainStopSpeed    = 1.5,
    CompanyShare      = 0.50,
}

---------------------------------------------------------------
-- RANKS (Brakeman -> Foreman)
---------------------------------------------------------------
Config.Ranks = {
    [1] = { label = 'Brakeman',  xpRequired = 0,    payMultiplier = 1.0 },
    [2] = { label = 'Fireman',   xpRequired = 100,  payMultiplier = 1.1 },
    [3] = { label = 'Engineer',  xpRequired = 250,  payMultiplier = 1.25 },
    [4] = { label = 'Conductor', xpRequired = 500,  payMultiplier = 1.5 },
    [5] = { label = 'Foreman',   xpRequired = 1000, payMultiplier = 2.0 },
}

---------------------------------------------------------------
-- V2: COMPANY OWNERSHIP
---------------------------------------------------------------
Config.CompanyPurchasePrice = 50000
Config.CompanySellPercent = 0.50
Config.MissionPaySplit = {
    driver = 0.50,
    company = 0.50,
}

Config.SupplyItems = {
    { item = 'coal',       label = 'Coal',         icon = 'fire' },
    { item = 'rocker_bucket_full',          label = 'Bucket of Water',  icon = 'tint' },
    { item = 'oilcan',              label = 'Can of Oil',   icon = 'wrench' },
}

---------------------------------------------------------------
-- FUEL / WATER / CONDITION
---------------------------------------------------------------
Config.Fuel = {
    item = 'coal',
    itemLabel = 'Coal',
    refuelAmount = 2,
    decreaseInterval = 20000,
    decreaseAmount = 1,
}

Config.Water = {
    item = 'rocker_bucket_full',
    itemLabel = 'Bucket of Water',
    refillAmount = 50,
    decreaseInterval = 45000,
    decreaseAmount = 1,
}

Config.Condition = {
    item = 'oilcan',
    itemLabel = 'Oil Can',
    repairAmount = 50,
    decreaseInterval = 60000,
    decreaseAmount = 1,
    lowConditionSpeedCap = 0.25,
}

---------------------------------------------------------------
-- COMPANIES
---------------------------------------------------------------
Config.Companies = {
    ['lemoyne_central'] = {
        label = 'Lemoyne Central Railroad',
        shortLabel = 'LCR',
        blipColor = 'BLIP_MODIFIER_MP_COLOR_1',
        description = 'Premier freight and passenger service across Lemoyne.',
    },
    ['heartlands_express'] = {
        label = 'Heartlands Express',
        shortLabel = 'HEX',
        blipColor = 'BLIP_MODIFIER_MP_COLOR_6',
        description = 'Fast service through the Heartlands and beyond.',
    },
    ['cumberland_western'] = {
        label = 'Cumberland & Western',
        shortLabel = 'C&W',
        blipColor = 'BLIP_MODIFIER_MP_COLOR_8',
        description = 'Rugged mountain railway through the Cumberland Forest.',
    },
    ['new_austin_rail'] = {
        label = 'New Austin Rail Co.',
        shortLabel = 'NAR',
        blipColor = 'BLIP_MODIFIER_MP_COLOR_11',
        description = 'Desert rail connecting the frontier towns of New Austin.',
    },
    {
        trainname = 'City Tram',
        trainid = 'train3',
        trainhash = -1083616881,
        startcoords = vector3(2608.539, -1171.967, 53.77959),
        route = 'tramRouteOne',
    },
}

---------------------------------------------------------------
-- UPGRADES
---------------------------------------------------------------
Config.Upgrades = {
    speed = {
        [1] = { label = 'Bronze Speed',      cost = 150,  itemCost = { item = 'ironbar',  amount = 5 },  bonus = 2  },
        [2] = { label = 'Silver Speed',      cost = 400,  itemCost = { item = 'steelbar', amount = 5 },  bonus = 4  },
        [3] = { label = 'Gold Speed',        cost = 800,  itemCost = { item = 'goldbar',  amount = 3 },  bonus = 6  },
    },
    fuel_cap = {
        [1] = { label = 'Bronze Fuel',       cost = 100,  itemCost = { item = 'ironbar',  amount = 3 },  bonus = 25 },
        [2] = { label = 'Silver Fuel',       cost = 300,  itemCost = { item = 'steelbar', amount = 3 },  bonus = 50 },
        [3] = { label = 'Gold Fuel',         cost = 600,  itemCost = { item = 'goldbar',  amount = 2 },  bonus = 75 },
    },
    water_cap = {
        [1] = { label = 'Bronze Water',      cost = 100,  itemCost = { item = 'ironbar',  amount = 3 },  bonus = 25 },
        [2] = { label = 'Silver Water',      cost = 300,  itemCost = { item = 'steelbar', amount = 3 },  bonus = 50 },
        [3] = { label = 'Gold Water',        cost = 600,  itemCost = { item = 'goldbar',  amount = 2 },  bonus = 75 },
    },
    durability = {
        [1] = { label = 'Bronze Durability', cost = 120,  itemCost = { item = 'ironbar',  amount = 4 },  bonus = 10 },
        [2] = { label = 'Silver Durability', cost = 350,  itemCost = { item = 'steelbar', amount = 4 },  bonus = 25 },
        [3] = { label = 'Gold Durability',   cost = 700,  itemCost = { item = 'goldbar',  amount = 2 },  bonus = 40 },
    },
}

---------------------------------------------------------------
-- TRAINS
---------------------------------------------------------------
Config.Trains = {
    -- LEMOYNE CENTRAL RAILROAD
    { model = 'appleseed_config',        label = 'Appleseed Freight',      company = 'lemoyne_central', cost = 200,  sellPrice = 120, maxFuel = 100, maxWater = 100, maxCondition = 100, maxSpeed = 20, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'engine_config',           label = 'Standard Engine',        company = 'lemoyne_central', cost = 350,  sellPrice = 210, maxFuel = 120, maxWater = 110, maxCondition = 100, maxSpeed = 22, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'gunslinger3_config',      label = 'Gunslinger MkIII',       company = 'lemoyne_central', cost = 500,  sellPrice = 300, maxFuel = 130, maxWater = 120, maxCondition = 110, maxSpeed = 24, requiredRank = 2, upgradeable = true,  hasPassengerCars = false },
    { model = 'gunslinger4_config',      label = 'Gunslinger MkIV',        company = 'lemoyne_central', cost = 700,  sellPrice = 420, maxFuel = 140, maxWater = 130, maxCondition = 120, maxSpeed = 26, requiredRank = 3, upgradeable = true,  hasPassengerCars = true  },
    { model = 'prisoner_escort_config',  label = 'Lemoyne Prisoner Car',   company = 'lemoyne_central', cost = 900,  sellPrice = 540, maxFuel = 150, maxWater = 140, maxCondition = 130, maxSpeed = 18, requiredRank = 4, upgradeable = true,  hasPassengerCars = true  },
    { model = 'bountyhunter_config',     label = 'Lemoyne Bounty Express', company = 'lemoyne_central', cost = 1100, sellPrice = 660, maxFuel = 160, maxWater = 150, maxCondition = 140, maxSpeed = 28, requiredRank = 4, upgradeable = true,  hasPassengerCars = false },
    { model = 'winter4_config',          label = 'Lemoyne Winter Special', company = 'lemoyne_central', cost = 1500, sellPrice = 900, maxFuel = 180, maxWater = 170, maxCondition = 150, maxSpeed = 30, requiredRank = 5, upgradeable = true,  hasPassengerCars = true  },
 --{ model = 'handcart_config',          label = 'Lemoyne Handcart',       company = 'lemoyne_central', cost = 100,  sellPrice = 60,  maxFuel = 50,  maxWater = 50,  maxCondition = 80,  maxSpeed = 10, requiredRank = 1, upgradeable = false, hasPassengerCars = false },
 --{ model = 'trolley_config',           label = 'Lemoyne Trolley',        company = 'lemoyne_central', cost = 150,  sellPrice = 90,  maxFuel = 60,  maxWater = 60,  maxCondition = 80,  maxSpeed = 8,  requiredRank = 1, upgradeable = false, hasPassengerCars = false },

    -- HEARTLANDS EXPRESS
    { model = 'appleseed_config',        label = 'Heartland Hauler',       company = 'heartlands_express', cost = 200,  sellPrice = 120, maxFuel = 100, maxWater = 100, maxCondition = 100, maxSpeed = 20, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'engine_config',           label = 'Express Engine',         company = 'heartlands_express', cost = 350,  sellPrice = 210, maxFuel = 120, maxWater = 110, maxCondition = 100, maxSpeed = 22, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'bountyhunter_config',     label = 'Heartland Bounty',       company = 'heartlands_express', cost = 500,  sellPrice = 300, maxFuel = 130, maxWater = 120, maxCondition = 110, maxSpeed = 24, requiredRank = 2, upgradeable = true,  hasPassengerCars = false },
    { model = 'gunslinger3_config',      label = 'Heartland Fast',         company = 'heartlands_express', cost = 700,  sellPrice = 420, maxFuel = 140, maxWater = 130, maxCondition = 120, maxSpeed = 26, requiredRank = 3, upgradeable = true,  hasPassengerCars = true  },
    { model = 'gunslinger4_config',      label = 'Heartland Premium',      company = 'heartlands_express', cost = 900,  sellPrice = 540, maxFuel = 150, maxWater = 140, maxCondition = 130, maxSpeed = 28, requiredRank = 4, upgradeable = true,  hasPassengerCars = false },
    { model = 'winter4_config',          label = 'Heartland Blizzard',     company = 'heartlands_express', cost = 1500, sellPrice = 900, maxFuel = 180, maxWater = 170, maxCondition = 150, maxSpeed = 30, requiredRank = 5, upgradeable = true,  hasPassengerCars = true  },
    { model = 'prisoner_escort_config',  label = 'Heartland Transport',    company = 'heartlands_express', cost = 800,  sellPrice = 480, maxFuel = 140, maxWater = 130, maxCondition = 120, maxSpeed = 18, requiredRank = 3, upgradeable = true,  hasPassengerCars = true  },
 --{ model = 'handcart_config',          label = 'Heartland Handcart',     company = 'heartlands_express', cost = 100,  sellPrice = 60,  maxFuel = 50,  maxWater = 50,  maxCondition = 80,  maxSpeed = 10, requiredRank = 1, upgradeable = false, hasPassengerCars = false },
 --{ model = 'trolley_config',           label = 'Heartland Trolley',      company = 'heartlands_express', cost = 150,  sellPrice = 90,  maxFuel = 60,  maxWater = 60,  maxCondition = 80,  maxSpeed = 8,  requiredRank = 1, upgradeable = false, hasPassengerCars = false },

    -- CUMBERLAND & WESTERN
    { model = 'engine_config',           label = 'Mountain Engine',        company = 'cumberland_western', cost = 250,  sellPrice = 150, maxFuel = 110, maxWater = 110, maxCondition = 110, maxSpeed = 18, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'appleseed_config',        label = 'Cumberland Freight',     company = 'cumberland_western', cost = 400,  sellPrice = 240, maxFuel = 130, maxWater = 120, maxCondition = 120, maxSpeed = 20, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'handcart_config',         label = 'Mountain Handcart',      company = 'cumberland_western', cost = 100,  sellPrice = 60,  maxFuel = 50,  maxWater = 50,  maxCondition = 80,  maxSpeed = 10, requiredRank = 1, upgradeable = false, hasPassengerCars = false },
    { model = 'gunslinger3_config',      label = 'Cumberland Workhorse',   company = 'cumberland_western', cost = 600,  sellPrice = 360, maxFuel = 140, maxWater = 130, maxCondition = 130, maxSpeed = 22, requiredRank = 2, upgradeable = true,  hasPassengerCars = true  },
    { model = 'bountyhunter_config',     label = 'Cumberland Pursuit',     company = 'cumberland_western', cost = 800,  sellPrice = 480, maxFuel = 150, maxWater = 140, maxCondition = 140, maxSpeed = 24, requiredRank = 3, upgradeable = true,  hasPassengerCars = true  },
    { model = 'prisoner_escort_config',  label = 'Mountain Prison Car',    company = 'cumberland_western', cost = 1000, sellPrice = 600, maxFuel = 160, maxWater = 150, maxCondition = 150, maxSpeed = 16, requiredRank = 4, upgradeable = true,  hasPassengerCars = false },
    { model = 'winter4_config',          label = 'Cumberland Ice Runner',  company = 'cumberland_western', cost = 1400, sellPrice = 840, maxFuel = 170, maxWater = 160, maxCondition = 160, maxSpeed = 28, requiredRank = 5, upgradeable = true,  hasPassengerCars = true  },
    { model = 'gunslinger4_config',      label = 'Cumberland Premium',     company = 'cumberland_western', cost = 900,  sellPrice = 540, maxFuel = 150, maxWater = 140, maxCondition = 130, maxSpeed = 28, requiredRank = 4, upgradeable = true,  hasPassengerCars = false },
 --{ model = 'trolley_config',           label = 'Cumberland Trolley',     company = 'cumberland_western', cost = 150,  sellPrice = 90,  maxFuel = 60,  maxWater = 60,  maxCondition = 80,  maxSpeed = 8,  requiredRank = 1, upgradeable = false, hasPassengerCars = false },

    -- NEW AUSTIN RAIL CO.
    { model = 'engine_config',           label = 'Desert Engine',          company = 'new_austin_rail', cost = 250,  sellPrice = 150, maxFuel = 110, maxWater = 120, maxCondition = 100, maxSpeed = 20, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'appleseed_config',        label = 'Frontier Hauler',        company = 'new_austin_rail', cost = 400,  sellPrice = 240, maxFuel = 120, maxWater = 130, maxCondition = 110, maxSpeed = 22, requiredRank = 1, upgradeable = true,  hasPassengerCars = false },
    { model = 'handcart_config',         label = 'Desert Handcart',        company = 'new_austin_rail', cost = 100,  sellPrice = 60,  maxFuel = 50,  maxWater = 60,  maxCondition = 80,  maxSpeed = 10, requiredRank = 1, upgradeable = false, hasPassengerCars = false },
    { model = 'gunslinger3_config',      label = 'Austin Gunslinger',      company = 'new_austin_rail', cost = 600,  sellPrice = 360, maxFuel = 140, maxWater = 150, maxCondition = 120, maxSpeed = 24, requiredRank = 2, upgradeable = true,  hasPassengerCars = true  },
    { model = 'gunslinger4_config',      label = 'Austin Desperado',       company = 'new_austin_rail', cost = 800,  sellPrice = 480, maxFuel = 150, maxWater = 160, maxCondition = 130, maxSpeed = 26, requiredRank = 3, upgradeable = true,  hasPassengerCars = false },
    { model = 'bountyhunter_config',     label = 'Austin Bounty Runner',   company = 'new_austin_rail', cost = 1000, sellPrice = 600, maxFuel = 160, maxWater = 170, maxCondition = 140, maxSpeed = 28, requiredRank = 4, upgradeable = true,  hasPassengerCars = true  },
    { model = 'prisoner_escort_config',  label = 'Austin Chain Gang',      company = 'new_austin_rail', cost = 900,  sellPrice = 540, maxFuel = 150, maxWater = 160, maxCondition = 130, maxSpeed = 16, requiredRank = 3, upgradeable = true,  hasPassengerCars = false },
    { model = 'winter4_config',          label = 'Austin Sandstorm',       company = 'new_austin_rail', cost = 1400, sellPrice = 840, maxFuel = 180, maxWater = 180, maxCondition = 150, maxSpeed = 30, requiredRank = 5, upgradeable = true,  hasPassengerCars = false },
 --{ model = 'trolley_config',           label = 'Austin Trolley',         company = 'new_austin_rail', cost = 150,  sellPrice = 90,  maxFuel = 60,  maxWater = 60,  maxCondition = 80,  maxSpeed = 8,  requiredRank = 1, upgradeable = false, hasPassengerCars = false },
}

---------------------------------------------------------------
-- STATIONS
---------------------------------------------------------------
Config.StationBlipHash = 1258184551

Config.Stations = {
    {
        id = 'valentine',
        label = 'Valentine Station',
        company = 'heartlands_express',
        coords = vector3(-176.01, 627.86, 114.09),
        spawnCoords = vector3(-136.13, 659.75, 113.53),
        passengerSpawn = vector3(-168.78, 630.06, 114.03),
        hasWaterTower = true,
        waterTowerCoords = vec3(-157.91, 643.69, 113.44),
        hasMaintenanceDepot = true,
        depotCoords = vec3(-187.52, 597.78, 113.31),
    },
    {
        id = 'emerald',
        label = 'Emerald Station',
        company = 'heartlands_express',
        coords = vector3(1525.18, 442.51, 90.68),
        spawnCoords = vector3(1529.67, 442.54, 90.22),
        passengerSpawn = vector3(1525.18, 442.51, 90.68),
        hasWaterTower = false,
        waterTowerCoords = nil,
        hasMaintenanceDepot = true,
        depotCoords = vec3(1525.61, 450.25, 90.37),
    },
    {
        id = 'flatneck',
        label = 'Flatneck Station',
        company = 'lemoyne_central',
        coords = vector3(-337.13, -360.63, 88.08),
        spawnCoords = vector3(-339.0, -350.0, 87.81),
        passengerSpawn = vector3(-337.13, -360.63, 88.08),
        hasWaterTower = true,
        waterTowerCoords = vec3(-326.04, -340.06, 88.07),
        hasMaintenanceDepot = true,
        depotCoords = vec3(-315.75, -345.55, 87.99),
    },
    {
        id = 'rhodes',
        label = 'Rhodes Station',
        company = 'lemoyne_central',
        coords = vector3(1225.77, -1296.45, 76.9),
        spawnCoords = vector3(1226.74, -1310.03, 76.47),
        passengerSpawn = vector3(1225.77, -1296.45, 76.9),
        hasWaterTower = true,
        waterTowerCoords = vec3(1197.94, -1279.25, 76.44),
        hasMaintenanceDepot = false,
        depotCoords = nil,
    },
    {
        id = 'saintdenis',
        label = 'Saint Denis Station',
        company = 'lemoyne_central',
        coords = vector3(2747.5, -1398.89, 46.18),
        spawnCoords = vector3(2770.08, -1414.51, 45.98),
        passengerSpawn = vector3(2747.5, -1398.89, 46.18),
        hasWaterTower = true,
        waterTowerCoords = vec3(2893.59, -1229.56, 46.00),
        hasMaintenanceDepot = true,
        depotCoords = vec3(2591.20, -1473.83, 46.22),
    },
    {
        id = 'annesburg',
        label = 'Annesburg Station',
        company = 'heartlands_express',
        coords = vector3(2938.98, 1282.05, 44.65),
        spawnCoords = vector3(2957.25, 1281.58, 43.95),
        passengerSpawn = vector3(2938.98, 1282.05, 44.65),
        hasWaterTower = true,
        waterTowerCoords = vec3(2996.20, 1403.39, 44.46),
        hasMaintenanceDepot = true,
        depotCoords = vec3(2957.21, 1299.95, 44.50),
    },
    {
        id = 'bacchus',
        label = 'Bacchus Station',
        company = 'cumberland_western',
        coords = vector3(582.49, 1681.07, 187.79),
        spawnCoords = vector3(581.14, 1691.8, 187.6),
        passengerSpawn = vector3(582.49, 1681.07, 187.79),
        hasWaterTower = false,
        waterTowerCoords = nil,
        hasMaintenanceDepot = true,
        depotCoords = vec3(582.54, 1698.95, 187.48),
    },
    {
        id = 'wallace',
        label = 'Wallace Station',
        company = 'cumberland_western',
        coords = vector3(-1299.39, 402.09, 95.38),
        spawnCoords = vector3(-1307.62, 406.83, 94.98),
        passengerSpawn = vector3(-1299.39, 402.09, 95.38),
        hasWaterTower = true,
        waterTowerCoords = vec3(-1297.08, 421.09, 94.71),
        hasMaintenanceDepot = false,
        depotCoords = nil,
    },
    {
        id = 'riggs',
        label = 'Riggs Station',
        company = 'cumberland_western',
        coords = vector3(-1093.92, -576.97, 82.41),
        spawnCoords = vector3(-1097.07, -583.71, 81.67),
        passengerSpawn = vector3(-1093.92, -576.97, 82.41),
        hasWaterTower = true,
        waterTowerCoords = vec3(-1111.01, -569.48, 82.55),
        hasMaintenanceDepot = false,
        depotCoords = nil,
    },
    {
        id = 'armadillo',
        label = 'Armadillo Station',
        company = 'new_austin_rail',
        coords = vector3(-3729.1, -2602.83, -12.94),
        spawnCoords = vector3(-3748.85, -2600.8, -13.72),
        passengerSpawn = vector3(-3729.1, -2602.83, -12.94),
        hasWaterTower = true,
        waterTowerCoords = vec3(-3741.85, -2622.01, -13.26),
        hasMaintenanceDepot = true,
        depotCoords = vec3(-3746.68, -2561.46, -13.14),
    },
    {
        id = 'benedict',
        label = 'Benedict Point Station',
        company = 'new_austin_rail',
        coords = vector3(-5230.27, -3468.65, -20.58),
        spawnCoords = vector3(-5235.54, -3473.3, -21.25),
        passengerSpawn = vector3(-5230.27, -3468.65, -20.58),
        hasWaterTower = true,
        waterTowerCoords = vector3(-5225.0, -3460.0, -20.5),
        hasMaintenanceDepot = false,
        depotCoords = nil,
    },
}

---------------------------------------------------------------
-- TRACK SWITCHES (per route)
---------------------------------------------------------------
Config.TrackSwitches = {
    route_east = {
        { coords = vector3(-281.13, -319.66, 89.02),  trackHash = -705539859,  junctionIndex = 2,  enabled = 1 },
        { coords = vector3(357.96, 596.37, 115.68),   trackHash = 1499637393,  junctionIndex = 4,  enabled = 0 },
        { coords = vector3(1481.54, 648.33, 92.31),   trackHash = 1499637393,  junctionIndex = 2,  enabled = 1 },
        { coords = vector3(2464.55, -1475.74, 46.15), trackHash = -760570040,  junctionIndex = 5,  enabled = 1 },
        { coords = vector3(2654.03, -1477.15, 45.76), trackHash = -1242669618, junctionIndex = 2,  enabled = 1 },
        { coords = vector3(2659.79, -435.71, 43.39),  trackHash = -705539859,  junctionIndex = 13, enabled = 0 },
    },
    route_south = {
        { coords = vector3(2659.79, -435.71, 43.39),  trackHash = -705539859,  junctionIndex = 13, enabled = 0 },
        { coords = vector3(610.36, 1661.90, 187.39),  trackHash = -705539859,  junctionIndex = 8,  enabled = 1 },
        { coords = vector3(556.65, 1726.0, 187.80),   trackHash = -705539859,  junctionIndex = 7,  enabled = 1 },
        { coords = vector3(-281.13, -319.66, 89.02),  trackHash = -705539859,  junctionIndex = 2,  enabled = 0 },
        { coords = vector3(2588.54, -1482.19, 46.05), trackHash = -705539859,  junctionIndex = 18, enabled = 1 },
        { coords = vector3(2654.03, -1477.15, 45.76), trackHash = -1242669618, junctionIndex = 2,  enabled = 1 },
    },
}

Config.TrainSetup = {
    {
        trainname = 'Orient Express',
        trainid = 'train4',
        trainhash = -2006657222,
        startcoords = vector3(-154.65, 639.79, 113.52),
        route = 'trainRouteOne',
    },
    {
        trainname = 'City Tram',
        trainid = 'train3',
        trainhash = -1083616881,
        startcoords = vector3(2608.539, -1171.967, 53.77959),
        route = 'tramRouteOne',
    },
    {
        trainname = 'New Austin Express',
        trainid = 'train4',
        trainhash = -2006657222,
        startcoords = vector3(-3748.85, -2600.8, -13.72),
        route = 'trainRouteThree',
        reversed = true,
    },
}

Config.RouteOneTrainSwitches = {
    { coords = vector3(-281.1323, -319.6579, 89.02458), trainTrack = -705539859,  junctionIndex = 2,  enabled = 1 },
    { coords = vector3(357.959, 596.374, 115.6759),     trainTrack = 1499637393,  junctionIndex = 4,  enabled = 0 },
    { coords = vector3(1481.54, 648.331, 92.30682),     trainTrack = 1499637393,  junctionIndex = 2,  enabled = 1 },
    { coords = vector3(2464.55, -1475.74, 46.15192),    trainTrack = -760570040,  junctionIndex = 5,  enabled = 1 },
    { coords = vector3(2654.026, -1477.149, 45.75834),  trainTrack = -1242669618, junctionIndex = 2,  enabled = 1 },
    { coords = vector3(2659.79, -435.7114, 43.38848),   trainTrack = -705539859,  junctionIndex = 13, enabled = 0 },
}

Config.RouteOneTrainStops = {
    { dst = 100.0, dst2 = 10.0, coords = vector3(-318.5835, -339.5699, 89.8374),   waittime = 15000, name = "Flatneck Station" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(-154.6459, 639.7926, 113.52259),  waittime = 15000, name = "Valentine Station" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(511.73336, 654.95397, 115.67657), waittime = 15000, name = "Heartland Oil Fields" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(1529.366, 422.21853, 90.355613),  waittime = 15000, name = "Emerald Station" },
    { dst = 400.0, dst2 = 10.0, coords = vector3(2732.3334, -1445.62, 45.773746),  waittime = 15000, name = "Saint Denis Station" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(2895.6479, 645.07153, 57.12009),  waittime = 15000, name = "Van Horn Trading Post" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(2962.6826, 1293.7446, 43.906204), waittime = 15000, name = "Annesburg Station" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(572.00677, 1713.8681, 187.75619), waittime = 15000, name = "Bacchus Station" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(-1319.959, 388.2633, 95.492622),  waittime = 15000, name = "Wallace Station" },
    { dst = 100.0, dst2 = 10.0, coords = vector3(-1090.563, -588.4188, 81.372642), waittime = 15000, name = "Riggs Station" },
}

Config.RouteOneTramSwitches = {
    { coords = vector3(2615.05, -1281.2, 52.34358),  trainTrack = -1739625337, junctionIndex = 6,  enabled = 0 },
    { coords = vector3(2608.49, -1254.66, 52.66566), trainTrack = -1739625337, junctionIndex = 7,  enabled = 0 },
    { coords = vector3(2686.55, -1385.46, 46.36679), trainTrack = -1739625337, junctionIndex = 3,  enabled = 1 },
    { coords = vector3(2624.4, -1139.85, 51.51707),  trainTrack = -1739625337, junctionIndex = 11, enabled = 0 },
}

Config.RouteOneTramStops = {
    { dst = 5.0, dst2 = 2.0, coords = vector3(2612.97, -1276.06, 52.53), waittime = 15000, name = "Tram Stop One" },
    { dst = 5.0, dst2 = 2.0, coords = vector3(2751.14, -1408.82, 47.06), waittime = 15000, name = "Tram Stop Two" },
    { dst = 5.0, dst2 = 2.0, coords = vector3(2809.01, -1220.39, 48.76), waittime = 15000, name = "Tram Stop Three" },
    { dst = 5.0, dst2 = 2.0, coords = vector3(2608.69, -1161.45, 53.29), waittime = 15000, name = "Tram Stop Four" },
    { dst = 5.0, dst2 = 2.0, coords = vector3(2610.54, -1269.42, 53.78), waittime = 15000, name = "Tram Stop Five" },
}

Config.RouteThreeTrainSwitches = {
    { coords = vector3(-4921.73, -3000.57, -18.48), trainTrack = -1467515357, junctionIndex = 0, enabled = 1 },
    { coords = vector3(-2196.64, -2520.33, 65.87),  trainTrack = -988268728,  junctionIndex = 1, enabled = 1 },
}

Config.RouteThreeTrainStops = {
    { dst = 200.0, dst2 = 15.0, coords = vector3(-5230.27, -3468.65, -20.58), waittime = 20000, name = "Benedict Point Station" },
    { dst = 200.0, dst2 = 15.0, coords = vector3(-3729.1, -2602.83, -12.94),  waittime = 20000, name = "Armadillo Station" },
}

Config.TrackModels = {
    'FREIGHT_GROUP', 'TRAINS3', 'BRAITHWAITES2_TRACK_CONFIG',
    'TRAINS_OLD_WEST01', 'TRAINS_OLD_WEST03', 'TRAINS_NB1', 'TRAINS_INTERSECTION1_ANN',
}

---------------------------------------------------------------
-- MISSIONS
---------------------------------------------------------------
Config.Missions = {
    delivery = {
        basePay = 15,
        perMilePay = 2,
        xpReward = 50,
        timerEnabled = false,
        timerSeconds = 600,
        jobLegs = 3, -- "Start a Delivery Job" chains this many closest-stop deliveries in a row
        cargoTypes = {
            { label = 'Lumber Shipment',   weight = 1.0 },
            { label = 'Coal Delivery',     weight = 1.2 },
            { label = 'Gold Reserves',     weight = 1.5 },
            { label = 'Medical Supplies',  weight = 1.3 },
            { label = 'Ammunition Crates', weight = 1.4 },
            { label = 'Mail & Parcels',    weight = 0.8 },
            { label = 'Livestock Feed',    weight = 0.9 },
            { label = 'Dynamite Shipment', weight = 1.6 },
        },
    },
    maintenance = {
        basePay = 25,
        xpReward = 60,
        requiredRank = 3,
        repairTime = 10000,
        jobLegs = 3, -- "Start a Maintenance Job" chains this many closest-stop repairs in a row
        locations = {
            { coords = vector3(515.0, 650.0, 115.68),   label = 'Heartland Track Section' },
            { coords = vector3(-318.0, -340.0, 89.84),  label = 'Flatneck Rail Crossing' },
            { coords = vector3(1235.0, -1320.0, 76.44), label = 'Lemoyne Junction' },
            { coords = vector3(-1315.0, 395.0, 95.49),  label = 'Cumberland Pass' },
            { coords = vector3(2960.0, 1290.0, 43.91),  label = 'Annesburg Mine Track' },
        },
    },
}

---------------------------------------------------------------
-- DELIVERY DESTINATIONS
---------------------------------------------------------------
Config.DeliveryDestinations = {
    { coords = vector3(487.61, 666.50, 117.39),     label = 'Heartland Depot',        pay = 20, isWest = false, radius = 25 },
    { coords = vector3(-3735.41, -2602.66, -12.91), label = 'Armadillo Freight Yard', pay = 30, isWest = true,  radius = 25 },
    { coords = vector3(1521.84, 428.44, 90.68),     label = 'Emerald Siding',         pay = 18, isWest = false, radius = 25 },
    { coords = vector3(2719.13, -1439.78, 46.22),   label = 'Saint Denis Yard',       pay = 25, isWest = false, radius = 25 },
    { coords = vector3(-1312.36, 387.03, 95.40),    label = 'Wallace Depot',          pay = 22, isWest = false, radius = 25 },
    { coords = vector3(2954.11, 1306.58, 44.49),    label = 'Annesburg Coal Yard',    pay = 28, isWest = false, radius = 25 },
    { coords = vector3(-1095.93, -574.64, 82.41),   label = 'Riggs Landing',          pay = 20, isWest = false, radius = 25 },
    { coords = vector3(583.91, 1682.86, 187.80),    label = 'Bacchus Bridge Depot',   pay = 35, isWest = false, radius = 25 },
}

---------------------------------------------------------------
-- CARGO DELIVERY (physical barrel props for delivery jobs)
--
-- Ported from mack-oilcompany's proven wagon-loading workflow
-- (client/barrel.lua): barrels are NEVER targeted directly while
-- attached to the train -- the JRS interaction prompt/collision on props attached
-- to a moving train proved unreliable in testing. Instead:
--   1. Barrels spawn loose at PlatformSpawnCoords at job start.
--   2. Player targets a loose barrel to pick it up and carry it.
--   3. Player targets the TRAIN (flatbed) to load the carried
--      barrel aboard ("Load Barrel Onto Train").
--   4. At each leg's destination, player targets the TRAIN again
--      to take a barrel back into their hands ("Unload Cargo")
--      and carries it the rest of the way to the drop point.
--
-- ONLY appleseed_config supports delivery jobs -- it's the only
-- train model with a coupled flatbed car (privateflatcar01x) for
-- barrels to sit on. StartDeliveryMission refuses to start (with
-- a clear notification) on any other train.
--
-- PropModel / CarryOffset / CarryAnim / CarryMoveRate are copied
-- straight from mack-oilcompany's proven barrel-carry logic,
-- confirmed working in-game for JRS. TrainAttachOffsets/
-- PlatformSpawnCoords are still PLACEHOLDERS needing in-game
-- tuning (same caveat as Config.TrainRobbery's ped/horse models
-- below).
-- Disabling `Enabled` reverts to no physical cargo, but note that
-- delivery legs currently only complete via the carry/drop flow,
-- so leave this on unless you also restore a walk-based fallback.
---------------------------------------------------------------
Config.CargoDelivery = {
    Enabled              = true,
    PropModel            = 'p_barrel010x', -- PLACEHOLDER: verify in-game
    MaxSimultaneous      = 3,              -- should match Config.Missions.delivery.jobLegs; max barrels the flatbed can carry

    RequiredTrainModel   = 'appleseed_config', -- only this train has the flatbed car for barrels
    FlatbedCarModel      = 'privateflatcar01x', -- the coupled carriage barrels are loaded onto

    -- Where loose barrels spawn for the player to pick up and load onto the train.
    -- One placeholder entry per station (covering all 4 purchasable companies):
    -- 'valentine' is confirmed from in-game testing; every other station below
    -- just reuses that station's own `coords` (heading 0.0) as an untested
    -- starting point -- check each one in-game and adjust the x/y/z/heading as
    -- needed (e.g. move it away from doorways/props, face it properly, etc.).
    PlatformOverrides = {
        -- heartlands_express
        valentine  = vector4(-164.49, 636.65, 114.03, 111.05), -- confirmed by testing
        emerald    = vector4(1525.18, 442.51, 90.68, 0.0),     -- PLACEHOLDER: verify in-game
        annesburg  = vector4(2938.98, 1282.05, 44.65, 0.0),    -- PLACEHOLDER: verify in-game
        -- lemoyne_central
        flatneck   = vector4(-337.13, -360.63, 88.08, 0.0),    -- PLACEHOLDER: verify in-game
        rhodes     = vector4(1225.77, -1296.45, 76.9, 0.0),    -- PLACEHOLDER: verify in-game
        saintdenis = vector4(2747.5, -1398.89, 46.18, 0.0),    -- PLACEHOLDER: verify in-game
        -- cumberland_western
        bacchus    = vector4(582.49, 1681.07, 187.79, 0.0),    -- PLACEHOLDER: verify in-game
        wallace    = vector4(-1299.39, 402.09, 95.38, 0.0),    -- PLACEHOLDER: verify in-game
        riggs      = vector4(-1093.92, -576.97, 82.41, 0.0),   -- PLACEHOLDER: verify in-game
        -- new_austin_rail
        armadillo  = vector4(-3729.1, -2602.83, -12.94, 0.0),  -- PLACEHOLDER: verify in-game
        benedict   = vector4(-5230.27, -3468.65, -20.58, 0.0), -- PLACEHOLDER: verify in-game
    },
    -- Used only if a mission is somehow started without a station reference.
    PlatformFallbackCoords = vector4(-164.49, 636.65, 114.03, 111.05),

    -- Small per-barrel offsets (relative to PlatformSpawnCoords) so multiple loose
    -- barrels don't spawn stacked on top of each other.
    PlatformBarrelOffsets = {
        { x = 0.0, y = 0.0, z = -0.2 },
        { x = 0.8, y = 0.0, z = -0.2 },
        { x = 1.6, y = 0.0, z = -0.2 },
    },

    -- PLACEHOLDER: offsets relative to the resolved flatbed carriage entity's own root (bone 0),
    -- spread front-to-back along its deck. One entry per simultaneous barrel slot -- add more
    -- if MaxSimultaneous/jobLegs is increased. x = side offset, y = along the flatbed length,
    -- z = height above the deck. Still needs in-game tuning -- raise/lower z further if barrels
    -- are clipped into the flatbed deck or float above it.
    TrainAttachOffsets = {
        { x = 0.0, y = -1.5, z = 1.1 },
        { x = 0.0, y = 0.0,  z = 1.1 },
        { x = 0.0, y = 1.5,  z = 1.1 },
    },

    -- Proven values from mack-oilcompany's Config.CarryOffsets.barrel (CP_BeltFront attach point).
    CarryOffset          = { x = 0.0, y = 0.7, z = -0.2 },

    -- Proven barrel carry animation from mack-oilcompany's AttachBarrelToPlayer.
    CarryAnim            = { dict = 'mech_carry_box', name = 'walk_heavy' },
    CarryMoveRate        = 0.7, -- slows the player while carrying, same as mack-oilcompany

    PickupRequiresStopped = true, -- train must be stopped to load/unload barrels
    MaxTrainSpeedToPickup = 1.5,   -- m/s

    DropRadius            = 4.0,   -- distance from destination coords that completes the leg
    AbandonDistance       = 100.0, -- distance from the destination that force-fails an active carry

    -- Only one barrel can be unloaded per drop-off: after a delivery, the train
    -- must move at least this far from that spot before "Unload Cargo" appears again.
    MinMoveDistance       = 15.0,
}

---------------------------------------------------------------
-- REWARDS
---------------------------------------------------------------
Config.RailwaymanRewards = {
    { id = 'first_train',  label = 'First Train Purchased',    condition = 'trains_owned',       threshold = 1,    cashReward = 50,  xpReward = 100  },
    { id = 'mile_100',     label = '100 Miles Traveled',       condition = 'total_miles',        threshold = 100,  cashReward = 100, xpReward = 200  },
    { id = 'mile_500',     label = '500 Miles Traveled',       condition = 'total_miles',        threshold = 500,  cashReward = 300, xpReward = 500  },
    { id = 'mile_1000',    label = '1000 Miles Traveled',      condition = 'total_miles',        threshold = 1000, cashReward = 750, xpReward = 1000 },
    { id = 'delivery_10',  label = '10 Deliveries Completed',  condition = 'missions_completed', threshold = 10,   cashReward = 75,  xpReward = 150  },
    { id = 'delivery_50',  label = '50 Deliveries Completed',  condition = 'missions_completed', threshold = 50,   cashReward = 250, xpReward = 500  },
    { id = 'delivery_100', label = '100 Deliveries Completed', condition = 'missions_completed', threshold = 100,  cashReward = 500, xpReward = 1000 },
}

Config.CompanyRankRewards = {
    [2] = { cashReward = 50,  xpReward = 0 },
    [3] = { cashReward = 100, xpReward = 0 },
    [4] = { cashReward = 200, xpReward = 0 },
    [5] = { cashReward = 500, xpReward = 0 },
}

---------------------------------------------------------------
-- BLIPS
---------------------------------------------------------------
Config.Blips = {
    station = { hash = -250506368,  scale = 0.8 },
    train   = { hash = -399496385,  scale = 1.2 },
    mission = { hash = -1282792512, scale = 0.9 },
    water   = { hash = 1321928545,  scale = 0.5 },
    depot   = { hash = 1321928545,  scale = 0.5 },
    switch  = { hash = 1173759417,  scale = 0.4 },
}

---------------------------------------------------------------
-- AMBIENT TRAM (Saint Denis) -- was referenced by client/main.lua
-- (SpawnAmbientTram) but never defined; feature silently no-op'd.
---------------------------------------------------------------
Config.AmbientTram = {
    enabled    = true,
    model      = 'appleseed_config',                    -- reuse a known-good train model
    spawnCoords = vector3(2732.33, -1445.62, 45.77),     -- Saint Denis Yard
    direction  = 1,
    passengers = 6,
    speed      = 8.0,
}

---------------------------------------------------------------
-- TRAIN ROBBERY -- was referenced extensively by
-- client/train_robbery.lua but never defined at all, so the whole
-- feature errored out (Config.TrainRobbery.Enabled on a nil table).
--
-- NOTE: OutlawModels / HorseModels / OutlawWeapons below MUST be
-- verified against real RDR2 ped/weapon model names for your build
-- before enabling -- they are left as clearly-marked placeholders
-- because shipping guessed model hashes would just fail silently
-- (peds won't load) instead of erroring, which is worse to debug.
-- Enabled is set to false until you confirm/replace them.
---------------------------------------------------------------
Config.TrainRobbery = {
    Enabled              = false,   -- flip to true once models below are verified
    AmbientEnabled       = true,
    AmbientCheckInterval = 300000,  -- 5 min between scans for ambient trains to rob
    AmbientChance        = 25,      -- % chance an ambient train gets robbed per scan
    AmbientFollowMs      = 45000,   -- how long ambient outlaws harass a route train
    PlayerChance         = 20,      -- % chance used only if TriggerTrainRobbery(false) is ever called
    SafeZoneRadius       = 500.0,   -- no robbery within this distance of any station
    ManualStopRobRadius  = 15.0,    -- outlaw must be this close to rob a stopped/dead train
    TrainStopSpeed       = 1.5,     -- speed (m/s) below which a manual stop counts as "stopped"
    RobberySlowSpeed     = 8.0,     -- train is forced down to this speed during a robbery
    BoardTrain           = true,
    BoardDistance        = 4.0,
    BoardSideOffset      = 1.2,
    EscapeTimeMs         = 15000,
    InitialMessageDelay  = 4000,
    SpawnAheadDistance   = 80.0,
    SpawnMultiplier      = 3.0,
    OutlawCount          = { min = 2, max = 4 },
    OutlawAccuracy       = 35,
    -- PLACEHOLDER -- replace with real RDR2 ped model names:
    OutlawModels         = { 'cs_flaco', 'cs_billwilliamson' },
    HorseModels          = { 'a_c_horse_kentuckysaddle_black' },
    OutlawWeapons        = { 'WEAPON_REPEATER_WINCHESTER', 'WEAPON_REVOLVER_CATTLEMAN' },
    PressureDecayInterval    = 4000,
    PressureDecayPerOutlaw   = 4,
    PressureAttackRadius     = 40.0,
    PressureRecoveryInterval = 2000,
    PressureRecoveryAmount   = 5,
    PressureRepairAmount     = 30,
    PressureRepairTime       = 8000,
    -- Cash taken from the company register on a successful robbery:
    RobberyTakePercent   = 0.20,    -- 20% of the current cash register
    RobberyTakeMin       = 20,
    RobberyTakeMax       = 500,
}
