-- ===========================================================================
-- Ground Drops
-- ===========================================================================

local ground_drops = {}
local ground_drop_id = 0
local weaponDropLocks = {}
local itemDropLocks = {}
local GROUND_INTERACTION_DISTANCE = tonumber(Config.GroundInteractionDistance) or 1.0

local function isTrue(value)
    return value == true or value == 1 or value == "1" or tostring(value):lower() == "true"
end

local function notifyInventory(playerId, message)
	if tonumber(playerId) and tonumber(playerId) > 0 then
		TriggerClientEvent("jrsCore:notify", tonumber(playerId), _Up(tonumber(playerId), 'inventory'), message, 'bag', 2500)
	end
end

local function getCharacterData(playerId)
	local src = tonumber(playerId)
	if not src then return nil end
	local User = jrsCore and jrsCore.getUser(src)
	local Character = User and (User.character or User.getUsedCharacter)
	if Character then return Character, Character.identifier, Character.charIdentifier end

	-- See server/weapons.lua's getCharacterData for why this retries: jrs_core
	-- can still be resolving this connection's loaded character for a brief
	-- window even though the player is fully online.
	for _ = 1, 5 do
		if not GetPlayerName(src) then return nil end
		Citizen.Wait(300)
		User = jrsCore and jrsCore.getUser(src)
		Character = User and (User.character or User.getUsedCharacter)
		if Character then return Character, Character.identifier, Character.charIdentifier end
	end
	return nil
end

local function affectedRows(result)
	if type(result) == "number" then return result end
	if type(result) == "table" then
		return tonumber(result.affectedRows or result.changedRows or result.rowCount or result[1]) or 0
	end
	return 0
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

local function decodeDropList(raw)
	if type(raw) == "table" then return raw end
	if type(raw) ~= "string" then return {} end
	local ok, decoded = pcall(json.decode, raw)
	if not ok or type(decoded) ~= "table" then return {} end
	return decoded
end

local function publicDrop(id, drop)
	return {
		id = tonumber(id),
		x = tonumber(drop.x),
		y = tonumber(drop.y),
		z = tonumber(drop.z),
		item = tostring(drop.item or ""):lower(),
		count = drop.count,
		weapon = isTrue(drop.weapon),
		weapon_model = tostring(drop.weapon_model or "none"),
		itemid = drop.itemid,
		serial_number = drop.serial_number,
		metaData = type(JRSInventoryNormalizeMetadata) == "function"
            and JRSInventoryNormalizeMetadata(drop.metaData, tostring(drop.item or ""), false)
            or (type(drop.metaData) == "table" and drop.metaData or {})
	}
end

local function buildMemoryDropList()
	local sendTable = {}
	for _, drop in pairs(ground_drops) do
		table.insert(sendTable, publicDrop(drop.id, drop))
	end
	table.sort(sendTable, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
	return sendTable
end

local function fetchDatabaseDrops(callback)
	exports[Config.MysqlResource]:execute('SELECT * FROM jrs_drops', {}, function(rows)
		local sendTable = {}
		for _, row in pairs(rows or {}) do
			for _, drop in pairs(decodeDropList(row.drop_list)) do
				table.insert(sendTable, publicDrop(row.id, drop))
			end
		end
		table.sort(sendTable, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
		callback(sendTable)
	end)
end

local function sendDrops(target, updateReason)
	target = tonumber(target) or -1
	updateReason = tostring(updateReason or "sync")
	if Config.SaveDrops then
		fetchDatabaseDrops(function(sendTable)
			TriggerClientEvent("jrs_inventory:drop_list", target, #sendTable > 0 and sendTable or false, updateReason)
		end)
	else
		local sendTable = buildMemoryDropList()
		TriggerClientEvent("jrs_inventory:drop_list", target, #sendTable > 0 and sendTable or false, updateReason)
	end
end

local function broadcastDrops(updateReason)
	sendDrops(-1, updateReason)
end

local function validCoordinate(value)
	value = tonumber(value)
	return value ~= nil and value == value and math.abs(value) < 100000.0
end

local function isPlayerNearCoords(playerId, x, y, z, maxDistance)
	if not validCoordinate(x) or not validCoordinate(y) or not validCoordinate(z) then return false end
	local ped = GetPlayerPed(tonumber(playerId))
	if not ped or ped == 0 then
		return false
	end
	local coords = GetEntityCoords(ped)
	if not coords then return false end
	local dx = tonumber(coords.x) - tonumber(x)
	local dy = tonumber(coords.y) - tonumber(y)
	local dz = tonumber(coords.z) - tonumber(z)
	return (dx * dx + dy * dy + dz * dz) <= (maxDistance * maxDistance)
end

local function getAvailableWeaponSlot(playerId, callback)
	local Character, identifier, charid = getCharacterData(playerId)
	if not Character then callback(nil, "player_not_found") return end

	exports[Config.MysqlResource]:execute(
		'SELECT name, slot FROM jrs_weaponloadout WHERE charidentifier=@charidentifier AND identifier=@identifier',
		{ ['charidentifier'] = charid, ['identifier'] = identifier },
		function(rows)
			local count = 0
			local used = {}
			for _, row in pairs(rows or {}) do
				if ShouldCountWeaponTowardLimit(row.name) then count = count + 1 end
				if row.slot then used[tonumber(row.slot)] = true end
			end
			if count >= getMaxWeapons(tonumber(playerId)) then
				callback(nil, "full")
				return
			end
			for _, item in pairs(inv_table[tonumber(playerId)] or {}) do
				if item.slot then used[tonumber(item.slot)] = true end
			end
			local slot = 1
			while used[slot] do slot = slot + 1 end
			callback(slot, nil, identifier, charid)
		end
	)
end

local function findMemoryDrop(dropId)
	for index, drop in ipairs(ground_drops) do
		if tonumber(drop.id) == tonumber(dropId) then
			return index, drop
		end
	end
	return nil, nil
end

-- On resource start, if not saving to DB, clear old DB drops.
if not Config.SaveDrops then
	exports[Config.MysqlResource]:execute("DELETE FROM jrs_drops", {})
end

local function cloneValue(value)
	if type(value) ~= "table" then return value end
	local ok, encoded = pcall(json.encode, value)
	if not ok then return {} end
	local decodedOk, decoded = pcall(json.decode, encoded)
	if not decodedOk or type(decoded) ~= "table" then return {} end
	return decoded
end

local function dropDistanceSquared(first, second)
	local dx = (tonumber(first.x) or 0.0) - (tonumber(second.x) or 0.0)
	local dy = (tonumber(first.y) or 0.0) - (tonumber(second.y) or 0.0)
	local dz = (tonumber(first.z) or 0.0) - (tonumber(second.z) or 0.0)
	return dx * dx + dy * dy + dz * dz
end

local function isDropPositionAvailable(x, y, z, callback)
	-- Multiple drops are intentionally allowed at the same position. Each drop
	-- has its own authoritative ID and lock, so spacing is not an anti-dupe
	-- requirement. The old one-metre block made later drops appear to fail.
	callback(true)
end

local function createGroundDrop(drop, callback)
	if Config.SaveDrops then
		exports[Config.MysqlResource]:execute(
			"INSERT jrs_drops SET drop_list=@drop_list",
			{ ['drop_list'] = json.encode({ drop }) },
			function(result)
				callback(writeSucceeded(result))
			end
		)
		return
	end

	ground_drop_id = ground_drop_id + 1
	drop.id = ground_drop_id
	table.insert(ground_drops, drop)
	callback(true)
end

-- Secure normal item/money/gold/dirty-money drop. Ownership/balance is checked and removed
-- by the server only after the requested position passes the one-metre checks.
local function groundCurrencyType(currencyName)
    if currencyName == "money" then return 0 end
    if currencyName == "gold" then return 1 end
    if currencyName == "dirtymoney" then return 3 end
    return nil
end

local function groundCurrencyBalance(Character, currencyType)
    if not Character then return 0 end
    if currencyType == 0 then return tonumber(Character.money) or 0 end
    if currencyType == 1 then return tonumber(Character.gold) or 0 end
    if currencyType == 3 then return tonumber(Character.dirtymoney) or 0 end
    return 0
end

-- `who` is the player who will read the message, so it resolves in their
-- language rather than the server default.
local function groundCurrencyNotEnough(who, currencyType)
    if currencyType == 0 then return _Up(who, 'not_enough_money') end
    if currencyType == 1 then return _Up(who, 'not_enough_gold') end
    if currencyType == 3 then return _Up(who, 'not_enough_dirtymoney') end
    return _Up(who, 'transfer_failed')
end

local function groundCurrencyLogName(currencyType)
    if currencyType == 0 then return "Money" end
    if currencyType == 1 then return "Gold" end
    if currencyType == 3 then return "Dirty Money" end
    return "Currency"
end

RegisterNetEvent('jrs_inventory:dropGroundItem')
AddEventHandler('jrs_inventory:dropGroundItem', function(dropKind, reference, count, dropCoords, operationId)
	local playerId = tonumber(source)
	dropKind = tostring(dropKind or "")
	count = tonumber(count)

	local function sendResult(success, reason)
		TriggerClientEvent('jrs_inventory:groundDropResult', playerId, success == true, dropKind, reference, reason or "failed")
	end

	if not playerId or not isValidCount(count) or type(dropCoords) ~= "table" then
		sendResult(false, "invalid_request")
		return
	end
	if dropKind ~= "item" and dropKind ~= "money" and dropKind ~= "gold" and dropKind ~= "dirtymoney" then
		sendResult(false, "invalid_request")
		return
	end
	if dropKind == "money" and Config.AllowMoneyGroundDrop == false then
		notifyInventory(playerId, _Up(playerId, 'money_ground_drop_disabled'))
		JRSInventoryLogAction("Security", "Blocked Money Ground Drop", playerId, {
			amount = count,
			operationId = operationId or "legacy",
			reason = "disabled_by_config",
		})
		sendResult(false, "disabled")
		return
	end
	if dropKind == "gold" and Config.AllowGoldGroundDrop == false then
		notifyInventory(playerId, _Up(playerId, 'gold_ground_drop_disabled'))
		JRSInventoryLogAction("Security", "Blocked Gold Ground Drop", playerId, {
			amount = count,
			operationId = operationId or "legacy",
			reason = "disabled_by_config",
		})
		sendResult(false, "disabled")
		return
	end
	if dropKind == "dirtymoney" and Config.AllowDirtyMoneyGroundDrop == false then
		notifyInventory(playerId, _Up(playerId, 'dirtymoney_ground_drop_disabled'))
		JRSInventoryLogAction("Security", "Blocked Dirty Money Ground Drop", playerId, {
			amount = count,
			operationId = operationId or "legacy",
			reason = "disabled_by_config",
		})
		sendResult(false, "disabled")
		return
	end
	if not ClaimInventoryOperation(playerId, operationId, ("drop_ground:%s:%s:%s"):format(dropKind, tostring(reference), tostring(count))) then
		sendResult(false, "replayed")
		return
	end
	if isOnCooldown(playerId) then
		notifyInventory(playerId, _Up(playerId, 'too_fast'))
		sendResult(false, "cooldown")
		return
	end
	if not TryLockInventoryPlayer(playerId) then
		notifyInventory(playerId, _Up(playerId, 'transfer_busy'))
		sendResult(false, "busy")
		return
	end

	local released = false
	local function finish(success, reason)
		if not released then
			UnlockInventoryPlayer(playerId)
			released = true
		end
		sendResult(success, reason)
		if success then broadcastDrops("drop") end
	end

	local x = tonumber(dropCoords.x)
	local y = tonumber(dropCoords.y)
	local z = tonumber(dropCoords.z)
	if not isPlayerNearCoords(playerId, x, y, z, GROUND_INTERACTION_DISTANCE) then
		finish(false, "invalid_position")
		return
	end

	isDropPositionAvailable(x, y, z, function(positionAvailable)
		if not positionAvailable then
			notifyInventory(playerId, _Up(playerId, 'cant_drop_near_items'))
			finish(false, "near_drop")
			return
		end
		if not isPlayerNearCoords(playerId, x, y, z, GROUND_INTERACTION_DISTANCE) then
			finish(false, "invalid_position")
			return
		end

		local Character = getCharacterData(playerId)
		if not Character then
			finish(false, "player_not_loaded")
			return
		end

		if dropKind == "money" or dropKind == "gold" or dropKind == "dirtymoney" then
			local currencyType = groundCurrencyType(dropKind)
			local balance = groundCurrencyBalance(Character, currencyType)
			if not balance or balance < count then
				notifyInventory(playerId, groundCurrencyNotEnough(playerId, currencyType))
				finish(false, "not_enough")
				return
			end

			-- pcall's first value only says "did not throw"; removeCurrency returns
			-- false (without throwing) when the character is not active, and the
			-- drop used to be created anyway = free money on the ground.
			local removedOk, removedResult = pcall(Character.removeCurrency, playerId, currencyType, count)
			if not removedOk or removedResult ~= true then
				finish(false, "currency_remove_failed")
				return
			end

			local drop = {
				x = x, y = y, z = z,
				item = dropKind,
				count = count,
				weapon = false,
				weapon_model = "none"
			}
			createGroundDrop(drop, function(created)
				if not created then
					pcall(Character.addCurrency, playerId, currencyType, count)
					finish(false, "drop_create_failed")
					return
				end
				TriggerEvent("jrs_inventory:get_items_sec", playerId)
				TriggerEvent("jrs_inventory:get_money_sec", playerId)
				JRSInventoryLogAction("Ground", groundCurrencyLogName(currencyType) .. " Dropped On Ground", playerId, {
					item = dropKind,
					amount = count,
					operationId = operationId or "legacy",
					coordinates = ("%.3f, %.3f, %.3f"):format(x, y, z),
				})
				finish(true, "ok")
			end)
			return
		end

		local itemId = tonumber(reference)
		if not itemId then
			finish(false, "invalid_item")
			return
		end

		local inventoryItem
		for _, item in pairs(inv_table[playerId] or {}) do
			if tonumber(item.itemId) == itemId then
				inventoryItem = item
				break
			end
		end
		if not inventoryItem or (tonumber(inventoryItem.count) or 0) < count then
			notifyInventory(playerId, _Up(playerId, 'dont_own_item'))
			finish(false, "not_owned")
			return
		end
		if Config.IsPersonalItem(inventoryItem.item) then
			notifyInventory(playerId, _Up(playerId, 'personal_item_locked'))
			finish(false, "personal_item")
			return
		end
		if Config.IsNoTransferItem(inventoryItem.item) then
			notifyInventory(playerId, _Up(playerId, 'resource_item_locked'))
			finish(false, "resource_item")
			return
		end

		local drop = {
			x = x, y = y, z = z,
			itemid = itemId,
			item = inventoryItem.item,
			count = count,
			metaData = type(JRSInventoryNormalizeMetadata) == "function"
                and JRSInventoryNormalizeMetadata(inventoryItem.metaData, inventoryItem.item, false)
                or cloneValue(inventoryItem.metaData or {}),
			weapon = false,
			weapon_model = "none"
		}

		local removed, removeReason, removeOperation = RemoveInventoryItemByIdDirect(playerId, itemId, count)
		if not removed then
			finish(false, removeReason or "remove_failed")
			return
		end

		if Config.SaveDrops then
			RunInventoryTransaction({
				{
					query = 'UPDATE jrs_characters SET inventory=? WHERE identifier=? AND charidentifier=?',
					values = { json.encode(inv_table[playerId] or {}), Character.identifier, Character.charIdentifier }
				},
				{
					query = 'INSERT INTO jrs_drops (drop_list) VALUES (?)',
					values = { json.encode({ drop }) }
				}
			}, function(created)
				if not created then
					UndoInventoryItemRemoval(playerId, removeOperation)
					finish(false, "drop_create_failed")
					return
				end
				updateItemsInventory(playerId)
				local label = ItemLabelFor(playerId, inventoryItem.item)
				JRSInventoryLogAction("Ground", "Item Dropped On Ground", playerId, {
					item = label .. " (`" .. tostring(inventoryItem.item) .. "`)",
					itemId = itemId,
					amount = count,
					operationId = operationId or "legacy",
					coordinates = ("%.3f, %.3f, %.3f"):format(x, y, z),
					metadata = drop.metaData or {},
				})
				finish(true, "ok")
			end)
			return
		end

		createGroundDrop(drop, function(created)
			if not created then
				UndoInventoryItemRemoval(playerId, removeOperation)
				finish(false, "drop_create_failed")
				return
			end
			SaveInventoryNow(playerId)
			updateItemsInventory(playerId)
			local label = ItemLabelFor(playerId, inventoryItem.item)
			JRSInventoryLogAction("Ground", "Item Dropped On Ground", playerId, {
				item = label .. " (`" .. tostring(inventoryItem.item) .. "`)",
				itemId = itemId,
				amount = count,
				operationId = operationId or "legacy",
				coordinates = ("%.3f, %.3f, %.3f"):format(x, y, z),
				metadata = drop.metaData or {},
			})
			finish(true, "ok")
		end)
	end)
end)

-- Deprecated non-atomic drop creator. All client drops must go through
-- jrs_inventory:dropGroundItem or jrs_inventory:dropGroundWeapon.
RegisterNetEvent('jrs_inventory:upload_drops')
AddEventHandler('jrs_inventory:upload_drops', function()
	if Config.Debug then
		print(("[jrs_inventory] Blocked deprecated upload_drops from %s"):format(tostring(source)))
	end
end)

-- Secure weapon drop: verifies ownership, clears identifier/charidentifier,
-- then creates exactly one ground-drop record containing the weapon database id.
RegisterNetEvent('jrs_inventory:dropGroundWeapon')
AddEventHandler('jrs_inventory:dropGroundWeapon', function(weaponId, dropCoords, operationId)
	local playerId = tonumber(source)
	weaponId = tonumber(weaponId)
	if WeaponSerialSystemReady ~= true or WeaponSerialSystemAvailable ~= true then
		notifyInventory(playerId, _Up(playerId, 'serial_system_not_ready'))
		TriggerClientEvent('jrs_inventory:weaponDropResult', playerId, false, weaponId, "serial_system_unavailable")
		return
	end
	if not playerId or not weaponId or type(dropCoords) ~= "table" then return end
	if not ClaimInventoryOperation(playerId, operationId, ("drop_ground_weapon:%s"):format(tostring(weaponId))) then
		TriggerClientEvent('jrs_inventory:weaponDropResult', playerId, false, weaponId, "replayed")
		return
	end

	local weaponLockKey = "weapon:" .. tostring(weaponId)
	if weaponDropLocks[weaponLockKey] then
		TriggerClientEvent('jrs_inventory:weaponDropResult', playerId, false, weaponId)
		return
	end
	if isOnCooldown(playerId) then
		notifyInventory(playerId, _Up(playerId, 'too_fast'))
		TriggerClientEvent('jrs_inventory:weaponDropResult', playerId, false, weaponId)
		return
	end
	if not TryLockInventoryPlayer(playerId) then
		notifyInventory(playerId, _Up(playerId, 'transfer_busy'))
		TriggerClientEvent('jrs_inventory:weaponDropResult', playerId, false, weaponId)
		return
	end
	weaponDropLocks[weaponLockKey] = true

	local finished = false
	local function finish(success, reason)
		if finished then return end
		finished = true
		weaponDropLocks[weaponLockKey] = nil
		UnlockInventoryPlayer(playerId)
		TriggerClientEvent('jrs_inventory:weaponDropResult', playerId, success == true, weaponId, reason or "failed")
		if success then broadcastDrops("drop") end
	end

	local Character, identifier, charid = getCharacterData(playerId)
	if not Character then
		finish(false, "player_not_loaded")
		return
	end

	local x, y, z = tonumber(dropCoords.x), tonumber(dropCoords.y), tonumber(dropCoords.z)
	if not isPlayerNearCoords(playerId, x, y, z, GROUND_INTERACTION_DISTANCE) then
		finish(false, "invalid_position")
		return
	end

	isDropPositionAvailable(x, y, z, function(positionAvailable)
		if not positionAvailable then
			notifyInventory(playerId, _Up(playerId, 'cant_drop_near_items'))
			finish(false, "near_drop")
			return
		end
		if not isPlayerNearCoords(playerId, x, y, z, GROUND_INTERACTION_DISTANCE) then
			finish(false, "invalid_position")
			return
		end

		exports[Config.MysqlResource]:execute(
			'SELECT id, name, identifier, charidentifier, used, serial_number FROM jrs_weaponloadout WHERE id=@id',
			{ ['id'] = weaponId },
			function(rows)
				local row = rows and rows[1]
				if not row or row.identifier ~= identifier or tonumber(row.charidentifier) ~= tonumber(charid) then
					notifyInventory(playerId, _Up(playerId, 'dont_own_weapon'))
					finish(false, "not_owned")
					return
				end
				local serial = NormalizeWeaponSerial(row.serial_number)
				if not serial then
					RecordInventorySecurityViolation(playerId, "ground_weapon_missing_serial", tostring(weaponId))
					finish(false, "missing_serial")
					return
				end
				if tonumber(row.used) == 1 then
					notifyInventory(playerId, _Up(playerId, 'cant_drop_equiped_weapon'))
					finish(false, "equipped")
					return
				end
				if Config.IsPersonalItem(row.name) then
					notifyInventory(playerId, _Up(playerId, 'personal_item_locked'))
					finish(false, "personal_item")
					return
				end

				exports[Config.MysqlResource]:execute(
					"UPDATE jrs_weaponloadout SET identifier='', charidentifier=0, used=0 WHERE id=@id AND identifier=@identifier AND charidentifier=@charidentifier AND used=0 AND serial_number=@serial_number",
					{ ['id'] = weaponId, ['identifier'] = identifier, ['charidentifier'] = charid, ['serial_number'] = serial },
					function(updateResult)
						if affectedRows(updateResult) <= 0 then
							finish(false, "database_failed")
							return
						end

						local drop = {
							x = x, y = y, z = z,
							item = weaponId,
							count = 1,
							weapon = true,
							weapon_model = row.name,
							serial_number = serial
						}

						createGroundDrop(drop, function(created)
							if not created then
								exports[Config.MysqlResource]:execute(
									"UPDATE jrs_weaponloadout SET identifier=@identifier, charidentifier=@charidentifier WHERE id=@id AND identifier='' AND charidentifier=0 AND serial_number=@serial_number",
									{ ['identifier'] = identifier, ['charidentifier'] = charid, ['id'] = weaponId, ['serial_number'] = serial }
								)
								finish(false, "drop_create_failed")
								return
							end

							TriggerEvent("jrs_inventory:get_items_sec", playerId)
							local label = (function()
								local resolved = ResolveInventoryWeaponName(row.name)
								return (resolved and weaponTableForData[resolved] and weaponTableForData[resolved].label) or row.name
							end)()
							JRSInventoryLogAction("Ground", "Weapon Dropped On Ground", playerId, {
								weapon = label .. " (`" .. tostring(row.name) .. "`)",
								weaponId = weaponId,
								serial = serial,
								operationId = operationId or "legacy",
								coordinates = ("%.3f, %.3f, %.3f"):format(x, y, z),
							})
							finish(true, "ok")
						end)
					end
				)
			end
		)
	end)
end)

local function finishGroundWeaponPickup(playerId, dropId, success, reason)
	weaponDropLocks["drop:" .. tostring(dropId)] = nil
	UnlockInventoryPlayer(playerId)
	TriggerClientEvent('jrs_inventory:weaponPickupResult', playerId, success == true, dropId, reason or "failed")
	if success then broadcastDrops("pickup") end
end

local function claimGroundWeapon(playerId, dropId, drop, removeDrop)
	local weaponId = tonumber(drop.item)
	if not weaponId or drop.weapon ~= true then
		finishGroundWeaponPickup(playerId, dropId, false, "invalid_weapon")
		return
	end
	if not isPlayerNearCoords(playerId, drop.x, drop.y, drop.z, GROUND_INTERACTION_DISTANCE) then
		finishGroundWeaponPickup(playerId, dropId, false, "too_far")
		return
	end

	getAvailableWeaponSlot(playerId, function(slot, reason, identifier, charid)
		if not slot then
			if reason == "full" then notifyInventory(playerId, _Up(playerId, 'cant_hold_more_weapons')) end
			finishGroundWeaponPickup(playerId, dropId, false, reason or "failed")
			return
		end
		if not isPlayerNearCoords(playerId, drop.x, drop.y, drop.z, GROUND_INTERACTION_DISTANCE) then
			finishGroundWeaponPickup(playerId, dropId, false, "too_far")
			return
		end

		exports[Config.MysqlResource]:execute(
			"SELECT id, serial_number FROM jrs_weaponloadout WHERE id=@id AND identifier='' AND charidentifier=0 LIMIT 1",
			{ ['id'] = weaponId },
			function(rows)
				local weapon = rows and rows[1]
				local databaseSerial = NormalizeWeaponSerial(weapon and weapon.serial_number)
				local dropSerial = NormalizeWeaponSerial(drop.serial_number)
				if not weapon or not databaseSerial then
					RecordInventorySecurityViolation(playerId, "ground_weapon_missing_serial", tostring(weaponId))
					finishGroundWeaponPickup(playerId, dropId, false, "missing_serial")
					return
				end
				if dropSerial and dropSerial ~= databaseSerial then
					RecordInventorySecurityViolation(playerId, "ground_weapon_serial_mismatch", tostring(dropId) .. ":" .. dropSerial .. ":" .. databaseSerial)
					finishGroundWeaponPickup(playerId, dropId, false, "serial_mismatch")
					return
				end

				exports[Config.MysqlResource]:execute(
					"UPDATE jrs_weaponloadout SET identifier=@identifier, charidentifier=@charidentifier, slot=@slot, used=0 WHERE id=@id AND identifier='' AND charidentifier=0 AND serial_number=@serial_number",
					{ ['identifier'] = identifier, ['charidentifier'] = charid, ['slot'] = slot, ['id'] = weaponId, ['serial_number'] = databaseSerial },
					function(updateResult)
						if affectedRows(updateResult) <= 0 then
							finishGroundWeaponPickup(playerId, dropId, false, "ownership_failed")
							return
						end

						removeDrop(function(removed)
							if not removed then
								exports[Config.MysqlResource]:execute(
									"UPDATE jrs_weaponloadout SET identifier='', charidentifier=0, used=0 WHERE id=@id AND identifier=@identifier AND charidentifier=@charidentifier AND serial_number=@serial_number",
									{ ['id'] = weaponId, ['identifier'] = identifier, ['charidentifier'] = charid, ['serial_number'] = databaseSerial }
								)
								finishGroundWeaponPickup(playerId, dropId, false, "drop_remove_failed")
								return
							end

							TriggerEvent("jrs_inventory:get_items_sec", playerId)
							local weaponName = tostring(drop.weapon_model or "unknown")
							local label = (function()
								local resolved = ResolveInventoryWeaponName(weaponName)
								return (resolved and weaponTableForData[resolved] and weaponTableForData[resolved].label) or weaponName
							end)()
							JRSInventoryLogAction("Ground", "Weapon Picked Up From Ground", playerId, {
								weapon = label .. " (`" .. weaponName .. "`)",
								weaponId = weaponId,
								serial = databaseSerial,
								dropId = dropId,
								coordinates = ("%.3f, %.3f, %.3f"):format(tonumber(drop.x) or 0.0, tonumber(drop.y) or 0.0, tonumber(drop.z) or 0.0),
							})
							finishGroundWeaponPickup(playerId, dropId, true, "ok")
						end)
					end
				)
			end
		)
	end)
end

-- Secure weapon pickup: assigns identifier + charidentifier before deleting the drop.
RegisterNetEvent('jrs_inventory:pickupGroundWeapon')
AddEventHandler('jrs_inventory:pickupGroundWeapon', function(dropId, operationId)
	local playerId = tonumber(source)
	dropId = tonumber(dropId)
	if WeaponSerialSystemReady ~= true or WeaponSerialSystemAvailable ~= true then
		notifyInventory(playerId, _Up(playerId, 'serial_system_not_ready'))
		TriggerClientEvent('jrs_inventory:weaponPickupResult', playerId, false, dropId, "serial_system_unavailable")
		return
	end
	if not playerId or not dropId then return end
	if not ClaimInventoryOperation(playerId, operationId, ("pickup_ground_weapon:%s"):format(tostring(dropId))) then
		TriggerClientEvent('jrs_inventory:weaponPickupResult', playerId, false, dropId, "replayed")
		return
	end

	local lockKey = "drop:" .. tostring(dropId)
	if weaponDropLocks[lockKey] then
		TriggerClientEvent('jrs_inventory:weaponPickupResult', playerId, false, dropId, "busy")
		return
	end
	if not TryLockInventoryPlayer(playerId) then
		notifyInventory(playerId, _Up(playerId, 'transfer_busy'))
		TriggerClientEvent('jrs_inventory:weaponPickupResult', playerId, false, dropId, "busy")
		return
	end
	weaponDropLocks[lockKey] = true

	if Config.SaveDrops then
		exports[Config.MysqlResource]:execute('SELECT id, drop_list FROM jrs_drops WHERE id=@id', { ['id'] = dropId }, function(rows)
			local row = rows and rows[1]
			local drops = row and decodeDropList(row.drop_list) or {}
			local dropIndex, weaponDrop
			for index, drop in ipairs(drops) do
				if drop.weapon == true then
					dropIndex, weaponDrop = index, drop
					break
				end
			end
			if not weaponDrop then
				finishGroundWeaponPickup(playerId, dropId, false, "not_found")
				return
			end

			claimGroundWeapon(playerId, dropId, weaponDrop, function(done)
				table.remove(drops, dropIndex)
				if #drops == 0 then
					exports[Config.MysqlResource]:execute('DELETE FROM jrs_drops WHERE id=@id', { ['id'] = dropId }, function(result)
						done(affectedRows(result) > 0)
					end)
				else
					exports[Config.MysqlResource]:execute('UPDATE jrs_drops SET drop_list=@drop_list WHERE id=@id', {
						['drop_list'] = json.encode(drops),
						['id'] = dropId
					}, function(result)
						done(writeSucceeded(result))
					end)
				end
			end)
		end)
		return
	end

	local _, drop = findMemoryDrop(dropId)
	if not drop or drop.weapon ~= true then
		finishGroundWeaponPickup(playerId, dropId, false, "not_found")
		return
	end

	claimGroundWeapon(playerId, dropId, drop, function(done)
		local currentIndex, currentDrop = findMemoryDrop(dropId)
		if currentIndex and currentDrop and currentDrop.weapon == true then
			table.remove(ground_drops, currentIndex)
			done(true)
		else
			done(false)
		end
	end)
end)

RegisterServerEvent('jrs_inventory:check_drops')
AddEventHandler('jrs_inventory:check_drops', function(requestedSource)
    local invokedLocally = GetInvokingResource() ~= nil
	local target = invokedLocally and tonumber(requestedSource) or tonumber(source)
	if not target then return end
    if not invokedLocally and not AllowInventoryRequest(target, 'ground_refresh') then return end
    sendDrops(target, "open")
end)

RegisterServerEvent('jrs_inventory:check_drops_1')
AddEventHandler('jrs_inventory:check_drops_1', function()
    local playerId = tonumber(source)
    if not playerId or not AllowInventoryRequest(playerId, 'ground_refresh') then return end
	sendDrops(playerId, "open")
end)

-- Secure non-weapon pickup. Capacity/ownership is validated before the
-- drop is removed, and inventory changes are rolled back if persistence fails.
local function completeGroundItemPickup(playerId, dropId, drop, removeDrop)
	if not isPlayerNearCoords(playerId, drop.x, drop.y, drop.z, GROUND_INTERACTION_DISTANCE) then
		itemDropLocks[dropId] = nil
		UnlockInventoryPlayer(playerId)
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId)
		return
	end

	local User = jrsCore and jrsCore.getUser(playerId)
	local Character = User and (User.character or User.getUsedCharacter)
	if not Character then
		itemDropLocks[dropId] = nil
		UnlockInventoryPlayer(playerId)
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId)
		return
	end

	local itemName = tostring(drop.item or ""):lower()
	local amount = tonumber(drop.count)
	if itemName == "" or not isValidCount(amount) then
		itemDropLocks[dropId] = nil
		UnlockInventoryPlayer(playerId)
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId)
		return
	end

	local function finish(success)
		itemDropLocks[dropId] = nil
		UnlockInventoryPlayer(playerId)
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, success == true, dropId)
		if success then broadcastDrops("pickup") end
	end

	if itemName == "money" or itemName == "gold" or itemName == "dirtymoney" then
		local currencyType = groundCurrencyType(itemName)

		-- Delete the authoritative drop before crediting currency. If the core
		-- rejects the credit, recreate the drop; this prefers temporary loss over
		-- ever leaving the same currency both on the ground and on the player.
		removeDrop(function(removed)
			if not removed then
				finish(false)
				return
			end

			local callOk, addResult = pcall(Character.addCurrency, playerId, currencyType, amount)
			if not callOk or addResult == false then
				createGroundDrop(cloneValue(drop), function(restored)
					if restored then broadcastDrops("restore") end
					finish(false)
				end)
				return
			end

			TriggerEvent("jrs_inventory:get_items_sec", playerId)
			TriggerEvent("jrs_inventory:get_money_sec", playerId)
			JRSInventoryLogAction("Ground", groundCurrencyLogName(currencyType) .. " Picked Up From Ground", playerId, {
				item = itemName,
				amount = amount,
				dropId = dropId,
				coordinates = ("%.3f, %.3f, %.3f"):format(tonumber(drop.x) or 0.0, tonumber(drop.y) or 0.0, tonumber(drop.z) or 0.0),
			})
			finish(true)
		end)
		return
	end

	local added, reason, operation = AddInventoryItemDirect(playerId, itemName, amount, drop.metaData)
	if not added then
		if reason == "full" then notifyInventory(playerId, _Up(playerId, 'no_slots_alt')) end
		finish(false)
		return
	end

	removeDrop(function(removed)
		if not removed then
			UndoInventoryItemAdd(playerId, operation)
			finish(false)
			return
		end
		SaveInventoryNow(playerId)
		updateItemsInventory(playerId)
		local label = ItemLabelFor(playerId, itemName)
		JRSInventoryLogAction("Ground", "Item Picked Up From Ground", playerId, {
			item = label .. " (`" .. itemName .. "`)",
			amount = amount,
			dropId = dropId,
			coordinates = ("%.3f, %.3f, %.3f"):format(tonumber(drop.x) or 0.0, tonumber(drop.y) or 0.0, tonumber(drop.z) or 0.0),
			metadata = drop.metaData or {},
		})
		finish(true)
	end)
end

RegisterNetEvent('jrs_inventory:pickupGroundItem')
AddEventHandler('jrs_inventory:pickupGroundItem', function(dropId, operationId)
	local playerId = tonumber(source)
	dropId = tonumber(dropId)
	if not playerId or not dropId then return end
	if not ClaimInventoryOperation(playerId, operationId, ("pickup_ground_item:%s"):format(tostring(dropId))) then
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId, "replayed")
		return
	end
	if itemDropLocks[dropId] then
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId, "busy")
		return
	end
	if not TryLockInventoryPlayer(playerId) then
		notifyInventory(playerId, _Up(playerId, 'transfer_busy'))
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId)
		return
	end
	itemDropLocks[dropId] = true

	if Config.SaveDrops then
		exports[Config.MysqlResource]:execute('SELECT id, drop_list FROM jrs_drops WHERE id=@id', { ['id'] = dropId }, function(rows)
			local row = rows and rows[1]
			if not row then
				itemDropLocks[dropId] = nil
				UnlockInventoryPlayer(playerId)
				TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId)
				return
			end

			local drops = decodeDropList(row.drop_list)
			local dropIndex, drop
			for index, candidate in ipairs(drops) do
				if candidate.weapon ~= true then
					dropIndex, drop = index, candidate
					break
				end
			end
			if not drop then
				itemDropLocks[dropId] = nil
				UnlockInventoryPlayer(playerId)
				TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId)
				return
			end

			completeGroundItemPickup(playerId, dropId, drop, function(callback)
				table.remove(drops, dropIndex)
				if #drops == 0 then
					exports[Config.MysqlResource]:execute('DELETE FROM jrs_drops WHERE id=@id', { ['id'] = dropId }, function(result)
						callback(affectedRows(result) > 0)
					end)
				else
					exports[Config.MysqlResource]:execute('UPDATE jrs_drops SET drop_list=@drop_list WHERE id=@id', {
						['drop_list'] = json.encode(drops),
						['id'] = dropId
					}, function(result)
						callback(affectedRows(result) > 0)
					end)
				end
			end)
		end)
		return
	end

	local index, drop = findMemoryDrop(dropId)
	if not index or not drop or drop.weapon == true then
		itemDropLocks[dropId] = nil
		UnlockInventoryPlayer(playerId)
		TriggerClientEvent('jrs_inventory:groundItemPickupResult', playerId, false, dropId)
		return
	end

	completeGroundItemPickup(playerId, dropId, drop, function(callback)
		if ground_drops[index] and tonumber(ground_drops[index].id) == dropId then
			table.remove(ground_drops, index)
			callback(true)
		else
			callback(false)
		end
	end)
end)

-- Deprecated non-atomic pickup removal. Secure pickups use
-- jrs_inventory:pickupGroundItem and cannot delete a drop without crediting it.
RegisterServerEvent('jrs_inventory:drop_update')
AddEventHandler('jrs_inventory:drop_update', function()
	if Config.Debug then
		print(("[jrs_inventory] Blocked deprecated drop_update from %s"):format(tostring(source)))
	end
end)

-- Periodic cleanup when SaveDrops is false. Unclaimed weapon rows are removed
-- together with their expired world drop so orphan database records do not accumulate.
if not Config.SaveDrops then
	Citizen.CreateThread(function()
		while true do
			Citizen.Wait(Config.DropCleanupIntervalMs)
			for _, drop in pairs(ground_drops) do
				if drop.weapon == true and tonumber(drop.item) then
					local serial = NormalizeWeaponSerial(drop.serial_number)
					if serial then
						exports[Config.MysqlResource]:execute(
							"DELETE FROM jrs_weaponloadout WHERE id=@id AND identifier='' AND charidentifier=0 AND serial_number=@serial_number",
							{ ['id'] = tonumber(drop.item), ['serial_number'] = serial }
						)
					else
						-- Compatibility for an old in-memory drop created before serials
						-- were enabled. New weapon drops always use the serial guard.
						exports[Config.MysqlResource]:execute(
							"DELETE FROM jrs_weaponloadout WHERE id=@id AND identifier='' AND charidentifier=0",
							{ ['id'] = tonumber(drop.item) }
						)
					end
				end
			end
			ground_drops = {}
			TriggerClientEvent("jrs_inventory:drop_list", -1, false, "cleanup")
			if Config.Debug then print("Ground drops cleared after cleanup interval") end
		end
	end)
end
