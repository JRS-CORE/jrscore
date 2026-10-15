-- ==========================================================================
--  JRS CORE  |  jrs_inventory  |  config/config.lua
--  JRS Inventory unified resource: inventory + weapons + storage + ground + robbery + transactional trade
-- ==========================================================================

Config = {}
-- Fallback only. The live language is per player and comes from jrs_core.
Config.defaultlang = "ar"
Config.Max_Items = 50 -- kg (base capacity at level 1, scales to 300 with level perks)
Config.Max_Weapons = 4 -- base weapons at level 1, scales to 7 with level perks

-- Per-item ownership cap (total count across the whole inventory, all stacks
-- summed). Enforced centrally in AddInventoryItemDirect so it applies no
-- matter how the item is acquired (store purchase, admin give, crafting,
-- quest reward, player trade, ground pickup, etc).
Config.MaxOwnedItems = {
    hoe = 1,
    wellpumpnbx = 1,
    pickaxe = 1, -- one per player (players stacked/duped extras)
}
Config.CountUnknownWeaponsTowardLimit = false -- unknown/orphan DB weapon names do not consume capacity

-- Permanent weapon serial numbers
Config.WeaponSerials = {
    Prefix = 'JRS',                -- serial prefix, e.g. JRS-20260804-...
    RandomLength = 8,              -- random part length
    AutoMigrate = true,            -- add/backfill the serial_number DB column automatically
    MaintenanceIntervalMs = 300000, -- lightweight mode: legacy serial maintenance every 5 minutes
}

-- Inventory UI feature settings
-- Server-authoritative item metadata system
Config.Metadata = {
    Enabled = true,
    ApplyDatabaseDefaults = true, -- parse items.metadata JSON as defaults for each item instance
    DefaultDurability = 100,
    DurabilityMin = 0,
    DurabilityMax = 100,
    PreventUseWhenBroken = true, -- block item usage when durability reaches 0
    MaxDepth = 5,
    MaxKeys = 32,
    MaxStringLength = 256,
    MaxEncodedLength = 2048,
    LogChanges = false, -- enable only when you want a Discord audit entry for every metadata mutation

    -- Metadata keys that make an item a unique instance instead of a stack.
    -- This prevents one durability value from being shared by several tools.
    UniqueKeys = { 'durability', 'serial_number', 'instance_id', 'instanceId' },

    -- Optional defaults by item category. Category names are case-insensitive.
    -- Every item in the EQUIPMENT category starts with 100% durability automatically.
    CategoryDefaults = {
        equipment = { durability = 100 },
    },

    -- Optional per-item default metadata. DB items.metadata JSON is merged first,
    -- category defaults are merged next, then values here override them. Example:
    -- ItemDefaults = { pickaxe = { durability = 100 } }
    ItemDefaults = {
        pickaxe = { durability = 100 },
        -- Horse brushes wear out per brush (jrs_stable Config.brushDurability).
        kit_horse_brush = { durability = 100 },
        provision_hrlm_brush_horse = { durability = 100 },
        -- jrs_mining gold furnace: wears per melt (Config.GoldSmelt.furnaceWearPerMelt).
        gold_furnace = { durability = 100 },
    },
}

-- Secure player trading button inside the inventory UI.
-- The button is shown only when Enabled=true AND the configured trade resource is started.
Config.Trade = {
    Enabled = true,
    Resource = 'jrs_inventory',
    SelectorDistance = 5.0, -- nearby-player mouse selector range used when starting a trade
}

Config.InventoryUI = {
    DamagedThreshold = 30,       -- items/weapons at or below this condition appear in DAMAGED filter
    WeightWarningPercent = 80,  -- yellow weight warning
    WeightCriticalPercent = 95, -- red critical weight warning
    WeightWarningSound = true,  -- play one short UI warning sound when a threshold is crossed
    MultiActionDelayMs = 120,   -- pause after each answered multi-select transfer (server cooldown is 100)
}

-- Personal-only items. Names are case-insensitive.
-- They can be used and arranged in the owner's bag/hotbar, but cannot be
-- dropped, given to another player, or moved into storage.
Config.PersonalItems = {
     "lockpick",
     "pickaxe", -- no give / drop / trade / storage (wagon, stash, house)
    -- "personal_radio",
}

-- Job resources (farming crops, mining ores/bars/gems, lumber). Names are
-- case-insensitive. They can NOT be given to another player, dropped on the
-- ground, put in a player trade or listed in a player-owned store: the only way
-- to sell them is the job NPC (farming store / mining shop / lumber NPC) or
-- the mining orders, and other players buy them from that NPC's Player Market.
-- Storage (house, wagon, stash) is still allowed.
Config.NoTransferItems = {
    -- Farming (jrs_farming configs/plants.lua Produce)
    "Agarita", "Alaskan_Ginseng", "American_Ginseng", "Bitter_Weed", "Black_Berry",
    "Black_Currant", "Blood_Flower", "Bulrush", "Burdock_Root", "Cardinal_Flower",
    "Chanterelles", "Choc_Daisy", "Creeking_Thyme", "Creekplum", "Crows_Garlic",
    "Desert_Sage", "English_Mace", "Evergreen_Huckleberry", "Golden_Currant",
    "Hummingbird_Sage", "Indian_Tobbaco", "Milk_Weed", "Oleander_Sage", "Oregano",
    "Parasol_Mushroom", "Prairie_Poppy", "Rams_Head", "Red_Raspberry", "Red_Sage",
    "Saltbush", "Texas_Bonnet", "Violet_Snowdrop", "Wild_Feverfew", "Wild_Mint",
    "Wild_Rhubarb", "Wintergreen_Berry", "Wisteria", "Yarrow",
    "aloe_vera", "apple", "blackmulberry", "cana", "carrots", "chamomile_flower",
    "cocoa", "coffeebeans", "consumable_peach", "consumable_tomato", "corn",
    "echinacea_flower", "grapes", "hemp", "hop", "lavender_flower", "malt",
    "moonbloom", "mulberry", "potato", "sugarcube", "tealeaf", "weed_ex", "wheat",

    -- Mining (ores, gems, smelted bars)
    "amethyst", "clay", "coal", "copper", "copper_ore", "copperbar", "diamond",
    "diamondore", "emerald", "goldbar", "goldnugget", "iron", "iron_ore", "ironbar",
    "minesalt", "niter_rock", "nitrite", "rock", "rubis", "salt", "sapphire",
    "silver", "silverbar", "sulfur",

    -- Lumber
    "wood", "hwood", "rubber",
}

-- Translation comes from jrs_core's shared runtime
-- (@jrs_core/shared/jrs_lang.lua), which the manifest loads before this file:
-- _U resolves against the language the player picked on the character screen,
-- _UE forces English for RedM on-screen prompts.
Locales = Locales or {}

-- Config.IsPersonalItem(itemName) lives in shared/personal_items.lua (logic
-- moved out of config so this file stays values-only). It reads the
-- Config.PersonalItems list above.

Config.WeaponLimitByJob = {                 -- override Max_Weapons per job/group (key = job or group, value = max weapons)
    default = 7, -- NOT used for weapon slots anymore: jrs_core level perks give 4 -> 7; job entries below only ever raise it
    police = 10,
    sheriff = 10,
    admin = 10,
}

-- Prefix overrides: any job whose name starts with the key gets this limit
-- (all ranks). gunsmith covers gunsmith + every gunsmith_<city> store job.
Config.WeaponLimitByJobPrefix = {
    gunsmith = 20,
}

Config.openinv = 0xC1989F95 -- I (legacy control-hash fallback)
-- RedM uses the control hash above directly for reliable first-press detection.
-- Change Config.openinv if you want to use a different RedM control.

-- Commands / controls
Config.OpenInventoryCommand = 'inv'        -- /inv command that opens the inventory
Config.PickupControlHash = 0x27D1C284      -- INPUT_PICKUP control used for ground/prop item pickup prompts
Config.PickupDistance = 7.0                -- max distance (units) to search for nearby ground drops / interactable peds
Config.InteractionDistance = 2.0           -- max distance (units) for close-range interactions (looting, storage, trading)
Config.PlayerTransferDistance = 4.5      -- maximum server-verified distance for giving items, weapons, money, or gold to another player
Config.InteractionDistance = 4.5         -- general player-to-player interaction check radius
Config.GroundInteractionDistance = 1.5     -- Ground list visibility and server-validated pickup range
Config.GroundPromptDistance = 0.7          -- world pickup prompt appears only when standing directly over the drop
Config.GroundWorldPromptEnabled = false    -- world PICK UP prompt stays disabled; pickup is through the inventory GROUND panel only
Config.GroundSpawnWorldProps = true       -- spawn a lightweight world prop for each nearby ground drop
Config.GroundPropStreamDistance = 35.0        -- create local drop props only near the player
Config.GroundPropDespawnDistance = 45.0       -- remove local props after leaving this range
Config.GroundPropStreamRefreshMs = 1000       -- lightweight prop streaming refresh

-- Currency ground-drop permissions
Config.AllowMoneyGroundDrop = true       -- true: players can drop cash on the ground; false: server blocks it
Config.AllowGoldGroundDrop = true        -- true: players can drop gold on the ground; false: server blocks it
Config.AllowDirtyMoneyGroundDrop = true  -- true: players can drop dirty/illegal money on the ground; false: server blocks it

-- Currency storage deposit permissions
-- These options control moving currency FROM the player INTO a storage/chest.
-- Currency already stored can still be withdrawn when these options are false.
Config.AllowMoneyToStorage = true         -- true: allow depositing cash into storage; false: block it
Config.AllowGoldToStorage = true          -- true: allow depositing gold into storage; false: block it
Config.AllowDirtyMoneyToStorage = true    -- true: allow depositing dirty/illegal money into storage; false: block it

-- Weapon slot keybinds (1-5, holster and lantern toggle)
Config.WeaponHolsterControlHash = 0x52D29063   -- toggle-holster key for dual-wielded pistols/revolvers
Config.LanternToggleControlHash = 0x53296B75   -- toggle key for the davy lantern melee weapon

Config.WeaponSlot1ControlHash = 0xE6F612E4
Config.WeaponSlot2ControlHash = 0x1CE6D9EB
Config.WeaponSlot3ControlHash = 0x4F49CC4C
Config.WeaponSlot4ControlHash = 0x8F9F9E58
Config.WeaponSlot5ControlHash = 0xAB62E997
    -- ["1"] = 0xE6F612E4,
    -- ["2"] = 0x1CE6D9EB,
    -- ["3"] = 0x4F49CC4C,
    -- ["4"] = 0x8F9F9E58,
    -- ["5"] = 0xAB62E997,
    -- ["6"] = 0xA1FDE2A6,
    
Config.HotbarUseCooldownMs = 400          -- prevents one key press from firing the same slot repeatedly

-- Player interaction settings now belong to jrs_core.
-- Config.GetPlayerInteractions() lives in shared/player_interactions.lua
-- (logic moved out of config so this file stays values-only).

-- Carried-weight movement penalty.
-- Set to false to disable the system completely and restore normal movement.
Config.WeightSpeedEnabled = true

-- RedM movement uses SET_PED_MAX_MOVE_BLEND_RATIO for the carried-weight cap.
-- Lower values are slower. 0.0 means no weight cap / normal movement.
-- These are the original JRS inventory values that were used by the working system.
Config.WeightSpeedPenalty = {
	{ threshold = 45, speed = 1.60 },
	{ threshold = 42, speed = 1.70 },
	{ threshold = 39, speed = 1.80 },
	{ threshold = 35, speed = 1.90 },
	{ threshold = 30, speed = 2.10 },
	{ threshold = 27, speed = 2.20 },
}

Config.DefaultMoveSpeed = 0.0       -- 0.0 = no weight restriction below every threshold
Config.NormalMoveBlendRatio = 3.0   -- restore full normal locomotion when no penalty is active

-- Timing
Config.ActionCooldownMs = 100              -- minimum delay between repeated give/transfer/drop requests from the same player

-- Lightweight runtime tuning. These values keep controls responsive while avoiding
-- expensive native/player scans every few milliseconds when nothing is happening.
Config.Performance = {
    -- Idle-power profile. These values are deliberately conservative so jrs_inventory
    -- spends almost no client time while the inventory is closed, without making input feel delayed.
    OpenKeyIdleMs = 50,             -- holster / lantern polling; inventory I key has its own one-control frame watcher
    OpenKeyUiMs = 250,              -- no gameplay polling is needed quickly while NUI owns focus

    GroundNoDropsMs = 2000,         -- nothing exists on the ground: sleep almost completely
    GroundFarScanMs = 600,          -- drops exist, but none is within the near radius
    GroundMidScanMs = 100,          -- a drop is within GroundMidDistance
    GroundMidDistance = 3.0,
    GroundNearScanMs = 15,          -- only while actually standing on the pickup prompt

    HotbarIdleMs = 500,             -- no assigned hotbar slots => no control natives are called
    HotbarActiveMs = 25,            -- assigned slot controls remain responsive without a 100 Hz loop

    SocialIdleMs = 350,             -- target scanner while not aiming at another player
    SocialTargetMs = 15,            -- fast only while a valid player interaction prompt is visible

    RobberyNoPlayersMs = 1500,      -- only yourself online/streamed locally
    RobberyIdleScanMs = 750,        -- no nearby searchable target
    RobberyMidScanMs = 150,         -- another player is within RobberyMidDistance
    RobberyMidDistance = 3.0,
    RobberyNearMs = 15,             -- fast only while the Search prompt is actually visible

    GiveSelectorRefreshMs = 100,    -- selector exists only while choosing a recipient
    PedPromptNameRefreshMs = 15000, -- Citizen (ID) name refresh; does not need a high rate
    MoveSpeedRefreshMs = 1000,      -- weight speed check; value is only applied when it changes
    AmmoSaveActiveMs = 5000,        -- ammo is sampled only while an inventory weapon is equipped
    AmmoSaveIdleMs = 15000          -- no equipped weapon => do not scan ammo types; only re-check state
}

-- Anti-duplication / lag-switch protection
Config.AntiDupe = {
    Enabled = true,
    OperationReplayWindowMs = 120000,
    LockTimeoutMs = 30000,
    LegacyReplayWindowMs = 1500,
    LogBlockedActions = true,
    MaxViolationsBeforeDrop = 0,
}

-- Server-authoritative request validation. These limits are intentionally
-- generous for normal play and only block spammed, malformed, or oversized
-- client payloads. JRS is the only supported framework.
Config.Security = {
    RequestWindowMs = 5000,
    RequestLimits = {
        get_items = 5,
        get_money = 10,
        refresh_items = 12,
        refresh_money = 16,
        save_hotbar = 8,
        save_slots = 10,
        use_item = 10,
        turn_ped = 8,
        social = 6,
        weapon_state = 16,
        ground_refresh = 12,
        inventory_operation = 30, -- multi-select storage moves send one per item
        robbery_search = 5,
        robbery_refresh = 10,
        robbery_action = 12,
    },
    MaxLayoutEntries = 256,
    MaxLayoutSlot = 512,
    MaxHotbarPayloadBytes = 4096,
    MaxUseArgsBytes = 4096,
    MaxLayoutPayloadBytes = 65536,
    MaxAmmoPayloadBytes = 8192,
    MaxAmmoEntries = 32,
    MaxAmmoPerType = 999,
    SocialSessionTimeoutMs = 30000,
}
Config.InventoryLoadTimeoutMs = 8000       -- if the server hasn't answered a get_items request by this point, open with whatever is cached instead of staying stuck on the loading screen
Config.AutoSaveIntervalMs = 30000          -- lightweight mode: dirty inventories are flushed every 30s; critical actions still save immediately
Config.SaveThrottleMs = 100                -- delay between each player's save within a single sweep (spreads out DB load)
Config.CharacterLoadDelayMs = 5000          -- delay after character selection before the first inventory/money load request
Config.ResourceRestartSyncDelayMs = 3500      -- safe re-sync delay after txAdmin/resource restart
Config.UnequipWeaponsOnSpawn = true       -- remove inventory weapons from the weapon wheel whenever the player spawns/respawns
Config.RespawnWeaponCleanupDelayMs = 1500 -- wait for the new player ped to exist before clearing its weapon wheel

-- Props (ground drops / cleaning prop)
Config.Props = {
	weaponCleaningCloth = 's_balledragcloth01x',
	droppedWeapon = 'mp005_s_posse_weaponslocker01x',
	droppedMoney = 'p_moneystack01x',
	droppedGold = 'p_goldstack01x',
	droppedDirtyMoney = 'p_moneystack01x',
	droppedItem = 'p_cs_flourbag01x',
}

-- Animations (dict/name/duration used with the playAnim/playAnim2 wrappers)
Config.Animations = {
	itemPickupGround = { dict = "mech_pickup@fish_bag@pickup_handheld", name = "pickup", duration = 2000 },
	itemDropGround = { dict = "mech_pickup@firewood", name = "putdown", duration = 3000 },
	hostageTakeLoop = { dict = "script_mp@bounty@legendary@lbnik@ig@lbnik_ig2_humanshield", name = "loop_humanshield_yukon", duration = -1 },
	hostageHeldLoop = { dict = "script_mp@bounty@legendary@lbnik@ig@lbnik_ig2_humanshield", name = "loop_humanshield_hostage", duration = -1 },
	hostageRelease = { dict = "mech_grapple@pistol@_male@_ambient@_healthy@front@_streamed", name = "release_att", duration = 600 },
	giveHandGreet = { dict = "script_story@ind1@leadin@int", name = "greet_f_player", duration = 800 },
	giveRat = { dict = "mech_butcher", name = "small_rat_give_player", duration = 2500 },
	holsterPocketwatch = { dict = "mech_inventory@item@pocketwatch@unarmed@base", name = "holster", duration = 1500 },
	-- indexed 1-7 to match the "random" slap variant picked by jrs_inventory:give_slap
	Slaps = {
		[1] = { dict = "mech_melee@unarmed@posse@ambient@healthy@noncombat", attackerName = "slap_front_drunk_vs_drunk_heavy_v1_att", attackerDuration = 4000, victimName = "slap_front_drunk_vs_drunk_heavy_v1_vic", victimDuration = 5500, victimExtraWaitMs = 0 },
		[2] = { dict = "mech_melee@unarmed@posse@ambient@healthy@noncombat", attackerName = "slap_front_drunk_vs_drunk_medium_v1_att", attackerDuration = 4000, victimName = "slap_front_drunk_vs_drunk_medium_v1_vic", victimDuration = 6000, victimExtraWaitMs = 0 },
		[3] = { dict = "mech_melee@unarmed@posse@ambient@healthy@noncombat", attackerName = "slap_front_sober_vs_drunk_heavy_v1_att", attackerDuration = 4000, victimName = "slap_front_sober_vs_drunk_heavy_v1_vic", victimDuration = 6000, victimExtraWaitMs = 0 },
		[4] = { dict = "mech_melee@unarmed@posse@ambient@healthy@noncombat", attackerName = "slap_front_sober_vs_drunk_medium_v1_att", attackerDuration = 4000, victimName = "slap_front_sober_vs_drunk_medium_v1_vic", victimDuration = 5000, victimExtraWaitMs = 0 },
		[5] = { dict = "mech_melee@unarmed@posse@ambient@healthy@noncombat", attackerName = "slap_front_drunk_vs_drunk_heavy_v3_att", attackerDuration = 6000, victimName = "slap_front_drunk_vs_drunk_heavy_v3_vic", victimDuration = 4000, victimExtraWaitMs = 0 },
		[6] = { dict = "mech_melee@unarmed@posse@ambient@healthy@noncombat", attackerName = "slap_front_sober_vs_drunk_light_v1_att", attackerDuration = 3000, victimName = "slap_front_sober_vs_drunk_light_v1_vic", victimDuration = 4000, victimExtraWaitMs = 100 },
		[7] = { dict = "mech_melee@unarmed@posse@ambient@healthy@noncombat", attackerName = "slap_front_sober_vs_drunk_light_v2_att", attackerDuration = 4000, victimName = "slap_front_sober_vs_drunk_light_v2_vic", victimDuration = 4000, victimExtraWaitMs = 0 },
	},
}

-- Dependent resource names (change here if you rename any of these resources)
Config.NotificationResource = 'jrs_core' -- jrs_notify is only a `provide` alias of jrs_core; exports[] need the real name
Config.CoreResource = 'jrs_core'
Config.MysqlResource = 'oxmysql'

-- Dev Mode: lets an admin re-initialize the inventory system in-game without restarting the resource
Config.DevMode = false                    -- master switch, the command below does nothing while this is false
Config.DevCommand = 'restartinventory'     -- command name (no leading slash)
Config.DevPermission = 'admin'             -- must match the player's jrsCore.getUser(source).group value
Config.DevReopenInventory = false          -- reopen the inventory UI for the admin after a successful reinit
Config.Debug = false                      -- print debug info to server console (Dev Mode + general script debug)
Config.SaveDrops = false                   -- save ground drops to DB (false = in-memory only, cleared periodically + on restart)
Config.DropCleanupIntervalMs = 300000      -- cleanup interval in ms when SaveDrops is false (300000 = 5 min)
