-- JRS housing (server): ownership + keys in `jrs_houses`, doors through
-- jrs_doorlocks, storages through jrs_inventory custom inventories.
local Houses = {}        -- [index] = { owner = charid, ownerName = '', keys = { [charid] = name } }
local Entrances = {}     -- [index] = vector3

local function n(v) return tonumber(v) end

local function notify(src, key, ...) TriggerClientEvent('jrs_housing:notify', src, L(key, ...), 5000) end

local function storageId(index, s) return ('house_%d_%d'):format(index, s) end

local function publicState(index)
    local h = Houses[index]
    if not h then return { owned = false } end
    local keys = {}
    for cid in pairs(h.keys) do keys[#keys + 1] = cid end
    return { owned = true, owner = h.owner, ownerName = h.ownerName, keys = keys }
end

local function broadcast(index)
    TriggerClientEvent('jrs_housing:client:update', -1, index, publicState(index))
end

local function save(index)
    local h = Houses[index]
    if not h then
        MySQL.update.await('DELETE FROM jrs_houses WHERE house = ?', { index })
        return
    end
    MySQL.insert.await([[INSERT INTO jrs_houses (house, owner_charid, owner_name, `keys`) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE owner_charid = VALUES(owner_charid), owner_name = VALUES(owner_name), `keys` = VALUES(`keys`)]],
        { index, h.owner, h.ownerName, json.encode(h.keys) })
end

local function sourceOfChar(charId)
    for _, s in ipairs(GetPlayers()) do
        if tostring(JRS.CharId(s)) == tostring(charId) then return tonumber(s) end
    end
end

local function accessLevel(index, charId)
    local h = index and Houses[index]
    if not h or not charId then return nil end
    if h.owner == charId then return 'owner' end
    if h.keys[charId] then return 'key' end
    return nil
end

-- door access is per player session: (re)applied on spawn, purchase and key changes
local function setDoors(src, index, allow)
    if not src or not Player(src).state.IsInSession then return end
    for _, door in ipairs(Config.Houses[index].doors or {}) do
        pcall(function() exports.jrs_doorlocks:updateDoorPermission(src, door, allow and true or nil) end)
    end
end

local function registerStorages(index)
    for s, st in ipairs(Config.Houses[index].storages or {}) do
        exports.jrs_inventory:registerInventory({
            id = storageId(index, s), name = st.label, limit = st.slots or 100,
            acceptWeapons = false, shared = true, ignoreItemStackLimit = true,
        })
    end
end

local function applyAccess(src)
    local charId = n(JRS.CharId(src))
    if not charId then return end
    for index in pairs(Houses) do
        if accessLevel(index, charId) then setDoors(src, index, true) end
    end
end

-- ─── boot ──────────────────────────────────────────────────────────────────
CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `jrs_houses` (
        `house` INT NOT NULL,
        `owner_charid` INT NOT NULL,
        `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
        `keys` LONGTEXT NULL,
        `bought_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`house`),
        KEY `idx_owner` (`owner_charid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM jrs_houses') or {}) do
        local index = n(row.house)
        if index and Config.Houses[index] then
            local ok, keys = pcall(json.decode, row.keys or '{}')
            local clean = {}
            for k, v in pairs(ok and type(keys) == 'table' and keys or {}) do
                if n(k) then clean[n(k)] = tostring(v) end
            end
            Houses[index] = { owner = n(row.owner_charid), ownerName = row.owner_name or '', keys = clean }
        end
    end

    for index, house in ipairs(Config.Houses) do
        local pos
        if house.doors and house.doors[1] then
            local ok, p = pcall(function() return exports.jrs_doorlocks:getDoorCoords(house.doors[1]) end)
            if ok and p then pos = vector3(p.x, p.y, p.z) end
        end
        Entrances[index] = pos or house.position
        registerStorages(index)
    end

    -- players already in game (resource restart)
    for _, s in ipairs(GetPlayers()) do applyAccess(tonumber(s)) end
end)

AddEventHandler('jrs:SelectedCharacter', function(src)
    SetTimeout(3000, function() applyAccess(src) end)
end)

-- ─── callbacks ─────────────────────────────────────────────────────────────
JRS.Callback('jrs_housing:state', function()
    local list = {}
    for index in ipairs(Config.Houses) do list[index] = publicState(index) end
    return list, Entrances
end)

JRS.Callback('jrs_housing:keys', function(src, index)
    index = n(index)
    local h = index and Houses[index]
    if not h or h.owner ~= n(JRS.CharId(src)) then return {} end
    local out = {}
    for cid, name in pairs(h.keys) do out[#out + 1] = { charId = cid, name = name } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end)

JRS.Callback('jrs_housing:buy', function(src, index)
    index = n(index)
    local house = index and Config.Houses[index]
    local charId = n(JRS.CharId(src))
    if not house or not charId then return false end
    if not JRS.Near(src, Entrances[index], 8.0) then return false, L('too_far') end
    if not JRS.Cooldown(src, 'house_buy', 3) then return false end
    if Houses[index] then return false, L('already_owned') end
    local owned = 0
    for _, h in pairs(Houses) do if h.owner == charId then owned = owned + 1 end end
    if owned >= Config.MaxHousesPerCharacter then return false, L('too_many') end
    if not JRS.TakeMoney(src, house.price) then return false, L('no_money') end

    Houses[index] = { owner = charId, ownerName = JRS.Name(src), keys = {} }
    save(index)
    setDoors(src, index, true)
    broadcast(index)
    return true, L('bought', house.label)
end)

JRS.Callback('jrs_housing:sell', function(src, index)
    index = n(index)
    local house = index and Config.Houses[index]
    local h = house and Houses[index]
    if not h or h.owner ~= n(JRS.CharId(src)) then return false, L('not_owner') end
    if not JRS.Cooldown(src, 'house_sell', 3) then return false end

    local refund = math.floor(house.price * (Config.SellBackPercent / 100))
    Houses[index] = nil
    save(index)
    setDoors(src, index, false)
    for cid in pairs(h.keys) do setDoors(sourceOfChar(cid), index, false) end
    if Config.ClearStorageOnSell then
        for s in ipairs(house.storages or {}) do
            pcall(function() exports.jrs_inventory:deleteCustomInventory(storageId(index, s)) end)
        end
        registerStorages(index)
    end
    if refund > 0 then JRS.GiveMoney(src, refund) end
    broadcast(index)
    return true, L('sold', house.label, refund)
end)

JRS.Callback('jrs_housing:giveKey', function(src, index, target)
    index, target = n(index), n(target)
    local h = index and Houses[index]
    if not h or h.owner ~= n(JRS.CharId(src)) then return false, L('not_owner') end
    if not target or target == src or not GetPlayerName(target) then return false, L('no_player') end
    if JRS.Distance(src, target) > Config.GiveKeyDistance + 1.0 then return false, L('no_player') end
    local cid = n(JRS.CharId(target))
    if not cid or cid == h.owner or h.keys[cid] then return false, L('has_key') end
    local count = 0
    for _ in pairs(h.keys) do count = count + 1 end
    if count >= Config.MaxKeys then return false, L('key_limit') end

    local name = JRS.Name(target)
    h.keys[cid] = name
    save(index)
    setDoors(target, index, true)
    notify(target, 'key_received', Config.Houses[index].label)
    broadcast(index)
    return true, L('key_given', name)
end)

JRS.Callback('jrs_housing:takeKey', function(src, index, charId)
    index, charId = n(index), n(charId)
    local h = index and Houses[index]
    if not h or h.owner ~= n(JRS.CharId(src)) then return false, L('not_owner') end
    local name = charId and h.keys[charId]
    if not name then return false end
    h.keys[charId] = nil
    save(index)
    local target = sourceOfChar(charId)
    if target then
        setDoors(target, index, false)
        notify(target, 'key_lost', Config.Houses[index].label)
    end
    broadcast(index)
    return true, L('key_taken', name)
end)

RegisterNetEvent('jrs_housing:server:openStorage', function(index, s)
    local src = source
    index, s = n(index), n(s)
    local house = index and Config.Houses[index]
    local st = house and house.storages and s and house.storages[s]
    if not st then return end
    if not accessLevel(index, n(JRS.CharId(src))) then return notify(src, 'no_access') end
    if not JRS.Near(src, st.coords, 3.0) then return notify(src, 'too_far') end
    exports.jrs_inventory:openInventory(src, storageId(index, s))
end)

RegisterNetEvent('jrs_housing:server:openWardrobe', function(index)
    local src = source
    index = n(index)
    local house = index and Config.Houses[index]
    if not house or not house.wardrobe then return end
    if not accessLevel(index, n(JRS.CharId(src))) then return notify(src, 'no_access') end
    if not JRS.Near(src, house.wardrobe, 3.0) then return notify(src, 'too_far') end
    TriggerClientEvent('jrs_clothing:open', src)
end)

-- other resources: exports.jrs_housing:GetHouseAccess(src, index) -> 'owner' | 'key' | nil
exports('GetHouseAccess', function(src, index) return accessLevel(n(index), n(JRS.CharId(src))) end)
exports('GetOwnedHouses', function(charId)
    local out = {}
    for index, h in pairs(Houses) do if h.owner == n(charId) then out[#out + 1] = index end end
    return out
end)
