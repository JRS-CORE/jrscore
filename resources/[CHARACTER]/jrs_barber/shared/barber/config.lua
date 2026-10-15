-- ==========================================================================
--  JRS CORE  |  jrs_barber  |  shared/barber/config.lua
--  Free - barber (hair, beard, hair colour)
-- ==========================================================================

BarberConfig = {}

BarberConfig.framework = "jrs_core"
BarberConfig.MenuCommand = nil           -- e.g. "barber"
BarberConfig.PromptKey = 0x760A9C6F      -- G
BarberConfig.PromptText = nil            -- nil = translated "Open Barber"
BarberConfig.PromptDistance = 2.2

-- ─── Barber chair ──────────────────────────────────────────────────────────
BarberConfig.ChairAnimation   = true    -- sit in the barber chair when the barber opens
BarberConfig.ChairTimeout     = 8000    -- ms allowed to reach the chair
BarberConfig.ChairSettleDelay = 700     -- ms after sitting before the menu opens
BarberConfig.SitPrompt        = true    -- "Sit" prompt next to every barber chair
BarberConfig.SitKey           = 0xCEFD9220 -- E
BarberConfig.SitDistance      = 4.0

BarberConfig.Shops = {
    ["Saint Denis Barber"] = { coords = vector3(2656.3066, -1181.0294, 53.2785) },
    ["Blackwater Barber"]  = { coords = vector3(-815.4733, -1367.094, 42.75088) },
    -- these two shops have no chair in the map: one is placed (chair = { model, heading })
    ["Rhodes Barber"]      = { coords = vector3(1350.788, -1381.203, 83.28922), chair = { model = "p_barberchair01x", heading = 169.47 } },
    ["Annesburg Barber"]   = { coords = vector3(2954.8, 1356.93, 43.65),        chair = { model = "p_barberchair01x", heading = 130.0 } },
    ["Valentine Barber"]   = { coords = vector3(-306.51, 812.79, 119.18) },
    ["Armadillo Barber"]   = { coords = vector3(-3668.18, -2598.0, -13.4) },
}

-- Price per category (new style or new colour).
BarberConfig.Price = {
    hair = 0.25,
    hair_bonnet = 0.25,
    beard = 0.15,
    beards_complete = 0.20,
    beards_chin = 0.15,
    beards_mustache = 0.15,
    beards_chops = 0.15,
}

-- Hair colours (Red Dead Online hair tints).
BarberConfig.HairColours = {
    { tint = 0, hex = "#151515" },
    { tint = 1, hex = "#211f1f" },
    { tint = 2, hex = "#2c1f19" },
    { tint = 3, hex = "#38241a" },
    { tint = 4, hex = "#442b1d" },
    { tint = 5, hex = "#533524" },
    { tint = 6, hex = "#613c27" },
    { tint = 7, hex = "#6b4b35" },
    { tint = 8, hex = "#7a583e" },
    { tint = 9, hex = "#886948" },
    { tint = 10, hex = "#9c7a50" },
    { tint = 11, hex = "#b4935e" },
    { tint = 12, hex = "#c1a06c" },
    { tint = 13, hex = "#d3b47f" },
    { tint = 14, hex = "#ded0a5" },
    { tint = 15, hex = "#491d15" },
    { tint = 16, hex = "#592217" },
    { tint = 17, hex = "#772d19" },
    { tint = 18, hex = "#8c361b" },
    { tint = 19, hex = "#a25336" },
    { tint = 145, hex = "#444341" },
    { tint = 148, hex = "#363638" },
    { tint = 152, hex = "#5f5e63" },
    { tint = 156, hex = "#858488" },
    { tint = 160, hex = "#ababaf" },
    { tint = 161, hex = "#dedee2" },
}
