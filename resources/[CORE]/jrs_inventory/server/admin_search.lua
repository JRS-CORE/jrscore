-- ===========================================================================
-- JRS / JRS Admin Dual Inventory Inspection Module
-- Allows admins to view and manage a player's inventory side-by-side with their own
-- ===========================================================================

local isCallable = function(fn)
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

local jrsCore = setmetatable({}, {
    __index = function(_, key)
        return function(...)
            local args = { ... }
            if key == "getUser" or key == "GetUser" then
                if type(JRSInventoryGetCoreUser) == "function" then
                    return JRSInventoryGetCoreUser(tonumber(args[1]))
                end
                return nil
            end

            if key == "getCharacter" or key == "GetCharacter" then
                local okDirect, character = pcall(function()
                    return exports[(Config and Config.CoreResource) or 'jrs_core']:GetCharacter(tonumber(args[1]))
                end)
                if okDirect and character then return character end
            end

            local ok, api = pcall(function() return exports[(Config and Config.CoreResource) or 'jrs_core']:getCoreApi() end)
            if not ok or type(api) ~= "table" or not isCallable(api[key]) then
                return nil
            end
            return api[key](...)
        end
    end,
})

local Inventory = JRSInventoryInternalAPI or exports[GetCurrentResourceName()]:jrs_inventoryApi()
local activeAdminSearches = {}
local transferBusy = {}

-- Sessions opened by gameplay (jrs_robbery) carry maxDistance; admin sessions have none.
local function sessionInRange(admin, session)
    if not session.maxDistance then return true end
    local a, t = GetPlayerPed(admin), GetPlayerPed(session.target)
    if a == 0 or t == 0 then return false end
    return #(GetEntityCoords(a) - GetEntityCoords(t)) <= session.maxDistance
end

local function getCharacter(playerId)
    playerId = tonumber(playerId)
    if not playerId then return nil end

    local ok, character = pcall(function()
        return jrsCore.getCharacter(playerId)
    end)
    if ok and character then return character end

    local okUser, user = pcall(function()
        return jrsCore.getUser(playerId)
    end)
    if okUser and user then
        return user.getUsedCharacter
    end
    return nil
end

local function buildPlayerStorage(targetPlayerId)
    local storageItems = {}
    local Character = getCharacter(targetPlayerId)

    if Character then
        local cash = tonumber(Character.money) or 0
        if cash > 0 then
            table.insert(storageItems, {
                item = 'money',
                count = math.floor(cash * 100 + 0.5) / 100,
                limit = 0.0,
                slot = 1
            })
        end

        local gold = tonumber(Character.gold) or 0
        if gold > 0 then
            table.insert(storageItems, {
                item = 'gold',
                count = math.floor(gold * 100 + 0.5) / 100,
                limit = 0.0,
                slot = 2
            })
        end

        local dirtymoney = tonumber(Character.dirtymoney) or 0
        if dirtymoney > 0 then
            table.insert(storageItems, {
                item = 'dirtymoney',
                count = math.floor(dirtymoney * 100 + 0.5) / 100,
                limit = 0.0,
                slot = 3
            })
        end
    end

    local inv = Inventory.getUserInventory(targetPlayerId) or {}
    for _, entry in pairs(inv) do
        local count = tonumber(entry.count) or 0
        if count > 0 then
            table.insert(storageItems, {
                item = tostring(entry.item or entry.name or ''),
                count = count,
                metaData = entry.metaData or {},
                itemId = tonumber(entry.itemId or entry.id),
                slot = tonumber(entry.slot)
            })
        end
    end

    local weapons = Inventory.getWeaponsMe(targetPlayerId) or {}
    for _, weapon in pairs(weapons) do
        table.insert(storageItems, {
            item = tonumber(weapon.id) or weapon.id,
            name = tostring(weapon.name or ''),
            count = 1,
            itemId = tonumber(weapon.id) or weapon.id,
            serial_number = weapon.serial_number,
            stolen = weapon.stolen,
            used = weapon.used,
            slot = tonumber(weapon.slot)
        })
    end

    return storageItems
end

local function sendAdminSearch(adminSource, targetPlayerId, isRefresh)
    adminSource = tonumber(adminSource)
    targetPlayerId = tonumber(targetPlayerId)
    if not adminSource or not targetPlayerId then return end

    if not GetPlayerName(targetPlayerId) then
        TriggerClientEvent('jrs_inventory:CloseInv', adminSource)
        return
    end

    local storage = buildPlayerStorage(targetPlayerId)
    local items = exports[GetCurrentResourceName()]:preload_itemtable() or {}
    local weapons = exports[GetCurrentResourceName()]:preload_weapontable() or {}
    local storageId = 'admin_search:' .. tostring(targetPlayerId)

    local targetWeight = 0
    pcall(function()
        targetWeight = exports[GetCurrentResourceName()]:GetMaxWeight(targetPlayerId)
    end)
    if not targetWeight or targetWeight <= 0 then
        targetWeight = tonumber(Config.Max_Items) or 50
    end

    local targetName = GetPlayerName(targetPlayerId) or ('Player ' .. targetPlayerId)
    local display = {
        title = _Up(adminSource, 'inv_player_inventory') or 'حقيبة اللاعب',
        name = targetName
    }

    if isRefresh then
        TriggerClientEvent('jrs_inventory:refresh_storage', adminSource, storage, items, weapons, storageId, targetWeight)
    else
        TriggerClientEvent('jrs_inventory:get_storage', adminSource, storage, items, weapons, storageId, targetWeight, display)
    end
end

-- Only weapons the giving side really holds may be moved; the id comes from the client.
local function ownsWeapon(playerId, weaponId)
    for _, weapon in pairs(Inventory.getWeaponsMe(playerId) or {}) do
        if tonumber(weapon.id) == weaponId then return true end
    end
    return false
end

local function getTargetFromStorageId(storageId)
    local str = tostring(storageId or '')
    if str:find('^admin_search:') then
        return tonumber(str:sub(14))
    end
    return nil
end

-- Export called by jrs_admin or console
exports('OpenPlayerInventoryAdmin', function(adminSource, targetPlayerId, maxDistance)
    local admin = tonumber(adminSource)
    local target = tonumber(targetPlayerId)
    if not admin or not target then return false end
    if not GetPlayerName(target) then return false end

    -- Self-inspection fallback
    if admin == target then
        -- get_items/get_money are server events; the client handler refreshes and opens.
        TriggerClientEvent('jrs_inventory:open_inventory', admin)
        return true
    end

    activeAdminSearches[admin] = {
        target = target,
        targetName = GetPlayerName(target),
        maxDistance = tonumber(maxDistance)
    }

    -- Refresh admin's own inventory first
    TriggerEvent('jrs_inventory:get_items_sec', admin)
    TriggerEvent('jrs_inventory:get_money_sec', admin)

    Citizen.SetTimeout(150, function()
        sendAdminSearch(admin, target, false)
    end)
    return true
end)

-- Refresh request from UI
RegisterServerEvent('jrs_inventory:get_storage_srv')
AddEventHandler('jrs_inventory:get_storage_srv', function(_, id)
    local src = source
    local target = getTargetFromStorageId(id)
    if not target then return end
    if activeAdminSearches[src] and activeAdminSearches[src].target == target then
        sendAdminSearch(src, target, true)
    end
end)

-- Transfer Item from Target Player to Admin
RegisterServerEvent('jrs_inventory:transfer_item_from_storage')
AddEventHandler('jrs_inventory:transfer_item_from_storage', function(item, count, id, itemId, metaData, operationId, targetInventorySlot)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end
    if transferBusy[admin] then return end
    transferBusy[admin] = true

    count = math.floor(tonumber(count) or 1)
    itemId = tonumber(itemId)
    if count <= 0 or not itemId then
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'invalid_amount')
        return
    end

    -- Item name, metadata and amount come from the owner's real stack, never
    -- from the client, and nothing is added unless the removal succeeded.
    local owned = Inventory.getItemById(target, itemId)
    if not owned or (tonumber(owned.count) or 0) < count then
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'not_owned')
        sendAdminSearch(admin, target, true)
        return
    end
    local ownedName, ownedMeta = tostring(owned.item), owned.metaData or {}
    local removed = Inventory.subItemByID(target, itemId, count)
    if not removed then
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'remove_failed')
        sendAdminSearch(admin, target, true)
        return
    end
    -- The receiver can be full: give the stack back instead of losing it.
    if not Inventory.addItem(admin, ownedName, count, ownedMeta) then
        Inventory.addItem(target, ownedName, count, ownedMeta)
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'receiver_full')
        sendAdminSearch(admin, target, true)
        return
    end

    Citizen.Wait(100)
    TriggerEvent('jrs_inventory:get_items_sec', admin)
    TriggerEvent('jrs_inventory:get_items_sec', target)
    sendAdminSearch(admin, target, true)
    TriggerClientEvent('jrs_inventory:storageTransferResult', admin, true, 'ok')
    transferBusy[admin] = nil
end)

-- Transfer Item from Admin to Target Player
RegisterServerEvent('jrs_inventory:transfer_item_to_storage')
AddEventHandler('jrs_inventory:transfer_item_to_storage', function(item, count, id, itemId, metaData, operationId, targetSlot)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end
    if transferBusy[admin] then return end
    transferBusy[admin] = true

    count = math.floor(tonumber(count) or 1)
    itemId = tonumber(itemId)
    if count <= 0 or not itemId then
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'invalid_amount')
        return
    end

    -- Item name, metadata and amount come from the owner's real stack, never
    -- from the client, and nothing is added unless the removal succeeded.
    local owned = Inventory.getItemById(admin, itemId)
    if not owned or (tonumber(owned.count) or 0) < count then
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'not_owned')
        sendAdminSearch(admin, target, true)
        return
    end
    local ownedName, ownedMeta = tostring(owned.item), owned.metaData or {}
    local removed = Inventory.subItemByID(admin, itemId, count)
    if not removed then
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'remove_failed')
        sendAdminSearch(admin, target, true)
        return
    end
    -- The receiver can be full: give the stack back instead of losing it.
    if not Inventory.addItem(target, ownedName, count, ownedMeta) then
        Inventory.addItem(admin, ownedName, count, ownedMeta)
        transferBusy[admin] = nil
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'receiver_full')
        sendAdminSearch(admin, target, true)
        return
    end

    Citizen.Wait(100)
    TriggerEvent('jrs_inventory:get_items_sec', admin)
    TriggerEvent('jrs_inventory:get_items_sec', target)
    sendAdminSearch(admin, target, true)
    TriggerClientEvent('jrs_inventory:storageTransferResult', admin, true, 'ok')
    transferBusy[admin] = nil
end)

-- Transfer Weapon from Target Player to Admin
RegisterServerEvent('jrs_inventory:transfer_weapon_from_storage')
AddEventHandler('jrs_inventory:transfer_weapon_from_storage', function(weaponId, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    weaponId = tonumber(weaponId)
    if not weaponId or not ownsWeapon(target, weaponId) then
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'not_owned')
        return
    end
    if transferBusy[admin] then return end
    transferBusy[admin] = true

    -- subWeapon is async. giveWeapon(x, id, 0) only re-owns a row that is already
    -- unowned, so running it before the removal was written left the weapon
    -- owned by nobody. Chain it on the removal result instead.
    Inventory.subWeapon(target, weaponId, function(removed)
        if removed then
            Inventory.giveWeapon(admin, weaponId, 0)
        end
        Citizen.SetTimeout(250, function()
            TriggerEvent('jrs_inventory:get_items_sec', admin)
            TriggerEvent('jrs_inventory:get_items_sec', target)
            sendAdminSearch(admin, target, true)
            TriggerClientEvent('jrs_inventory:storageTransferResult', admin, removed == true, removed and 'ok' or 'remove_failed')
            transferBusy[admin] = nil
        end)
    end)
end)

-- Transfer Weapon from Admin to Target Player
RegisterServerEvent('jrs_inventory:transfer_weapon_to_storage')
AddEventHandler('jrs_inventory:transfer_weapon_to_storage', function(weaponId, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    weaponId = tonumber(weaponId)
    if not weaponId or not ownsWeapon(admin, weaponId) then
        TriggerClientEvent('jrs_inventory:storageTransferResult', admin, false, 'not_owned')
        return
    end
    if transferBusy[admin] then return end
    transferBusy[admin] = true

    -- subWeapon is async. giveWeapon(x, id, 0) only re-owns a row that is already
    -- unowned, so running it before the removal was written left the weapon
    -- owned by nobody. Chain it on the removal result instead.
    Inventory.subWeapon(admin, weaponId, function(removed)
        if removed then
            Inventory.giveWeapon(target, weaponId, 0)
        end
        Citizen.SetTimeout(250, function()
            TriggerEvent('jrs_inventory:get_items_sec', admin)
            TriggerEvent('jrs_inventory:get_items_sec', target)
            sendAdminSearch(admin, target, true)
            TriggerClientEvent('jrs_inventory:storageTransferResult', admin, removed == true, removed and 'ok' or 'remove_failed')
            transferBusy[admin] = nil
        end)
    end)
end)

-- Currency between admin and target. jrs_core's methods are
-- Character.method(source, currencyType, amount); the old calls passed
-- (currencyType, amount), so every admin cash/gold move errored and did nothing.
-- Fresh characters are read each time (the ones from exports are copies), and
-- the debit is refunded if the credit fails.
local function currencyBalance(character, currencyType)
    if not character then return 0 end
    if currencyType == 0 then return tonumber(character.money) or 0 end
    if currencyType == 1 then return tonumber(character.gold) or 0 end
    return tonumber(character.dirtymoney) or 0
end

local function callCurrency(character, method, playerId, currencyType, amount)
    local fn = character and character[method]
    if fn == nil then return false end
    local ok, result = pcall(fn, playerId, currencyType, amount)
    return ok and result == true
end

local function moveAdminCurrency(admin, fromId, toId, target, currencyType, count)
    local amount = math.floor((tonumber(count) or 0) * 100 + 0.5) / 100
    if amount <= 0 or transferBusy[admin] then return end
    transferBusy[admin] = true

    local fromChar, toChar = getCharacter(fromId), getCharacter(toId)
    local ok = fromChar and toChar and currencyBalance(fromChar, currencyType) >= amount
        and callCurrency(fromChar, 'removeCurrency', fromId, currencyType, amount)
    if ok and not callCurrency(toChar, 'addCurrency', toId, currencyType, amount) then
        callCurrency(fromChar, 'addCurrency', fromId, currencyType, amount)
        ok = false
    end

    TriggerEvent('jrs_inventory:get_money_sec', admin)
    TriggerEvent('jrs_inventory:get_money_sec', target)
    sendAdminSearch(admin, target, true)
    TriggerClientEvent('jrs_inventory:storageTransferResult', admin, ok == true, ok and 'ok' or 'not_enough')
    transferBusy[admin] = nil
end

-- Currency: Money
RegisterServerEvent('jrs_inventory:transfer_money_from_storage')
AddEventHandler('jrs_inventory:transfer_money_from_storage', function(_, count, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    moveAdminCurrency(admin, target, admin, target, 0, count)
end)

RegisterServerEvent('jrs_inventory:transfer_money_to_storage')
AddEventHandler('jrs_inventory:transfer_money_to_storage', function(_, count, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    moveAdminCurrency(admin, admin, target, target, 0, count)
end)

-- Currency: Gold
RegisterServerEvent('jrs_inventory:transfer_gold_from_storage')
AddEventHandler('jrs_inventory:transfer_gold_from_storage', function(_, count, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    moveAdminCurrency(admin, target, admin, target, 1, count)
end)

RegisterServerEvent('jrs_inventory:transfer_gold_to_storage')
AddEventHandler('jrs_inventory:transfer_gold_to_storage', function(_, count, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    moveAdminCurrency(admin, admin, target, target, 1, count)
end)

-- Currency: Dirty Money
RegisterServerEvent('jrs_inventory:transfer_dirtymoney_from_storage')
AddEventHandler('jrs_inventory:transfer_dirtymoney_from_storage', function(_, count, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    moveAdminCurrency(admin, target, admin, target, 3, count)
end)

RegisterServerEvent('jrs_inventory:transfer_dirtymoney_to_storage')
AddEventHandler('jrs_inventory:transfer_dirtymoney_to_storage', function(_, count, id)
    local admin = source
    local target = getTargetFromStorageId(id)
    if not target then return end

    local session = activeAdminSearches[admin]
    if not session or session.target ~= target or not sessionInRange(admin, session) then return end

    moveAdminCurrency(admin, admin, target, target, 3, count)
end)

-- Session Cleanup
local function cleanupSession(adminSource)
    adminSource = tonumber(adminSource)
    if adminSource and activeAdminSearches[adminSource] then
        activeAdminSearches[adminSource] = nil
        transferBusy[adminSource] = nil
    end
end

RegisterServerEvent('jrs_inventory:adminSearch:closeSearch')
AddEventHandler('jrs_inventory:adminSearch:closeSearch', function()
    cleanupSession(source)
end)

RegisterNetEvent('jrsCore:closestorage')
AddEventHandler('jrsCore:closestorage', function(id)
    if getTargetFromStorageId(id) then
        cleanupSession(source)
    end
end)

AddEventHandler('playerDropped', function()
    local droppedPlayer = source
    cleanupSession(droppedPlayer)

    for admin, session in pairs(activeAdminSearches) do
        if session.target == droppedPlayer then
            cleanupSession(admin)
            TriggerClientEvent('jrs_inventory:CloseInv', admin)
            TriggerClientEvent('jrsCore:notify', admin, _Up(admin, 'inventory'), 'The player has disconnected.', 'bag', 4000)
        end
    end
end)
