-- ==========================================================================
--  JRS CORE  |  jrs_trader  |  config.lua
--  traders - NPC traders with stock-based prices, managed in game with /traderadmin
-- ==========================================================================

Config = {}

Config.Language         = 'en'   -- 'en' or 'ar'
Config.MaxBuyAmount     = 10     -- max items per buy
Config.MaxSellAmount    = 10     -- max items per sell
Config.InteractDistance = 5.0    -- server-side max distance from the trader
Config.Cooldown         = 2000   -- ms between two trades per player
Config.UseDistance      = 2.5    -- prompt radius

Config.Sounds = {
    enabled = true,
    success = { name = 'PURCHASE', set = 'Ledger_Sounds' },
    fail    = { name = 'UNAFFORDABLE', set = 'Ledger_Sounds' },
}

---------------------------------
-- npc settings
---------------------------------
Config.DistanceSpawn = 30.0

---------------------------------
-- dynamic price settings
---------------------------------
Config.Pricing = {
    priceMultipliers = {
        lowStock    = 1.2, -- stock <= lowstock
        highStock   = 0.9, -- stock >= highstock
        normalStock = 1.0,
    },
    minPriceFactor = 0.7, -- price never below 70% of base
    maxPriceFactor = 1.5, -- price never above 150% of base
    -- traders pay this fraction of their current selling price when buying from players.
    -- keep (sellFactor * lowStock) below normalStock, otherwise players can loop buy/sell for profit.
    sellFactor = 0.8,
}

---------------------------------
-- trader npcs
-- traders are stored in the `jrs_trader_npcs` table and managed in game
-- through the admin panel: /traderadmin
-- Config.DefaultTraders is only used to seed a brand new table.
---------------------------------
Config.DefaultModel = 'mp_u_m_m_trader_01'
Config.DefaultBlip  = { sprite = 'blip_shop_market_stall', scale = 0.2 }

Config.DefaultTraders = {
    --{ traderid = 'emeraldtrader',     tradername = 'Emerald Ranch Trader', coords = vector4(1440.85, 355.17, 88.55, 102.52) },
}

---------------------------------
-- default items (only inserted when Config.AutoDatabase creates a brand new table)
---------------------------------
Config.DefaultItems = {
    --{ traderid = 'emeraldtrader',     item = 'bread', stock = 0, lowstock = 10, highstock = 100, baseprice = 0.10 },
    --{ traderid = 'emeraldtrader',     item = 'water', stock = 0, lowstock = 10, highstock = 100, baseprice = 0.10 },
}

---------------------------------
-- shared helpers (used by client + server)
---------------------------------
function Config.Round2(n)
    return math.floor(n * 100 + 0.5) / 100
end
local round2 = Config.Round2

--- Price the trader charges a player for one unit at the given stock level.
function Config.GetBuyPrice(stock, lowstock, highstock, basePrice)
    local p = Config.Pricing
    local mult = p.priceMultipliers.normalStock
    if stock <= lowstock then
        mult = p.priceMultipliers.lowStock
    elseif stock >= highstock then
        mult = p.priceMultipliers.highStock
    end
    local price = basePrice * mult
    price = math.max(basePrice * p.minPriceFactor, math.min(basePrice * p.maxPriceFactor, price))
    return round2(price)
end

--- Price the trader pays a player for one unit at the given stock level.
function Config.GetSellPrice(stock, lowstock, highstock, basePrice)
    return round2(Config.GetBuyPrice(stock, lowstock, highstock, basePrice) * Config.Pricing.sellFactor)
end
