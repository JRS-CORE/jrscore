local MenuData = exports.jrs_core:GetMenuData()

------------------------------------------------------------------
-- Local Functions
------------------------------------------------------------------

local function StartRentingProccess(data)

	local locationIndex = GetPlayerData().LocationIndex

	local data = {
		model         = data.model, 
		name          = data.name,
		index         = locationIndex,
		vehicle_index = data.index,
	}

	local cb = JRS.Await('jrs_canoe:canRentSelectedBoat', data )
	
	if cb then

		local coords = Config.Stores[locationIndex].SpawnCoords

		TriggerServerEvent("jrs_canoe:server:start_building", locationIndex)

		Wait(22000)

		LoadModel(data.model)

		local vehicleEntity = CreateVehicle(data.model, coords.x, coords.y, coords.z, coords.h, true, false)

		Citizen.InvokeNative(0x283978A15512B2FE, vehicleEntity, true)
		SetModelAsNoLongerNeeded(data.model)

		TriggerServerEvent("jrs_canoe:server:setBusyState", locationIndex, false)

		SendNotification(nil, Locales['CANOE_READY'])
	end

end


------------------------------------------------------------------
-- Functions
------------------------------------------------------------------

OpenCanoeRentingShop = function(index, title)

    MenuData.CloseAll()

	local PlayerData = GetPlayerData()
	
	local player = PlayerPedId()
	local cb     = JRS.Await('jrs_canoe:getStoreStatus', { index = index } )

	if cb then
		SendNotification(nil, Locales['STORE_BUSY'])
		return
	end

	local coords         = Config.Stores[index].SpawnCoords
	local closestVehicle = GetClosestVehicle(coords)
	local entityModel    = GetEntityModel(closestVehicle)
	local isModelCanoe   = IsModelCanoe(entityModel)

	if isModelCanoe then
		SendNotification(nil, Locales['STORE_PICKUP'])
		return
	end

	PlayerData.IsBusy = true
	PlayerData.LocationIndex = index
	TaskStandStill(PlayerPedId(), -1)

	TriggerServerEvent("jrs_canoe:server:setBusyState", index, true)
	TriggerEvent("jrs_canoe:client:menu_tasks")

	local elements = {}

	for k, v in pairs(Config.Stores[index].Canoes) do

		table.insert(elements, {
			label      = v.Title,
			rightLabel = '$' .. tostring(v.Cost),
			image      = 'nui://jrs_canoe/html/img/' .. v.ImageBackground,
			desc       = ('%s: %s'):format(v.DescriptionTitle, v.Description),
			value      = k,
			index      = k,
			model      = v.Model,
			name       = v.Title,
		})

	end


	table.insert(elements, { value = "exit", label = Locales['MENU_EXIT'], desc = "" })

	MenuData.Open('default', GetCurrentResourceName(), 'canoes',

    {
        title    = title,
        subtext  = "",
        align    = "top-left",
        elements = elements,
        lastmenu = "notMenu"
    },

    function(data, menu)
        if data.current == "backup" or data.current.value == "exit" then
			menu.close()
			PlayerData.IsBusy = false
			PlayerData.LocationIndex = nil
			TaskStandStill(PlayerPedId(), 1)

			TriggerServerEvent("jrs_canoe:server:setBusyState", index, false)
            return
        end

		local current = data.current
		CreateThread(function() StartRentingProccess(current) end)
		
    end,

    function(data, menu)
        menu.close()
        PlayerData.IsBusy = false
		PlayerData.LocationIndex = nil
        TaskStandStill(PlayerPedId(), 1)
		
		TriggerServerEvent("jrs_canoe:server:setBusyState", index, false)
    end)

end

------------------------------------------------------------------
-- Events
------------------------------------------------------------------

RegisterNetEvent("jrs_canoe:client:close") 
AddEventHandler("jrs_canoe:client:close", function() 
    MenuData.CloseAll()
	
	local PlayerData = GetPlayerData()

	PlayerData.IsBusy = false
	PlayerData.LocationIndex = nil
	TaskStandStill(PlayerPedId(), 1)
end)

AddEventHandler("onResourceStop", function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

	local PlayerData = GetPlayerData()

	if PlayerData.IsBusy then 
		MenuData.CloseAll()
	end

end)

RegisterNetEvent("jrs_canoe:client:start_building")
AddEventHandler("jrs_canoe:client:start_building", function(data)

	local index = data.index

	LoadModel('p_canoeconst01x')

	local coords = Config.Stores[index].SpawnCoords
	local brokenVehicleEntity = CreateObject('p_canoeconst01x', coords.x, coords.y, coords.z, false, false)
	SetEntityHeading(brokenVehicleEntity, coords.h)

	Wait(250)
	FreezeEntityPosition(brokenVehicleEntity, true)
	
	local npc = Config.Stores[index].NPC

	JRS.PlayAnimation(npc, { 
		dict = "amb_work@world_human_hammer@table@male_a@idle_b", 
		name = "idle_e",
		blendInSpeed = 1.0,
		blendOutSpeed = 1.0,
		duration = -1,
		flag = 31,
		playbackRate = 0.0
	})

	Wait(19 * 1000)

	JRS.RemoveEntity(brokenVehicleEntity, joaat('p_canoeconst01x'))

	Wait(1000)
	StopAnimTask(npc, "amb_work@world_human_hammer@table@male_a@idle_b", "idle_e", 31)
end)

AddEventHandler('jrs_canoe:client:menu_tasks', function()

	Citizen.CreateThread(function()

		while GetPlayerData().IsBusy do 
			Wait(1)
			DisplayRadar(false)
		end

	end)

end)