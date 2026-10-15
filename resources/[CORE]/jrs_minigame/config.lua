-- jrs_minigame | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_minigame  |  config.lua
--  Skill bar: a bar fills up, the player has to hit E (or click) while it is inside the marked zone.
-- ==========================================================================

Config = {
    MinZone         = 12,      -- the zone is never narrower than this many percent of the bar
    MaxZone         = 60,
    ZoneStart       = { min = 15, max = 70 },     -- where the zone may begin (percent of the bar)

    -- Missing makes the next bars faster (less time), like losing your nerve.
    FatigueStep     = 0.1,     -- time lost per miss, as a share of the base time
    FatigueFloor    = 0.4,     -- never faster than this share of the base time
    RecoverEvery    = 15000,   -- ms; every period one step is regained
    FrustratedBelow = 0.5,     -- below this share the player is told they are frustrated
}

Config.Text = {
    en = { tip = 'Press E (or click) inside the line', bar = 'Press E in the line', hint = 'or click',
           frustrated = 'You are frustrated', calm = 'You are calm again' },
    ar = { tip = 'اضغط E (أو انقر) داخل الخط', bar = 'اضغط E داخل الخط', hint = 'أو انقر',
           frustrated = 'أنت متوتر', calm = 'هديت' },
}
