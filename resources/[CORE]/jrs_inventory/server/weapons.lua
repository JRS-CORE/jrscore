-- ===========================================================================
-- Weapons (register / give / sub / ammo / condition)
-- ===========================================================================

local function notifyInventory(playerId, message, duration)
	if tonumber(playerId) and tonumber(playerId) > 0 then
		TriggerClientEvent("jrsCore:notify", tonumber(playerId), _Up(tonumber(playerId), 'inventory'), message, 'bag', duration or 2500)
	end
end

local function shouldNotifyTrustedWeaponOperation(sourceResource)
	return tostring(sourceResource or "") ~= "jrs_admin"
end

local function runWeaponOperationCallback(callback, success, reason, data)
	if callback == nil then return end
	local ok, err = pcall(callback, success == true, reason, type(data) == "table" and data or {})
	if not ok and Config.Debug then
		print("[jrs_inventory] weapon operation callback error: " .. tostring(err))
	end
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

local function affectedRows(result)
	if type(result) == "number" then return result end
	if type(result) == "table" then
		return tonumber(result.affectedRows or result.changedRows or result.rowCount or result[1]) or 0
	end
	return 0
end

local function normalizeWeaponName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local upperName = string.upper(tostring(name))
	if type(ResolveInventoryWeaponName) == "function" then
		return ResolveInventoryWeaponName(upperName)
	end
	return upperName
end

local function buildDefaultAmmo(weaponName, ammo)
	if type(ammo) == "table" then return ammo end
	if type(ammo) == "string" then
		local ok, decoded = pcall(json.decode, ammo)
		if ok and type(decoded) == "table" then return decoded end
	end

	local amount = math.max(0, math.floor(tonumber(ammo) or 0))
	if amount <= 0 then return {} end

	local name = string.upper(weaponName or "")
	if string.find(name, "REVOLVER", 1, true) then return { AMMO_REVOLVER = amount } end
	if string.find(name, "PISTOL", 1, true) then return { AMMO_PISTOL = amount } end
	if string.find(name, "REPEATER", 1, true) then return { AMMO_REPEATER = amount } end
	if string.find(name, "SHOTGUN", 1, true) then return { AMMO_SHOTGUN = amount } end
	if string.find(name, "VARMINT", 1, true) then return { AMMO_22 = amount } end
	if string.find(name, "ELEPHANT", 1, true) then return { AMMO_RIFLE_ELEPHANT = amount } end
	if string.find(name, "RIFLE", 1, true) or string.find(name, "SNIPER", 1, true) then return { AMMO_RIFLE = amount } end
	if string.find(name, "BOW", 1, true) then return { AMMO_ARROW = amount } end
	if string.find(name, "THROWING_KNIVES", 1, true) then return { AMMO_THROWING_KNIVES = amount } end
	if string.find(name, "TOMAHAWK", 1, true) then return { AMMO_TOMAHAWK = amount } end
	if string.find(name, "DYNAMITE", 1, true) then return { AMMO_DYNAMITE = amount } end
	if string.find(name, "MOLOTOV", 1, true) then return { AMMO_MOLOTOV = amount } end
	if string.find(name, "BOLAS", 1, true) then return { AMMO_BOLAS = amount } end
	return {}
end

local function normalizeComponents(comps)
	if type(comps) == "table" then return comps end
	if type(comps) == "string" then
		local ok, decoded = pcall(json.decode, comps)
		if ok and type(decoded) == "table" then return decoded end
	end
	return {}
end

local function insertWeaponRecord(parameters, callback, attempt, stolen)
	attempt = tonumber(attempt) or 1
	local serial = stolen and GenerateStolenWeaponSerial() or GenerateWeaponSerial()
	parameters.serial_number = serial

	parameters.stolen = stolen and 1 or 0

	exports[Config.MysqlResource]:execute(
		"INSERT jrs_weaponloadout SET identifier=@identifier, charidentifier=@charidentifier, name=@name, ammo=@ammo, comps=@comps, slot=@slot, used=0, dirtlevel=@dirtlevel, conditionlevel=@conditionlevel, no_break=@no_break, serial_number=@serial_number, stolen=@stolen, package_name=@package_name, custom_name=@custom_name",
		parameters,
		function(result)
			if affectedRows(result) > 0 then
				callback(true, serial, result)
				return
			end

			-- A unique-index collision is extremely unlikely, but retrying keeps
			-- serial creation safe even across multiple concurrent resources.
			if attempt < 5 then
				insertWeaponRecord(parameters, callback, attempt + 1, stolen)
			else
				callback(false, nil, result)
			end
		end
	)
end

local function getAvailableWeaponSlot(playerId, callback, bypassLimit)
	local Character, identifier, charid = getCharacterData(playerId)
	if not Character then
		callback(nil, "player_not_found", nil, nil, { count = 0, maxWeapons = 0 })
		return
	end

	exports[Config.MysqlResource]:execute(
		'SELECT name, slot FROM jrs_weaponloadout WHERE charidentifier = @charidentifier AND identifier = @identifier',
		{ ['charidentifier'] = charid, ['identifier'] = identifier },
		function(existing)
			local used = {}
			local count = 0
			local maxWeapons = tonumber(getMaxWeapons(tonumber(playerId))) or 0
			for _, row in pairs(existing or {}) do
				if ShouldCountWeaponTowardLimit(row.name) then count = count + 1 end
				if row.slot then used[tonumber(row.slot)] = true end
			end

			local limitData = { count = count, maxWeapons = maxWeapons }
			if not bypassLimit and count >= maxWeapons then
				callback(nil, "full", identifier, charid, limitData)
				return
			end

			for _, item in pairs(inv_table[tonumber(playerId)] or {}) do
				if item.slot then used[tonumber(item.slot)] = true end
			end

			local slot = 1
			while used[slot] do slot = slot + 1 end
			callback(slot, nil, identifier, charid, limitData)
		end
	)
end

-- Which callers are waiting on the pause-menu grant event. The event is keyed
-- by player source, so firing it for EVERY weapon ever created meant an
-- unrelated script handing a player a weapon could resolve - and wrongly
-- complete or fail - a store purchase that player had in flight for something
-- else entirely. Only the two callers that actually wait on it are announced.
local GRANT_RESULT_CALLERS = {
	jrs_weapons = true,
	jrs_pausemenu = true,
}

local function runCreateCallback(callback, success, reason, data, invokingResource)
	-- Pause-menu gold store handoff: the createWeaponOwned export receives a
	-- callback that cannot survive the cross-resource border, so report the
	-- result here by player source on the grant event as well.
	local target = (type(data) == "table") and data.target or nil
	if target and GRANT_RESULT_CALLERS[tostring(invokingResource or "")] then
		TriggerEvent('jrs_pausemenu:grant:result', tonumber(target) or target, success == true, reason)
	end
	if callback == nil then return end
	local ok, err = pcall(callback, success == true, reason, data or {})
	if not ok then
		print("[jrs_inventory] createWeaponOwned callback error: " .. tostring(err))
	end
end

local function createWeaponForPlayer(target, name, ammo, comps, callback, sourceResource, noBreak, stolen, forcedComponents, packageName, customName)
	target = tonumber(target)
	local invokingResource = tostring(sourceResource or GetInvokingResource() or "server")

	-- Serial numbers are mandatory for every newly-created weapon. Wait for the
	-- database migration instead of inserting an untracked weapon row.
	if WeaponSerialSystemReady ~= true then
		WhenWeaponSerialSystemReady(function(available)
			if available then
				createWeaponForPlayer(target, name, ammo, comps, callback, invokingResource, noBreak, stolen, forcedComponents, packageName, customName)
			else
				if shouldNotifyTrustedWeaponOperation(invokingResource) then
					notifyInventory(target, _Up(target, 'weapon_serial_migration_failed'))
				end
				runCreateCallback(callback, false, "serial_system_unavailable", { target = target }, invokingResource)
			end
		end)
		return true
	end
	if WeaponSerialSystemAvailable ~= true then
		if shouldNotifyTrustedWeaponOperation(invokingResource) then
			notifyInventory(target, _Up(target, 'weapon_serial_migration_failed'))
		end
		runCreateCallback(callback, false, "serial_system_unavailable", { target = target }, invokingResource)
		return false
	end

	local Character = getCharacterData(target)
	if not Character then
		runCreateCallback(callback, false, "player_not_found", { target = target }, invokingResource)
		return false
	end

	local normalizedName = normalizeWeaponName(name)
	if not normalizedName then
		if shouldNotifyTrustedWeaponOperation(invokingResource) then
			notifyInventory(target, _Up(target, 'inventory_invalid_weapon_name') .. tostring(name))
		end
		runCreateCallback(callback, false, "invalid_weapon", { target = target, weapon = tostring(name) }, invokingResource)
		return false
	end

	if not TryLockInventoryPlayer(target) then
		if shouldNotifyTrustedWeaponOperation(invokingResource) then
			notifyInventory(target, _Up(target, 'transfer_busy'))
		end
		runCreateCallback(callback, false, "busy", { target = target, weapon = normalizedName }, invokingResource)
		return false
	end
	local released = false
	local function releaseCreateLock()
		if not released then
			released = true
			UnlockInventoryPlayer(target)
		end
	end

	local bypassLimit = (noBreak == true)
		or (packageName ~= nil and packageName ~= "")
		or (customName ~= nil and customName ~= "")
		or (sourceResource == "jrs_weapons_bundle")
		or (sourceResource == "jrs_weapons_single")
		or (sourceResource == "jrs_pausemenu")
		or (sourceResource == "jrs_admin")
		or (type(IsUtilityWeapon) == "function" and IsUtilityWeapon(normalizedName))

	getAvailableWeaponSlot(target, function(slot, reason, identifier, charid, limitData)
		if not slot then
			releaseCreateLock()
			if reason == "full" and shouldNotifyTrustedWeaponOperation(invokingResource) then
				notifyInventory(target, _Up(target, 'cant_hold_more_weapons'))
			end
			local data = limitData or {}
			data.target = target
			data.weapon = normalizedName
			runCreateCallback(callback, false, reason or "failed", data, invokingResource)
			return
		end

		local ammoTable = buildDefaultAmmo(normalizedName, ammo)
		local componentTable = normalizeComponents(comps)
		if stolen and type(forcedComponents) == "table" then
			-- Black Market weapons always render with their forced (worn/dark)
			-- look, regardless of whatever comps the caller passed in.
			for category, componentName in pairs(forcedComponents) do
				componentTable[category] = componentName
			end
		end
		insertWeaponRecord({
			['identifier'] = identifier,
			['charidentifier'] = charid,
			['name'] = normalizedName,
			['ammo'] = json.encode(ammoTable),
			['comps'] = json.encode(componentTable),
			['slot'] = slot,
			['dirtlevel'] = 0.0,
			['conditionlevel'] = 1.0,
			['no_break'] = noBreak and 1 or 0,
			['package_name'] = packageName or '',
			['custom_name'] = customName or ''
		}, function(success, serial, result)
			releaseCreateLock()
			if not success then
				runCreateCallback(callback, false, "database_error", {
					target = target,
					weapon = normalizedName,
					slot = slot
				}, invokingResource)
				return
			end

			TriggerEvent("jrs_inventory:get_items_sec", target)
			local data = limitData or {}
			data.target = target
			data.weapon = normalizedName
			data.slot = slot
			data.ammo = ammoTable
			data.serial_number = serial
			data.stolen = stolen == true
			local label = (customName and customName ~= "") and customName
				or ((weaponTableForData[normalizedName] and weaponTableForData[normalizedName].label) or normalizedName)
			JRSInventoryLogAction("Weapons", "Weapon Added", target, {
				weapon = label .. " (`" .. normalizedName .. "`)",
				serial = serial,
				stolen = stolen == true,
				amount = 1,
				slot = slot,
				ammo = ammoTable,
				sourceResource = invokingResource,
			})
			if shouldNotifyTrustedWeaponOperation(invokingResource) then
				notifyInventory(target, _Up(target, 'weapon_added', label, tostring(serial or 'N/A')), 4500)
			end
			runCreateCallback(callback, true, "success", data, invokingResource)
		end, nil, stolen)
	end, bypassLimit)
	return true
end

-- Server-only export used by jrs_core and other trusted resources.
-- The optional callback receives: success, reason, data.
exports('createWeaponOwned', function(target, name, ammo, comps, callback, context)
	local sourceResource = type(context) == "table" and context.sourceResource or context
	local noBreak = type(context) == "table" and context.noBreak == true
	local stolen = type(context) == "table" and context.stolen == true
	local forcedComponents = type(context) == "table" and type(context.forcedComponents) == "table" and context.forcedComponents or nil
	local packageName = type(context) == "table" and type(context.packageName) == "string" and context.packageName:sub(1, 64) or nil
	local customName = type(context) == "table" and type(context.customName) == "string" and context.customName:sub(1, 100) or nil
	if packageName == "" then packageName = nil end
	if customName == "" then customName = nil end
	return createWeaponForPlayer(target, name, ammo, comps, callback, sourceResource, noBreak, stolen, forcedComponents, packageName, customName)
end)

-- Server-local compatibility event. It is intentionally not registered as a
-- network event, so clients cannot create weapons for themselves.
AddEventHandler('jrsCore:registerWeapon', function(target, name, ammo, comps, sourceResource)
	target = tonumber(target)
	if not target then return end
	createWeaponForPlayer(target, name, ammo, comps, nil, sourceResource)
end)

local function processWeaponTransfer(ownerSource, weaponid, target, requirePlayerDistance, operationId)
	local invokingResource = GetInvokingResource() or "server"
	ownerSource = tonumber(ownerSource)
	weaponid = tonumber(weaponid)
	target = tonumber(target) or 0
	if not ownerSource or not weaponid then return end

	local playerTransfer = target > 0 and target ~= ownerSource
	local destination = playerTransfer and target or ownerSource
	local locked = false

	local function result(success, reason, weaponName)
		if locked then
			UnlockInventoryPlayers(ownerSource, destination)
			locked = false
		end
		if requirePlayerDistance then
			TriggerClientEvent('jrs_inventory:weaponTransferResult', ownerSource, success == true, reason or "failed", weaponid, weaponName)
		end
	end

	if WeaponSerialSystemReady ~= true or WeaponSerialSystemAvailable ~= true then
		notifyInventory(ownerSource, _Up(ownerSource, 'serial_system_not_ready'))
		result(false, "serial_system_unavailable")
		return
	end

	if playerTransfer then
		if not isValidTarget(destination) then
			notifyInventory(ownerSource, _Up(ownerSource, 'invalid_target'))
			result(false, "invalid_target")
			return
		end
		if requirePlayerDistance and not ArePlayersWithinTransferDistance(ownerSource, destination) then
			notifyInventory(ownerSource, _Up(ownerSource, 'target_too_far'))
			result(false, "too_far")
			return
		end
		if not TryLockInventoryPlayers(ownerSource, destination) then
			notifyInventory(ownerSource, _Up(ownerSource, 'transfer_busy'))
			result(false, "busy")
			return
		end
		locked = true
	end

	local OwnerCharacter, ownerIdentifier, ownerCharid = getCharacterData(ownerSource)
	if not OwnerCharacter then
		result(false, "owner_not_loaded")
		return
	end

	exports[Config.MysqlResource]:execute(
		'SELECT id, identifier, charidentifier, name, used, serial_number FROM jrs_weaponloadout WHERE id = @id',
		{ ['id'] = weaponid },
		function(rows)
			local row = rows and rows[1]
			if not row then
				notifyInventory(ownerSource, _Up(ownerSource, 'dont_own_weapon'))
				result(false, "not_found")
				return
			end
			if tonumber(row.used) == 1 then
				notifyInventory(ownerSource, _Up(ownerSource, 'unequip_first'))
				result(false, "equipped", row.name)
				return
			end

			local serial = NormalizeWeaponSerial(row.serial_number)
			if not serial then
				RecordInventorySecurityViolation(ownerSource, "weapon_missing_serial", tostring(weaponid))
				notifyInventory(ownerSource, _Up(ownerSource, 'weapon_serial_missing'))
				result(false, "missing_serial", row.name)
				return
			end

			if playerTransfer then
				if row.identifier ~= ownerIdentifier or tonumber(row.charidentifier) ~= tonumber(ownerCharid) then
					notifyInventory(ownerSource, _Up(ownerSource, 'dont_own_weapon'))
					result(false, "not_owned", row.name)
					return
				end
				if Config.IsPersonalItem(row.name) then
					notifyInventory(ownerSource, _Up(ownerSource, 'personal_item_locked'))
					result(false, "personal_item", row.name)
					return
				end
				if requirePlayerDistance and not ArePlayersWithinTransferDistance(ownerSource, destination) then
					notifyInventory(ownerSource, _Up(ownerSource, 'target_too_far'))
					result(false, "too_far", row.name)
					return
				end
			end

			local DestinationCharacter = getCharacterData(destination)
			if not DestinationCharacter then
				notifyInventory(ownerSource, _Up(ownerSource, 'invalid_target'))
				result(false, "target_not_loaded", row.name)
				return
			end

			getAvailableWeaponSlot(destination, function(slot, reason, destinationIdentifier, destinationCharid, limitData)
				if not slot then
					if reason == "full" then
						notifyInventory(ownerSource, _Up(ownerSource, 'target_cant_hold_more_weapons'))
						if destination ~= ownerSource then
							notifyInventory(destination, _Up(destination, 'cant_hold_more_weapons'))
						end
					end
					result(false, reason or "failed", row.name)
					return
				end

				if playerTransfer and requirePlayerDistance and not ArePlayersWithinTransferDistance(ownerSource, destination) then
					notifyInventory(ownerSource, _Up(ownerSource, 'target_too_far'))
					result(false, "too_far", row.name)
					return
				end

				local query
				local params = {
					['destinationIdentifier'] = destinationIdentifier,
					['destinationCharid'] = destinationCharid,
					['slot'] = slot,
					['id'] = weaponid,
					['serial_number'] = serial
				}

				if playerTransfer then
					query = "UPDATE jrs_weaponloadout SET identifier=@destinationIdentifier, charidentifier=@destinationCharid, slot=@slot, used=0 WHERE id=@id AND identifier=@ownerIdentifier AND charidentifier=@ownerCharid AND used=0 AND serial_number=@serial_number"
					params.ownerIdentifier = ownerIdentifier
					params.ownerCharid = ownerCharid
				else
					-- Trusted storage/ground compatibility path: reclaim an unowned weapon.
					query = "UPDATE jrs_weaponloadout SET identifier=@destinationIdentifier, charidentifier=@destinationCharid, slot=@slot, used=0 WHERE id=@id AND identifier='' AND charidentifier=0 AND serial_number=@serial_number"
				end

				exports[Config.MysqlResource]:execute(query, params, function(updateResult)
					if affectedRows(updateResult) <= 0 then
						notifyInventory(ownerSource, _Up(ownerSource, 'transfer_failed'))
						result(false, "database_failed", row.name)
						return
					end

					TriggerEvent("jrs_inventory:get_items_sec", ownerSource)
					if destination ~= ownerSource then
						Citizen.SetTimeout(100, function()
							TriggerEvent("jrs_inventory:get_items_sec", destination)
						end)
						local label = (weaponTableForData[row.name] and weaponTableForData[row.name].label) or row.name
						notifyInventory(ownerSource, _Up(ownerSource, 'gave_weapon', label), 3000)
						notifyInventory(destination, _Up(destination, 'received_weapon', label), 3000)
						JRSInventoryLogAction("Weapons", "Weapon Given To Player", ownerSource, {
							target = destination,
							weapon = label .. " (`" .. tostring(row.name) .. "`)",
							weaponId = weaponid,
							serial = serial,
							amount = 1,
							operationId = operationId or "server",
							sourceResource = invokingResource,
						})
					end
					result(true, "ok", row.name)
				end)
			end)
		end
	)
end

-- Trusted server-local compatibility event used by storage and the API.
-- Client calls are redirected to the validated player-transfer path and the
-- claimed source argument is never trusted.
AddEventHandler('jrsCore:giveWeapon', function(claimedSource, weaponid, target)
	processWeaponTransfer(tonumber(claimedSource), weaponid, target, false, nil)
end)

RegisterNetEvent('jrs_inventory:transferWeapon')
AddEventHandler('jrs_inventory:transferWeapon', function(target, weaponid, operationId)
	local ownerSource = tonumber(source)
	if not ownerSource then return end
	if not ClaimInventoryOperation(ownerSource, operationId, ("give_weapon:%s:%s"):format(tostring(target), tostring(weaponid))) then
		notifyInventory(ownerSource, _Up(ownerSource, 'transfer_busy'))
		TriggerClientEvent('jrs_inventory:weaponTransferResult', ownerSource, false, "replayed", tonumber(weaponid))
		return
	end
	if isOnCooldown(ownerSource) then
		notifyInventory(ownerSource, _Up(ownerSource, 'too_fast'))
		TriggerClientEvent('jrs_inventory:weaponTransferResult', ownerSource, false, "cooldown", tonumber(weaponid))
		return
	end
	processWeaponTransfer(ownerSource, weaponid, target, true, operationId)
end)

-- Deprecated insecure pickup event. Ground weapon pickup is handled atomically
-- by jrs_inventory:pickupGroundWeapon in server/ground.lua.
RegisterServerEvent('jrsCore:giveWeapon_dropped')
AddEventHandler('jrsCore:giveWeapon_dropped', function()
	if Config.Debug then
		print("[jrs_inventory] Blocked deprecated jrsCore:giveWeapon_dropped event")
	end
end)

-- Trusted server-local subtraction used by the inventory API/storage.
-- Clients cannot disown arbitrary weapon rows through this event.
AddEventHandler('jrsCore:subWeapon', function(claimedSource, weaponid, callback, sourceResource)
	local ownerSource = tonumber(claimedSource)
	weaponid = tonumber(weaponid)
	local invokingResource = tostring(sourceResource or GetInvokingResource() or "server")
	if not ownerSource or not weaponid then
		runWeaponOperationCallback(callback, false, "invalid_request", { weaponId = weaponid })
		return
	end
	if WeaponSerialSystemReady ~= true or WeaponSerialSystemAvailable ~= true then
		if shouldNotifyTrustedWeaponOperation(invokingResource) then
			notifyInventory(ownerSource, _Up(ownerSource, 'serial_system_not_ready'))
		end
		runWeaponOperationCallback(callback, false, "serial_system_unavailable", { weaponId = weaponid })
		return
	end

	local Character, identifier, charid = getCharacterData(ownerSource)
	if not Character then
		runWeaponOperationCallback(callback, false, "player_not_found", { weaponId = weaponid })
		return
	end

	exports[Config.MysqlResource]:execute(
		'SELECT name, identifier, charidentifier, used, serial_number FROM jrs_weaponloadout WHERE id=@id',
		{ ['id'] = weaponid },
		function(rows)
			local row = rows and rows[1]
			if not row then
				if shouldNotifyTrustedWeaponOperation(invokingResource) then notifyInventory(ownerSource, _Up(ownerSource, 'dont_own_weapon')) end
				runWeaponOperationCallback(callback, false, "not_found", { weaponId = weaponid })
				return
			end
			if row.identifier ~= identifier or tonumber(row.charidentifier) ~= tonumber(charid) then
				if shouldNotifyTrustedWeaponOperation(invokingResource) then notifyInventory(ownerSource, _Up(ownerSource, 'dont_own_weapon')) end
				runWeaponOperationCallback(callback, false, "not_owner", { weaponId = weaponid })
				return
			end
			if tonumber(row.used) == 1 then
				if shouldNotifyTrustedWeaponOperation(invokingResource) then notifyInventory(ownerSource, _Up(ownerSource, 'unequip_first')) end
				runWeaponOperationCallback(callback, false, "equipped", { weaponId = weaponid, weapon = row.name })
				return
			end

			local serial = NormalizeWeaponSerial(row.serial_number)
			if not serial then
				RecordInventorySecurityViolation(ownerSource, "weapon_missing_serial", tostring(weaponid))
				if shouldNotifyTrustedWeaponOperation(invokingResource) then notifyInventory(ownerSource, _Up(ownerSource, 'weapon_serial_missing')) end
				runWeaponOperationCallback(callback, false, "serial_missing", { weaponId = weaponid, weapon = row.name })
				return
			end

			exports[Config.MysqlResource]:execute(
				"UPDATE jrs_weaponloadout SET identifier='', charidentifier=0, used=0 WHERE id=@id AND identifier=@identifier AND charidentifier=@charidentifier AND serial_number=@serial_number",
				{ ['id'] = weaponid, ['identifier'] = identifier, ['charidentifier'] = charid, ['serial_number'] = serial },
				function(result)
					if affectedRows(result) <= 0 then
						runWeaponOperationCallback(callback, false, "database_error", {
							weaponId = weaponid,
							weapon = row.name,
							serial_number = serial,
						})
						return
					end
					TriggerClientEvent("jrs_inventory:remove_wepo", ownerSource, row.name)
					TriggerEvent("jrs_inventory:get_items_sec", ownerSource)
					local label = (weaponTableForData[row.name] and weaponTableForData[row.name].label) or row.name
					JRSInventoryLogAction("Weapons", "Weapon Removed", ownerSource, {
						weapon = label .. " (`" .. tostring(row.name) .. "`)",
						weaponId = weaponid,
						serial = serial,
						sourceResource = invokingResource,
					})
					if shouldNotifyTrustedWeaponOperation(invokingResource) then
						notifyInventory(ownerSource, _Up(ownerSource, 'weapon_removed', label, serial), 4500)
					end
					runWeaponOperationCallback(callback, true, "success", {
						weaponId = weaponid,
						weapon = row.name,
						label = label,
						serial_number = serial,
					})
				end
			)
		end
	)
end)

-- ===========================================================================
-- Weapon state
-- ===========================================================================

RegisterServerEvent('jrs_inventory:send_state_weapon')
AddEventHandler('jrs_inventory:send_state_weapon', function(wepid, state, token)
    local src = tonumber(source)
    if not src then return end
    local weaponId, nextState = tonumber(wepid), tonumber(state)
    local function reply(success, reason)
        if type(token) == 'string' and #token <= 128 then
            TriggerClientEvent('jrs_inventory:weaponStateResult', src, token, weaponId, nextState, success, reason)
        end
    end
    if not AllowInventoryRequest(src, 'weapon_state') then reply(false, 'rate_limited'); return end
    if tonumber(state) == 1 and Player(src).state.jrsArena == true then reply(false, 'arena'); return end -- jrs_fightarena
    if not weaponId or weaponId < 1 or weaponId % 1 ~= 0 or (nextState ~= 0 and nextState ~= 1) then
        RecordInventorySecurityViolation(src, 'invalid_weapon_state', tostring(wepid) .. ':' .. tostring(state))
        reply(false, 'invalid_state')
        return
    end
    local ownedWeapon = nil
    for _, weapon in pairs(weapon_table[src] or {}) do
        if tonumber(weapon.id) == weaponId then ownedWeapon = weapon; break end
    end
    if not ownedWeapon then
        RecordInventorySecurityViolation(src, 'weapon_state_not_owned', tostring(weaponId))
        reply(false, 'not_owned')
        return
    end

    -- Equipping (not unequipping) is blocked inside safe zones.
    if nextState == 1 then
        if GetResourceState('jrs_safezone') == 'started' then
            local ok, blocked = pcall(function()
                return exports['jrs_safezone']:IsWeaponBlockedForPlayer(src, ownedWeapon and ownedWeapon.name)
            end)
            if ok and blocked == true then
                notifyInventory(src, _Up(src, 'weapon_blocked_in_safezone'), 4000)
                reply(false, 'safezone_blocked')
                return
            end
        end
    end

    -- Equipping (not unequipping) is gated by the same level jrs_weapons
    -- requires to buy the weapon, unless it was created outside the normal
    -- gunsmith flow (Custom Weapon Package Store / pause-menu gold store),
    -- which is flagged with weaponloadout.no_break = 1 and stays exempt.
    if nextState == 1 and not (ownedWeapon.no_break == true) then
        local requiredLevel = 0
        if GetResourceState('jrs_weapons') == 'started' then
            local ok, lvl = pcall(function() return exports.jrs_weapons:GetWeaponRequiredLevel(ownedWeapon.name) end)
            if ok then requiredLevel = math.max(0, math.floor(tonumber(lvl) or 0)) end
        end
        if requiredLevel > 0 then
            local playerLevel = 1
            if GetResourceState('jrs_core') == 'started' then
                local ok, lvl = pcall(function() return exports.jrs_core:GetLevel(src) end)
                if ok then playerLevel = math.max(1, math.floor(tonumber(lvl) or 1)) end
            end
            if playerLevel < requiredLevel then
                notifyInventory(src, _Up(src, 'weapon_level_required', requiredLevel), 4500)
                reply(false, 'level_required')
                return
            end
        end
    end

    local Character = jrsCore.GetCharacter(src)
    if not Character then reply(false, 'character_unavailable'); return end
    local params = {identifier = Character.identifier, charidentifier = Character.charIdentifier, id = weaponId, used = nextState}
    local function finish(success)
        if success then
            for _, weapon in pairs(weapon_table[src] or {}) do
                if tonumber(weapon.id) == weaponId then weapon.used = nextState; break end
            end
        end
        -- Acknowledge before the heavier inventory refresh, including failures.
        reply(success, success and 'success' or 'state_not_saved')
        if not success then return end
        TriggerEvent('jrs_inventory:get_items_sec', src)
        if DiscordLogConfig and DiscordLogConfig.LogWeaponStateChanges == true then
            JRSInventoryLogAction('Usage', nextState == 1 and 'Weapon Equipped' or 'Weapon Unequipped', src, {
                weaponId = weaponId, state = nextState,
            })
        end
    end
    exports[Config.MysqlResource]:execute(
        'UPDATE jrs_weaponloadout SET used = @used WHERE identifier = @identifier AND charidentifier = @charidentifier AND id = @id', params,
        function(result)
            if affectedRows(result) > 0 then finish(true); return end
            -- Repeated requests can change zero rows; verify ownership and state.
            exports[Config.MysqlResource]:execute(
                'SELECT id FROM jrs_weaponloadout WHERE identifier = @identifier AND charidentifier = @charidentifier AND id = @id AND used = @used', params,
                function(rows) finish(type(rows) == 'table' and rows[1] ~= nil) end)
        end)
end)

RegisterServerEvent('jrs_inventory:set_all_weapons_unequipped')
AddEventHandler('jrs_inventory:set_all_weapons_unequipped', function()
	local src = tonumber(source)
    if not src or not AllowInventoryRequest(src, 'weapon_state') then return end
	local Character = jrsCore.GetCharacter(tonumber(src))
	if not Character then return end
	local identifier = Character.identifier
	local charid = Character.charIdentifier

	exports[Config.MysqlResource]:execute(
		"UPDATE jrs_weaponloadout SET used = 0 WHERE identifier = @identifier AND charidentifier = @charidentifier",
		{
			['identifier'] = identifier,
			['charidentifier'] = charid,
		},
		function()
			-- Refresh the client-side inventory so every weapon immediately appears
			-- as stored in the bag rather than equipped in the weapon wheel.
			TriggerEvent('jrs_inventory:get_items_sec', tonumber(src))
		end
	)
end)

-- ===========================================================================
-- Ammo save
-- ===========================================================================

JRSInventoryAmmoRevisions = JRSInventoryAmmoRevisions or {}

-- Serialize ammo writes per weapon. A refill can arrive while an older periodic
-- save is still being written; this queue guarantees the newest accepted value
-- is always the final database write for that weapon.
local ammoWriteQueues = {}

local function sanitizeWeaponAmmoTable(ammoTable)
	local clean = {}
	if type(ammoTable) ~= 'table' then return clean end

    local settings = type(Config.Security) == 'table' and Config.Security or {}
    local maxEntries = math.max(1, math.floor(tonumber(settings.MaxAmmoEntries) or 32))
    local maxPerType = math.max(0, math.floor(tonumber(settings.MaxAmmoPerType) or 999))
    local accepted = 0
	for key, value in pairs(ammoTable) do
		local numberValue = tonumber(value)
		if type(key) == 'string'
            and #key <= 64
            and key:match('^AMMO_[%w_]+$')
            and numberValue ~= nil
            and accepted < maxEntries then
			clean[key] = math.max(0, math.min(maxPerType, math.floor(numberValue)))
            accepted = accepted + 1
		end
	end
	return clean
end

local function getCachedWeapon(src, weaponId)
    src = tonumber(src)
    weaponId = tonumber(weaponId)
    if not src or not weaponId then return nil end
    for _, weapon in pairs(weapon_table[src] or {}) do
        if tonumber(weapon.id) == weaponId then return weapon end
    end
    return nil
end

local function decodeWeaponAmmo(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end

-- Periodic client saves may only consume ammo and weapon condition. Any refill
-- or repair must use the trusted server export below, so a modified client
-- cannot manufacture ammunition or restore a weapon by sending larger values.
local function clampClientWeaponState(src, weaponId, proposedAmmo, proposedCondition)
    local cachedWeapon = getCachedWeapon(src, weaponId)
    if not cachedWeapon then return nil, nil, false end

    local previousAmmo = sanitizeWeaponAmmoTable(decodeWeaponAmmo(cachedWeapon.ammo))
    local submittedAmmo = sanitizeWeaponAmmoTable(proposedAmmo)
    local acceptedAmmo = {}
    local attemptedIncrease = false

    for key, previousValue in pairs(previousAmmo) do
        acceptedAmmo[key] = tonumber(previousValue) or 0
    end
    for key, submittedValue in pairs(submittedAmmo) do
        local previousValue = tonumber(previousAmmo[key]) or 0
        local nextValue = math.min(previousValue, tonumber(submittedValue) or 0)
        if (tonumber(submittedValue) or 0) > previousValue then attemptedIncrease = true end
        acceptedAmmo[key] = math.max(0, math.floor(nextValue))
    end

    local previousCondition = tonumber(cachedWeapon.conditionlevel)
        or tonumber(cachedWeapon.dirtlevel)
        or 100
    previousCondition = math.max(0, math.min(100, previousCondition))
    local submittedCondition = math.max(0, math.min(100, tonumber(proposedCondition) or previousCondition))
    if submittedCondition > previousCondition then attemptedIncrease = true end

    return acceptedAmmo, math.min(previousCondition, submittedCondition), attemptedIncrease
end

local function currentAmmoRevision(src, weaponId)
	src = tonumber(src)
	weaponId = tonumber(weaponId)
	if not src or not weaponId then return 0 end
	JRSInventoryAmmoRevisions[src] = JRSInventoryAmmoRevisions[src] or {}
	return tonumber(JRSInventoryAmmoRevisions[src][weaponId]) or 0
end

local function setAmmoRevision(src, weaponId, revision)
	src = tonumber(src)
	weaponId = tonumber(weaponId)
	if not src or not weaponId then return end
	JRSInventoryAmmoRevisions[src] = JRSInventoryAmmoRevisions[src] or {}
	JRSInventoryAmmoRevisions[src][weaponId] = tonumber(revision) or 0
end

local function updateWeaponAmmoCache(src, weaponId, encodedAmmo, condition)
	src = tonumber(src)
	weaponId = tonumber(weaponId)
	if not src or not weaponId then return end
	if type(weapon_table) ~= 'table' or type(weapon_table[src]) ~= 'table' then return end

	for _, weapon in pairs(weapon_table[src]) do
		if tonumber(weapon.id) == weaponId then
			weapon.ammo = encodedAmmo
			if condition ~= nil then
				weapon.dirtlevel = tonumber(condition) or weapon.dirtlevel
				weapon.conditionlevel = tonumber(condition) or weapon.conditionlevel
			end
			break
		end
	end
end

local function enqueueAmmoWrite(src, weaponId, entry)
	src = tonumber(src)
	weaponId = tonumber(weaponId)
	if not src or not weaponId or type(entry) ~= 'table' then return false end

	local key = tostring(src) .. ':' .. tostring(weaponId)
	local queue = ammoWriteQueues[key]
	if not queue then
		queue = { running = false, pending = nil }
		ammoWriteQueues[key] = queue
	end

	-- While one query is in flight, only retain the newest accepted state.
	queue.pending = entry
	if queue.running then return true end

	local function runNext()
		local current = queue.pending
		queue.pending = nil
		if not current then
			queue.running = false
			ammoWriteQueues[key] = nil
			return
		end

		queue.running = true
		local query
		local params = {
			['ammo'] = current.ammo,
			['identifier'] = current.identifier,
			['charidentifier'] = current.charidentifier,
			['id'] = weaponId,
		}

		query = [[
			UPDATE jrs_weaponloadout
			SET ammo = @ammo
			WHERE identifier = @identifier AND charidentifier = @charidentifier AND id = @id
		]]

		exports[Config.MysqlResource]:execute(query, params, function()
			queue.running = false
			runNext()
		end)
	end

	runNext()
	return true
end

exports('syncWeaponAmmo', function(src, weaponId, ammoTable, ammoKey, exactTotal, weaponHash)
	src = tonumber(src)
	weaponId = tonumber(weaponId)
	if not src or not weaponId then
		return false
	end

	local Character, identifier, charid = getCharacterData(src)
	if not Character or not identifier or not charid then
		return false
	end
	local cleanAmmo = sanitizeWeaponAmmoTable(ammoTable)
	local encodedAmmo = json.encode(cleanAmmo)
	local nextRevision = currentAmmoRevision(src, weaponId) + 1

	-- Raise the revision before queuing the DB write. Any older save packet that
	-- arrives after this point is rejected, and any older in-flight DB write is
	-- followed by this newer write through enqueueAmmoWrite().
	setAmmoRevision(src, weaponId, nextRevision)
	updateWeaponAmmoCache(src, weaponId, encodedAmmo, nil)

	local queued = enqueueAmmoWrite(src, weaponId, {
		ammo = encodedAmmo,
		identifier = identifier,
		charidentifier = charid,
	})
	if not queued then return false end

	TriggerClientEvent('jrs_inventory:syncWeaponAmmo', src, weaponId, cleanAmmo, tostring(ammoKey or ''), tonumber(exactTotal) or 0, tonumber(weaponHash) or 0, nextRevision)
	return true
end)

AddEventHandler('playerDropped', function()
	JRSInventoryAmmoRevisions[tonumber(source)] = nil
end)

RegisterServerEvent('jrs_inventory:saveAmmoThrow')
AddEventHandler('jrs_inventory:saveAmmoThrow', function(wepName, ammoTable, wepCond, clientRevision, clientWeaponId)
	local _source = tonumber(source)
    if not _source or not AllowInventoryRequest(_source, 'weapon_state') then return end
    if InventoryPayloadSize(ammoTable) > (tonumber(Config.Security and Config.Security.MaxAmmoPayloadBytes) or 8192) then
        RecordInventorySecurityViolation(_source, 'oversized_ammo_payload', tostring(InventoryPayloadSize(ammoTable)))
        return
    end
    wepCond = math.max(0, math.min(100, tonumber(wepCond) or 0))
	local Character = jrsCore.GetCharacter(_source)
	if not Character then return end

	local weaponId = tonumber(clientWeaponId)
	if not weaponId and type(weapon_table) == 'table' and type(weapon_table[_source]) == 'table' then
		for _, cachedWeapon in pairs(weapon_table[_source]) do
			if tonumber(cachedWeapon.used) == 1 and string.upper(tostring(cachedWeapon.name)) == string.upper(tostring(wepName)) then
				weaponId = tonumber(cachedWeapon.id)
				break
			end
		end
	end
	if not weaponId then return end

	-- Verify the client-provided id still belongs to the named weapon in cache.
	local validWeapon = false
	if type(weapon_table) == 'table' and type(weapon_table[_source]) == 'table' then
		for _, cachedWeapon in pairs(weapon_table[_source]) do
			if tonumber(cachedWeapon.id) == weaponId
				and string.upper(tostring(cachedWeapon.name)) == string.upper(tostring(wepName)) then
				validWeapon = true
				break
			end
		end
	end
	if not validWeapon then return end

	if (tonumber(clientRevision) or 0) < currentAmmoRevision(_source, weaponId) then
		return
	end

	local cleanAmmo, acceptedCondition, attemptedIncrease = clampClientWeaponState(_source, weaponId, ammoTable, wepCond)
    if not cleanAmmo then return end
	local encodedAmmo = json.encode(cleanAmmo)
	updateWeaponAmmoCache(_source, weaponId, encodedAmmo, acceptedCondition)
	enqueueAmmoWrite(_source, weaponId, {
		ammo = encodedAmmo,
		condition = tonumber(acceptedCondition),
		identifier = Character.identifier,
		charidentifier = Character.charIdentifier,
	})
end)

RegisterServerEvent('jrs_inventory:saveAmmoNormal')
AddEventHandler('jrs_inventory:saveAmmoNormal', function(wepName, ammoTable, wepCond, clientRevision)
	local _source = tonumber(source)
    if not _source or not AllowInventoryRequest(_source, 'weapon_state') then return end
    if InventoryPayloadSize(ammoTable) > (tonumber(Config.Security and Config.Security.MaxAmmoPayloadBytes) or 8192) then
        RecordInventorySecurityViolation(_source, 'oversized_ammo_payload', tostring(InventoryPayloadSize(ammoTable)))
        return
    end
    wepCond = math.max(0, math.min(100, tonumber(wepCond) or 0))
	local Character = jrsCore.GetCharacter(_source)
	if not Character then return end
	local weaponId = tonumber(wepName)
	if not weaponId then return end

	if (tonumber(clientRevision) or 0) < currentAmmoRevision(_source, weaponId) then
		return
	end

	-- Only accept ids present in this player's current server-side weapon cache.
	local validWeapon = false
	if type(weapon_table) == 'table' and type(weapon_table[_source]) == 'table' then
		for _, cachedWeapon in pairs(weapon_table[_source]) do
			if tonumber(cachedWeapon.id) == weaponId then
				validWeapon = true
				break
			end
		end
	end
	if not validWeapon then return end

	local cleanAmmo, acceptedCondition, attemptedIncrease = clampClientWeaponState(_source, weaponId, ammoTable, wepCond)
    if not cleanAmmo then return end
	local encodedAmmo = json.encode(cleanAmmo)
	updateWeaponAmmoCache(_source, weaponId, encodedAmmo, acceptedCondition)
	enqueueAmmoWrite(_source, weaponId, {
		ammo = encodedAmmo,
		condition = tonumber(acceptedCondition),
		identifier = Character.identifier,
		charidentifier = Character.charIdentifier,
	})
end)

-- Direct client cleaning was unused and allowed a modified client to repair a
-- weapon for free. Keep the legacy event as a blocked trap, and expose a trusted
-- server-only API for a JRS cleaning-kit resource.
RegisterNetEvent('jrs_inventory:save_cleaning')
AddEventHandler('jrs_inventory:save_cleaning', function(name, cleaning)
    local playerId = tonumber(source)
    if playerId then
        RecordInventorySecurityViolation(playerId, 'blocked_direct_weapon_cleaning', tostring(name) .. ':' .. tostring(cleaning))
    end
end)

local function setWeaponConditionTrusted(playerId, weaponId, condition, sourceResource)
    playerId = tonumber(playerId)
    weaponId = tonumber(weaponId)
    condition = tonumber(condition)
    if not playerId or not weaponId or not condition then return false, 'invalid_request' end

    condition = math.max(0, math.min(100, condition))
    local cachedWeapon = getCachedWeapon(playerId, weaponId)
    if not cachedWeapon then return false, 'weapon_not_owned' end

    local Character = jrsCore.GetCharacter(playerId)
    if not Character then return false, 'player_not_loaded' end

    cachedWeapon.conditionlevel = condition
    exports[Config.MysqlResource]:execute(
        'UPDATE jrs_weaponloadout SET conditionlevel=@condition WHERE id=@id AND identifier=@identifier AND charidentifier=@charidentifier',
        {
            ['condition'] = condition,
            ['id'] = weaponId,
            ['identifier'] = Character.identifier,
            ['charidentifier'] = Character.charIdentifier,
        }
    )

    if DiscordLogConfig and DiscordLogConfig.LogWeaponStateChanges == true then
        local name = string.upper(tostring(cachedWeapon.name or 'UNKNOWN'))
        local label = (weaponTableForData[name] and weaponTableForData[name].label) or name
        JRSInventoryLogAction('Usage', 'Weapon Condition Updated', playerId, {
            weapon = label .. ' (`' .. name .. '`)',
            weaponId = weaponId,
            condition = condition,
            sourceResource = tostring(sourceResource or 'server'),
        })
    end
    return true, 'success'
end

exports('setWeaponCondition', function(playerId, weaponId, condition)
    return setWeaponConditionTrusted(playerId, weaponId, condition, GetInvokingResource() or 'server_export')
end)

AddEventHandler('jrs_inventory:server:setWeaponCondition', function(playerId, weaponId, condition, callback)
    local invokingResource = GetInvokingResource()
    if not invokingResource then return end
    local success, reason = setWeaponConditionTrusted(playerId, weaponId, condition, invokingResource)
    if callback ~= nil then pcall(callback, success, reason) end
end)
