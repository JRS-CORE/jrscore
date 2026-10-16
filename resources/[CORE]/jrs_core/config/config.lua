-- ==========================================================================
--  JRS CORE  |  Core settings
--  jrs_core configuration
-- ==========================================================================
Config = Config or {}


-- --------------------------------------------------------------------------
--  Core
-- --------------------------------------------------------------------------
do
Config = Config or {}
Config.defaultlang = "ar" -- Available: en, ar
-- Fallback only. Each player picks their own language on the character screen
-- and it is stored in users.language; this value is what a brand new account
-- starts on and what server-side console/log text uses.

Config.Onesync = true

Config.Info_print = false

-- Require an issued jrs_idcard for every new job assignment (including admins).
-- Unemployed remains available for firing/quitting. Existing jobs are not removed.
Config.JobIdentity = { Required = false } -- true needs jrs_idcard
-- Character slots every player starts with. This is the default only: a slot
-- count granted to one player with /addchar is stored in users.chars_override
-- and is never touched by this value. On boot, every player WITHOUT such an
-- override is set back to this number, so lowering it applies to existing
-- accounts too, not just new ones. Max 5.
-- Keep this in step with Config.Creator.Slots.default in
-- [character]/jrs_character/config/config.lua, which reads this value.
Config.Char_Count = 1

Config.Eagle_Eye = true
Config.Whitelist = false          -- Enable whitelist checks
Config.WhitelistDiscord = false   -- Discord & Database whitelist check
Config.DiscordInvite = "https://discord.gg/your-invite"
Config.DiscordWhitelistRole = "" -- Discord role id required when WhitelistDiscord = true

-- Connection requirements (kick player if condition not met)
Config.RequireSteam = true    -- Steam is required (needs steam_webApiKey in server.cfg). Set false to let players join without Steam
Config.RequireDiscord = false -- Require a Discord identifier from Cfx/RedM

Config.MaxHealth = 10 -- 10 is max value, 0 is empty core for the players.
Config.MaxStamina = 10 -- 10 is max value, 0 is empty core for the players.

Config.StartMoney = 35.00 -- Starter Cash ($35.00)
Config.StartGold = 0.15   -- RDO Exact Starter Gold (0.15 Gold)
Config.StartDirtyMoney = 0 -- Starting illegal/dirty money balance for new characters

-- Currency types used by jrs_core
Config.CurrencyTypes = {
    Money = 0,
    Gold = 1,
    Rol = 2,
    DirtyMoney = 3,
}

-- Official Red Dead Online Starter Kit (Items & Arrows, No Firearm Ammo, No Lasso)
Config.StartItems = {
    Bread = 3,
    consumable_kidneybeans_can = 2,
    water = 3,
    consumable_coffee = 1,
    ammoarrownormal = 5,
}

-- Starter Weapon: ONLY Bow & Loaded Arrows (No firearms, no lasso)
Config.StartWeapons = {
    { name = "WEAPON_BOW", ammo = 5 },
}


-- Legacy static density fallback. Used only when Config.Performance.Enabled = false.
Config.Traffic = {
    enabled = true,
    pedFrequency = 0.05,      -- Humans only. Animals are controlled separately in config/animals.lua.
    trafficFrequency = 0.0,  -- Ambient/random/parked wagons.
}

-- Animals are intentionally separate from traffic/performance so hunting
-- population is not reduced when nearby-player performance levels change.
-- See config/animals.lua.

-- Adaptive human/vehicle density settings are in config/performance.lua.

-- Unlock map discoveries/landmarks for every player.
-- Set enabled = false to keep the normal game discovery behavior.
Config.MapDiscoveries = {
    enabled = true,
    disableOnResourceStop = true, -- Restore discoveries to disabled when jrs_core stops.
    debug = false,
}

-- minimap mode.
-- mode options: "small", "medium", "hidden"
Config.MiniMap = {
    enabled = true,
    -- "hidden": the native map is off; jrs_metabolism's map compass is the minimap.
    mode = "small", -- "hidden" only if you run a compass HUD (jrs_metabolism)
    showOnMountOrVehicle = true, -- Always show radar/minimap when riding a horse or wagon/vehicle
    vehicleMode = "small",       -- Radar mode when on horse or in wagon ("small" or "medium")
    lockMode = true, -- Prevent players from opening the native radar-mode selector.
    applyDelay = 1500, -- Delay before applying the mode after the character becomes ready.
    restoreOnResourceStop = true, -- Show the radar again if jrs_core is stopped/restarted.
    debug = false,
}


Config.MapObject        = false -- If true, a map object will be attached to the players hand when opening the map.

Config.NegativeValueOnAccounts = false

-- Discord Rich Presence
Config.DiscordRichPresence = false                     -- تفعيل الـ Rich Presence من داخل jrs_core
Config.DiscordID = ""                                              -- Application ID من Discord Developer Portal
Config.DiscordBigLogo = "logoname"                     -- اسم الصورة الكبيرة المرفوعة في Discord Developer Portal
Config.DiscordPText = "سيرفر JRS Core Roleplay"      -- النص الذي يظهر عند وضع الماوس على الشعار الكبير
Config.DiscordSmallLogo = "smallboy_name"              -- اسم الصورة الصغيرة
Config.DiscordSText = "انضم إلينا لقضاء وقت ممتع"       -- النص الذي يظهر عند وضع الماوس على الشعار الصغير
Config.DiscordShowNameAndId = true                     -- إظهار اسم اللاعب والـ ID
Config.DiscordButtons = {                              -- أزرار الديسكورد (الحد الأقصى زرين)
    { text = 'DISCORD | ديسكورد', url = 'https://discord.gg/your-invite' },
    { text = 'CONNECT | اتصال', url = 'https://cfx.re/join/xxxxxx' }
}
Config.MaxPlayers = nil -- اضبطه على nil ليطابق تلقائياً sv_maxclients من server.cfg

-- Currency display symbols
Config.CurrencyMoneySymbol = "$ "
Config.CurrencyGoldSymbol = "𝕲 "
Config.CurrencyDirtyMoneySymbol = "$ "
Config.CurrencyXpSymbol = "LV " -- HUD now displays the calculated level, not raw XP

-- HUD update settings
Config.HudUpdateInterval = 5000 -- ms between HUD data requests
Config.HudReadyDelay = 9000 -- legacy compatibility only; CharacterReady now controls HUD visibility

-- HUD debug prints (true = show prints in F8 console)
-- Keep this false in normal play: true makes the HUD spam the console every
-- Config.HudUpdateInterval with the money/job/level payload.
Config.HudDebug = false

-- Level / XP presentation copied from alfie_level UI only.
-- The XP system, database and commands still belong entirely to jrs_core.
Config.LevelHud = {
    enabled = true,
    peekControlHash = 0xAC4BD4F1, -- TAB: opens weapon wheel & peeks Level HUD on top left like RDO
    showOnPauseMenu = false, -- Only show on TAB
    pollIdleMs = 100,
    showLevelToast = false, -- Toast disabled so it only shows on TAB
    toastDurationMs = 4000,
    clearChatOnPeek = false,
    autoShowOnUpdate = false, -- Disabled: Level HUD only shows when TAB is pressed
    autoShowDurationMs = 4500,
}

-- Global timed XP multiplier. All global XP and per-script/job XP granted
-- through jrs_core AddXP/AddJobXP/events/API is multiplied while the event is
-- active. RemoveXP, RemoveJobXP, SetXP and SetJobXP are unchanged.
Config.DoubleXP = {
    enabled = true,
    tableName = "jrs_double_xp_state", -- created automatically
    maxMultiplier = 10.0,
    maxDurationMinutes = 10080, -- 7 days
    announceStart = true,
    announceEnd = true,

    -- Automatic event: after every server/resource start, ONE boost (x2 or x3,
    -- picked at random) is scheduled to begin after a random delay. Skipped if
    -- an admin event is already running when the timer fires.
    -- XP reasons (prefix match, case-insensitive) that are never multiplied.
    exemptReasonPrefixes = { 'admin', 'discord bot', 'gift bundle', 'starter_origin', 'battlepass:' },

    autoEvent = {
        enabled = true,
        minDelayMinutes = 60,   -- earliest start after restart (1h)
        maxDelayMinutes = 180,  -- latest start after restart (3h)
        multipliers = { 2, 3 }, -- random pick: double or triple
        minDurationMinutes = 60,  -- boost lasts random 1h..3h
        maxDurationMinutes = 180,
    },
}

-- Compact HUD (money, gold, job, level, town, PVP, Double XP banner).
--   enabled        developer master switch: false turns the compact HUD off for everyone
--   PlayerCommand  command players use to hide / show it (remembered on their PC), false = no command
--   <element>      false = that element is never shown on this server
Config.Hud = {
    enabled = true,
    PlayerCommand = "hud",
    PlayerGold = true,   -- gold
    PlayerMoney = true,  -- money
    PlayerDirtyMoney = true, -- dirty money
    id = true,           -- player ID
    job = true,          -- job
    xp = true,           -- level
    town = true,         -- current town
    pvp = true,          -- PVP ON/OFF
    doubleXpHud = true,  -- Double XP banner
}

-- Layout for characters that have no saved layout yet. Players move, resize and
-- hide single elements in /editcorehud. visible = false starts an element hidden.
Config.HudDefaultLayout = {
    PlayerGold       = { x = 0.95, y = 0.05, scale = 1.0, visible = true },
    PlayerMoney      = { x = 0.95, y = 0.08, scale = 1.0, visible = true },
    PlayerDirtyMoney = { x = 0.95, y = 0.11, scale = 1.0, visible = true },
    id               = { x = 0.95, y = 0.14, scale = 1.0, visible = true },
    job              = { x = 0.95, y = 0.17, scale = 1.0, visible = true },
    xp               = { x = 0.95, y = 0.20, scale = 1.0, visible = true },
    town             = { x = 0.95, y = 0.23, scale = 1.0, visible = true },
    pvp              = { x = 0.95, y = 0.26, scale = 1.0, visible = true },
    doubleXpHud      = { x = 0.50, y = 0.02, scale = 1.0, visible = true },
}
-- Central HUD gate (client/hud_gate.lua).
-- When a script opens its UI, BOTH the jrs_core compact HUD and the
-- jrs_metabolism status HUD are hidden, and they come back when it is closed.
--
-- UI only, on purpose. Animations and scripted cameras are not detected: they
-- have no dependable "finished" signal, so one script leaving a ped animated
-- would hide the HUD permanently. Scripts whose UI takes no NUI focus report
-- it themselves with TriggerEvent('jrs_hud:busy', '<resource>', true/false).
Config.HudGate = {
    enabled = true,
    checkInterval = 100,   -- ms between detection passes
    releaseDelayMs = 250,  -- wait this long after the UI closes before showing the HUD again

    -- Safety net: a blocker that is never released expires by itself, so the
    -- HUD can never disappear permanently. Long enough that a real menu session
    -- is never cut short; scripts that watch a UI flag also refresh it while
    -- their UI stays open. /hudshow clears every blocker at once.
    maxBlockMs = 60000,

    autoHide = {
        OnDeath        = true, -- player dead / dying
        OnNuiFocus     = true, -- any script UI holding NUI focus
        OnStateBagMenu = true, -- common invOpen / menuOpen / uiOpen state-bag flags
        OnPauseMenu    = true,
        OnMap          = true,
        OnWeaponWheel  = true, -- TAB / weapon wheel hides metabolism only (never core/level HUD - see hud_gate.lua)
    },
}

-- Players use /editcorehud to move, resize, show or hide compact HUD elements.
-- Position, size and visibility are stored per character in jrs_core_hud_layouts.
Config.HudEditor = {
    enabled = true,
    command = "editcorehud",
    visibilityCheckInterval = 150,

    -- Hand-off button at the bottom of the editor's General tab. Pressing it
    -- saves the layout, closes this editor and opens the OTHER HUD's editor,
    -- so the two can be arranged in one sitting instead of two commands.
    --
    -- Set enabled = false if jrs_metabolism is not on this server: the button
    -- then never appears at all. It is ALSO hidden automatically whenever that
    -- resource is missing or stopped, so a server without it can never end up
    -- showing a button that does nothing.
    link = {
        enabled  = true,
        resource = "jrs_metabolism",
        event    = "jrs_metabolism:hud:openEditor",
        label    = "Metabolism HUD",
        hint     = "Saves this layout, closes this editor and opens the metabolism HUD editor.",
    },
}

-- ============================================================================
-- JRS Custom Aiming Reticle (Crosshair) / مؤشر التصويب المخصص - JRS
-- ============================================================================
-- مدمج مباشرة داخل الكور وقسم تعديل الهود (/editcorehud)
-- Enabled: تفعيل أو إيقاف نظام مؤشر التصويب بالكامل من السيرفر (true / false)
-- EnableCommand: تفعيل أو إيقاف أمر الاختصار المباشر /jrs_crosshair
-- Command: اسم الأمر المستخدم للاختصار (افتراضياً: "jrs_crosshair")
-- ============================================================================
Config.JrsCrosshair = {
    Enabled       = true,            -- تفعيل/تعطيل مؤشر التصويب بالكامل (Master switch)
    EnableCommand = false,           -- إيقاف أمر الاختصار المباشر، والتعديل يكون من هود الكور فقط (/editcorehud)
    Command       = "jrs_crosshair", -- اسم الأمر الأساسي (/jrs_crosshair أو /crosshair)
    Debug         = false,           -- طباعة سجلات التصحيح في الكونسول (Debug logs)
}
Config.Crosshair = Config.JrsCrosshair

-- Player-to-player interactions used by jrs_inventory.
-- Enabled is the master switch; individual actions can also be disabled.
Config.PlayerInteractions = {
    Enabled = true,
    GiveHand = true,
    GiveSlap = true,
    TakeHostage = true,

    GiveHandControlHash = `INPUT_CONTEXT_X`,
    GiveSlapControlHash = `INPUT_INTERACT_OPTION1`,
    TakeHostageControlHash = `INPUT_PROMPT_PAGE_NEXT`,
    ReleaseControlHash = 0x07CE1E61,

    SocialActionCooldownMs = 2000,
    HostageTakeCooldownMs = 1000,
}

-- Coords save settings
Config.CoordsSaveTimerOnesync = 180000 -- 3 min, interval for onesync mode (reduced from 10 min to ensure coords are fresh on player drop)
Config.CoordsSaveTimerLegacy = 60000  -- 1 min, interval for legacy mode
Config.CoordsSaveDistance = 10.0 -- min distance moved before saving coords
Config.CoordsSaveSkipZones = {
    { x = 1407.43, y = -1139.52, z = 75.35, radius = 5.0 },
    { x = -563.77, y = -3776.49, z = 238.56, radius = 20.0 }
}

-- Heal player values
Config.HealInnerCore = 100
Config.HealOuterHealth = 600
Config.HealStaminaFlag = 1065330373

-- Teleport settings
Config.TeleportFadeOut = 500
Config.TeleportFadeIn = 650
Config.TeleportWait = 1000
Config.TeleportStartHeight = 650.0
Config.TeleportStartPoint = 750.0

-- New character default values
Config.DefaultSpawnCoords = { x = 1240.63, y = -1282.88, z = 75.94 }
Config.DefaultCharacterStatus = '{"Hunger":100.0, "Thirst":100.0}'

-- Dev mode (extra prints)
Config.DevMode = false

-- Player count broadcast interval
Config.PlayerCountInterval = 30000 -- 30 s in ms (Discord presence player count refresh)

-- Command names
Config.Commands = {
    addwhitelist = "addwh",
    removewhitelist = "removewh",
    checkwhitelist = "checkwh",
    setjob = "addjob",
    setchar = "addchar",
    delchar = "delchar",
    setgroup = "addgroup",
    getplayers = "getplayers",
    listPlayers = "listPlayers",
    giveitem = "additem",
    giveweapon = "addweapon",
    givemoney = "addmoney",
    addxp = "addxp",
    removexp = "removexp",
    setxp = "setxp",
    setlevel = "setlevel",
    addlevel = "addlevel",
    doublexp = "doublexp", -- /doublexp 2 60 | /doublexp status | /doublexp stop
    revive = "revive",
    tpm = "tpm", -- teleport to a player: /tpm [id] -- teleport to the map waypoint
    setlang = "setlang", -- set another player's language: /setlang [id] [en|ar]
    language = "language", -- admin self language switch: /language [en|ar]
}

-- Groups allowed to use administrator commands.
-- Keys are case-insensitive; set a value to false to disable that group.
Config.AdminGroups = {
    owner = true,
    admin = true,
    support = true,
}

-- Core owners: identifiers that ALWAYS receive the full "owner" group straight
-- from jrs_core, no matter what the users database row says. The owner group is
-- also written back to the database on connect, so jrs_admin (which maps core
-- owner -> server_owner) and every /command permission sees full access.
-- Add more identifiers as ['steam:...'] = true (license:/discord: also work).
Config.CoreOwners = {
    -- ['steam:110000xxxxxxxxx'] = true,
}

-- Re-check users.group for connected players with one batched database query.
-- This keeps permission groups correct even after a manual DB edit while a
-- player is online. Set to 0 to disable automatic refresh.
Config.GroupSyncIntervalMs = 15000

-- Config.IsAdminGroup(group) and Config.CanUseCommand(group, commandKey) live in
-- server/permissions.lua (logic moved out of config so this file stays values-only).

-- Per-command permissions.
-- Owner only:       { "owner" }
-- Admin only:       { "admin" }
-- Owner + admin:    { "owner", "admin" }
-- All staff:        { "owner", "admin", "support" }
Config.CommandPermissions = {
    addwhitelist   = { "owner", "admin", "support" },
    removewhitelist = { "owner", "admin", "support" },
    checkwhitelist  = { "owner", "admin", "support" },
    setjob     = { "owner", "admin", "support" },
    setchar    = { "owner", "admin", "support" },
    delchar    = { "owner", "admin", "support" },
    setgroup   = { "owner", "admin", "support" },
    giveitem   = { "owner", "admin", "support" },
    giveweapon = { "owner", "admin", "support" },
    givemoney  = { "owner", "admin", "support" },
    addxp      = { "owner", "admin", "support" },
    removexp   = { "owner", "admin", "support" },
    setxp      = { "owner", "admin", "support" },
    setlevel   = { "owner", "admin", "support" },
    addlevel   = { "owner", "admin", "support" },
    revive     = { "owner", "admin", "support" },
    doublexp   = { "owner", "admin", "support" },
    tpm        = { "owner", "admin", "support" },
    performance = { "owner", "admin", "support" },
    setlang    = { "owner", "admin", "support" },
    language   = { "owner", "admin", "support" },
}

-- Player disconnect marker
-- Integrated replacement for the old standalone jrs_playerDropped resource.
Config.PlayerDropped = {
    Enabled = true,              -- master switch for the entire feature
    Lifetime = 300,              -- seconds a disconnect marker remains active
    UpdateInterval = 10000,      -- client position snapshot interval (ms)
    MaxActiveSigns = 50,         -- safety limit for simultaneous disconnect markers

    UsePed = true,               -- spawn a frozen ped at the last player position
    PedModel = 'mp_male',        -- fallback model if the player's model cannot be loaded
    PedCollision = false,        -- false prevents disconnect peds blocking players
    SpawnDistance = 80.0,        -- only create the local ped/board inside this distance
    DrawDistance = 25.0,         -- 3D text visibility distance
    ManagerInterval = 250,       -- idle manager interval when no text is being drawn (ms)
    ModelLoadTimeout = 5000,

    UseBoard = true,
    BoardModel = 'P_BOARD01X',
    BoardPedBone = 18905,
    BoardBoneIndex = 0x49D9,     -- fallback bone index
    BoardOffset = { x = 0.0, y = 0.0, z = 0.0 },
    BoardRotation = { x = 0.0, y = 0.0, z = 0.0 },

    TextHeight = 1.15,
    TextScale = 0.30,
    TextFont = 25,
    ShowServerId = true,
    ShowCharacterId = true,
    ShowReason = true,
    ShowDisconnectTime = true,
    TimeFormat = '%H:%M',
}

-- Native RDR2 award / toast banners blocker (integrated from jrs_feed)
Config.Feed = {
    Enabled = true,
    HideAwardToasts = true,        -- Hide Survivalist / Collector / Sharpshooter award banners
    HideAppLinkToasts = true,      -- Hide "Hold F1 for details" toast style
    HideFeedToast = true,          -- Extra native toast slot (0xDAABF7FD)
    HideFeedLhmToast = true,       -- Extra native toast slot (0xD211C444)
    ClearOnChallengeEvents = true, -- Clear toast channels when challenge/award event fires
    KeepHidden = true,             -- Keep running a light hide loop
    HideInterval = 0,              -- Hide loop interval in ms (0 = every frame)
    DisableToastChannels = true,   -- Suppress native toast channels (1 and 6)
    ToggleCommand = 'toggleawards',-- Command to toggle award blocker
}
end


-- --------------------------------------------------------------------------
--  Server management
-- --------------------------------------------------------------------------
do
-- JRS server management and connection protection.

Config.ConnectionGuard = Config.ConnectionGuard or {
    -- Optional grace period after jrs_core starts. Useful when dependent resources/DB need time.
    StartupDelay = {
        Enabled = false,
        Seconds = 20,
        Message = "The server is still starting. Please reconnect in %s seconds.\n(الخادم ما زال قيد التشغيل. يرجى إعادة الاتصال خلال %s ثانية.)",
    },

    -- Reject obviously unsafe/control-character player names during connection.
    PlayerName = {
        Enabled = true,
        MaxLength = 64,
        RejectPatterns = {
            "<",
            ">",
            "http://",
            "https://",
            "\n",
            "\r",
        },
        Message = "Your player name contains unsupported characters or text.\n(اسم اللاعب يحتوي على رموز أو نص غير مدعوم.)",
    },
}

-- Scheduled restart helper. This does not restart the server itself.
-- It can announce upcoming restarts, block new connections during a window,
-- and optionally kick connected players at a configured time so data can save cleanly.
Config.RestartManagement = Config.RestartManagement or {
    Enabled = false,
    Debug = false,

    -- Server-machine local time, HH:MM 24-hour format.
    BlockJoinWindows = {
        -- { From = "05:50", To = "05:59" },
    },

    KickTimes = {
        -- "05:57",
    },

    Announcements = {
        -- ["05:00"] = { Text = "Server restart in 60 minutes.", DurationMs = 10000 },
        -- ["05:30"] = { Text = "Server restart in 30 minutes.", DurationMs = 10000 },
        -- ["05:45"] = { Text = "Server restart in 15 minutes.", DurationMs = 10000 },
    },

    ConnectBlockedMessage = "The server is preparing to restart. Please reconnect in a few minutes.\n(الخادم يستعد لإعادة التشغيل. يرجى إعادة الاتصال خلال دقائق.)",
    KickMessage = "The server is restarting. Please reconnect in a few minutes.\n(الخادم يعيد التشغيل حالياً. يرجى إعادة الاتصال خلال دقائق.)",
}

-- Optional heartbeat state useful for anti-dupe / network-loss handling.
-- Disabled by default to avoid kicking players on unstable connections.
Config.NetworkGuard = Config.NetworkGuard or {
    Enabled = false,
    HeartbeatIntervalMs = 5000,
    TimeoutMs = 20000,
    KickOnTimeout = false,
    KickMessage = "You were disconnected because your network connection stopped responding.\n(تم قطع الاتصال بسبب عدم استجابة اتصال الشبكة.)",
    Debug = false,
}
end


-- --------------------------------------------------------------------------
--  Performance
-- --------------------------------------------------------------------------
do
-- JRS adaptive human / vehicle population performance controller.
-- This configuration is loaded by both client and server.

Config.Performance = {
    Enabled = true,

    -- How often the local nearby-player count is sampled.
    SampleIntervalMs = 2000,

    -- Radius used to decide how crowded the local area is.
    DensityRadius = 125.0,

    -- A mode must remain the best candidate for this long before it is applied.
    ModeChangeHoldMs = 4000,

    -- How often debug entity counts refresh while debug mode is enabled.
    DebugRefreshMs = 3000,
    DebugEntityRadius = 125.0,

    -- Shared state-bag key for important scripted entities.
    ProtectionStateKey = 'jrsProtected',

    -- Ambient/scenario human ("bot") density used while the local player is
    -- standing inside a jrs_safezone zone flagged isCity = true (the big towns
    -- only). Scripted/job NPCs (store clerks, doctors, sheriffs, etc.) are
    -- created directly by their own resources, not by this ambient population
    -- system, so they are never affected by this.
    CityAmbientHumans = 0.0,
    CityScenarioHumans = 0.0,

    -- Core admin commands. Permissions are controlled by
    -- Config.CommandPermissions.performance in config/config.lua.
    Commands = {
        status = 'jrsperf',
        debug = 'jrsperfdebug',
        mode = 'jrsperfmode',
    },

    -- Areas where adaptive density must remain at normal game density.
    -- Example:
    -- ExcludedAreas = {
    --     { coords = vector3(-276.0, 805.0, 119.0), radius = 60.0 },
    -- },
    ExcludedAreas = {},

    -- Adaptive profiles. minimumPlayers is inclusive.
    -- ULTRA-LOW human/wagon preset. Animal population is intentionally
    -- controlled separately by config/animals.lua and never scales with players.
    -- Values should stay between 0.0 and 1.0.
    Levels = {
        {
            name = 'normal',
            minimumPlayers = 1,
            ambientHumans = 0.05,
            scenarioHumans = 0.05,
            vehicleDensity = 0.00,
            randomVehicleDensity = 0.00,
            parkedVehicleDensity = 0.00,
        },
        {
            name = 'light',
            minimumPlayers = 11,
            ambientHumans = 0.04,
            scenarioHumans = 0.04,
            vehicleDensity = 0.00,
            randomVehicleDensity = 0.00,
            parkedVehicleDensity = 0.00,
        },
        {
            name = 'medium',
            minimumPlayers = 21,
            ambientHumans = 0.03,
            scenarioHumans = 0.03,
            vehicleDensity = 0.00,
            randomVehicleDensity = 0.00,
            parkedVehicleDensity = 0.00,
        },
        {
            name = 'high',
            minimumPlayers = 36,
            ambientHumans = 0.02,
            scenarioHumans = 0.02,
            vehicleDensity = 0.00,
            randomVehicleDensity = 0.00,
            parkedVehicleDensity = 0.00,
        },
        {
            name = 'event',
            minimumPlayers = 51,
            ambientHumans = 0.01,
            scenarioHumans = 0.01,
            vehicleDensity = 0.00,
            randomVehicleDensity = 0.00,
            parkedVehicleDensity = 0.00,
        },
    },
}
end


-- --------------------------------------------------------------------------
--  Shared library
-- --------------------------------------------------------------------------
do
-- ---------------------------------------------------------------------------
-- Shared helper library (merged in from the standalone jrs_lib resource)
--
-- jrs_lib used to define a bare `Config = {}` of its own. Inside jrs_core that
-- would wipe the framework's own Config table, so every former jrs_lib setting
-- now lives under Config.Lib.
-- ---------------------------------------------------------------------------

Config = Config or {}

Config.Lib = {
    -- Folder the built-in notification fallback pulls item icons from. Only
    -- used when jrs_notify is not running.
    FolderWithIcons = 'jrs_inventory/html/images/items/',

    -- Developer helpers jrs_lib registered unconditionally. Kept on so the
    -- merge does not silently remove tools that were already available.
    EnableDevCommands = true,
    PolyPointCommand  = 'polyPoint',
    TargetCommand     = 'target',

    -- Field names the server API reports back to callers.
    CharacterTable  = 'Characters',
    JobColumn       = 'job',
    JobGradeColumn  = 'jobgrade',
    SteamColumn     = 'identifier',
    CharIdColumn    = 'charidentifier',
}
end


-- --------------------------------------------------------------------------
--  Award / feed pop-ups
-- --------------------------------------------------------------------------
do
-- Native award/feed suppression merged from jrs_feed.
Config = Config or {}

Config.Feed = {
    Enabled = true,
    HideAwardToasts = true,
    HideAppLinkToasts = true,
    HideFeedToast = true,
    HideFeedLhmToast = true,
    ClearOnChallengeEvents = true,
    KeepHidden = true,
    HideInterval = 0,
    DisableToastChannels = true,
    ToggleCommand = 'toggleawards',
}
end


-- --------------------------------------------------------------------------
--  Characters
-- --------------------------------------------------------------------------
do

Config = Config or {}

Config.CharacterService = Config.CharacterService or {
    MaxJobs = 0, -- 0 = no limit (jrs_multijob matches)
    JobSwitchCooldownSeconds = 10,
    DefaultDuty = false,
    PersistHealthStamina = true,
    OfflineLookupLimit = 50,
    Skills = {
        Mining = { maxLevel = 100, xpPerLevel = 100 },
        Lumberjack = { maxLevel = 100, xpPerLevel = 100 },
        Fishing = { maxLevel = 100, xpPerLevel = 100 },
        Hunting = { maxLevel = 100, xpPerLevel = 100 },
        Farming = { maxLevel = 100, xpPerLevel = 100 },
        HorseTraining = { maxLevel = 100, xpPerLevel = 100 },
    }
}
end
