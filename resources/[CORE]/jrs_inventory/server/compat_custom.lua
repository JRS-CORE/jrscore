-- Custom inventories (registerInventory / openInventory(id) / ...) on top of
-- JRS storages. Each custom inventory id becomes one jrs_inventory_storage row.
-- Item storage format matches jrs_inventory: { item, count, metaData }.

local Registered = {}

local function key(id) return "jrs:" .. tostring(id) end

local function respond(cb, result)
    if type(cb) == "function" then cb(result) end
    return result
end

local function ensureRow(id)
    local data = Registered[id] or {}
    MySQL.insert.await('INSERT IGNORE INTO jrs_inventory_storage (identifier, charid, size, items) VALUES (?, 0, ?, ?)',
        { key(id), tonumber(data.limit) or 100, '[]' })
end

local function readItems(id)
    local row = MySQL.single.await('SELECT items FROM jrs_inventory_storage WHERE identifier = ? LIMIT 1', { key(id) })
    local ok, items = pcall(json.decode, row and row.items or '[]')
    return ok and type(items) == "table" and items or {}
end

local function writeItems(id, items)
    ensureRow(id)
    MySQL.update.await('UPDATE jrs_inventory_storage SET items = ? WHERE identifier = ?', { json.encode(items), key(id) })
end

local Custom = {}

Custom.Register = function(data)
    if type(data) ~= "table" or not data.id then return end
    Registered[data.id] = {
        id = data.id,
        name = data.name or tostring(data.id),
        limit = tonumber(data.limit) or 100,
        data = data,
    }
    ensureRow(data.id)
end

Custom.Open = function(source, id)
    if not Registered[id] then
        print(("^3[jrs_inventory] openInventory: inventory '%s' is not registered^7"):format(tostring(id)))
        return
    end
    local inv = Registered[id]
    JRSInventoryAPI.openstorage(source, key(id), { title = inv.name })
end

local function countOf(items, name, metadata)
    local n = 0
    for _, e in ipairs(items) do
        if e.item == name then
            local ok = true
            if type(metadata) == "table" then
                for k, v in pairs(metadata) do
                    if type(e.metaData) ~= "table" or e.metaData[k] ~= v then ok = false break end
                end
            end
            if ok then n = n + (tonumber(e.count) or 0) end
        end
    end
    return n
end

local E = {}
E.registerInventory = Custom.Register
E.isCustomInventoryRegistered = function(id, cb) return respond(cb, Registered[id] ~= nil) end
E.removeInventory = function(id) Registered[id] = nil end
E.deleteCustomInventory = function(id, cb)
    Registered[id] = nil
    MySQL.update.await('DELETE FROM jrs_inventory_storage WHERE identifier = ?', { key(id) })
    return respond(cb, true)
end
E.updateCustomInventorySlots = function(id, slots)
    if Registered[id] then Registered[id].limit = tonumber(slots) or Registered[id].limit end
    MySQL.update.await('UPDATE jrs_inventory_storage SET size = ? WHERE identifier = ?', { tonumber(slots) or 0, key(id) })
end
E.getCustomInventorySlots = function(id, cb) return respond(cb, Registered[id] and Registered[id].limit or 0) end
E.getCustomInventoryData = function(id, cb) return respond(cb, Registered[id] and Registered[id].data or nil) end
E.updateCustomInventoryData = function(id, data, cb)
    if Registered[id] and type(data) == "table" then
        for k, v in pairs(data) do Registered[id].data[k] = v end
        if data.name then Registered[id].name = data.name end
        if data.limit then Registered[id].limit = tonumber(data.limit) or Registered[id].limit end
    end
    return respond(cb, Registered[id] ~= nil)
end

E.getCustomInventoryItems = function(id, cb)
    local list = {}
    for i, e in ipairs(readItems(id)) do
        if e.item and not e.name then
            list[#list + 1] = { id = i, name = e.item, label = e.label or e.item, amount = tonumber(e.count) or 0,
                count = tonumber(e.count) or 0, metadata = e.metaData or {} }
        end
    end
    return respond(cb, list)
end
E.getCustomInventoryItemCount = function(id, name, _, cb, metadata)
    return respond(cb, countOf(readItems(id), name, metadata))
end
E.addItemsToCustomInventory = function(id, items, charid, cb)
    local current = readItems(id)
    for _, it in ipairs(type(items) == "table" and items or {}) do
        local name, amount = it.name or it.item, tonumber(it.amount or it.count) or 1
        local merged = false
        if type(it.metadata) ~= "table" or next(it.metadata) == nil then
            for _, e in ipairs(current) do
                if e.item == name and (type(e.metaData) ~= "table" or next(e.metaData) == nil) then
                    e.count = (tonumber(e.count) or 0) + amount
                    merged = true
                    break
                end
            end
        end
        if not merged then current[#current + 1] = { item = name, count = amount, metaData = it.metadata or {} } end
    end
    writeItems(id, current)
    return respond(cb, true)
end
E.removeItemFromCustomInventory = function(id, name, amount, _, cb)
    local current, left = readItems(id), tonumber(amount) or 1
    for i = #current, 1, -1 do
        local e = current[i]
        if left <= 0 then break end
        if e.item == name then
            local take = math.min(left, tonumber(e.count) or 0)
            e.count = (tonumber(e.count) or 0) - take
            left = left - take
            if e.count <= 0 then table.remove(current, i) end
        end
    end
    writeItems(id, current)
    return respond(cb, left <= 0)
end
E.updateCustomInventoryItem = function(id, itemId, metadata, amount, cb)
    local current = readItems(id)
    local e = current[tonumber(itemId)]
    if not e then return respond(cb, false) end
    if type(metadata) == "table" then e.metaData = metadata end
    if amount then e.count = tonumber(amount) or e.count end
    writeItems(id, current)
    return respond(cb, true)
end

-- Weapons in custom inventories are not supported by JRS storages.
E.addWeaponsToCustomInventory = function(id, weapons, charid, cb) return respond(cb, false) end
E.getCustomInventoryWeapons = function(id, cb) return respond(cb, {}) end
E.getCustomInventoryWeaponCount = function(id, name, cb) return respond(cb, 0) end
E.removeWeaponFromCustomInventory = function(id, name, cb) return respond(cb, false) end
E.removeCustomInventoryWeaponById = function(id, weaponId, cb) return respond(cb, false) end

-- Permissions / limits: JRS storages are opened only by the script that owns
-- them, so these are accepted and ignored.
for _, name in ipairs({ "AddPermissionMoveToCustom", "AddPermissionTakeFromCustom", "AddCharIdPermissionMoveToCustom",
    "AddCharIdPermissionTakeFromCustom", "BlackListCustomAny", "setCustomInventoryItemLimit", "setCustomInventoryWeaponLimit" }) do
    E[name] = function() end
end

for name, fn in pairs(E) do
    if not JRSInventoryAPI[name] then exports(name, fn) end
    JRSExtInventoryAPI[name] = fn
end

JRSExtCustom = Custom
