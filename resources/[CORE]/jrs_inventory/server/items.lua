-- ===========================================================================
-- Item Operations (secure add / subtract / player transfer)
-- ===========================================================================

local function notifyInventory(playerId, message, duration)
    playerId = tonumber(playerId)
    if playerId and playerId > 0 then
        TriggerClientEvent("jrsCore:notify", playerId, _Up(playerId, 'inventory'), tostring(message), 'bag', duration or 2500)
    end
end

local function finishInventoryOperation(callback, success, reason, data)
    if callback == nil then return end
    local ok, err = pcall(callback, success == true, reason, type(data) == "table" and data or {})
    if not ok and Config.Debug then
        print("[jrs_inventory] item operation callback error: " .. tostring(err))
    end
end

local function shouldNotifyTrustedOperation(sourceResource)
    return tostring(sourceResource or "") ~= "jrs_admin"
end

local function notifyItemFailure(playerId, reason, itemName, sourceResource)
    if not shouldNotifyTrustedOperation(sourceResource) then return end
    if reason == "full" then
        notifyInventory(playerId, _Up(playerId, 'no_slots_alt'))
    elseif reason == "invalid_item" then
        notifyInventory(playerId, _Up(playerId, 'invalid_item', tostring(itemName or '')))
    elseif reason == "invalid_count" or reason == "not_enough" then
        notifyInventory(playerId, _Up(playerId, 'wrong_amount'))
    elseif reason == "not_found" then
        notifyInventory(playerId, _Up(playerId, 'dont_own_item'))
    elseif reason == "owned_limit" then
        local label = ItemLabelFor(playerId, itemName)
        notifyInventory(playerId, _Up(playerId, 'owned_limit', label))
    end
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return copy
end

local function metadataEqual(first, second, seen)
    if first == second then return true end
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return false end

    seen = seen or {}
    if seen[first] == second then return true end
    seen[first] = second

    for key, value in pairs(first) do
        if not metadataEqual(value, second[key], seen) then return false end
    end
    for key in pairs(second) do
        if first[key] == nil then return false end
    end
    return true
end

local function normalizeMetadata(metadata, itemName)
    if type(JRSInventoryNormalizeMetadata) == "function" then
        return JRSInventoryNormalizeMetadata(metadata, itemName, true)
    end
    if metadata == nil then return {} end
    return deepCopy(metadata)
end

local function createUniqueItemId()
    if type(JRSInventoryCreateUniqueItemId) == "function" then
        return JRSInventoryCreateUniqueItemId()
    end
    local candidate
    local exists
    repeat
        candidate = math.random(1, 99999999999999)
        exists = false
        for _, inventory in pairs(inv_table or {}) do
            for _, item in pairs(inventory or {}) do
                if tonumber(item.itemId) == tonumber(candidate) then
                    exists = true
                    break
                end
            end
            if exists then break end
        end
    until not exists
    return candidate
end

local function findMatchingStack(playerId, itemName, metadata)
    for index, item in pairs(inv_table[tonumber(playerId)] or {}) do
        if item.item == itemName and metadataEqual(item.metaData or {}, metadata or {}) then
            return index
        end
    end
    return nil
end

-- Shared by trusted server exports, player transfer, and secure ground pickup.
-- Returns: success, reason, operation data (operation data supports rollback).
function AddInventoryItemDirect(playerId, itemName, count, metadata, preferredSlot)
    playerId = tonumber(playerId)
    count = tonumber(count)
    itemName = tostring(itemName or "")

    if not playerId or not isValidCount(count) then return false, "invalid_count" end
    local itemDef = ResolveItemDef(itemName)
    if itemName == "" or not itemDef then return false, "invalid_item" end

    local User = jrsCore and jrsCore.getUser and jrsCore.getUser(playerId)
    local Character = User and User.getUsedCharacter
    if not Character then return false, "player_not_found" end
    if type(IsInventoryLoadedForPlayer) ~= "function" or not IsInventoryLoadedForPlayer(playerId, Character) then
        return false, "inventory_not_loaded"
    end

    inv_table[playerId] = inv_table[playerId] or {}
    if not CanCarry(playerId, itemName, count) then
        return false, "full"
    end

    local ownershipLimit = type(Config.MaxOwnedItems) == "table" and tonumber(Config.MaxOwnedItems[itemName]) or nil
    if ownershipLimit then
        local owned = 0
        for _, entry in pairs(inv_table[playerId]) do
            if entry.item == itemName then
                owned = owned + (tonumber(entry.count) or 0)
            end
        end
        if owned + count > ownershipLimit then
            return false, "owned_limit"
        end
    end

    local cleanMetadata = normalizeMetadata(metadata, itemName)
    local requiresUnique = type(JRSInventoryMetadataRequiresUniqueInstance) == "function"
        and JRSInventoryMetadataRequiresUniqueInstance(itemName, cleanMetadata)

    if not requiresUnique then
        local stackIndex = findMatchingStack(playerId, itemName, cleanMetadata)
        if stackIndex then
            local previousCount = tonumber(inv_table[playerId][stackIndex].count) or 0
            inv_table[playerId][stackIndex].count = math.floor(previousCount + count)
            return true, nil, {
                created = false,
                itemId = inv_table[playerId][stackIndex].itemId,
                previousCount = previousCount
            }
        end
    end

    local function canUsePreferredSlot(slotValue)
        local slot = tonumber(slotValue)
        if not slot or slot ~= math.floor(slot) or slot < 1 or slot > 500 then return nil end
        for _, entry in pairs(inv_table[playerId] or {}) do
            if tonumber(entry.slot) == slot then return nil end
        end
        for _, weapon in pairs(weapon_table[playerId] or {}) do
            if tonumber(weapon.slot) == slot then return nil end
        end
        return slot
    end

    local requestedSlot = canUsePreferredSlot(preferredSlot)
    local createdEntries = {}
    local createCount = requiresUnique and math.floor(count) or 1
    for index = 1, createCount do
        local itemId = createUniqueItemId()
        local selectedSlot = (index == 1 and requestedSlot) or GetFreeSlot(playerId)
        local entry = {
            itemId = itemId,
            item = itemName,
            label = itemDef.label or itemName,
            count = requiresUnique and 1 or math.floor(count),
            metaData = deepCopy(cleanMetadata),
            slot = selectedSlot
        }
        table.insert(inv_table[playerId], entry)
        createdEntries[#createdEntries + 1] = itemId
    end

    return true, nil, {
        created = true,
        itemId = createdEntries[1],
        createdItemIds = createdEntries
    }
end

function UndoInventoryItemAdd(playerId, operation)
    playerId = tonumber(playerId)
    if not playerId or type(operation) ~= "table" or not inv_table[playerId] then return end

    if operation.created and type(operation.createdItemIds) == "table" then
        local removeLookup = {}
        for _, createdId in ipairs(operation.createdItemIds) do
            removeLookup[tonumber(createdId)] = true
        end
        for index = #inv_table[playerId], 1, -1 do
            if removeLookup[tonumber(inv_table[playerId][index].itemId)] then
                table.remove(inv_table[playerId], index)
            end
        end
        return
    end

    for index, item in pairs(inv_table[playerId]) do
        if tonumber(item.itemId) == tonumber(operation.itemId) then
            if operation.created then
                table.remove(inv_table[playerId], index)
            else
                item.count = tonumber(operation.previousCount) or item.count
            end
            return
        end
    end
end

-- Removes an exact inventory entry by itemId. This prevents metadata variants
-- of the same item name from being mixed up during transfer/drop operations.
function RemoveInventoryItemByIdDirect(playerId, itemId, count)
    playerId = tonumber(playerId)
    itemId = tonumber(itemId)
    count = tonumber(count)
    if not playerId or not itemId or not isValidCount(count) then
        return false, "invalid_count"
    end

    local inventory = inv_table[playerId] or {}
    for index, item in pairs(inventory) do
        if tonumber(item.itemId) == itemId then
            local currentCount = tonumber(item.count) or 0
            if currentCount < count then return false, "not_enough" end

            local operation = {
                index = index,
                itemId = itemId,
                previousCount = currentCount,
                removedEntry = nil
            }

            local remaining = currentCount - count
            if remaining <= 0 then
                operation.removedEntry = deepCopy(item)
                table.remove(inventory, index)
            else
                item.count = math.floor(remaining)
            end
            return true, nil, operation
        end
    end

    return false, "not_found"
end

function UndoInventoryItemRemoval(playerId, operation)
    playerId = tonumber(playerId)
    if not playerId or type(operation) ~= "table" then return end
    inv_table[playerId] = inv_table[playerId] or {}

    if operation.removedEntry then
        local insertIndex = tonumber(operation.index) or (#inv_table[playerId] + 1)
        if insertIndex < 1 or insertIndex > (#inv_table[playerId] + 1) then
            insertIndex = #inv_table[playerId] + 1
        end
        table.insert(inv_table[playerId], insertIndex, deepCopy(operation.removedEntry))
        return
    end

    for _, item in pairs(inv_table[playerId]) do
        if tonumber(item.itemId) == tonumber(operation.itemId) then
            item.count = tonumber(operation.previousCount) or item.count
            return
        end
    end
end

-- Trusted server-side item creation. It is intentionally not registered as a
-- network event, so clients cannot create arbitrary items for themselves.
AddEventHandler('jrsCore:addItem', function(target, name, count, metadata, callback, sourceResource)
    target = tonumber(target)
    local invokingResource = tostring(sourceResource or GetInvokingResource() or "server")
    local success, reason, addOperation = AddInventoryItemDirect(target, tostring(name or ""), tonumber(count), metadata)
    if not success then
        notifyItemFailure(target, reason, name, invokingResource)
        finishInventoryOperation(callback, false, reason, { item = tostring(name or ""), amount = tonumber(count) or 0 })
        return false
    end

    SaveInventoryNow(target)
    updateItemsInventory(target)
    local itemName = tostring(name or "")
    local itemLabel = ItemLabelFor(target, itemName)
    JRSInventoryLogAction("Items", "Item Added", target, {
        item = itemLabel .. " (`" .. itemName .. "`)",
        itemId = addOperation and addOperation.itemId or "N/A",
        amount = tonumber(count),
        metadata = metadata or {},
        sourceResource = invokingResource,
    })
    if shouldNotifyTrustedOperation(invokingResource) then
        notifyInventory(target, _Up(target, 'item_added', tonumber(count), itemLabel), 3500)
    end
    finishInventoryOperation(callback, true, "success", {
        item = itemName,
        label = itemLabel,
        amount = tonumber(count),
        itemId = addOperation and addOperation.itemId or nil,
    })
    return true
end)

-- Secure stack splitting. A split always creates a separate itemId and slot,
-- even when the metadata matches another stack.
RegisterNetEvent('jrs_inventory:splitStack')
AddEventHandler('jrs_inventory:splitStack', function(itemId, splitCount, operationId)
    local src = tonumber(source)
    itemId = tonumber(itemId)
    splitCount = tonumber(splitCount)

    if not src or not itemId or not isValidCount(splitCount) then
        return
    end
    if not ClaimInventoryOperation(src, operationId, ("split_stack:%s:%s"):format(tostring(itemId), tostring(splitCount))) then
        notifyInventory(src, _Up(src, 'transfer_busy'))
        return
    end

    if isOnCooldown(src) then
        notifyInventory(src, _Up(src, 'too_fast'))
        return
    end

    if not TryLockInventoryPlayer(src) then
        notifyInventory(src, _Up(src, 'transfer_busy'))
        return
    end

    local function finish()
        UnlockInventoryPlayer(src)
    end

    local inventory = inv_table[src] or {}
    local sourceItem = nil

    for _, item in pairs(inventory) do
        if tonumber(item.itemId) == itemId then
            sourceItem = item
            break
        end
    end

    if not sourceItem then
        finish()
        notifyInventory(src, _Up(src, 'dont_own_item'))
        return
    end

    local currentCount = tonumber(sourceItem.count) or 0
    if splitCount >= currentCount then
        finish()
        notifyInventory(src, _Up(src, 'wrong_amount'))
        return
    end

    sourceItem.count = math.floor(currentCount - splitCount)

    table.insert(inventory, {
        itemId = createUniqueItemId(),
        item = sourceItem.item,
        label = sourceItem.label,
        count = math.floor(splitCount),
        metaData = deepCopy(sourceItem.metaData or {}),
        slot = GetFreeSlot(src)
    })

    SaveInventoryNow(src)
    updateItemsInventory(src)
    notifyInventory(src, _Up(src, 'stack_split_success'))
    JRSInventoryLogAction("Items", "Item Stack Split", src, {
        item = tostring(sourceItem.label or sourceItem.item),
        itemId = itemId,
        amount = splitCount,
        operationId = operationId or "legacy",
        metadata = sourceItem.metaData or {},
    })
    finish()
end)

-- Secure stack merging. The dragged/source stack is consumed and its
-- full amount is added to the target stack. Only identical item names and
-- identical metadata may be merged.
local function isHotbarWeaponEntry(entry)
    if type(entry) ~= "table" then return false end
    return entry.weapon == true
        or tonumber(entry.weapon) == 1
        or tostring(entry.weapon) == "true"
end

local function remapMergedItemInHotbar(playerId, removedItemId, targetItemId, itemName)
    playerId = tonumber(playerId)
    removedItemId = tonumber(removedItemId)
    targetItemId = tonumber(targetItemId)
    if not playerId or not removedItemId or not targetItemId then return end

    local hotbar = hotbarByPlayer and hotbarByPlayer[playerId]
    if type(hotbar) ~= "table" then return end

    local changed = false
    local seenTarget = false

    for slotNumber = 1, 5 do
        local slotKey = "slot" .. tostring(slotNumber)
        local entry = hotbar[slotKey]

        if type(entry) == "table" and not isHotbarWeaponEntry(entry) then
            local entryId = tonumber(entry.id)

            if entryId == removedItemId then
                entry.id = targetItemId
                entry.item = itemName
                entry.weapon = false
                entryId = targetItemId
                changed = true
            end

            if entryId == targetItemId then
                if seenTarget then
                    hotbar[slotKey] = {}
                    changed = true
                else
                    seenTarget = true
                end
            end
        end
    end

    if not changed then return end

    local User = jrsCore and jrsCore.getUser and jrsCore.getUser(playerId)
    local Character = User and User.getUsedCharacter
    if not Character then return end

    exports[Config.MysqlResource]:execute(
        "UPDATE jrs_characters SET hotbar=@hotbar WHERE identifier=@identifier AND charidentifier=@charid",
        {
            ["@hotbar"] = json.encode(hotbar),
            ["@identifier"] = Character.identifier,
            ["@charid"] = Character.charIdentifier
        }
    )
end

RegisterNetEvent('jrs_inventory:mergeStacks')
AddEventHandler('jrs_inventory:mergeStacks', function(sourceItemId, targetItemId, operationId)
    local src = tonumber(source)
    sourceItemId = tonumber(sourceItemId)
    targetItemId = tonumber(targetItemId)

    if not src or not sourceItemId or not targetItemId or sourceItemId == targetItemId then
        return
    end
    if not ClaimInventoryOperation(src, operationId, ("merge_stack:%s:%s"):format(tostring(sourceItemId), tostring(targetItemId))) then
        notifyInventory(src, _Up(src, 'transfer_busy'))
        return
    end

    if isOnCooldown(src) then
        notifyInventory(src, _Up(src, 'too_fast'))
        return
    end

    if not TryLockInventoryPlayer(src) then
        notifyInventory(src, _Up(src, 'transfer_busy'))
        return
    end

    local function finish()
        UnlockInventoryPlayer(src)
    end

    local inventory = inv_table[src] or {}
    local sourceIndex, targetIndex
    local sourceItem, targetItem

    for index, item in ipairs(inventory) do
        local currentId = tonumber(item.itemId)
        if currentId == sourceItemId then
            sourceIndex = index
            sourceItem = item
        elseif currentId == targetItemId then
            targetIndex = index
            targetItem = item
        end
    end

    if not sourceItem or not targetItem or not sourceIndex or not targetIndex then
        finish()
        notifyInventory(src, _Up(src, 'dont_own_item'))
        return
    end

    if tostring(sourceItem.item) ~= tostring(targetItem.item)
        or not metadataEqual(sourceItem.metaData or {}, targetItem.metaData or {}) then
        finish()
        notifyInventory(src, _Up(src, 'stack_merge_mismatch'))
        return
    end

    local sourceCount = tonumber(sourceItem.count) or 0
    local targetCount = tonumber(targetItem.count) or 0
    if sourceCount <= 0 or targetCount <= 0 then
        finish()
        notifyInventory(src, _Up(src, 'wrong_amount'))
        return
    end

    targetItem.count = math.floor(targetCount + sourceCount)
    table.remove(inventory, sourceIndex)

    remapMergedItemInHotbar(src, sourceItemId, targetItemId, targetItem.item)
    SaveInventoryNow(src)
    updateItemsInventory(src)
    notifyInventory(src, _Up(src, 'stack_merge_success'))
    JRSInventoryLogAction("Items", "Item Stacks Merged", src, {
        item = tostring(targetItem.label or targetItem.item),
        sourceItemId = sourceItemId,
        targetItemId = targetItemId,
        amount = sourceCount,
        operationId = operationId or "legacy",
        metadata = targetItem.metaData or {},
    })
    finish()
end)

-- Secure, metadata-aware and server-distance-verified player item transfer.
RegisterNetEvent('jrs_inventory:transferItem')
AddEventHandler('jrs_inventory:transferItem', function(target, giverItemId, count, operationId)
    local giver = tonumber(source)
    target = tonumber(target)
    giverItemId = tonumber(giverItemId)
    count = tonumber(count)

    local function fail(reason, message)
        if message then notifyInventory(giver, message) end
        TriggerClientEvent('jrs_inventory:itemTransferResult', giver, false, reason or "failed")
    end

    if not giver or not target or target == giver or not giverItemId or not isValidCount(count) then
        fail("invalid_request", _Up(giver, 'invalid_target'))
        return
    end
    if not ClaimInventoryOperation(giver, operationId, ("give_item:%s:%s:%s"):format(tostring(target), tostring(giverItemId), tostring(count))) then
        fail("replayed", _Up(giver, 'transfer_busy'))
        return
    end
    if isOnCooldown(giver) then
        fail("cooldown", _Up(giver, 'too_fast'))
        return
    end
    if not isValidTarget(target) then
        fail("invalid_target", _Up(giver, 'invalid_target'))
        return
    end
    if not ArePlayersWithinTransferDistance(giver, target) then
        fail("too_far", _Up(giver, 'target_too_far'))
        return
    end
    if not TryLockInventoryPlayers(giver, target) then
        fail("busy", _Up(giver, 'transfer_busy'))
        return
    end

    local function finish()
        UnlockInventoryPlayers(giver, target)
    end

    local giverUser = jrsCore and jrsCore.getUser and jrsCore.getUser(giver)
    local targetUser = jrsCore and jrsCore.getUser and jrsCore.getUser(target)
    local giverCharacter = giverUser and giverUser.getUsedCharacter
    local targetCharacter = targetUser and targetUser.getUsedCharacter
    if not giverCharacter or not targetCharacter then
        finish()
        fail("player_not_loaded", _Up(giver, 'invalid_target'))
        return
    end
    if not ArePlayersWithinTransferDistance(giver, target) then
        finish()
        fail("too_far", _Up(giver, 'target_too_far'))
        return
    end

    local giverItem
    for _, item in pairs(inv_table[giver] or {}) do
        if tonumber(item.itemId) == giverItemId then
            giverItem = item
            break
        end
    end

    if not giverItem or (tonumber(giverItem.count) or 0) < count then
        finish()
        fail("not_owned", _Up(giver, 'dont_own_item'))
        return
    end
    if Config.IsPersonalItem(giverItem.item) then
        finish()
        fail("personal_item", _Up(giver, 'personal_item_locked'))
        return
    end
    if Config.IsNoTransferItem(giverItem.item) then
        finish()
        fail("resource_item", _Up(giver, 'resource_item_locked'))
        return
    end

    local itemName = giverItem.item
    local itemMetadata = deepCopy(giverItem.metaData or {})
    local label = ItemLabelFor(giver, itemName)

    -- Capacity is checked before anything is removed from the giver.
    local added, addReason, addOperation = AddInventoryItemDirect(target, itemName, count, itemMetadata)
    if not added then
        finish()
        if addReason == "full" then
            fail(addReason, _Up(giver, 'target_cant_hold_much'))
        else
            fail(addReason, _Up(giver, 'transfer_failed'))
        end
        return
    end

    local removed, removeReason, removeOperation = RemoveInventoryItemByIdDirect(giver, giverItemId, count)
    if not removed then
        UndoInventoryItemAdd(target, addOperation)
        finish()
        fail(removeReason, _Up(giver, 'transfer_failed'))
        return
    end

    -- Persist both inventories in one database transaction. A lag-switch,
    -- disconnect, or duplicate packet cannot commit only one side.
    RunInventoryTransaction({
        {
            query = 'UPDATE jrs_characters SET inventory=? WHERE identifier=? AND charidentifier=?',
            values = { json.encode(inv_table[giver] or {}), giverCharacter.identifier, giverCharacter.charIdentifier }
        },
        {
            query = 'UPDATE jrs_characters SET inventory=? WHERE identifier=? AND charidentifier=?',
            values = { json.encode(inv_table[target] or {}), targetCharacter.identifier, targetCharacter.charIdentifier }
        }
    }, function(success)
        if success ~= true then
            UndoInventoryItemRemoval(giver, removeOperation)
            UndoInventoryItemAdd(target, addOperation)
            updateItemsInventory(giver)
            updateItemsInventory(target)
            finish()
            fail("database_failed", _Up(giver, 'transfer_failed'))
            return
        end

        updateItemsInventory(giver)
        updateItemsInventory(target)
        notifyInventory(giver, _Up(giver, 'gave_item', count, label), 3000)
        notifyInventory(target, _Up(target, 'received_item', count, label), 3000)
        TriggerClientEvent('jrs_inventory:itemTransferResult', giver, true, "ok")
        JRSInventoryLogAction("Items", "Item Given To Player", giver, {
            target = target,
            item = label .. " (`" .. tostring(itemName) .. "`)",
            itemId = giverItemId,
            amount = count,
            operationId = operationId or "legacy",
            metadata = itemMetadata,
        })
        finish()
    end)
end)

-- Trusted server-local subtraction APIs. These are intentionally not network
-- events; clients must use validated inventory actions instead.
AddEventHandler('jrsCore:subItem', function(target, name, count, callback, sourceResource)
    target = tonumber(target)
    count = tonumber(count)
    name = tostring(name or "")
    local invokingResource = tostring(sourceResource or GetInvokingResource() or "server")
    if not target or not isValidCount(count) then
        notifyItemFailure(target, "invalid_count", name, invokingResource)
        finishInventoryOperation(callback, false, "invalid_count", { item = name, amount = count or 0 })
        return false
    end

    local User = jrsCore and jrsCore.getUser and jrsCore.getUser(target)
    if not User or not User.getUsedCharacter then
        finishInventoryOperation(callback, false, "player_not_found", { item = name, amount = count })
        return false
    end

    local matchingStacks = {}
    local totalAvailable = 0
    for _, item in pairs(inv_table[target] or {}) do
        local isMatch = (item.item == name) or (type(item.item) == "string" and type(name) == "string" and item.item:lower() == name:lower())
        if isMatch and (tonumber(item.count) or 0) > 0 and item.itemId then
            local current = tonumber(item.count) or 0
            totalAvailable = totalAvailable + current
            matchingStacks[#matchingStacks + 1] = {
                itemId = item.itemId,
                count = current,
                metaData = type(item.metaData) == "table" and deepCopy(item.metaData) or {}
            }
        end
    end

    if totalAvailable < count then
        local reason = totalAvailable > 0 and "not_enough" or "not_found"
        notifyItemFailure(target, reason, name, invokingResource)
        finishInventoryOperation(callback, false, reason, { item = name, amount = count, available = totalAvailable })
        return false
    end

    table.sort(matchingStacks, function(a, b) return a.itemId < b.itemId end)
    local remaining = count
    local removedOperations = {}
    for _, stack in ipairs(matchingStacks) do
        if remaining <= 0 then break end
        local take = math.min(remaining, stack.count)
        local removed, removeReason, removeOp = RemoveInventoryItemByIdDirect(target, stack.itemId, take)
        if not removed then
            for index = #removedOperations, 1, -1 do
                UndoInventoryItemRemoval(target, removedOperations[index])
            end
            finishInventoryOperation(callback, false, removeReason or "remove_failed", { item = name, amount = count, itemId = stack.itemId })
            return false
        end
        removedOperations[#removedOperations + 1] = removeOp
        remaining = remaining - take
    end

    SaveInventoryNow(target)
    updateItemsInventory(target)
    local label = ItemLabelFor(target, name)
    JRSInventoryLogAction("Items", "Item Removed", target, {
        item = label .. " (`" .. name .. "`)",
        amount = count,
        sourceResource = invokingResource,
    })
    if shouldNotifyTrustedOperation(invokingResource) then
        notifyInventory(target, _Up(target, 'item_removed', count, label), 3500)
    end
    finishInventoryOperation(callback, true, "success", {
        item = name,
        label = label,
        amount = count,
    })
    return true
end)



-- ===========================================================================
-- Direct trusted item API for server exports
-- ===========================================================================
-- These helpers intentionally bypass the event/callback bridge. External JRS
-- resources call them through server exports so the real result of the inventory
-- mutation is returned, and multi-stack subtraction is natively supported.

function JRSInventorySubItemSync(target, name, count, sourceResource)
    target = tonumber(target)
    count = tonumber(count)
    name = tostring(name or "")
    local invokingResource = tostring(sourceResource or GetInvokingResource() or "server")
    if not target or not isValidCount(count) then
        notifyItemFailure(target, "invalid_count", name, invokingResource)
        return false, "invalid_count", { item = name, amount = count or 0 }
    end

    local User = jrsCore and jrsCore.getUser and jrsCore.getUser(target)
    if not User or not User.getUsedCharacter then
        return false, "player_not_found", { item = name, amount = count }
    end

    local matchingStacks = {}
    local totalAvailable = 0
    for _, item in pairs(inv_table[target] or {}) do
        local isMatch = (item.item == name) or (type(item.item) == "string" and type(name) == "string" and item.item:lower() == name:lower())
        if isMatch and (tonumber(item.count) or 0) > 0 and item.itemId then
            local current = tonumber(item.count) or 0
            totalAvailable = totalAvailable + current
            matchingStacks[#matchingStacks + 1] = {
                itemId = item.itemId,
                count = current,
                metaData = type(item.metaData) == "table" and deepCopy(item.metaData) or {}
            }
        end
    end

    if totalAvailable < count then
        local reason = totalAvailable > 0 and "not_enough" or "not_found"
        notifyItemFailure(target, reason, name, invokingResource)
        return false, reason, { item = name, amount = count, available = totalAvailable }
    end

    table.sort(matchingStacks, function(a, b) return a.itemId < b.itemId end)
    local remaining = count
    local removedOperations = {}
    local lastMetadata = {}
    for _, stack in ipairs(matchingStacks) do
        if remaining <= 0 then break end
        local take = math.min(remaining, stack.count)
        local removed, removeReason, removeOp = RemoveInventoryItemByIdDirect(target, stack.itemId, take)
        if not removed then
            for index = #removedOperations, 1, -1 do
                UndoInventoryItemRemoval(target, removedOperations[index])
            end
            return false, removeReason or "remove_failed", { item = name, amount = count, itemId = stack.itemId }
        end
        removedOperations[#removedOperations + 1] = removeOp
        lastMetadata = stack.metaData
        remaining = remaining - take
    end

    SaveInventoryNow(target)
    updateItemsInventory(target)
    local label = ItemLabelFor(target, name)
    JRSInventoryLogAction("Items", "Item Removed", target, {
        item = label .. " (`" .. name .. "`)",
        amount = count,
        metadata = lastMetadata,
        sourceResource = invokingResource,
    })
    if shouldNotifyTrustedOperation(invokingResource) then
        notifyInventory(target, _Up(target, 'item_removed', count, label), 3500)
    end
    if type(JRSEmitInventoryHook) == "function" then
        JRSEmitInventoryHook("itemRemoved", { source = target, item = name, amount = count, metadata = lastMetadata, sourceResource = invokingResource })
    end
    return true, "success", {
        item = name,
        label = label,
        amount = count,
        metadata = lastMetadata,
    }
end

function JRSInventoryAddItemSync(target, name, count, metadata, sourceResource)
    target = tonumber(target)
    name = tostring(name or "")
    count = tonumber(count)
    local invokingResource = tostring(sourceResource or GetInvokingResource() or "server")
    local success, reason, addOperation = AddInventoryItemDirect(target, name, count, metadata)
    if not success then
        notifyItemFailure(target, reason, name, invokingResource)
        return false, reason, { item = name, amount = count or 0 }
    end

    SaveInventoryNow(target)
    updateItemsInventory(target)
    local itemLabel = ItemLabelFor(target, name)
    JRSInventoryLogAction("Items", "Item Added", target, {
        item = itemLabel .. " (`" .. name .. "`)",
        itemId = addOperation and addOperation.itemId or "N/A",
        amount = count,
        metadata = metadata or {},
        sourceResource = invokingResource,
    })
    if shouldNotifyTrustedOperation(invokingResource) then
        notifyInventory(target, _Up(target, 'item_added', count, itemLabel), 3500)
    end
    if type(JRSEmitInventoryHook) == "function" then
        JRSEmitInventoryHook("itemAdded", { source = target, item = name, amount = count, itemId = addOperation and addOperation.itemId or nil, metadata = metadata or {}, sourceResource = invokingResource })
    end
    return true, "success", {
        item = name,
        label = itemLabel,
        amount = count,
        itemId = addOperation and addOperation.itemId or nil,
    }
end

exports('subItemSync', JRSInventorySubItemSync)
exports('addItemSync', JRSInventoryAddItemSync)
AddEventHandler('jrsCore:subItemByID', function(target, itemId, count, callback, sourceResource)
    target = tonumber(target)
    itemId = tonumber(itemId)
    count = tonumber(count)
    local invokingResource = tostring(sourceResource or GetInvokingResource() or "server")
    if not target or not itemId or not isValidCount(count) then
        notifyItemFailure(target, "invalid_count", nil, invokingResource)
        finishInventoryOperation(callback, false, "invalid_count", { itemId = itemId, amount = count or 0 })
        return false
    end

    local User = jrsCore and jrsCore.getUser and jrsCore.getUser(target)
    if not User or not User.getUsedCharacter then
        finishInventoryOperation(callback, false, "player_not_found", { itemId = itemId, amount = count })
        return false
    end

    local itemSnapshot
    for _, entry in pairs(inv_table[target] or {}) do
        if tonumber(entry.itemId) == itemId then
            itemSnapshot = deepCopy(entry)
            break
        end
    end

    local removed, removeReason = RemoveInventoryItemByIdDirect(target, itemId, count)
    if not removed then
        local reason = removeReason or "remove_failed"
        notifyItemFailure(target, reason, itemSnapshot and itemSnapshot.item, invokingResource)
        finishInventoryOperation(callback, false, reason, { itemId = itemId, amount = count })
        return false
    end

    SaveInventoryNow(target)
    updateItemsInventory(target)
    local itemName = itemSnapshot and tostring(itemSnapshot.item or "unknown") or "unknown"
    local label = ItemLabelFor(target, itemName)
    JRSInventoryLogAction("Items", "Item Removed By ID", target, {
        item = label .. " (`" .. itemName .. "`)",
        itemId = itemId,
        amount = count,
        metadata = itemSnapshot and itemSnapshot.metaData or {},
        sourceResource = invokingResource,
    })
    if shouldNotifyTrustedOperation(invokingResource) then
        notifyInventory(target, _Up(target, 'item_removed', count, label), 3500)
    end
    finishInventoryOperation(callback, true, "success", {
        item = itemName,
        label = label,
        amount = count,
        itemId = itemId,
    })
    return true
end)

-- ===========================================================================
-- Money & Gold player transfers
-- ===========================================================================

local function getCharacterCurrencyBalance(Character, currencyType)
    if not Character then return 0 end
    if currencyType == 0 then return tonumber(Character.money) or 0 end
    if currencyType == 1 then return tonumber(Character.gold) or 0 end
    if currencyType == 3 then return tonumber(Character.dirtymoney) or 0 end
    return 0
end

local function getCurrencyLogName(currencyType)
    if currencyType == 0 then return "Money" end
    if currencyType == 1 then return "Gold" end
    if currencyType == 3 then return "Dirty Money" end
    return "Currency"
end

local function getCurrencyKey(currencyType)
    if currencyType == 0 then return "money" end
    if currencyType == 1 then return "gold" end
    if currencyType == 3 then return "dirtymoney" end
    return "currency"
end

-- `who` is the player who will read the message, so it resolves in their
-- language rather than the server default.
local function getCurrencyNotEnoughMessage(who, currencyType)
    if currencyType == 0 then return _Up(who, 'not_enough_money') end
    if currencyType == 1 then return _Up(who, 'not_enough_gold') end
    if currencyType == 3 then return _Up(who, 'not_enough_dirtymoney') end
    return _Up(who, 'transfer_failed')
end

local function transferCurrency(giver, target, amount, currencyType, currencyName, operationId)
    giver = tonumber(giver)
    target = tonumber(target)
    amount = tonumber(amount)

    if not giver or not target or giver == target or not isValidCount(amount) then
        notifyInventory(giver, _Up(giver, 'invalid_target'))
        return
    end
    if not ClaimInventoryOperation(giver, operationId, ("give_currency:%s:%s:%s"):format(tostring(target), tostring(currencyType), tostring(amount))) then
        notifyInventory(giver, _Up(giver, 'transfer_busy'))
        return
    end
    if isOnCooldown(giver) then
        notifyInventory(giver, _Up(giver, 'too_fast'))
        return
    end
    if not isValidTarget(target) then
        notifyInventory(giver, _Up(giver, 'invalid_target'))
        return
    end
    if not ArePlayersWithinTransferDistance(giver, target) then
        notifyInventory(giver, _Up(giver, 'target_too_far'))
        return
    end
    if not TryLockInventoryPlayers(giver, target) then
        notifyInventory(giver, _Up(giver, 'transfer_busy'))
        return
    end

    local function finish()
        UnlockInventoryPlayers(giver, target)
    end

    local giverUser = jrsCore and jrsCore.getUser and jrsCore.getUser(giver)
    local targetUser = jrsCore and jrsCore.getUser and jrsCore.getUser(target)
    local giverCharacter = giverUser and giverUser.getUsedCharacter
    local targetCharacter = targetUser and targetUser.getUsedCharacter
    if not giverCharacter or not targetCharacter then
        finish()
        notifyInventory(giver, _Up(giver, 'invalid_target'))
        return
    end
    if not ArePlayersWithinTransferDistance(giver, target) then
        finish()
        notifyInventory(giver, _Up(giver, 'target_too_far'))
        return
    end

    local balance = getCharacterCurrencyBalance(giverCharacter, currencyType)
    if not balance or balance < amount then
        finish()
        notifyInventory(giver, getCurrencyNotEnoughMessage(giver, currencyType))
        return
    end

    -- pcall's own first return is only "did removeCurrency error", not the
    -- function's actual success boolean. Discarding the second return let a
    -- charge that ran without erroring but reported failure (removeCurrency
    -- returns false, not an error, on invalid state) still hand the target money.
    local removedOk, removedOn = pcall(giverCharacter.removeCurrency, giver, currencyType, amount)
    if not removedOk or removedOn ~= true then
        finish()
        notifyInventory(giver, _Up(giver, 'transfer_failed'))
        return
    end

    local addedOk, addedOn = pcall(targetCharacter.addCurrency, target, currencyType, amount)
    if not addedOk or addedOn ~= true then
        pcall(giverCharacter.addCurrency, giver, currencyType, amount)
        finish()
        notifyInventory(giver, _Up(giver, 'transfer_failed'))
        return
    end

    TriggerEvent("jrs_inventory:get_items_sec", giver)
    TriggerEvent("jrs_inventory:get_items_sec", target)
    TriggerEvent("jrs_inventory:get_money_sec", giver)
    TriggerEvent("jrs_inventory:get_money_sec", target)
    notifyInventory(giver, _Up(giver, 'gave_currency', amount, currencyName), 3000)
    notifyInventory(target, _Up(target, 'received_currency', amount, currencyName), 3000)
    JRSInventoryLogAction("Currency", getCurrencyLogName(currencyType) .. " Given To Player", giver, {
        target = target,
        amount = amount,
        currency = getCurrencyKey(currencyType),
    })
    finish()
end

RegisterNetEvent('jrs_inventory:give_money')
AddEventHandler('jrs_inventory:give_money', function(target, amount, _, operationId)
    transferCurrency(source, target, amount, 0, '$', operationId)
end)

RegisterNetEvent('jrs_inventory:give_gold')
AddEventHandler('jrs_inventory:give_gold', function(target, amount, _, operationId)
    transferCurrency(source, target, amount, 1, 'gold', operationId)
end)

RegisterNetEvent('jrs_inventory:give_dirtymoney')
AddEventHandler('jrs_inventory:give_dirtymoney', function(target, amount, _, operationId)
    transferCurrency(source, target, amount, 3, 'dirty money', operationId)
end)

-- Deprecated insecure ground-credit/subtraction events. Ground drop/pickup is
-- handled atomically in server/ground.lua.
RegisterNetEvent('jrs_inventory:drop_money')
AddEventHandler('jrs_inventory:drop_money', function()
    if Config.Debug then print('[jrs_inventory] Blocked deprecated drop_money event') end
end)

RegisterNetEvent('jrs_inventory:drop_gold')
AddEventHandler('jrs_inventory:drop_gold', function()
    if Config.Debug then print('[jrs_inventory] Blocked deprecated drop_gold event') end
end)

RegisterNetEvent('jrs_inventory:drop_give_money')
AddEventHandler('jrs_inventory:drop_give_money', function()
    if Config.Debug then print('[jrs_inventory] Blocked deprecated drop_give_money event') end
end)

RegisterNetEvent('jrs_inventory:drop_give_gold')
AddEventHandler('jrs_inventory:drop_give_gold', function()
    if Config.Debug then print('[jrs_inventory] Blocked deprecated drop_give_gold event') end
end)

RegisterNetEvent('jrs_inventory:multi_delete_items')
AddEventHandler('jrs_inventory:multi_delete_items', function(entries)
    -- Was: no rate limit, no lock, no size cap, and fractional counts (0.5)
    -- accepted, which left half-items that break stacks, weight and trades.
    local _source = tonumber(source)
    if not _source or type(entries) ~= 'table' or #entries == 0 then return end
    if not AllowInventoryRequest(_source, 'multi_delete', 4, 5000) then return end
    if #entries > 64 then
        RecordInventorySecurityViolation(_source, 'multi_delete_too_large', tostring(#entries))
        return
    end

    local User = jrsCore and jrsCore.getUser and jrsCore.getUser(_source)
    local Character = User and User.getUsedCharacter
    if not Character then return end
    if not TryLockInventoryPlayer(_source) then
        notifyInventory(_source, _Up(_source, 'transfer_busy'))
        return
    end

    local itemsChanged = false
    local weaponIds = {}

    for _, entry in ipairs(entries) do
        if type(entry) == 'table' and entry.kind == 'item' then
            local itemId = tonumber(entry.id)
            local count = tonumber(entry.count) or 1
            if itemId and isValidCount(count) then
                local canDelete = true
                for _, invItem in pairs(inv_table[_source] or {}) do
                    if tonumber(invItem.itemId) == itemId and Config.IsPersonalItem(invItem.item) then
                        canDelete = false
                        break
                    end
                end

                if canDelete and RemoveInventoryItemByIdDirect(_source, itemId, count) then
                    itemsChanged = true
                end
            end
        elseif type(entry) == 'table' and entry.kind == 'weapon' then
            local weaponId = tonumber(entry.id)
            if weaponId and #weaponIds < 16 then weaponIds[#weaponIds + 1] = weaponId end
        end
    end

    if itemsChanged then
        SaveInventoryNow(_source)
        updateItemsInventory(_source)
    end
    UnlockInventoryPlayer(_source)

    -- Weapons are removed through the ownership-checked trusted path; refresh
    -- once they are all done (this used to never refresh the bag).
    local pending = #weaponIds
    for _, weaponId in ipairs(weaponIds) do
        TriggerEvent('jrsCore:subWeapon', _source, weaponId, function()
            pending = pending - 1
            if pending == 0 then TriggerEvent('jrs_inventory:get_items_sec', _source) end
        end, 'jrs_inventory')
    end
end)

-- Job resources that may only be sold at their NPC (Config.NoTransferItems).
exports('isNoTransferItem', function(itemName)
    return Config.IsNoTransferItem(itemName)
end)
