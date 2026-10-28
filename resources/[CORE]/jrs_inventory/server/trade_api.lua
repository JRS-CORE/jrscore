-- ===========================================================================
-- JRS Trade trusted escrow bridge
-- Server-only API consumed by the standalone jrs_trade resource.
-- ===========================================================================

local TRADE_RESOURCE = 'jrs_trade'

local function tradeCallerAllowed()
    local caller = GetInvokingResource()
    -- Same-resource exports can report nil depending on the CFX call path.
    -- External resources always report their resource name, so nil/empty is safe here.
    return caller == nil or caller == '' or caller == TRADE_RESOURCE or caller == GetCurrentResourceName()
end

local function copyTable(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[copyTable(k, seen)] = copyTable(v, seen)
    end
    return out
end

local function awaitExecute(query, params)
    local p = promise.new()
    exports[Config.MysqlResource]:execute(query, params or {}, function(result)
        p:resolve(result)
    end)
    return Citizen.Await(p)
end

local function awaitTransaction(queries)
    local p = promise.new()
    RunInventoryTransaction(queries, function(success)
        p:resolve(success == true)
    end)
    return Citizen.Await(p) == true
end

local function affectedRows(result)
    if type(result) == 'number' then return result end
    if type(result) == 'table' then
        return tonumber(result.affectedRows or result.changedRows or result.rowCount or result[1]) or 0
    end
    return 0
end

local function characterFor(source)
    source = tonumber(source)
    if not source or source <= 0 or not jrsCore then return nil end
    if type(jrsCore.GetCharacter) == 'function' then
        local Character = jrsCore.GetCharacter(source)
        if Character then return Character end
    end
    local User = jrsCore.getUser and jrsCore.getUser(source)
    return User and (User.character or User.getUsedCharacter) or nil
end

local function sameMetadata(a, b)
    local okA, encA = pcall(json.encode, a or {})
    local okB, encB = pcall(json.encode, b or {})
    return okA and okB and encA == encB
end

local function findItemById(source, itemId)
    for _, item in pairs(inv_table[tonumber(source)] or {}) do
        if tonumber(item.itemId) == tonumber(itemId) then
            return item
        end
    end
    return nil
end

local function makeUniqueItemId(source)
    local used = {}
    for _, item in pairs(inv_table[tonumber(source)] or {}) do
        used[tonumber(item.itemId)] = true
    end
    local id
    repeat
        id = math.random(100000000, 99999999999999)
    until not used[id]
    return id
end

local function addEscrowItemForReturn(source, entry)
    source = tonumber(source)
    local amount = math.max(1, math.floor(tonumber(entry.amount or entry.count) or 1))
    local originalId = tonumber(entry.itemId)
    local existing = originalId and findItemById(source, originalId) or nil

    if existing and tostring(existing.item) == tostring(entry.item) and sameMetadata(existing.metaData, entry.metaData) then
        existing.count = math.floor((tonumber(existing.count) or 0) + amount)
        return true
    end

    local ok = AddInventoryItemDirect(source, tostring(entry.item), amount, entry.metaData or {}, tonumber(entry.slot))
    if ok then return true end

    -- Refunds must never disappear only because the player filled the bag while
    -- the offer was locked. In that exceptional case restore the property even
    -- if the configured carry weight is temporarily exceeded.
    inv_table[source] = inv_table[source] or {}
    local itemName = tostring(entry.item or '')
    if itemName == '' or not itemTableForData[itemName] then return false end

    local restoredId = originalId
    if not restoredId or findItemById(source, restoredId) then
        restoredId = makeUniqueItemId(source)
    end
    local preferredSlot = tonumber(entry.slot)
    local slotBusy = false
    if preferredSlot then
        for _, item in pairs(inv_table[source] or {}) do
            if tonumber(item.slot) == preferredSlot then slotBusy = true break end
        end
        if not slotBusy then
            for _, weapon in pairs(weapon_table[source] or {}) do
                if tonumber(weapon.slot) == preferredSlot then slotBusy = true break end
            end
        end
    end
    if not preferredSlot or slotBusy then preferredSlot = GetFreeSlot(source) end

    table.insert(inv_table[source], {
        itemId = restoredId,
        item = itemName,
        label = entry.label or itemTableForData[itemName].label or itemName,
        count = amount,
        metaData = copyTable(entry.metaData or {}),
        slot = preferredSlot,
    })
    return true
end

local function getOwnedWeaponRows(source)
    local Character = characterFor(source)
    if not Character then return nil end
    return awaitExecute(
        'SELECT * FROM jrs_weaponloadout WHERE identifier=@identifier AND charidentifier=@charidentifier ORDER BY id ASC',
        { ['identifier'] = Character.identifier, ['charidentifier'] = Character.charIdentifier }
    ) or {}
end

local function buildUsedWeaponSlots(rows)
    local used = {}
    for _, row in pairs(rows or {}) do
        local slot = tonumber(row.slot)
        if slot then used[slot] = true end
    end
    return used
end

local function chooseSlot(used, preferred)
    preferred = tonumber(preferred)
    if preferred and preferred > 0 and not used[preferred] then
        used[preferred] = true
        return preferred
    end
    local slot = 1
    while used[slot] do slot = slot + 1 end
    used[slot] = true
    return slot
end

local function validateEscrowWeapon(entry)
    local rows = awaitExecute(
        'SELECT * FROM jrs_weaponloadout WHERE id=@id LIMIT 1',
        { ['id'] = tonumber(entry.weaponId or entry.id) }
    ) or {}
    local row = rows[1]
    if not row then return nil, 'weapon_missing' end
    if tostring(row.identifier or '') ~= '' or tonumber(row.charidentifier) ~= 0 then
        return nil, 'weapon_not_in_escrow'
    end
    if tostring(row.serial_number or '') ~= tostring(entry.serial_number or '') then
        return nil, 'weapon_serial_mismatch'
    end
    return row
end

local function canReceiveEscrow(source, escrow)
    source = tonumber(source)
    local Character = characterFor(source)
    if not source or not Character or not IsInventoryLoadedForPlayer(source, Character) then
        return false, 'inventory_not_loaded'
    end

    local newWeight = GetInventoryWeight(source)
    for _, entry in ipairs((escrow and escrow.items) or {}) do
        local itemData = itemTableForData[tostring(entry.item or '')]
        if not itemData then return false, 'invalid_item' end
        local amount = math.max(1, math.floor(tonumber(entry.amount or entry.count) or 1))
        newWeight = newWeight + (amount * (tonumber(itemData.limit) or 0))
    end
    local maxWeight = type(GetMaxWeight) == 'function' and GetMaxWeight(source) or (tonumber(Config.Max_Items) or 50)
    if newWeight > maxWeight then
        return false, 'full'
    end

    local rows = getOwnedWeaponRows(source)
    if rows == nil then return false, 'player_not_found' end
    local current = 0
    for _, row in pairs(rows) do
        if ShouldCountWeaponTowardLimit(row.name) then current = current + 1 end
    end
    local incoming = 0
    for _, entry in ipairs((escrow and escrow.weapons) or {}) do
        if ShouldCountWeaponTowardLimit(entry.name) then incoming = incoming + 1 end
    end
    if (current + incoming) > (tonumber(getMaxWeapons(source)) or 0) then
        return false, 'weapon_full'
    end
    return true, 'ok'
end

exports('tradeGetSnapshot', function(source)
    if not tradeCallerAllowed() then return nil, 'unauthorized' end
    source = tonumber(source)
    local Character = characterFor(source)
    if not source or not Character or not IsInventoryLoadedForPlayer(source, Character) then
        return nil, 'inventory_not_loaded'
    end

    local items = {}
    for _, entry in pairs(inv_table[source] or {}) do
        local name = tostring(entry.item or '')
        if name ~= '' and not Config.IsPersonalItem(name) and not Config.IsNoTransferItem(name) then
            items[#items + 1] = {
                itemId = tonumber(entry.itemId),
                item = name,
                label = entry.label or ItemLabelFor(source, name),
                count = math.max(0, math.floor(tonumber(entry.count) or 0)),
                slot = tonumber(entry.slot),
                metaData = copyTable(entry.metaData or {}),
            }
        end
    end

    local weapons = {}
    for _, row in pairs(getOwnedWeaponRows(source) or {}) do
        local name = tostring(row.name or '')
        if name ~= '' and not Config.IsPersonalItem(name) then
            weapons[#weapons + 1] = {
                weaponId = tonumber(row.id),
                name = name,
                label = (weaponTableForData[name] and weaponTableForData[name].label) or name,
                serial_number = row.serial_number,
                used = tonumber(row.used) or 0,
                slot = tonumber(row.slot),
                conditionlevel = tonumber(row.conditionlevel),
                dirtlevel = tonumber(row.dirtlevel),
                ammo = row.ammo,
                comps = row.comps,
            }
        end
    end

    return { items = items, weapons = weapons }, 'ok'
end)

exports('tradeCanReceive', function(source, escrow)
    if not tradeCallerAllowed() then return false, 'unauthorized' end
    return canReceiveEscrow(source, escrow)
end)

exports('tradeReserveOffer', function(source, itemSelections, weaponSelections, orderContext)
    if not tradeCallerAllowed() then return false, 'unauthorized' end
    source = tonumber(source)
    local Character = characterFor(source)
    if not source or not Character or not IsInventoryLoadedForPlayer(source, Character) then
        return false, 'inventory_not_loaded'
    end
    if not TryLockInventoryPlayer(source) then return false, 'busy' end

    local originalInventory = copyTable(inv_table[source] or {})
    local escrow = { items = {}, weapons = {} }
    local queries = {}
    local ok, reason = true, 'ok'

    local seenItems = {}
    for _, selection in ipairs(type(itemSelections) == 'table' and itemSelections or {}) do
        local itemId = tonumber(selection.itemId)
        local amount = math.floor(tonumber(selection.count or selection.amount) or 0)
        if not itemId or amount <= 0 or seenItems[itemId] then
            ok, reason = false, 'invalid_item_selection'
            break
        end
        seenItems[itemId] = true

        local live = findItemById(source, itemId)
        if not live or (tonumber(live.count) or 0) < amount then
            ok, reason = false, 'item_not_owned'
            break
        end
        if Config.IsPersonalItem(live.item) then
            ok, reason = false, 'personal_item'
            break
        end
        if Config.IsNoTransferItem(live.item) then
            ok, reason = false, 'resource_item'
            TriggerClientEvent("jrsCore:notify", source, _Up(source, 'inventory'), _Up(source, 'resource_item_locked'), 'bag', 3500)
            break
        end

        local snapshot = {
            itemId = itemId,
            item = live.item,
            label = live.label or ItemLabelFor(source, live.item),
            amount = amount,
            metaData = copyTable(live.metaData or {}),
            slot = tonumber(live.slot),
        }
        local removed, removeReason = RemoveInventoryItemByIdDirect(source, itemId, amount)
        if not removed then
            ok, reason = false, removeReason or 'remove_failed'
            break
        end
        escrow.items[#escrow.items + 1] = snapshot
    end

    local seenWeapons = {}
    if ok then
        for _, weaponValue in ipairs(type(weaponSelections) == 'table' and weaponSelections or {}) do
            local weaponId = tonumber(type(weaponValue) == 'table' and (weaponValue.weaponId or weaponValue.id) or weaponValue)
            if not weaponId or seenWeapons[weaponId] then
                ok, reason = false, 'invalid_weapon_selection'
                break
            end
            seenWeapons[weaponId] = true

            local rows = awaitExecute('SELECT * FROM jrs_weaponloadout WHERE id=@id LIMIT 1', { ['id'] = weaponId }) or {}
            local row = rows[1]
            if not row or tostring(row.identifier) ~= tostring(Character.identifier) or tonumber(row.charidentifier) ~= tonumber(Character.charIdentifier) then
                ok, reason = false, 'weapon_not_owned'
                break
            end
            if tonumber(row.used) == 1 then
                ok, reason = false, 'weapon_equipped'
                break
            end
            if Config.IsPersonalItem(row.name) then
                ok, reason = false, 'personal_item'
                break
            end
            local serial = tostring(row.serial_number or '')
            if serial == '' then
                ok, reason = false, 'weapon_serial_missing'
                break
            end

            escrow.weapons[#escrow.weapons + 1] = {
                weaponId = weaponId,
                name = row.name,
                label = (weaponTableForData[row.name] and weaponTableForData[row.name].label) or row.name,
                serial_number = serial,
                slot = tonumber(row.slot),
                ammo = row.ammo,
                comps = row.comps,
                dirtlevel = tonumber(row.dirtlevel),
                conditionlevel = tonumber(row.conditionlevel),
            }
            queries[#queries + 1] = {
                query = "UPDATE jrs_weaponloadout SET identifier='', charidentifier=0, used=0 WHERE id=? AND identifier=? AND charidentifier=? AND used=0 AND serial_number=?",
                values = { weaponId, Character.identifier, Character.charIdentifier, serial }
            }
        end
    end

    if not ok then
        inv_table[source] = originalInventory
        updateItemsInventory(source)
        UnlockInventoryPlayer(source)
        return false, reason
    end

    if #escrow.items == 0 and #escrow.weapons == 0 then
        inv_table[source] = originalInventory
        UnlockInventoryPlayer(source)
        return false, 'empty_offer'
    end

    queries[#queries + 1] = {
        query = 'UPDATE jrs_characters SET inventory=? WHERE identifier=? AND charidentifier=?',
        values = { json.encode(inv_table[source] or {}), Character.identifier, Character.charIdentifier }
    }

    if type(orderContext) == 'table' and tostring(orderContext.tradeKey or '') ~= '' then
        local buyerIdentifier = tostring(orderContext.buyerIdentifier or '')
        local buyerCharid = tostring(orderContext.buyerCharid or '')
        if buyerIdentifier == '' or buyerCharid == '' then
            inv_table[source] = originalInventory
            updateItemsInventory(source)
            UnlockInventoryPlayer(source)
            return false, 'invalid_buyer_identity'
        end
        queries[#queries + 1] = {
            query = [[
                INSERT INTO jrs_trade_orders
                    (trade_key, seller_identifier, seller_charid, seller_name, buyer_identifier, buyer_charid, buyer_name, price, status, offer_json, expires_at, buyer_charged, delivered, seller_paid)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'locked', ?, ?, 0, 0, 0)
                ON DUPLICATE KEY UPDATE
                    seller_identifier=VALUES(seller_identifier), seller_charid=VALUES(seller_charid), seller_name=VALUES(seller_name),
                    buyer_identifier=VALUES(buyer_identifier), buyer_charid=VALUES(buyer_charid), buyer_name=VALUES(buyer_name),
                    price=VALUES(price), status='locked', offer_json=VALUES(offer_json), expires_at=VALUES(expires_at),
                    buyer_charged=0, delivered=0, seller_paid=0, cancel_reason=NULL, updated_at=CURRENT_TIMESTAMP
            ]],
            values = {
                tostring(orderContext.tradeKey), tostring(Character.identifier), tostring(Character.charIdentifier), tostring(orderContext.sellerName or ''),
                buyerIdentifier, buyerCharid, tostring(orderContext.buyerName or ''), math.max(0, math.floor(tonumber(orderContext.price) or 0)),
                json.encode(escrow), tostring(orderContext.expiresAt or '')
            }
        }
    end

    local committed = awaitTransaction(queries)
    if not committed then
        inv_table[source] = originalInventory
        updateItemsInventory(source)
        UnlockInventoryPlayer(source)
        return false, 'database_failed'
    end

    updateItemsInventory(source)
    TriggerEvent('jrs_inventory:get_items_sec', source)
    UnlockInventoryPlayer(source)
    return true, 'ok', escrow
end)

exports('tradeReturnEscrow', function(source, escrow, tradeContext)
    if not tradeCallerAllowed() then return false, 'unauthorized' end
    source = tonumber(source)
    local Character = characterFor(source)
    if not source or not Character or not IsInventoryLoadedForPlayer(source, Character) then
        return false, 'inventory_not_loaded'
    end
    if not TryLockInventoryPlayer(source) then return false, 'busy' end

    local originalInventory = copyTable(inv_table[source] or {})
    local queries = {}
    local ok, reason = true, 'ok'

    for _, entry in ipairs((escrow and escrow.items) or {}) do
        if not addEscrowItemForReturn(source, entry) then
            ok, reason = false, 'item_restore_failed'
            break
        end
    end

    local ownedRows = getOwnedWeaponRows(source) or {}
    local usedSlots = buildUsedWeaponSlots(ownedRows)
    if ok then
        for _, entry in ipairs((escrow and escrow.weapons) or {}) do
            local row, verifyReason = validateEscrowWeapon(entry)
            if not row then
                ok, reason = false, verifyReason
                break
            end
            local slot = chooseSlot(usedSlots, entry.slot)
            queries[#queries + 1] = {
                query = "UPDATE jrs_weaponloadout SET identifier=?, charidentifier=?, slot=?, used=0 WHERE id=? AND identifier='' AND charidentifier=0 AND serial_number=?",
                values = { Character.identifier, Character.charIdentifier, slot, tonumber(entry.weaponId or entry.id), tostring(entry.serial_number) }
            }
        end
    end

    if not ok then
        inv_table[source] = originalInventory
        UnlockInventoryPlayer(source)
        return false, reason
    end

    queries[#queries + 1] = {
        query = 'UPDATE jrs_characters SET inventory=? WHERE identifier=? AND charidentifier=?',
        values = { json.encode(inv_table[source] or {}), Character.identifier, Character.charIdentifier }
    }

    if type(tradeContext) == 'table' and tostring(tradeContext.tradeKey or '') ~= '' then
        queries[#queries + 1] = {
            query = 'UPDATE jrs_trade_orders SET status=?, cancel_reason=?, updated_at=CURRENT_TIMESTAMP WHERE trade_key=?',
            values = { tostring(tradeContext.finalStatus or 'cancelled'), tostring(tradeContext.cancelReason or 'manual'), tostring(tradeContext.tradeKey) }
        }
    end

    local committed = awaitTransaction(queries)
    if not committed then
        inv_table[source] = originalInventory
        updateItemsInventory(source)
        UnlockInventoryPlayer(source)
        return false, 'database_failed'
    end

    updateItemsInventory(source)
    TriggerEvent('jrs_inventory:get_items_sec', source)
    UnlockInventoryPlayer(source)
    return true, 'ok'
end)

exports('tradeDeliverEscrow', function(source, escrow, tradeKey)
    if not tradeCallerAllowed() then return false, 'unauthorized' end
    source = tonumber(source)
    local Character = characterFor(source)
    if not source or not Character or not IsInventoryLoadedForPlayer(source, Character) then
        return false, 'inventory_not_loaded'
    end
    if not TryLockInventoryPlayer(source) then return false, 'busy' end

    local canCarry, carryReason = canReceiveEscrow(source, escrow)
    if not canCarry then
        UnlockInventoryPlayer(source)
        return false, carryReason
    end

    local originalInventory = copyTable(inv_table[source] or {})
    local queries = {}
    local ok, reason = true, 'ok'

    for _, entry in ipairs((escrow and escrow.items) or {}) do
        local added, addReason = AddInventoryItemDirect(
            source,
            tostring(entry.item),
            math.max(1, math.floor(tonumber(entry.amount or entry.count) or 1)),
            copyTable(entry.metaData or {})
        )
        if not added then
            ok, reason = false, addReason or 'item_add_failed'
            break
        end
    end

    local ownedRows = getOwnedWeaponRows(source) or {}
    local usedSlots = buildUsedWeaponSlots(ownedRows)
    if ok then
        for _, entry in ipairs((escrow and escrow.weapons) or {}) do
            local row, verifyReason = validateEscrowWeapon(entry)
            if not row then
                ok, reason = false, verifyReason
                break
            end
            local slot = chooseSlot(usedSlots, nil)
            queries[#queries + 1] = {
                query = "UPDATE jrs_weaponloadout SET identifier=?, charidentifier=?, slot=?, used=0 WHERE id=? AND identifier='' AND charidentifier=0 AND serial_number=?",
                values = { Character.identifier, Character.charIdentifier, slot, tonumber(entry.weaponId or entry.id), tostring(entry.serial_number) }
            }
        end
    end

    if not ok then
        inv_table[source] = originalInventory
        updateItemsInventory(source)
        UnlockInventoryPlayer(source)
        return false, reason
    end

    queries[#queries + 1] = {
        query = 'UPDATE jrs_characters SET inventory=? WHERE identifier=? AND charidentifier=?',
        values = { json.encode(inv_table[source] or {}), Character.identifier, Character.charIdentifier }
    }

    if tradeKey ~= nil and tostring(tradeKey) ~= '' then
        queries[#queries + 1] = {
            query = "UPDATE jrs_trade_orders SET delivered=1, status='processing', updated_at=CURRENT_TIMESTAMP WHERE trade_key=? AND status='processing' AND buyer_charged=1",
            values = { tostring(tradeKey) }
        }
    end

    local committed = awaitTransaction(queries)
    if not committed then
        inv_table[source] = originalInventory
        updateItemsInventory(source)
        UnlockInventoryPlayer(source)
        return false, 'database_failed'
    end

    updateItemsInventory(source)
    TriggerEvent('jrs_inventory:get_items_sec', source)
    UnlockInventoryPlayer(source)
    return true, 'ok'
end)
