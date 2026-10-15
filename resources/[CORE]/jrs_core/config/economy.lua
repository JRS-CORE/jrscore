-- ==========================================================================
--  JRS CORE  |  Economy
--  jrs_core configuration
-- ==========================================================================
Config = Config or {}


-- --------------------------------------------------------------------------
--  Economy
-- --------------------------------------------------------------------------
do
-- ============================================================================
-- JRS CORE — CENTRALIZED MASTER ECONOMY CONFIGURATION
-- ============================================================================
-- All scripts should reference this central matrix for item prices, job base
-- payouts, money sinks, economic tiers, and anti-exploit threshold multipliers.
-- ============================================================================

Config = Config or {}
Config.Economy = Config.Economy or {}

-- Core Economic System Enable Flag
Config.Economy.Enabled = true

-- Master Scarcity Multipliers (1899 Realism & Scarcity Philosophy)
-- Payouts routed through getCoreApi().AddReward(...) or AddJobXP(...) use these multipliers.
-- Everyday activities pay in modest cents; wealth accumulation is deliberate and hard-earned.
Config.Economy.RewardMultiplier = 0.35   -- Gameplay cash payouts scaled to 35%
Config.Economy.GoldMultiplier   = 0.50   -- Gold rewards scaled to 50%
Config.Economy.XpMultiplier     = 1.00   -- XP progression multiplier
Config.Economy.MinReward        = 0.05   -- Floor minimum for fractional earnings (5 cents)

-- Default Store Sell Margin (Prevents Shop Arbitrage)
-- Players selling items back to stores/butchers receive between 35% and 45% of buying value
Config.Economy.DefaultSellMargin = 0.40

-- ============================================================================
-- 1. ECONOMIC TIERS & HOURLY EARNING TARGETS (1899 Cents Scale)
-- ============================================================================
Config.Economy.Tiers = {
    [1] = { name = "Tier 1: Survival",     minHourly = 4.00,   maxHourly = 9.00,   targetPer10Min = 1.00 },
    [2] = { name = "Tier 2: Established",  minHourly = 12.00,  maxHourly = 25.00,  targetPer10Min = 3.00 },
    [3] = { name = "Tier 3: Professional", minHourly = 30.00,  maxHourly = 55.00,  targetPer10Min = 7.00 },
    [4] = { name = "Tier 4: End Game",     minHourly = 65.00,  maxHourly = 120.00, targetPer10Min = 15.00 },
}

-- ============================================================================
-- 2. MASTER ITEM PRICE CATALOG (Centralized Store & Crafting Reference)
-- ============================================================================
-- Everyday survival items cost mere cents, keeping basic needs accessible.
-- Durable weapons and luxury assets remain expensive goals.
Config.Economy.ItemPrices = {
    -- Food & Consumables (Pennies & Cents)
    ["bread"]               = { buy = 0.20,  sell = 0.08, category = "Food" },
    ["stew"]                = { buy = 0.45,  sell = 0.18, category = "Food" },
    ["canned_beans"]        = { buy = 0.25,  sell = 0.10, category = "Food" },
    ["salted_meat"]         = { buy = 0.50,  sell = 0.20, category = "Food" },
    ["cooked_meat"]         = { buy = 0.70,  sell = 0.28, category = "Food" },

    -- Drinks (Accessible Cents)
    ["water"]               = { buy = 0.10,  sell = 0.04, category = "Drinks" },
    ["consumable_coffee"]   = { buy = 0.20,  sell = 0.08, category = "Drinks" },
    ["beer"]                = { buy = 0.35,  sell = 0.12, category = "Drinks" },
    ["wine"]                = { buy = 1.25,  sell = 0.50, category = "Drinks" },
    ["whiskey"]             = { buy = 2.00,  sell = 0.80, category = "Drinks" },
    ["moonshine"]           = { buy = 4.50,  sell = 2.00, category = "Drinks" },

    -- Medical Supplies
    ["bandage"]             = { buy = 0.40,  sell = 0.15, category = "Medical" },
    ["health_tonic"]        = { buy = 1.50,  sell = 0.60, category = "Medical" },
    ["miracle_tonic"]       = { buy = 3.50,  sell = 1.40, category = "Medical" },
    ["snake_oil"]           = { buy = 1.80,  sell = 0.70, category = "Medical" },
    ["revive_medicine"]     = { buy = 5.00,  sell = 2.00, category = "Medical" },

    -- Tools & Equipment (Balanced Initial Investments)
    ["pickaxe"]             = { buy = 5.50,  sell = 2.00, category = "Tools" },
    ["axe"]                 = { buy = 4.50,  sell = 1.60, category = "Tools" },
    ["fishing_rod"]         = { buy = 7.50,  sell = 2.80, category = "Tools" },
    ["bucket"]              = { buy = 1.50,  sell = 0.50, category = "Tools" },
    ["watering_can"]        = { buy = 2.25,  sell = 0.80, category = "Tools" },
    ["lockpick"]            = { buy = 12.00, sell = 4.00, category = "Tools" },

    -- Ammunition (Cents per Box)
    ["ammo_revolver"]       = { buy = 0.35,  sell = 0.12, category = "Ammunition" },
    ["ammo_pistol"]         = { buy = 0.35,  sell = 0.12, category = "Ammunition" },
    ["ammo_repeater"]       = { buy = 0.35,  sell = 0.12, category = "Ammunition" },
    ["ammo_rifle"]          = { buy = 0.40,  sell = 0.15, category = "Ammunition" },
    ["ammo_shotgun"]        = { buy = 0.40,  sell = 0.15, category = "Ammunition" },

    -- Weapons (Official RDO Catalogue Prices)
    ["weapon_revolver_cattleman"] = { buy = 50.00,  sell = 20.00, category = "Weapons" },
    ["weapon_revolver_schofield"] = { buy = 192.00, sell = 75.00, category = "Weapons" },
    ["weapon_repeater_carbine"]   = { buy = 90.00,  sell = 36.00, category = "Weapons" },
    ["weapon_repeater_winchester"]= { buy = 348.00, sell = 140.00,category = "Weapons" },
    ["weapon_rifle_boltaction"]   = { buy = 216.00, sell = 85.00, category = "Weapons" },
    ["weapon_shotgun_doublebarrel"]= { buy = 185.00,sell = 75.00, category = "Weapons" },

    -- Farming Seeds & Inputs (Cents)
    ["corn_seed"]           = { buy = 0.08,  sell = 0.03, category = "Farming" },
    ["wheat_seed"]          = { buy = 0.10,  sell = 0.04, category = "Farming" },
    ["carrot_seed"]         = { buy = 0.12,  sell = 0.05, category = "Farming" },
    ["tobacco_seed"]        = { buy = 0.30,  sell = 0.10, category = "Farming" },
    ["fertilizer"]          = { buy = 0.25,  sell = 0.08, category = "Farming" },

    -- Harvested Crops (Pennies to Cents Earnings)
    ["corn"]                = { buy = 0.35,  sell = 0.18, category = "Farming" },
    ["wheat"]               = { buy = 0.45,  sell = 0.22, category = "Farming" },
    ["carrot"]              = { buy = 0.40,  sell = 0.20, category = "Farming" },
    ["tobacco"]             = { buy = 1.10,  sell = 0.60, category = "Farming" },

    -- Mining Ores & Processed Materials (Modest Cents)
    ["coal"]                = { buy = 0.35,  sell = 0.15, category = "Mining" },
    ["copper_ore"]          = { buy = 0.60,  sell = 0.25, category = "Mining" },
    ["iron_ore"]            = { buy = 0.85,  sell = 0.38, category = "Mining" },
    ["silver_ore"]          = { buy = 2.50,  sell = 1.25, category = "Mining" },
    ["gold_nugget"]         = { buy = 6.00,  sell = 3.00, category = "Mining" },
    ["iron_ingot"]          = { buy = 2.25,  sell = 1.10, category = "Mining" },
    ["gold_bar"]            = { buy = 50.00, sell = 25.00,category = "Mining" },

    -- Animal Pelts & Carcasses (Butcher Trade)
    ["pelt_poor"]           = { buy = 0.75,  sell = 0.35, category = "Hunting" },
    ["pelt_good"]           = { buy = 1.75,  sell = 0.90, category = "Hunting" },
    ["pelt_perfect"]        = { buy = 4.00,  sell = 2.10, category = "Hunting" },
    ["carcass_deer"]        = { buy = 4.50,  sell = 2.25, category = "Hunting" },
    ["carcass_bear"]        = { buy = 15.00, sell = 7.50, category = "Hunting" },
    ["alligator_skin"]      = { buy = 6.50,  sell = 3.50, category = "Hunting" },
}

-- ============================================================================
-- 3. JOB BASE PAYOUT & EXP FORMULAS (Cents Scale)
-- ============================================================================
Config.Economy.JobBaseRates = {
    ["farmer"]      = { basePay = 0.20, levelBonus = 0.02, tier = 1, baseXP = 15 },
    ["miner"]       = { basePay = 0.35, levelBonus = 0.04, tier = 2, baseXP = 25 },
    ["hunter"]      = { basePay = 0.45, levelBonus = 0.05, tier = 2, baseXP = 30 },
    ["lumberjack"]  = { basePay = 0.25, levelBonus = 0.03, tier = 1, baseXP = 20 },
    ["fisher"]      = { basePay = 0.20, levelBonus = 0.03, tier = 1, baseXP = 18 },
    ["bounty"]      = { basePay = 5.00, levelBonus = 0.50, tier = 3, baseXP = 100 },
    ["delivery"]    = { basePay = 3.50, levelBonus = 0.30, tier = 2, baseXP = 50 },
    ["police"]      = { salary  = 12.00,arrestBonus = 3.0, tier = 2, baseXP = 40 },
    ["doctor"]      = { feeShare= 0.70, reviveBonus = 2.0, tier = 2, baseXP = 35 },
    ["blacksmith"]  = { basePay = 1.25, levelBonus = 0.10, tier = 3, baseXP = 45 },
    ["trash"]       = { basePay = 0.25, levelBonus = 0.03, tier = 1, baseXP = 25 },
}

-- ============================================================================
-- 4. MONEY SINKS & ONGOING SYSTEM EXPENSES
-- ============================================================================
Config.Economy.MoneySinks = {
    -- Horse & Stable
    StableFeeDaily          = 1.50,   -- Daily maintenance per owned horse
    HorseReviveFee          = 15.00,  -- Cost to recover fallen horse at stable

    -- Housing & Real Estate
    PropertyTaxWeeklyRate   = 0.015,  -- 1.5% weekly property tax rate based on purchase value
    HousingUpkeepBase       = 5.00,   -- Weekly baseline maintenance fee

    -- Medical & Healthcare
    DoctorReviveBaseFee     = 10.00,  -- Base doctor revive/respawn fee
    DoctorRevivePercentCap  = 0.02,   -- Max 2% of player cash on hand for revive

    -- Banking & Financial
    BankWireTransferFee     = 1.00,   -- Flat fee per wire transaction
    BankWirePercentFee      = 0.01,   -- 1% fee on large transfers

    -- Repair & Maintenance
    ToolDurabilityRepairPer = 0.05,   -- $0.05 per 1% tool durability restored
    WeaponCleaningKitCost   = 3.50,   -- Cost for gun oil / cleaning supplies
}

-- ============================================================================
-- 5. CRIME & OUTLAW BALANCING
-- ============================================================================
Config.Economy.Crime = {
    HouseRobberyRewardMin   = 15.00,
    HouseRobberyRewardMax   = 45.00,
    StoreRobberyRewardMin   = 40.00,
    StoreRobberyRewardMax   = 110.00,
    BankRobberyRewardMin    = 250.00,
    BankRobberyRewardMax    = 600.00,
    TrainRobberyRewardMin   = 200.00,
    TrainRobberyRewardMax   = 500.00,

    -- Crime Cooldowns (Minutes)
    HouseRobberyCooldown    = 20,
    StoreRobberyCooldown    = 30,
    BankRobberyCooldown     = 60,
    TrainRobberyCooldown    = 45,

    -- Outlaw Equipment Costs
    DynamiteCost            = 40.00,
    LockpickCost            = 25.00,
}

-- ============================================================================
-- 6. ANTI-INFLATION & TRANSACTION AUDIT THRESHOLDS
-- ============================================================================
Config.Economy.AntiExploit = {
    MaxTransactionSingleVal = 2000.00, -- Single transaction flag threshold
    MaxCashTransferPerMin   = 500.00,  -- Cash drop/transfer rate limit
    MaxJobPayoutPerMin      = 150.00,  -- Maximum total job payouts permitted per minute
    AuditLogConsoleAlert    = true,    -- Log large transactions to server log
}

-- ============================================================================
-- 7. STARTER ORIGINS & CHARACTER BACKGROUND SELECTION
-- ============================================================================
Config.Economy.StarterOrigins = {
    Enabled = true,
    Origins = {
        ["hunter"] = {
            id = "hunter",
            label = "صياد (Hunter)",
            description = "ابدأ كصياد في البرية مع معدات الصيد وأدوات السلخ والتعقب.",
            money = 15.00,
            items = { { item = "Bread", count = 2 }, { item = "water", count = 2 }, { item = "p_crawdad01x", count = 3 } },
            jobXP = { job = "hunter", xp = 100 }
        },
        ["farmer"] = {
            id = "farmer",
            label = "مزارع (Farmer)",
            description = "ابدأ كمزارع في الريف مع بذور المحاصيل وأدوات الزراعة.",
            money = 15.00,
            items = { { item = "Bread", count = 2 }, { item = "water", count = 2 }, { item = "corn_seed", count = 5 }, { item = "watering_can", count = 1 } },
            jobXP = { job = "farmer", xp = 100 }
        },
        ["miner"] = {
            id = "miner",
            label = "عامل مناجم (Miner)",
            description = "ابدأ كعامل مناجم مع فأس التعدين وأدوات العمل الشاق.",
            money = 15.00,
            items = { { item = "Bread", count = 2 }, { item = "water", count = 2 }, { item = "pickaxe", count = 1 } },
            jobXP = { job = "miner", xp = 100 }
        },
        ["outlaw"] = {
            id = "outlaw",
            label = "خارج عن القانون (Outlaw)",
            description = "ابدأ كخارج عن القانون مع الويسكي وأداة فتح الأقفال.",
            money = 15.00,
            items = { { item = "Bread", count = 2 }, { item = "water", count = 2 }, { item = "whiskey", count = 1 }, { item = "lockpick", count = 1 } },
            jobXP = { job = "bounty", xp = 100 }
        },
        ["trader"] = {
            id = "trader",
            label = "تاجر (Trader)",
            description = "ابدأ كتاجر طموح مع مؤن إضافية للتجارة والترحال.",
            money = 15.00,
            items = { { item = "Bread", count = 3 }, { item = "water", count = 3 }, { item = "consumable_coffee", count = 1 } },
            jobXP = { job = "delivery", xp = 100 }
        },
        ["laborer"] = {
            id = "laborer",
            label = "عامل عام (Laborer)",
            description = "بداية قياسية في عالم ريد ديد مع مؤن ومعدات النجاة الأساسية.",
            money = 15.00,
            items = { { item = "Bread", count = 3 }, { item = "water", count = 3 } },
            coreXP = 50
        }
    }
}
end


-- --------------------------------------------------------------------------
--  Taxes
-- --------------------------------------------------------------------------
do
-- ============================================================================
-- JRS CORE — CENTRALIZED MASTER TAXATION CONFIGURATION
-- ============================================================================
-- All scripts reference this central matrix for sales tax, property tax,
-- business tax, horse/luxury tax, service tax, transfer tax, and tax debt limits.
-- ============================================================================

Config = Config or {}
Config.Taxes = Config.Taxes or {}

-- Master Taxation System Enable Flag
Config.Taxes.Enabled = true

-- Destination of Tax Revenue:
-- 'sink' = 100% removed/destroyed from economy (Anti-Inflation Default)
-- 'treasury' = Deposited into central government account if enabled
Config.Taxes.Destination = "sink"

-- ============================================================================
-- 1. TAX CATEGORIES & RATES
-- ============================================================================
Config.Taxes.Categories = {
    -- Sales Tax: Consumer store & merchant purchases
    Sales = {
        enabled = true,
        rate = 0.03,            -- 3% Sales Tax on store purchases
        minTax = 0.01,          -- Minimum 1 cent tax
        includeInDisplay = true -- Communicate Base, Tax, and Total in UI
    },

    -- Property Tax: Real estate acquisition & weekly ownership tax
    Property = {
        enabled = true,
        purchaseRate = 0.02,    -- 2% tax on property purchase price
        weeklyRate = 0.015,     -- 1.5% weekly property ownership tax
        gracePeriodDays = 7,    -- 7 days grace period before debt accumulates
        maxDebtCap = 500.00,    -- Maximum unpaid tax debt cap before restriction
        lateFeeRate = 0.02,     -- 2% late fee on unpaid tax debt
    },

    -- Business Tax: Commercial business net profit tax
    Business = {
        enabled = true,
        rate = 0.04,            -- 4% tax on NET profit (operating expenses exempt)
        minProfitThreshold = 100.00, -- Minimum profit required before tax triggers
        deductExpenses = true   -- Deduct wages and supply costs before taxing
    },

    -- Horse & Stable Tax: Mount ownership & luxury animals
    Horse = {
        enabled = true,
        purchaseRate = 0.03,    -- 3% base horse sales tax
        luxuryThreshold = 500.00, -- Purchases above $500 trigger luxury rate
        luxuryRate = 0.05,      -- 5% tax on portion exceeding threshold
    },

    -- Service Tax: Paid services (Doctors, Barbers, Customizations, Repairs)
    Service = {
        enabled = true,
        rate = 0.03,            -- 3% Service Tax on paid services
        minTax = 0.05,
    },

    -- Transfer Tax: Large bank wire and player-to-player transfers
    Transfer = {
        enabled = true,
        threshold = 500.00,     -- Transfers above $500 trigger transfer tax
        rate = 0.01,            -- 1% transfer tax on large wire transactions
        maxTax = 50.00,         -- Maximum $50 transfer tax cap
        payor = "sender"        -- "sender" or "recipient" pays tax
    },

    -- Luxury Tax: General high-value luxury purchases
    Luxury = {
        enabled = true,
        threshold = 1000.00,    -- Purchases above $1,000 trigger general luxury tax
        rate = 0.05,            -- 5% tax on amount exceeding threshold
    }
}

-- ============================================================================
-- 2. TAX EXEMPTIONS (100% EXEMPT FROM TAXATION)
-- ============================================================================
Config.Taxes.Exemptions = {
    -- Job labor payouts are 100% tax exempt to protect beginner progression
    TaxJobSalaries = false,

    -- XP gains and level rewards are non-monetary and 100% tax exempt
    TaxXpRewards = false,

    -- Starter cash and starter equipment are 100% tax exempt
    TaxStarterAssets = false,

    -- System refunds and reversal transactions are 100% tax exempt
    TaxRefunds = false,

    -- Exempt jobs (e.g. Police on duty, Doctors on duty, Government officials)
    ExemptJobs = {
        ["police"] = true,
        ["doctor"] = true,
        ["government"] = true
    }
}

-- ============================================================================
-- 3. AUDIT LEDGER & RECEIPT SETTINGS
-- ============================================================================
Config.Taxes.Ledger = {
    LogToDatabase = true,       -- Record all tax receipts in jrs_tax_ledger
    ReceiptPrefix = "TX-",      -- Receipt ID prefix (e.g. TX-000123)
    ConsoleAuditAlert = false,  -- Console log high-value taxes
}
end


-- --------------------------------------------------------------------------
--  Daily challenges
-- --------------------------------------------------------------------------
do
-- JRS / Red Dead Online Daily Challenges Configuration
Config = Config or {}

Config.DailyChallenges = {
    Enabled = true,
    SlotsCount = 7, -- 7 challenges per day, matching RDO

    -- Streak multipliers (consecutive days completed)
    -- RDO: Base (1.0x), 7 days (1.5x), 14 days (2.0x), 21+ days (2.5x)
    Streak = {
        Tiers = {
            { minDays = 21, multiplier = 2.5 },
            { minDays = 14, multiplier = 2.0 },
            { minDays = 7,  multiplier = 1.5 },
            { minDays = 1,  multiplier = 1.0 },
        },
        ResetDays = 28, -- in RDO streaks reset at 28 days
    },

    -- Base rewards per completed challenge
    BaseGold = 0.20,  -- 0.20 gold bars per task
    BaseCash = 15.00, -- $15 cash per task
    BaseXp = 200,     -- 200 account XP

    -- Completion bonus (completing all 7 challenges in a day)
    AllCompletedBonusGold = 0.60, -- bonus so total day reaches up to 2.0 - 2.5 Gold
    AllCompletedBonusCash = 50.00,

    -- Available challenge pool mapped to activities & jobs
    ChallengePool = {
        { id = 'bounty_complete',  job = 'bounty',      target = 2, title = 'Turn in 2 Bounty Targets',           desc = 'Complete 2 bounty hunts alive or dead.' },
        { id = 'hunting_skin',     job = 'hunting',     target = 4, title = 'Skin 4 Wild Animals',               desc = 'Hunt and skin wild animals in the frontier.' },
        { id = 'fishing_catch',    job = 'fishing',     target = 3, title = 'Catch 3 Fish',                     desc = 'Cast a line and catch 3 fish from rivers or lakes.' },
        { id = 'mining_gather',    job = 'mining',      target = 5, title = 'Mine 5 Ore Veins',                  desc = 'Extract ore from any active mining shaft.' },
        { id = 'herbs_pick',       job = 'herbs',       target = 5, title = 'Pick 5 Wild Herbs',                 desc = 'Forage wild plants and herbs across the landscape.' },
        { id = 'moonshine_distill',job = 'moonshine',   target = 1, title = 'Complete a Moonshine Operation',    desc = 'Brew or distribute a batch of moonshine.' },
        { id = 'collector_find',   job = 'auction',     target = 2, title = 'Appraise or Find 2 Collectibles',   desc = 'Locate or trade rare collectibles.' },
        { id = 'lumber_chop',      job = 'lumberjack',  target = 5, title = 'Chop 5 Timber Logs',                desc = 'Fell trees and harvest timber.' },
        { id = 'farm_harvest',     job = 'farming',     target = 5, title = 'Harvest 5 Farm Crops',              desc = 'Tend to fields and gather farmed produce.' },
        { id = 'cargo_deliver',    job = 'delivery',    target = 1, title = 'Deliver a Wagon Shipment',          desc = 'Transport trade goods safely to destination.' },
    }
}
end
