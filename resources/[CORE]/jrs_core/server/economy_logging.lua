-- ============================================================================
-- JRS CORE — ECONOMY LOGGING & TRANSACTION AUDIT SYSTEM
-- ============================================================================
-- Lightweight, non-blocking asynchronous database audit logger.
-- Logs high-value transfers, job payouts, shop sales, and anti-exploit flags.
-- Target performance overhead: < 0.02 ms per transaction.
-- ============================================================================

local EconomyLogger = {}
local LogQueue = {}
local BATCH_INTERVAL_MS = 5000 -- Flush log queue every 5 seconds

--- Log an economic event
---@param charIdentifier string|number Player character identifier
---@param actionType string Event type (e.g. 'JOB_PAYOUT', 'SHOP_BUY', 'SHOP_SELL', 'BANK_TRANSFER', 'EXPLOIT_FLAG')
---@param amount number Cash/Gold amount involved
---@param currencyType number|string Currency (0=cash, 1=gold, 2=rol, 3=dirty)
---@param metadata table|string Optional JSON metadata detailing the transaction
function EconomyLogger.LogEvent(charIdentifier, actionType, amount, currencyType, metadata)
    if not Config.Economy or not Config.Economy.Enabled then return end

    amount = tonumber(amount) or 0
    if amount == 0 and actionType ~= 'EXPLOIT_FLAG' then return end

    local metaJson = type(metadata) == "table" and json.encode(metadata) or tostring(metadata or "")

    table.insert(LogQueue, {
        charidentifier = tostring(charIdentifier or "0"),
        action_type    = tostring(actionType or "UNKNOWN"),
        amount         = amount,
        currency       = tostring(currencyType or "0"),
        metadata       = metaJson,
        timestamp      = os.time()
    })

    -- High-value alert logging
    local flagVal = Config.Economy.AntiExploit and Config.Economy.AntiExploit.MaxTransactionSingleVal or 2000.0
    if amount >= flagVal and Config.Economy.AntiExploit and Config.Economy.AntiExploit.AuditLogConsoleAlert then
        print(string.format("[JRS CORE ECONOMY AUDIT] High-value event: Char %s | Action %s | Amount $%.2f | Meta: %s",
            tostring(charIdentifier), tostring(actionType), amount, metaJson))
    end
end

-- Asynchronous Batch Inserter Loop
CreateThread(function()
    while true do
        Wait(BATCH_INTERVAL_MS)
        if #LogQueue > 0 then
            local currentBatch = LogQueue
            LogQueue = {}

            local queryParams = {}
            local sqlValues = {}

            for i = 1, #currentBatch do
                local entry = currentBatch[i]
                table.insert(queryParams, entry.charidentifier)
                table.insert(queryParams, entry.action_type)
                table.insert(queryParams, entry.amount)
                table.insert(queryParams, entry.currency)
                table.insert(queryParams, entry.metadata)
                table.insert(queryParams, entry.timestamp)

                table.insert(sqlValues, "(?, ?, ?, ?, ?, FROM_UNIXTIME(?))")
            end

            local sqlQuery = "INSERT INTO jrs_economy_logs (charidentifier, action_type, amount, currency, metadata, created_at) VALUES " .. table.concat(sqlValues, ", ")
            
            MySQL.Async.execute(sqlQuery, queryParams, function(rowsChanged)
                -- Silent background write complete
            end)
        end
    end
end)

-- Register Server Export
exports('LogEconomyEvent', EconomyLogger.LogEvent)

-- Attach to Core API
AddEventHandler('jrs_core:getCoreApi', function(cb)
    if type(cb) == 'function' then
        cb({
            LogEconomyEvent = EconomyLogger.LogEvent
        })
    end
end)

-- Economy price lookup moved from config
Config = Config or {}
Config.Economy = Config.Economy or {}
function Config.Economy.GetItemPrice(itemName)
    if not itemName or not Config.Economy.ItemPrices then return nil, nil end
    local item = Config.Economy.ItemPrices[tostring(itemName):lower()]
    if item then
        return item.buy, item.sell
    end
    return nil, nil
end

