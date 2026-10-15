-- jrs_mining | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_mining  |  config.lua
--  Mine rocks with a pickaxe for ore and minerals.
-- ==========================================================================

Config = {
    Language   = 'en',                 -- 'en' or 'ar' (prompts stay English: the game font has no Arabic)

    Pickaxe    = 'pickaxe',            -- inventory item used as the pickaxe
    Swings     = { min = 1, max = 3 }, -- swings a rock takes (the server decides)
    Cooldown   = 60,                   -- minutes before the same spot can be mined again
    RockReach  = 1.3,                  -- metres from the rock

    -- Skill bar (jrs_minigame): milliseconds the bar takes. Smaller = faster = harder.
    BarTime    = { easiest = 4000, hardest = 2700 },
    BarGap     = 7,

    -- Keys
    StartKey   = 0xD9D0E1C0,           -- SPACE (hold)
    CancelKey  = 0x3B24C470,           -- F (hold)
    SwingKey   = 0x07B8BEAF,           -- left mouse button

    -- Pickaxe wear
    Wear = {
        startsAt     = 99,             -- durability of a new pickaxe
        riskBelow    = 20,             -- below this durability the pickaxe may break on a use
        breakOneIn   = { min = 1, max = 3 },   -- rolls 1..n; a 1 breaks it
    },

    ChanceRange = 20,                  -- loot roll is 1..this; an item drops when its chance is at least the roll
}

-- Mining is not allowed inside these towns (Annesburg is a mining town: allowed)
Config.ForbiddenTowns = {
    'Armadillo', 'Blackwater', 'Lagras', 'Rhodes',
    'StDenis', 'Strawberry', 'Tumbleweed', 'Valentine', 'Vanhorn',
}

-- What a good swing can give: name, label, chance (out of Config.ChanceRange), most pieces
Config.Loot = {
    { name = 'clay',       label = 'Clay',         chance = 20, most = 4 },
    { name = 'coal',       label = 'Coal',         chance = 15, most = 4 },
    { name = 'copper',     label = 'Copper',       chance = 10, most = 8 },
    { name = 'iron',       label = 'Iron',         chance = 20, most = 12 },
    { name = 'nitrite',    label = 'Nitrite',      chance = 8,  most = 4 },
    { name = 'rock',       label = 'Rocks',        chance = 10, most = 4 },
    { name = 'salt',       label = 'Salt',         chance = 10, most = 4 },
    { name = 'goldnugget', label = 'Gold Nuggets', chance = 3,  most = 2 },
}

Config.Text = {
    en = {
        mine = 'Mine', mineTitle = 'Mine the rock', usePickaxe = 'Use Pickaxe', stop = 'Keep/Exit',
        got = 'You got ', nothing = 'You got nothing', bagFull = "You can't carry any more ",
        pickBroke = 'Your pickaxe broke', noPickaxe = "You don't have a pickaxe", cooling = 'Nothing to mine here',
        durability = 'Durability',
        slips = {
            'That almost went into my foot...', "Careful, don't hit your knee!", "It's a pick, not a hammer!",
            'Slipped!', 'Missed!', 'It was wood, not rock...', 'No strength to lift the pickaxe?',
        },
    },
    ar = {
        mine = 'Mine', mineTitle = 'Mine the rock', usePickaxe = 'Use Pickaxe', stop = 'Keep/Exit',
        got = 'حصلت على ', nothing = 'ما حصلت شي', bagFull = 'ما تقدر تشيل أكثر ',
        pickBroke = 'انكسر معولك', noPickaxe = 'ما عندك معول', cooling = 'ما فيه شي تحفره هنا',
        durability = 'المتانة',
        slips = {
            'كانت بتجي في رجلي...', 'انتبه لا تضرب ركبتك!', 'هذا معول مو مطرقة!',
            'زلقت!', 'ما صبت!', 'كان خشب مو صخر...', 'ما عندك قوة ترفع المعول؟',
        },
    },
}

-- Rock models that can be mined
Config.Rocks = {
    'alp_rock_01', 'alp_rock_02', 'alp_rock_03',
    'alp_rock_04', 'alp_rock_05', 'alp_rock_06',
    'alp_rock_07', 'alp_rock_08', 'alp_rock_09',
    'alp_rock_10', 'alp_rock_scree_01', 'alp_rock_scree_02',
    'alp_rock_scree_03', 'alp_rock_scree_04', 'alp_rock_scree_05',
    'alp_rock_scree_06', 'alp_rock_scree_sim_01', 'alp_rock_scree_sim_02',
    'alp_rock_scree_sim_03', 'alp_rock_scree_sim_04', 'alp_rock_scree_sim_05',
    'alp_rock_scree_sim_06', 'alp_rock_scree_sim_07', 'alp_rock_scree_sim_08',
    'alp_rock_scree_sim_09', 'alp_rock_scree_sim_10', 'alp_rock_scree_sim_11',
    'bgv_rock_01', 'bgv_rock_02', 'bgv_rock_03',
    'bgv_rock_04', 'bgv_rock_05', 'bgv_rock_06',
    'bgv_rock_07', 'bgv_rock_08', 'bgv_rock_09',
    'bgv_rock_10', 'bgv_rock_11', 'bgv_rock_12',
    'bgv_rock_scree_01', 'bgv_rock_scree_02', 'bgv_rock_scree_03',
    'bgv_rock_scree_04', 'bgv_rock_scree_05', 'bgv_rock_scree_06',
    'bgv_rock_scree_sim_01', 'bgv_rock_scree_sim_02', 'bgv_rock_scree_sim_03',
    'bgv_rock_scree_sim_04', 'bgv_rock_scree_sim_05', 'bgv_rock_scree_sim_06',
    'bgv_rock_scree_sim_07', 'bgv_rock_scree_sim_08', 'bgv_rock_scree_sim_09',
    'bgv_rock_scree_sim_10', 'bgv_rock_scree_sim_11', 'bgv_rock_stones_aa',
    'bgv_rock_stones_ab', 'cumb_rock_01', 'cumb_rock_02',
    'cumb_rock_03', 'cumb_rock_04', 'cumb_rock_05',
    'cumb_rock_06', 'cumb_rock_07', 'cumb_rock_08',
    'cumb_rock_09', 'cumb_rock_10', 'cumb_rock_11',
    'cumb_rock_12', 'cumb_rock_hero_01', 'cumb_rock_scree_01',
    'cumb_rock_scree_02', 'cumb_rock_scree_03', 'cumb_rock_scree_04',
    'cumb_rock_scree_05', 'cumb_rock_scree_06', 'cumb_rock_scree_sim_01',
    'cumb_rock_scree_sim_02', 'cumb_rock_scree_sim_03', 'cumb_rock_scree_sim_04',
    'cumb_rock_scree_sim_05', 'cumb_rock_scree_sim_06', 'cumb_rock_scree_sim_07',
    'cumb_rock_scree_sim_08', 'cumb_rock_scree_sim_09', 'cumb_rock_scree_sim_10',
    'cumb_rock_scree_sim_11', 'dak_rock_scree_stg1_01', 'dak_rock_scree_stg1_02',
    'dak_rock_scree_stg1_03', 'dak_rock_scree_stg1_04', 'dak_rock_scree_stg1_05',
    'dak_rock_scree_stg1_06', 'dak_rock_scree_stg2_01', 'dak_rock_scree_stg2_02',
    'dak_rock_scree_stg2_03', 'dak_rock_scree_stg2_04', 'dak_rock_scree_stg2_05',
    'dak_rock_scree_stg2_06', 'dak_rock_scree_stg345_01', 'dak_rock_scree_stg345_02',
    'dak_rock_scree_stg345_03', 'dak_rock_scree_stg345_04', 'dak_rock_scree_stg345_05',
    'dak_rock_scree_stg345_06', 'dak_rock_scree_stg345_sim_01', 'dak_rock_scree_stg345_sim_02',
    'dak_rock_scree_stg345_sim_03', 'dak_rock_scree_stg345_sim_04', 'dak_rock_scree_stg345_sim_05',
    'dak_rock_scree_stg345_sim_06', 'dak_rock_scree_stg345_sim_07', 'dak_rock_scree_stg345_sim_08',
    'dak_rock_scree_stg345_sim_09', 'dak_rock_scree_stg345_sim_10', 'dak_rock_scree_stg345_sim_11',
    'dak_rock_shelve_stg345_01', 'dak_rock_shelve_stg345_02', 'dak_rock_shelve_stg345_03',
    'dak_rock_shelve_stg345_04', 'dak_rock_shelve_stg345_05', 'dak_rock_stg1_01',
    'dak_rock_stg1_02', 'dak_rock_stg1_03', 'dak_rock_stg1_04',
    'dak_rock_stg1_05', 'dak_rock_stg1_06', 'dak_rock_stg2_01',
    'dak_rock_stg2_02', 'dak_rock_stg2_03', 'dak_rock_stg2_04',
    'dak_rock_stg2_05', 'dak_rock_stg2_06', 'dak_rock_stg345_01',
    'dak_rock_stg345_010', 'dak_rock_stg345_011', 'dak_rock_stg345_012',
    'dak_rock_stg345_013', 'dak_rock_stg345_014', 'dak_rock_stg345_015',
    'dak_rock_stg345_016', 'dak_rock_stg345_017', 'dak_rock_stg345_018',
    'dak_rock_stg345_019', 'dak_rock_stg345_02', 'dak_rock_stg345_03',
    'dak_rock_stg345_04', 'dak_rock_stg345_05', 'dak_rock_stg345_06',
    'dak_rock_stg345_07', 'dak_rock_stg345_08', 'dak_rock_stg345_09',
    'grp_rock_01', 'grp_rock_02', 'grp_rock_03',
    'grp_rock_04', 'grp_rock_05', 'grp_rock_06',
    'grp_rock_07', 'grp_rock_08', 'grp_rock_09',
    'grp_rock_10', 'grp_rock_11', 'grp_rock_scree_01',
    'grp_rock_scree_02', 'grp_rock_scree_03', 'grp_rock_scree_04',
    'grp_rock_scree_05', 'grp_rock_scree_06', 'grp_rock_scree_sim_01',
    'grp_rock_scree_sim_02', 'grp_rock_scree_sim_03', 'grp_rock_scree_sim_04',
    'grp_rock_scree_sim_05', 'grp_rock_scree_sim_06', 'grp_rock_scree_sim_07',
    'grp_rock_scree_sim_08', 'grp_rock_scree_sim_09', 'grp_rock_scree_sim_10',
    'grp_rock_scree_sim_11', 'grp_rock_stones_aa', 'grp_rock_stones_ab',
    'gri_rock_01', 'gri_rock_02', 'gri_rock_03',
    'gri_rock_04', 'gri_rock_05', 'gri_rock_06',
    'gri_rock_07', 'gri_rock_08', 'gri_rock_09',
    'gri_rock_10', 'gri_rock_scree_01', 'gri_rock_scree_02',
    'gri_rock_scree_03', 'gri_rock_scree_04', 'gri_rock_scree_05',
    'gri_rock_scree_06', 'gri_rock_scree_sim_01', 'gri_rock_scree_sim_02',
    'gri_rock_scree_sim_03', 'gri_rock_scree_sim_04', 'gri_rock_scree_sim_05',
    'gri_rock_scree_sim_06', 'gri_rock_scree_sim_07', 'gri_rock_scree_sim_08',
    'gri_rock_scree_sim_09', 'gri_rock_scree_sim_10', 'gri_rock_scree_sim_11',
    'gri_rock_scree_snow_05', 'gri_rock_scree_snow_06', 'gri_rock_snow_01',
    'gri_rock_snow_02', 'gri_rock_snow_03', 'gri_rock_snow_04',
    'gri_rock_snow_05', 'gri_rock_snow_06', 'gri_rock_snow_07',
    'gri_rock_snow_08', 'gri_rock_snow_09', 'gri_rock_snow_10',
    'gua_rock_01', 'gua_rock_02', 'gua_rock_03',
    'gua_rock_04', 'gua_rock_05', 'gua_rock_06',
    'gua_rock_07', 'gua_rock_08', 'gua_rock_09',
    'gua_rock_10', 'gua_rock_11', 'gua_rock_12',
    'gua_rock_13', 'gua_rock_14', 'gua_rock_15',
    'gua_rock_scree_01', 'gua_rock_scree_02', 'gua_rock_scree_03',
    'gua_rock_scree_04', 'gua_rock_scree_05', 'gua_rock_scree_06',
    'gua_rock_scree_sim_01', 'gua_rock_scree_sim_02', 'gua_rock_scree_sim_03',
    'gua_rock_scree_sim_04', 'gua_rock_scree_sim_05', 'gua_rock_scree_sim_06',
    'gua_rock_stones_aa', 'gua_rock_wall_ba', 'gua_rock_wall_bb',
    'gua_rock_wall_bc', 'gua_rock_wall_bd', 'gua_rock_wall_be',
    'gua_rock_wall_bf', 'gua_rock_wall_bg', 'gua_rock_wall_bh',
    'gua_rock_wall_deb_aa', 'gua_rock_wall_deb_ab', 'gua_rock_wall_deb_ac',
    'gua_rubble_large_01', 'gua_rubble_large_02', 'gua_rubble_rock_01',
    'gua_rubble_rock_02', 'gua_rubble_rock_03', 'gua_rubble_rock_04',
    'hea_rock_01', 'hea_rock_02', 'hea_rock_03',
    'hea_rock_04', 'hea_rock_05', 'hea_rock_06',
    'hea_rock_07', 'hea_rock_08', 'hea_rock_09',
    'hea_rock_scree_01', 'hea_rock_scree_02', 'hea_rock_scree_03',
    'hea_rock_scree_04', 'hea_rock_scree_05', 'hea_rock_scree_06',
    'hea_rock_scree_sim_01', 'hea_rock_scree_sim_02', 'hea_rock_scree_sim_03',
    'hea_rock_scree_sim_04', 'hea_rock_scree_sim_05', 'hea_rock_scree_sim_06',
    'hea_rock_scree_sim_07', 'hea_rock_scree_sim_08', 'hea_rock_scree_sim_09',
    'hea_rock_scree_sim_10', 'hea_rock_scree_sim_11', 'hea_rock_stones_aa',
    'hea_rock_stones_ab', 'gap_rock_01', 'gap_rock_02',
    'gap_rock_03', 'gap_rock_04', 'gap_rock_05',
    'gap_rock_06', 'gap_rock_07', 'gap_rock_08',
    'gap_rock_09', 'old_hen_rock_01', 'old_hen_rock_02',
    'old_hen_rock_03', 'old_hen_rock_04', 'old_hen_rock_05',
    'old_hen_rock_06', 'old_hen_rock_07', 'old_hen_rock_08',
    'old_hen_rock_09', 'old_hen_rock_10', 'old_hen_rock_11',
    'old_hen_rock_scree_01', 'old_hen_rock_scree_02', 'old_hen_rock_scree_03',
    'old_hen_rock_scree_04', 'old_hen_rock_scree_05', 'old_hen_rock_scree_06',
    'old_hen_rock_scree_sim_01', 'old_hen_rock_scree_sim_02', 'old_hen_rock_scree_sim_03',
    'old_hen_rock_scree_sim_04', 'old_hen_rock_scree_sim_05', 'old_hen_rock_scree_sim_06',
    'old_hen_rock_scree_sim_07', 'old_hen_rock_scree_sim_08', 'old_hen_rock_scree_sim_09',
    'old_hen_rock_scree_sim_10', 'old_hen_rock_scree_sim_11', 'rio_red_rock_01',
    'rio_red_rock_02', 'rio_red_rock_03', 'rio_red_rock_04',
    'rio_red_rock_05', 'rio_red_rock_06', 'rio_red_rock_07',
    'rio_red_rock_08', 'rio_red_rock_08_l3', 'rio_red_rock_09',
    'roa_rock_01', 'roa_rock_01a', 'roa_rock_02',
    'roa_rock_03', 'roa_rock_04', 'roa_rock_05',
    'roa_rock_06', 'roa_rock_07', 'roa_rock_08',
    'roa_rock_10', 'roa_rock_11', 'roa_rock_hero_01',
    'roa_rock_hero_02', 'roa_rock_hero_03', 'roa_rock_hero_04',
    'roa_rock_hero_05', 'roa_rock_scree_01', 'roa_rock_scree_02',
    'roa_rock_scree_02a', 'roa_rock_scree_03', 'roa_rock_scree_04',
    'roa_rock_scree_05', 'roa_rock_scree_06', 'roa_rock_scree_06a',
    'roa_rock_scree_07', 'roa_rock_scree_sim_01', 'roa_rock_scree_sim_02',
    'roa_rock_scree_sim_03', 'roa_rock_scree_sim_04', 'roa_rock_scree_sim_05',
    'roa_rock_scree_sim_06', 'roa_rock_scree_sim_07', 'roa_rock_scree_sim_08',
    'roa_rock_scree_sim_09', 'roa_rock_scree_sim_10', 'roa_rock_scree_sim_11',
    'roa_rock_stones_ab', 'sca_rock_01', 'sca_rock_02',
    'sca_rock_03', 'sca_rock_04', 'sca_rock_05',
    'sca_rock_06', 'sca_rock_07', 'sca_rock_08',
    'sca_rock_09', 'sca_rock_10', 'sca_rock_11',
    'sca_rock_scree_01', 'sca_rock_scree_02', 'sca_rock_scree_03',
    'sca_rock_scree_04', 'sca_rock_scree_05', 'sca_rock_scree_06',
    'sca_rock_scree_sim_01', 'sca_rock_scree_sim_02', 'sca_rock_scree_sim_03',
    'sca_rock_scree_sim_04', 'sca_rock_scree_sim_05', 'sca_rock_scree_sim_06',
    'sca_rock_scree_sim_07', 'sca_rock_scree_sim_08', 'sca_rock_scree_sim_09',
    'sca_rock_scree_sim_10', 'sca_rock_scree_sim_11', 'sca_rock_shelve_01',
    'sca_rock_shelve_02', 'sca_rock_shelve_03', 'sca_rock_shelve_04',
    'sca_rock_shelve_05', 'tal_rock_01', 'tal_rock_02',
    'tal_rock_03', 'tal_rock_04', 'tal_rock_05',
    'tal_rock_06', 'tal_rock_07', 'tal_rock_08',
    'tal_rock_09', 'tal_rock_10', 'tal_rock_11',
    'tal_rock_12', 'tal_rock_scree_01', 'tal_rock_scree_02',
    'tal_rock_scree_03', 'tal_rock_scree_04', 'tal_rock_scree_05',
    'tal_rock_scree_06', 'tal_rock_scree_sim_01', 'tal_rock_scree_sim_02',
    'tal_rock_scree_sim_03', 'tal_rock_scree_sim_04', 'tal_rock_scree_sim_05',
    'tal_rock_scree_sim_06', 'tal_rock_scree_sim_07', 'tal_rock_scree_sim_08',
    'tal_rock_scree_sim_09', 'tal_rock_scree_sim_10', 'tal_rock_scree_sim_11',
}
