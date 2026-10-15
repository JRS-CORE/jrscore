-- ==========================================================================
--  JRS CORE  |  jrs_guarma  |  config.lua
--  Guarma - sail between Saint Denis and Guarma
-- ==========================================================================

Config = {}

Config.Language = 'en'          -- 'en' or 'ar'
Config.Key      = 0x760A9C6F    -- G (hold)
Config.BlipSprite = 2033397166

-- payment: { label, money = dollars } or { label, item = 'name', amount = n (0 = only needs to carry it) }
Config.Ports = {
    saint_denis = {
        label = 'Saint Denis Harbour', to = 'guarma', guarma = false,
        port = vector4(2671.13, -1552.96, 46.47, 0.0),
        payments = {
            { label = 'Ticket to Guarma ($5)', money = 5 },
        },
        loading = { 'Guarma', 'El Bahia De La Paz', 'The boat has sailed for Guarma harbour.' },
    },
    guarma = {
        label = 'Guarma Harbour', to = 'saint_denis', guarma = true,
        port = vector4(1266.666, -6852.54, 43.318, 62.74),
        payments = {
            { label = 'Sail back to Saint Denis', money = 0 },
        },
        loading = { 'Mainland', 'Saint Denis Harbour', 'The boat has sailed for Saint Denis.' },
    },
}

-- where you arrive
Config.Arrive = {
    guarma      = vector4(1269.242, -6854.48, 43.318, 244.54),
    saint_denis = vector4(2670.899, -1548.12, 45.969, 0.72),
}
