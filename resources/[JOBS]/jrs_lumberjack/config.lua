-- jrs_lumberjack | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_lumberjack  |  config.lua
--  Chop trees with an axe for wood and forest goods.
-- ==========================================================================

Config = {
    Language   = 'en',                 -- 'en' or 'ar' (prompts stay English: the game font has no Arabic)

    Axe        = 'hatchet',            -- inventory item used as the axe
    Swings     = { min = 1, max = 5 }, -- swings a tree takes (the server decides)
    Cooldown   = 60,                   -- minutes before the same spot can be chopped again
    TreeReach  = 1.4,                  -- metres from the trunk

    -- Skill bar (jrs_minigame): milliseconds the bar takes. Smaller = faster = harder.
    BarTime    = { easiest = 3800, hardest = 2000 },
    BarGap     = 7,

    -- Keys
    StartKey   = 0xD9D0E1C0,           -- SPACE (hold)
    CancelKey  = 0x3B24C470,           -- F (hold)
    SwingKey   = 0x07B8BEAF,           -- left mouse button

    -- Axe wear
    Wear = {
        startsAt     = 99,             -- durability of a new axe
        riskBelow    = 20,             -- below this durability the axe may break on a use
        breakOneIn   = { min = 1, max = 3 },   -- rolls 1..n; a 1 breaks it
    },

    ChanceRange = 20,                  -- loot roll is 1..this; an item drops when its chance is at least the roll
}

-- Chopping is not allowed inside these towns
Config.ForbiddenTowns = {
    'Annesburg', 'Armadillo', 'Blackwater', 'Lagras', 'Rhodes',
    'StDenis', 'Strawberry', 'Tumbleweed', 'Valentine', 'Vanhorn',
}

-- What a good swing can give: name, label, chance (out of Config.ChanceRange), most pieces
Config.Loot = {
    { name = 'sap',    label = 'Sap',       chance = 8,  most = 2 },
    { name = 'honey',  label = 'Honey',     chance = 5,  most = 2 },
    { name = 'wood',   label = 'Soft Wood', chance = 10, most = 5 },
    { name = 'hwood',  label = 'Hard Wood', chance = 8,  most = 5 },
    { name = 'rubber', label = 'Rubber',    chance = 5,  most = 4 },
    { name = 'fibers', label = 'Fibers',    chance = 8,  most = 5 },
    { name = 'pulp',   label = 'Pulp',      chance = 10, most = 3 },
}

Config.Text = {
    en = {
        cut = 'Cut', cutTitle = 'Cut down the tree', useAxe = 'Use Hatchet', stop = 'Keep/Exit',
        got = 'You got ', nothing = 'You got nothing', bagFull = "You can't carry any more ",
        axeBroke = 'Your axe broke', noAxe = "You don't have an axe", cooling = 'Nothing to chop here',
        durability = 'Durability',
        slips = {
            'That almost went into my foot...', 'Careful, do not hit your knee with the axe!',
            "That's an axe, not a hammer!", 'Slipped!', 'The branch was rotten...', 'You should have hit the tree by now!',
        },
    },
    ar = {
        cut = 'Cut', cutTitle = 'Cut down the tree', useAxe = 'Use Hatchet', stop = 'Keep/Exit',
        got = 'حصلت على ', nothing = 'ما حصلت شي', bagFull = 'ما تقدر تشيل أكثر ',
        axeBroke = 'انكسر فأسك', noAxe = 'ما عندك فأس', cooling = 'ما فيه شي تقطعه هنا',
        durability = 'المتانة',
        slips = {
            'كانت بتجي في رجلي...', 'انتبه لا تضرب ركبتك بالفأس!', 'هذا فأس مو مطرقة!',
            'زلقت!', 'الغصن كان خربان...', 'المفروض ضربت الشجرة من زمان!',
        },
    },
}

-- Tree models that can be chopped
Config.Trees = {
    'p_tree_birch_03', 'p_tree_birch_03b', 'p_tree_birch_03_lg',
    'p_tree_birch_03_md', 'p_tree_birch_03_md_a', 'p_tree_birch_04',
    'p_tree_birch_04_lg', 'p_tree_birch_multistem', 'p_tree_birch_tall_sap',
    'p_tree_poplar_01', 'p_tree_poplar_02', 'p_tree_riv_poplar_01',
    'p_tree_riv_poplar_02', 'p_tree_willow_01', 'p_tree_willow_02',
    'rdr2_tree_gimlet', 'rdr2_tree_riverbirch', 'rdr_nrml_branch_aa_sim',
    'p_tree_birch_01_sapling', 'p_tree_birch_02_sapling', 'p_tree_birch_03_sapling',
    'rdr2_tree_rata01', 'rdr2_tree_rata02', 'p_sap_fir_aa_sim',
    'p_sap_fir_ab_sim', 'p_sap_fir_ac_sim', 'p_sap_fir_snow_aa_sim',
    'p_sap_fir_snow_ab_sim', 'p_sap_fir_snow_ac_sim', 'p_tree_cedar_03b_snow',
    'p_tree_cedar_03b_snow_deep', 'p_tree_cedar_decor_01', 'p_tree_cedar_decor_02',
    'p_tree_cedar_s_deep_02_c', 'p_tree_douglasfir_01', 'p_tree_douglasfir_02',
    'p_tree_douglasfir_03', 'p_tree_douglasfir_04', 'p_tree_douglasfir_05',
    'p_tree_douglasfir_snow_01', 'p_tree_douglasfir_snow_01a', 'p_tree_douglasfir_snow_02',
    'p_tree_douglasfir_snow_03', 'p_tree_douglasfir_snow_03a', 'p_tree_douglasfir_snow_03b',
    'p_tree_douglasfir_snow_03c', 'p_tree_douglasfir_snow_03d', 'p_tree_douglasfir_snow_04',
    'p_tree_douglasfir_snow_04a', 'p_tree_douglasfir_snow_05', 'p_tree_douglasfir_snow_05a',
    'p_tree_lodgepole_01', 'p_tree_lodgepole_02', 'p_tree_lodgepole_02_bv',
    'p_tree_lodgepole_02_bv_l', 'p_tree_lodgepole_02_bv_s', 'p_tree_lodgepole_03',
    'p_tree_lodgepole_04', 'p_tree_lodgepole_05', 'p_tree_lodgepole_06',
    'p_tree_lodgepole_07', 'p_tree_lodgepole_07a', 'p_tree_lodgepole_roots_01',
    'p_tree_lodgepole_snow_01', 'p_tree_lodgepole_snow_01a', 'p_tree_lodgepole_snow_02',
    'p_tree_lodgepole_snow_02a', 'p_tree_lodgepole_snow_02b', 'p_tree_lodgepole_snow_03',
    'p_tree_lodgepole_snow_04', 'p_tree_longleafpine_01', 'p_tree_longleafpine_02',
    'p_tree_longleafpine_03', 'p_tree_longleafpine_04', 'p_tree_pine_burnt_01',
    'p_tree_pine_burnt_01a', 'p_tree_pine_burnt_02', 'p_tree_pine_burnt_02a',
    'p_tree_pine_burnt_log_aa', 'p_tree_pine_burnt_log_ab', 'p_tree_pine_ponderosa_01',
    'p_tree_pine_ponderosa_02', 'p_tree_pine_ponderosa_03', 'p_tree_pine_ponderosa_04',
    'p_tree_pine_ponderosa_05', 'p_tree_pine_ponderosa_06', 'p_tree_pine_ponderosa_07',
    'p_tree_ponderosa_sap_01', 'p_tree_ponderosa_sap_02', 'p_tree_ponderosa_sap_03',
    'p_tree_whitepine_01', 'p_tree_whitepine_02', 'p_tree_whitepine_03',
    'p_tree_whitepine_04', 'p_tree_whitepine_05', 'p_tree_whitepine_06',
    'p_tree_whitepine_07', 'p_tree_whitepine_08', 'p_tree_whitepine_09',
    'p_tree_whitepine_10', 'p_tree_whitepine_sap_01', 'p_tree_whitepine_sap_02',
    'p_tree_whitepine_sap_03', 'rdr_pine_branch_aa_sim', 'rdr_pine_branch_ab_sim',
    'rdr2_tree_utahjuniper', 'p_tree_engoak_dead', 'p_tree_fallen_pine_01',
    'p_tree_fallen_pine_01bc', 'p_tree_fallen_pine_02', 'p_tree_lightning_01',
    'p_tree_lightning_02', 'p_tree_lightning_03', 'p_tree_lightning_04',
    'p_tree_maple_03_dead', 'p_tree_pine_dead_01', 'p_tree_pine_dead_02',
    'p_tree_riodel_01', 'p_tree_rusolive_dead', 'p_tree_rusolive_dead001',
    'p_tree_w_r_cedar_dead', 'p_tree_w_r_cedar_dead_01', 'p_tree_w_r_cedar_dead_02',
    'p_tree_mesquite_01', 'p_tree_mesquite_01_dead', 'p_tree_maple_dead_s_01',
    'p_tree_maple_02', 'p_tree_maple_03', 'p_tree_maple_03_lg',
    'p_tree_maple_03_lg_m', 'p_tree_maple_03_lg_os', 'p_tree_maple_03_md',
    'p_tree_maple_03_md_bv', 'p_tree_maple_03_md_bv_l', 'p_tree_maple_03_md_bv_s',
    'p_tree_maple_03_os', 'p_tree_maple_04_md', 'p_tree_maple_04_md_m',
    'p_tree_maple_05_lg', 'p_tree_maple_05_lg_ch', 'p_tree_maple_05_lg_ch2',
    'p_tree_maple_05_lg_m', 'p_tree_maple_bent_01', 'p_tree_maple_bent_02',
    'p_tree_maple_bent_03', 'p_tree_maple_s_01', 'p_tree_maple_s_02',
    'p_tree_maple_s_03', 'p_tree_maple_s_04', 'p_tree_mapleroot_01',
    'p_tree_mapleroot_02', 'p_tree_riv_maple_01', 'p_tree_riv_maple_04',
    'p_sap_maple_aa_sim', 'p_sap_maple_ab_sim', 'p_sap_maple_ac_sim',
    'p_sap_maple_ad_sim', 'p_sap_maple_ba_sim', 'p_sap_maple_bb_sim',
    'p_sap_maple_bc_sim', 'p_tree_angel_oak', 'p_tree_blue_oak_01',
    'p_tree_cottonwood_01', 'p_tree_cottonwood_02', 'p_tree_cottonwood_03',
    'p_tree_cottonwood_04', 'p_tree_engoak_01', 'p_tree_engoak_01_lg',
    'p_tree_engoak_02', 'p_tree_engoak_moss_01', 'p_tree_engoak_moss_01_os',
    'p_tree_engoak_nbx_01', 'p_tree_hangingtree_moss', 'p_tree_hangingtreebranch',
    'p_tree_hangingtreeoak01', 'p_tree_jacada_01', 'p_tree_liveoak_01',
    'p_tree_liveoak_moss_01', 'p_tree_oak_01', 'p_tree_oak_braith_03',
    'p_tree_poor_joe_oak', 'p_tree_white_oak_01', 'p_tree_white_oak_01_ch',
    'p_tree_white_oak_02', 'rdr2_tree_beech', 'rdr2_tree_brokentree',
    'rdr2_tree_sycamore', 'p_tree_bamboo_01', 'p_tree_bamboo_01_crt',
    'p_tree_banana_01_crt', 'p_tree_banana_01_md_crt', 'p_tree_banana_01_lg',
    'p_tree_banana_dead_01_lg', 'p_tree_banyan_01', 'p_tree_magnolia_01',
    'p_tree_magnolia_02', 'p_tree_magnolia_02_lg', 'p_tree_magnolia_02_lg_os',
    'p_tree_magnolia_02_md', 'p_tree_magnolia_02_vine', 'p_tree_magnolia_03',
    'p_tree_magnolia_03_crt', 'p_tree_magnolia_04', 'p_tree_mangrove_02',
    'p_tree_mangrove_03', 'p_tree_palm_fan_03a', 'p_tree_palm_fan_04b',
    'p_tree_palm_fan_06', 'p_tree_palm_fan_bea_03b', 'p_tree_palm_fan_low_ba',
    'p_tree_palm_s_01a', 'p_tree_palm_s_01d', 'p_tree_palm_s_01e',
    'p_tree_palm_s_01f', 'p_sap_magnolia_aa_sim', 'p_tree_log_redwood_01',
    'p_tree_redwood_05', 'p_tree_redwood_05_lg', 'p_tree_redwood_05_md',
    'p_tree_redwood_05_mf', 'p_tree_redwood_05_sm', 'p_tree_apple_01',
    'p_tree_burntstump_01', 'p_tree_burntstump_03', 'p_tree_hickory_01',
    'p_tree_hickory_02', 'p_tree_pine_newburnt_01', 'p_tree_pine_newburnt_02',
    'p_tree_pine_newburnt_03', 'p_tree_pine_newburnt_04', 'p_tree_pine_newburnt_log_01',
    'p_tree_pine_newburnt_log_02', 'p_tree_baldcypress_01_dead', 'p_tree_baldcypress_01a',
    'p_tree_baldcypress_01a_os', 'p_tree_baldcypress_02', 'p_tree_baldcypress_02_os',
    'p_tree_baldcypress_02_sm_a', 'p_tree_baldcypress_03', 'p_tree_baldcypress_03_dead',
    'p_tree_baldcypress_03_script', 'p_tree_baldcypress_04_dead', 'p_tree_baldcypress_04_sm_a',
    'p_tree_baldcypress_04a', 'p_tree_baldcypress_05', 'p_tree_baldcypress_05_sm_a',
    'p_tree_baldcypress_06a', 'p_tree_baldcypress_06b', 'p_tree_baldcypress_05a',
    'p_tree_baldcypress_07', 'p_tree_baldcypress_grave', 'p_tree_baldcypress_knees_01',
    'p_tree_baldcypress_knees_02', 'p_tree_branch_01_swamp', 'p_tree_branch_02_swamp',
    'p_tree_log_01_swamp', 'p_tree_log_01_swamp_sim', 'p_tree_stump_01_swamp',
    'p_tree_stump_02_swamp', 'p_sap_cypress_aa_sim', 'p_sap_cypress_ab_sim',
}
