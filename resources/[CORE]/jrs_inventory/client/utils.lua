-- ===========================================================================
-- Utility Functions
-- ===========================================================================

function LoadModel(model)
	if not IsModelInCdimage(model) then
		return false
	end
	RequestModel(model)
	local deadline = GetGameTimer() + 3000
	while not HasModelLoaded(model) and GetGameTimer() < deadline do
		Wait(10)
	end
	return HasModelLoaded(model)
end

function GetClosestPlayer()
    local players = GetActivePlayers()
    local playerPed, playerId = PlayerPedId(), PlayerId()
    local coords = GetEntityCoords(playerPed)
    local closestPlayer, closestDistanceSq = -1, math.huge
    local closestServerId, closestPed = nil, nil

    -- Compare squared distances inside the loop and take one sqrt at the end.
    -- This function is used by several interaction systems, so avoiding a sqrt
    -- for every active player noticeably reduces native/math churn.
    for i = 1, #players do
        local player = players[i]
        if player ~= playerId then
            local tgt = GetPlayerPed(player)
            if tgt and tgt ~= 0 and DoesEntityExist(tgt) then
                local targetCoords = GetEntityCoords(tgt)
                local dx = coords.x - targetCoords.x
                local dy = coords.y - targetCoords.y
                local dz = coords.z - targetCoords.z
                local distanceSq = (dx * dx) + (dy * dy) + (dz * dz)

                if distanceSq < closestDistanceSq then
                    closestPlayer = player
                    closestDistanceSq = distanceSq
                    closestServerId = GetPlayerServerId(player)
                    closestPed = tgt
                end
            end
        end
    end

    if closestPlayer == -1 then
        return -1, -1, nil, nil
    end
    return closestPlayer, math.sqrt(closestDistanceSq), closestServerId, closestPed
end

function GetPlayers()
	local players = {}
	for _, player in ipairs(GetActivePlayers()) do
		table.insert(players, player)
	end
	return players
end

function GetPlayersClick()
	local players = {}
	for _, player in ipairs(GetActivePlayers()) do
		table.insert(players, GetPlayerServerId(player))
	end
	return players
end

function RequestControl(entity)
	local type = GetEntityType(entity)
	if type < 1 or type > 3 then
		return
	end
	NetworkRequestControlOfEntity(entity)
end

function playAnim(dict, name, time, flag)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(100)
    end
    TaskPlayAnim(PlayerPedId(), dict, name, 8.0, 8.0, time, flag, 0, true, 0, false, 0, false)
end

function playAnim2(dict, name, time, flag)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(100)
    end
    TaskPlayAnim(PlayerPedId(), dict, name, 1.0, 1.0, time, flag, 0, true, 0, false, 0, false)
end

function DrawText3D(x, y, z, text)
	local onScreen,_x,_y=GetScreenCoordFromWorldCoord(x, y, z)
	local px,py,pz=table.unpack(GetGameplayCamCoord())
	local dist = GetDistanceBetweenCoords(px,py,pz, x,y,z, 1)
	local str = CreateVarString(10, "LITERAL_STRING", text, Citizen.ResultAsLong())
	if onScreen then
		SetTextScale(0.30, 0.30)
		SetTextFontForCurrentCommand(0)
		SetTextColor(255, 255, 255, 255)
		SetTextCentre(1)
		SetTextDropshadow(1, 1, 0, 0, 200)
		DisplayText(str,_x,_y)
	end
end

function getGuidFromItemId(inventoryId, itemData, category, slotId)
    local outItem = DataView.ArrayBuffer(8 * 13)

    if not itemData then
        itemData = 0
    end

    local success = Citizen.InvokeNative("0x886DFD3E185C8A89", inventoryId, itemData, category, slotId, outItem:Buffer())
    if success then
        return outItem:Buffer()
    else
        return nil
    end
end

function addWardrobeInventoryItem(itemName, slotHash)
    local itemHash = GetHashKey(itemName)
    local addReason = GetHashKey("ADD_REASON_DEFAULT")
    local inventoryId = 1

    local isValid = Citizen.InvokeNative("0x6D5D51B188333FD1", itemHash, 0)
    if not isValid then
        return false
    end

    local characterItem = getGuidFromItemId(inventoryId, nil, GetHashKey("CHARACTER"), 0xA1212100)
    if not characterItem then
        return false
    end

    local wardrobeItem = getGuidFromItemId(inventoryId, characterItem, GetHashKey("WARDROBE"), 0x3DABBFA7)
    if not wardrobeItem then
        return false
    end

    local itemData = DataView.ArrayBuffer(8 * 13)

    local isAdded = Citizen.InvokeNative("0xCB5D11F9508A928D", inventoryId, itemData:Buffer(), wardrobeItem, itemHash, slotHash, 1, addReason);
    if not isAdded then
        return false
    end

    local equipped = Citizen.InvokeNative("0x734311E2852760D0", inventoryId, itemData:Buffer(), true);
    return equipped;
end

function givePlayerWeapon(weaponName, attachPoint)
    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weaponName)
    local started = GetGameTimer()
    Citizen.InvokeNative(0x72D4CB5DB927009C, weaponHash, 1, true)
    while not Citizen.InvokeNative(0xFF07CF465F48B830, weaponHash) do
        if GetGameTimer() - started >= 5000 or PlayerPedId() ~= ped then return false end
        Wait(25)
    end
    if PlayerPedId() ~= ped then return false end
    Citizen.InvokeNative(0x5E3BDDBCB83F3D84, ped, weaponHash, 0, true, false,
        attachPoint or 0, false, 0.0, 1.0, GetHashKey('ADD_REASON_DEFAULT'), true, 0.0, false)
    return true
end

function GetSpeedForCarriedWeight(carriedWeight)
	local weight = math.max(0.0, tonumber(carriedWeight) or 0.0)
	local defaultSpeed = math.max(0.0, math.min(3.0, tonumber(Config.DefaultMoveSpeed) or 0.0))

	if Config.WeightSpeedEnabled == false then
		return defaultSpeed
	end

	local perks = LocalPlayer.state.jrsPerks
	if type(perks) == 'table' then
		if perks.freeRun then
			return 0.0 -- Level 40+: Free run, no slowdown from bag weight
		end
		if type(Config.LevelPerksMoveSpeed) == 'function' then
			return Config.LevelPerksMoveSpeed(perks, weight)
		end
		local capacity = math.max(1, tonumber(perks.carryKg) or 50)
		local percent = (weight / capacity) * 100
		if percent >= 115 then return 1.20
		elseif percent >= 100 then return 1.60
		elseif percent >= 90 then return 1.85
		elseif percent >= 75 then return 2.10
		elseif percent >= 60 then return 2.40
		else return 0.0 end
	end

	local selectedSpeed = defaultSpeed
	local selectedThreshold = -1.0

	-- Select the highest matching threshold. A positive result is the maximum
	-- locomotion blend ratio applied to the RedM ped; 0.0 means unrestricted.
	for _, tier in ipairs(Config.WeightSpeedPenalty or {}) do
		local threshold = tonumber(tier.threshold)
		local tierSpeed = tonumber(tier.speed)
		if threshold and tierSpeed and threshold >= 0.0
			and weight >= threshold and threshold > selectedThreshold then
			selectedThreshold = threshold
			selectedSpeed = math.max(0.0, math.min(3.0, tierSpeed))
		end
	end

	return selectedSpeed
end

function GetClientInventoryWeight(items)
	local totalWeight = 0.0
	for _, item in pairs(type(items) == "table" and items or {}) do
		if type(item) == "table" then
			local count = math.max(0.0, tonumber(item.count) or 0.0)
			local unitWeight = math.max(0.0, tonumber(item.limit) or 0.0)
			totalWeight = totalWeight + (count * unitWeight)
		end
	end
	return totalWeight
end

function clearThisFunction()
	giveItemEnable = false
	idPlayerForItem = 0
	playerDragId = 0
	if type(SetNuiFocusKeepInput) == "function" then
		pcall(SetNuiFocusKeepInput, false)
	end
	SetNuiFocus(false, false)
	guiEnabled = false
	if type(SetInventoryHudBlocked) == "function" then
		SetInventoryHudBlocked(false)
	end
	SendNUIMessage({
		type = "give_flow_finished"
	})
end

function mulNumber(vector1, value)
    local result = {}
    result.x = vector1.x * value
    result.y = vector1.y * value
    result.z = vector1.z * value
    return result
end

function addVector3(vector1, vector2)
    return {x = vector1.x + vector2.x, y = vector1.y + vector2.y, z = vector1.z + vector2.z}
end

function subVector3(vector1, vector2)
    return {x = vector1.x - vector2.x, y = vector1.y - vector2.y, z = vector1.z - vector2.z}
end

function rotationToDirection(rotation)
    local z = degToRad(rotation.z)
    local x = degToRad(rotation.x)
    local num = math.abs(math.cos(x))
    local result = {}
    result.x = -math.sin(z) * num
    result.y = math.cos(z) * num
    result.z = math.sin(x)
    return result
end

function w2s(position)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(position.x, position.y, position.z)
    if not onScreen then
        return nil
    end
    local newPos = {}
    newPos.x = (_x - 0.5) * 2
    newPos.y = (_y - 0.5) * 2
    newPos.z = 0
    return newPos
end

function processCoordinates(x, y)
    local screenX, screenY = xRes, yRes
    local relativeX = 1 - (x / screenX) * 1.0 * 2
    local relativeY = 1 - (y / screenY) * 1.0 * 2

    if relativeX > 0.0 then
        relativeX = -relativeX;
    else
        relativeX = math.abs(relativeX)
    end
    if relativeY > 0.0 then
        relativeY = -relativeY
    else
        relativeY = math.abs(relativeY)
    end
    return { x = relativeX, y = relativeY }
end

function s2w(camPos, relX, relY)
    local camRot = GetGameplayCamRot(0)
    local camForward = rotationToDirection(camRot)
    local rotUp = addVector3(camRot, { x = 10, y = 0, z = 0 })
    local rotDown = addVector3(camRot, { x = -10, y = 0, z = 0 })
    local rotLeft = addVector3(camRot, { x = 0, y = 0, z = -10 })
    local rotRight = addVector3(camRot, { x = 0, y = 0, z = 10 })

    local camRight = subVector3(rotationToDirection(rotRight), rotationToDirection(rotLeft))
    local camUp = subVector3(rotationToDirection(rotUp), rotationToDirection(rotDown))

    local rollRad = -degToRad(camRot.y)
    local camRightRoll = subVector3(mulNumber(camRight, math.cos(rollRad)), mulNumber(camUp, math.sin(rollRad)))
    local camUpRoll = addVector3(mulNumber(camRight, math.sin(rollRad)), mulNumber(camUp, math.cos(rollRad)))

    local point3D = addVector3(addVector3(addVector3(camPos, mulNumber(camForward, 10.0)), camRightRoll), camUpRoll)

    local point2D = w2s(point3D)

    if point2D == undefined then
        return addVector3(camPos, mulNumber(camForward, 10.0))
    end

    local point3DZero = addVector3(camPos, mulNumber(camForward, 10.0))
    local point2DZero = w2s(point3DZero)

    if point2DZero == nil then
        return addVector3(camPos, mulNumber(camForward, 10.0))
    end

    local eps = 0.001

    if math.abs(point2D.x - point2DZero.x) < eps or math.abs(point2D.y - point2DZero.y) < eps then
        return addVector3(camPos, mulNumber(camForward, 10.0))
    end

    local scaleX = (relX - point2DZero.x) / (point2D.x - point2DZero.x)
    local scaleY = (relY - point2DZero.y) / (point2D.y - point2DZero.y)
    local point3Dret = addVector3(addVector3(addVector3(camPos, mulNumber(camForward, 10.0)), mulNumber(camRightRoll, scaleX)), mulNumber(camUpRoll, scaleY))

    return point3Dret
end

function degToRad(deg)
    return (deg * math.pi) / 180.0
end

function screenToWorld(flags, ignore)
    local x, y = GetNuiCursorPosition()
    local absoluteX = x
    local absoluteY = y
    local camPos = GetGameplayCamCoord()
    local processedCoords = processCoordinates(absoluteX, absoluteY)
    local target = s2w(camPos, processedCoords.x, processedCoords.y)
    local dir = subVector3(target, camPos)
    local from = addVector3(camPos, mulNumber(dir, 0.05))
    local to = addVector3(camPos, mulNumber(dir, 300))
    local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore, 0)
	local a, b, c, d, e = GetShapeTestResult(ray)
    return b, c, e, to
end
