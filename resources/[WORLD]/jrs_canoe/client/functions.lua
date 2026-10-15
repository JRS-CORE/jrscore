local PromptGroup  = GetRandomIntInRange(0, 0xffffff)
local PromptList   = nil

local CanoeObjectEntityPromptGroup = GetRandomIntInRange(0, 0xffffff)
local CanoeObjectEntityPrompt = nil

--[[-------------------------------------------------------
 Base Events
]]---------------------------------------------------------

AddEventHandler("onResourceStop", function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    if PromptList then PromptDelete(PromptList) end
    if CanoeObjectEntityPrompt then PromptDelete(CanoeObjectEntityPrompt) end

    if GetPlayerData().IsBusy == true then
        ClearPedTasksImmediately(PlayerPedId())
    end

    for i, v in pairs(Config.Stores) do

        if v.BlipHandle then
            RemoveBlip(v.BlipHandle)
        end

        if v.NPC then
            DeleteEntity(v.NPC)
            DeletePed(v.NPC)
            SetEntityAsNoLongerNeeded(v.NPC)
        end

    end
    
    if Config.UseInteractPrompt then 
        JRS.RemoveModelTarget(Config.Models, Config.ModelsTargetOptions)
    end

end)


--[[-------------------------------------------------------
 Blips
]]---------------------------------------------------------


function AddBlip(Store, StatusType)

    if Config.Stores[Store].BlipData then

        local BlipData = Config.Stores[Store].BlipData

        local sprite, blipModifier = BlipData.Sprite, 'BLIP_MODIFIER_MP_COLOR_32'

        if BlipData.OpenBlipModifier then
            blipModifier = BlipData.OpenBlipModifier
        end

        if StatusType == 'CLOSED' then
            sprite = BlipData.DisplayClosedHours.Sprite
            blipModifier = BlipData.DisplayClosedHours.BlipModifier
        end
        
        Config.Stores[Store].BlipHandle = N_0x554d9d53f696d002(1664425300, Config.Stores[Store].Coords.x, Config.Stores[Store].Coords.y, Config.Stores[Store].Coords.z)

        SetBlipSprite(Config.Stores[Store].BlipHandle, sprite, 1)
        SetBlipScale(Config.Stores[Store].BlipHandle, 0.2)

        Citizen.InvokeNative(0x662D364ABF16DE2F, Config.Stores[Store].BlipHandle, joaat(blipModifier))

        Config.Stores[Store].BlipHandleModifier = blipModifier

        Citizen.InvokeNative(0x9CB1A1623062F402, Config.Stores[Store].BlipHandle, BlipData.Name)

    end
end

--[[-------------------------------------------------------
 Prompt Set Up Function
]]---------------------------------------------------------

RegisterCanoeDropActionPrompt = function()

    local str = Config.CanoeActionPrompt.Label

    CanoeObjectEntityPrompt = PromptRegisterBegin()
    PromptSetControlAction(CanoeObjectEntityPrompt, Config.CanoeActionPrompt.Key)
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(CanoeObjectEntityPrompt, str)
    PromptSetEnabled(CanoeObjectEntityPrompt, 1)
    PromptSetVisible(CanoeObjectEntityPrompt, 1)
    PromptSetStandardMode(CanoeObjectEntityPrompt, 1)
    PromptSetGroup(CanoeObjectEntityPrompt, CanoeObjectEntityPromptGroup)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, CanoeObjectEntityPrompt, true)
    PromptRegisterEnd(CanoeObjectEntityPrompt)
end

function GetCanoeActionPromptData()
    return CanoeObjectEntityPromptGroup, CanoeObjectEntityPrompt
end

CreatePromptRegistration = function()
    local str = LocalesEN["PROMPT_TEXT"]
    PromptList = PromptRegisterBegin()
    PromptSetControlAction(PromptList, Config.PromptAction.Key)
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(PromptList, str)
    PromptSetEnabled(PromptList, 1)
    PromptSetVisible(PromptList, 1)
    PromptSetStandardMode(PromptList, 1)
    PromptSetHoldMode(PromptList, Config.PromptAction.HoldMode)
    PromptSetGroup(PromptList, PromptGroup)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, PromptList, true)
    PromptRegisterEnd(PromptList)
end

GetPromptData = function ()
    return PromptGroup, PromptList
end

--[[-------------------------------------------------------
 Closest Vehicles Function
]]---------------------------------------------------------

local volumeArea = Citizen.InvokeNative(0xB3FB80A32BAE3065, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0) -- _CREATE_VOLUME_SPHERE

function GetClosestVehicle(coords, range)
	local itemSet2  = CreateItemset(true)

    local vehiclesToDraw = {}
    if volumeArea then 
        Citizen.InvokeNative(0x541B8576615C33DE, volumeArea, coords.x, coords.y, coords.z) -- SET_VOLUME_COORDS
        local itemsFound = Citizen.InvokeNative(0x886171A12F400B89, volumeArea, itemSet2, 2) -- Get volume items into itemset
        if itemsFound then
            local n = 0
            while n < itemsFound do
                vehiclesToDraw[(GetIndexedItemInItemset(n, itemSet2))] = true
                n = n + 1
            end
        end
        Citizen.InvokeNative(0x20A4BF0E09BEE146, itemSet2)
        for k,v in pairs(vehiclesToDraw) do 
            Citizen.InvokeNative(0x20A4BF0E09BEE146, itemSet2)
            return k
        end
        
    end
    if IsItemsetValid(itemSet2) then
        Citizen.InvokeNative(0x20A4BF0E09BEE146, itemSet2)
    end
end


--[[-------------------------------------------------------
 Notifications
]]---------------------------------------------------------

ShowNotification = function(_message, rgbData, timer)

    if timer == nil or timer == 0 then
        timer = 200
    end
    local r, g, b, a = 161, 3, 0, 255

    if rgbData then
        r, g, b, a = rgbData.r, rgbData.g, rgbData.b, rgbData.a
    end

	while timer > 0 do
		DisplayHelp(_message, 0.50, 0.90, 0.6, 0.6, true, r, g, b, a, true)

		timer = timer - 1
		Citizen.Wait(0)
	end

end

DisplayHelp = function(_message, x, y, w, h, enableShadow, col1, col2, col3, a, centre)

	local str = CreateVarString(10, "LITERAL_STRING", _message, Citizen.ResultAsLong())

	SetTextScale(w, h)
	SetTextColor(col1, col2, col3, a)

	SetTextCentre(centre)

	if enableShadow then
		SetTextDropshadow(1, 0, 0, 0, 255)
	end

	Citizen.InvokeNative(0xADA9255D, 10);

	DisplayText(str, x, y)

end

--[[-------------------------------------------------------
 NPC Functions
]]---------------------------------------------------------

SpawnNPC = function(index)
    local v = Config.Stores[index]

    LoadModel(v.NPCData.Model)

    local coords = v.NPCData.Coords
    local npc = CreatePed(v.NPCData.Model, coords.x, coords.y, coords.z, coords.h, false, true, true, true)

    Citizen.InvokeNative(0x283978A15512B2FE, npc, true) -- SetRandomOutfitVariation
    SetEntityNoCollisionEntity(PlayerPedId(), npc, false)
    SetEntityCanBeDamaged(npc, false)
    SetEntityInvincible(npc, true)
    Wait(1000)
    FreezeEntityPosition(npc, true) -- NPC can't escape
    SetBlockingOfNonTemporaryEvents(npc, true) -- NPC can't be scared

    Config.Stores[index].NPC = npc

    if Config.UseInteractPrompt then

        local options = {
            {
                label = v.PromptName,
                icon = v.TargetIcon,
                distance = v.TargetDistance,

                onSelect = function(data)
                    OpenCanoeRentingShop(index, v.City)
                end,

                description = ""
            }
        }

        JRS.AddEntityTarget(Config.Stores[index].NPC, options)
    end

end

LoadModel = function(model)
    model = type(model) == 'string' and joaat(model) or model
    RequestModel(model)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        RequestModel(model)
        Citizen.Wait(100)
    end
    return HasModelLoaded(model)
end

--[[-------------------------------------------------------
 Canoe Functions
]]---------------------------------------------------------

function IsModelCanoe(inputModel)

    for _, model in pairs (Config.Models) do 

        if inputModel == joaat(model) then 
            return true
        end

    end

    return false

end

function IsCarryingCanoe()
    local ped    = PlayerPedId()

    local retval = IsPedCarryingSomething(ped)

    if not retval then return false end

	local coords         = GetEntityCoords(ped)
    local closestVehicle = GetClosestVehicle(coords)
    local vehNetId       = Citizen.InvokeNative(0xB4C94523F023419C, closestVehicle)
    local netToVeh       = Citizen.InvokeNative(0x367B936610BA360C, vehNetId)
    local entityModel    = GetEntityModel(netToVeh)

    if DoesEntityExist(netToVeh) and IsEntityAttached(netToVeh) then

        local isModelCanoe = IsModelCanoe(entityModel)

        if isModelCanoe then
            return true, netToVeh
        end
    end

    return false, 0
end

function DropCarriedCanoe()
    local playerPed  = PlayerPedId()

    local retval, canoeEntity = IsCarryingCanoe()

	if retval then

		FreezeEntityPosition(playerPed, true)
		TaskStandStill(PlayerPedId(), -1)

		DetachEntity(canoeEntity, nil, nil)
		SetEntityHeading(canoeEntity, GetEntityHeading(playerPed))
		ClearPedTasksImmediately(playerPed)
		PickedUpCanoe = false
		canoeEntity = nil

		Wait(1000)
		FreezeEntityPosition(playerPed, false)
		TaskStandStill(PlayerPedId(), 1)
	end
end

function PickupClosestCanoe()

    local playerPed = PlayerPedId()
	local coords = GetEntityCoords(playerPed)
    
    local retval, canoeEntity = IsCarryingCanoe()

	if not retval then

		local closestVehicle = GetClosestVehicle(coords)

        local vehNetId = Citizen.InvokeNative(0xB4C94523F023419C, closestVehicle)
        local netToVeh = Citizen.InvokeNative(0x367B936610BA360C, vehNetId)

		local entityModel  = GetEntityModel(netToVeh)
        local isModelCanoe = IsModelCanoe(entityModel)

		if isModelCanoe then

            -- Making the vehicle entity as net id, in order for everyone to carry it.
            if NetworkDoesNetworkIdExist(vehNetId) then

                SetVehicleAsNoLongerNeeded(netToVeh)

                NetworkRequestControlOfNetworkId(vehNetId)
                NetworkRequestControlOfEntity(netToVeh)
                SetVehicleHasBeenOwnedByPlayer(netToVeh, true)

                SetCurrentPedWeapon(playerPed, joaat("WEAPON_UNARMED"), true, 0, false, false)

                Wait(1000)

                JRS.PlayAnimation(playerPed, { 
                    dict = "mech_carry_box", 
                    name = "idle",
                    blendInSpeed = 1.0,
                    blendOutSpeed = 8.0,
                    duration = -1,
                    flag = 31,
                    playbackRate = 0.0
                })

                Citizen.InvokeNative(0x6B9BBD38AB0796DF, netToVeh, playerPed, GetEntityBoneIndexByName(playerPed,"SKEL_L_Finger12"), 0.20, 0.00, -0.05, 240.0, 190.0, 0.0, true, true, false, true, 1, true)

                Wait(500)
                TriggerEvent('jrs_canoe:client:tasks')

            end
		end

	end

end