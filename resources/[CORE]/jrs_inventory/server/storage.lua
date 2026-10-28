-- ===========================================================================
-- Storage (lockers / containers)
-- Server-authoritative, replay-protected and transaction-safe.
-- ===========================================================================

local function emitStorageTransaction(playerId, storageId, direction, data)
    TriggerEvent('jrs_inventory:server:storageTransaction', tonumber(playerId), tostring(storageId or ''), tostring(direction or ''), type(data) == 'table' and data or {})
end

local function notifyInventory(playerId, message, duration)
    playerId = tonumber(playerId)
    if playerId and playerId > 0 then
        TriggerClientEvent("jrsCore:notify", playerId, _Up(playerId, 'inventory'), tostring(message), 'bag', duration or 2500)
    end
end

local function checkExternalStoragePermission(playerId, storageId, direction, data)
    local denied, denyReason, denyMessage = false, nil, nil

    -- Server-local callback hook. Resources that own a storage namespace may
    -- deny the transaction. If nobody answers, the storage keeps its default
    -- inventory behavior. This is intentionally not a network event.
    TriggerEvent(
        'jrs_inventory:server:storagePermission',
        tonumber(playerId),
        tostring(storageId or ''),
        tostring(direction or ''),
        type(data) == 'table' and data or {},
        function(allowed, reason, message)
            if allowed == false then
                denied = true
                denyReason = tostring(reason or 'permission_denied')
                denyMessage = message and tostring(message) or nil
            end
        end
    )

    if denied then
        if denyMessage and denyMessage ~= '' then
            notifyInventory(playerId, denyMessage, 3500)
        end
        return false, denyReason or 'permission_denied'
    end

    return true, nil
end

local function getCharacterData(playerId)
    local src = tonumber(playerId)
    if not src then return nil end
    local Character = exports.jrs_core:GetCharacter(src) or (jrsCore and jrsCore.GetCharacter and jrsCore.GetCharacter(src))
    if Character then return Character, Character.identifier, Character.charIdentifier end

    for _ = 1, 5 do
        if not GetPlayerName(src) then return nil end
        Citizen.Wait(300)
        Character = exports.jrs_core:GetCharacter(src) or (jrsCore and jrsCore.GetCharacter and jrsCore.GetCharacter(src))
        if Character then return Character, Character.identifier, Character.charIdentifier end
    end
    return nil
end

local function changeCharacterCurrency(Character, methodName, playerId, currencyType, amount)
    if not Character then return false end
    local method = Character[methodName]
    -- Methods on a character fetched from jrs_core arrive as Cfx funcref tables
    -- (type "table" with __call), not plain functions. The old type check
    -- rejected them, so every storage cash deposit/withdraw failed.
    local methodType = type(method)
    if methodType ~= "function" and methodType ~= "table" and methodType ~= "userdata" then return false end

    -- jrs_core currency methods use: Character.method(source, currencyType, amount).
    -- Try the bound-method form only when that call raises an error; never retry
    -- after a successful call, because retrying a currency mutation could credit
    -- or debit the same amount twice.
    local ok, result = pcall(method, playerId, currencyType, amount)
    if ok then return result ~= false end

    ok, result = pcall(method, Character, playerId, currencyType, amount)
    return ok and result ~= false
end

local function cloneValue(value)
    if type(value) ~= "table" then return value end
    local ok, encoded = pcall(json.encode, value)
    if not ok then return {} end
    local decodedOk, decoded = pcall(json.decode, encoded)
    if not decodedOk or type(decoded) ~= "table" then return {} end
    return decoded
end

local function decodeItems(raw)
    local decoded
    if type(raw) == "table" then
        decoded = cloneValue(raw)
    elseif type(raw) == "string" and raw ~= "" then
        local ok, result = pcall(json.decode, raw)
        if ok and type(result) == "table" then decoded = result end
    end
    if type(decoded) ~= "table" then decoded = {} end

    for _, entry in pairs(decoded) do
        if type(entry) == "table" and entry.name == nil and entry.item ~= "money" and entry.item ~= "gold" and entry.item ~= "dirtymoney" then
            if type(JRSInventoryNormalizeMetadata) == "function" then
                entry.metaData = JRSInventoryNormalizeMetadata(entry.metaData, tostring(entry.item or ""), false)
            elseif type(entry.metaData) ~= "table" then
                entry.metaData = {}
            end
        end
    end
    return decoded
end

local function metadataEqual(first, second)
    if type(JRSInventoryMetadataEqual) == "function" then
        return JRSInventoryMetadataEqual(first, second)
    end
    local okA, encodedA = pcall(json.encode, first or {})
    local okB, encodedB = pcall(json.encode, second or {})
    if not okA or not okB then return false end
    return encodedA == encodedB
end

local function writeSucceeded(result)
    if result == nil or result == false then return false end
    if type(result) == "number" then return result > 0 end
    if type(result) == "table" then
        local rows = result.affectedRows or result.changedRows or result.rowCount
        if rows ~= nil then return tonumber(rows) and tonumber(rows) > 0 end
    end
    return true
end

local function normalizeStorageId(id)
    if id == nil then return nil end
    local value = tostring(id)
    if value == "" or #value > 190 then return nil end
    return value
end

-- Personal storages historically use id 0 but are stored under the account
-- identifier. Resolve that id consistently for open, refresh, and transfers.
local function resolveStorageId(playerId, id)
    local storageId = normalizeStorageId(id)
    if not storageId then return nil end
    if storageId ~= "0" then return storageId end

    local Character = getCharacterData(playerId)
    if not Character or Character.identifier == nil then return nil end
    return tostring(Character.identifier)
end

local function storageIsOpenForPlayer(playerId, storageId)
    playerId = tonumber(playerId)
    storageId = normalizeStorageId(storageId)
    if not playerId or not storageId then return false end
    for _, openId in pairs(openstorages[playerId] or {}) do
        if tostring(openId) == storageId then return true end
    end
    return false
end

local function storageIsOpenByAnotherPlayer(playerId, storageId)
    storageId = normalizeStorageId(storageId)
    for otherPlayer, storageList in pairs(openstorages) do
        if tonumber(otherPlayer) ~= tonumber(playerId) and playerIsActive(otherPlayer) then
            for _, openId in pairs(storageList or {}) do
                if tostring(openId) == storageId then
                    return true
                end
            end
        end
    end
    return false
end

local function storageEntryWeight(entry)
    if type(entry) ~= "table" then return 0.0 end
    if entry.name ~= nil or entry.weapon == true then return 1.0 end
    local count = tonumber(entry.count) or 0
    if entry.item == "money" or entry.item == "gold" or entry.item == "dirtymoney" then
        return count * 0.2
    end
    local itemData = itemTableForData[tostring(entry.item or "")]
    return count * (tonumber(itemData and itemData.limit) or 0.0)
end

local function storageWeight(items)
    local total = 0.0
    for _, entry in pairs(items or {}) do
        total = total + storageEntryWeight(entry)
    end
    return total
end

local function normalizeStorageSlot(value)
    local slot = tonumber(value)
    if not slot or slot ~= math.floor(slot) or slot < 1 or slot > 500 then return nil end
    return slot
end

local function ensureStorageSlots(items)
    local used = {}
    local missing = {}
    for _, entry in ipairs(items or {}) do
        local slot = normalizeStorageSlot(entry.slot)
        if slot and not used[slot] then
            entry.slot = slot
            used[slot] = true
        else
            entry.slot = nil
            table.insert(missing, entry)
        end
    end

    local nextSlot = 1
    for _, entry in ipairs(missing) do
        while used[nextSlot] do nextSlot = nextSlot + 1 end
        entry.slot = nextSlot
        used[nextSlot] = true
        nextSlot = nextSlot + 1
    end
    return used
end

local function chooseStorageSlot(items, requestedSlot)
    local used = ensureStorageSlots(items)
    local requested = normalizeStorageSlot(requestedSlot)
    if requested and not used[requested] then return requested end
    local slot = 1
    while used[slot] do slot = slot + 1 end
    return slot
end

-- The item/weapon definition tables are large (every item in the database).
-- The client caches them from send_list_inventory, so storage refreshes only
-- carry them when this player has not received them yet. Sending them on every
-- transfer was the main cause of the slow, stuttering storage window.
local function storageDefinitionsFor(playerId)
    if clientDefinitionsSent and clientDefinitionsSent[tonumber(playerId)] == true then
        return false, false
    end
    return table_item, weapons_table
end

local function refreshStorage(playerId, storageId)
    playerId = tonumber(playerId)
    storageId = resolveStorageId(playerId, storageId)
    if not playerId or not storageId then return end

    exports[Config.MysqlResource]:execute(
        'SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1',
        { ['identifier'] = storageId },
        function(rows)
            local row = rows and rows[1]
            if not row then return end
            local defs, weaponDefs = storageDefinitionsFor(playerId)
            TriggerClientEvent(
                "jrs_inventory:refresh_storage",
                playerId,
                decodeItems(row.items),
                defs,
                weaponDefs,
                storageId,
                tonumber(row.size) or 0
            )
        end
    )
end

local function storageTransferResult(playerId, storageId, success, reason)
    TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), success == true, reason or "failed")
    refreshStorage(playerId, storageId)
end

local function runTransaction(queries, callback)
    RunInventoryTransaction(queries, callback)
end

local function characterInventoryTransactionQueries(playerId, Character, storageId, storageItems)
    return {
        {
            query = 'UPDATE jrs_inventory_storage SET items=? WHERE identifier=?',
            values = { json.encode(storageItems), storageId }
        },
        {
            query = 'UPDATE jrs_characters SET inventory=? WHERE identifier=? AND charidentifier=?',
            values = { json.encode(inv_table[tonumber(playerId)] or {}), Character.identifier, Character.charIdentifier }
        }
    }
end

local function beginStorageTransfer(playerId, storageId, operationId, fingerprint)
    if tostring(storageId or ''):find('^admin_search:') then return false, "admin_search" end
    playerId = tonumber(playerId)
    storageId = resolveStorageId(playerId, storageId)
    if not playerId or not storageId then return false, "invalid_request" end
    if not ClaimInventoryOperation(playerId, operationId, fingerprint) then return false, "replayed" end
    if isOnCooldown(playerId) then return false, "cooldown" end
    if not storageIsOpenForPlayer(playerId, storageId) then
        RecordInventorySecurityViolation(playerId, "storage_not_open", storageId)
        return false, "storage_not_open"
    end
    if storageIsOpenByAnotherPlayer(playerId, storageId) then
        RecordInventorySecurityViolation(playerId, "storage_opened_by_other", storageId)
        return false, "busy"
    end
    if not TryLockInventoryPlayerAndResource(playerId, "storage", storageId) then
        return false, "busy"
    end
    return true, storageId
end

local function finishStorageTransfer(playerId, storageId, success, reason, updatedItems, storageSize)
    UnlockInventoryPlayerAndResource(playerId, "storage", storageId)
    TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), success == true, reason or "failed")
    -- Successful transfer: push the already-computed storage state directly to
    -- the client instead of a second DB SELECT round-trip.
    if success and updatedItems ~= nil then
        local defs, weaponDefs = storageDefinitionsFor(playerId)
        TriggerClientEvent(
            "jrs_inventory:refresh_storage",
            tonumber(playerId),
            updatedItems,
            defs,
            weaponDefs,
            storageId,
            storageSize or 0
        )
    elseif success then
        refreshStorage(playerId, storageId)
    end
    -- On failure: no items changed, no refresh needed.
end

local function failStorageTransfer(playerId, storageId, reason, message)
    if message then notifyInventory(playerId, message) end
    -- Failure: nothing changed in storage, so just notify – no refresh needed.
    TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), false, reason or "failed")
end

-- Trusted server-local storage registration API. Do not expose as a client event.
-- Storage table guard (2026-09-24). The live table had identifier VARCHAR(50)
-- and no key at all, while ids up to 190 chars are accepted above:
--  * STRICT_TRANS_TABLES rejects any longer id, so that storage was never
--    created and every open failed with no row;
--  * without a key, ON DUPLICATE KEY / INSERT IGNORE callers (jrs_banking,
--    jrs_ranch) and the SELECT-then-INSERT below could write duplicate rows.
-- Widening is always safe. The key is only added when no duplicates exist;
-- duplicates are reported, never deleted.
CreateThread(function()
    Wait(1500)
    local mysql = exports[Config.MysqlResource]
    local ok, err = pcall(function()
        local column = mysql:executeSync([[
            SELECT CHARACTER_MAXIMUM_LENGTH AS len, DATA_TYPE AS dtype FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jrs_inventory_storage' AND COLUMN_NAME = 'identifier'
        ]])
        local info = column and column[1]
        if not info then return end
        local dtype = tostring(info.dtype or ''):lower()
        if (dtype == 'varchar' or dtype == 'char') and (tonumber(info.len) or 0) < 190 then
            mysql:executeSync("ALTER TABLE `jrs_inventory_storage` MODIFY `identifier` VARCHAR(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL")
            print('^2[jrs_inventory] jrs_inventory_storage.identifier widened to VARCHAR(190)^7')
        end

        local keyed = mysql:executeSync([[
            SELECT 1 FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jrs_inventory_storage'
              AND COLUMN_NAME = 'identifier' AND NON_UNIQUE = 0 AND SEQ_IN_INDEX = 1
            LIMIT 1
        ]])
        if keyed and keyed[1] then return end

        local dupes = mysql:executeSync([[
            SELECT identifier, COUNT(*) AS n FROM jrs_inventory_storage
            GROUP BY identifier HAVING COUNT(*) > 1 LIMIT 20
        ]])
        if dupes and dupes[1] then
            local list = {}
            for _, row in ipairs(dupes) do list[#list + 1] = tostring(row.identifier) .. ' x' .. tostring(row.n) end
            print('^3[jrs_inventory] jrs_inventory_storage has duplicate identifiers, unique key NOT added: ' .. table.concat(list, ', ') .. '^7')
            return
        end
        mysql:executeSync("ALTER TABLE `jrs_inventory_storage` ADD PRIMARY KEY (`identifier`)")
        print('^2[jrs_inventory] jrs_inventory_storage: primary key on identifier added^7')
    end)
    if not ok then
        print('^1[jrs_inventory] storage table guard failed: ' .. tostring(err) .. '^7')
    end
end)

AddEventHandler('jrsCore:registerstorage', function(requestedSource, id, size)
    local playerId = tonumber(requestedSource)
    -- Server-side callers passing 0/nil have no character; bail before any
    -- player native sees the bad id ("Argument at index 0 was null").
    if not playerId or playerId <= 0 then return end
    local invokingResource = GetInvokingResource() or "server"
    local Character = getCharacterData(playerId)
    local rawStorageId = normalizeStorageId(id)
    local storageId = resolveStorageId(playerId, id)
    local storageSize = math.max(0, tonumber(size) or 0)
    if not playerId or not rawStorageId or not storageId or not Character then return end

    local ownerCharId = rawStorageId == "0" and Character.charIdentifier or 0
    local finalIdentifier = storageId

    exports[Config.MysqlResource]:execute(
        'SELECT identifier FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1',
        { ['identifier'] = finalIdentifier },
        function(rows)
            if rows and rows[1] then return end
            exports[Config.MysqlResource]:execute(
                -- IGNORE: two quick createstorage calls for the same id must not
                -- produce a second row (the key above makes this atomic).
                'INSERT IGNORE INTO jrs_inventory_storage (identifier, charid, size, items) VALUES (@identifier, @charid, @size, @items)',
                {
                    ['identifier'] = finalIdentifier,
                    ['charid'] = ownerCharId,
                    ['size'] = storageSize,
                    ['items'] = json.encode({})
                },
                function(result)
                    if writeSucceeded(result) then
                        JRSInventoryLogAction("Storage", "Storage Registered", playerId, {
                            storage = finalIdentifier,
                            size = storageSize,
                            sourceResource = invokingResource,
                        })
                    end
                end
            )
        end
    )
end)

AddEventHandler('jrsCore:updatestorage', function(requestedSource, id, size)
    local playerId = tonumber(requestedSource)
    local storageId = resolveStorageId(playerId, id)
    local storageSize = math.max(0, tonumber(size) or 0)
    local invokingResource = GetInvokingResource() or "server"
    if not playerId or not storageId or not getCharacterData(playerId) then return end
    exports[Config.MysqlResource]:execute(
        'UPDATE jrs_inventory_storage SET size=@size WHERE identifier=@identifier',
        { ['size'] = storageSize, ['identifier'] = storageId },
        function(result)
            if writeSucceeded(result) then
                JRSInventoryLogAction("Storage", "Storage Size Updated", playerId, {
                    storage = storageId,
                    size = storageSize,
                    sourceResource = invokingResource,
                })
            end
        end
    )
end)

-- Storage window title. Callers may pass a label as the 3rd argument of
-- openstorage: a string, or { title = 'Wagon Locker', name = 'Thunder' }
-- (title/name may themselves be { en = ..., ar = ... }). Without one the kind
-- is recognised from the id and translated per player.
local StorageNamePatterns = {
    { '^jrs_trash_bin_', 'storage_name_trash' },
    { '^jrs_admin:', 'storage_name_admin' },
    { '^jrs_stash:', 'storage_name_stash' },
    { '^[Tt]rain_.*_jrs_traininv$', 'storage_name_train' },
    { '^train_freight', 'storage_name_freight' },
    { '^saddlebagID_', 'storage_name_saddlebag' },
    { '^wagonID_', 'storage_name_wagon' },
    { '^horseCargo_', 'storage_name_horse_cargo' },
    { '^balloon_', 'storage_name_balloon' },
    { '^jrs_boat_', 'storage_name_boat' },
    { '^Bank_.*_vault$', 'storage_name_bank' },
    { '^jrs_camp_storage_', 'storage_name_camp' },
    { '^jrs_moonshine_', 'storage_name_moonshine' },
    { '^jrs_backpack_', 'storage_name_backpack' },
    { '^jrs_doctors_wagon_', 'storage_name_doctor_wagon' },
    { '^jrs_doctors_mount_', 'storage_name_doctor_mount' },
    { '^jrs_doctors_personal_', 'storage_name_doctor_personal' },
    { '^jrs_doctors_hospital_', 'storage_name_hospital' },
    { '^jrs_ranch_storage_', 'storage_name_ranch' },
    { '^1%d%d%d%d%d$', 'storage_name_player_store' },
    { '^%d+$', 'storage_name_property' },
}

local function storageNameText(playerId, value)
    if type(value) == 'table' then
        local lang = (JrsLang and JrsLang.Of and JrsLang.Of(playerId)) or 'en'
        value = value[lang] or value.en or value.ar
    end
    if value == nil then return nil end
    value = tostring(value):gsub('[\r\n\t]', ' '):gsub('<', ''):gsub('>', '')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    if #value > 64 then value = value:sub(1, 64) end
    return value
end

local function storageKindTitle(playerId, storageId)
    local key = 'storage_name_default'
    for _, rule in ipairs(StorageNamePatterns) do
        if tostring(storageId):find(rule[1]) then key = rule[2]; break end
    end
    local text = _Up(playerId, key)
    if type(text) ~= 'string' or text == '' or text == key then return 'Storage' end
    return text
end

function ResolveStorageDisplay(playerId, storageId, info)
    local title, name
    if type(info) == 'table' and (info.title or info.name or info.label) then
        title = storageNameText(playerId, info.title or info.label)
        name = storageNameText(playerId, info.name)
    elseif info ~= nil then
        title = storageNameText(playerId, info)
    end
    title = title or storageKindTitle(playerId, storageId)
    if name == title then name = nil end
    return { title = title, name = name }
end

-- Trusted server-local open API. Client-side scripts cannot claim an arbitrary source.
AddEventHandler('jrsCore:openstorage', function(requestedSource, id, info)
    local playerId = tonumber(requestedSource)
    local storageId = resolveStorageId(playerId, id)
    if not playerId or not storageId or not getCharacterData(playerId) then return end

    if storageIsOpenByAnotherPlayer(playerId, storageId) then
        notifyInventory(playerId, _Up(playerId, 'inventory_opened_other'))
        return
    end
    if not TryLockInventoryResource("storage-open", storageId, playerId) then
        notifyInventory(playerId, _Up(playerId, 'transfer_busy'))
        return
    end

    exports[Config.MysqlResource]:execute(
        'SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1',
        { ['identifier'] = storageId },
        function(rows)
            local row = rows and rows[1]
            if not row then
                UnlockInventoryResource("storage-open", storageId, playerId)
                return
            end
            if storageIsOpenByAnotherPlayer(playerId, storageId) then
                UnlockInventoryResource("storage-open", storageId, playerId)
                notifyInventory(playerId, _Up(playerId, 'inventory_opened_other'))
                return
            end
            openstorages[playerId] = { storageId }
            UnlockInventoryResource("storage-open", storageId, playerId)
            local defs, weaponDefs = storageDefinitionsFor(playerId)
            TriggerClientEvent(
                "jrs_inventory:get_storage",
                playerId,
                decodeItems(row.items),
                defs,
                weaponDefs,
                storageId,
                tonumber(row.size) or 0,
                ResolveStorageDisplay(playerId, storageId, info)
            )
            if DiscordLogConfig and DiscordLogConfig.LogStorageOpenClose == true then
                JRSInventoryLogAction("Storage", "Storage Opened", playerId, {
                    storage = storageId,
                    size = tonumber(row.size) or 0,
                })
            end
        end
    )
end)

RegisterNetEvent('jrsCore:closestorage')
AddEventHandler('jrsCore:closestorage', function(id)
    local playerId = tonumber(source)
    if not playerId then return end

    -- Only close the storage actually registered for this player. Never accept
    -- an arbitrary client id as permission to release somebody else's lock.
    local opened = openstorages[playerId] or {}
    for _, storageId in pairs(opened) do
        UnlockInventoryResource("storage-open", storageId, playerId)
        if DiscordLogConfig and DiscordLogConfig.LogStorageOpenClose == true then
            JRSInventoryLogAction("Storage", "Storage Closed", playerId, {
                storage = storageId,
            })
        end
    end
    openstorages[playerId] = {}
end)

-- Server-local refresh only.
AddEventHandler('jrs_inventory:get_storage_srv', function(requestedSource, id)
    -- admin_search.lua registers this name as a network event, so clients can
    -- reach this handler too. From a client, requestedSource/id are forged
    -- (read any storage by id, or push it to another player): ignore them.
    if GetInvokingResource() == nil then return end
    if tostring(id or ''):find('^admin_search:') then return end
    refreshStorage(tonumber(requestedSource), id)
end)

-- ===========================================================================
-- Item transfers
-- ===========================================================================

RegisterNetEvent('jrs_inventory:transfer_item_to_storage')
AddEventHandler('jrs_inventory:transfer_item_to_storage', function(item, count, id, itemId, metaData, operationId, targetSlot)
    if tostring(id or ''):find('^admin_search:') then return end
    local playerId = tonumber(source)
    local amount = tonumber(count)
    local inventoryItemId = tonumber(itemId)
    local fingerprint = ("item_to_storage:%s:%s:%s"):format(tostring(id), tostring(inventoryItemId), tostring(amount))
    local started, storageId = beginStorageTransfer(playerId, id, operationId, fingerprint)
    if not started then
        failStorageTransfer(playerId, id, storageId, storageId == "cooldown" and _Up(playerId, 'too_fast') or _Up(playerId, 'transfer_busy'))
        return
    end

    if not inventoryItemId or not isValidCount(amount) then
        finishStorageTransfer(playerId, storageId, false, "invalid_request")
        return
    end

    local allowed, permissionReason = checkExternalStoragePermission(playerId, storageId, 'deposit', {
        kind = 'item', item = tostring(item or ''), amount = amount, itemId = inventoryItemId
    })
    if not allowed then
        finishStorageTransfer(playerId, storageId, false, permissionReason)
        return
    end

    local Character = getCharacterData(playerId)
    local inventoryEntry
    for _, entry in pairs(inv_table[playerId] or {}) do
        if tonumber(entry.itemId) == inventoryItemId then
            inventoryEntry = entry
            break
        end
    end

    if not Character or not inventoryEntry or (tonumber(inventoryEntry.count) or 0) < amount then
        finishStorageTransfer(playerId, storageId, false, "not_owned")
        return
    end
    if Config.IsPersonalItem(inventoryEntry.item) then
        notifyInventory(playerId, _Up(playerId, 'personal_item_locked'))
        finishStorageTransfer(playerId, storageId, false, "personal_item")
        return
    end

    exports[Config.MysqlResource]:execute(
        'SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1',
        { ['identifier'] = storageId },
        function(rows)
            local row = rows and rows[1]
            if not row then
                finishStorageTransfer(playerId, storageId, false, "storage_not_found")
                return
            end

            local storageItems = decodeItems(row.items)
            ensureStorageSlots(storageItems)
            local maxSize = tonumber(row.size) or 0
            local itemData = itemTableForData[inventoryEntry.item]
            local addedWeight = amount * (tonumber(itemData and itemData.limit) or 0)
            if storageWeight(storageItems) + addedWeight > maxSize + 0.0001 then
                notifyInventory(playerId, _Up(playerId, 'no_slots'))
                finishStorageTransfer(playerId, storageId, false, "storage_full")
                return
            end

            local cleanMetadata = type(JRSInventoryNormalizeMetadata) == "function"
                and JRSInventoryNormalizeMetadata(inventoryEntry.metaData, inventoryEntry.item, false)
                or cloneValue(inventoryEntry.metaData or {})
            local stacked = false
            for _, storedEntry in pairs(storageItems) do
                local uniqueMetadata = type(JRSInventoryMetadataRequiresUniqueInstance) == "function"
                    and JRSInventoryMetadataRequiresUniqueInstance(inventoryEntry.item, cleanMetadata)
                if not uniqueMetadata and storedEntry.name == nil and tostring(storedEntry.item) == tostring(inventoryEntry.item)
                    and metadataEqual(storedEntry.metaData or {}, cleanMetadata) then
                    storedEntry.count = math.floor((tonumber(storedEntry.count) or 0) + amount)
                    stacked = true
                    break
                end
            end
            if not stacked then
                table.insert(storageItems, {
                    item = inventoryEntry.item,
                    count = math.floor(amount),
                    metaData = cleanMetadata,
                    itemId = inventoryItemId,
                    slot = chooseStorageSlot(storageItems, targetSlot)
                })
            end

            local removed, removeReason, removeOperation = RemoveInventoryItemByIdDirect(playerId, inventoryItemId, amount)
            if not removed then
                finishStorageTransfer(playerId, storageId, false, removeReason or "remove_failed")
                return
            end

            runTransaction(characterInventoryTransactionQueries(playerId, Character, storageId, storageItems), function(success)
                if not success then
                    UndoInventoryItemRemoval(playerId, removeOperation)
                    finishStorageTransfer(playerId, storageId, false, "database_failed")
                    return
                end
                updateItemsInventory(playerId)
                local label = ItemLabelFor(playerId, inventoryEntry.item)
                JRSInventoryLogAction("Storage", "Item Moved To Storage", playerId, {
                    item = label .. " (`" .. tostring(inventoryEntry.item) .. "`)",
                    itemId = inventoryItemId,
                    amount = amount,
                    storage = storageId,
                    operationId = operationId or "legacy",
                    metadata = cleanMetadata,
                })
                emitStorageTransaction(playerId, storageId, 'deposit', {
                    kind = 'item', item = inventoryEntry.item, label = _UItem(playerId, inventoryEntry.item, label), amount = amount,
                    itemId = inventoryItemId, metadata = cleanMetadata
                })
                finishStorageTransfer(playerId, storageId, true, "ok", storageItems, maxSize)
            end)
        end
    )
end)

RegisterNetEvent('jrs_inventory:transfer_item_from_storage')
AddEventHandler('jrs_inventory:transfer_item_from_storage', function(item, count, id, itemId, metaData, operationId, targetInventorySlot)
    if tostring(id or ''):find('^admin_search:') then return end
    local playerId = tonumber(source)
    local amount = tonumber(count)
    local storageItemId = tonumber(itemId)
    local fingerprint = ("item_from_storage:%s:%s:%s"):format(tostring(id), tostring(storageItemId), tostring(amount))
    local started, storageId = beginStorageTransfer(playerId, id, operationId, fingerprint)
    if not started then
        failStorageTransfer(playerId, id, storageId, storageId == "cooldown" and _Up(playerId, 'too_fast') or _Up(playerId, 'transfer_busy'))
        return
    end

    if not storageItemId or not isValidCount(amount) then
        finishStorageTransfer(playerId, storageId, false, "invalid_request")
        return
    end

    local allowed, permissionReason = checkExternalStoragePermission(playerId, storageId, 'withdraw', {
        kind = 'item', item = tostring(item or ''), amount = amount, itemId = storageItemId
    })
    if not allowed then
        finishStorageTransfer(playerId, storageId, false, permissionReason)
        return
    end

    local Character = getCharacterData(playerId)
    if not Character then
        finishStorageTransfer(playerId, storageId, false, "player_not_loaded")
        return
    end

    exports[Config.MysqlResource]:execute(
        'SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1',
        { ['identifier'] = storageId },
        function(rows)
            local row = rows and rows[1]
            if not row then
                finishStorageTransfer(playerId, storageId, false, "storage_not_found")
                return
            end

            local storageItems = decodeItems(row.items)
            ensureStorageSlots(storageItems)
            local foundIndex, foundEntry
            for index, entry in ipairs(storageItems) do
                if entry.name == nil and tonumber(entry.itemId) == storageItemId and tostring(entry.item) == tostring(item) then
                    foundIndex, foundEntry = index, entry
                    break
                end
            end
            if not foundEntry or (tonumber(foundEntry.count) or 0) < amount then
                RecordInventorySecurityViolation(playerId, "storage_item_not_owned", fingerprint)
                finishStorageTransfer(playerId, storageId, false, "not_owned")
                return
            end

            local added, addReason, addOperation = AddInventoryItemDirect(playerId, tostring(foundEntry.item), amount, foundEntry.metaData or {}, targetInventorySlot)
            if not added then
                if addReason == "full" then notifyInventory(playerId, _Up(playerId, 'no_slots_alt')) end
                finishStorageTransfer(playerId, storageId, false, addReason or "add_failed")
                return
            end

            local remaining = math.floor((tonumber(foundEntry.count) or 0) - amount)
            if remaining <= 0 then
                table.remove(storageItems, foundIndex)
            else
                foundEntry.count = remaining
            end

            runTransaction(characterInventoryTransactionQueries(playerId, Character, storageId, storageItems), function(success)
                if not success then
                    UndoInventoryItemAdd(playerId, addOperation)
                    finishStorageTransfer(playerId, storageId, false, "database_failed")
                    return
                end
                updateItemsInventory(playerId)
                local label = ItemLabelFor(playerId, foundEntry.item)
                JRSInventoryLogAction("Storage", "Item Taken From Storage", playerId, {
                    item = label .. " (`" .. tostring(foundEntry.item) .. "`)",
                    itemId = storageItemId,
                    amount = amount,
                    storage = storageId,
                    operationId = operationId or "legacy",
                    metadata = foundEntry.metaData or {},
                })
                emitStorageTransaction(playerId, storageId, 'withdraw', {
                    kind = 'item', item = foundEntry.item, label = _UItem(playerId, foundEntry.item, label), amount = amount,
                    itemId = storageItemId, metadata = foundEntry.metaData or {}
                })
                finishStorageTransfer(playerId, storageId, true, "ok", storageItems, tonumber(row.size) or 0)
            end)
        end
    )
end)

-- ===========================================================================
-- Currency transfers (ordered to prefer loss over duplication on disconnect)
-- ===========================================================================

local function storageCurrencyBalance(Character, currencyType)
    if not Character then return 0 end
    if currencyType == 0 then return tonumber(Character.money) or 0 end
    if currencyType == 1 then return tonumber(Character.gold) or 0 end
    if currencyType == 3 then return tonumber(Character.dirtymoney) or 0 end
    return 0
end

local function storageCurrencyLabel(currencyType)
    if currencyType == 0 then return "Money" end
    if currencyType == 1 then return "Gold" end
    if currencyType == 3 then return "Dirty Money" end
    return "Currency"
end

-- `who` is the player who will read the message, so it resolves in their
-- language rather than the server default.
local function storageCurrencyNotEnough(who, currencyType)
    if currencyType == 0 then return _Up(who, 'not_enough_money') end
    if currencyType == 1 then return _Up(who, 'not_enough_gold') end
    if currencyType == 3 then return _Up(who, 'not_enough_dirtymoney') end
    return _Up(who, 'transfer_failed')
end

local function transferCurrencyToStorage(playerId, storageIdRaw, amount, currencyName, currencyType, operationId)
    if tostring(storageIdRaw or ''):find('^admin_search:') then return end
    local fingerprint = ("%s_to_storage:%s:%s"):format(currencyName, tostring(storageIdRaw), tostring(amount))

    if currencyName == "money" and Config.AllowMoneyToStorage == false then
        notifyInventory(playerId, _Up(playerId, 'money_storage_transfer_disabled'))
        if type(RecordInventorySecurityViolation) == 'function' then
            RecordInventorySecurityViolation(playerId, 'blocked_money_to_storage', fingerprint)
        end
        TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), false, "money_storage_disabled")
        return
    end

    if currencyName == "gold" and Config.AllowGoldToStorage == false then
        notifyInventory(playerId, _Up(playerId, 'gold_storage_transfer_disabled'))
        if type(RecordInventorySecurityViolation) == 'function' then
            RecordInventorySecurityViolation(playerId, 'blocked_gold_to_storage', fingerprint)
        end
        TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), false, "gold_storage_disabled")
        return
    end

    if currencyName == "dirtymoney" and Config.AllowDirtyMoneyToStorage == false then
        notifyInventory(playerId, _Up(playerId, 'dirtymoney_storage_transfer_disabled'))
        if type(RecordInventorySecurityViolation) == 'function' then
            RecordInventorySecurityViolation(playerId, 'blocked_dirtymoney_to_storage', fingerprint)
        end
        TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), false, "dirtymoney_storage_disabled")
        return
    end
    local started, storageId = beginStorageTransfer(playerId, storageIdRaw, operationId, fingerprint)
    if not started then
        failStorageTransfer(playerId, storageIdRaw, storageId, storageId == "cooldown" and _Up(playerId, 'too_fast') or _Up(playerId, 'transfer_busy'))
        return
    end
    if not isValidCount(amount) then
        finishStorageTransfer(playerId, storageId, false, "invalid_count")
        return
    end

    local allowed, permissionReason = checkExternalStoragePermission(playerId, storageId, 'deposit', {
        kind = 'currency', currency = currencyName, amount = amount
    })
    if not allowed then
        finishStorageTransfer(playerId, storageId, false, permissionReason)
        return
    end

    local Character = getCharacterData(playerId)
    local balance = storageCurrencyBalance(Character, currencyType)
    if not Character or balance < amount then
        notifyInventory(playerId, storageCurrencyNotEnough(playerId, currencyType))
        finishStorageTransfer(playerId, storageId, false, "not_enough")
        return
    end

    exports[Config.MysqlResource]:execute('SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1', {
        ['identifier'] = storageId
    }, function(rows)
        local row = rows and rows[1]
        if not row then
            finishStorageTransfer(playerId, storageId, false, "storage_not_found")
            return
        end
        local storageItems = decodeItems(row.items)
        local maxSize = tonumber(row.size) or 0
        if storageWeight(storageItems) + amount * 0.2 > maxSize + 0.0001 then
            notifyInventory(playerId, _Up(playerId, 'no_slots'))
            finishStorageTransfer(playerId, storageId, false, "storage_full")
            return
        end

        local found = false
        for _, entry in ipairs(storageItems) do
            if entry.item == currencyName then
                entry.count = (tonumber(entry.count) or 0) + amount
                found = true
                break
            end
        end
        if not found then table.insert(storageItems, { item = currencyName, count = amount }) end

        -- The balance was read before the async SELECT; money can have been
        -- spent elsewhere meanwhile. Re-check so the balance can't go negative.
        local freshCharacter = getCharacterData(playerId)
        if not freshCharacter or storageCurrencyBalance(freshCharacter, currencyType) < amount then
            notifyInventory(playerId, storageCurrencyNotEnough(playerId, currencyType))
            finishStorageTransfer(playerId, storageId, false, "not_enough")
            return
        end
        local removedOk = changeCharacterCurrency(Character, 'removeCurrency', playerId, currencyType, amount)
        if not removedOk then
            finishStorageTransfer(playerId, storageId, false, "currency_remove_failed")
            return
        end

        exports[Config.MysqlResource]:execute('UPDATE jrs_inventory_storage SET items=@items WHERE identifier=@identifier', {
            ['items'] = json.encode(storageItems), ['identifier'] = storageId
        }, function(result)
            if not writeSucceeded(result) then
                changeCharacterCurrency(Character, 'addCurrency', playerId, currencyType, amount)
                finishStorageTransfer(playerId, storageId, false, "database_failed")
                return
            end
            TriggerEvent("jrs_inventory:get_money_sec", playerId)
            local currencyLabel = storageCurrencyLabel(currencyType)
            JRSInventoryLogAction("Currency", currencyLabel .. " Moved To Storage", playerId, {
                amount = amount,
                storage = storageId,
                operationId = operationId or "legacy",
                currency = currencyName,
            })
            emitStorageTransaction(playerId, storageId, 'deposit', {
                kind = 'currency', currency = currencyName, label = currencyLabel, amount = amount
            })
            finishStorageTransfer(playerId, storageId, true, "ok", storageItems, maxSize)
        end)
    end)
end

local function transferCurrencyFromStorage(playerId, storageIdRaw, amount, currencyName, currencyType, operationId)
    if tostring(storageIdRaw or ''):find('^admin_search:') then return end
    local fingerprint = ("%s_from_storage:%s:%s"):format(currencyName, tostring(storageIdRaw), tostring(amount))
    local started, storageId = beginStorageTransfer(playerId, storageIdRaw, operationId, fingerprint)
    if not started then
        failStorageTransfer(playerId, storageIdRaw, storageId, storageId == "cooldown" and _Up(playerId, 'too_fast') or _Up(playerId, 'transfer_busy'))
        return
    end
    if not isValidCount(amount) then
        finishStorageTransfer(playerId, storageId, false, "invalid_count")
        return
    end

    local allowed, permissionReason = checkExternalStoragePermission(playerId, storageId, 'withdraw', {
        kind = 'currency', currency = currencyName, amount = amount
    })
    if not allowed then
        finishStorageTransfer(playerId, storageId, false, permissionReason)
        return
    end

    local Character = getCharacterData(playerId)
    if not Character then
        finishStorageTransfer(playerId, storageId, false, "player_not_loaded")
        return
    end

    exports[Config.MysqlResource]:execute('SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1', {
        ['identifier'] = storageId
    }, function(rows)
        local row = rows and rows[1]
        if not row then
            finishStorageTransfer(playerId, storageId, false, "storage_not_found")
            return
        end
        local storageItems = decodeItems(row.items)
        local foundIndex, foundEntry
        for index, entry in ipairs(storageItems) do
            if entry.item == currencyName then foundIndex, foundEntry = index, entry break end
        end
        if not foundEntry or (tonumber(foundEntry.count) or 0) < amount then
            RecordInventorySecurityViolation(playerId, "storage_currency_not_owned", fingerprint)
            finishStorageTransfer(playerId, storageId, false, "not_enough")
            return
        end

        local originalCount = tonumber(foundEntry.count) or 0
        local remaining = originalCount - amount
        if remaining <= 0 then table.remove(storageItems, foundIndex) else foundEntry.count = remaining end

        -- Persist removal first. A disconnect can lose the transfer, but cannot duplicate it.
        exports[Config.MysqlResource]:execute('UPDATE jrs_inventory_storage SET items=@items WHERE identifier=@identifier', {
            ['items'] = json.encode(storageItems), ['identifier'] = storageId
        }, function(result)
            if not writeSucceeded(result) then
                finishStorageTransfer(playerId, storageId, false, "database_failed")
                return
            end
            local addedOk = changeCharacterCurrency(Character, 'addCurrency', playerId, currencyType, amount)
            if not addedOk then
                -- Best-effort rollback if the core rejected the credit.
                foundEntry.count = originalCount
                local stillPresent = false
                for _, entry in ipairs(storageItems) do
                    if entry == foundEntry then stillPresent = true break end
                end
                if not stillPresent then table.insert(storageItems, foundEntry) end
                exports[Config.MysqlResource]:execute('UPDATE jrs_inventory_storage SET items=@items WHERE identifier=@identifier', {
                    ['items'] = json.encode(storageItems), ['identifier'] = storageId
                })
                finishStorageTransfer(playerId, storageId, false, "currency_add_failed")
                return
            end
            TriggerEvent("jrs_inventory:get_money_sec", playerId)
            local currencyLabel = storageCurrencyLabel(currencyType)
            JRSInventoryLogAction("Currency", currencyLabel .. " Taken From Storage", playerId, {
                amount = amount,
                storage = storageId,
                operationId = operationId or "legacy",
                currency = currencyName,
            })
            emitStorageTransaction(playerId, storageId, 'withdraw', {
                kind = 'currency', currency = currencyName, label = currencyLabel, amount = amount
            })
            finishStorageTransfer(playerId, storageId, true, "ok", storageItems, tonumber(row.size) or 0)
        end)
    end)
end

RegisterNetEvent('jrs_inventory:transfer_money_to_storage')
AddEventHandler('jrs_inventory:transfer_money_to_storage', function(_, count, id, operationId)
    transferCurrencyToStorage(tonumber(source), id, tonumber(count), "money", 0, operationId)
end)

RegisterNetEvent('jrs_inventory:transfer_gold_to_storage')
AddEventHandler('jrs_inventory:transfer_gold_to_storage', function(_, count, id, operationId)
    transferCurrencyToStorage(tonumber(source), id, tonumber(count), "gold", 1, operationId)
end)

RegisterNetEvent('jrs_inventory:transfer_dirtymoney_to_storage')
AddEventHandler('jrs_inventory:transfer_dirtymoney_to_storage', function(_, count, id, operationId)
    transferCurrencyToStorage(tonumber(source), id, tonumber(count), "dirtymoney", 3, operationId)
end)

RegisterNetEvent('jrs_inventory:transfer_money_from_storage')
AddEventHandler('jrs_inventory:transfer_money_from_storage', function(_, count, id, operationId)
    transferCurrencyFromStorage(tonumber(source), id, tonumber(count), "money", 0, operationId)
end)

RegisterNetEvent('jrs_inventory:transfer_gold_from_storage')
AddEventHandler('jrs_inventory:transfer_gold_from_storage', function(_, count, id, operationId)
    transferCurrencyFromStorage(tonumber(source), id, tonumber(count), "gold", 1, operationId)
end)

RegisterNetEvent('jrs_inventory:transfer_dirtymoney_from_storage')
AddEventHandler('jrs_inventory:transfer_dirtymoney_from_storage', function(_, count, id, operationId)
    transferCurrencyFromStorage(tonumber(source), id, tonumber(count), "dirtymoney", 3, operationId)
end)

-- ===========================================================================
-- Weapon transfers
-- ===========================================================================

local function getAvailableWeaponSlot(playerId, callback, preferredSlot)
    local Character, identifier, charId = getCharacterData(playerId)
    if not Character then callback(nil, "player_not_loaded") return end

    exports[Config.MysqlResource]:execute(
        'SELECT name, slot FROM jrs_weaponloadout WHERE identifier=@identifier AND charidentifier=@charidentifier',
        { ['identifier'] = identifier, ['charidentifier'] = charId },
        function(rows)
            local used, count = {}, 0
            for _, row in pairs(rows or {}) do
                if ShouldCountWeaponTowardLimit(row.name) then count = count + 1 end
                if row.slot ~= nil then used[tonumber(row.slot)] = true end
            end
            local maxWeapons = getMaxWeapons(playerId)
            if count >= maxWeapons then
                callback(nil, "full", identifier, charId, count, maxWeapons)
                return
            end
            for _, entry in pairs(inv_table[tonumber(playerId)] or {}) do
                if entry.slot ~= nil then used[tonumber(entry.slot)] = true end
            end
            local preferred = tonumber(preferredSlot)
            if preferred and preferred == math.floor(preferred) and preferred >= 1 and preferred <= 500 and not used[preferred] then
                callback(preferred, nil, identifier, charId, count, maxWeapons)
                return
            end
            local slot = 1
            while used[slot] do slot = slot + 1 end
            callback(slot, nil, identifier, charId, count, maxWeapons)
        end
    )
end

RegisterNetEvent('jrs_inventory:transfer_weapon_to_storage')
AddEventHandler('jrs_inventory:transfer_weapon_to_storage', function(weaponId, claimedName, id, operationId, targetSlot)
    if tostring(id or ''):find('^admin_search:') then return end
    local playerId = tonumber(source)
    weaponId = tonumber(weaponId)
    if WeaponSerialSystemReady ~= true or WeaponSerialSystemAvailable ~= true then
        notifyInventory(playerId, _Up(playerId, 'serial_system_not_ready'))
        TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), false, "serial_system_unavailable")
        return
    end
    local fingerprint = ("weapon_to_storage:%s:%s"):format(tostring(id), tostring(weaponId))
    local started, storageId = beginStorageTransfer(playerId, id, operationId, fingerprint)
    if not started then
        failStorageTransfer(playerId, id, storageId, storageId == "cooldown" and _Up(playerId, 'too_fast') or _Up(playerId, 'transfer_busy'))
        return
    end
    if not weaponId then
        finishStorageTransfer(playerId, storageId, false, "invalid_weapon")
        return
    end

    local allowed, permissionReason = checkExternalStoragePermission(playerId, storageId, 'deposit', {
        kind = 'weapon', weaponId = weaponId, weapon = tostring(claimedName or '')
    })
    if not allowed then
        finishStorageTransfer(playerId, storageId, false, permissionReason)
        return
    end

    local Character, identifier, charId = getCharacterData(playerId)
    if not Character then
        finishStorageTransfer(playerId, storageId, false, "player_not_loaded")
        return
    end

    exports[Config.MysqlResource]:execute(
        'SELECT id,name,used,identifier,charidentifier,serial_number FROM jrs_weaponloadout WHERE id=@id LIMIT 1',
        { ['id'] = weaponId },
        function(weaponRows)
            local weapon = weaponRows and weaponRows[1]
            if not weapon or weapon.identifier ~= identifier or tonumber(weapon.charidentifier) ~= tonumber(charId) then
                RecordInventorySecurityViolation(playerId, "weapon_not_owned", fingerprint)
                notifyInventory(playerId, _Up(playerId, 'dont_own_weapon'))
                finishStorageTransfer(playerId, storageId, false, "not_owned")
                return
            end
            if not NormalizeWeaponSerial(weapon.serial_number) then
                RecordInventorySecurityViolation(playerId, "weapon_missing_serial", fingerprint)
                finishStorageTransfer(playerId, storageId, false, "missing_serial")
                return
            end
            if tonumber(weapon.used) == 1 then
                notifyInventory(playerId, _Up(playerId, 'cant_transfer_equiped_weapon'))
                finishStorageTransfer(playerId, storageId, false, "equipped")
                return
            end
            if Config.IsPersonalItem(weapon.name) then
                notifyInventory(playerId, _Up(playerId, 'personal_item_locked'))
                finishStorageTransfer(playerId, storageId, false, "personal_item")
                return
            end

            exports[Config.MysqlResource]:execute('SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1', {
                ['identifier'] = storageId
            }, function(storageRows)
                local row = storageRows and storageRows[1]
                if not row then
                    finishStorageTransfer(playerId, storageId, false, "storage_not_found")
                    return
                end
                local storageItems = decodeItems(row.items)
                ensureStorageSlots(storageItems)
                if storageWeight(storageItems) + 1.0 > (tonumber(row.size) or 0) + 0.0001 then
                    notifyInventory(playerId, _Up(playerId, 'no_slots'))
                    finishStorageTransfer(playerId, storageId, false, "storage_full")
                    return
                end
                table.insert(storageItems, { item = weaponId, name = weapon.name, weapon = true, serial_number = weapon.serial_number, slot = chooseStorageSlot(storageItems, targetSlot) })

                -- Release ownership first and require exactly one changed row.
                -- A transaction commits even when the conditional UPDATE matches
                -- nothing (weapon equipped/given away in the meantime), which
                -- stored a copy while the player kept the original (dupe).
                -- Order prefers loss over duplication if the server dies mid-way.
                local mysql = exports[Config.MysqlResource]
                mysql:execute(
                    "UPDATE jrs_weaponloadout SET identifier='', charidentifier=0, used=0 WHERE id=? AND identifier=? AND charidentifier=? AND used=0 AND serial_number=?",
                    { weaponId, identifier, charId, weapon.serial_number },
                    function(released)
                    if not writeSucceeded(released) then
                        RecordInventorySecurityViolation(playerId, "weapon_release_failed", fingerprint)
                        finishStorageTransfer(playerId, storageId, false, "ownership_failed")
                        return
                    end
                    mysql:execute('UPDATE jrs_inventory_storage SET items=? WHERE identifier=?', { json.encode(storageItems), storageId }, function(stored)
                    if not writeSucceeded(stored) then
                        mysql:execute("UPDATE jrs_weaponloadout SET identifier=?, charidentifier=? WHERE id=? AND identifier='' AND charidentifier=0",
                            { identifier, charId, weaponId })
                        finishStorageTransfer(playerId, storageId, false, "database_failed")
                        return
                    end
                    -- Drop it from the cached list and push the bag right away so
                    -- the weapon leaves the bag together with the storage refresh,
                    -- instead of showing in both until the DB reload lands.
                    local cachedWeapons = weapon_table and weapon_table[playerId]
                    if type(cachedWeapons) == "table" then
                        for index = #cachedWeapons, 1, -1 do
                            if tonumber(cachedWeapons[index].id) == weaponId then table.remove(cachedWeapons, index) end
                        end
                        updateItemsInventory(playerId)
                    end
                    TriggerEvent("jrs_inventory:get_items_sec", playerId)
                    local label = (weaponTableForData[weapon.name] and weaponTableForData[weapon.name].label) or weapon.name
                    JRSInventoryLogAction("Storage", "Weapon Moved To Storage", playerId, {
                        weapon = label .. " (`" .. tostring(weapon.name) .. "`)",
                        weaponId = weaponId,
                        serial = weapon.serial_number or 'N/A',
                        storage = storageId,
                        operationId = operationId or "legacy",
                    })
                    emitStorageTransaction(playerId, storageId, 'deposit', {
                        kind = 'weapon', weapon = weapon.name, label = label, amount = 1,
                        weaponId = weaponId, serial = weapon.serial_number or 'N/A'
                    })
                    finishStorageTransfer(playerId, storageId, true, "ok", storageItems, tonumber(row.size) or 0)
                    end)
                    end
                )
            end)
        end
    )
end)

RegisterNetEvent('jrs_inventory:transfer_weapon_from_storage')
AddEventHandler('jrs_inventory:transfer_weapon_from_storage', function(weaponId, id, operationId, targetInventorySlot)
    if tostring(id or ''):find('^admin_search:') then return end
    local playerId = tonumber(source)
    weaponId = tonumber(weaponId)
    if WeaponSerialSystemReady ~= true or WeaponSerialSystemAvailable ~= true then
        notifyInventory(playerId, _Up(playerId, 'serial_system_not_ready'))
        TriggerClientEvent('jrs_inventory:storageTransferResult', tonumber(playerId), false, "serial_system_unavailable")
        return
    end
    local fingerprint = ("weapon_from_storage:%s:%s"):format(tostring(id), tostring(weaponId))
    local started, storageId = beginStorageTransfer(playerId, id, operationId, fingerprint)
    if not started then
        failStorageTransfer(playerId, id, storageId, storageId == "cooldown" and _Up(playerId, 'too_fast') or _Up(playerId, 'transfer_busy'))
        return
    end
    if not weaponId then
        finishStorageTransfer(playerId, storageId, false, "invalid_weapon")
        return
    end

    local allowed, permissionReason = checkExternalStoragePermission(playerId, storageId, 'withdraw', {
        kind = 'weapon', weaponId = weaponId
    })
    if not allowed then
        finishStorageTransfer(playerId, storageId, false, permissionReason)
        return
    end

    exports[Config.MysqlResource]:execute('SELECT items,size FROM jrs_inventory_storage WHERE identifier=@identifier LIMIT 1', {
        ['identifier'] = storageId
    }, function(storageRows)
        local row = storageRows and storageRows[1]
        if not row then
            finishStorageTransfer(playerId, storageId, false, "storage_not_found")
            return
        end
        local storageItems = decodeItems(row.items)
        ensureStorageSlots(storageItems)
        local foundIndex, foundWeapon
        for index, entry in ipairs(storageItems) do
            if tonumber(entry.item) == weaponId and (entry.name ~= nil or entry.weapon == true) then
                foundIndex, foundWeapon = index, entry
                break
            end
        end
        if not foundWeapon then
            RecordInventorySecurityViolation(playerId, "storage_weapon_not_owned", fingerprint)
            finishStorageTransfer(playerId, storageId, false, "not_owned")
            return
        end

        getAvailableWeaponSlot(playerId, function(slot, reason, identifier, charId)
            if not slot then
                if reason == "full" then notifyInventory(playerId, _Up(playerId, 'cant_hold_more_weapons')) end
                finishStorageTransfer(playerId, storageId, false, reason or "failed")
                return
            end

            exports[Config.MysqlResource]:execute(
                "SELECT id,name,identifier,charidentifier,serial_number FROM jrs_weaponloadout WHERE id=@id LIMIT 1",
                { ['id'] = weaponId },
                function(weaponRows)
                    local weapon = weaponRows and weaponRows[1]
                    if not weapon or tostring(weapon.identifier or "") ~= "" or tonumber(weapon.charidentifier) ~= 0 then
                        RecordInventorySecurityViolation(playerId, "storage_weapon_invalid_owner", fingerprint)
                        finishStorageTransfer(playerId, storageId, false, "ownership_failed")
                        return
                    end

                    local storedSerial = NormalizeWeaponSerial(foundWeapon and foundWeapon.serial_number)
                    local databaseSerial = NormalizeWeaponSerial(weapon.serial_number)
                    if not databaseSerial then
                        RecordInventorySecurityViolation(playerId, "storage_weapon_missing_serial", fingerprint)
                        finishStorageTransfer(playerId, storageId, false, "missing_serial")
                        return
                    end
                    if storedSerial and storedSerial ~= databaseSerial then
                        RecordInventorySecurityViolation(playerId, "storage_weapon_serial_mismatch", fingerprint .. ":" .. storedSerial .. ":" .. databaseSerial)
                        finishStorageTransfer(playerId, storageId, false, "serial_mismatch")
                        return
                    end

                    table.remove(storageItems, foundIndex)
                    -- Remove the chest reference first, then claim ownership and
                    -- require exactly one changed row. If the claim matches nothing
                    -- the reference is put back; a crash in between loses the
                    -- weapon instead of duplicating it.
                    local mysql = exports[Config.MysqlResource]
                    mysql:execute('UPDATE jrs_inventory_storage SET items=? WHERE identifier=?', { json.encode(storageItems), storageId }, function(stored)
                    if not writeSucceeded(stored) then
                        finishStorageTransfer(playerId, storageId, false, "database_failed")
                        return
                    end
                    mysql:execute(
                        "UPDATE jrs_weaponloadout SET identifier=?, charidentifier=?, slot=?, used=0 WHERE id=? AND identifier='' AND charidentifier=0 AND serial_number=?",
                        { identifier, charId, slot, weaponId, weapon.serial_number },
                        function(claimed)
                        if not writeSucceeded(claimed) then
                            table.insert(storageItems, foundIndex, foundWeapon)
                            mysql:execute('UPDATE jrs_inventory_storage SET items=? WHERE identifier=?', { json.encode(storageItems), storageId })
                            RecordInventorySecurityViolation(playerId, "storage_weapon_claim_failed", fingerprint)
                            finishStorageTransfer(playerId, storageId, false, "ownership_failed")
                            return
                        end
                        TriggerEvent("jrs_inventory:get_items_sec", playerId)
                        local weaponName = tostring((weapon and weapon.name) or (foundWeapon and foundWeapon.name) or "unknown")
                        local label = (weaponTableForData[weaponName] and weaponTableForData[weaponName].label) or weaponName
                        local serial = weapon.serial_number or (foundWeapon and foundWeapon.serial_number) or 'N/A'
                        JRSInventoryLogAction("Storage", "Weapon Taken From Storage", playerId, {
                            weapon = label .. " (`" .. weaponName .. "`)",
                            weaponId = weaponId,
                            serial = serial,
                            storage = storageId,
                            operationId = operationId or "legacy",
                        })
                        emitStorageTransaction(playerId, storageId, 'withdraw', {
                            kind = 'weapon', weapon = weaponName, label = label, amount = 1,
                            weaponId = weaponId, serial = serial
                        })
                        finishStorageTransfer(playerId, storageId, true, "ok", storageItems, tonumber(row.size) or 0)
                        end
                    )
                    end)
                end
            )
        end, targetInventorySlot)
    end)
end)
