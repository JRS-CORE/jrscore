-- jrs_saloons | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- ==========================================================================
--  JRS CORE  |  jrs_saloons  |  config.lua
--  One storage point (and one cooking spot for jrs_crafting) per saloon job.
-- ==========================================================================

Config = {
    PromptKey    = 0x760A9C6F,   -- G
    UseDistance  = 1.5,          -- metres from the storage point
    StorageLimit = 5000,         -- slots per saloon storage

    ShowBlips    = true,
    BlipSprite   = 1879260108,   -- used when a saloon has no sprite of its own

    -- Prompt text (the game font has no Arabic glyphs: keep this English)
    Text = {
        press   = 'Press',
        storage = 'Open storage ',
    },
}

-- saloon{ job, name, blip, storage, cook, sprite?, meals? }
local function saloon(def)
    def.cookName = def.cookName or (def.name .. ' cooker')
    return def
end

Config.Saloons = {
    saloon{ job = 'smithfields',       name = "Smithfield's",     blip = vector3(-313.17, 804.77, 118.98),   storage = vector3(-313.46, 804.79, 118.98),   cook = vector3(-313.99, 807.50, 118.98),
            -- extra recipes this saloon can cook (read by jrs_crafting through the cook point)
            meals = {
                {
                    label = 'Meat with oregano', note = 'InvMax = 10', recipe = 'Recipe: 1x Meat, 1x Oregano',
                    items = { { name = 'meat', count = 1 }, { name = 'oregano', count = 1 } },
                    reward = { { name = 'consumable_game_meat_oregano_cooked', count = 1 } },
                    kind = 'item', category = 'food', animation = 'spindlecook',
                },
            } },
    saloon{ job = 'keanes',            name = "Keane's",          blip = vector3(-244.65, 765.42, 118.15),   storage = vector3(-237.25, 768.21, 118.11),   cook = vector3(-239.20, 770.95, 118.10) },
    saloon{ job = 'emeraldsaloon',     name = 'Emeraldsaloon',    blip = vector3(1444.90, 369.23, 89.90),    storage = vector3(1451.57, 371.34, 89.89),    cook = vector3(1450.96, 369.29, 89.89) },
    saloon{ job = 'bastille',          name = 'Bastille',         blip = vector3(2627.90, -1220.41, 53.25),  storage = vector3(2639.90, -1226.34, 53.38),  cook = vector3(2640.16, -1222.92, 53.38) },
    saloon{ job = 'doyles',            name = "Doyle's",          blip = vector3(2793.56, -1174.50, 47.92),  storage = vector3(2791.61, -1168.46, 48.02),  cook = vector3(2792.86, -1167.61, 47.93) },
    saloon{ job = 'parlour',           name = 'Parlour',          blip = vector3(1353.65, -1377.04, 80.53),  storage = vector3(1339.55, -1375.40, 80.48),  cook = vector3(1340.32, -1374.12, 80.48) },
    saloon{ job = 'oldlight',          name = 'OldLight',         blip = vector3(2952.46, 523.38, 45.49),    storage = vector3(2947.41, 529.00, 45.33),    cook = vector3(2947.70, 528.09, 45.34) },
    saloon{ job = 'blackwatersaloon',  name = 'Blackwater',       blip = vector3(-808.59, -1319.44, 43.67),  storage = vector3(-819.82, -1318.14, 43.68),  cook = vector3(-818.70, -1318.92, 43.68), cookName = 'blackwater cooker' },
    saloon{ job = 'armadillosaloon',   name = 'Armadillo',        blip = vector3(-3708.08, -2600.95, -13.30), storage = vector3(-3697.94, -2600.66, -13.32), cook = vector3(-3699.77, -2592.32, -13.32), cookName = 'armadillo cooker' },
    saloon{ job = 'tumbleweedsaloon',  name = 'Tumbleweedsaloon', blip = vector3(-5514.49, -2918.09, -1.73), storage = vector3(-5518.93, -2906.76, -1.75), cook = vector3(-5516.95, -2905.78, -1.75), cookName = 'Tumbleweed cooker' },
}
