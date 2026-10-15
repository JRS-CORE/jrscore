local function isCallable(fn)
    if fn == nil then return false end
    local t = type(fn)
    if t == 'function' or t == 'userdata' then return true end
    if t == 'table' then
        local mt = getmetatable(fn)
        if mt and mt.__call then return true end
        if rawget(fn, '__cfx_functionReference') ~= nil then return true end
    end
    return false
end

-- See server/main.lua for why this re-resolves getCoreApi() on every access
-- instead of caching it once: jrs_core rebuilds its funcref table per call, so
-- a stale cache here would survive a jrs_core restart as dead references.
local function getCoreApiSafe()
    local resource = tostring((Config and Config.CoreResource) or 'jrs_core')
    local ok, api = pcall(function()
        return exports[resource]:getCoreApi()
    end)
    if ok and type(api) == 'table' then
        return api
    end
    return nil
end

-- Compatibility resolver for ALL supported jrs_core revisions.
-- Newer cores expose GetUser/getUser directly. Older cores may only expose
-- GetCharacter + GetGroup, while some builds return a getCoreApi() table that
-- simply does not contain getUser. Inventory only needs getUsedCharacter and
-- group from the user object, so we can construct the same minimal facade
-- without failing inventory load or spamming "no such API method".
local function getCoreUser(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil end

    local resource = tostring((Config and Config.CoreResource) or 'jrs_core')

    -- 1) Preferred stable exports (newer jrs_core).
    local ok, user = pcall(function()
        return exports[resource]:GetUser(source)
    end)
    if ok then
        return user
    end

    ok, user = pcall(function()
        return exports[resource]:getUser(source)
    end)
    if ok then
        return user
    end

    -- 2) Unified API (works on builds where getUser is actually registered).
    local api = getCoreApiSafe()
    if api then
        local getter = api.getUser or api.GetUser
        if isCallable(getter) then
            local okGetter, apiUser = pcall(getter, source)
            if okGetter then
                return apiUser
            end
        end
    end

    -- 3) Old-core compatibility: recreate the only parts of the user object
    -- jrs_inventory consumes: getUsedCharacter and group.
    local character = nil
    local group = nil

    local okCharacter, directCharacter = pcall(function()
        return exports[resource]:GetCharacter(source)
    end)
    if okCharacter then
        character = directCharacter
    elseif api then
        local getCharacter = api.GetCharacter or api.getCharacter
        if isCallable(getCharacter) then
            local okApiCharacter, apiCharacter = pcall(getCharacter, source)
            if okApiCharacter then character = apiCharacter end
        end
    end

    local okGroup, directGroup = pcall(function()
        return exports[resource]:GetGroup(source)
    end)
    if okGroup then
        group = directGroup
    elseif api then
        local getGroup = api.GetGroup or api.getGroup
        if isCallable(getGroup) then
            local okApiGroup, apiGroup = pcall(getGroup, source)
            if okApiGroup then group = apiGroup end
        end
    end

    if character ~= nil or group ~= nil then
        return {
            getUsedCharacter = character,
            group = group,
        }
    end

    -- Character may simply not be selected/ready yet. Returning nil here is
    -- expected and must NOT be treated as a missing API method.
    return nil
end

JRSInventoryGetCoreApi = getCoreApiSafe
JRSInventoryGetCoreUser = getCoreUser


local Inventory = {}
JRSInventoryAPI = Inventory
JRSInventoryInternalAPI = Inventory -- internal API for integrated jrs_inventory modules

local function resolveCallingResource(context)
    if type(context) == "table" and context.sourceResource then
        return tostring(context.sourceResource)
    end
    if type(context) == "string" and context ~= "" then
        return context
    end
    return GetInvokingResource() or "server"
end

-----------------------------------------------------------------------
-- [[  (Utility Functions) ]]
-----------------------------------------------------------------------

local function queryAsync(query, params)
    local p = promise.new()
    exports[Config.MysqlResource]:execute(query, params or {}, function(result)
        p:resolve(result or {})
    end)
    return Citizen.Await(p)
end


-----------------------------------------------------------------------
-- [[ (Main Exports) ]]
-----------------------------------------------------------------------

exports('jrs_inventoryApi', function()
    return Inventory
end)

-----------------------------------------------------------------------
-- [[  (Database & Preload) ]]
-----------------------------------------------------------------------

Inventory.getItemNames = function()
    local result = queryAsync('SELECT * FROM jrs_items')
    return result
end
exports('getItemNames', Inventory.getItemNames)


Inventory.preload_itemtable = function()
    local result = queryAsync('SELECT * FROM jrs_items')
    return result
end
exports('preload_itemtable', Inventory.preload_itemtable)


Inventory.preload_weapontable = function()
    return RECORDSW or {}
end

exports('preload_weapontable', Inventory.preload_weapontable)


Inventory.check_itemtable = function()
    local result = queryAsync('SELECT * FROM jrs_items')
    return result
end
exports('check_itemtable', Inventory.check_itemtable)


-- Refresh the actual caches used by AddInventoryItemDirect and client payloads.
Inventory.reloadItemTable = function()
    local result = nil
    if MySQL and MySQL.query and MySQL.query.await then
        result = MySQL.query.await('SELECT * FROM jrs_items')
    else
        local p = promise.new()
        exports[Config.MysqlResource]:execute('SELECT * FROM jrs_items', {}, function(rows)
            p:resolve(rows or {})
        end)
        result = Citizen.Await(p)
    end

    if type(result) ~= 'table' or next(result) == nil then
        return false
    end
    local definitions = {}
    local definitionsLower = {}
    for _, row in pairs(result) do
        local isUsable = (row.usable == 1 or row.usable == true)
        if not isUsable and usableItemsFunctions and (usableItemsFunctions[row.item] or (type(row.item) == 'string' and usableItemsFunctions[row.item:lower()])) then
            isUsable = true
        end
        local def = {
            item = row.item,
            label = row.label or row.item,
            label_ar = row.label_ar or row.label,
            limit = tonumber(row.limit) or 0.1,
            can_remove = row.can_remove,
            type = row.type or "item_standard",
            usable = isUsable and 1 or 0,
            descriptions = row.descriptions,
            descriptions_ar = row.descriptions_ar,
            metadata = row.metadata,
            category = row.category
        }
        definitions[row.item] = def
        definitionsLower[row.item:lower()] = def
    end
    table_item = result
    itemTableForData = definitions
    itemTableForDataLower = definitionsLower
    if type(ensureOutfitItemDefinition) == 'function' then ensureOutfitItemDefinition() end
    clientDefinitionsSent = {}
    return true
end
exports('reloadItemTable', Inventory.reloadItemTable)

-----------------------------------------------------------------------
-- [[ (Items Actions) ]]
-----------------------------------------------------------------------


Inventory.getItemLabel = function(itemName)
    local result = queryAsync('SELECT label FROM jrs_items WHERE item = @item LIMIT 1', {['@item'] = itemName})

    if result and result[1] then
        return result[1].label
    else
        return itemName
    end
end
exports('getItemLabel', Inventory.getItemLabel)


Inventory.addItem = function(source, itemName, count, metaData, context)
    local sourceResource = resolveCallingResource(context)
    if type(JRSInventoryAddItemSync) == "function" then
        return JRSInventoryAddItemSync(source, tostring(itemName), tonumber(count), metaData, sourceResource)
    end
    return false, "inventory_not_ready", {}
end
exports('addItem', Inventory.addItem)


Inventory.subItem = function(source, itemName, count, context)
    local sourceResource = resolveCallingResource(context)
    if type(JRSInventorySubItemSync) == "function" then
        return JRSInventorySubItemSync(source, tostring(itemName), tonumber(count), sourceResource)
    end
    return false, "inventory_not_ready", {}
end
exports('subItem', Inventory.subItem)


Inventory.subItemByID = function(source, itemId, count, context)
    local completed, success, reason, data = false, false, "not_processed", {}
    local sourceResource = resolveCallingResource(context)
    TriggerEvent("jrsCore:subItemByID", source, tostring(itemId), count, function(ok, why, details)
        completed = true
        success = ok == true
        reason = why
        data = type(details) == "table" and details or {}
    end, sourceResource)
    if completed then return success, reason, data end

    if type(RemoveInventoryItemByIdDirect) == "function" then
        local removed, removeReason = RemoveInventoryItemByIdDirect(source, tonumber(itemId), tonumber(count))
        if removed then
            if type(SaveInventoryNow) == "function" then SaveInventoryNow(source) end
            if type(updateItemsInventory) == "function" then updateItemsInventory(source) end
            return true, "success", { itemId = tonumber(itemId), amount = tonumber(count) }
        end
        return false, removeReason or "remove_failed", { itemId = tonumber(itemId), amount = tonumber(count) }
    end
    return false, "not_processed", {}
end
exports('subItemByID', Inventory.subItemByID)


-- The handler answers with the total across every stack of `item` (see
-- jrsCore:getItemCount in server/main.lua). Coerce defensively so a caller can
-- never receive nil where it expects a number to compare against.
Inventory.getItemCount = function(source, item)
    local count = 0
    TriggerEvent("jrsCore:getItemCount", source, item, function(itemcount)
        count = tonumber(itemcount) or 0
    end, tostring(item))
    return count
end
exports('getItemCount', Inventory.getItemCount)


Inventory.canCarryItem = function(source, name, amount)
    local can
    TriggerEvent("jrsCore:canCarryItem", source, name, amount, function(data)
        can = data
    end)
    return can
end
exports('canCarryItem', Inventory.canCarryItem)

Inventory.getCarryInfo = function(source, name, amount)
    local info
    TriggerEvent("jrsCore:getCarryInfo", source, name, amount, function(data)
        info = data
    end)
    if type(info) == 'table' then
        return info
    end
    local canCarry = Inventory.canCarryItem(source, name, amount)
    return {
        canCarry = canCarry == true,
        reason = canCarry and 'ok' or 'overweight',
        currentWeight = 0,
        addedWeight = 0,
        maxWeight = 0
    }
end
exports('getCarryInfo', Inventory.getCarryInfo)

-- Checks the per-item ownership cap (Config.MaxOwnedItems) without granting
-- anything. Returns true when the item has no configured cap.
Inventory.canAcquireItem = function(source, name, amount)
    local can
    TriggerEvent("jrsCore:canAcquireItem", source, name, amount, function(data)
        can = data
    end)
    return can
end
exports('canAcquireItem', Inventory.canAcquireItem)

-----------------------------------------------------------------------
-- [[ (Weapons API) ]]
-----------------------------------------------------------------------

Inventory.getWeaponsMe = function(source)
    local User = getCoreUser(source)
    local Character = User and User.getUsedCharacter
    if not Character then return {} end

    local result = queryAsync('SELECT * FROM jrs_weaponloadout WHERE charidentifier = @charidentifier', {['charidentifier'] = Character.charIdentifier})
    return result
end

exports('getWeaponsMe', Inventory.getWeaponsMe)


Inventory.GetWeaponTable = function()
    return RECORDSW or {}
end
exports('GetWeaponTable', Inventory.GetWeaponTable)

Inventory.createWeapon = function(source, weaponName, ammoaux, compaux, context)
    TriggerEvent("jrsCore:registerWeapon", source, tostring(weaponName), ammoaux, compaux, resolveCallingResource(context))
    return true
end
exports('createWeapon', Inventory.createWeapon)

Inventory.subWeapon = function(source, weaponid, callback, context)
    local sourceResource = resolveCallingResource(context)
    TriggerEvent("jrsCore:subWeapon", source, tonumber(weaponid), callback, sourceResource)
    return true
end
exports('subWeapon', Inventory.subWeapon)

Inventory.giveWeapon = function(source, weaponid, target)
    TriggerEvent("jrsCore:giveWeapon", source, weaponid, target)
end
exports('giveWeapon', Inventory.giveWeapon)

-----------------------------------------------------------------------
-- [[ (Metadata & Inventory) ]]
-----------------------------------------------------------------------


Inventory.getUserInventory = function(source)
    local inv
    TriggerEvent("jrsCore:getUserInventory", source, function(invent)
        inv = invent
    end)
    return inv
end


exports('getUserInventory', Inventory.getUserInventory)
exports('getUserInventoryItems', Inventory.getUserInventory)

Inventory.getItemById = function(source, itemId)
    local _source = tonumber(source)
    local _itemId = tonumber(itemId)
    if not _source or not _itemId then return nil end
    local inv = inv_table and inv_table[_source]
    if type(inv) == "table" then
        for _, item in pairs(inv) do
            if tonumber(item.itemId or item.id or item.mainid) == _itemId then
                return item
            end
        end
    end
    return nil
end
exports('getItemById', Inventory.getItemById)

Inventory.getMetaTypeById = function(source, id, value)
    TriggerEvent("jrsCore:getMetadataValue", source, id, value, function(data)
        id = data
    end)
    return id
end
exports('getMetaTypeById', Inventory.getMetaTypeById)

-- Return the full metadata table for one exact inventory itemId.
Inventory.getMetadata = function(source, itemId)
    if type(JRSInventoryGetMetadata) ~= "function" then return nil end
    return JRSInventoryGetMetadata(tonumber(source), tonumber(itemId))
end
exports('getMetadata', Inventory.getMetadata)

-- Merge metadata into an item. Pass replace=true to replace the table instead.
Inventory.setMetadata = function(source, itemId, metadata, replace)
    if type(JRSInventorySetMetadata) ~= "function" then return false, "metadata_not_ready" end
    return JRSInventorySetMetadata(tonumber(source), tonumber(itemId), metadata, replace == true)
end
exports('setMetadata', Inventory.setMetadata)

Inventory.setMetadataValue = function(source, itemId, key, value)
    if type(JRSInventorySetMetadataValue) ~= "function" then return false, "metadata_not_ready" end
    return JRSInventorySetMetadataValue(tonumber(source), tonumber(itemId), key, value)
end
exports('setMetadataValue', Inventory.setMetadataValue)

Inventory.removeMetadataValue = function(source, itemId, key)
    if type(JRSInventoryRemoveMetadataValue) ~= "function" then return false, "metadata_not_ready" end
    return JRSInventoryRemoveMetadataValue(tonumber(source), tonumber(itemId), key)
end
exports('removeMetadataValue', Inventory.removeMetadataValue)

Inventory.setDurability = function(source, itemId, durability)
    if type(JRSInventorySetDurability) ~= "function" then return false, "metadata_not_ready" end
    return JRSInventorySetDurability(tonumber(source), tonumber(itemId), durability)
end
exports('setDurability', Inventory.setDurability)

Inventory.damageItem = function(source, itemId, amount)
    if type(JRSInventoryDamageItem) ~= "function" then return false, "metadata_not_ready" end
    return JRSInventoryDamageItem(tonumber(source), tonumber(itemId), amount)
end
exports('damageItem', Inventory.damageItem)

Inventory.repairItem = function(source, itemId, amount)
    if type(JRSInventoryRepairItem) ~= "function" then return false, "metadata_not_ready" end
    return JRSInventoryRepairItem(tonumber(source), tonumber(itemId), amount)
end
exports('repairItem', Inventory.repairItem)

Inventory.getInventoryTotalWeight = function(source)
    if getWeight then
        return getWeight(source)
    end
    return 0
end
exports('getInventoryTotalWeight', Inventory.getInventoryTotalWeight)

Inventory.CloseInv = function(source)
    TriggerClientEvent("jrs_inventory:CloseInv", source)
end
exports('CloseInv', Inventory.CloseInv)

-----------------------------------------------------------------------
-- [[  (Storage) ]]
-----------------------------------------------------------------------

Inventory.createstorage = function(source, id, tosize)
    TriggerEvent("jrsCore:registerstorage", source, id, tosize)
end
exports('createstorage', Inventory.createstorage)

Inventory.updatestorage = function(source, id, tosize)
    TriggerEvent("jrsCore:updatestorage", source, id, tosize)
end
exports('updatestorage', Inventory.updatestorage)

-- label (optional): string or { title = ..., name = ... } shown on the storage window.
Inventory.openstorage = function(source, id, label)
    TriggerEvent("jrsCore:openstorage", source, id, label)
end
exports('openstorage', Inventory.openstorage)

Inventory.RegisterUsableItem = function(itemName, cb)
    TriggerEvent("jrsCore:registerUsableItem", itemName, cb)
end
exports('RegisterUsableItem', Inventory.RegisterUsableItem)
