-- jrs_herbs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_herbs  |  config.lua
--  Pick wild plants around the map and herbs at fixed spots.
-- ==========================================================================

Config = {
    Language   = 'en',          -- 'en' or 'ar' (the prompt itself stays English: the game font has no Arabic)
    PromptKey  = 0x6D1319BE,    -- R, hold it
    HoldTime   = 3000,          -- ms the key must be held
    Reach      = 2.0,           -- metres to a plant
    SpotRange  = 100.0,         -- fixed spots are active this close (their model is spawned here)
}

Config.Text = {
    en = {
        pick = 'Pick', plants = 'Plants',
        noRoom = 'No room in inventory for the items.', tooFar = 'You are too far from the plant location.',
        picked = 'This plant was picked already, come back in a bit.', noSpace = "You don't have enough space in your inventory",
        got = 'You got ',
    },
    ar = {
        pick = 'Pick', plants = 'Plants',
        noRoom = 'ما فيه مكان بشنطتك.', tooFar = 'أنت بعيد عن النبتة.',
        picked = 'هالنبتة انقطفت قبل شوي، ارجع بعدين.', noSpace = 'ما عندك مكان كافي بشنطتك',
        got = 'حصلت على ',
    },
}

-- ------------------------------------------------------------------ plant lists
-- wild(label, model, { reward items }, fewest, most, cooldown minutes)
-- spot(label, model, { reward items }, fewest, most, cooldown minutes, vector3(x, y, z), spawnModel?)
-- Every reward item is given in the same random amount between fewest and most.

local function wild(label, model, reward, lo, hi, cooldown)
    return { kind = 'wild', label = label, model = model, reward = reward, min = lo, max = hi, cooldown = cooldown }
end

local function spot(label, model, reward, lo, hi, cooldown, at, spawn)
    return { kind = 'spot', label = label, model = model, reward = reward, min = lo, max = hi,
             cooldown = cooldown, at = at, spawn = spawn == true }
end

-- wild plants: found anywhere in the world by their model
Config.WildPlants = {
    wild('blueberry', 'rdr_bush_dry_thin_ba_sim', { 'blueberry', 'Blueberry_Seed' }, 1, 5, 1),
    wild('Indian Tobbaco', 'indtobacco_p', { 'Indian_Tobbaco' }, 1, 5, 1),
    wild('Cotton', 'crp_cotton_bd_sim', { 'cotton' }, 1, 5, 1),
    wild('Oregano', 'oregano_p', { 'Oregano' }, 1, 5, 1),
    wild('Basil', 'rdr_bush_bram_aa_sim', { 'Basil' }, 1, 5, 1),
    wild('Agarita', 'mp005_s_inv_agarita_01x', { 'Agarita' }, 1, 5, 1),
    wild('Creeking Thyme', 'thyme_p', { 'Creeking_Thyme' }, 1, 5, 1),
    wild('Milk Weed', 'milkweed_p', { 'Milk_Weed' }, 1, 5, 1),
    wild('Crows Garlic', 'crowsgarlic_p', { 'Crows_Garlic' }, 1, 5, 1),
    wild('English Mace', 'engmace_p', { 'English_Mace' }, 1, 5, 1),
    wild('Hummingbird Sage', 'humbirdsage_p', { 'Hummingbird_Sage' }, 1, 5, 1),
    wild('Oleander Sage', 'orleander_p', { 'Oleander_Sage' }, 1, 5, 1),
    wild('Desert Sage', 'desertsage_p', { 'Desert_Sage' }, 1, 5, 1),
    wild('American Ginseng', 'ginseng_p', { 'American_Ginseng' }, 1, 5, 1),
    wild('Alaskan Ginseng', 'alaskanginseng_p', { 'Alaskan_Ginseng' }, 1, 5, 1),
    wild('Red Raspberry', 's_inv_raspberry01x', { 'Red_Raspberry' }, 1, 5, 1),
    wild('Apple', 'p_tree_apple_01', { 'apple' }, 1, 5, 1),
    wild('Grain', 'crp_wheat_dry_aa_sim', { 'Grain' }, 1, 5, 1),
    wild('Agave', 'rdr_bush_agave_aa_sim', { 'Agave' }, 1, 5, 1),
    wild('Red Sage', 'redsage_p', { 'Red_Sage' }, 1, 5, 1),
    wild('Black Currant', 'blackcurrant_p', { 'Black_Currant' }, 1, 5, 1),
    wild('Bitter Weed', 'mp005_bitterweed_p', { 'Bitter_Weed' }, 1, 5, 1),
    wild('Evergreen Huckleberry', 's_inv_huckleberry01x', { 'Evergreen_Huckleberry' }, 1, 5, 1),
    wild('Bulrush', 'bulrush_p', { 'Bulrush' }, 1, 5, 1),
    wild('Wisteria', 'mp005_s_inv_wisteria01x', { 'Wisteria' }, 1, 5, 1),
    wild('Wild Rhubarb', 'mp005_rhubarb_p', { 'Wild_Rhubarb' }, 1, 5, 1),
    wild('Wintergreen Berry', 's_inv_wintergreen01x', { 'Wintergreen_Berry' }, 1, 5, 1),
    wild('Sugarcane', 'crp_sugarcane_ac_sim', { 'sugar' }, 1, 5, 1),
}

-- fixed spots: a plant at known coordinates (the last argument true = spawn the model there)
Config.Spots = {
    spot('blueberry', 'rdr_bush_dry_thin_ba_sim', { 'blueberry', 'Blueberry_Seed' }, 1, 5, 1, vector3(2032.34, -818.20, 42.67), true),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(2009.33, -882.96, 42.96)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1999.68, -883.71, 42.91)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1989.15, -882.77, 42.36)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1981.92, -882.38, 42.40)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1971.59, -876.93, 42.03)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1981.15, -875.14, 42.45)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1987.82, -873.35, 42.68)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1999.60, -873.65, 42.42)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(2009.29, -872.42, 42.34)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(2018.73, -873.18, 42.77)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(2036.01, -864.92, 42.60)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(2027.38, -865.86, 42.56)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(2018.20, -865.97, 42.60)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1960.38, -856.78, 42.12)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(2008.23, -865.35, 42.86)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1999.31, -865.48, 42.89)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1989.77, -864.45, 42.47)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1979.89, -866.82, 41.85)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1970.70, -866.30, 41.55)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1962.55, -866.43, 41.71)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1970.33, -858.09, 41.96)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1979.69, -856.79, 41.93)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1987.90, -855.47, 42.38)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1997.71, -855.62, 42.69)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2007.12, -854.76, 42.80)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2017.02, -853.60, 42.81)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2026.87, -855.13, 42.57)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2036.59, -854.72, 42.40)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2036.57, -845.50, 42.80)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2027.04, -845.69, 43.03)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2017.53, -844.59, 43.14)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(2007.35, -845.59, 42.92)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1998.93, -845.95, 42.65)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1988.51, -846.20, 42.32)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1979.88, -847.81, 42.10)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1970.52, -849.38, 41.86)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1961.45, -848.45, 41.90)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1987.28, -837.99, 42.13)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1996.80, -837.54, 42.28)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(2006.63, -836.59, 42.44)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(2016.89, -836.21, 42.86)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(2026.19, -835.05, 42.73)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(2035.89, -835.05, 42.55)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(2027.24, -826.91, 42.32)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(2007.30, -826.90, 42.26)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(2017.68, -827.99, 42.33)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1051.53, -1731.91, 46.81)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1050.98, -1741.04, 46.73)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1052.01, -1749.82, 46.81)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1051.53, -1758.96, 46.85)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1050.71, -1768.72, 46.87)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1051.72, -1778.53, 47.10)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1059.81, -1797.46, 48.32)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1059.52, -1788.41, 47.96)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1060.63, -1779.88, 47.77)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1059.94, -1769.92, 47.47)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1061.08, -1759.55, 47.42)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1060.70, -1750.92, 47.33)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1059.99, -1741.61, 47.22)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1059.63, -1733.98, 47.18)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1057.89, -1723.74, 47.22)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1069.00, -1713.32, 48.32)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1068.46, -1721.85, 48.20)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1069.36, -1731.84, 48.18)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1070.92, -1740.19, 48.28)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1069.19, -1748.79, 48.08)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1070.34, -1759.50, 48.21)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1068.87, -1767.70, 48.13)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1068.94, -1777.57, 48.32)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1068.30, -1786.75, 48.56)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1068.70, -1796.17, 48.91)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1069.08, -1806.43, 49.04)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1078.13, -1807.23, 48.87)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1077.29, -1797.22, 49.11)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1079.04, -1788.33, 49.21)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1078.82, -1778.40, 49.26)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1078.22, -1769.87, 49.06)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1078.52, -1759.52, 49.00)),
    spot('Orange Tree', '', { 'orange' }, 1, 5, 1, vector3(1079.14, -1816.25, 48.57)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1088.54, -1816.66, 47.60)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1088.29, -1806.62, 48.18)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1088.46, -1797.53, 48.54)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1088.21, -1787.97, 48.92)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1087.50, -1778.22, 49.15)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1087.88, -1768.41, 49.37)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1087.74, -1759.34, 49.45)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1087.48, -1749.55, 49.61)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1086.87, -1740.60, 49.84)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1086.41, -1732.88, 49.92)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1078.05, -1749.62, 48.98)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1078.71, -1742.08, 49.00)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1079.07, -1732.60, 49.27)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1077.90, -1723.14, 49.25)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1078.42, -1712.51, 49.35)),
    spot('Lemon Tree', '', { 'lemon' }, 1, 5, 1, vector3(1087.00, -1722.88, 50.05)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1768.56, -1322.75, 43.82)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1765.59, -1314.21, 44.08)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1758.56, -1318.52, 44.23)),
    spot('Apple Tree', '', { 'apple' }, 1, 5, 1, vector3(1761.63, -1325.03, 44.35)),
}
