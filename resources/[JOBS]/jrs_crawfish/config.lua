-- jrs_crawfish | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_crawfish  |  config.lua
--  Search crawfish holes along the water, then harvest the crawfish for meat.
-- ==========================================================================

Config = {
    Language = 'en',                 -- 'en' or 'ar'

    -- jrs_progressbar look while searching / harvesting
    Bar = { theme = 'linear', color = 'rgb(217, 212, 199)', width = '20vw', focus = false },

    SearchTime   = { min = 5000, max = 10000 },   -- ms a search takes
    SearchDelay  = 600,                           -- seconds before the same hole can be searched again
    HarvestTime  = 5000,                          -- ms to harvest one crawfish
    HoleReach    = 1.5,                           -- metres from a hole
    PromptKey    = 0x760A9C6F,                    -- G

    -- What one search finds. A number, or { min, max } for a random count.
    SearchCount  = 1,

    Crawfish     = { item = 'animal_crawfish', label = 'Crawfish' },

    -- What a harvest turns one crawfish into. Number or { min, max }.
    Meat = { item = 'provision_meat_crustacean', label = 'Raw Crustacean Meat', amount = 1 },

    -- Set true if another script already handles using the crawfish item.
    CustomUse = false,

    -- Rare extras from a search
    Extras = {
        enabled = false,
        chance  = 2,                 -- percent per search
        most    = 1,                 -- different extras per search
        pool    = {
            -- { item = 'itemname', amount = 1 },
            -- { item = 'itemname', amount = { 0, 1 } },   -- a 0 in the range makes the item rarer
        },
    },
}

Config.Holes = {
    -- Crawdad Willies
    vector3(2021.29, -1789.33, 40.52), vector3(2027.25, -1722.36, 40.61), vector3(2042.19, -1885.94, 40.39),
    vector3(2045.33, -1785.77, 40.68), vector3(2058.19, -1866.73, 40.50), vector3(2087.13, -1859.83, 40.52),
    -- Lagras / Lakay
    vector3(2176.27, -693.79, 40.66), vector3(2216.03, -679.24, 40.63), vector3(2253.83, -549.89, 40.60),
    vector3(2258.77, -720.30, 40.48), vector3(2301.91, -515.66, 40.82), vector3(2339.40, -544.33, 40.83),
}

Config.Text = {
    en = {
        prompt = 'Crawfish Hole', search = 'Search Crawfish Hole', searching = 'Searching Crawfish Hole...',
        harvesting = 'Harvesting...',
        busy = 'This Crawfish Hole is currently being searched!', recent = 'This Crawfish Hole has been searched too recently...',
        far = 'You are too far away!', noSpace = 'Not enough space in your inventory!',
        found = 'You found {count} x {item}!', foundExtra = 'You found something else!', foundNothing = 'You did not find anything!',
        notSearching = 'You are not searching for anything...',
        harvested = 'You harvested {count} x {item}!', alreadyHarvesting = 'You are already harvesting!',
        nothingToHarvest = 'You have nothing to harvest!', notHarvesting = 'You are not harvesting...',
    },
    ar = {
        prompt = 'جحر الجمبري', search = 'ابحث في جحر الجمبري', searching = 'جارٍ البحث في الجحر...',
        harvesting = 'جارٍ الحصاد...',
        busy = 'أحد يبحث في هذا الجحر حالياً!', recent = 'تم البحث في هذا الجحر قبل قليل...',
        far = 'أنت بعيد جداً!', noSpace = 'لا توجد مساحة كافية في حقيبتك!',
        found = 'وجدت {count} × {item}!', foundExtra = 'وجدت شيئاً آخر!', foundNothing = 'لم تجد شيئاً!',
        notSearching = 'أنت لا تبحث عن شيء...',
        harvested = 'حصدت {count} × {item}!', alreadyHarvesting = 'أنت تحصد بالفعل!',
        nothingToHarvest = 'ليس عندك ما تحصده!', notHarvesting = 'أنت لا تحصد...',
    },
}
