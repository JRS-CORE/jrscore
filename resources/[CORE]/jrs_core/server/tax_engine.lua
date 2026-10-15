-- ============================================================================
-- JRS CORE — CENTRALIZED SERVER TAXATION ENGINE
-- ============================================================================
-- Server-authoritative tax calculation, execution, debt handling, and receipt logger.
-- All tax revenue is 100% removed/sunk from the player economy to curb inflation.
-- Target performance impact: < 0.03 ms.
-- ============================================================================

local TaxEngine = {}
local ReceiptCounter = 100000

local function normalizeCategory(name)
    name = tostring(name or ''):lower()
    if name == 'sales' or name == 'store' then return 'Sales' end
    if name == 'property' or name == 'housing' then return 'Property' end
    if name == 'business' or name == 'company' then return 'Business' end
    if name == 'horse' or name == 'stable' then return 'Horse' end
    if name == 'service' or name == 'doctor' or name == 'barber' then return 'Service' end
    if name == 'transfer' or name == 'wire' or name == 'bank' then return 'Transfer' end
    if name == 'luxury' then return 'Luxury' end
    return 'Sales'
end

local function generateReceiptId()
    ReceiptCounter = ReceiptCounter + 1
    local prefix = Config.Taxes and Config.Taxes.Ledger and Config.Taxes.Ledger.ReceiptPrefix or "TX-"
    return string.format("%s%06d%02d", prefix, ReceiptCounter % 1000000, math.random(10, 99))
end

--- Calculate tax breakdown for a transaction
---@param categoryName string Tax category ('Sales', 'Property', 'Horse', 'Transfer', 'Business', 'Service', 'Luxury')
---@param baseAmount number Base transaction amount
---@param context table|nil Optional context (e.g. { isLuxury = true, threshold = 500 })
---@return number taxAmount, number totalAmount, table breakdown
function TaxEngine.CalculateTax(categoryName, baseAmount, context)
    baseAmount = math.max(0, tonumber(baseAmount) or 0)
    if not Config.Taxes or not Config.Taxes.Enabled or baseAmount == 0 then
        return 0, baseAmount, { base = baseAmount, tax = 0, total = baseAmount, category = categoryName, rate = 0 }
    end

    local category = normalizeCategory(categoryName)
    local cfg = Config.Taxes.Categories[category]
    if not cfg or not cfg.enabled then
        return 0, baseAmount, { base = baseAmount, tax = 0, total = baseAmount, category = category, rate = 0 }
    end

    local taxAmount = 0
    local rate = cfg.rate or 0

    if category == 'Sales' then
        taxAmount = baseAmount * rate
        if cfg.minTax and taxAmount < cfg.minTax then taxAmount = cfg.minTax end

    elseif category == 'Property' then
        local isPurchase = context and context.isPurchase == true
        rate = isPurchase and (cfg.purchaseRate or 0.02) or (cfg.weeklyRate or 0.015)
        taxAmount = baseAmount * rate

    elseif category == 'Horse' then
        local threshold = cfg.luxuryThreshold or 500.00
        local baseTax = baseAmount * (cfg.purchaseRate or 0.03)
        local luxuryTax = 0
        if baseAmount > threshold then
            luxuryTax = (baseAmount - threshold) * (cfg.luxuryRate or 0.05)
        end
        taxAmount = baseTax + luxuryTax
        rate = baseAmount > 0 and (taxAmount / baseAmount) or 0

    elseif category == 'Transfer' then
        local threshold = cfg.threshold or 500.00
        if baseAmount >= threshold then
            taxAmount = baseAmount * rate
            if cfg.maxTax and taxAmount > cfg.maxTax then taxAmount = cfg.maxTax end
        else
            taxAmount = 0
            rate = 0
        end

    elseif category == 'Luxury' then
        local threshold = cfg.threshold or 1000.00
        if baseAmount > threshold then
            taxAmount = (baseAmount - threshold) * rate
        end

    else
        taxAmount = baseAmount * rate
        if cfg.minTax and taxAmount < cfg.minTax then taxAmount = cfg.minTax end
    end

    local src = context and (context.playerSource or context.source)
    local taxSavings = 0
    if src and taxAmount > 0 and JRSPerks and JRSPerks.ApplyTaxReduction then
        local reducedTax, saved = JRSPerks.ApplyTaxReduction(src, taxAmount)
        taxAmount = reducedTax
        taxSavings = saved or 0
    end

    taxAmount = math.floor(taxAmount * 100 + 0.5) / 100
    local totalAmount = math.floor((baseAmount + taxAmount) * 100 + 0.5) / 100

    return taxAmount, totalAmount, {
        base = baseAmount,
        tax = taxAmount,
        total = totalAmount,
        category = category,
        rate = rate,
        saved = taxSavings
    }
end

--- Apply tax to a transaction and log receipt
---@param playerSource number Player source ID
---@param categoryName string Tax category
---@param baseAmount number Base transaction amount
---@param context table|nil Additional transaction context
---@return boolean success, string receiptId, number totalPaid, table breakdown
function TaxEngine.ApplyTax(playerSource, categoryName, baseAmount, context)
    playerSource = tonumber(playerSource)
    baseAmount = math.max(0, tonumber(baseAmount) or 0)
    if not playerSource or baseAmount <= 0 then return false, nil, 0, nil end

    context = type(context) == 'table' and context or {}
    context.playerSource = playerSource

    local taxAmount, totalAmount, breakdown = TaxEngine.CalculateTax(categoryName, baseAmount, context)
    local receiptId = generateReceiptId()

    -- Deduct total amount (Base + Tax) from player
    local char = jrsCore.getUser(playerSource) and jrsCore.getUser(playerSource).getUsedCharacter
    if not char or (char.money or 0) < totalAmount then
        return false, nil, totalAmount, breakdown
    end

    -- Server-authoritative Money Removal
    char.removeCurrency(playerSource, 0, totalAmount)

    -- Log Tax Receipt to Database Ledger
    local charId = tostring(char.charIdentifier or "0")
    local resourceName = context and context.resource or GetInvokingResource() or "jrs_core"

    if Config.Taxes.Ledger.LogToDatabase then
        exports.oxmysql:execute([[
            INSERT INTO jrs_tax_ledger (receipt_id, charidentifier, category, base_amount, tax_amount, total_amount, resource_name, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
        ]], { receiptId, charId, breakdown.category, baseAmount, taxAmount, totalAmount, resourceName })
    end

    -- Log to Central Economy Audit Logger
    if exports.jrs_core and type(exports.jrs_core.LogEconomyEvent) == 'function' then
        exports.jrs_core:LogEconomyEvent(charId, "TAX_" .. breakdown.category:upper(), taxAmount, "0", {
            receipt_id = receiptId,
            base_amount = baseAmount,
            total_amount = totalAmount,
            resource = resourceName
        })
    end

    return true, receiptId, totalAmount, breakdown
end

--- Check and retrieve player tax debt
---@param charIdentifier string|number Character identifier
function TaxEngine.GetTaxDebt(charIdentifier)
    local pending = promise.new()
    exports.oxmysql:fetch("SELECT unpaid_tax FROM jrs_tax_debts WHERE charidentifier = ? LIMIT 1", { tostring(charIdentifier) }, function(result)
        local debt = result and result[1] and tonumber(result[1].unpaid_tax) or 0
        pending:resolve(debt)
    end)
    return Citizen.Await(pending)
end

-- Export API functions
exports('CalculateTax', TaxEngine.CalculateTax)
exports('ApplyTax', TaxEngine.ApplyTax)
exports('GetTaxDebt', TaxEngine.GetTaxDebt)

-- Attach to Core API
AddEventHandler('jrs_core:getCoreApi', function(cb)
    if type(cb) == 'function' then
        cb({
            CalculateTax = TaxEngine.CalculateTax,
            ApplyTax = TaxEngine.ApplyTax,
            GetTaxDebt = TaxEngine.GetTaxDebt
        })
    end
end)

-- Tax category checker moved from config
Config = Config or {}
Config.Taxes = Config.Taxes or {}
function Config.Taxes.IsCategoryEnabled(categoryName)
    if not Config.Taxes.Categories then return false end
    local cat = Config.Taxes.Categories[tostring(categoryName or ''):gsub("^%l", string.upper)] or Config.Taxes.Categories[tostring(categoryName)]
    return cat and cat.enabled == true
end

