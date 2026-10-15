-- ==========================================================================
--  JRS CORE  |  Gameplay
--  jrs_core configuration
-- ==========================================================================
Config = Config or {}


-- --------------------------------------------------------------------------
--  Gameplay
-- --------------------------------------------------------------------------
do
-- JRS gameplay controls.
-- These settings are implemented independently for jrs_core and are safe to toggle per feature.

Config.Gameplay = Config.Gameplay or {}

-- JRS PVP & Combat System
Config.Gameplay.PVP = false                     -- Default state for player combat (PVP)
Config.Gameplay.PVPToggle = true                -- Allows players to toggle their PVP status (/pvp or BaseMenu)
Config.Gameplay.CommandOnOffPVP = 'pvp'         -- Command to toggle PVP status (default: 'pvp')
Config.Gameplay.PVPCooldown = 5                 -- Cooldown in seconds between PVP toggles (anti-spam)
Config.Gameplay.PVPBlockInCombat = true         -- Block disabling PVP while in active combat
Config.Gameplay.PVPCombatDuration = 10          -- Seconds a player remains tagged "in combat" after dealing/taking damage

-- PVP HUD icon: disabled in jrs_core; jrs_metabolism now owns this display
Config.Gameplay.PVPHud = {
    Enabled = false,
    IdleFade = false,       -- Enable the idle fade behaviour
    IdleFadeSeconds = 5,    -- Seconds of no movement before it fades out
}
-- Forces "Free Aim" targeting every frame (no controller aim assist / snap-to-target).
-- The lock-on half (no square-up while holding a gun, no lock-on to players) lives in
-- config/gamepad.lua -> Config.Gamepad.AimAssist.
Config.Gameplay.DisableAutoAim = true
Config.Gameplay.DisableHeadshots = false
Config.Gameplay.DisableGrapples = false
Config.Gameplay.DisableMeleeTakeDowns = false

-- Block only the native F4 key so it cannot open the RDR2 item/quick-select wheel.
-- This does NOT disable TAB / the normal weapon wheel.
Config.Gameplay.DisableF4ItemWheel = true
Config.Gameplay.F4ControlHash = 0x1F6D95E5

-- Player abilities. EagleEye keeps backward compatibility with Config.Eagle_Eye.
Config.Gameplay.EagleEye = Config.Eagle_Eye ~= false
Config.Gameplay.DeadEye = true

-- HUD core visibility.
Config.Gameplay.HidePlayerCores = false
Config.Gameplay.HideHorseCores = false
Config.Gameplay.HideDeadEyeCoreOnly = false

-- jrs_core historically disabled health auto recharge. Override=true preserves that behavior.
-- Set Override=false if another script should control the multiplier.
Config.Gameplay.HealthRecharge = {
    Override = false,
    Multiplier = 1.0,
}

-- Disabled by default so metabolism/stamina resources can keep full control.
Config.Gameplay.StaminaRecharge = {
    Override = false,
    Multiplier = 1.0,
}

-- RDR2 mercy-kill support for downed animals.
Config.Gameplay.MercyKill = {
    Enabled = false,
    RefreshIntervalMs = 30000,
}

-- Disable selected native RDR prompt families. Keep disabled unless needed.
-- Common types: 1 eat/pour/take, 2 open/close container, 3 loot, 5 pickup/drop,
-- 7 lock-on actions, 8 sit, 12 mount.
Config.Gameplay.DisabledPromptTypes = {
    Enabled = false,
    Types = { 1, 2, 3 },
}

-- Replace the native focus prompt name shown when looking at another player.
-- Mode: "TEXT" => Text only, "ID" => Text + server ID.
Config.Gameplay.PlayerFocus = {
    Enabled = false,
    Mode = "TEXT",
    Text = "STRANGER",
    UpdateIntervalMs = 500,
}
end


-- --------------------------------------------------------------------------
--  Gamepad
-- --------------------------------------------------------------------------
do
-- JRS controller (gamepad) support.
--
-- Two jobs:
--   1. AimAssist - no aim assist / lock-on for anyone (free aim itself is forced by
--      Config.Gameplay.DisableAutoAim in config/gameplay.lua).
--   2. PadGuard  - keyboard hotkeys that scripts poll with IsControlJustPressed & co.
--      are ALSO bound to controller buttons, so a controller player tapping a normal
--      gameplay button popped inventories / anim menus / hands-up / chat. A resource
--      that lists '@jrs_core/shared/pad_guard.lua' first in client_scripts gets ITS
--      hashes below gated while the last input device is a controller. Keyboard +
--      mouse is never touched, and nothing is gated while a NUI / menu has focus (so
--      menu navigation keeps working on the pad).
--
-- Policies are per resource on purpose: the same hash means different things in
-- different scripts (X is "raise hands" in jrs_animmenu but the melee block while
-- drinking in jrs_metabolism), so a hash is only gated inside the resource listed.
--
-- Modes:
--   'hold'  - on the pad the hotkey only fires after being held HoldMs (a tap does
--             nothing). Keeps the feature reachable from the controller.
--   'block' - never fires from the pad (feature has no sane controller use).
--   'double'- on the pad the hotkey only fires on a quick double tap (two presses
--             within DoubleTapMs). One tap or a long hold does nothing.
-- In both modes the script's own DisableControlAction on that hash is skipped on
-- the pad, because there the hash is a real gameplay button.
--
-- To find other scripts that still react to controller buttons: type /paddiag in F8,
-- press the buttons, and read the "[pad-guard]" lines (resource + hash). Only
-- resources that include the guard can report, so add the guard line first.

Config.Gamepad = Config.Gamepad or {}

Config.Gamepad.AimAssist = {
    DisableLockonWhenArmed = false, -- Disabled: calling SetPlayerLockon(player, false) breaks aim zoom/over-the-shoulder camera on KBM and controller
    DisableFriendlyLockon = true,   -- never lock onto other players
}

Config.Gamepad.PadGuard = {
    Enabled = true,
    HoldMs = 600,
    DoubleTapMs = 350,
    Resources = {
        jrs_inventory = {
            [0xC1989F95] = 'double', -- I   open inventory: double tap on the pad (single tap/hold opened it by accident)
        },
        jrs_animmenu = {
            [0x80F28E95] = 'double', -- L   open animation menu: double tap on the pad
            [0x8CC9CD42] = 'hold',   -- X   raise hands
            [0x4CC0E2FE] = 'hold',   -- B   point
        },
        jrs_chat = {
            [0x9720FCEE] = 'block',  -- T   open chat (no typing on a pad)
        },
        jrs_admin = {
            [0x3C3DD371] = 'block',  -- PgDn admin panel (admins: keyboard or command)
        },
        jrs_pets = {
            [0x80F28E95] = 'hold',   -- L = INPUT_PLAYER_MENU: pet whistle (pad D-pad menu button)
        },
    },
}

-- Controller control of NUI pages (inventory, stores, menus...). Any resource
-- whose page loads nui://jrs_core/html/jrs-pad.js and whose client_scripts start
-- with '@jrs_core/shared/pad_guard.lua' can be driven with the pad while it holds
-- NUI focus: left stick = cursor, A = click/drag, B = back (Escape), X = right
-- click, Y = on-screen keyboard, D-pad = jump between buttons, RS = scroll,
-- LB/RB = tabs, LT/RT = page up/down.
Config.Gamepad.UI = {
    Enabled = true,
    CursorSpeed = 1.0,   -- multiplier
    ScrollSpeed = 1.0,   -- multiplier
}
end


-- --------------------------------------------------------------------------
--  Wildlife
-- --------------------------------------------------------------------------
do
-- JRS animal population controller.
-- Kept completely separate from human/wagon traffic so hunting is not
-- affected by adaptive performance levels or nearby player counts.

Config.Animals = {
    enabled = true,

    -- Red Dead Online style wildlife: sparse, a few animals near the player.
    -- 1.0 = full story-mode density (far too many). ~0.4 matches RDO free roam.
    ambientFrequency = 0.4,
    scenarioFrequency = 0.4,
    pedRangeMultiplier = 1.0,

    -- Animal density used while the local player is standing inside ANY jrs_safezone
    -- (cities, towns, camps, RP zones, house safezones).
    -- Wildlife and predators should never wander through or spawn inside safezones.
    cityFrequency = 0.0,

    -- Ambient Wildlife Spawner
    -- Ensures wild animals spawn abundantly and naturally across all biomes in the wilderness.
    Spawner = {
        enabled = true,
        checkIntervalMs = 30000, -- RDO-style: slow, sparse top-up
        targetNearbyAnimals = 2, -- RDO-style: a couple of animals around, not herds
        maxNearbyAnimals = 3,    -- Hard cap nearby before halting spawns
        detectionRadius = 90.0,  -- Radius around player to count existing animals
        spawnMinDistance = 45.0, -- Minimum distance from player to spawn an animal
        spawnMaxDistance = 90.0, -- Maximum distance from player to spawn an animal
        despawnDistance = 150.0, -- Cleanup distance when player moves away
        groupSpawnChance = 0.10, -- 10% chance to spawn a pair
        debug = false,
    },

    -- Predator quota. Keeps bears, wolves, cougars, panthers active in the wilderness.
    Predators = {
        enabled = true,
        detectionRadius = 160.0,  -- Radius used to count predators already nearby
        -- RDO-style: predators are a rare encounter, not a constant threat.
        -- Checks run every 30s: 0.02 ~ one every ~25 min by day, 0.05 ~ ~10 min at night.
        targetNearby = 1,         -- Daytime: at most 1 predator around
        targetNearbyNight = 1,    -- Night (20:00-05:00)
        spawnChance = 0.02,       -- Chance per spawner check during the day
        spawnChanceNight = 0.05,  -- Chance per spawner check at night
        spawnMinDistance = 65.0,
        spawnMaxDistance = 115.0, -- Keep below Spawner.despawnDistance (150)
        -- Per-district habitats (RDR2 story/RDO): no cougars in Lemoyne/Heartlands,
        -- panthers only in Bayou Nwa / Bluewater Marsh, grizzlies only in the north/west.
        Pools = {
            -- Panthers live in the Bayou/Bluewater marsh, not around Rhodes.
            swamp       = { 'a_c_alligator_01', 'a_c_alligator_01', 'a_c_panther_01' },
            lemoyne     = { },
            heartlands  = { 'a_c_wolf' },
            cumberland  = { 'a_c_wolf', 'a_c_wolf', 'a_c_bearblack_01' },
            roanoke     = { 'a_c_wolf', 'a_c_bearblack_01', 'a_c_bear_01' },
            mountains   = { 'a_c_wolf', 'a_c_wolf', 'a_c_bear_01', 'a_c_cougar_01' },
            valley      = { 'a_c_wolf', 'a_c_cougar_01', 'a_c_bear_01', 'a_c_bearblack_01' },
            greatplains = { 'a_c_wolf' },
            desert      = { 'a_c_cougar_01', 'a_c_cougar_01', 'a_c_wolf' },
            default     = { 'a_c_wolf' },
        },
    },

    -- Carcass/pelt quality given to spawner animals (0 poor, 1 good, 2 perfect).
    -- Script-created peds have no real kill quality and read back 'Ruined'.
    carcassQuality = 1,

    -- Regional animal pools (aligned 100% with jrs_hunting animal catalog)
    -- Prey only: bears/wolves/cougars/big alligators come ONLY from the rare
    -- Predators quota above, so the normal top-up never spawns extra predators.
    Pools = {
        -- Bayou Nwa / Bluewater Marsh
        swamp = {
            'a_c_alligator_03', 'a_c_boar_01', 'a_c_deer_01',
            'a_c_snakewater_01', 'a_c_muskrat_01', 'a_c_raccoon_01',
            'a_c_possum_01', 'a_c_turtlesnapping_01',
        },
        -- Scarlett Meadows (Rhodes, Bolger Glade, Caliga): wild boar live here
        lemoyne = {
            'a_c_deer_01', 'a_c_buck_01', 'a_c_boar_01', 'a_c_turkey_01',
            'a_c_raccoon_01', 'a_c_skunk_01', 'a_c_possum_01', 'a_c_rabbit_01',
        },
        -- Heartlands (Valentine, Emerald Ranch, oil fields): no boar, no cougar
        heartlands = {
            'a_c_deer_01', 'a_c_buck_01', 'a_c_pronghorn_01', 'a_c_buffalo_01',
            'a_c_coyote_01', 'a_c_fox_01', 'a_c_rabbit_01', 'a_c_badger_01',
            'a_c_skunk_01',
        },
        -- Cumberland Forest (north/east of Valentine)
        cumberland = {
            'a_c_deer_01', 'a_c_buck_01', 'a_c_elk_01', 'a_c_fox_01',
            'a_c_rabbit_01', 'a_c_squirrel_01', 'a_c_beaver_01',
        },
        -- Roanoke Ridge (Annesburg, Van Horn)
        roanoke = {
            'a_c_deer_01', 'a_c_buck_01', 'a_c_boar_01', 'a_c_beaver_01',
            'a_c_fox_01', 'a_c_raccoon_01', 'a_c_rabbit_01',
        },
        -- Grizzlies East & West / Ambarino
        mountains = {
            'a_c_bighornram_01', 'a_c_elk_01', 'a_c_moose_01', 'a_c_deer_01',
            'a_c_buck_01', 'a_c_fox_01', 'a_c_rabbit_01',
        },
        -- Big Valley / Tall Trees (West Elizabeth woods)
        valley = {
            'a_c_elk_01', 'a_c_deer_01', 'a_c_buck_01', 'a_c_fox_01',
            'a_c_rabbit_01', 'a_c_beaver_01', 'a_c_squirrel_01',
        },
        -- Great Plains (Blackwater, Strawberry outskirts)
        greatplains = {
            'a_c_buffalo_01', 'a_c_pronghorn_01', 'a_c_coyote_01',
            'a_c_deer_01', 'a_c_rabbit_01', 'a_c_badger_01', 'a_c_prairiechicken_01',
        },
        -- New Austin (Gaptooth, Cholla, Rio Bravo, Hennigan's): javelina, not boar
        desert = {
            'a_c_armadillo_01', 'a_c_bighornram_01', 'a_c_coyote_01',
            'a_c_pronghorn_01', 'a_c_gilamonster_01', 'a_c_iguanadesert_01',
            'a_c_snakeblacktailrattle_01', 'a_c_javelina_01', 'a_c_rabbit_01',
        },
        -- Unknown spot: animals found almost everywhere
        default = {
            'a_c_deer_01', 'a_c_rabbit_01', 'a_c_fox_01',
        },
    },
}
end


-- --------------------------------------------------------------------------
--  Input wheel
-- --------------------------------------------------------------------------
do
Config.InputWheel = {
    Enabled = true,
    Debug = false,

    -- The native quick-select wheel maps SPACE to INPUT_QUICK_SHORTCUT_ABILITIES_MENU.
    -- jrs_core does not use Rockstar's shortcut-abilities sub-menu, and opening it can
    -- leave hud_quick_select stuck. Block only that wheel-specific action; normal SPACE
    -- (jump / prompts) remains untouched outside the wheel.
    DisableSpaceAbilitiesShortcut = true,
    SpaceAbilitiesControlHash = 0x9CC7A1A4,
    Notify = {
        Enabled = true,
        Event = 'jrs_core:sendAdvancedRightNotification',
        Title = 'Used:',
        Icon = 'inventory_items',
        Color = 'COLOR_WHITE',
        Duration = 5000,
        ShowAmount = true,
    },
    Sync = {
        RequestOnClientStartDelayMs = 3000,
        UseCooldownMs = 350,
        ServerPollMs = 2000,
        RequestAfterUseMs = 900,
    },
    WheelItems = {
        -- Fresh Water & Non-Alcoholic Drinks (Mapped to single-slot stamina restoratives / provisions, NEVER multi-slot tonics)
        water = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Fresh Water" },
        Water = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Fresh Water" },
        consumable_water = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Fresh Water" },
        clean_water_bottle = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Clean Water Bottle" },
        Clean_Water_Bottle = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Clean Water Bottle" },
        water_bottle = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Water Bottle" },
        Water_Bottle = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Water Bottle" },
        waterbottle = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Water Bottle" },
        WaterBottle = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Water Bottle" },
        consumable_raspberrywater = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Berry Water" },

        -- Coffee, Teas & Milks (Mapped to Stamina slot restoratives and provisions - no multi-slot duplicates)
        consumable_coffee = { nativeName = "consumable_restorative", useAmount = 1, notifyText = "Coffee" },
        coffee = { nativeName = "consumable_restorative", useAmount = 1, notifyText = "Coffee" },
        Coffee = { nativeName = "consumable_restorative", useAmount = 1, notifyText = "Coffee" },
        consumable_chocolatecoffee = { nativeName = "consumable_potent_restorative", useAmount = 1, notifyText = "Chocolate Coffee" },
        consumable_coffeecake = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Coffee Cake" },
        ginsengtea = { nativeName = "consumable_special_medicine", useAmount = 1, notifyText = "Ginseng Tea" },
        milk = { nativeName = "consumable_cheese_wedge", useAmount = 1, notifyText = "Fresh Milk" },
        a_milk = { nativeName = "consumable_cheese_wedge", useAmount = 1, notifyText = "Fresh Milk" },
        consumable_milk = { nativeName = "consumable_cheese_wedge", useAmount = 1, notifyText = "Fresh Milk" },

        -- Authentic RDO Alcohol & Moonshines
        beer = { nativeName = "consumable_rum", useAmount = 1, notifyText = "Beer" },
        consumable_beer = { nativeName = "consumable_rum", useAmount = 1, notifyText = "Beer" },
        whiskey = { nativeName = "consumable_whiskey", useAmount = 1, notifyText = "Whiskey" },
        whisky = { nativeName = "consumable_whiskey", useAmount = 1, notifyText = "Whiskey" },
        consumable_whiskey = { nativeName = "consumable_whiskey", useAmount = 1, notifyText = "Whiskey" },
        consumable_whiskey_used = { nativeName = "consumable_whiskey_used", useAmount = 1, notifyText = "Whiskey" },
        moonshine = { nativeName = "consumable_moonshine", useAmount = 1, notifyText = "Moonshine" },
        consumable_moonshine = { nativeName = "consumable_moonshine", useAmount = 1, notifyText = "Moonshine" },
        moonshineapple = { nativeName = "consumable_moonshine", useAmount = 1, notifyText = "Apple Moonshine" },
        moonshineraspberryp = { nativeName = "consumable_moonshine", useAmount = 1, notifyText = "Raspberry Moonshine" },
        wildCiderMoonshine = { nativeName = "consumable_moonshine", useAmount = 1, notifyText = "Wild Cider Moonshine" },
        tropicalPunchMoonshine = { nativeName = "consumable_moonshine", useAmount = 1, notifyText = "Tropical Punch Moonshine" },
        raspberryale = { nativeName = "consumable_rum", useAmount = 1, notifyText = "Raspberry Ale" },
        gin = { nativeName = "consumable_gin", useAmount = 1, notifyText = "Gin" },
        consumable_gin = { nativeName = "consumable_gin", useAmount = 1, notifyText = "Gin" },
        consumable_gin_used = { nativeName = "consumable_gin_used", useAmount = 1, notifyText = "Gin" },
        rum = { nativeName = "consumable_rum", useAmount = 1, notifyText = "Rum" },
        consumable_rum = { nativeName = "consumable_rum", useAmount = 1, notifyText = "Rum" },
        consumable_rum_used = { nativeName = "consumable_rum_used", useAmount = 1, notifyText = "Rum" },
        brandy = { nativeName = "consumable_brandy", useAmount = 1, notifyText = "Brandy" },
        consumable_brandy = { nativeName = "consumable_brandy", useAmount = 1, notifyText = "Brandy" },
        consumable_brandy_used = { nativeName = "consumable_brandy_used", useAmount = 1, notifyText = "Brandy" },
        wine = { nativeName = "consumable_brandy", useAmount = 1, notifyText = "Wine" },
        consumable_wine = { nativeName = "consumable_brandy", useAmount = 1, notifyText = "Wine" },
        vodka = { nativeName = "consumable_whiskey", useAmount = 1, notifyText = "Vodka" },
        tequila = { nativeName = "consumable_whiskey", useAmount = 1, notifyText = "Tequila" },
        consumable_tequila = { nativeName = "consumable_whiskey", useAmount = 1, notifyText = "Tequila Bottle" },

        -- Apples, Peaches & Fresh Produce
        apple = { nativeName = "consumable_apple", useAmount = 1, notifyText = "Fresh Apple" },
        Applee = { nativeName = "consumable_apple", useAmount = 1, notifyText = "Fresh Apple" },
        golden_apple = { nativeName = "consumable_apple", useAmount = 1, notifyText = "Golden Apple" },
        consumable_apple = { nativeName = "consumable_apple", useAmount = 1, notifyText = "Fresh Apple" },
        peach = { nativeName = "consumable_peach", useAmount = 1, notifyText = "Fresh Peach" },
        consumable_peach = { nativeName = "consumable_peach", useAmount = 1, notifyText = "Fresh Peach" },
        orangees = { nativeName = "consumable_peach", useAmount = 1, notifyText = "Fresh Orange" },
        Creekplum = { nativeName = "consumable_peach", useAmount = 1, notifyText = "Creek Plum" },
        consumable_pear = { nativeName = "consumable_pear", useAmount = 1, notifyText = "Pear" },
        carrot = { nativeName = "consumable_carrot", useAmount = 1, notifyText = "Carrot" },
        carrots = { nativeName = "consumable_carrot", useAmount = 1, notifyText = "Carrot" },
        consumable_carrot = { nativeName = "consumable_carrot", useAmount = 1, notifyText = "Carrot" },
        corn = { nativeName = "consumable_corn", useAmount = 1, notifyText = "Corn" },
        consumable_corn = { nativeName = "consumable_corn", useAmount = 1, notifyText = "Corn" },
        consumable_beets = { nativeName = "consumable_beets", useAmount = 1, notifyText = "Beets" },
        potato = { nativeName = "consumable_beets", useAmount = 1, notifyText = "Potato" },
        consumable_celery = { nativeName = "consumable_celery", useAmount = 1, notifyText = "Celery" },
        consumable_tomato = { nativeName = "consumable_apple", useAmount = 1, notifyText = "Fresh Tomato" },
        grapes = { nativeName = "consumable_herb_black_berry", useAmount = 1, notifyText = "Fresh Grapes" },
        consumable_fruitsalad = { nativeName = "consumable_peaches_can", useAmount = 1, notifyText = "Fruit Salad" },
        consumable_veggies = { nativeName = "consumable_corn", useAmount = 1, notifyText = "Cooked Vegetables" },

        -- RDO Canned Provisions
        consumable_apricots_can = { nativeName = "consumable_apricots_can", useAmount = 1, notifyText = "Canned Apricots" },
        consumable_baked_beans_can = { nativeName = "consumable_baked_beans_can", useAmount = 1, notifyText = "Baked Beans" },
        beans = { nativeName = "consumable_baked_beans_can", useAmount = 1, notifyText = "Baked Beans" },
        canned_beans = { nativeName = "consumable_baked_beans_can", useAmount = 1, notifyText = "Baked Beans" },
        consumable_cornedbeef_can = { nativeName = "consumable_cornedbeef_can", useAmount = 1, notifyText = "Corned Beef" },
        consumable_salmon_can = { nativeName = "consumable_salmon_can", useAmount = 1, notifyText = "Canned Salmon" },
        consumable_peaches_can = { nativeName = "consumable_peaches_can", useAmount = 1, notifyText = "Canned Peaches" },
        consumable_sweet_corn_can = { nativeName = "consumable_sweet_corn_can", useAmount = 1, notifyText = "Canned Sweet Corn" },
        consumable_strawberries_can = { nativeName = "consumable_strawberries_can", useAmount = 1, notifyText = "Canned Strawberries" },
        consumable_pineapples_can = { nativeName = "consumable_pineapples_can", useAmount = 1, notifyText = "Canned Pineapples" },
        consumable_peas_can = { nativeName = "consumable_peas_can", useAmount = 1, notifyText = "Canned Peas" },
        consumable_kidneybeans_can = { nativeName = "consumable_kidneybeans_can", useAmount = 1, notifyText = "Kidney Beans" },
        kidneybeans = { nativeName = "consumable_kidneybeans_can", useAmount = 1, notifyText = "Kidney Beans" },

        -- Dry Goods, Rations, Breads & Sweets
        bread = { nativeName = "consumable_bread_chunk", useAmount = 1, notifyText = "Bread" },
        Bread = { nativeName = "consumable_bread_chunk", useAmount = 1, notifyText = "Bread" },
        consumable_bread = { nativeName = "consumable_bread_chunk", useAmount = 1, notifyText = "Bread" },
        consumable_bread_chunk = { nativeName = "consumable_bread_chunk", useAmount = 1, notifyText = "Bread Chunk" },
        consumable_bread_roll = { nativeName = "consumable_bread_roll", useAmount = 1, notifyText = "Bread Roll" },
        consumable_biscuit_box = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Assorted Biscuits" },
        consumable_poundcake = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Pound Cake" },
        consumable_crumbcake = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Crumb Cake" },
        consumable_cupcake = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Cupcake" },
        consumable_grapejelly = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Grape Jelly" },
        crackers = { nativeName = "consumable_crackers", useAmount = 1, notifyText = "Crackers" },
        consumable_crackers = { nativeName = "consumable_crackers", useAmount = 1, notifyText = "Crackers" },
        cheese = { nativeName = "consumable_cheese_wedge", useAmount = 1, notifyText = "Cheese" },
        consumable_cheese_wedge = { nativeName = "consumable_cheese_wedge", useAmount = 1, notifyText = "Cheese Wedge" },
        butter = { nativeName = "consumable_cheese_wedge", useAmount = 1, notifyText = "Butter" },
        a_egg = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Fresh Egg" },
        egg = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Fresh Egg" },
        boiled_egg = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Boiled Egg" },
        boiledegg = { nativeName = "consumable_biscuit_box", useAmount = 1, notifyText = "Boiled Egg" },
        consumable_oat_cakes = { nativeName = "consumable_oat_cakes", useAmount = 1, notifyText = "Oatcakes" },
        jerky = { nativeName = "consumable_jerky", useAmount = 1, notifyText = "Salted Beef Jerky" },
        consumable_jerky = { nativeName = "consumable_jerky", useAmount = 1, notifyText = "Salted Beef Jerky" },
        consumable_jerky_venison = { nativeName = "consumable_jerky_venison", useAmount = 1, notifyText = "Salted Venison Jerky" },
        consumable_game = { nativeName = "consumable_jerky", useAmount = 1, notifyText = "Jerkied Game Meat" },
        consumable_offal = { nativeName = "consumable_offal", useAmount = 1, notifyText = "Offal" },
        Chocolate = { nativeName = "consumable_chocolate_bar", useAmount = 1, notifyText = "Chocolate Bar" },
        consumable_chocolate = { nativeName = "consumable_chocolate_bar", useAmount = 1, notifyText = "Chocolate Bar" },
        consumable_chocolate_bar = { nativeName = "consumable_chocolate_bar", useAmount = 1, notifyText = "Chocolate Bar" },
        consumable_chocolatecake = { nativeName = "consumable_chocolate_bar", useAmount = 1, notifyText = "Chocolate Cake" },
        consumable_candy_bag = { nativeName = "consumable_candy_bag", useAmount = 1, notifyText = "Candy Bag" },
        consumable_caramel = { nativeName = "consumable_candy_bag", useAmount = 1, notifyText = "Caramel" },
        consumable_peppermint = { nativeName = "consumable_peppermint", useAmount = 1, notifyText = "Peppermint" },
        consumable_sugarcube = { nativeName = "consumable_sugarcube", useAmount = 1, notifyText = "Sugar Cube" },
        honey = { nativeName = "consumable_sugarcube", useAmount = 1, notifyText = "Raw Honey" },
        apiary_honey = { nativeName = "consumable_sugarcube", useAmount = 1, notifyText = "Raw Honey" },
        apiary_honey2 = { nativeName = "consumable_sugarcube", useAmount = 1, notifyText = "Quality Honey" },
        apiary_honey3 = { nativeName = "consumable_sugarcube", useAmount = 1, notifyText = "Premium Honey" },

        -- Saloon Meals, Steaks & Prepared Dishes
        steak = { nativeName = "consumable_meat_prime_beef_cooked", useAmount = 1, notifyText = "Steak" },
        steakeggs = { nativeName = "consumable_meat_big_game_cooked", useAmount = 1, notifyText = "Steak and Eggs" },
        steakveg = { nativeName = "consumable_meat_game_cooked", useAmount = 1, notifyText = "Steak with Veggies" },
        sausage = { nativeName = "consumable_meat_tender_pork_cooked", useAmount = 1, notifyText = "Sausage" },
        shrimps = { nativeName = "consumable_meat_crustacean_cooked", useAmount = 1, notifyText = "Deluxe Shrimp Stew" },
        consumable_chickenpie = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Chicken Pie" },
        consumable_steakpie = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Steak Pie" },
        consumable_peachcobbler = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Peach Cobbler" },
        trayoffood = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Saloon Food Tray" },
        vegstew = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Vegetable Stew" },
        consumable_meat_greavy = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Hearty Meat Stew" },
        consumable_crafted_super_meal = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Camp Stew" },
        special_camp_stew = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Camp Stew" },
        cowboy_feast = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Cowboy Feast" },
        consumable_breakfast = { nativeName = "consumable_crafted_super_meal", useAmount = 1, notifyText = "Breakfast" },

        -- Plain Cooked Meats & Fish (Campfire)
        consumable_big_game_meat_cooked = { nativeName = "consumable_big_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Big Game Meat" },
        consumable_game_meat_cooked = { nativeName = "consumable_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Game Meat" },
        consumable_prime_beef_cooked = { nativeName = "consumable_prime_beef_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Prime Beef" },
        consumable_tender_pork_cooked = { nativeName = "consumable_tender_pork_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Tender Pork" },
        consumable_gristly_mutton_cooked = { nativeName = "consumable_gristly_mutton_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Gristly Mutton" },
        consumable_mature_venison_cooked = { nativeName = "consumable_mature_venison_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Mature Venison" },
        consumable_crustacean_meat_cooked = { nativeName = "consumable_crustacean_meat_mint_cooked", useAmount = 1, notifyText = "Cooked Crustacean Meat" },
        consumable_flakey_fish_cooked = { nativeName = "consumable_flakey_fish_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Flakey Fish" },
        consumable_succulent_fish_cooked = { nativeName = "consumable_succulent_fish_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Succulent Fish" },
        consumable_plump_bird_cooked = { nativeName = "consumable_plump_bird_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Plump Bird" },
        consumable_exotic_bird_cooked = { nativeName = "consumable_exotic_bird_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Exotic Bird" },
        consumable_salmon = { nativeName = "consumable_meat_flakey_fish_cooked", useAmount = 1, notifyText = "Dried Salmon" },
        consumable_trout = { nativeName = "consumable_meat_succulent_fish_cooked", useAmount = 1, notifyText = "Cooked Trout" },
        consumable_bluegil = { nativeName = "consumable_meat_flakey_fish_cooked", useAmount = 1, notifyText = "Dried Bluegill" },
        fishmeat = { nativeName = "consumable_meat_flakey_fish_cooked", useAmount = 1, notifyText = "Cooked Fish" },
        Gamey_Meat = { nativeName = "consumable_meat_game_cooked", useAmount = 1, notifyText = "Gamey Meat" },
        Pork_Meat = { nativeName = "consumable_meat_tender_pork_cooked", useAmount = 1, notifyText = "Pork Meat" },
        pork = { nativeName = "consumable_meat_tender_pork_cooked", useAmount = 1, notifyText = "Pork" },
        Mutton = { nativeName = "consumable_meat_gristly_mutton_cooked", useAmount = 1, notifyText = "Mutton" },
        legendary_onwolf_meat = { nativeName = "consumable_meat_big_game_cooked", useAmount = 1, notifyText = "Wolf Roast" },
        meat = { nativeName = "consumable_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Meat" },
        raw_meat = { nativeName = "consumable_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Meat" },
        cookedpork = { nativeName = "consumable_tender_pork_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Pork" },
        cookedbird = { nativeName = "consumable_plump_bird_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Bird" },
        cookedsmallgame = { nativeName = "consumable_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Small Game" },
        cookedbluegil = { nativeName = "consumable_flakey_fish_wild_mint_cooked", useAmount = 1, notifyText = "Cooked Fish" },
        SaltedCookedBigGameMeat = { nativeName = "consumable_big_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Salted Cooked Big Game Meat" },

        -- Seasoned Cooked Meats (Oregano, Thyme, Wild Mint)
        consumable_big_game_meat_oregano_cooked = { nativeName = "consumable_big_game_meat_oregano_cooked", useAmount = 1, notifyText = "Oregano Big Game Meat" },
        consumable_big_game_meat_thyme_cooked = { nativeName = "consumable_big_game_meat_thyme_cooked", useAmount = 1, notifyText = "Thyme Big Game Meat" },
        consumable_big_game_meat_wild_mint_cooked = { nativeName = "consumable_big_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Mint Big Game Meat" },
        consumable_game_meat_oregano_cooked = { nativeName = "consumable_game_meat_oregano_cooked", useAmount = 1, notifyText = "Oregano Game Meat" },
        consumable_game_meat_thyme_cooked = { nativeName = "consumable_game_meat_thyme_cooked", useAmount = 1, notifyText = "Thyme Game Meat" },
        consumable_game_meat_wild_mint_cooked = { nativeName = "consumable_game_meat_wild_mint_cooked", useAmount = 1, notifyText = "Mint Game Meat" },
        consumable_prime_beef_oregano_cooked = { nativeName = "consumable_prime_beef_oregano_cooked", useAmount = 1, notifyText = "Oregano Prime Beef" },
        consumable_prime_beef_thyme_cooked = { nativeName = "consumable_prime_beef_thyme_cooked", useAmount = 1, notifyText = "Thyme Prime Beef" },
        consumable_prime_beef_wild_mint_cooked = { nativeName = "consumable_prime_beef_wild_mint_cooked", useAmount = 1, notifyText = "Mint Prime Beef" },
        consumable_tender_pork_oregano_cooked = { nativeName = "consumable_tender_pork_oregano_cooked", useAmount = 1, notifyText = "Oregano Tender Pork" },
        consumable_tender_pork_thyme_cooked = { nativeName = "consumable_tender_pork_thyme_cooked", useAmount = 1, notifyText = "Thyme Tender Pork" },
        consumable_tender_pork_wild_mint_cooked = { nativeName = "consumable_tender_pork_wild_mint_cooked", useAmount = 1, notifyText = "Mint Tender Pork" },
        consumable_gristly_mutton_oregano_cooked = { nativeName = "consumable_gristly_mutton_oregano_cooked", useAmount = 1, notifyText = "Oregano Mutton" },
        consumable_gristly_mutton_thyme_cooked = { nativeName = "consumable_gristly_mutton_thyme_cooked", useAmount = 1, notifyText = "Thyme Mutton" },
        consumable_gristly_mutton_wild_mint_cooked = { nativeName = "consumable_gristly_mutton_wild_mint_cooked", useAmount = 1, notifyText = "Mint Mutton" },
        consumable_mature_venison_oregano_cooked = { nativeName = "consumable_mature_venison_oregano_cooked", useAmount = 1, notifyText = "Oregano Venison" },
        consumable_mature_venison_thyme_cooked = { nativeName = "consumable_mature_venison_thyme_cooked", useAmount = 1, notifyText = "Thyme Venison" },
        consumable_mature_venison_wild_mint_cooked = { nativeName = "consumable_mature_venison_wild_mint_cooked", useAmount = 1, notifyText = "Mint Venison" },
        consumable_crustacean_meat_mint_cooked = { nativeName = "consumable_crustacean_meat_mint_cooked", useAmount = 1, notifyText = "Mint Crustacean" },
        consumable_crustacean_meat_oregano_cooked = { nativeName = "consumable_crustacean_meat_oregano_cooked", useAmount = 1, notifyText = "Oregano Crustacean" },
        consumable_crustacean_meat_thyme_cooked = { nativeName = "consumable_crustacean_meat_thyme_cooked", useAmount = 1, notifyText = "Thyme Crustacean" },
        consumable_flakey_fish_oregano_cooked = { nativeName = "consumable_flakey_fish_oregano_cooked", useAmount = 1, notifyText = "Oregano Fish" },
        consumable_flakey_fish_thyme_cooked = { nativeName = "consumable_flakey_fish_thyme_cooked", useAmount = 1, notifyText = "Thyme Fish" },
        consumable_flakey_fish_wild_mint_cooked = { nativeName = "consumable_flakey_fish_wild_mint_cooked", useAmount = 1, notifyText = "Mint Fish" },
        consumable_succulent_fish_oregano_cooked = { nativeName = "consumable_succulent_fish_oregano_cooked", useAmount = 1, notifyText = "Oregano Succulent Fish" },
        consumable_succulent_fish_thyme_cooked = { nativeName = "consumable_succulent_fish_thyme_cooked", useAmount = 1, notifyText = "Thyme Succulent Fish" },
        consumable_succulent_fish_wild_mint_cooked = { nativeName = "consumable_succulent_fish_wild_mint_cooked", useAmount = 1, notifyText = "Mint Succulent Fish" },
        consumable_plump_bird_oregano_cooked = { nativeName = "consumable_plump_bird_oregano_cooked", useAmount = 1, notifyText = "Oregano Bird" },
        consumable_plump_bird_thyme_cooked = { nativeName = "consumable_plump_bird_thyme_cooked", useAmount = 1, notifyText = "Thyme Bird" },
        consumable_plump_bird_wild_mint_cooked = { nativeName = "consumable_plump_bird_wild_mint_cooked", useAmount = 1, notifyText = "Mint Bird" },
        consumable_exotic_bird_oregano_cooked = { nativeName = "consumable_exotic_bird_oregano_cooked", useAmount = 1, notifyText = "Oregano Exotic Bird" },
        consumable_exotic_bird_thyme_cooked = { nativeName = "consumable_exotic_bird_thyme_cooked", useAmount = 1, notifyText = "Thyme Exotic Bird" },
        consumable_exotic_bird_wild_mint_cooked = { nativeName = "consumable_exotic_bird_wild_mint_cooked", useAmount = 1, notifyText = "Mint Exotic Bird" },

        -- Wild Berries & Foraged Herbs
        Black_Berry = { nativeName = "consumable_herb_black_berry", useAmount = 1, notifyText = "Blackberry" },
        Blackberry = { nativeName = "consumable_herb_black_berry", useAmount = 1, notifyText = "Blackberry" },
        blueberry = { nativeName = "consumable_herb_black_berry", useAmount = 1, notifyText = "Blueberry" },
        Blueberries = { nativeName = "consumable_herb_black_berry", useAmount = 1, notifyText = "Blueberries" },
        Black_Currant = { nativeName = "consumable_herb_black_currant", useAmount = 1, notifyText = "Black Currant" },
        Golden_Currant = { nativeName = "consumable_herb_golden_currant", useAmount = 1, notifyText = "Golden Currant" },
        Red_Raspberry = { nativeName = "consumable_herb_red_raspberry", useAmount = 1, notifyText = "Red Raspberry" },
        Wintergreen_Berry = { nativeName = "consumable_herb_wintergreen_berry", useAmount = 1, notifyText = "Wintergreen Berry" },
        Evergreen_Huckleberry = { nativeName = "consumable_herb_evergreen_huckleberry", useAmount = 1, notifyText = "Evergreen Huckleberry" },
        mulberry = { nativeName = "consumable_herb_black_berry", useAmount = 1, notifyText = "Mulberry" },
        blackmulberry = { nativeName = "consumable_herb_black_berry", useAmount = 1, notifyText = "Black Mulberry" },
        Bay_Bolete = { nativeName = "consumable_herb_bay_bolete", useAmount = 1, notifyText = "Bay Bolete" },
        Chanterelles = { nativeName = "consumable_herb_chanterelles", useAmount = 1, notifyText = "Chanterelles" },
        Parasol_Mushroom = { nativeName = "consumable_herb_parasol_mushroom", useAmount = 1, notifyText = "Parasol Mushroom" },
        Rams_Head = { nativeName = "consumable_herb_rams_head", useAmount = 1, notifyText = "Ram's Head" },
        Wild_Mint = { nativeName = "consumable_herb_wild_mint", useAmount = 1, notifyText = "Wild Mint" },
        Wild_Rhubarb = { nativeName = "consumable_herb_burdock_root", useAmount = 1, notifyText = "Wild Rhubarb" },
        Burdock_Root = { nativeName = "consumable_herb_burdock_root", useAmount = 1, notifyText = "Burdock Root" },
        Crows_Garlic = { nativeName = "consumable_herb_burdock_root", useAmount = 1, notifyText = "Crow's Garlic" },
        aloe_vera = { nativeName = "consumable_herb_burdock_root", useAmount = 1, notifyText = "Aloe Vera" },
        consumable_herb_oregano = { nativeName = "consumable_herb_oregano", useAmount = 1, notifyText = "Oregano" },

        -- Authentic RDO Tonics & Remedies
        consumable_medicine = { nativeName = "consumable_medicine", useAmount = 1, notifyText = "Health Cure" },
        consumable_medicine_used = { nativeName = "consumable_medicine_used", useAmount = 1, notifyText = "Health Cure" },
        consumable_potent_medicine = { nativeName = "consumable_potent_medicine", useAmount = 1, notifyText = "Potent Health Cure" },
        consumable_snake_oil = { nativeName = "consumable_snake_oil", useAmount = 1, notifyText = "Snake Oil" },
        consumable_snake_oil_used = { nativeName = "consumable_snake_oil_used", useAmount = 1, notifyText = "Snake Oil" },
        consumable_potent_snake_oil = { nativeName = "consumable_potent_snake_oil", useAmount = 1, notifyText = "Potent Snake Oil" },
        consumable_restorative = { nativeName = "consumable_restorative", useAmount = 1, notifyText = "Bitters" },
        consumable_restorative_used = { nativeName = "consumable_restorative_used", useAmount = 1, notifyText = "Bitters" },
        consumable_potent_restorative = { nativeName = "consumable_potent_restorative", useAmount = 1, notifyText = "Potent Bitters" },
        consumable_tonic = { nativeName = "consumable_tonic", useAmount = 1, notifyText = "Miracle Tonic" },
        consumable_tonic_used = { nativeName = "consumable_tonic_used", useAmount = 1, notifyText = "Miracle Tonic" },
        consumable_potent_tonic = { nativeName = "consumable_potent_tonic", useAmount = 1, notifyText = "Potent Miracle Tonic" },
        fish_oil = { nativeName = "consumable_special_restorative", useAmount = 1, notifyText = "Pure Fish Oil" },

        -- Tobacco, Cigars & Smokes
        consumable_chewing_tobacco = { nativeName = "consumable_chewing_tobacco", useAmount = 1, notifyText = "Chewing Tobacco" },
        consumable_chewing_tobacco_used = { nativeName = "consumable_chewing_tobacco_used", useAmount = 1, notifyText = "Chewing Tobacco" },
        consumable_cigar = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Cigar" },
        cigar = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Cigar" },
        consumable_cigarette_box = { nativeName = "consumable_cigarette_box", useAmount = 1, notifyText = "Cigarettes" },
        cigarette = { nativeName = "consumable_cigarette_box", useAmount = 1, notifyText = "Cigarettes" },
        consumable_cigarette_box_cheap = { nativeName = "consumable_cigarette_box_cheap", useAmount = 1, notifyText = "Cheap Cigarettes" },
        cigarette_indigo = { nativeName = "consumable_cigarette_box_cheap", useAmount = 1, notifyText = "Indigo Cigarettes" },
        joint = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Joint" },
        desert_chronic = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Desert Chronic" },
        exoticjoint = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Exotic Joint" },
        anejocigar = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Anejo Cigar" },
        corojocigar = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Corojo Cigar" },
        madurocigar = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Maduro Cigar" },
        robustocigar = { nativeName = "consumable_cigar", useAmount = 1, notifyText = "Robusto Cigar" },
        consumable_cocaine_chewing_gum = { nativeName = "consumable_cocaine_chewing_gum", useAmount = 1, notifyText = "Cocaine Gum" },
        consumable_cocaine_chewing_gum_used = { nativeName = "consumable_cocaine_chewing_gum_used", useAmount = 1, notifyText = "Cocaine Gum" },

        -- Horse Care & Baits
        consumable_sugarcube = { nativeName = "consumable_sugarcube", useAmount = 1, notifyText = "Sugar Cube" },
        sugarcube = { nativeName = "consumable_sugarcube", useAmount = 1, notifyText = "Sugar Cube" },
        consumable_horse_meal = { nativeName = "consumable_horse_meal", useAmount = 1, notifyText = "Horse Meal" },
        consumable_haycube = { nativeName = "consumable_haycube", useAmount = 1, notifyText = "Haycube" },
        haycube = { nativeName = "consumable_haycube", useAmount = 1, notifyText = "Haycube" },
        consumable_horse_peppermints = { nativeName = "consumable_peppermint", useAmount = 1, notifyText = "Peppermints" },
        consumable_horse_medicine = { nativeName = "consumable_horse_medicine", useAmount = 1, notifyText = "Horse Medicine" },
        consumable_horse_medicine_used = { nativeName = "consumable_horse_medicine_used", useAmount = 1, notifyText = "Horse Medicine" },
        consumable_horse_medicine_potent = { nativeName = "consumable_potent_horse_medicine", useAmount = 1, notifyText = "Potent Horse Medicine" },
        consumable_potent_horse_medicine = { nativeName = "consumable_potent_horse_medicine", useAmount = 1, notifyText = "Potent Horse Medicine" },
        consumable_horse_special_medicine = { nativeName = "consumable_special_horse_medicine", useAmount = 1, notifyText = "Special Horse Medicine" },
        consumable_special_horse_medicine = { nativeName = "consumable_special_horse_medicine", useAmount = 1, notifyText = "Special Horse Medicine" },
        consumable_horse_stimulant = { nativeName = "consumable_horse_stimulant", useAmount = 1, notifyText = "Horse Stimulant" },
        consumable_horse_stimulant_used = { nativeName = "consumable_horse_stimulant_used", useAmount = 1, notifyText = "Horse Stimulant" },
        consumable_horse_stimulant_potent = { nativeName = "consumable_potent_horse_stimulant", useAmount = 1, notifyText = "Potent Horse Stimulant" },
        consumable_potent_horse_stimulant = { nativeName = "consumable_potent_horse_stimulant", useAmount = 1, notifyText = "Potent Horse Stimulant" },
        consumable_horse_special_stimulant_crafted = { nativeName = "consumable_special_horse_stimulant_crafted", useAmount = 1, notifyText = "Special Horse Stimulant" },
        consumable_special_horse_stimulant_crafted = { nativeName = "consumable_special_horse_stimulant_crafted", useAmount = 1, notifyText = "Special Horse Stimulant" },
        consumable_horse_reviver = { nativeName = "consumable_horse_reviver", useAmount = 1, notifyText = "Horse Reviver" },
        consumable_special_horse_reviver_crafted = { nativeName = "consumable_special_horse_reviver_crafted", useAmount = 1, notifyText = "Special Horse Reviver" },
        consumable_predator_bait = { nativeName = "consumable_predator_bait", useAmount = 1, notifyText = "Predator Bait" },
        consumable_potent_predator_bait = { nativeName = "consumable_potent_predator_bait", useAmount = 1, notifyText = "Potent Predator Bait" },
        consumable_herbivore_bait = { nativeName = "consumable_herbivore_bait", useAmount = 1, notifyText = "Herbivore Bait" },
        consumable_potent_herbivore_bait = { nativeName = "consumable_potent_herbivore_bait", useAmount = 1, notifyText = "Potent Herbivore Bait" },
        kit_horse_brush = { nativeName = "kit_horse_brush", useAmount = 1, notifyText = "Horse Brush" },
        provision_hrlm_brush_horse = { nativeName = "kit_horse_brush", useAmount = 1, notifyText = "Horse Brush" },
        kit_camp = { nativeName = "kit_camp", useAmount = 1, notifyText = "Camp" },
        kit_camp_simple = { nativeName = "kit_camp_simple", useAmount = 1, notifyText = "Simple Camp" },
        upgrade_upg_mortar_pestle = { nativeName = "upgrade_upg_mortar_pestle", useAmount = 1, notifyText = "Mortar & Pestle" },
    },
}

-- ---------------------------------------------------------------------------
-- Items that are NOT listed in WheelItems above still reach the wheel when they are
-- food / drink AND the inventory can really use them (usable = 1 with a registered
-- callback). They are mirrored as the generic native below, so every edible/drinkable
-- item in the bag has an entry. Add a proper mapping to WheelItems to pick a nicer icon.
-- ---------------------------------------------------------------------------
Config.InputWheel.AutoNative = {
    Categories = {
        food = 'consumable_bread_chunk',
        provisions = 'consumable_bread_chunk',
        drink = 'consumable_restorative',
    },
    ExcludePatterns = { '^dog_', '^animal_' },
}

-- The native item database silently rejects a name it does not know (the item then never
-- shows on the wheel). The client checks every nativeName with ItemdatabaseIsKeyValid and,
-- when it is rejected, tries these known-good natives in order instead.
local DRINK_FALLBACK = { 'consumable_restorative', 'consumable_potent_restorative', 'consumable_special_restorative', 'consumable_whiskey' }
local FOOD_FALLBACK = { 'consumable_bread_chunk', 'consumable_biscuit_box', 'consumable_crackers', 'consumable_apple' }
local MEAT_FALLBACK = { 'consumable_jerky', 'consumable_cornedbeef_can', 'consumable_bread_chunk' }

Config.InputWheel.FallbackNatives = { generic = FOOD_FALLBACK, drink = DRINK_FALLBACK }

for _, entry in pairs(Config.InputWheel.WheelItems) do
    local native = entry.nativeName
    local cooked = native:match('^consumable_meat_(.+)_cooked$')
    if cooked then
        local list = { 'consumable_' .. cooked .. '_wild_mint_cooked' }
        for i = 1, #MEAT_FALLBACK do list[#list + 1] = MEAT_FALLBACK[i] end
        entry.fallback = list
    elseif native:find('restorative', 1, true) or native:find('medicine', 1, true)
        or native:find('tonic', 1, true) or native:find('whiskey', 1, true)
        or native:find('rum', 1, true) or native:find('gin', 1, true)
        or native:find('brandy', 1, true) or native:find('moonshine', 1, true) then
        entry.fallback = DRINK_FALLBACK
    else
        entry.fallback = FOOD_FALLBACK
    end
end

-- ---------------------------------------------------------------------------
-- Substitution: the native wheel only lists items the game itself files under a wheel slot.
-- Any item whose native is NOT in ShownNatives takes the place of a native from Substitutes instead.
-- Each item gets its own unused entry, mapped strictly to single-slot natives to prevent duplication.
-- ---------------------------------------------------------------------------
Config.InputWheel.SubstituteUnlisted = true

Config.InputWheel.ShownNatives = {
    -- Provisions: Canned Goods
    'consumable_apricots_can', 'consumable_baked_beans_can', 'consumable_cornedbeef_can',
    'consumable_salmon_can', 'consumable_peaches_can', 'consumable_sweet_corn_can',
    'consumable_strawberries_can', 'consumable_pineapples_can', 'consumable_peas_can',
    'consumable_kidneybeans_can',

    -- Provisions: Dry Goods, Biscuits, Sweets, Fruits & Veggies
    'consumable_biscuit_box', 'consumable_crackers', 'consumable_cheese_wedge',
    'consumable_oat_cakes', 'consumable_jerky', 'consumable_chocolate_bar',
    'consumable_candy_bag', 'consumable_apple', 'consumable_peach', 'consumable_pear',
    'consumable_carrot', 'consumable_corn', 'consumable_beets', 'consumable_celery',
    'consumable_peppermint', 'consumable_sugarcube',

    -- Provisions: Alcohol
    'consumable_whiskey', 'consumable_whiskey_used', 'consumable_gin', 'consumable_gin_used',
    'consumable_rum', 'consumable_rum_used', 'consumable_brandy', 'consumable_brandy_used',
    'consumable_moonshine',

    -- Health Tonics / Cures (Health slot only)
    'consumable_medicine', 'consumable_medicine_used', 'consumable_potent_medicine',
    'consumable_special_medicine',

    -- Stamina Tonics / Bitters / Restoratives (Stamina slot only)
    'consumable_restorative', 'consumable_restorative_used', 'consumable_potent_restorative',
    'consumable_special_restorative',

    -- Dead Eye Tonics / Snake Oil (Dead Eye slot only)
    'consumable_snake_oil', 'consumable_snake_oil_used', 'consumable_potent_snake_oil',
    'consumable_special_snake_oil',

    -- Genuine Miracle Tonics (Only for actual player-owned Miracle Tonic items)
    'consumable_tonic', 'consumable_tonic_used', 'consumable_potent_tonic', 'consumable_special_tonic',

    -- Tobacco, Cigars & Smokes (Dead Eye / Tobacco slot)
    'consumable_chewing_tobacco', 'consumable_chewing_tobacco_used', 'consumable_cigar',
    'consumable_cigarette_box', 'consumable_cigarette_box_cheap',
    'consumable_cocaine_chewing_gum', 'consumable_cocaine_chewing_gum_used',

    -- Horse Care, Stimulants, Revivers & Baits (Horse slot)
    'consumable_haycube', 'consumable_sugarcube', 'consumable_horse_meal',
    'consumable_horse_medicine', 'consumable_horse_medicine_used',
    'consumable_potent_horse_medicine', 'consumable_special_horse_medicine',
    'consumable_horse_stimulant', 'consumable_horse_stimulant_used',
    'consumable_potent_horse_stimulant', 'consumable_special_horse_stimulant_crafted',
    'consumable_horse_reviver', 'consumable_special_horse_reviver_crafted',
    'consumable_predator_bait', 'consumable_potent_predator_bait',
    'consumable_herbivore_bait', 'consumable_potent_herbivore_bait',
    'kit_horse_brush',

    -- Camp & Kit (Kit slot)
    'kit_camp', 'kit_camp_simple', 'upgrade_upg_mortar_pestle',
}

Config.InputWheel.Substitutes = {
    food = {
        'consumable_baked_beans_can', 'consumable_cornedbeef_can', 'consumable_peaches_can',
        'consumable_sweet_corn_can', 'consumable_peas_can', 'consumable_pineapples_can',
        'consumable_strawberries_can', 'consumable_apricots_can', 'consumable_salmon_can',
        'consumable_kidneybeans_can', 'consumable_biscuit_box', 'consumable_crackers',
        'consumable_cheese_wedge', 'consumable_oat_cakes', 'consumable_jerky',
    },
    drink = {
        -- Strictly single-slot restoratives and alcohols. NEVER multi-slot miracle tonics!
        'consumable_restorative', 'consumable_potent_restorative', 'consumable_special_restorative',
        'consumable_whiskey', 'consumable_gin', 'consumable_rum', 'consumable_brandy', 'consumable_moonshine',
        'consumable_medicine', 'consumable_potent_medicine', 'consumable_special_medicine',
        'consumable_snake_oil', 'consumable_potent_snake_oil', 'consumable_special_snake_oil',
    },
}

for _, entry in pairs(Config.InputWheel.WheelItems) do
    entry.kind = (entry.fallback == DRINK_FALLBACK) and 'drink' or 'food'
end

-- Effect-matched substitutes.
-- ALL multi-core foods/meals/stews are directed to Provisions (canned goods) so they NEVER duplicate across slots.
-- Stamina restoratives/drinks stay strictly in the Stamina slot.
-- Health remedies stay strictly in the Health slot.
-- Dead Eye tonics stay strictly in the Dead Eye slot.
Config.InputWheel.SubstitutesBySignature = {
    HS = {
        'consumable_baked_beans_can', 'consumable_cornedbeef_can', 'consumable_peaches_can',
        'consumable_sweet_corn_can', 'consumable_peas_can', 'consumable_pineapples_can',
        'consumable_strawberries_can', 'consumable_apricots_can', 'consumable_salmon_can',
        'consumable_kidneybeans_can',
    },
    -- Multi-core meals/stews belong in Provisions (food), NEVER miracle tonics!
    HSD = {
        'consumable_cornedbeef_can', 'consumable_baked_beans_can', 'consumable_salmon_can',
        'consumable_sweet_corn_can', 'consumable_peaches_can', 'consumable_kidneybeans_can',
    },
    SD = { 'consumable_whiskey', 'consumable_brandy', 'consumable_gin', 'consumable_rum', 'consumable_restorative', 'consumable_potent_restorative' },
    D = { 'consumable_snake_oil', 'consumable_potent_snake_oil', 'consumable_special_snake_oil', 'consumable_moonshine' },
    S = { 'consumable_restorative', 'consumable_potent_restorative', 'consumable_special_restorative' },
    H = { 'consumable_medicine', 'consumable_potent_medicine', 'consumable_special_medicine' },
    ['-'] = {
        'consumable_baked_beans_can', 'consumable_cornedbeef_can', 'consumable_peaches_can',
        'consumable_sweet_corn_can', 'consumable_peas_can', 'consumable_pineapples_can',
        'consumable_strawberries_can', 'consumable_apricots_can', 'consumable_salmon_can',
        'consumable_kidneybeans_can',
    },
}
Config.InputWheel.SubstitutesBySignature.HD = Config.InputWheel.SubstitutesBySignature.HSD
end


-- --------------------------------------------------------------------------
--  3D waypoint
-- --------------------------------------------------------------------------
do
Config.Waypoint3D = {
    Enabled = true,

    defaultBlip = {
        sprite = "blip_poi",
        color = {232, 16, 5},
    },

    display = {
        spriteSize = {0.02, 0.035},
        textScale = 0.25,
        textColor = {255, 255, 255, 255},
        textFont = 4,
        textOffset = 0.025,
        minDistance = 6.0,
        heightOffset = 1.0,
    },

    commands = {
        toggle = "togglewaypoint",
    },
}
end
