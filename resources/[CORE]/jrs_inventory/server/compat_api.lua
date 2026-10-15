-- Extended inventory API for the extra scripts (server).
-- Every exports.jrs_inventory:* call used by extra scripts is served by
-- jrs_inventory. Custom inventories are JRS storages (jrs_inventory_storage).

-- Calls go straight to this resource's own API table (JRSInventoryAPI, see jrsInventoryAPI.lua).
local INVProxy = setmetatable({}, { __index = function(_, k)
    return function(_, ...) return JRSInventoryAPI[k](...) end
end })
local INV = function() return INVProxy end

-- Returns the value AND calls cb(value) when a callback is given.
local function respond(cb, result)
    if type(cb) == "function" then cb(result) end
    return result
end

-- Item definitions cache (jrs_items). "limit" in JRS is the item weight.
local ItemDefs, ItemDefsAt = {}, 0
local function loadItemDefs()
    local rows = MySQL.query.await('SELECT item, label, `limit`, type, usable, descriptions FROM jrs_items') or {}
    local defs = {}
    for _, r in ipairs(rows) do
        defs[r.item] = { item = r.item, label = r.label, weight = tonumber(r.limit) or 0, limit = 0,
            type = r.type, usable = r.usable, desc = r.descriptions }
    end
    ItemDefs, ItemDefsAt = defs, GetGameTimer()
end
local function itemDef(name)
    if GetGameTimer() - ItemDefsAt > 300000 or next(ItemDefs) == nil then pcall(loadItemDefs) end
    return ItemDefs[name]
end

-- JRS inventory entry -> item table
local function toExtItem(entry)
    if type(entry) ~= "table" then return nil end
    local def = itemDef(entry.item) or {}
    local meta = type(entry.metaData) == "table" and entry.metaData or {}
    return {
        id = entry.itemId,
        mainid = entry.itemId,
        name = entry.item,
        label = meta.label or entry.label or def.label or entry.item,
        desc = meta.description or def.desc or "",
        metadata = meta,
        type = def.type or "item_standard",
        count = tonumber(entry.count) or 0,
        amount = tonumber(entry.count) or 0,
        limit = tonumber(def.limit) or 0,
        canUse = tonumber(def.usable) == 1,
        group = def.group or 1,
        weight = tonumber(def.weight) or 0,
        percentage = 100,
        isDegradable = false,
        durability = meta.durability,
    }
end

local function inventory(source)
    local ok, inv = pcall(function() return INV():getUserInventory(source) end)
    return ok and type(inv) == "table" and inv or {}
end

local function metaMatches(meta, wanted)
    if type(wanted) ~= "table" then return true end
    meta = type(meta) == "table" and meta or {}
    for k, v in pairs(wanted) do
        if meta[k] ~= v then return false end
    end
    return true
end

local API = {}

-- ITEMS -------------------------------------------------------------------
API.addItem = function(source, name, amount, metadata, cb)
    local ok = INV():addItem(source, name, tonumber(amount) or 1, metadata or {}) == true
    return respond(cb, ok)
end
API.subItem = function(source, name, amount, metadata, cb)
    if type(metadata) == "function" then cb, metadata = metadata, nil end
    amount = tonumber(amount) or 1
    if type(metadata) == "table" and next(metadata) then
        for _, entry in pairs(inventory(source)) do
            if entry.item == name and metaMatches(entry.metaData, metadata) then
                return respond(cb, INV():subItemByID(source, entry.itemId, amount) == true)
            end
        end
        return respond(cb, false)
    end
    return respond(cb, INV():subItem(source, name, amount) == true)
end
API.subItemById = function(source, id, cb, allow, amount)
    return respond(cb, INV():subItemByID(source, id, tonumber(amount) or 1) == true)
end
API.subItemID = API.subItemById
API.canCarryItem = function(source, name, amount, cb)
    return respond(cb, INV():canCarryItem(source, name, tonumber(amount) or 1) == true)
end
API.canCarryItems = function(source, amount, cb)
    local ok, info = pcall(function() return INV():getCarryInfo(source, nil, amount) end)
    return respond(cb, true)
end
API.getItemCount = function(source, cb, name, metadata)
    if type(cb) == "string" then cb, name, metadata = nil, cb, name end
    if type(metadata) == "table" and next(metadata) then
        local n = 0
        for _, entry in pairs(inventory(source)) do
            if entry.item == name and metaMatches(entry.metaData, metadata) then n = n + (tonumber(entry.count) or 0) end
        end
        return respond(cb, n)
    end
    return respond(cb, tonumber(INV():getItemCount(source, name)) or 0)
end
API.getUserInventoryItems = function(source, cb)
    local list = {}
    for _, entry in pairs(inventory(source)) do list[#list + 1] = toExtItem(entry) end
    return respond(cb, list)
end
API.getItem = function(source, name, cb, metadata)
    for _, entry in pairs(inventory(source)) do
        if entry.item == name and metaMatches(entry.metaData, metadata) then
            return respond(cb, toExtItem(entry))
        end
    end
    return respond(cb, nil)
end
API.getItemByName = function(source, name, cb) return API.getItem(source, name, cb) end
API.getItemContainingMetadata = function(source, name, metadata, cb) return API.getItem(source, name, cb, metadata) end
API.getItemMatchingMetadata = API.getItemContainingMetadata
API.getItemById = function(source, id, cb)
    return respond(cb, toExtItem(INV():getItemById(source, id)))
end
API.getItemByMainId = API.getItemById
API.getItemDB = function(name, cb)
    local def = itemDef(name)
    if not def then return respond(cb, nil) end
    return respond(cb, {
        item = def.item or name, label = def.label, label_ar = def.label_ar, weight = def.weight, limit = def.limit,
        desc = def.desc, type = def.type, usable = def.usable, metadata = {},
    })
end
API.setItemMetadata = function(source, itemId, metadata, amount, cb)
    if type(amount) == "function" then cb = amount end
    return respond(cb, INV():setMetadata(source, itemId, metadata, true) == true)
end
API.setItemDurability = function(source, itemId, durability, cb)
    return respond(cb, INV():setDurability(source, itemId, durability) == true)
end
API.subAllItems = function(source, cb)
    for _, entry in pairs(inventory(source)) do
        INV():subItemByID(source, entry.itemId, tonumber(entry.count) or 1)
    end
    return respond(cb, true)
end
API.registerUsableItem = function(name, cb)
    INV():RegisterUsableItem(name, function(data)
        local entry = { itemId = data.itemId, item = data.item, label = data.label, count = 1, metaData = data.metaData }
        cb({ source = data.source, item = toExtItem(entry), args = data.args })
    end)
end
API.unRegisterUsableItem = function(name)
    INV():RegisterUsableItem(name, nil)
end

-- WEAPONS -----------------------------------------------------------------
local function weapons(source)
    local ok, list = pcall(function() return INV():getWeaponsMe(source) end)
    return ok and type(list) == "table" and list or {}
end
local function toExtWeapon(w)
    return {
        id = w.id, name = w.name, label = w.label or w.name, ammo = json.decode(w.ammo or '{}') or {},
        components = json.decode(w.comps or '[]') or {}, used = w.used == 1, used2 = false,
        serial_number = w.serial_number,
        charidentifier = w.charidentifier,
    }
end
API.createWeapon = function(source, name, ammo, _, comps, cb)
    if type(comps) == "function" then cb, comps = comps, nil end
    INV():createWeapon(source, name, ammo or {}, comps or {})
    return respond(cb, true)
end
API.giveWeapon = function(source, weaponId, target, cb)
    INV():giveWeapon(source, weaponId, target)
    return respond(cb, true)
end
API.subWeapon = function(source, weaponId, cb)
    INV():subWeapon(source, weaponId)
    return respond(cb, true)
end
API.deleteWeapon = function(source, weaponId, cb)
    INV():subWeapon(source, weaponId)
    return respond(cb, true)
end
API.subAllWeapons = function(source, cb)
    for _, w in ipairs(weapons(source)) do INV():subWeapon(source, w.id) end
    return respond(cb, true)
end
API.getUserInventoryWeapons = function(source, cb)
    local list = {}
    for _, w in ipairs(weapons(source)) do list[#list + 1] = toExtWeapon(w) end
    return respond(cb, list)
end
API.getUserWeapon = function(source, cb, weaponId)
    for _, w in ipairs(weapons(source)) do
        if tonumber(w.id) == tonumber(weaponId) then return respond(cb, toExtWeapon(w)) end
    end
    return respond(cb, nil)
end
API.canCarryWeapons = function(source, amount, cb) return respond(cb, true) end
API.getWeaponBullets = function(source, cb, weaponId) return respond(cb, 0) end
API.getWeaponComponents = function(source, weaponId, cb) return respond(cb, {}) end
API.getUserAmmo = function(source, cb) return respond(cb, {}) end
API.removeAllUserAmmo = function(source, cb) return respond(cb, true) end
API.addBullets = function(source, ammoType, amount, cb) return respond(cb, true) end
API.subBullets = function(source, weaponId, ammoType, amount, cb) return respond(cb, true) end
API.addWeaponComponent = function(...) local cb = select(5, ...) return respond(cb, true) end
API.subWeaponComponent = API.addWeaponComponent
API.addComponent = API.addWeaponComponent
API.subComponent = API.addWeaponComponent
-- jrs_weaponloadout has no custom label/description columns.
API.setWeaponCustomLabel = function(source, weaponId, label, cb) return respond(cb, false) end
API.setWeaponSerialNumber = function(source, weaponId, serial, cb)
    MySQL.update.await('UPDATE jrs_weaponloadout SET serial_number = ? WHERE id = ?', { serial, weaponId })
    return respond(cb, true)
end
API.setWeaponCustomDesc = function(source, weaponId, desc, cb) return respond(cb, false) end

-- PLAYER INVENTORY UI -----------------------------------------------------
API.openInventory = function(source, id)
    if not id then
        TriggerClientEvent('jrs_inventory:open_inventory', source)
        return
    end
    return JRSExtCustom.Open(source, id)
end
API.closeInventory = function(source)
    INV():CloseInv(source)
end
API.openPlayerInventory = function(source, target)
    pcall(function() exports[GetCurrentResourceName()]:OpenPlayerInventoryAdmin(source, target) end)
end

-- Export every extended name. Where jrs_inventory already has the same export
-- (addItem, subItem, getItemCount, ...) the call is routed by the CALLER:
-- resources that use the extended API declare `jrs_api 'ext'` in their fxmanifest.
local function isExtCaller()
    local res = GetInvokingResource()
    return res ~= nil and GetResourceMetadata(res, 'jrs_api', 0) == 'ext'
end
for name, fn in pairs(API) do
    local native = JRSInventoryAPI[name]
    if native then
        exports(name, function(...)
            if isExtCaller() then return fn(...) end
            return native(...)
        end)
    else
        exports(name, fn)
    end
end
exports('jrs_inventoryExtApi', function() return API end)

JRSExtInventoryAPI = API
