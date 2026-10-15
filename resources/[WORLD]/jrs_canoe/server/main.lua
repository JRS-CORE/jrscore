local BusyStoresList = {}

---------------------------------------------------------------
--[[ Callbacks ]]--
---------------------------------------------------------------

function GetBusyStoresList()
	return BusyStoresList
end

---------------------------------------------------------------
--[[ Events ]]--
---------------------------------------------------------------


AddEventHandler("onResourceStop", function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

	BusyStoresList = nil
end)

local BusyBy = {} -- store index -> source that is building there

RegisterServerEvent('jrs_canoe:server:start_building')
AddEventHandler('jrs_canoe:server:start_building', function(index)
	local _source = source
	local store = Config.Stores[tonumber(index) or index]
	if not store or BusyBy[index] ~= _source then return end
	local coords = vector3(store.SpawnCoords.x, store.SpawnCoords.y, store.SpawnCoords.z)
	JRS.TriggerNearby("jrs_canoe:client:start_building", { index = index }, coords, 50.0)
end)

RegisterServerEvent('jrs_canoe:server:setBusyState')
AddEventHandler('jrs_canoe:server:setBusyState', function(index, cb)
	local _source = source
	local store = Config.Stores[index]
	if not store then return end
	if cb == true then
		if BusyBy[index] and BusyBy[index] ~= _source then return end
		if not JRS.Near(_source, store.Coords, (store.DistanceOpenStore or 3.0) + 5.0) then return end
		BusyBy[index] = _source
		BusyStoresList[index] = true
	elseif BusyBy[index] == _source then
		BusyBy[index] = nil
		BusyStoresList[index] = nil
	end
end)

AddEventHandler('playerDropped', function()
	local _source = source
	for index, who in pairs(BusyBy) do
		if who == _source then
			BusyBy[index] = nil
			if BusyStoresList then BusyStoresList[index] = nil end
		end
	end
end)