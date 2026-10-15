-- ==========================================================================
--  JRS CORE  |  jrs_housing  |  config.lua
--  houses for sale - buy, sell, share keys, storage, wardrobe and door access
-- ==========================================================================

Config = {}

Config.Language = 'en'                  -- 'en' or 'ar'

-- ─── Buying / selling ──────────────────────────────────────────────────────
Config.MaxHousesPerCharacter = 1        -- how many houses one character may own
Config.SellBackPercent       = 50       -- % of the price paid back when selling
Config.MaxKeys               = 4        -- extra key holders per house
Config.ClearStorageOnSell    = true     -- empty the storages when a house is sold

-- ─── Interaction ───────────────────────────────────────────────────────────
Config.InteractKey      = 0x760A9C6F    -- G
Config.EntranceDistance = 2.0           -- "View house" prompt at the front door
Config.SpotDistance     = 1.6           -- storage / wardrobe prompts
Config.GiveKeyDistance  = 4.0           -- the player receiving a key must be this close

-- ─── Map ───────────────────────────────────────────────────────────────────
Config.Blips = {
    forSale = { show = true, sprite = `blip_mp_base`, modifier = 'BLIP_MODIFIER_MP_COLOR_8',  scale = 0.2 },
    owned   = { show = true, sprite = `blip_mp_base`, modifier = 'BLIP_MODIFIER_MP_COLOR_32', scale = 0.2 },
}

-- ─── Houses ────────────────────────────────────────────────────────────────
-- label, price (cash), position (centre of the house), wardrobe (vector3 or false),
-- storages { label, coords, slots }, doors = door hashes from jrs_doorlocks.
-- The first door is the entrance where the house can be viewed and bought.
-- Never reorder or remove entries once players own houses: the list index is
-- the house id saved in the database. Add new houses at the end.
Config.Houses = {
    -- 1. Widows Rock House 1
    {
        label    = "Widows Rock House 1",
        price    = 350,
        position = vector3(-397.7, 1727.66, 216.49),
        wardrobe = vector3(-397.22, 1728.51, 216.54),
        storages = {
            { label = "Food Storage", coords = vector3(-391.28, 1728.72, 216.44), slots = 100 },
            { label = "Tools Storage", coords = vector3(-396.38, 1732.76, 216.43), slots = 100 },
        },
        doors = {
            4070066247, -- Front Door
            3444471262, -- Front Door
        },
    },

    -- 2. Cabin at Braithwaite Manor
    {
        label    = "Cabin at Braithwaite Manor",
        price    = 300,
        position = vector3(1118.0621, -1987.8922, 55.3475),
        wardrobe = vector3(1118.96, -1989.63, 55.42),
        storages = {
            { label = "Storage", coords = vector3(1119.0345, -1985.6793, 55.3500), slots = 100 },
        },
        doors = {
            3921310299, -- Front Door
        },
    },

    -- 3. Cabin at Lake O'Creagh's
    {
        label    = "Cabin at Lake O'Creagh's",
        price    = 300,
        position = vector3(1700.6041, 1511.0630, 147.8734),
        wardrobe = vector3(1702.66, 1512.67, 147.92),
        storages = {
            { label = "Storage", coords = vector3(1701.4554, 1509.2227, 147.8706), slots = 100 },
        },
        doors = {
            868379185, -- Front Door
            640077562, -- Back Door
        },
    },

    -- 4. Cabin on the Southfield Plains
    {
        label    = "Cabin on the Southfield Plains",
        price    = 300,
        position = vector3(1134.9661, -979.6726, 69.3992),
        wardrobe = vector3(1132.72, -980.94, 69.45),
        storages = {
            { label = "Storage", coords = vector3(1133.7925, -981.4205, 69.4031), slots = 100 },
        },
        doors = {
            3929468747, -- Front Door
        },
    },

    -- 5. Cabin in the Roanoke Valley
    {
        label    = "Cabin in the Roanoke Valley",
        price    = 450,
        position = vector3(2625.1238, 1695.9159, 115.6895),
        wardrobe = vector3(2624.99, 1692.77, 115.75),
        storages = {
            { label = "Storage", coords = vector3(2624.1274, 1696.4465, 115.7027), slots = 100 },
        },
        doors = {
            1574473390, -- Front Door
        },
    },

    -- 6. House in Rhodes
    {
        label    = "House in Rhodes",
        price    = 400,
        position = vector3(1112.8748, -1301.4908, 66.4053),
        wardrobe = vector3(1107.6, -1302.6, 66.46),
        storages = {
            { label = "Storage", coords = vector3(1116.5450, -1297.7770, 66.3814), slots = 100 },
        },
        doors = {
            1485561723, -- Front Door
            4276865168, -- Room 1 Door
            1532575796, -- Room 2 Door
            1151226872, -- Room 3 Door
            3544613794, -- Back Door
        },
    },

    -- 7. House in the snow town
    {
        label    = "House in the snow town",
        price    = 400,
        position = vector3(-1351.5906, 2439.3948, 308.4406),
        wardrobe = vector3(-1357.44, 2443.98, 308.47),
        storages = {
            { label = "Storage", coords = vector3(-1354.6299, 2443.4001, 308.4202), slots = 100 },
        },
        doors = {
            2183007198, -- Front Door
            4288310487, -- Back Door
        },
    },

    -- 8. House in the snow
    {
        label    = "House in the snow",
        price    = 500,
        position = vector3(-554.4449, 2703.8315, 320.4272),
        wardrobe = vector3(-555.6, 2710.54, 320.46),
        storages = {
            { label = "Storage", coords = vector3(-553.2963, 2701.4446, 320.4149), slots = 100 },
        },
        doors = {
            872775928, -- Front Door
            2385374047, -- Back Door
        },
    },

    -- 9. House in Valentine
    {
        label    = "House in Valentine",
        price    = 350,
        position = vector3(774.8596, 847.4821, 118.9179),
        wardrobe = vector3(779.44, 844.47, 121.97),
        storages = {
            { label = "Storage", coords = vector3(776.3958, 845.6426, 121.9363), slots = 100 },
        },
        doors = {
            4123766266, -- Front Door
            1002666274, -- Room 1 Door
            417362979, -- Back Door
        },
    },

    -- 10. Cabin on the Dakota River
    {
        label    = "Cabin on the Dakota River",
        price    = 350,
        position = vector3(-689.8939, 1044.0026, 135.0041),
        wardrobe = vector3(-690.71, 1045.72, 135.13),
        storages = {
            { label = "Storage", coords = vector3(-689.4321, 1040.9478, 135.0034), slots = 100 },
        },
        doors = {
            1434140379, -- Front Door
        },
    },

    -- 11. House on the Dakota River
    {
        label    = "House on the Dakota River",
        price    = 300,
        position = vector3(-612.9479, -27.5009, 85.9752),
        wardrobe = vector3(-614.13, -29.92, 86.02),
        storages = {
            { label = "Storage", coords = vector3(-613.2334, -35.0650, 85.9820), slots = 100 },
        },
        doors = {
            1189146288, -- Front Door
            365712512, -- Room 1 Door
            138361190, -- Room 2 Door
            906448125, -- Back Door
        },
    },

    -- 12. Big Valley Farm House
    {
        label    = "Big Valley Farm House",
        price    = 300,
        position = vector3(-2594.6492, 457.3839, 146.9972),
        wardrobe = vector3(-2595.87, 460.92, 147.05),
        storages = {
            { label = "Storage", coords = vector3(-2595.0100, 453.5163, 146.9974), slots = 100 },
        },
        doors = {
            1535511805, -- Front Door
            2395304827, -- Back Door
        },
    },

    -- 13. House on the Little Creek River
    {
        label    = "House on the Little Creek River",
        price    = 300,
        position = vector3(-2177.1870, 718.3368, 122.6199),
        wardrobe = vector3(-2181.22, 721.0, 126.25),
        storages = {
            { label = "Storage", coords = vector3(-2173.4402, 715.4520, 122.6186), slots = 100 },
        },
        doors = {
            2212914984, -- Front Door
            2670400201, -- Room 1 Door
        },
    },

    -- 14. Farm House on the outskirts of Blackwater
    {
        label    = "Farm House on the outskirts of Blackwater",
        price    = 450,
        position = vector3(-1641.7750, -1360.7200, 84.4027),
        wardrobe = vector3(-1645.93, -1359.01, 87.5),
        storages = {
            { label = "Storage", coords = vector3(-1642.6538, -1351.1543, 84.4032), slots = 100 },
        },
        doors = {
            1606546482, -- Front Door
            1309495497, -- Room 1 Door
            1063695460, -- Room 2 Door
            1731691513, -- Bathroom Door
            2310818050, -- Back Door
        },
    },
}
