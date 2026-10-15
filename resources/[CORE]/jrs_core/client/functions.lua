CoreFunctions = {}

CoreFunctions.LoadModel = function(model)
    local model = GetHashKey(model)

    if IsModelValid(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            RequestModel(model)
            Citizen.Wait(100)
        end
    else
        print(model .. " is not valid") -- Concatenations
    end
end

CoreFunctions.LoadTexture = function(hash)
    if not HasStreamedTextureDictLoaded(hash) then
        RequestStreamedTextureDict(hash, true)
        while not HasStreamedTextureDictLoaded(hash) do
            Wait(1)
        end
        return true
    end
    return false
end


CoreFunctions.BigInt  = function(text)
    local string1 = DataView.ArrayBuffer(16)
    string1:SetInt64(0, text)
    return string1:GetInt64(0)
end

CoreFunctions.DrawText  = function(text, font, x, y, fontscale, fontsize, r, g, b, alpha, textcentred, shadow)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    SetTextScale(fontscale, fontsize)
    SetTextColor(r, g, b, alpha)
    SetTextCentre(textcentred)
    if shadow then SetTextDropshadow(1, 0, 0, 0, 255) end
    SetTextFontForCurrentCommand(font)
    DisplayText(str, x, y)
end

CoreFunctions.TeleportToCoords = function(x, y, z, heading)
    local playerPedId = PlayerPedId()
    SetEntityCoords(playerPedId, x, y, z, true, true, true, false)

    if heading then
        SetEntityHeading(playerPedId, heading)
    end

    while not HasCollisionLoadedAroundEntity(PlayerPedId()) do
        Wait(500)
    end

end

CoreFunctions.TeleportPedToCoords = function(ped, x, y, z, heading)
    local playerPedId = ped
    SetEntityCoords(playerPedId, x, y, z, true, true, true, false)

    if heading then
        SetEntityHeading(playerPedId, heading)
    end

    while not HasCollisionLoadedAroundEntity(PlayerPedId()) do
        Wait(500)
    end

end

CoreFunctions.TeleportToWaypoint = function()
    local ped = PlayerPedId()
    if not IsWaypointActive() then return false end

    local originalCoords = GetEntityCoords(ped)
    local coords = GetWaypointCoords()
    local x, y = coords.x, coords.y
    local groundZ = Config.TeleportStartHeight
    local found = false

    DoScreenFadeOut(Config.TeleportFadeOut)
    Wait(Config.TeleportWait)
    FreezeEntityPosition(ped, true)

    for z = Config.TeleportStartPoint, 0, -25.0 do
        SetEntityCoords(ped, x, y, z, false, false, false, true)
        Wait(Config.TeleportWait)
        found, groundZ = GetGroundZAndNormalFor_3dCoord(x, y, z)
        if found then
            SetEntityCoords(ped, x, y, groundZ, false, false, false, true)
            break
        end
    end

    if not found then
        SetEntityCoords(ped, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, true)
    end

    FreezeEntityPosition(ped, false)
    Wait(Config.TeleportWait)
    DoScreenFadeIn(Config.TeleportFadeIn)
    return found
end

CoreFunctions.GetPlayerData = function()
    local result = nil
    local done = false

    TriggerEvent("jrs_core:ExecuteServerCallBack", "jrs:getPlayerData", function(data)
        result = data
        done = true
    end)

    while not done do
        Wait(25)
    end

    return result
end

CoreFunctions.HealPlayer = function()
    local ped = PlayerPedId()

    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, Config.HealInnerCore)
    SetEntityHealth(ped, Config.HealOuterHealth, 1)
    Citizen.InvokeNative(0xC6258F41D86676E0, ped, 1, Config.HealInnerCore)
    Citizen.InvokeNative(0x675680D089BFA21F, ped, Config.HealStaminaFlag)

    SetAttributeCoreValue(ped, 0, Config.HealInnerCore)
    SetEntityHealth(ped, Config.HealOuterHealth, 1)
    SetAttributeCoreValue(ped, 1, Config.HealInnerCore)
    RestorePedStamina(ped, Config.HealStaminaFlag)
end


CoreFunctions.RemoveEntityProperly = function(entity, objectHash)
	DeleteEntity(entity)
	DeletePed(entity)
	SetEntityAsNoLongerNeeded( entity )

	if objectHash then
		SetModelAsNoLongerNeeded(objectHash)
	end
end

