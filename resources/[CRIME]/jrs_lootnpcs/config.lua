-- jrs_lootnpcs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_lootnpcs  |  config.lua
--  Rewards for looting dead NPCs.
-- ==========================================================================

Config = {
    Language       = 'en',    -- 'en' or 'ar'
    LootWindow     = 5,       -- minutes during which one body can pay out (and cannot pay twice)
    MaxDistance    = 5.0,     -- how close the looter must be to the body (server-checked)
    UseRightTip    = false,   -- true: plain tip on the right; false: card on the left
}

-- Every enabled reward is rolled separately for each looted body.
--   chance  percent chance (0-100) that this reward drops
--   pool    what can drop; one entry is picked at random
Config.Rewards = {
    items = {
        enabled = true, chance = 35,
        pool = {
            { name = 'water',              label = 'Water' },
            { name = 'ammorepeaternormal', label = 'Normal Ammo Repeater' },
            { name = 'ammoriflenormal',    label = 'Normal Ammo Rifle' },
        },
        amount = 1,
    },
    money = {
        enabled = false, chance = 50,
        pool = { 0.5, 1, 1.5 },                 -- dollars
    },
    gold = {
        enabled = false, chance = 5,
        pool = { 1, 2, 3 },                     -- nuggets
    },
    weapons = {
        enabled = false, chance = 10,
        pool = {
            { name = 'WEAPON_REVOLVER_CATTLEMAN', label = 'Cattleman Revolver' },
            { name = 'WEAPON_REPEATER_CARBINE',   label = 'Carbine Repeater' },
            { name = 'WEAPON_RIFLE_VARMINT',      label = 'Varmint Rifle' },
        },
    },
}

Config.Text = {
    en = {
        title = 'Loot', got = 'You got ', dollars = ' $', nuggets = ' nugget',
        nothing = {
            items = 'This person had no items on him.', money = 'This person had no money on him.',
            gold = 'This person had no gold on him.', weapons = 'This person had no weapon on him.',
        },
        full = { items = "You can't carry any more ITEMS.", weapons = "You can't carry any more WEAPONS." },
    },
    ar = {
        title = 'النهب', got = 'حصلت على ', dollars = ' $', nuggets = ' قطعة ذهب',
        nothing = {
            items = 'هالشخص ما معه أغراض.', money = 'هالشخص ما معه فلوس.',
            gold = 'هالشخص ما معه ذهب.', weapons = 'هالشخص ما معه سلاح.',
        },
        full = { items = 'ما تقدر تشيل أغراض أكثر.', weapons = 'ما تقدر تشيل أسلحة أكثر.' },
    },
}
