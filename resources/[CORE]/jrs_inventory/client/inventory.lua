-- ===========================================================================
-- Inventory UI Functions
-- ===========================================================================

-- Keep the Lua hotbar state synchronized with the hotbar saved in the database.
-- Previously the saved hotbar was sent only to NUI, so the icons appeared after
-- reconnect/restart while slot1..slot5 stayed empty and the keys did nothing.
local function NormalizeLoadedHotbarSlot(data)
    if type(data) ~= "table" or next(data) == nil then
        return {}, false
    end

    local itemName = data.item and tostring(data.item) or ""
    if itemName == "" then
        return {}, false
    end

    local isWeapon = data.weapon == true
        or data.weapon == 1
        or tostring(data.weapon) == "true"

    if isWeapon then
        local weaponId = tonumber(data.id)
        if not weaponId then
            return {}, true
        end

        local itemUpper = string.upper(itemName)
        for _, weapon in pairs(weapon_table or {}) do
            if tonumber(weapon.id) == weaponId and string.upper(tostring(weapon.name)) == itemUpper then
                return {
                    item = tostring(weapon.name),
                    id = weaponId,
                    weapon = true
                }, false
            end
        end

        -- The weapon was deleted/transferred and the old shortcut is no longer valid.
        return {}, true
    end

    local requestedId = tonumber(data.id)
    local fallbackItem = nil
    for _, item in pairs(inventory_table or {}) do
        if tostring(item.item) == itemName and tonumber(item.count or 0) > 0 then
            fallbackItem = fallbackItem or item
            if requestedId and tonumber(item.itemId) == requestedId then
                return {
                    item = itemName,
                    id = tonumber(item.itemId) or item.itemId,
                    weapon = false
                }, false
            end
        end
    end

    if fallbackItem then
        return {
            item = itemName,
            id = tonumber(fallbackItem.itemId) or fallbackItem.itemId,
            weapon = false
        }, requestedId ~= tonumber(fallbackItem.itemId)
    end

    -- The item is no longer in the inventory.
    return {}, true
end

local function LoadHotbarIntoClientState(hotbar)
    hotbar = type(hotbar) == "table" and hotbar or {}

    local cleaned = {}
    local changed = false
    local slots = {}
    local seenEntries = {}

    for index = 1, 5 do
        local slotData, slotChanged = NormalizeLoadedHotbarSlot(hotbar["slot" .. index])
        if type(slotData) == "table" and next(slotData) ~= nil then
            local identity = (slotData.weapon == true and "w:" or "i:")
                .. tostring(slotData.id) .. ":" .. tostring(slotData.item)
            if seenEntries[identity] then
                slotData = {}
                slotChanged = true
            else
                seenEntries[identity] = true
            end
        end

        slots[index] = slotData
        cleaned["slot" .. index] = slotData
        changed = changed or slotChanged
    end

    slot1 = slots[1]
    slot2 = slots[2]
    slot3 = slots[3]
    slot4 = slots[4]
    slot5 = slots[5]

    return cleaned, changed
end

function getWeaponDataWithActive()
    local _, currentWepHash = GetCurrentPedWeapon(PlayerPedId(), true, 0, true)
    local wpCopy = {}
    for _, w in pairs(weapon_table or {}) do
        local entry = {}
        for k2, v2 in pairs(w) do entry[k2] = v2 end
        entry.used = (GetHashKey(tostring(w.name)) == currentWepHash) and 1 or w.used
        table.insert(wpCopy, entry)
    end
    return wpCopy
end

-- Keep the canonical metaData table consistent before it is sent to NUI.
-- Equipment items inherit the configured durability default when it is missing.
local function normalizeClientInventoryMetadata(items)
	local settings = Config.Metadata or {}
	for _, item in pairs(type(items) == "table" and items or {}) do
		local metadata = item.metaData

		if type(metadata) ~= "table" then
			metadata = {}
		end

		local category = string.lower(tostring(item.category or ""))
		category = category:gsub("^%s+", ""):gsub("%s+$", "")
		local categoryDefaults = type(settings.CategoryDefaults) == "table"
			and settings.CategoryDefaults[category] or nil

		if metadata.durability == nil and type(categoryDefaults) == "table" then
			metadata.durability = tonumber(categoryDefaults.durability)
		end
		if metadata.durability == nil and category == "equipment" then
			metadata.durability = tonumber(settings.DefaultDurability) or 100
		end

		item.metaData = metadata
	end
	return items
end

local function IsInventoryTradeAvailable()
    local settings = type(Config.Trade) == 'table' and Config.Trade or {}
    if settings.Enabled ~= true then
        return false
    end

    local resourceName = tostring(settings.Resource or 'jrs_trade')
    return resourceName ~= '' and GetResourceState(resourceName) == 'started'
end

local function SendInventoryTradeAvailability()
    SendNUIMessage({
        type = 'trade_availability',
        enabled = IsInventoryTradeAvailable()
    })
end

function GetPlayerMaxWeight()
    local perks = LocalPlayer.state.jrsPerks
    if type(perks) == 'table' and tonumber(perks.carryKg) then
        return tonumber(perks.carryKg)
    end
    return tonumber(Config.Max_Items) or 50
end

function Show_Items(bool)
    inventory_table = normalizeClientInventoryMetadata(inventory_table)
    SetInventoryHudBlocked(bool)
    SetNuiFocus(bool, bool)
    guiEnabled = bool
    local groundData = GetNearbyGroundDrops and GetNearbyGroundDrops() or {}
    SendNUIMessage({
        type = "inventory_table",
        status = bool,
		table_for_json = inventory_table,
		wtable_for_json = getWeaponDataWithActive(),
		max_limit_i = GetPlayerMaxWeight(),
		max_limit_w = max_weapons_limit,
		money = money_state,
		gold = gold_state,
		dirtymoney = dirtymoney_state,
		ground = groundData,
		personal_items = Config.PersonalItems,
        ui_config = Config.InventoryUI,
        trade_enabled = IsInventoryTradeAvailable()
	})
	if bool and type(RefreshInventoryClothingState) == "function" then
		RefreshInventoryClothingState()
	end
end

function TryOpenInventoryWhenReady()
	if inventoryLoadPending and inventoryItemsReady and inventoryGroundReady then
		inventoryLoadPending = false
	end
end

function OpenInventory()
	if not inventoryCharacterReady then return end
	-- jrs_fightarena: the inventory is locked while fighting in the arena.
	if LocalPlayer.state and LocalPlayer.state.jrsArena == true then return end
	if guiEnabled or devReinitInProgress then return end

	-- Open on the very first frame using the already synchronized local cache.
	-- Server inventory/ground data is refreshed in the background and patches the
	-- visible UI when it arrives, so pressing the key never waits on MySQL/network.
	inventoryLoadPending = true
	inventoryItemsReady = false
	inventoryGroundReady = false
	Show_Items(true)

	TriggerServerEvent("jrs_inventory:get_items")
	TriggerServerEvent("jrs_inventory:check_drops_1")

	Citizen.CreateThread(function()
		Citizen.Wait(Config.InventoryLoadTimeoutMs)
		if inventoryLoadPending then
			inventoryLoadPending = false
		end
	end)
end

local storageDisplay = nil

function Show_Other(bool, open, storage)
	if bool and LocalPlayer.state and LocalPlayer.state.jrsArena == true then return end
	id_container = open
    SetInventoryHudBlocked(bool)
    SetNuiFocus(bool, bool)
    guiEnabled = bool
    local isAdminSearch = tostring(open or ''):find('^admin_search:') ~= nil
    SendNUIMessage({
        type = "container_table",
        status = bool,
        container_mode = isAdminSearch and "admin_search" or nil,
        target_name = storageDisplay and storageDisplay.name or nil,
		table_for_json = inventory_table,
		wtable_for_json = getWeaponDataWithActive(),
		max_limit_i = GetPlayerMaxWeight(),
		max_limit_w = max_weapons_limit,
		money = money_state,
		gold = gold_state,
		dirtymoney = dirtymoney_state,
		id_con = open,
		container_title = storageDisplay and storageDisplay.title or nil,
		container_name = storageDisplay and storageDisplay.name or nil,
		strg_tbl = storage,
		size = size,
		personal_items = Config.PersonalItems,
        ui_config = Config.InventoryUI,
        trade_enabled = false
	})
end


local function CurrentRobberyGameHour()
    local hour = nil
    if type(GetClockHours) == 'function' then
        local ok, value = pcall(GetClockHours)
        if ok then hour = tonumber(value) end
    end
    if hour == nil then
        local ok, value = pcall(Citizen.InvokeNative, 0xC82CF208C2B19199)
        if ok then hour = tonumber(value) end
    end
    if hour == nil then return -1 end
    return math.floor(hour) % 24
end

local function BuildRobberyContainer(payload)
    payload = type(payload) == 'table' and payload or {}
    local result = {}
    local itemDefinitions = {}
    local weaponDefinitions = {}

    for _, definition in pairs(payload.itemDefinitions or {}) do
        if definition.item then
            itemDefinitions[tostring(definition.item)] = definition
        end
    end

    for _, definition in pairs(payload.weaponDefinitions or {}) do
        local weaponName = definition.item or definition.name
        if weaponName then
            weaponDefinitions[string.upper(tostring(weaponName))] = definition
        end
    end

    if payload.allowMoney == true and (tonumber(payload.money) or 0) > 0 then
        table.insert(result, {
            weapon = false,
            label = _U('money'),
            item = 'money',
            count = math.floor((tonumber(payload.money) or 0) * 100 + 0.5) / 100,
            limit = 0.0,
            robbery = true,
        })
    end

    if payload.allowGold == true and (tonumber(payload.gold) or 0) > 0 then
        table.insert(result, {
            weapon = false,
            label = _U('gold'),
            item = 'gold',
            count = math.floor((tonumber(payload.gold) or 0) * 100 + 0.5) / 100,
            limit = 0.0,
            robbery = true,
        })
    end

    if payload.allowDirtyMoney == true and (tonumber(payload.dirtymoney) or 0) > 0 then
        table.insert(result, {
            weapon = false,
            label = _U('dirtymoney'),
            item = 'dirtymoney',
            count = math.floor((tonumber(payload.dirtymoney) or 0) * 100 + 0.5) / 100,
            limit = 0.0,
            robbery = true,
        })
    end

    for _, entry in pairs(payload.inventory or {}) do
        local itemName = tostring(entry.item or '')
        local definition = itemDefinitions[itemName]
        if itemName ~= '' and definition then
            table.insert(result, {
                weapon = false,
                label = tostring(definition.label or itemName),
                item = itemName,
                count = tonumber(entry.count) or 0,
                limit = tonumber(definition.limit) or 0,
                metaData = entry.metaData or {},
                itemId = tonumber(entry.itemId) or entry.itemId,
                category = definition.category,
                can_remove = definition.can_remove,
                robbery = true,
            })
        end
    end

    for _, weapon in pairs(payload.weapons or {}) do
        local weaponName = string.upper(tostring(weapon.name or ''))
        if weaponName ~= '' then
            local definition = weaponDefinitions[weaponName] or {}
            table.insert(result, {
                weapon = true,
                label = tostring(definition.label or weapon.name or weaponName),
                item = tonumber(weapon.id) or weapon.id, -- live weapon row id
                count = weaponName,                      -- image name expected by storage renderer
                limit = 1,
                used = tonumber(weapon.used) or 0,
                serial_number = weapon.serial_number,
                robbery = true,
            })
        end
    end

    return result
end

local function ResetRobberyInventoryState()
    robberyMode = false
    robberyTargetId = 0
    robberyTargetName = ""
    robberyPendingPayload = nil
    robberyInitialOpenPending = false
    id_container = 0
    storage_table = {}
    blockSpamming = false
    transferCount = nil
    waitForInteraction = false
end

local function Show_Robbery(payload)
    payload = type(payload) == 'table' and payload or {}
    local targetId = tonumber(payload.targetId)
    if not targetId or targetId <= 0 then return end

    robberyMode = true
    robberyTargetId = targetId
    robberyTargetName = tostring(payload.targetName or ('Player ' .. targetId))
    id_container = targetId
    size = tonumber(payload.targetMaxWeight) or tonumber(Config.Max_Items) or 0
    storage_table = BuildRobberyContainer(payload)

    SetInventoryHudBlocked(true)
    SetNuiFocus(true, true)
    guiEnabled = true
    blockSpamming = false
    transferCount = nil
    waitForInteraction = false

    SendNUIMessage({
        type = "container_table",
        status = true,
        container_mode = "robbery",
        target_id = robberyTargetId,
        target_name = robberyTargetName,
        table_for_json = inventory_table,
        wtable_for_json = getWeaponDataWithActive(),
        max_limit_i = GetPlayerMaxWeight(),
        max_limit_w = max_weapons_limit,
        money = money_state,
        gold = gold_state,
        dirtymoney = dirtymoney_state,
        id_con = robberyTargetId,
        strg_tbl = storage_table,
        size = size,
        personal_items = Config.PersonalItems,
        ui_config = Config.InventoryUI
    })

    SendNUIMessage({ type = 'cleanTransfer', success = true, reason = 'robbery_refresh' })
end

RegisterNetEvent('jrs_inventory:openRobbery')
AddEventHandler('jrs_inventory:openRobbery', function(payload)
    payload = type(payload) == 'table' and payload or {}

    if robberyMode == true then
        Show_Robbery(payload)
        return
    end

    robberyPendingPayload = payload
    robberyInitialOpenPending = true

    -- Always refresh the robber's own side before the first dual-inventory render.
    TriggerServerEvent('jrs_inventory:get_items')
    TriggerServerEvent('jrs_inventory:get_money')

    Citizen.SetTimeout(350, function()
        if robberyInitialOpenPending == true and robberyPendingPayload then
            local pending = robberyPendingPayload
            robberyPendingPayload = nil
            robberyInitialOpenPending = false
            Show_Robbery(pending)
        end
    end)
end)

-- Admin panel "View inventory" on yourself (jrs_admin -> OpenPlayerInventoryAdmin self path).
RegisterNetEvent('jrs_inventory:open_inventory')
AddEventHandler('jrs_inventory:open_inventory', function()
    TriggerServerEvent('jrs_inventory:get_money')
    -- jrs_admin closes its NUI first; give the focus release a frame before opening.
    Citizen.SetTimeout(150, function()
        OpenInventory()
    end)
end)

RegisterNetEvent('jrs_inventory:closeRobbery')
AddEventHandler('jrs_inventory:closeRobbery', function()
    if robberyMode ~= true and robberyInitialOpenPending ~= true then return end
    ResetRobberyInventoryState()
    Show_Items(false)
    SetNuiFocus(false, false)
    guiEnabled = false
end)

-- ===========================================================================
-- Inventory Events
-- ===========================================================================

RegisterNetEvent('jrs_inventory:reset_inventory')
AddEventHandler('jrs_inventory:reset_inventory', function()
	inventory_table,weapon_table, dropped_items, dropped_items_entity, condition_level, storage_table = {}, {}, {}, {}, {}, {}
	weaponAmmoRevision = {}
	weapon_first_used, weapon_second_used, rifle_first_used, rifle_second_used, is_last_ammo = false, false, false, false, false
	money_state, gold_state, dirtymoney_state, size, backup_save_throw = 0, 0, 0, 0, 0
	RemoveAllWeapons()
end)

-- Builds the storage rows the NUI shows. Definitions come with the event only
-- until this client has cached them (see storageDefinitionsFor on the server);
-- lookups are keyed once per call instead of scanning every definition for
-- every stored entry. Entries whose definition is missing are still listed
-- (they used to vanish while still counting toward the storage weight).
-- Name -> definition maps, rebuilt only when the definition tables change
-- (every storage refresh used to walk the whole item database).
local storageDefIndexSource = { items = nil, weapons = nil }
local storageItemDefIndex, storageWeaponDefIndex = {}, {}

local function storageDefinitionIndexes()
	if storageDefIndexSource.items ~= table_item then
		storageItemDefIndex = {}
		for _, def in pairs(table_item or {}) do
			if type(def) == 'table' and def.item ~= nil then storageItemDefIndex[tostring(def.item)] = def end
		end
		storageDefIndexSource.items = table_item
	end
	if storageDefIndexSource.weapons ~= wp_table then
		storageWeaponDefIndex = {}
		for _, def in pairs(wp_table or {}) do
			if type(def) == 'table' and def.item ~= nil then storageWeaponDefIndex[tostring(def.item)] = def end
		end
		storageDefIndexSource.weapons = wp_table
	end
	return storageItemDefIndex, storageWeaponDefIndex
end

local function buildStorageTable(storage, itm, wpn)
	if type(itm) == 'table' then table_item = itm end
	if type(wpn) == 'table' then wp_table = wpn end
	local itemDefs, weaponDefs = storageDefinitionIndexes()

	local rows = {}
	for _, v in ipairs(type(storage) == 'table' and storage or {}) do
		if v.item == 'gold' or v.item == 'dirtymoney' or v.item == 'money' then
			local count = v.count == nil and 0 or (math.floor(v.count * 10) / 10)
			table.insert(rows, { weapon = false, label = _U(v.item), item = v.item, count = count, limit = 0.2, slot = v.slot })
		elseif v.name == nil then
			local def = itemDefs[tostring(v.item)]
			table.insert(rows, {
				weapon = false,
				label = def and def.label or tostring(v.item),
				item = v.item,
				count = v.count,
				limit = def and def.limit or 0,
				metaData = v.metaData,
				itemId = v.itemId,
				slot = v.slot
			})
		else
			local def = weaponDefs[tostring(v.name)]
			table.insert(rows, {
				weapon = true,
				label = def and def.label or tostring(v.name),
				item = v.item,
				count = v.name,
				limit = 1,
				serial_number = v.serial_number,
				slot = v.slot
			})
		end
	end
	return rows
end

RegisterNetEvent('jrs_inventory:get_storage')
AddEventHandler('jrs_inventory:get_storage', function(storage, itm, wpn, id, sizes, display)
	storageDisplay = type(display) == 'table' and display or nil
	-- Resources that send this event directly (jrs_police's suspect search)
	-- do not go through the server name resolver.
	if not storageDisplay and tostring(id) == 'police_search' then
		storageDisplay = { title = _U('storage_name_police_search') }
	end
	size = tonumber(sizes) or 0
	storage_table = buildStorageTable(storage, itm, wpn)
	Show_Other(true, id, storage_table, money_state, size, gold_state)
end)

RegisterNetEvent('jrs_inventory:refresh_storage')
AddEventHandler('jrs_inventory:refresh_storage', function(storage, itm, wpn, id, sizes)
	-- A late refresh must not reopen a storage the player already closed.
	if id_container == nil or tostring(id_container) == '0' then return end
	size = tonumber(sizes) or size
	storage_table = buildStorageTable(storage, itm, wpn)
	if guiEnabled and tostring(id) == tostring(id_container) then
		-- Window already open on this storage: redraw only the storage grid.
		-- Show_Other re-sent the whole bag, focus and layout on every move.
		SendNUIMessage({ type = "storage_refresh", id_con = id, strg_tbl = storage_table, size = size })
		return
	end
	Show_Other(true, id, storage_table, money_state, size)
end)

RegisterNetEvent('jrs_inventory:close_storage')
AddEventHandler('jrs_inventory:close_storage', function(id)
	TriggerServerEvent("jrsCore:closestorage", id)
end)

-- Bumped on every server answer so batched transfers can wait for the
-- previous one instead of racing it into the server's busy/cooldown checks.
storageTransferResults = 0

RegisterNetEvent('jrs_inventory:storageTransferResult')
AddEventHandler('jrs_inventory:storageTransferResult', function(success, reason)
	storageTransferResults = (storageTransferResults or 0) + 1
	blockSpamming = false
	transferCount = nil
	waitForInteraction = false
	SendNUIMessage({ type = 'cleanTransfer', success = success == true, reason = reason })
end)

RegisterNetEvent('jrs_inventory:send_list_inventory')
AddEventHandler('jrs_inventory:send_list_inventory', function(table, wtable, ttable, wptable, hotbar, maxWeapons)
	table = normalizeClientInventoryMetadata(table)
	max_weapons_limit = maxWeapons or Config.Max_Weapons
	count_in_inventory = GetClientInventoryWeight(table)
	speed = GetSpeedForCarriedWeight(count_in_inventory)
	inventory_table = table

    if wtable ~= nil then
        weapon_table = ReconcileInventoryWeapons(wtable)
    end

	if type(ttable) == "table" then table_item = ttable end
	if type(wptable) == "table" then wp_table = wptable end

	-- Full inventory refreshes caused by using/equipping an item must never erase
	-- the local hotbar merely because an older server event omitted hotbar data.
	if type(hotbar) == "table" then
		local loadedHotbar, hotbarWasCleaned = LoadHotbarIntoClientState(hotbar)

		SendNUIMessage({
			type = "loadHotbar",
			hotbar = loadedHotbar
		})

		-- Remove stale shortcuts from the database too, so they do not return later.
		if hotbarWasCleaned then
			TriggerServerEvent("jrs_inventory:saveHotbar", loadedHotbar)
		end
	end

	if devReinitInProgress then
		devReinitInProgress = false
		if Config.DevReopenInventory then
			Show_Items(true)
		end
	elseif robberyInitialOpenPending == true and robberyPendingPayload then
		local pending = robberyPendingPayload
		robberyPendingPayload = nil
		robberyInitialOpenPending = false
		Show_Robbery(pending)
	elseif inventoryLoadPending then
		inventoryItemsReady = true
		SendNUIMessage({
			type = "updateInventory",
			table_for_json = inventory_table,
			wtable_for_json = getWeaponDataWithActive(),
			money = money_state,
			gold = gold_state,
			dirtymoney = dirtymoney_state,
		})
		TryOpenInventoryWhenReady()
	elseif guiEnabled then
		-- Only while the bag is on screen. When it is closed the cache above is
		-- enough (opening sends it in full); pushing the whole inventory into
		-- NUI on every change cost a JSON round trip + re-render for nothing.
		SendNUIMessage({
			type = "updateInventory",
			table_for_json = inventory_table,
			wtable_for_json = getWeaponDataWithActive(),
			money = money_state,
			gold = gold_state,
			dirtymoney = dirtymoney_state,
		})
	end
end)

RegisterNetEvent('jrs_inventory:update_list_inventory')
AddEventHandler('jrs_inventory:update_list_inventory', function(table, name, count, update_full,ttable,wptable)
	table = normalizeClientInventoryMetadata(table)
	inventory_table = {}
	inventory_table = table
	if type(ttable) == "table" then table_item = ttable end
	if type(wptable) == "table" then wp_table = wptable end
	count_in_inventory = GetClientInventoryWeight(table)
	speed = GetSpeedForCarriedWeight(count_in_inventory)
	if not guiEnabled then
		return
	end
	if update_full == true then
		SendNUIMessage({
			type = "inventory_update",
			update = update_full,
			table_for_json = inventory_table,
			wtable_for_json = getWeaponDataWithActive(),
			money = money_state,
			gold = gold_state,
			dirtymoney = dirtymoney_state,
		})
	else
		SendNUIMessage({
			type = "inventory_update",
			update = update_full,
			iditem = name,
			idcount = count,
			table_for_json = inventory_table,
			wtable_for_json = getWeaponDataWithActive(),
			money = money_state,
			gold = gold_state,
			dirtymoney = dirtymoney_state,
		})
	end
end)

RegisterNetEvent('jrs_inventory:send_list_money')
AddEventHandler('jrs_inventory:send_list_money', function(money, gold, dirtymoney)
	money_state = tonumber(money) or 0
	gold_state = tonumber(gold) or 0
	dirtymoney_state = tonumber(dirtymoney) or 0
	SendNUIMessage({
		type = "currency_update",
		money = money_state,
		gold = gold_state,
		dirtymoney = dirtymoney_state,
	})
end)

-- ===========================================================================
-- Inventory NUI Callbacks
-- ===========================================================================

RegisterNUICallback("saveSlots", function(data, cb)
    TriggerServerEvent("jrs_inventory:saveSlots", data.items, data.weapons)
    cb("ok")
end)

local function CurrentHotbarSnapshot()
    return {
        slot1 = type(slot1) == "table" and slot1 or {},
        slot2 = type(slot2) == "table" and slot2 or {},
        slot3 = type(slot3) == "table" and slot3 or {},
        slot4 = type(slot4) == "table" and slot4 or {},
        slot5 = type(slot5) == "table" and slot5 or {}
    }
end

local function SaveRequestedHotbar(requestedHotbar)
    local cleanedHotbar = LoadHotbarIntoClientState(requestedHotbar)
    TriggerServerEvent("jrs_inventory:saveHotbar", cleanedHotbar)
    SendNUIMessage({
        type = "loadHotbar",
        hotbar = cleanedHotbar
    })
    return cleanedHotbar
end

-- Legacy one-slot callback kept for compatibility with older HTML builds.
-- The requested entry is still resolved against the client's owned inventory
-- before it is allowed into local shortcut state or sent to the server.
RegisterNUICallback('hotbar_set', function(data, cb)
    local slot = math.floor(tonumber(data and data.slot) or 0)
    if slot < 1 or slot > 5 then
        cb("invalid_slot")
        return
    end

    local requested = CurrentHotbarSnapshot()
    if data.item == nil or tostring(data.item) == "" then
        requested["slot" .. slot] = {}
    else
        requested["slot" .. slot] = {
            item = tostring(data.item),
            id = tonumber(data.id) or data.id,
            weapon = data.weapon == true or tonumber(data.weapon) == 1 or tostring(data.weapon) == "true"
        }
    end

    SaveRequestedHotbar(requested)
    cb("ok")
end)

-- Primary v1.6.9 callback: all five quick slots are saved atomically. This makes
-- slot swaps/reorders a single server request and avoids brief duplicate states.
RegisterNUICallback('hotbar_save_all', function(data, cb)
    local requested = type(data) == "table" and data.hotbar or nil
    if type(requested) ~= "table" then
        cb("invalid_hotbar")
        return
    end

    SaveRequestedHotbar(requested)
    cb("ok")
end)

RegisterNetEvent("jrs_inventory:hotbarSync")
AddEventHandler("jrs_inventory:hotbarSync", function(hotbar)
    local cleanedHotbar = LoadHotbarIntoClientState(hotbar)
    SendNUIMessage({
        type = "loadHotbar",
        hotbar = cleanedHotbar
    })
end)

RegisterNUICallback('use_item' , function(data, cb)
	if id_container == 0 then
		TriggerServerEvent("jrs:use", data.item, data.id)
	end
	cb("ok")
end)

-- ===========================================================================
-- Integrated nearby-player selector for Give Item / Give Weapon
-- Inspired by the interaction style of mega_nplayerselector, but implemented
-- directly inside jrs_inventory so no external resource is required.
-- ===========================================================================

local givePlayerSelectorActive = false
local givePlayerSelectorThread = false
local givePlayerSelectorPurpose = 'single'

local function StopGivePlayerSelector(keepFocus)
    givePlayerSelectorActive = false
    giveItemEnable = false
    SendNUIMessage({
        type = 'give_player_selector',
        active = false,
        positions = {}
    })
    if keepFocus ~= true and guiEnabled ~= true then
        SetNuiFocus(false, false)
    end
end

local function FinishGiveFlow(closeInv)
    StopGivePlayerSelector(false)
    clearThisFunction()
    if closeInv == true then
        if id_container ~= 0 then
            TriggerServerEvent("jrsCore:closestorage", id_container)
            id_container = 0
        end
        inventoryLoadPending = false
        inventoryItemsReady = false
        inventoryGroundReady = false
        Show_Items(false, false)
        SetNuiFocus(false, false)
        guiEnabled = false
    end
end

local function StartGivePlayerSelector(purpose)
    if robberyMode == true then
        return false
    end

    givePlayerSelectorPurpose = tostring(purpose or 'single')
    givePlayerSelectorActive = true
    giveItemEnable = givePlayerSelectorPurpose ~= 'trade'
    playerDragId = 0
    SetNuiFocus(true, true)

    if givePlayerSelectorThread then
        return true
    end

    givePlayerSelectorThread = true
    Citizen.CreateThread(function()
        while givePlayerSelectorActive do
            local playerPed = PlayerPedId()
            local playerPos = GetEntityCoords(playerPed)
            local maxDistance
            if givePlayerSelectorPurpose == 'trade' then
                local tradeSettings = type(Config.Trade) == 'table' and Config.Trade or {}
                maxDistance = tonumber(tradeSettings.SelectorDistance) or 3.0
            else
                maxDistance = tonumber(Config.PlayerTransferDistance) or 2.0
            end
            local positions = {}

            for _, playerIndex in ipairs(GetActivePlayers()) do
                if playerIndex ~= PlayerId() then
                    local targetPed = GetPlayerPed(playerIndex)
                    if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
                        local coords = GetEntityCoords(targetPed)
                        if #(coords - playerPos) <= maxDistance then
                            -- Chest height: the marker dot sits ON the player, its name tag above.
                            local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 0.45)
                            if onScreen then
                                positions[#positions + 1] = {
                                    id = GetPlayerServerId(playerIndex),
                                    name = GetPlayerName(playerIndex) or ('Player ' .. tostring(GetPlayerServerId(playerIndex))),
                                    coords = { screenX, screenY }
                                }
                            end
                        end
                    end
                end
            end

            SendNUIMessage({
                type = 'give_player_selector',
                active = true,
                purpose = givePlayerSelectorPurpose,
                positions = positions,
                range = maxDistance
            })
            Citizen.Wait((Config.Performance and tonumber(Config.Performance.GiveSelectorRefreshMs)) or 100)
        end

        givePlayerSelectorThread = false
        SendNUIMessage({
            type = 'give_player_selector',
            active = false,
            positions = {}
        })
    end)

    return true
end

RegisterNUICallback('give_selector_cancel', function(_, cb)
    if givePlayerSelectorPurpose == 'trade' then
        StopGivePlayerSelector(false)
        givePlayerSelectorPurpose = 'single'
        Citizen.SetTimeout(0, function()
            OpenInventory()
        end)
    else
        FinishGiveFlow()
    end
    cb('ok')
end)

RegisterNUICallback('multi_start_player_selector', function(_, cb)
    if robberyMode == true then
        FinishGiveFlow()
        cb('blocked')
        return
    end
    -- Fully close the inventory so the bag close animation plays
    inventoryLoadPending = false
    inventoryItemsReady = false
    inventoryGroundReady = false
    Show_Items(false, false)
    SetNuiFocus(false, false)
    guiEnabled = false
    -- Wait for the close animation to finish before showing the give selector
    Citizen.SetTimeout(500, function()
        if StartGivePlayerSelector('multi') ~= true then
            FinishGiveFlow()
            return
        end
    end)
    cb('ok')
end)

RegisterNUICallback('give_checked_item', function(data, cb)
	local currencyItem = tostring(data.item or ""):lower()
	if currencyItem == "money" or currencyItem == "gold" or currencyItem == "dirtymoney" then
		local amount = tonumber(data.count) or 0
		local target = tonumber(data.id)
		if target and amount > 0 then
			local eventName = currencyItem == "money" and "jrs_inventory:give_money"
				or (currencyItem == "gold" and "jrs_inventory:give_gold" or "jrs_inventory:give_dirtymoney")
			FinishGiveFlow(true)
			TriggerServerEvent("jrs_inventory:turn_ped", target)
			TriggerServerEvent(eventName, target, amount, GetPlayerServerId(PlayerId()), NewInventoryOperationId("give_" .. currencyItem))
		else
			FinishGiveFlow(false)
		end
		cb("ok")
		return
	end
	if data.is == "item" then
		if data.item ~= "money" and data.item ~= "gold" and data.item ~= "dirtymoney" then
			if Config.IsNoTransferItem(data.itemName) then
				FinishGiveFlow(false)
				exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('resource_item_locked'), 'bag', 3500)
				cb("blocked")
				return
			end
			if Config.IsPersonalItem(data.itemName) then
				FinishGiveFlow(false)
				exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('personal_item_locked'), 'bag', 2500)
				cb("blocked")
				return
			end
			if tonumber(data.count) and tonumber(data.count) >= 1 then
				-- Exactly the stack that was picked (by its itemId). The old loop
				-- also matched every other stack with the same item name and
				-- sent a transfer for EACH of them.
				local stack = nil
				for _, v in pairs(inventory_table) do
					if tostring(v.itemId) == tostring(data.item) then
						stack = v
						break
					end
				end
				if stack and (tonumber(stack.count) or 0) >= tonumber(data.count) then
					FinishGiveFlow(true)
					TriggerServerEvent("jrs_inventory:turn_ped", data.id)
					TriggerServerEvent("jrs_inventory:transferItem", tonumber(data.id), tonumber(stack.itemId) or stack.itemId, tonumber(data.count), NewInventoryOperationId("give_item"))
				else
					FinishGiveFlow(false)
					exports['jrs_core']:DisplayLeftNotification(_U('inventory'), "".._U('not_enough_count').."", 'bag', 2000)
				end
			else
				FinishGiveFlow(false)
				exports['jrs_core']:DisplayLeftNotification(_U('inventory'), "".._U('wrong_value').."", 'bag', 2000)
			end
		else
			FinishGiveFlow(true)
			if data.item == "money" then
				TriggerServerEvent("jrs_inventory:turn_ped", data.id)
				TriggerServerEvent("jrs_inventory:give_money", data.id, data.count, GetPlayerServerId(PlayerId()), NewInventoryOperationId("give_money"))
			elseif data.item == "gold" then
				TriggerServerEvent("jrs_inventory:turn_ped", data.id)
				TriggerServerEvent("jrs_inventory:give_gold", data.id, data.count, GetPlayerServerId(PlayerId()), NewInventoryOperationId("give_gold"))
			elseif data.item == "dirtymoney" then
				TriggerServerEvent("jrs_inventory:turn_ped", data.id)
				TriggerServerEvent("jrs_inventory:give_dirtymoney", data.id, data.count, GetPlayerServerId(PlayerId()), NewInventoryOperationId("give_dirtymoney"))
			end
		end
	else
		local handled = false
		for k,v in pairs(weapon_table) do
			if tonumber(data.item) == tonumber(v.id) then
				handled = true
				if v.used == 0 then
					FinishGiveFlow(true)
					TriggerServerEvent("jrs_inventory:turn_ped", data.id)
					TriggerServerEvent("jrs_inventory:transferWeapon", tonumber(data.id), tonumber(data.item), NewInventoryOperationId("give_weapon"))
				else
					-- Close the marker picker too, or it keeps holding the mouse.
					FinishGiveFlow(false)
					exports['jrs_core']:DisplayLeftNotification(_U('inventory'), "".._U('unequip_first').."", 'bag', 2000)
				end
				break
			end
		end
		if not handled then FinishGiveFlow(false) end
	end
	if cb then cb("ok") end
end)

-- Give: the NUI already holds the item and amount. Close the bag completely,
-- then show the marker over each nearby player; clicking one sends
-- give_checked_item. ESC cancels (give_selector_cancel).
RegisterNUICallback('give_pick_player', function(data, cb)
	data = type(data) == 'table' and data or {}
	if robberyMode == true or robberyInitialOpenPending == true or id_container ~= 0 then
		FinishGiveFlow(false)
		if cb then cb('blocked') end
		return
	end
	if data.itemName and Config.IsNoTransferItem(data.itemName) then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('resource_item_locked'), 'bag', 3500)
		FinishGiveFlow(false)
		if cb then cb('blocked') end
		return
	end
	if data.itemName and Config.IsPersonalItem(data.itemName) then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('personal_item_locked'), 'bag', 2500)
		FinishGiveFlow(false)
		if cb then cb('blocked') end
		return
	end

	inventoryLoadPending = false
	inventoryItemsReady = false
	inventoryGroundReady = false
	Show_Items(false, false)
	SetNuiFocus(false, false)
	guiEnabled = false
	giveItemEnable = true

	-- Let the bag's close animation finish before the markers appear.
	Citizen.SetTimeout(350, function()
		if giveItemEnable ~= true then return end
		if StartGivePlayerSelector('single') ~= true then
			FinishGiveFlow(false)
		end
	end)
	if cb then cb('ok') end
end)

RegisterNUICallback('give_item', function(data, cb)
	if Config.IsNoTransferItem(data.itemName) then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('resource_item_locked'), 'bag', 3500)
		if cb then cb("blocked") end
		return
	end
	if Config.IsPersonalItem(data.itemName) then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('personal_item_locked'), 'bag', 2500)
		if cb then cb("blocked") end
		return
	end
	Citizen.Wait(20)
	local player_table = {}
	local mycoords = GetEntityCoords(PlayerPedId())
	local maxDist = tonumber(Config.PlayerTransferDistance) or 4.5
	for k,v in pairs(GetPlayers()) do
		local targetPed = GetPlayerPed(v)
		if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
			local targetCoords = GetEntityCoords(targetPed)
			local distance = #(mycoords - targetCoords)
			if distance <= maxDist and GetPlayerServerId(PlayerId()) ~= GetPlayerServerId(v) then
				table.insert(player_table, {
					name = GetPlayerName(v) or ('Player ' .. tostring(GetPlayerServerId(v))),
					id = GetPlayerServerId(v),
					distance = math.floor(distance * 10) / 10
				})
			end
		end
	end
	table.sort(player_table, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
	SendNUIMessage({
		type = "playertable",
		table_p_for_json = player_table,
		item = data.item,
		count = data.count,
		itemName = data.itemName,
		is = data.is or "item"
	})
	if cb then cb("ok") end
end)

local function StartInventoryTrade(target)
    target = tonumber(target)
    local settings = type(Config.Trade) == 'table' and Config.Trade or {}
    if not target or target <= 0 or settings.Enabled ~= true then return false end
    TriggerEvent('jrs_trade:client:openFromInventory', target)
    return true
end

local function OpenInventoryInput(title, prompt, callback)
    if type(callback) ~= 'function' then return false end
    if GetResourceState('jrs_core') == 'started' then
        local ok, result = pcall(function()
            return exports.jrs_core:GetInput(title, prompt, callback, { force = true })
        end)
        if ok and result ~= false then return true end
    end
    TriggerEvent('jrs_inputs:getInput', title, prompt, callback)
    return true
end

RegisterNUICallback('open_trade', function(_, cb)
    if robberyMode == true or robberyInitialOpenPending == true or id_container ~= 0 then
		TriggerEvent('jrsCore:notify', 'Trade', 'Close the current container before starting a trade.', 'bag', 3000)
        if cb then cb({ ok = false, reason = 'container_open' }) end
        return
    end

    if not IsInventoryTradeAvailable() then
        SendInventoryTradeAvailability()
		TriggerEvent('jrsCore:notify', 'Trade', 'The trade system is currently unavailable.', 'bag', 3000)
        if cb then cb({ ok = false, reason = 'trade_unavailable' }) end
        return
    end

    inventoryLoadPending = false
    inventoryItemsReady = false
    inventoryGroundReady = false
    Show_Items(false)
    guiEnabled = false

    -- Keep the inventory NUI focused only for the existing world-space player selector.
    -- No player ID screen is opened: selecting a marker immediately sends the trade request.
    if StartGivePlayerSelector('trade') ~= true then
        SetNuiFocus(false, false)
        if cb then cb({ ok = false, reason = 'selector_failed' }) end
        return
    end

    if cb then cb({ ok = true }) end
end)

RegisterNUICallback('trade_select_player', function(data, cb)
    local target = tonumber(data and data.target) or 0
    if givePlayerSelectorPurpose ~= 'trade' or target <= 0 or target == GetPlayerServerId(PlayerId()) then
        if cb then cb({ ok = false, reason = 'invalid_target' }) end
        return
    end

    if not IsInventoryTradeAvailable() then
        StopGivePlayerSelector(false)
        givePlayerSelectorPurpose = 'single'
        SendInventoryTradeAvailability()
        if cb then cb({ ok = false, reason = 'trade_unavailable' }) end
        return
    end

    StopGivePlayerSelector(false)
    givePlayerSelectorPurpose = 'single'
    guiEnabled = false

    local started = StartInventoryTrade(target)
    if not started then
        SendInventoryTradeAvailability()
        TriggerEvent('jrsCore:notify', 'Trade', 'The trade system is currently unavailable.', 'bag', 3000)
        if cb then cb({ ok = false, reason = 'trade_start_failed' }) end
        return
    end

    if cb then cb({ ok = true }) end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    local settings = type(Config.Trade) == 'table' and Config.Trade or {}
    local tradeResource = tostring(settings.Resource or 'jrs_trade')
    if resourceName == tradeResource or resourceName == GetCurrentResourceName() then
        SendInventoryTradeAvailability()
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    local settings = type(Config.Trade) == 'table' and Config.Trade or {}
    local tradeResource = tostring(settings.Resource or 'jrs_trade')
    if resourceName == tradeResource then
        SendInventoryTradeAvailability()
        if givePlayerSelectorActive and givePlayerSelectorPurpose == 'trade' then
            StopGivePlayerSelector(false)
            givePlayerSelectorPurpose = 'single'
            Citizen.SetTimeout(0, function()
                OpenInventory()
            end)
        end
    end
end)

RegisterNUICallback('showSkills', function(data, cb)
	TriggerEvent("jrs_inventory:CloseInv")
	ExecuteCommand("skills")
end)

RegisterNetEvent('jrs_inventory:CloseInv', function()
	if id_container ~= 0 then
		TriggerServerEvent("jrsCore:closestorage", id_container)
		id_container = 0
	end
	inventoryLoadPending = false
	inventoryItemsReady = false
	inventoryGroundReady = false
	Show_Items(false, false)
	SetNuiFocus(false, false)
	guiEnabled = false
	giveItemEnable = false
	StopGivePlayerSelector(false)
	clearThisFunction()
end)

RegisterNUICallback('exit', function(data, cb)
    if robberyMode == true or robberyInitialOpenPending == true then
        TriggerServerEvent('jrs_inventory:robbery:closeSearch')
        TriggerEvent('jrs_inventory:robbery:inventoryClosed')
        ResetRobberyInventoryState()
        inventoryLoadPending = false
        inventoryItemsReady = false
        inventoryGroundReady = false
        Show_Items(false, false)
        SetNuiFocus(false, false)
        guiEnabled = false
        cb('ok')
        return
    end

	if id_container ~= 0 then
		TriggerServerEvent("jrsCore:closestorage", id_container)
		Citizen.Wait(0)
		id_container = 0
	end
	inventoryLoadPending = false
	inventoryItemsReady = false
	inventoryGroundReady = false
	Show_Items(false, false)
    SetNuiFocus(false, false)
    guiEnabled = false
    cb('ok')
end)

RegisterNUICallback('exit2', function(data, cb)
	FinishGiveFlow()
	if cb then cb('ok') end
end)

RegisterNUICallback('transferItem', function(data, cb)
	if robberyMode == true then
		FinishGiveFlow()
		if cb then cb('blocked') end
		return
	end
	if givePlayerSelectorActive ~= true then
		-- Fully close the inventory so the bag close animation plays
		inventoryLoadPending = false
		inventoryItemsReady = false
		inventoryGroundReady = false
		Show_Items(false, false)
		SetNuiFocus(false, false)
		guiEnabled = false
		-- Wait for the close animation to finish before showing the give selector
		Citizen.SetTimeout(500, function()
			if StartGivePlayerSelector('single') ~= true then
				FinishGiveFlow()
				return
			end
		end)
	end
	if cb then cb('ok') end
end)

RegisterNUICallback('cancelBlock', function(data, cb)
	blockSpamming = false
	if cb then cb('ok') end
end)

RegisterNUICallback('transferAcceptItem', function(data, cb)
	transferCount = tonumber(data.count)
	waitForInteraction = true
	if cb then cb('ok') end
end)

RegisterNUICallback('transferLeaveItem', function(data, cb)
	waitForInteraction = false
	if cb then cb('ok') end
end)

RegisterNUICallback('screen', function(data, cb)
    xRes = tonumber(data.x)
    yRes = tonumber(data.y)
    if cb then cb('ok') end
end)

local function normalizeTransferMetadata(metadata)
    if type(metadata) ~= 'table' then return nil end
    for _ in pairs(metadata) do
        return metadata
    end
    return nil
end

-- Storage / robbery transfer callbacks

local function startRobberyTake(data)
    if robberyMode ~= true or tonumber(robberyTargetId) == nil or tonumber(robberyTargetId) <= 0 then
        return false, 'no_robbery'
    end
    if blockSpamming == true then
        return false, 'busy'
    end

    data = type(data) == 'table' and data or {}

    if data.weapon == true then
        local weaponId = tonumber(data.item) or tonumber(data.id)
        if not weaponId then return false, 'invalid_weapon' end
        blockSpamming = true
        TriggerServerEvent(
            'jrs_inventory:robbery:takeWeapon',
            weaponId,
            NewInventoryOperationId('robbery_weapon'),
            CurrentRobberyGameHour()
        )
        Citizen.SetTimeout(1200, function()
            if robberyMode == true then blockSpamming = false end
        end)
        return true, 'started'
    end

    local available = tonumber(data.count) or 0
    if available <= 0 then return false, 'empty' end

    local isCurrency = data.item == 'money' or data.item == 'gold' or data.item == 'dirtymoney'
    local itemId = tonumber(data.itemId)
    if not isCurrency and not itemId then return false, 'invalid_item' end

    local function executeTake(amount)
        amount = tonumber(amount)
        if not amount or amount <= 0 or amount > available then
            return false
        end

        if not isCurrency and amount ~= math.floor(amount) then
            return false
        end

        blockSpamming = true
        if data.item == 'money' then
            TriggerServerEvent('jrs_inventory:robbery:takeMoney', amount, NewInventoryOperationId('robbery_money'), CurrentRobberyGameHour())
        elseif data.item == 'gold' then
            TriggerServerEvent('jrs_inventory:robbery:takeGold', amount, NewInventoryOperationId('robbery_gold'), CurrentRobberyGameHour())
        elseif data.item == 'dirtymoney' then
            TriggerServerEvent('jrs_inventory:robbery:takeDirtyMoney', amount, NewInventoryOperationId('robbery_dirtymoney'), CurrentRobberyGameHour())
        else
            TriggerServerEvent('jrs_inventory:robbery:takeItem', itemId, math.floor(amount), NewInventoryOperationId('robbery_item'), CurrentRobberyGameHour())
        end

        Citizen.SetTimeout(1200, function()
            if robberyMode == true then blockSpamming = false end
        end)
        return true
    end

    -- A single item can move immediately. Stacks and currencies ask for quantity
    -- after the user drops them onto the left inventory.
    if not isCurrency and available == 1 then
        return executeTake(1) and true or false, 'started'
    end
    -- Shift held while dropping: take the whole stack, no amount box.
    if data.fullStack == true then
        return executeTake(isCurrency and math.floor(available) or available) and true or false, 'started'
    end

    blockSpamming = true
    transferCount = nil
    waitForInteraction = nil
    SendNUIMessage({ type = 'input_data', status = true, count = available })

    Citizen.CreateThread(function()
        while robberyMode == true and waitForInteraction == nil do
            Citizen.Wait(0)
        end

        if robberyMode ~= true then
            blockSpamming = false
            return
        end

        if waitForInteraction == true then
            local amount = tonumber(transferCount)
            blockSpamming = false
            if not executeTake(amount) then
                exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('wrong_amount'), 'money', 2000)
                SendNUIMessage({ type = 'cleanTransfer', success = false, reason = 'invalid_amount' })
            end
        else
            blockSpamming = false
            SendNUIMessage({ type = 'cleanTransfer', success = false, reason = 'cancelled' })
        end
    end)

    return true, 'prompt'
end

RegisterNUICallback('split_stack', function(data, cb)
    TriggerServerEvent('jrs_inventory:splitStack', tonumber(data.itemId), tonumber(data.count), NewInventoryOperationId('split_stack'))
    cb('ok')
end)

RegisterNUICallback('merge_stacks', function(data, cb)
    TriggerServerEvent('jrs_inventory:mergeStacks', tonumber(data.sourceItemId), tonumber(data.targetItemId), NewInventoryOperationId('merge_stack'))
    cb('ok')
end)

RegisterNUICallback('quick_transfer_to_storage', function(data, cb)
    if robberyMode == true then
        cb('robbery_read_only')
        return
    end
    if id_container == 0 then
        cb('no_storage')
        return
    end

    if Config.IsPersonalItem(data.item) then
        exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('personal_item_locked'), 'bag', 2500)
        cb('blocked')
        return
    end

    local amount = tonumber(data.count) or 0
    if amount <= 0 then
        cb('invalid')
        return
    end

    local isAdminSearch = tostring(id_container or ''):find('^admin_search:') ~= nil
    if data.item == 'money' then
        if Config.AllowMoneyToStorage == false and not isAdminSearch then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('money_storage_transfer_disabled'), 'bag', 2500)
            cb('blocked')
            return
        end
        TriggerServerEvent('jrs_inventory:transfer_money_to_storage', 'money', amount, id_container, NewInventoryOperationId('money_to_storage'))
    elseif data.item == 'gold' then
        if Config.AllowGoldToStorage == false and not isAdminSearch then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('gold_storage_transfer_disabled'), 'bag', 2500)
            cb('blocked')
            return
        end
        TriggerServerEvent('jrs_inventory:transfer_gold_to_storage', 'gold', amount, id_container, NewInventoryOperationId('gold_to_storage'))
    elseif data.item == 'dirtymoney' then
        if Config.AllowDirtyMoneyToStorage == false and not isAdminSearch then
            exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('dirtymoney_storage_transfer_disabled'), 'bag', 2500)
            cb('blocked')
            return
        end
        TriggerServerEvent('jrs_inventory:transfer_dirtymoney_to_storage', 'dirtymoney', amount, id_container, NewInventoryOperationId('dirtymoney_to_storage'))
    elseif data.weapon == true then
        if tonumber(data.used) == 1 then
            exports['jrs_core']:DisplayLeftNotification(_U('inventory'), _U('cant_transfer_equiped_weapon'), 'pistol', 2000)
            cb('equipped')
            return
        end
        TriggerServerEvent('jrs_inventory:transfer_weapon_to_storage', tonumber(data.id), data.item, id_container, NewInventoryOperationId('weapon_to_storage'))
    else
        local currentStorageWeight = tonumber(data.currentSize) or 0
        local itemWeight = tonumber(data.limit) or 0
        if tonumber(size) < currentStorageWeight + (amount * itemWeight) then
            exports['jrs_core']:DisplayLeftNotification(_U('inventory'), _U('no_slots'), 'pistol', 2000)
            cb('full')
            return
        end
        TriggerServerEvent('jrs_inventory:transfer_item_to_storage', data.item, amount, id_container, tonumber(data.itemId), normalizeTransferMetadata(data.metaData), NewInventoryOperationId('item_to_storage'))
    end

    cb('ok')
end)

RegisterNUICallback('quick_transfer_from_storage', function(data, cb)
    if robberyMode == true then
        local started, reason = startRobberyTake(data)
        cb(started and 'ok' or reason)
        return
    end
    if id_container == 0 then
        cb('no_storage')
        return
    end

    local amount = tonumber(data.count) or 0
    if amount <= 0 then
        cb('invalid')
        return
    end

    if data.item == 'money' then
        TriggerServerEvent('jrs_inventory:transfer_money_from_storage', 'money', amount, id_container, NewInventoryOperationId('money_from_storage'))
    elseif data.item == 'gold' then
        TriggerServerEvent('jrs_inventory:transfer_gold_from_storage', 'gold', amount, id_container, NewInventoryOperationId('gold_from_storage'))
    elseif data.item == 'dirtymoney' then
        TriggerServerEvent('jrs_inventory:transfer_dirtymoney_from_storage', 'dirtymoney', amount, id_container, NewInventoryOperationId('dirtymoney_from_storage'))
    elseif data.weapon == true then
        TriggerServerEvent('jrs_inventory:transfer_weapon_from_storage', data.item, id_container, NewInventoryOperationId('weapon_from_storage'))
    else
        local itemWeight = tonumber(data.limit) or 0
        if GetPlayerMaxWeight() < tonumber(count_in_inventory + (amount * itemWeight)) then
            exports['jrs_core']:DisplayLeftNotification(_U('inventory'), _U('no_slots_alt'), 'bag', 2500)
            cb('full')
            return
        end
        TriggerServerEvent('jrs_inventory:transfer_item_from_storage', data.item, amount, id_container, tonumber(data.itemId), normalizeTransferMetadata(data.metaData), NewInventoryOperationId('item_from_storage'))
    end

    cb('ok')
end)



local function getNearbyInventoryPlayers()
    local playerList = {}
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local maxDistance = tonumber(Config.PlayerTransferDistance) or 2.0

    for _, playerIndex in pairs(GetPlayers()) do
        if playerIndex ~= PlayerId() then
            local targetPed = GetPlayerPed(playerIndex)
            if targetPed and targetPed ~= 0 then
                local targetCoords = GetEntityCoords(targetPed)
                local distance = #(myCoords - targetCoords)
                if distance <= maxDistance then
                    table.insert(playerList, {
                        id = GetPlayerServerId(playerIndex),
                        name = GetPlayerName(playerIndex) or ("Player " .. tostring(GetPlayerServerId(playerIndex)))
                    })
                end
            end
        end
    end

    return playerList
end

RegisterNUICallback('multi_get_players', function(_, cb)
    SendNUIMessage({
        type = 'multi_player_table',
        table_p_for_json = getNearbyInventoryPlayers()
    })
    cb('ok')
end)

RegisterNUICallback('multi_transfer_to_storage', function(data, cb)
    if robberyMode == true then
        cb('robbery_read_only')
        return
    end
    if id_container == 0 or type(data.entries) ~= 'table' then
        cb('no_storage')
        return
    end

    local delayMs = tonumber(Config.InventoryUI and Config.InventoryUI.MultiActionDelayMs) or 150
    local storageId = id_container

    Citizen.CreateThread(function()
        -- One request at a time: a fixed delay fired the next transfer while the
        -- previous one still held the storage lock, so most of a big selection
        -- came back "busy" and the rest hit the rate limit.
        local function waitForAnswer(before)
            local deadline = GetGameTimer() + 5000
            while storageTransferResults == before and GetGameTimer() < deadline do
                Citizen.Wait(10)
            end
            Citizen.Wait(delayMs)
        end
        for _, entry in ipairs(data.entries) do
            if id_container ~= storageId then break end
            local before = storageTransferResults
            local sent = false
            if entry.kind == 'item' then
                local itemId = tonumber(entry.id)
                for _, inventoryItem in pairs(inventory_table or {}) do
                    if tonumber(inventoryItem.itemId) == itemId and not Config.IsPersonalItem(inventoryItem.item) then
                        sent = true
                        TriggerServerEvent(
                            'jrs_inventory:transfer_item_to_storage',
                            inventoryItem.item,
                            tonumber(inventoryItem.count) or 1,
                            id_container,
                            itemId,
                            normalizeTransferMetadata(inventoryItem.metaData),
                            NewInventoryOperationId("item_to_storage")
                        )
                        break
                    end
                end
            elseif entry.kind == 'weapon' then
                local weaponId = tonumber(entry.id)
                for _, weapon in pairs(weapon_table or {}) do
                    if tonumber(weapon.id) == weaponId and tonumber(weapon.used) ~= 1 and weapon.used ~= true and not Config.IsPersonalItem(weapon.name) then
                        sent = true
                        TriggerServerEvent('jrs_inventory:transfer_weapon_to_storage', weaponId, weapon.name, id_container, NewInventoryOperationId('weapon_to_storage'))
                        break
                    end
                end
            end
            if sent then waitForAnswer(before) end
        end
    end)

    cb('ok')
end)

RegisterNUICallback('multi_give_to_player', function(data, cb)
    StopGivePlayerSelector(false)
    local target = tonumber(data.target)
    if not target or type(data.entries) ~= 'table' then
        cb('invalid')
        return
    end

    local delayMs = tonumber(Config.InventoryUI and Config.InventoryUI.MultiActionDelayMs) or 500

    Citizen.CreateThread(function()
        TriggerServerEvent('jrs_inventory:turn_ped', target)
        for _, entry in ipairs(data.entries) do
            if entry.kind == 'item' then
                local itemId = tonumber(entry.id)
                for _, inventoryItem in pairs(inventory_table or {}) do
                    if tonumber(inventoryItem.itemId) == itemId and not Config.IsPersonalItem(inventoryItem.item) then
                        TriggerServerEvent('jrs_inventory:transferItem', target, itemId, tonumber(inventoryItem.count) or 1, NewInventoryOperationId('give_item'))
                        break
                    end
                end
            elseif entry.kind == 'weapon' then
                local weaponId = tonumber(entry.id)
                for _, weapon in pairs(weapon_table or {}) do
                    if tonumber(weapon.id) == weaponId and tonumber(weapon.used) ~= 1 and not Config.IsPersonalItem(weapon.name) then
                        TriggerServerEvent('jrs_inventory:transferWeapon', target, weaponId, NewInventoryOperationId('give_weapon'))
                        break
                    end
                end
            end
            Citizen.Wait(delayMs)
        end
    end)

    FinishGiveFlow(true)
    cb('ok')
end)

RegisterNUICallback('multi_delete_items', function(data, cb)
    if robberyMode == true then
        cb('robbery_read_only')
        return
    end
    if type(data.entries) ~= 'table' or #data.entries == 0 then
        cb('invalid')
        return
    end

    local validEntries = {}
    for _, entry in ipairs(data.entries) do
        if entry.kind == 'item' then
            local itemId = tonumber(entry.id)
            for _, inventoryItem in pairs(inventory_table or {}) do
                if tonumber(inventoryItem.itemId) == itemId and not Config.IsPersonalItem(inventoryItem.item) then
                    table.insert(validEntries, {
                        kind = 'item',
                        id = itemId,
                        count = tonumber(inventoryItem.count) or 1
                    })
                    break
                end
            end
        elseif entry.kind == 'weapon' then
            local weaponId = tonumber(entry.id)
            for _, weapon in pairs(weapon_table or {}) do
                if tonumber(weapon.id) == weaponId and tonumber(weapon.used) ~= 1 and not Config.IsPersonalItem(weapon.name) then
                    table.insert(validEntries, {
                        kind = 'weapon',
                        id = weaponId
                    })
                    break
                end
            end
        end
    end

    if #validEntries > 0 then
        TriggerServerEvent('jrs_inventory:multi_delete_items', validEntries)
        exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('inv_items_deleted') or 'تم مسح العناصر المحددة', 'bag', 2500)
    end

    cb('ok')
end)

local function resetCurrencyStorageTransferUi()
	blockSpamming = false
	transferCount = nil
	waitForInteraction = false
	SendNUIMessage({ type = 'cleanTransfer' })
end

local function startCurrencyStorageTransfer(data, toStorage)
	if blockSpamming == true then return false, 'busy' end

	local currency = tostring(data and data.item or ''):lower()
	if currency ~= 'money' and currency ~= 'gold' and currency ~= 'dirtymoney' then return false, 'invalid_currency' end

	if toStorage and currency == 'money' and Config.AllowMoneyToStorage == false then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('money_storage_transfer_disabled'), 'bag', 2500)
		return false, 'blocked'
	end
	if toStorage and currency == 'gold' and Config.AllowGoldToStorage == false then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('gold_storage_transfer_disabled'), 'bag', 2500)
		return false, 'blocked'
	end
	if toStorage and currency == 'dirtymoney' and Config.AllowDirtyMoneyToStorage == false then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('dirtymoney_storage_transfer_disabled'), 'bag', 2500)
		return false, 'blocked'
	end

	local available = tonumber(data.count) or 0
	local containerKey = tostring(id_container or '')
	if available <= 0 or containerKey == '' or containerKey == '0' then return false, 'invalid_request' end

	-- Shift held while dropping: move the whole (whole-number) balance at once.
	-- storageTransferResult from the server unlocks the UI, same as the box path.
	if data.fullStack == true then
		local amount = math.floor(available)
		if amount <= 0 then return false, 'invalid_request' end
		blockSpamming = true
		local action = currency .. (toStorage and '_to_storage' or '_from_storage')
		local eventName = ('jrs_inventory:transfer_%s_%s_storage'):format(currency, toStorage and 'to' or 'from')
		TriggerServerEvent(eventName, currency, amount, id_container, NewInventoryOperationId(action))
		return true, 'started'
	end

	blockSpamming = true
	transferCount = nil
	waitForInteraction = nil
	SendNUIMessage({ type = 'input_data', status = true, count = available })

	Citizen.CreateThread(function()
		while waitForInteraction == nil do Citizen.Wait(0) end

		if waitForInteraction ~= true then
			resetCurrencyStorageTransferUi()
			return
		end

		local amount = tonumber(transferCount)
		if not amount or amount <= 0 or amount ~= math.floor(amount) or amount > available then
			exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('wrong_amount'), 'money', 2000)
			resetCurrencyStorageTransferUi()
			return
		end

		local action = currency .. (toStorage and '_to_storage' or '_from_storage')
		local eventName = ('jrs_inventory:transfer_%s_%s_storage'):format(currency, toStorage and 'to' or 'from')
		TriggerServerEvent(eventName, currency, amount, id_container, NewInventoryOperationId(action))
		-- The server sends jrs_inventory:storageTransferResult after the database
		-- and currency operation finish. That event unlocks the UI.
	end)

	return true, 'started'
end

-- Storage drag/drop transfers (rewritten 2026-09-28).
-- Every path either reaches the server (whose storageTransferResult unlocks
-- the UI) or unlocks the UI itself. The old version left blockSpamming set
-- after a cancelled amount box, a non-integer amount, a full bag or an
-- equipped weapon, so every later drag answered 'busy' and the window froze
-- until it was reopened. A watchdog also unlocks if no answer ever arrives.
local storageTransferSeq = 0
local STORAGE_TRANSFER_WATCHDOG_MS = 6000

local function releaseStorageTransfer(reason)
	blockSpamming = false
	transferCount = nil
	waitForInteraction = false
	SendNUIMessage({ type = 'cleanTransfer', success = false, reason = reason })
end

local function sendStorageTransfer(eventName, ...)
	storageTransferSeq = storageTransferSeq + 1
	local seq = storageTransferSeq
	blockSpamming = true
	TriggerServerEvent(eventName, ...)
	Citizen.SetTimeout(STORAGE_TRANSFER_WATCHDOG_MS, function()
		if seq == storageTransferSeq and blockSpamming == true then
			releaseStorageTransfer('timeout')
		end
	end)
end

local function validStorageSlot(value)
	local slot = tonumber(value)
	if slot and slot >= 1 and slot <= 500 and slot == math.floor(slot) then return slot end
	return nil
end

-- Opens the amount box and calls onAmount(integer) once the player confirms a
-- valid amount; anything else (cancel, close, bad number) unlocks the UI.
local function askStorageAmount(available, onAmount)
	blockSpamming = true
	transferCount = nil
	waitForInteraction = nil
	SendNUIMessage({ type = 'input_data', status = true, count = available })
	Citizen.CreateThread(function()
		local deadline = GetGameTimer() + 120000
		while waitForInteraction == nil and GetGameTimer() < deadline do
			Citizen.Wait(0)
		end
		if waitForInteraction ~= true then
			if waitForInteraction == nil then SendNUIMessage({ type = 'input_data', status = false }) end
			releaseStorageTransfer('cancelled')
			return
		end
		local amount = tonumber(transferCount)
		if not amount or amount <= 0 or amount ~= math.floor(amount) or amount > available then
			exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('wrong_amount'), 'money', 2000)
			releaseStorageTransfer('invalid_amount')
			return
		end
		onAmount(math.floor(amount))
	end)
end

RegisterNUICallback('transfer_from_storage', function(data, cb)
	data = type(data) == 'table' and data or {}
	local targetInventorySlot = validStorageSlot(data.targetInventorySlot)
	if robberyMode == true then
		local started, reason = startRobberyTake(data)
		if not started then SendNUIMessage({ type = 'cleanTransfer', success = false, reason = reason }) end
		cb(started and 'ok' or reason)
		return
	end
	if data.item == 'money' or data.item == 'gold' or data.item == 'dirtymoney' then
		local started, reason = startCurrencyStorageTransfer(data, false)
		if not started and reason ~= 'busy' then releaseStorageTransfer(reason) end
		if not started and reason == 'busy' then SendNUIMessage({ type = 'cleanTransfer' }) end
		cb(started and 'ok' or reason)
		return
	end
	if blockSpamming == true then
		SendNUIMessage({ type = 'cleanTransfer' })
		cb('busy')
		return
	end
	if id_container == 0 or id_container == nil then
		releaseStorageTransfer('no_storage')
		cb('no_storage')
		return
	end

	if data.weapon == true then
		local weaponId = tonumber(data.item) or tonumber(data.id)
		if not weaponId then
			releaseStorageTransfer('invalid_weapon')
			cb('invalid')
			return
		end
		sendStorageTransfer('jrs_inventory:transfer_weapon_from_storage', weaponId, id_container, NewInventoryOperationId('weapon_from_storage'), targetInventorySlot)
		cb('ok')
		return
	end

	local available = math.floor(tonumber(data.count) or 0)
	local itemId = tonumber(data.itemId)
	local itemWeight = tonumber(data.limit) or 0
	if available <= 0 or not itemId then
		releaseStorageTransfer('invalid_item')
		cb('invalid')
		return
	end

	local function send(amount)
		if GetPlayerMaxWeight() < (tonumber(count_in_inventory) or 0) + amount * itemWeight - 0.0001 then
			exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('no_slots_alt'), 'bag', 2500)
			releaseStorageTransfer('full')
			return
		end
		sendStorageTransfer('jrs_inventory:transfer_item_from_storage', data.item, amount, id_container, itemId, normalizeTransferMetadata(data.metaData), NewInventoryOperationId('item_from_storage'), targetInventorySlot)
	end

	if available == 1 or data.fullStack == true then send(available) else askStorageAmount(available, send) end
	cb('ok')
end)

RegisterNUICallback('transfer_to_storage', function(data, cb)
	data = type(data) == 'table' and data or {}
	local targetSlot = validStorageSlot(data.targetSlot)
	if robberyMode == true then
		SendNUIMessage({ type = 'cleanTransfer' })
		cb('robbery_read_only')
		return
	end
	if data.item == 'money' and Config.AllowMoneyToStorage == false then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('money_storage_transfer_disabled'), 'bag', 2500)
		SendNUIMessage({ type = 'cleanTransfer' })
		cb('blocked')
		return
	elseif data.item == 'gold' and Config.AllowGoldToStorage == false then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('gold_storage_transfer_disabled'), 'bag', 2500)
		SendNUIMessage({ type = 'cleanTransfer' })
		cb('blocked')
		return
	elseif data.item == 'dirtymoney' and Config.AllowDirtyMoneyToStorage == false then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('dirtymoney_storage_transfer_disabled'), 'bag', 2500)
		SendNUIMessage({ type = 'cleanTransfer' })
		cb('blocked')
		return
	end
	if Config.IsPersonalItem(data.item) then
		exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('personal_item_locked'), 'bag', 2500)
		SendNUIMessage({ type = 'cleanTransfer' })
		cb('blocked')
		return
	end
	if data.item == 'money' or data.item == 'gold' or data.item == 'dirtymoney' then
		local started, reason = startCurrencyStorageTransfer(data, true)
		if not started and reason ~= 'busy' then releaseStorageTransfer(reason) end
		if not started and reason == 'busy' then SendNUIMessage({ type = 'cleanTransfer' }) end
		cb(started and 'ok' or reason)
		return
	end
	if blockSpamming == true then
		SendNUIMessage({ type = 'cleanTransfer' })
		cb('busy')
		return
	end
	if id_container == 0 or id_container == nil then
		releaseStorageTransfer('no_storage')
		cb('no_storage')
		return
	end

	if data.weapon == true then
		local weaponId = tonumber(data.id)
		if data.used == true or tonumber(data.used) == 1 then
			exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('cant_transfer_equiped_weapon'), 'pistol', 2000)
			releaseStorageTransfer('equipped')
			cb('equipped')
			return
		end
		if not weaponId then
			releaseStorageTransfer('invalid_weapon')
			cb('invalid')
			return
		end
		sendStorageTransfer('jrs_inventory:transfer_weapon_to_storage', weaponId, data.item, id_container, NewInventoryOperationId('weapon_to_storage'), targetSlot)
		cb('ok')
		return
	end

	local available = math.floor(tonumber(data.countInInventory) or tonumber(data.count) or 0)
	local itemId = tonumber(data.itemId)
	local itemWeight = tonumber(data.limit) or 0
	if available <= 0 or not itemId then
		releaseStorageTransfer('invalid_item')
		cb('invalid')
		return
	end

	local function send(amount)
		local used = tonumber(data.size) or 0
		if (tonumber(size) or 0) < used + amount * itemWeight - 0.0001 then
			exports[Config.NotificationResource]:DisplayLeftNotification(_U('inventory'), _U('no_slots'), 'bag', 2500)
			releaseStorageTransfer('full')
			return
		end
		sendStorageTransfer('jrs_inventory:transfer_item_to_storage', data.item, amount, id_container, itemId, normalizeTransferMetadata(data.metaData), NewInventoryOperationId('item_to_storage'), targetSlot)
	end

	if available == 1 or data.fullStack == true then send(available) else askStorageAmount(available, send) end
	cb('ok')
end)

RegisterNUICallback('transferToPlayer', function(data, cb)
	local selectedTarget = tonumber(data and data.target) or tonumber(playerDragId) or 0
	playerDragId = selectedTarget
	idPlayerForItem = selectedTarget

	-- Once a player is selected, the inventory's hidden selector must release
	-- NUI focus immediately. jrs_inputs manages its own focus when needed.
	StopGivePlayerSelector(false)

	local function finishGive(closeInv)
		FinishGiveFlow(closeInv == true)
	end

	local function validAmount(value, available)
		local amount = tonumber(value)
		if not amount or amount <= 0 or amount ~= math.floor(amount) then return nil end
		if amount > (tonumber(available) or 0) then return nil end
		return amount
	end

	if idPlayerForItem == 0 then
		finishGive(false)
		if cb then cb('invalid_target') end
		return
	end

	local target = tonumber(idPlayerForItem)
	local itemType = tostring(data and data.item or ''):lower()

	if itemType == 'money' or itemType == 'gold' or itemType == 'dirtymoney' then
		local title = itemType == 'money' and _U('money') or (itemType == 'gold' and _U('accept') or _U('dirtymoney'))
		local prompt = itemType == 'money' and _U('transfer_money_prompt') or (itemType == 'gold' and _U('transfer_gold_prompt') or _U('transfer_dirtymoney_prompt'))
		OpenInventoryInput(title, prompt, function(value)
			local amount = validAmount(value, data.count)
			if amount then
				TriggerServerEvent('jrs_inventory:turn_ped', target)
				local eventName = itemType == 'money' and 'jrs_inventory:give_money'
					or (itemType == 'gold' and 'jrs_inventory:give_gold' or 'jrs_inventory:give_dirtymoney')
				TriggerServerEvent(eventName, target, amount, GetPlayerServerId(PlayerId()), NewInventoryOperationId('give_' .. itemType))
				finishGive(true)
			else
				finishGive(false)
			end
		end)
		if cb then cb('ok') end
		return
	end

	if data.weapon == false then
		local available = tonumber(data.countInInventory) or tonumber(data.count) or 0
		local itemId = tonumber(data.itemId)
		if available <= 0 or not itemId then
			finishGive(false)
			if cb then cb('invalid_item') end
			return
		end

		if available == 1 then
			finishGive(true)
			TriggerServerEvent('jrs_inventory:turn_ped', target)
			TriggerServerEvent('jrs_inventory:transferItem', target, itemId, 1, NewInventoryOperationId('give_item'))
		else
			OpenInventoryInput(_U('accept'), _U('transfer_items_prompt'), function(value)
				local amount = validAmount(value, available)
				if amount then
					TriggerServerEvent('jrs_inventory:turn_ped', target)
					TriggerServerEvent('jrs_inventory:transferItem', target, itemId, amount, NewInventoryOperationId('give_item'))
					finishGive(true)
				else
					finishGive(false)
				end
			end)
		end
	else
		local weaponId = tonumber(data.id)
		if tonumber(data.used) == 1 then
			exports['jrs_core']:DisplayLeftNotification(_U('inventory'), _U('cant_transfer_equiped_weapon'), 'pistol', 2000)
			finishGive(false)
		elseif not weaponId then
			finishGive(false)
		else
			local found = false
			for _, weapon in pairs(weapon_table or {}) do
				if weaponId == tonumber(weapon.id) then
					found = true
					finishGive(true)
					TriggerServerEvent('jrs_inventory:turn_ped', target)
					TriggerServerEvent('jrs_inventory:transferWeapon', target, weaponId, NewInventoryOperationId('give_weapon'))
					break
				end
			end
			if not found then
				finishGive(false)
				exports['jrs_core']:DisplayLeftNotification(_U('inventory'), _U('transfer_failed'), 'bag', 2000)
			end
		end
	end

	if cb then cb('ok') end
end)

AddEventHandler('jrs_core:language:changed', function(language)
	TriggerServerEvent('jrs_inventory:refreshInventoryLanguage')
end)
