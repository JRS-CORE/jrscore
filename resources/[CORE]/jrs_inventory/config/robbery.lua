-- ==========================================================================
--  JRS CORE  |  jrs_inventory  |  config/robbery.lua
--  JRS Inventory unified resource: inventory + weapons + storage + ground + robbery + transactional trade
-- ==========================================================================

-- JRS Inventory - Player robbery / search settings
-- This system is fully integrated into jrs_inventory. No separate robbery resource is required.
Config.Robbery = {
    Enabled = true,

    -- Interaction / validation
    PromptControlHash = 0x27D1C284, -- INPUT_PICKUP / E-style prompt used by this server
    PromptDistance = 0.75,
    ServerDistance = 2.0,
    SessionTimeoutMs = 30000,
    ActionCooldownMs = 100,
    MaxTransferAmount = 100000,
    LockTargetToOneSearcher = true,

    -- What can be taken from the searched player
    AllowItems = true,
    AllowWeapons = true,
    AllowMoney = true,
    MoneyStealPercent = 0.10, -- Robbers can only steal up to 10% of victim cash
    MoneyStealWindowMinutes = 30, -- that 10% is a total per victim for this long, not per take
    AllowGold = true,
    AllowDirtyMoney = true,

    -- Prevent items configured as personal / non-removable from being stolen
    BlockPersonalItems = true,

    Restrictions = {
        ProtectedZones = {
            Enabled = true,
            BlockSearcherInside = true,
            BlockTargetInside = true,
            Zones = {
                { name = "Valentine",   x = -308.0,  y = 806.0,   z = 119.0, radius = 180.0 },
                { name = "Blackwater",  x = -815.0,  y = -1318.0, z = 43.0,  radius = 220.0 },
                { name = "Saint Denis", x = 2512.0,  y = -1306.0, z = 48.0,  radius = 360.0 },
                { name = "Rhodes",      x = 1232.0,  y = -1291.0, z = 76.0,  radius = 180.0 },
                { name = "Strawberry",  x = -1790.0, y = -387.0,  z = 160.0, radius = 170.0 },
                { name = "Annesburg",   x = 2931.0,  y = 1282.0,  z = 44.0,  radius = 190.0 },
                { name = "Armadillo",   x = -3731.0, y = -2601.0, z = -13.0, radius = 190.0 },
                { name = "Tumbleweed",  x = -5510.0, y = -2940.0, z = -2.0,  radius = 190.0 },
            }
        },

        Police = {
            RequirementEnabled = true,
            MinimumOnline = 1,
            Jobs = {
                police = true,
                sheriff = true,
                marshal = true,
            },
            NotifyOnRobbery = true,
            AlertCooldownMs = 60000,
            IncludeCoordinates = false,
            AlertMessage = "A player robbery has been reported.",
        },

        -- Server-local hours. 20 -> 6 means 20:00 through 05:59.
        -- The client clock is never trusted because it can be spoofed.
        NightOnly = {
            Enabled = true,
            StartHour = 20,
            EndHour = 6,
        },
    },

    ShowWeaponSerial = true,
    Debug = false,
}
