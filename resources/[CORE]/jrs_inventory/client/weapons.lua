-- ===========================================================================
-- Weapons (equip/unequip/ammo/cleaning)
-- ===========================================================================

-- Ammo revisions prevent an older save packet from overwriting a newer refill.
local function GetWeaponAmmoRevision(weaponId)
	weaponId = tonumber(weaponId)
	if not weaponId then return 0 end
	return tonumber((weaponAmmoRevision or {})[weaponId]) or 0
end

local function SaveAmmoNormalToServer(weaponId, ammoTable, weaponCondition)
	TriggerServerEvent('jrs_inventory:saveAmmoNormal', weaponId, ammoTable, weaponCondition, GetWeaponAmmoRevision(weaponId))
end

local function SaveAmmoThrowToServer(weaponName, ammoTable, weaponCondition)
	local revision = 0
	local weaponId = nil
	for _, weapon in pairs(weapon_table or {}) do
		if tonumber(weapon.used) == 1 and string.upper(tostring(weapon.name)) == string.upper(tostring(weaponName)) then
			weaponId = tonumber(weapon.id)
			revision = GetWeaponAmmoRevision(weaponId)
			break
		end
	end
	TriggerServerEvent('jrs_inventory:saveAmmoThrow', weaponName, ammoTable, weaponCondition, revision, weaponId)
end

-- SET_PED_AMMO / SET_AMMO_IN_CLIP act on the ammo type the weapon currently has
-- selected. Applying them for every saved type let the last one overwrite the rest
-- (refilling Express while Normal was loaded replaced the Normal count), so they
-- only run for the type the weapon is actually using.
local function WeaponUsesAmmoType(ped, weaponHash, ammoHash)
	local ok, current = pcall(Citizen.InvokeNative, 0x7FEAD38B326B9F74, ped, weaponHash, Citizen.ResultAsInteger())
	if not ok or not tonumber(current) or tonumber(current) == 0 then return true end
	return (math.floor(tonumber(current)) % 4294967296) == (math.floor(tonumber(ammoHash) or 0) % 4294967296)
end

RegisterNetEvent('jrs_inventory:syncWeaponAmmo')
AddEventHandler('jrs_inventory:syncWeaponAmmo', function(weaponId, ammoData, ammoKey, exactTotal, weaponHash, revision)
	weaponId = tonumber(weaponId)
	exactTotal = math.max(0, math.floor(tonumber(exactTotal) or 0))
	weaponAmmoRevision = weaponAmmoRevision or {}
	if weaponId and (tonumber(revision) or 0) < GetWeaponAmmoRevision(weaponId) then return end
	if weaponId then
		weaponAmmoRevision[weaponId] = math.max(GetWeaponAmmoRevision(weaponId), tonumber(revision) or 0)
	end

	local normalizedAmmo = type(ammoData) == 'table' and ammoData or {}
	local encodedAmmo = json.encode(normalizedAmmo)
	local equipped = false

	for _, weapon in pairs(weapon_table or {}) do
		if tonumber(weapon.id) == weaponId then
			weapon.ammo = encodedAmmo
			equipped = tonumber(weapon.used) == 1
			break
		end
	end

	-- Bag weapons receive their saved ammo when equipped. Applying it to the ped
	-- here would overwrite the shared ammo pool of an already equipped weapon.
	if not equipped then return end

	local key = tostring(ammoKey or '')
	if key ~= '' then
		ammoNormal[key] = exactTotal
		backupAmmoNormal[key] = exactTotal
		ammoThrow[key] = exactTotal
		backupAmmoThrow[key] = exactTotal

		local ped = PlayerPedId()
		local ammoHash = GetHashKey(key)
		SetPedAmmoByType(ped, ammoHash, exactTotal)

		-- Re-apply on the next frame. RedM can update weapon inventory state during
		-- the same frame an item-use event completes, which otherwise leaves the HUD stale.
		Citizen.Wait(0)
		SetPedAmmoByType(ped, ammoHash, exactTotal)

		local targetWeaponHash = tonumber(weaponHash) or 0
		if targetWeaponHash == 0 then
			local _, heldHash = GetCurrentPedWeapon(ped, true, 0, true)
			targetWeaponHash = tonumber(heldHash) or 0
		end

		if targetWeaponHash ~= 0 and targetWeaponHash ~= GetHashKey('WEAPON_UNARMED') and exactTotal > 0 and WeaponUsesAmmoType(ped, targetWeaponHash, ammoHash) then
			SetPedAmmo(ped, targetWeaponHash, exactTotal)
			local maxClip = Citizen.InvokeNative(0xA38C00D60E8023E8, ped, targetWeaponHash, true) or 0
			if maxClip > 0 then
				Citizen.InvokeNative(0xDCD2A934D65CB497, ped, targetWeaponHash, math.min(exactTotal, maxClip))
			end
		end
	end
end)

local function isAmmoTypeForWeapon(weaponName, ammoKey)
	local name = string.upper(tostring(weaponName or ''))
	local key = string.upper(tostring(ammoKey or ''))

	if name:find("REVOLVER", 1, true) then
		return key:find("REVOLVER", 1, true) ~= nil
	elseif name:find("PISTOL", 1, true) then
		return key:find("PISTOL", 1, true) ~= nil
	elseif name:find("REPEATER", 1, true) then
		return key:find("REPEATER", 1, true) ~= nil
	elseif name:find("SHOTGUN", 1, true) then
		return key:find("SHOTGUN", 1, true) ~= nil
	elseif name:find("VARMINT", 1, true) then
		return key:find("AMMO_22", 1, true) ~= nil or key:find("VARMINT", 1, true) ~= nil
	elseif name:find("ELEPHANT", 1, true) then
		return key:find("ELEPHANT", 1, true) ~= nil
	elseif name:find("RIFLE", 1, true) or name:find("SNIPER", 1, true) then
		if key:find("ELEPHANT", 1, true) or key:find("VARMINT", 1, true) or key:find("AMMO_22", 1, true) then
			return false
		end
		return key:find("RIFLE", 1, true) ~= nil
	elseif name:find("BOW", 1, true) then
		return key:find("ARROW", 1, true) ~= nil or key:find("BOW", 1, true) ~= nil
	end

	return false
end

function saveWeaponAmmo()
	if not weapon_table or type(weapon_table) ~= 'table' then return end
	local ped = PlayerPedId()

	local anyChanged = false
	for _, item in ipairs(ammo_list or {}) do
		local ammoKey = item[2]
		if type(ammoKey) == 'string' and ammoKey:sub(1, 5) == 'AMMO_' then
			local liveCount = Citizen.InvokeNative(0x39D22031557946C1, ped, GetHashKey(ammoKey)) or 0
			ammoNormal[ammoKey] = liveCount
			if backupAmmoNormal[ammoKey] == nil then
				backupAmmoNormal[ammoKey] = liveCount
			elseif ammoNormal[ammoKey] ~= backupAmmoNormal[ammoKey] then
				backupAmmoNormal[ammoKey] = liveCount
				if ignorMeForLoadNormal then
					anyChanged = true
				end
			end
		end
	end

	if ignorMeForLoadNormal and anyChanged then
		for _, weapon in pairs(weapon_table) do
			if tonumber(weapon.used) == 1 and weapon.id then
				local weaponId = tonumber(weapon.id)
				local weaponName = string.upper(tostring(weapon.name or ''))
				local filterAmmo = {}
				for key, val in pairs(ammoNormal) do
					if isAmmoTypeForWeapon(weaponName, key) then
						filterAmmo[key] = val
					end
				end
				if next(filterAmmo) ~= nil then
					local cond = tonumber(weapon.conditionlevel) or 1.0
					SaveAmmoNormalToServer(weaponId, filterAmmo, cond)
				end
			end
		end
	end
	ignorMeForLoadNormal = true
end

function saveThrowAmmo()
	local saveWhatThrow = nil
	local saveItNowThrow = false
	for a,b in pairs(ammo_list) do
		if string.match(b[2], "throw") or string.match(b[2], "THROW") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "knive"
				end
			end
		 end
		 if string.match(b[2], "bola") or string.match(b[2], "BOLA") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "bola"
				end
			end
		end
		if string.match(b[2], "dynamite") or string.match(b[2], "DYNAMITE") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "dynamite"
				end
			end
		end
		if string.match(b[2], "hatchet_cleaver") or string.match(b[2], "HATCHET_CLEAVER") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "hatchet_cleaver"
				end
			end
		end
		if string.match(b[2], "hatchet_hunter") or string.match(b[2], "HATCHET_HUNTER") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "hatchet_hunter"
				end
			end
		end
		if string.match(b[2], "HATCHET") and not string.match(b[2], "HATCHET_HUNTER") and not string.match(b[2], "HATCHET_CLEAVER") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "hatchet"
				end
			end
		end
		if string.match(b[2], "molotov") or string.match(b[2], "MOLOTOV") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "molotov"
				end
			end
		end
		if string.match(b[2], "tomahawk") or string.match(b[2], "TOMAHAWK") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "tomahawk"
				end
			end
		end
		if string.match(b[2], "poisonbottle") or string.match(b[2], "POISONBOTTLE") then
			ammoThrow[b[2]] = Citizen.InvokeNative(0x39D22031557946C1, PlayerPedId(), GetHashKey(b[2]))
			if ammoThrow[b[2]] ~= backupAmmoThrow[b[2]] then
				backupAmmoThrow[b[2]] = ammoThrow[b[2]]
				if ignorMeForLoadThrow == true then
					saveItNowThrow = true
					saveWhatThrow = "poisonbottle"
				end
			end
		end
	end
	if saveItNowThrow == true and saveWhatThrow ~= nil then
		if saveWhatThrow =="knive" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "knif") or string.match(a, "KNIF") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("WEAPON_THROWN_THROWING_KNIVES", saveTableFilter, 0.0)
		elseif saveWhatThrow =="bola" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "bola") or string.match(a, "BOLA") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("weapon_thrown_bolas", saveTableFilter, 0.0)
		elseif saveWhatThrow =="dynamite" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "dynamite") or string.match(a, "DYNAMITE") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("weapon_thrown_dynamite", saveTableFilter, 0.0)
		elseif saveWhatThrow =="hatchet" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "HATCHET") and not string.match(a, "HATCHET_CLEAVER") and not string.match(a, "HATCHET_HUNTER")  then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("WEAPON_MELEE_HATCHET", saveTableFilter, 0.0)
		elseif saveWhatThrow =="hatchet_hunter" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "hatchet_hunter") or string.match(a, "HATCHET_HUNTER") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("WEAPON_MELEE_HATCHET_HUNTER", saveTableFilter, 0.0)
		elseif saveWhatThrow =="hatchet_cleaver" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "hatchet_cleaver") or string.match(a, "HATCHET_CLEAVER") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("WEAPON_MELEE_CLEAVER", saveTableFilter, 0.0)
		elseif saveWhatThrow =="molotov" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "molotov") or string.match(a, "MOLOTOV") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("weapon_thrown_molotov", saveTableFilter, 0.0)
		elseif saveWhatThrow =="tomahawk" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "tomahawk") or string.match(a, "TOMAHAWK") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("WEAPON_THROWN_TOMAHAWK", saveTableFilter, 0.0)
		elseif saveWhatThrow =="poisonbottle" then
			local saveTableFilter = {}
			for a,b in pairs(ammoThrow) do
				if string.match(a, "poisonbottle") or string.match(a, "POISONBOTTLE") then
					saveTableFilter[a] = b
				end
			end
			Citizen.Wait(0)
			SaveAmmoThrowToServer("weapon_thrown_poisonbottle", saveTableFilter, 0.0)
		end
	end
	ignorMeForLoadThrow = true
end

function RemoveAllWeapons()
	for k,v in pairs(weapon_table) do
		RemoveWeaponFromPed(PlayerPedId(), GetHashKey(v.name))
	end
	weapon_first_used = false
	weapon_second_used = false
	rifle_first_used = false
	rifle_second_used = false
end

-- Serialize the complete operation, including server confirmation and asset loading.
local weaponOperationBusy = false
local weaponOperationEpoch = 0
local pendingWeaponStates = {}
local weaponStateReplies = {}
local latestWeaponRequest = {}
local componentReplies = {}

local function findWeapon(id)
    for _, weapon in pairs(weapon_table or {}) do
        if tonumber(weapon.id) == tonumber(id) then return weapon end
    end
end

local function clearWeaponMarkers(name)
    if weapon_first_used == name then weapon_first_used = false end
    if weapon_second_used == name then weapon_second_used = false end
    if rifle_first_used == name then rifle_first_used = false end
    if rifle_second_used == name then rifle_second_used = false end
end

local function setLocalWeaponState(id, state)
    local weapon = findWeapon(id)
    if weapon then
        weapon.used = state
        SendNUIMessage({ type = 'weapon_state_update', id = tonumber(id), state = state })
    end
end

RegisterNetEvent('jrs_inventory:weaponStateResult')
AddEventHandler('jrs_inventory:weaponStateResult', function(token, id, state, success, reason)
    local reply = weaponStateReplies[token]
    if reply then
        reply.done, reply.success, reply.reason = true, success == true, reason
    elseif success == true and tonumber(state) == 1 and latestWeaponRequest[tonumber(id)] == token then
        -- A timed-out request must not leave an invisible equipped row behind.
        TriggerServerEvent('jrs_inventory:send_state_weapon', id, 0)
    end
end)

local function requestWeaponState(id, state)
    local token = NewInventoryOperationId('weapon_state')
    local reply = {}
    latestWeaponRequest[tonumber(id)] = token
    weaponStateReplies[token] = reply
    TriggerServerEvent('jrs_inventory:send_state_weapon', id, state, token)
    local started = GetGameTimer()
    while not reply.done and GetGameTimer() - started < 8000 do Citizen.Wait(10) end
    weaponStateReplies[token] = nil
    return reply.success == true, reply.reason or 'timeout'
end

-- Do not let a refresh during an equip replace its in-flight state. Remove
-- weapons whose ownership disappeared; never create native weapons from a UI refresh.
function ReconcileInventoryWeapons(rows)
    local normalized, byId, seen = {}, {}, {}
    for _, row in pairs(type(rows) == 'table' and rows or {}) do
        local id = tonumber(row.id)
        if id and not seen[id] and type(row.name) == 'string' then
            row.id, row.used = id, tonumber(row.used) == 1 and 1 or 0
            row.name = string.upper(row.name)
            if pendingWeaponStates[id] ~= nil then row.used = pendingWeaponStates[id] end
            seen[id], byId[id] = true, row
            normalized[#normalized + 1] = row
        end
    end
    for _, old in pairs(weapon_table or {}) do
        local id = tonumber(old.id)
        if pendingWeaponStates[id] == nil and (not byId[id] or byId[id].used == 0) then
            -- Another legitimately equipped record of the same model is retained.
            local sameModelEquipped = false
            for _, current in ipairs(normalized) do
                if current.name == string.upper(tostring(old.name)) and current.used == 1 then
                    sameModelEquipped = true
                    break
                end
            end
            if not sameModelEquipped then
                RemoveWeaponFromPed(PlayerPedId(), GetHashKey(old.name))
                clearWeaponMarkers(old.name)
            end
        end
    end
    return normalized
end

local function decodeWeaponData(value)
    if type(value) == 'table' then return value end
    local ok, decoded = pcall(json.decode, value or '{}')
    return ok and type(decoded) == 'table' and decoded or {}
end

local function weaponSlot(weapon)
    local hash = GetHashKey(weapon.name)
    for _, other in pairs(weapon_table or {}) do
        if tonumber(other.id) ~= tonumber(weapon.id) and tonumber(other.used) == 1
            and string.upper(tostring(other.name)) == weapon.name then
            return nil, _U('weapon_model_already_equipped')
        end
    end
    if Citizen.InvokeNative(0xDDC64F5E31EEDAB6, hash)
        or Citizen.InvokeNative(0xC212F1D05A8232BB, hash)
        or weapon.name == 'WEAPON_SHOTGUN_SAWEDOFF' then
        if weapon_first_used == false then return false, nil, 'weapon_first_used' end
        if weapon_second_used == false then return true, nil, 'weapon_second_used' end
        return nil, _U('weapon_handgun_slots_occupied')
    end
    if Citizen.InvokeNative(0x0556E9D2ECF39D01, hash) then
        if rifle_first_used == false then return nil, nil, 'rifle_first_used' end
        if rifle_second_used == false then return nil, nil, 'rifle_second_used' end
        return nil, _U('weapon_longarm_slots_occupied')
    end
    return nil, nil, nil
end

local function equipWeaponRecord(weapon, epoch)
    local dual, reason, marker = weaponSlot(weapon)
    if reason then return false, reason end
    if not LoadWeaponChar(weapon.name, dual) then return false, _U('weapon_loading_timed_out') end
    if epoch ~= weaponOperationEpoch then return false, _U('weapon_operation_cancelled') end
    if not LoadCompAndAmmo(decodeWeaponData(weapon.ammo), decodeWeaponData(weapon.comps), weapon.name) then
        return false, _U('weapon_components_could_not_be_loaded')
    end
    if epoch ~= weaponOperationEpoch then return false, _U('weapon_operation_cancelled') end
    SetDirtToWeapon(weapon.id, tonumber(weapon.dirtlevel) or 0.0)
    if marker then _G[marker] = weapon.name end
    setLocalWeaponState(weapon.id, 1)
    return true
end

local function isSafezoneWeaponBlocked(weaponName)
    if GetResourceState('jrs_safezone') == 'started' then
        -- Props (lantern, fishing rod, binoculars...) are never blocked.
        local okProp, isProp = pcall(function()
            return exports['jrs_safezone']:IsNonWeaponProp(weaponName)
        end)
        if okProp and isProp == true then
            return false
        end
    end
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.safezoneBlockWeapons == true then
        return true
    end
    if GetResourceState('jrs_safezone') == 'started' then
        local ok, blocked = pcall(function()
            return exports['jrs_safezone']:IsWeaponBlocked(weaponName)
        end)
        if ok and blocked == true then
            return true
        end
    end
    return false
end

function UseWeapon(data)
    if weaponOperationBusy or equip_spam then return false end
    if LocalPlayer.state and LocalPlayer.state.jrsArena == true then return false end -- jrs_fightarena
    local weapon = type(data) == 'table' and findWeapon(data.id)
    if not weapon or string.upper(tostring(data.model)) ~= string.upper(weapon.name) then return false end
    weapon.name = string.upper(weapon.name)
    local nextState = tonumber(weapon.used) == 1 and 0 or 1
    if nextState == 1 then
        if isSafezoneWeaponBlocked(weapon.name) then
            TriggerEvent('jrsCore:notify', 'Weapons', _U('weapon_blocked_in_safezone'), 'gun', 4000)
            return false
        end
        local _, reason = weaponSlot(weapon)
        if reason then TriggerEvent('jrsCore:notify', 'Weapons', reason, 'gun', 3000); return false end
    end
    weaponOperationBusy, equip_spam, can_save = true, true, false
    local epoch = weaponOperationEpoch
    pendingWeaponStates[tonumber(weapon.id)] = nextState
    local ok, success, reason = pcall(function()
        if nextState == 0 then
            -- Save before removing the entity; never reset/add ammunition here.
            saveWeaponAmmo()
            saveThrowAmmo()
            RemoveWeaponFromPed(PlayerPedId(), GetHashKey(weapon.name))
            clearWeaponMarkers(weapon.name)
            setLocalWeaponState(weapon.id, 0)
        end
        local accepted, failure = requestWeaponState(weapon.id, nextState)
        if not accepted then return false, failure end
        if epoch ~= weaponOperationEpoch then return false, _U('weapon_operation_cancelled') end
        if nextState == 1 then return equipWeaponRecord(weapon, epoch) end
        return true
    end)
    if not ok or not success then
        RemoveWeaponFromPed(PlayerPedId(), GetHashKey(weapon.name))
        clearWeaponMarkers(weapon.name)
        setLocalWeaponState(weapon.id, 0)
        -- Keep the owned weapon, but leave it safely in the inventory on failure.
        requestWeaponState(weapon.id, 0)
        -- The server already sends the localized level requirement with its value.
        -- The server already sent a localized notice for these reasons.
        if not (ok and (reason == 'level_required' or reason == 'safezone_blocked')) then
            local reasonKeys = {
                safezone_blocked = 'weapon_blocked_in_safezone',
                arena = 'weapon_reason_arena',
                rate_limited = 'weapon_reason_rate_limited',
                invalid_state = 'weapon_could_not_equip_try_again',
                not_owned = 'weapon_could_not_equip_try_again',
                timeout = 'weapon_could_not_equip_try_again',
            }
            local msg = ok and reason or nil
            if type(msg) == 'string' and reasonKeys[msg] then msg = _U(reasonKeys[msg]) end
            TriggerEvent('jrsCore:notify', 'Weapons', tostring(msg or _U('weapon_could_not_equip_try_again')), 'gun', 4000)
        end
        if not ok then print('[jrs_inventory] Weapon operation failed: ' .. tostring(success)) end
    end
    pendingWeaponStates[tonumber(weapon.id)] = nil
    weaponOperationBusy, equip_spam, can_save = false, false, true
    return ok and success == true
end

function LoadWeaponChar(name, dual)
    local ped, hash = PlayerPedId(), GetHashKey(name)
    local epoch = weaponOperationEpoch
    -- Grant exactly once. Only selection is retried while the game loads it.
    if not givePlayerWeapon(name, dual == true and 3 or (dual == false and 2 or 0)) then return false end
    local started = GetGameTimer()
    repeat
        if ped ~= PlayerPedId() or epoch ~= weaponOperationEpoch then return false end
        SetCurrentPedWeapon(ped, hash, true)
        local _, selected = GetCurrentPedWeapon(ped, true, 0, true)
        if selected == hash then return true end
        Citizen.Wait(10)
    until GetGameTimer() - started >= 3000
    return false
end

function LoadCompAndAmmo(ammo, comps, weaponName)
    if GetResourceState('jrs_weapons') == 'started' then
        local token = NewInventoryOperationId('weapon_components')
        local reply = {}
        componentReplies[token] = reply
        TriggerEvent('jrs_weapons:load_components', comps, token)
        local started = GetGameTimer()
        while not reply.done and GetGameTimer() - started < 12000 do Citizen.Wait(10) end
        componentReplies[token] = nil
        if not reply.done or not reply.success then return false end
    end
    local ped = PlayerPedId()
    local _, heldHash = GetCurrentPedWeapon(ped, true, 0, true)
    heldHash = tonumber(heldHash) or 0
    local targetHash = (weaponName and GetHashKey(tostring(weaponName))) or heldHash
    for key, count in pairs(ammo) do
        local amount = tonumber(count)
        if type(key) == 'string' and amount and amount >= 0 and amount == amount and amount < math.huge then
            local ammoHash = GetHashKey(key)
            local total = math.floor(amount)
            ammoNormal[key] = total
            backupAmmoNormal[key] = total
            SetPedAmmoByType(ped, ammoHash, total)
            if targetHash ~= 0 and targetHash ~= GetHashKey('WEAPON_UNARMED') and total > 0 and WeaponUsesAmmoType(ped, targetHash, ammoHash) then
                SetPedAmmo(ped, targetHash, total)
                local maxClip = Citizen.InvokeNative(0xA38C00D60E8023E8, ped, targetHash, true) or 0
                if maxClip > 0 then
                    Citizen.InvokeNative(0xDCD2A934D65CB497, ped, targetHash, math.min(total, maxClip))
                end
            end
        end
    end
    return true
end

function SetDirtToWeapon(wpId, wpDirt)
	local weaponEntityIndex = GetCurrentPedWeaponEntityIndex(PlayerPedId())
	Citizen.InvokeNative(0xA7A57E89E965D839, weaponEntityIndex, tonumber(wpDirt) or 0.0)
	Citizen.InvokeNative(0x812CE61DEBCAB948, weaponEntityIndex, tonumber(wpDirt) or 0.0, 0)
end

local unequipAllWeaponsBusy = false

function UnequipAllWeaponsToInventory(syncServer)
	if unequipAllWeaponsBusy then return end
	unequipAllWeaponsBusy = true
	weaponOperationEpoch = weaponOperationEpoch + 1
	can_save = false
	equip_spam = true

	-- Remove every inventory weapon from the player's weapon wheel, while
	-- keeping the weapon record itself inside weaponloadout/the inventory bag.
	RemoveAllWeapons()

	for _, weapon in pairs(weapon_table or {}) do
		weapon.used = 0
	end

	-- Make sure the player is not left holding a removed weapon.
	SetCurrentPedWeapon(PlayerPedId(), GetHashKey('WEAPON_UNARMED'), true)

	if syncServer ~= false then
		TriggerServerEvent('jrs_inventory:set_all_weapons_unequipped')
	end

	Citizen.Wait(100)
	can_save = not weaponOperationBusy
	equip_spam = weaponOperationBusy
	unequipAllWeaponsBusy = false
end

function equip_weapon_login()
	-- On character/server spawn, weapons must return to the bag instead of
	-- being restored automatically to the weapon wheel from used = 1.
	addWardrobeInventoryItem("CLOTHING_ITEM_M_OFFHAND_000_TINT_004", 0xF20B6B4A)
	addWardrobeInventoryItem("UPGRADE_OFFHAND_HOLSTER", 0x39E57B01)
	UnequipAllWeaponsToInventory(true)
	TriggerEvent("jrs_character:selected_char")
end

-- ===========================================================================
-- Weapon Events
-- ===========================================================================

RegisterNetEvent('jrs_inventory:cleaning_weapons')
AddEventHandler('jrs_inventory:cleaning_weapons', function()
    TriggerEvent('jrsCore:notify', 'Weapons', _U('weapon_use_cleaning_kit'), 'gun', 3000)
end)

RegisterNetEvent('jrs_inventory:CloseInv')
AddEventHandler('jrs_inventory:CloseInv', function()
	Show_Items(false, false)
	SetNuiFocus(false, false)
	guiEnabled = false
	giveItemEnable = false
end)

RegisterNetEvent('jrs_inventory:reload_weap')
AddEventHandler('jrs_inventory:reload_weap', function()
    while weaponOperationBusy or equip_spam do Citizen.Wait(25) end
    weaponOperationBusy, equip_spam, can_save = true, true, false
    local epoch = weaponOperationEpoch
    local restore = {}
    for _, weapon in pairs(weapon_table or {}) do
        if tonumber(weapon.used) == 1 then restore[#restore + 1] = weapon end
    end
    RemoveAllWeapons()
    for _, weapon in ipairs(restore) do
        if epoch ~= weaponOperationEpoch then break end
        pendingWeaponStates[tonumber(weapon.id)] = 1
        local ok, success = pcall(function()
            if not requestWeaponState(weapon.id, 1) then return false end
            return equipWeaponRecord(weapon, epoch)
        end)
        if not ok or not success then
            RemoveWeaponFromPed(PlayerPedId(), GetHashKey(weapon.name))
            clearWeaponMarkers(weapon.name)
            setLocalWeaponState(weapon.id, 0)
            requestWeaponState(weapon.id, 0)
        end
        pendingWeaponStates[tonumber(weapon.id)] = nil
    end
    weaponOperationBusy, equip_spam, can_save = false, false, true
end)

RegisterNetEvent('jrs_inventory:sendOkLoading')
AddEventHandler('jrs_inventory:sendOkLoading', function(token, success)
    local reply = token and componentReplies[token]
    if reply then reply.done, reply.success = true, success ~= false end
end)

RegisterNetEvent('jrs_inventory:remove_wepo')
AddEventHandler('jrs_inventory:remove_wepo', function(model)
	if rifle_first_used == model then
		rifle_first_used = false
	end
	if rifle_second_used == model then
		rifle_second_used = false
	end
	if weapon_first_used == model then
		weapon_first_used = false
	end
	if weapon_second_used == model then
		weapon_second_used = false
	end
	RemoveWeaponFromPed(PlayerPedId(), GetHashKey(model))
end)

-- ===========================================================================
-- Weapon NUI Callbacks
-- ===========================================================================

RegisterNUICallback('show_weapon', function(data, cb)
  local ped = PlayerPedId()
  local weapon_type = ""
  local _, weapon_hash = GetCurrentPedWeapon(ped, true, 0, true)
  if GetHashKey('GROUP_REPEATER') == GetWeapontypeGroup(weapon_hash) then
		weapon_type = "LONGARM"
	elseif GetHashKey('GROUP_SHOTGUN') == GetWeapontypeGroup(weapon_hash) then
		weapon_type = "LONGARM"
	elseif GetHashKey('GROUP_HEAVY') == GetWeapontypeGroup(weapon_hash) then
		weapon_type = "LONGARM"
	elseif GetHashKey('GROUP_RIFLE') == GetWeapontypeGroup(weapon_hash) then
		weapon_type = "LONGARM"
	elseif GetHashKey('GROUP_SNIPER') == GetWeapontypeGroup(weapon_hash) then
		weapon_type = "LONGARM"
	elseif GetHashKey('GROUP_REVOLVER') == GetWeapontypeGroup(weapon_hash) then
		weapon_type = "SHORTARM"
	elseif GetHashKey('GROUP_PISTOL') == GetWeapontypeGroup(weapon_hash) then
		weapon_type = "SHORTARM"
	end

	if weapon_type ~= "" then
  		TaskItemInteraction(PlayerPedId(), weapon_hash, GetHashKey(""..weapon_type.."_HOLD"), 1, 0, 0)
		  Show_Items(false, false)
		  SetNuiFocus(false, false)
		  guiEnabled = false
	else
		exports['jrs_core']:DisplayLeftNotification(_U('inventory'), _U('no_weapon_to_show'), 'pistol', 2000)
	end
end)

local InventoryClothingSlots = {
	{ key = "hats", label = "Hats & Headwear", ar_label = "القبعات وغطاء الرأس", icon = "hats.png", categories = { "hats", "headwear", "hat_accessories", "hair_accessories" } },
	{ key = "eyewear", label = "Eyewear", ar_label = "النظارات", icon = "glasses.png", categories = { "eyewear" } },
	{ key = "masks", label = "Masks & Bandanas", ar_label = "الأقنعة والأوشحة", icon = "mask.png", categories = { "masks", "masks_large", "face_props" } },
	{ key = "neckwear", label = "Neckwear & Ties", ar_label = "ربطات العنق والمناديل", icon = "neckties.png", categories = { "neckwear", "neckerchiefs", "neckties" } },
	{ key = "cloaks", label = "Cloaks & Ponchos", ar_label = "العباءات والبانشو", icon = "ponchos.png", categories = { "ponchos", "cloaks", "capes", "shawls" } },
	{ key = "suspenders", label = "Suspenders", ar_label = "الحمالات", icon = "suspenders.png", categories = { "suspenders" } },
	{ key = "shirts", label = "Shirts & Underlayers", ar_label = "القمصان", icon = "shirts_full.png", categories = { "shirts_full", "shirts_full_overpants", "unionsuits_full", "chemises", "lduvmjua_0x2b388a05", "nbtudvja_0x53b67599" } },
	{ key = "vests", label = "Vests & Corsets", ar_label = "الصديريات", icon = "vests.png", categories = { "vests", "vest_accessories", "corsets" } },
	{ key = "coats", label = "Coats & Jackets", ar_label = "المعاطف والسترات", icon = "coats.png", categories = { "coats", "coats_closed", "coats_heavy", "coat_accessories" } },
	{ key = "gloves", label = "Gloves", ar_label = "القفازات", icon = "gloves.png", categories = { "gloves" } },
	{ key = "gauntlets", label = "Gauntlets", ar_label = "أساور الذراعين", icon = "gauntlets.png", categories = { "gauntlets" } },
	{ key = "belts", label = "Belts", ar_label = "الأحزمة", icon = "belts.png", categories = { "belts" } },
	{ key = "buckles", label = "Belt Buckles", ar_label = "إبزيم الحزام", icon = "buck.png", categories = { "belt_buckles" } },
	{ key = "gunbelts", label = "Gun Belts", ar_label = "أحزمة الأسلحة", icon = "gunbelts.png", categories = { "gunbelts" } },
	{ key = "holsters", label = "Holsters", ar_label = "أغماد الأسلحة", icon = "holsters_left.png", categories = { "holsters_right", "holsters_left", "holsters_knife", "holsters_crossdraw", "holsters_center", "loadouts", "gunbelt_accs", "holsters_quivers", "ammo_pistols" } },
	{ key = "pants", label = "Pants & Lower Layers", ar_label = "السراويل", icon = "pants.png", categories = { "pants", "pants_accessories", "overalls_modular_lowers", "unionsuit_legs", "knickers", "stockings", "skirts", "dresses", "overalls_full", "overalls_modular_uppers", "outfits", "cnvfyaba_0xd7ae0d03", "gjrbmoma_0xcb39a6f4", "pnyvpusa_0x44f4c713", "ogoolgaa_0xecd61654", "gnuusvra_0x7024af8b", "oacpqvda_0x41292b6f", "ywkywwvb_0xe93b9f1b" } },
	{ key = "chaps", label = "Chaps", ar_label = "واقيات الساق", icon = "chaps.png", categories = { "chaps" } },
	{ key = "boots", label = "Boots & Footwear", ar_label = "الأحذية", icon = "boots.png", categories = { "boots", "boot_accessories", "spats" } },
	{ key = "satchels", label = "Satchels", ar_label = "الحقائب الجانبية", icon = "satchels.png", categories = { "satchels", "satchel_straps" } },
	{ key = "rings_left", label = "Left Rings & Jewelry", ar_label = "خواتم اليد اليسرى", icon = "jewelry_rings_left.png", categories = { "jewelry_rings", "jewelry_rings_left", "jewelry_necklaces", "jewelry_earrings" } },
	{ key = "rings_right", label = "Right Rings & Bracelets", ar_label = "خواتم اليد اليمنى والأساور", icon = "jewelry_rings_right.png", categories = { "jewelry_rings_right", "jewelry_bracelets", "wrist_bindings", "ankle_bindings", "accessories", "badges", "armor", "mbbwboia_0x42e8f927" } },
}

local InventoryClothingSlotByKey = {}
for _, slot in ipairs(InventoryClothingSlots) do
	InventoryClothingSlotByKey[slot.key] = slot
end

local function getClothingSlotLocalizedLabel(slot)
	if not slot then return "" end
	local lang = (type(JrsLang) == 'table' and type(JrsLang.Current) == 'function') and JrsLang.Current() or 'ar'
	if lang == 'ar' and slot.ar_label and slot.ar_label ~= '' then
		return slot.ar_label
	end
	return slot.label or slot.key or ""
end

local function notifyClothing(message, isError)
	local title = _U('clothing_title') or _U('inventory') or 'الملابس'
	TriggerEvent(
		'jrsCore:notify',
		title,
		tostring(message or ''),
		'bag',
		4000
	)
end

function RefreshInventoryClothingState()
	local clothingStarted = GetResourceState('jrs_clothing') == 'started'
	local state = {}
	if clothingStarted then
		local called, result = pcall(function()
			return exports['jrs_clothing']:GetInventoryClothingState(InventoryClothingSlots)
		end)
		if called and type(result) == 'table' then state = result else clothingStarted = false end
	end

	SendNUIMessage({
		type = 'clothing_state',
		integration = clothingStarted,
		definitions = InventoryClothingSlots,
		state = state,
	})
end

AddEventHandler('jrs_clothes:OnInventoryStateChanged', function()
	if guiEnabled then RefreshInventoryClothingState() end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
	if resourceName ~= 'jrs_clothing' then return end
	Citizen.SetTimeout(750, function()
		if guiEnabled then RefreshInventoryClothingState() end
	end)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
	if resourceName == 'jrs_clothing' and guiEnabled then RefreshInventoryClothingState() end
end)

RegisterNUICallback('put_clothe', function(data, cb)
	local slotKey = tostring(data and (data.slot or data.clothe) or '')
	local slot = InventoryClothingSlotByKey[slotKey]
	if not slot then
		cb({ success = false, reason = 'invalid_slot' })
		return
	end

	local slotLabel = getClothingSlotLocalizedLabel(slot)

	if GetResourceState('jrs_clothing') ~= 'started' then
		notifyClothing(_U('inventory_jrs_clothing_is_not_started'), true)
		cb({ success = false, reason = 'resource_not_started' })
		return
	end

	local called, success, reason, state = pcall(function()
		return exports['jrs_clothing']:ToggleInventoryClothing(slot.categories)
	end)
	if not called then
		notifyClothing(_U('inventory_the_clothing_system_could_not_process'), true)
		cb({ success = false, reason = 'integration_error' })
		return
	end

	if success ~= true then
		notifyClothing((_U('inventory_you_are_not_wearing_anything_in')):format(slotLabel), true)
		RefreshInventoryClothingState()
		cb({ success = false, reason = reason or 'not_owned', state = state })
		return
	end

	local equipped = type(state) == 'table' and state.equipped == true
	local message = equipped and (_U('equipped_action'):format(slotLabel)) or (_U('unequipped_action'):format(slotLabel))
	notifyClothing(message, false)
	RefreshInventoryClothingState()
	cb({ success = true, reason = reason, state = state })
end)

RegisterNUICallback('use_UseWeapon', function(data, cb)
    local success = UseWeapon(data)
    cb({ success = success == true })
end)

-- 2.4.6: true only when the held weapon hash is one of the weapon rows in the
-- player's bag. jrs_weapons' licence check uses it so scenario/tool props
-- (buckets, hammers, cans...) are never treated as a firearm.
exports('IsBagWeaponHash', function(hash)
    hash = tonumber(hash)
    if not hash or hash == 0 then return false end
    for _, weapon in pairs(weapon_table or {}) do
        if type(weapon.name) == 'string' and GetHashKey(weapon.name) == hash then return true end
    end
    return false
end)

exports('UnequipAllWeapons', function(syncServer)
    return UnequipAllWeaponsToInventory(syncServer ~= false)
end)

RegisterNetEvent('jrs_inventory:client:unequipAllWeapons', function(syncServer)
    UnequipAllWeaponsToInventory(syncServer ~= false)
end)

