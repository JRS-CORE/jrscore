-- ==========================================================================
--  JRS CORE  |  jrs_goldpanning  |  config.lua
--  gold panning - pan for gold nuggets in rivers and lakes
-- ==========================================================================

Config = {}

Config.Language    = 'en'          -- 'en' or 'ar'
Config.PanItem     = 'goldpan'
Config.Reward      = { item = 'goldnugget', min = 1, max = 2 }
Config.BreakChance = 3             -- % chance the pan breaks on a failed try
Config.Rounds      = 3             -- skill checks in a row (jrs_minigame)
Config.Cooldown    = 5             -- seconds between two pans
Config.MinTime     = 8             -- seconds a pan really takes (server check)

-- fresh water only (no swamps)
Config.Water = {
    [-247856387] = true, [-1504425495] = true, [-1369817450] = true, [-1356490953] = true, [-1781130443] = true,
    [-1300497193] = true, [-1276586360] = true, [-1410384421] = true, [370072007] = true, [650214731] = true,
    [592454541] = true, [-804804953] = true, [1245451421] = true, [-218679770] = true, [-1817904483] = true,
    [-811730579] = true, [-1229593481] = true, [-105598602] = true, [-2040708515] = true, [231313522] = true,
    [2005774838] = true, [-1287619521] = true, [-1308233316] = true, [-196675805] = true,
}
