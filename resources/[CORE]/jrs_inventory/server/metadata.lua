-- ===========================================================================
-- Metadata System
-- Server-authoritative item metadata with validation, defaults and durability.
-- Metadata lives on the exact inventory entry (itemId) and is persisted inside
-- characters.inventory JSON. The items.metadata DB column is treated only as a
-- default metadata template for newly created / migrated item instances.
-- ===========================================================================

local function cfg()
    return Config.Metadata or {}
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

local function clampNumber(value, minimum, maximum)
    value = tonumber(value)
    if value == nil or value ~= value then return nil end
    if minimum ~= nil and value < minimum then value = minimum end
    if maximum ~= nil and value > maximum then value = maximum end
    return value
end

local function sanitizeValue(value, depth, state)
    local valueType = type(value)
    local settings = cfg()
    local maxDepth = math.max(1, tonumber(settings.MaxDepth) or 5)
    local maxKeys = math.max(1, tonumber(settings.MaxKeys) or 32)
    local maxStringLength = math.max(1, tonumber(settings.MaxStringLength) or 256)

    if valueType == "nil" then return nil end
    if valueType == "boolean" then return value end
    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if valueType == "string" then
        if #value > maxStringLength then
            return string.sub(value, 1, maxStringLength)
        end
        return value
    end
    if valueType ~= "table" then return nil end
    if depth >= maxDepth then return {} end

    state = state or { seen = {}, keys = 0 }
    if state.seen[value] then return {} end
    state.seen[value] = true

    local output = {}
    for key, child in pairs(value) do
        if state.keys >= maxKeys then break end
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local cleanKey = key
            if keyType == "string" then
                cleanKey = string.sub(key, 1, 64)
            end
            local cleanValue = sanitizeValue(child, depth + 1, state)
            if cleanValue ~= nil then
                output[cleanKey] = cleanValue
                state.keys = state.keys + 1
            end
        end
    end

    state.seen[value] = nil
    return output
end

local function safeDecodeMetadata(raw)
    if raw == nil or raw == false or raw == 0 then return {} end
    if type(raw) == "table" then return deepCopy(raw) end
    if type(raw) ~= "string" then return {} end

    local text = tostring(raw)
    if text == "" or text == "0" or text == "null" or text == "NULL" then return {} end

    local first = string.sub(text, 1, 1)
    if first ~= "{" and first ~= "[" then return {} end

    local ok, decoded = pcall(json.decode, text)
    if not ok or type(decoded) ~= "table" then return {} end
    return decoded
end

local function mergeTables(base, extra)
    local result = deepCopy(base or {})
    for key, value in pairs(extra or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = mergeTables(result[key], value)
        else
            result[key] = deepCopy(value)
        end
    end
    return result
end

local function normalizeDurability(metadata)
    if type(metadata) ~= "table" then return metadata end
    if metadata.durability == nil then return metadata end

    local settings = cfg()
    local minimum = tonumber(settings.DurabilityMin) or 0
    local maximum = tonumber(settings.DurabilityMax) or 100
    local durability = clampNumber(metadata.durability, minimum, maximum)
    if durability == nil then
        metadata.durability = nil
    else
        metadata.durability = math.floor(durability * 100 + 0.5) / 100
    end
    return metadata
end

function JRSInventoryGetDefaultMetadata(itemName)
    itemName = tostring(itemName or "")
    if itemName == "" then return {} end

    local defaults = {}
    local settings = cfg()

    if settings.ApplyDatabaseDefaults ~= false then
        local itemDefinition = itemTableForData and itemTableForData[itemName]
        if itemDefinition ~= nil then
            defaults = mergeTables(defaults, safeDecodeMetadata(itemDefinition.metadata))
        end
    end

    -- Apply metadata defaults for the item's database category.
    -- Example: every item with category=equipment receives durability=100.
    if type(settings.CategoryDefaults) == "table" then
        local itemDefinition = itemTableForData and itemTableForData[itemName]
        local category = itemDefinition and string.lower(tostring(itemDefinition.category or "")) or ""
        category = category:gsub("^%s+", ""):gsub("%s+$", "")
        if category ~= "" then
            local categoryDefaults = settings.CategoryDefaults[category]
            if type(categoryDefaults) == "table" then
                defaults = mergeTables(defaults, categoryDefaults)
            end
        end
    end

    if type(settings.ItemDefaults) == "table" then
        local configured = settings.ItemDefaults[itemName] or settings.ItemDefaults[string.lower(itemName)]
        if type(configured) == "table" then
            defaults = mergeTables(defaults, configured)
        end
    end

    defaults = sanitizeValue(defaults, 0, { seen = {}, keys = 0 }) or {}
    return normalizeDurability(defaults)
end

function JRSInventoryNormalizeMetadata(metadata, itemName, applyDefaults)
    local settings = cfg()
    if settings.Enabled == false then
        return type(metadata) == "table" and deepCopy(metadata) or {}
    end

    local clean = safeDecodeMetadata(metadata)
    clean = sanitizeValue(clean, 0, { seen = {}, keys = 0 }) or {}

    if applyDefaults ~= false then
        clean = mergeTables(JRSInventoryGetDefaultMetadata(itemName), clean)
    end

    clean = normalizeDurability(clean)

    local maxEncodedLength = math.max(128, tonumber(settings.MaxEncodedLength) or 2048)
    local ok, encoded = pcall(json.encode, clean)
    if not ok then return {} end
    if #encoded > maxEncodedLength then
        -- Reject oversized metadata rather than allowing arbitrary payload growth.
        return JRSInventoryGetDefaultMetadata(itemName)
    end

    return clean
end

local function metadataEqualRecursive(first, second, seen)
    if first == second then return true end
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return false end

    seen = seen or {}
    if seen[first] == second then return true end
    seen[first] = second

    for key, value in pairs(first) do
        if not metadataEqualRecursive(value, second[key], seen) then return false end
    end
    for key in pairs(second) do
        if first[key] == nil then return false end
    end
    return true
end

function JRSInventoryMetadataEqual(first, second)
    local a = JRSInventoryNormalizeMetadata(first, nil, false)
    local b = JRSInventoryNormalizeMetadata(second, nil, false)
    return metadataEqualRecursive(a, b)
end

function JRSInventoryMetadataRequiresUniqueInstance(itemName, metadata)
    local settings = cfg()
    metadata = JRSInventoryNormalizeMetadata(metadata, itemName, false)

    if metadata.stackable == false or metadata.unique == true then return true end

    local uniqueKeys = settings.UniqueKeys
    if type(uniqueKeys) ~= "table" then
        uniqueKeys = { "durability", "serial_number", "instance_id", "instanceId" }
    end
    for _, key in ipairs(uniqueKeys) do
        if metadata[key] ~= nil then return true end
    end
    return false
end

function JRSInventoryCreateUniqueItemId()
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

local function getItemEntry(playerId, itemId)
    playerId = tonumber(playerId)
    itemId = tonumber(itemId)
    if not playerId or not itemId then return nil end
    for index, entry in pairs(inv_table[playerId] or {}) do
        if tonumber(entry.itemId) == itemId then
            return entry, index
        end
    end
    return nil
end

function JRSInventoryGetMetadata(playerId, itemId)
    local entry = getItemEntry(playerId, itemId)
    if not entry then return nil end
    entry.metaData = JRSInventoryNormalizeMetadata(entry.metaData, entry.item, false)
    return deepCopy(entry.metaData)
end

local function splitStackForUniqueMutation(playerId, entry, metadataBefore)
    local count = math.max(1, math.floor(tonumber(entry.count) or 1))
    if count <= 1 then return end

    entry.count = 1
    for _ = 2, count do
        local clone = {
            itemId = JRSInventoryCreateUniqueItemId(),
            item = entry.item,
            label = entry.label,
            count = 1,
            metaData = deepCopy(metadataBefore or {}),
            slot = type(GetFreeSlot) == "function" and GetFreeSlot(playerId) or (#(inv_table[playerId] or {}) + 1),
        }
        table.insert(inv_table[playerId], clone)
    end
end

local function persistMetadataChange(playerId, entry, actionTitle, previousMetadata)
    playerId = tonumber(playerId)
    if not playerId or not entry then return end
    if type(SaveInventoryNow) == "function" then SaveInventoryNow(playerId) end
    if type(updateItemsInventory) == "function" then updateItemsInventory(playerId) end

    if cfg().LogChanges == true and type(JRSInventoryLogAction) == "function" then
        local itemName = tostring(entry.item or "unknown")
        local itemLabel = ItemLabelFor(playerId, itemName)
        JRSInventoryLogAction("Items", actionTitle or "Item Metadata Updated", playerId, {
            item = itemLabel .. " (`" .. itemName .. "`)",
            itemId = entry.itemId,
            metadata = entry.metaData or {},
            previousMetadata = previousMetadata or {},
            sourceResource = GetInvokingResource() or "server",
        })
    end
end

function JRSInventorySetMetadata(playerId, itemId, metadata, replace)
    local entry = getItemEntry(playerId, itemId)
    if not entry then return false, "not_found" end

    local previous = JRSInventoryNormalizeMetadata(entry.metaData, entry.item, false)
    local incoming = JRSInventoryNormalizeMetadata(metadata, entry.item, false)
    local nextMetadata
    if replace == true then
        nextMetadata = JRSInventoryNormalizeMetadata(incoming, entry.item, true)
    else
        nextMetadata = JRSInventoryNormalizeMetadata(mergeTables(previous, incoming), entry.item, true)
    end

    if JRSInventoryMetadataRequiresUniqueInstance(entry.item, nextMetadata) then
        splitStackForUniqueMutation(tonumber(playerId), entry, previous)
    end
    entry.metaData = nextMetadata
    persistMetadataChange(playerId, entry, "Item Metadata Updated", previous)
    return true, deepCopy(nextMetadata)
end

function JRSInventorySetMetadataValue(playerId, itemId, key, value)
    key = tostring(key or "")
    if key == "" or #key > 64 then return false, "invalid_key" end

    local entry = getItemEntry(playerId, itemId)
    if not entry then return false, "not_found" end

    local previous = JRSInventoryNormalizeMetadata(entry.metaData, entry.item, false)
    local nextMetadata = deepCopy(previous)
    nextMetadata[key] = value
    nextMetadata = JRSInventoryNormalizeMetadata(nextMetadata, entry.item, true)
    if JRSInventoryMetadataRequiresUniqueInstance(entry.item, nextMetadata) then
        splitStackForUniqueMutation(tonumber(playerId), entry, previous)
    end
    entry.metaData = nextMetadata
    persistMetadataChange(playerId, entry, "Item Metadata Value Updated", previous)
    return true, deepCopy(nextMetadata)
end

function JRSInventoryRemoveMetadataValue(playerId, itemId, key)
    key = tostring(key or "")
    if key == "" then return false, "invalid_key" end

    local entry = getItemEntry(playerId, itemId)
    if not entry then return false, "not_found" end

    local previous = JRSInventoryNormalizeMetadata(entry.metaData, entry.item, true)
    local nextMetadata = deepCopy(previous)
    nextMetadata[key] = nil
    nextMetadata = JRSInventoryNormalizeMetadata(nextMetadata, entry.item, false)
    entry.metaData = nextMetadata
    persistMetadataChange(playerId, entry, "Item Metadata Value Removed", previous)
    return true, deepCopy(nextMetadata)
end

function JRSInventoryIsItemBroken(itemName, metadata)
    local settings = cfg()
    if settings.Enabled == false or settings.PreventUseWhenBroken == false then
        return false, nil
    end

    local clean = JRSInventoryNormalizeMetadata(metadata, itemName, false)
    local durability = tonumber(clean and clean.durability)

    -- Items without durability metadata are not treated as broken.
    if durability == nil then
        return false, nil
    end

    return durability <= 0, durability
end

function JRSInventorySetDurability(playerId, itemId, durability)
    local settings = cfg()
    local minimum = tonumber(settings.DurabilityMin) or 0
    local maximum = tonumber(settings.DurabilityMax) or 100
    durability = clampNumber(durability, minimum, maximum)
    if durability == nil then return false, "invalid_durability" end
    return JRSInventorySetMetadataValue(playerId, itemId, "durability", durability)
end

function JRSInventoryDamageItem(playerId, itemId, amount)
    amount = tonumber(amount)
    if not amount or amount < 0 then return false, "invalid_amount" end

    local entry = getItemEntry(playerId, itemId)
    if not entry then return false, "not_found" end

    local metadata = JRSInventoryNormalizeMetadata(entry.metaData, entry.item, false)
    local current = tonumber(metadata.durability)
    if current == nil then
        current = tonumber(cfg().DefaultDurability) or 100
    end

    local nextValue = current - amount
    local success, result = JRSInventorySetDurability(playerId, itemId, nextValue)
    if not success then return false, result end
    return true, tonumber(result.durability) or 0, (tonumber(result.durability) or 0) <= 0
end

function JRSInventoryRepairItem(playerId, itemId, amount)
    local entry = getItemEntry(playerId, itemId)
    if not entry then return false, "not_found" end

    local metadata = JRSInventoryNormalizeMetadata(entry.metaData, entry.item, false)
    local current = tonumber(metadata.durability)
    if current == nil then current = tonumber(cfg().DefaultDurability) or 100 end

    if amount == nil then
        amount = (tonumber(cfg().DurabilityMax) or 100) - current
    end
    amount = tonumber(amount)
    if not amount or amount < 0 then return false, "invalid_amount" end

    local success, result = JRSInventorySetDurability(playerId, itemId, current + amount)
    if not success then return false, result end
    return true, tonumber(result.durability) or 0
end

-- Normalizes the current metaData schema and splits durability/unique metadata
-- stacks so each instance has its own itemId.
function JRSInventoryNormalizeLoadedInventory(playerId)
    playerId = tonumber(playerId)
    if not playerId then return false end
    inv_table[playerId] = type(inv_table[playerId]) == "table" and inv_table[playerId] or {}

    local changed = false
    local additions = {}
    local pendingIds = {}

    local function newUniqueId()
        local candidate
        repeat candidate = JRSInventoryCreateUniqueItemId() until not pendingIds[candidate]
        pendingIds[candidate] = true
        return candidate
    end

    for _, entry in ipairs(inv_table[playerId]) do
        local beforeOk, before = pcall(json.encode, entry.metaData or {})
        entry.metaData = JRSInventoryNormalizeMetadata(entry.metaData, entry.item, true)
        local afterOk, after = pcall(json.encode, entry.metaData or {})
        if not beforeOk or not afterOk or before ~= after then changed = true end

        local count = math.max(1, math.floor(tonumber(entry.count) or 1))
        if JRSInventoryMetadataRequiresUniqueInstance(entry.item, entry.metaData) and count > 1 then
            entry.count = 1
            changed = true
            for _ = 2, count do
                additions[#additions + 1] = {
                    itemId = newUniqueId(),
                    item = entry.item,
                    label = entry.label,
                    count = 1,
                    metaData = deepCopy(entry.metaData),
                    slot = nil,
                }
            end
        end
    end

    for _, entry in ipairs(additions) do
        entry.slot = type(GetFreeSlot) == "function" and GetFreeSlot(playerId) or (#inv_table[playerId] + 1)
        table.insert(inv_table[playerId], entry)
    end

    return changed
end
