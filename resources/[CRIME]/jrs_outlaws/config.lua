-- jrs_outlaws | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_outlaws  |  config.lua
--  Random bandit ambushes on the road.
-- ==========================================================================

Config = {
    Language = 'en',                   -- 'en' or 'ar'

    -- After a player walks into an ambush zone (lucky or not) the same player has to wait this long
    -- before the next roll, in milliseconds.
    Cooldown = 60 * 1000,

    -- When the player dies during an ambush the bandits stay this long (friends can still kill them), then vanish.
    LingerAfterDeath = 60 * 1000,

    -- Seconds after which a claimed zone is released even if its player never reported back.
    ClaimTimeout = 20 * 60,
}

-- Values every zone starts from; a zone only lists what it changes.
Config.Defaults = {
    chance        = 10,        -- percent chance that walking into the zone starts an ambush
    triggerRadius = 13.0,      -- metres from the zone centre that start the roll
    giveUpRadius  = 150.0,     -- the ambush ends when the player gets this far away
    maxAlive      = 7,         -- bandits fighting at the same time
    maxTotal      = 10,        -- bandits that can appear during one ambush
    wave          = { min = 1, max = 6 },   -- how many are added each time there is room
    blipSprite    = 953018525, -- sprite of the marker above each bandit
    models        = { 'G_M_M_UniBanditos_01' },
}

Config.Text = {
    en = {
        title = '~e~AMBUSH',  body = 'You are being ambushed by the notorious gang of Blackwater',
        busyBody = 'Bandits are here: run or fight',
        wonTitle = 'You have killed them all',  wonBody = 'Safe travels...',
        fledTitle = 'You have escaped!',        fledBody = 'Keep an eye on the road',
        diedTitle = 'You have been killed!',    diedBody = 'The bandits will stay for a while',
    },
    ar = {
        title = '~e~كمين',  body = 'عصابة بلاك ووتر الشهيرة تنصب لك كميناً',
        busyBody = 'اللصوص هنا: اهرب أو قاتل',
        wonTitle = 'قتلتهم جميعاً',  wonBody = 'رحلة آمنة...',
        fledTitle = 'نجوت!',         fledBody = 'انتبه للطريق',
        diedTitle = 'لقد قُتلت!',    diedBody = 'سيبقى اللصوص لبعض الوقت',
    },
}

-- Zones. `center` is what starts the roll, `spawns` are the points bandits appear at.
Config.Zones = {
    {
        key = 'valentine_ridge', center = vector3(-1406.96, -965.50, 61.75),
        chance = 10, triggerRadius = 18.0, maxAlive = 4, wave = { min = 1, max = 3 },
        spawns = {
            vector3(-1364.36, -966.01, 72.52), vector3(-1369.36, -960.01, 72.52), vector3(-1391.35, -985.01, 72.52),
            vector3(-1480.86, -915.48, 80.94), vector3(-1491.77, -944.48, 88.94),
        },
    },
    {
        key = 'beartooth_pass', center = vector3(-1370.55, 1471.54, 241.58),
        chance = 10,
        spawns = { vector3(-1362.82, 1429.08, 234.41), vector3(-1366.82, 1428.08, 235.41), vector3(-1359.82, 1423.08, 234.41) },
    },
    {
        key = 'citadel_rock', center = vector3(356.13, 442.88, 111.37),
        chance = 10,
        spawns = {
            vector3(466.03, 376.79, 106.49), vector3(450.94, 367.32, 104.30),
            vector3(469.02, 376.98, 106.72), vector3(454.90, 377.63, 105.72),
        },
    },
    {
        key = 'saint_denis_road', center = vector3(2163.16, -1329.42, 42.50),
        chance = 10,
        spawns = {
            vector3(2160.73, -1315.26, 41.35), vector3(2160.73, -1313.26, 41.39),
            vector3(2139.51, -1295.05, 41.32), vector3(2131.51, -1305.36, 41.54),
        },
    },
}
