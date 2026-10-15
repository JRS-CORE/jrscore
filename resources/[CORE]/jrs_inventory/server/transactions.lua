-- JRS Inventory transactional helpers, locks and hooks.
-- This module is intentionally server-authoritative. It does not trust NUI or client values.

local Locks = {}
local Hooks = {}
local LOCK_MAX_MS = 30000

local function nowMs()
    return GetGameTimer()
end

local function lockKey(source, key)
    return ('%s:%s'):format(tonumber(source) or 0, tostring(key or 'inventory'))
end

local function cleanupLock(key)
    local row = Locks[key]
    if row and tonumber(row.expiresAt or 0) <= nowMs() then
        Locks[key] = nil
        return nil
    end
    return row
end

local function AcquireInventoryLock(source, key, ttlMs, owner)
    source = tonumber(source)
    if not source or source <= 0 then return false, 'invalid_source' end
    key = lockKey(source, key)
    ttlMs = math.max(250, math.min(tonumber(ttlMs) or 10000, LOCK_MAX_MS))
    owner = tostring(owner or GetInvokingResource() or GetCurrentResourceName())
    local current = cleanupLock(key)
    if current and current.owner ~= owner then
        return false, 'locked'
    end
    Locks[key] = { owner = owner, expiresAt = nowMs() + ttlMs }
    return true
end

local function ReleaseInventoryLock(source, key, owner, force)
    source = tonumber(source)
    if not source then return false end
    key = lockKey(source, key)
    owner = tostring(owner or GetInvokingResource() or GetCurrentResourceName())
    local current = cleanupLock(key)
    if not current then return true end
    if force == true or current.owner == owner then
        Locks[key] = nil
        return true
    end
    return false
end

local function IsInventoryLocked(source, key)
    source = tonumber(source)
    if not source then return false end
    return cleanupLock(lockKey(source, key)) ~= nil
end

local function RegisterInventoryHook(eventName, name, callback)
    eventName = tostring(eventName or '')
    name = tostring(name or GetInvokingResource() or 'anonymous')
    if eventName == '' or type(callback) ~= 'function' then return false end
    Hooks[eventName] = Hooks[eventName] or {}
    Hooks[eventName][name] = callback
    return true
end

local function emitHook(eventName, payload)
    local entries = Hooks[tostring(eventName or '')]
    if type(entries) ~= 'table' then return end
    for name, callback in pairs(entries) do
        local ok, err = pcall(callback, payload)
        if not ok then
            print(('[jrs_inventory] hook %s/%s failed: %s'):format(eventName, name, tostring(err)))
        end
    end
    TriggerEvent('jrs_inventory:server:hook:' .. tostring(eventName), payload)
end
JRSEmitInventoryHook = emitHook

local function snapshotMetadata(source, itemName)
    local api = JRSInventoryInternalAPI
    local inventory = api and api.getUserInventory and api.getUserInventory(source) or nil
    if type(inventory) ~= 'table' then return {} end
    for _, entry in pairs(inventory) do
        if tostring(entry.item or '') == tostring(itemName or '') then
            return type(entry.metaData) == 'table' and entry.metaData or {}
        end
    end
    return {}
end

-- Atomic-at-resource-level operation batch. Database-level trade escrow remains in trade_api.
-- Supported operations:
-- {type='remove', item='water', amount=1}
-- {type='add', item='bread', amount=1, metadata={}}
local function InventoryTransaction(source, operations, context)
    source = tonumber(source)
    if not source or source <= 0 or type(operations) ~= 'table' or #operations == 0 or #operations > 64 then
        return false, 'invalid_transaction', {}
    end

    local owner = tostring((type(context) == 'table' and context.owner) or GetInvokingResource() or 'server')
    local transactionId = tostring((type(context) == 'table' and context.id) or ('tx:%s:%s:%s'):format(source, nowMs(), math.random(1000,9999)))
    local acquired, why = AcquireInventoryLock(source, 'transaction', 30000, owner .. ':' .. transactionId)
    if not acquired then return false, why, {} end

    local executed = {}
    local function finish(ok, reason, data)
        ReleaseInventoryLock(source, 'transaction', owner .. ':' .. transactionId)
        emitHook(ok and 'transactionCommitted' or 'transactionRolledBack', {
            source = source, id = transactionId, owner = owner, reason = reason, operations = operations, result = data
        })
        return ok, reason, data or {}
    end

    -- Prevalidate removals and all numeric values before changing anything.
    local api = JRSInventoryInternalAPI
    if not api then return finish(false, 'inventory_api_unavailable', {}) end
    for i, op in ipairs(operations) do
        if type(op) ~= 'table' then return finish(false, 'invalid_operation', {index=i}) end
        local kind = tostring(op.type or '')
        local item = tostring(op.item or '')
        local amount = tonumber(op.amount or op.count)
        if (kind ~= 'add' and kind ~= 'remove') or item == '' or not amount or amount <= 0 or amount == math.huge or amount ~= math.floor(amount) then
            return finish(false, 'invalid_operation', {index=i})
        end
        if kind == 'remove' and (tonumber(api.getItemCount(source, item)) or 0) < amount then
            return finish(false, 'not_enough', {index=i, item=item, amount=amount})
        end
    end

    for i, op in ipairs(operations) do
        local kind = tostring(op.type)
        local item = tostring(op.item)
        local amount = tonumber(op.amount or op.count)
        local metadata = type(op.metadata) == 'table' and op.metadata or nil
        local ok, reason, details
        if kind == 'remove' then
            metadata = metadata or snapshotMetadata(source, item)
            ok, reason, details = JRSInventorySubItemSync(source, item, amount, owner)
            if ok then
                executed[#executed+1] = {type='remove', item=item, amount=amount, metadata=(type(details) == 'table' and details.metadata) or metadata}
            end
        else
            if api.canCarryItem and api.canCarryItem(source, item, amount) == false then
                ok, reason, details = false, 'cannot_carry', {item=item, amount=amount}
            else
                ok, reason, details = JRSInventoryAddItemSync(source, item, amount, metadata or {}, owner)
                if ok then
                    executed[#executed+1] = {type='add', item=item, amount=amount, metadata=metadata or {}}
                end
            end
        end

        if not ok then
            -- Reverse every successful step. Best effort; failures are reported loudly.
            local rollbackErrors = {}
            for r = #executed, 1, -1 do
                local done = executed[r]
                local rok, rreason
                if done.type == 'remove' then
                    rok, rreason = JRSInventoryAddItemSync(source, done.item, done.amount, done.metadata or {}, owner .. ':rollback')
                else
                    rok, rreason = JRSInventorySubItemSync(source, done.item, done.amount, owner .. ':rollback')
                end
                if not rok then rollbackErrors[#rollbackErrors+1] = {index=r, reason=rreason} end
            end
            return finish(false, reason or 'operation_failed', {index=i, details=details, rollbackErrors=rollbackErrors})
        end
    end

    return finish(true, 'success', {id=transactionId, executed=#executed})
end

local function GetMaxWeight(source)
    local src = tonumber(source)
    if src then
        local state = Player(src).state
        local perks = state and state.jrsPerks
        if perks and tonumber(perks.carryKg) then
            return tonumber(perks.carryKg)
        end
        if GetResourceState('jrs_core') == 'started' then
            local ok, cap = pcall(function() return exports.jrs_core:GetCarryCapacity(src) end)
            if ok and tonumber(cap) then return tonumber(cap) end
        end
    end
    return tonumber(Config and Config.Max_Items) or 50
end

local function GetFreeWeight(source)
    local maxWeight = GetMaxWeight(source)
    local current = tonumber(JRSInventoryInternalAPI and JRSInventoryInternalAPI.getInventoryTotalWeight and JRSInventoryInternalAPI.getInventoryTotalWeight(source)) or 0
    return math.max(0, maxWeight - current), maxWeight, current
end

exports('AcquireInventoryLock', AcquireInventoryLock)
exports('ReleaseInventoryLock', ReleaseInventoryLock)
exports('IsInventoryLocked', IsInventoryLocked)
exports('InventoryTransaction', InventoryTransaction)
exports('RegisterInventoryHook', RegisterInventoryHook)
exports('GetFreeWeight', GetFreeWeight)
exports('GetMaxWeight', GetMaxWeight)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    local prefix = tostring(src) .. ':'
    for key in pairs(Locks) do
        if key:sub(1, #prefix) == prefix then Locks[key] = nil end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    for eventName, entries in pairs(Hooks) do
        entries[resourceName] = nil
        if next(entries) == nil then Hooks[eventName] = nil end
    end
end)

-- Character lifecycle integration: clean inventory-owned rows without making
-- jrs_character know inventory table internals.
CreateThread(function()
    while GetResourceState('jrs_core') ~= 'started' do Wait(250) end
    Wait(250)
    pcall(function()
        exports.jrs_core:RegisterCharacterDeleteHook('jrs_inventory', function(characterId, identifier, phase)
            characterId = tonumber(characterId)
            if not characterId then return false end
            if phase == 'before' then
                -- Weapon rows are the only inventory-owned persistent rows not stored
                -- directly inside characters.inventory. Trade orders are retained as
                -- audit/recovery history and are not deleted.
                return true
            end
            MySQL.update.await('DELETE FROM jrs_weaponloadout WHERE charidentifier = ?', { characterId })
            return true
        end)
    end)
end)
