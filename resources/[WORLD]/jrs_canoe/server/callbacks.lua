---------------------------------------------------------------
--[[ Callbacks ]]--
---------------------------------------------------------------

JRS.CreateCallback("jrs_canoe:getStoreStatus", function(source, cb, data)

	local BusyStoresList = GetBusyStoresList()
	
	if JRS.TableLength(BusyStoresList) <= 0 then 
		return cb(false) -- not busy 
	end

	for store, _ in pairs(BusyStoresList) do

		if store == data.index then 
			return cb(true)
		end

	end

	return cb(false)

end)

JRS.CreateCallback("jrs_canoe:canRentSelectedBoat", function(source, cb, data)
	local _source = source
	local xPlayer = JRS.MethodPlayer(_source)
	local store   = type(data) == 'table' and Config.Stores[data.index]
	local canoe   = store and store.Canoes and store.Canoes[data.vehicle_index]
	if not xPlayer or not canoe then return cb(false) end
	if not JRS.Near(_source, store.Coords, (store.DistanceOpenStore or 3.0) + 5.0) then return cb(false) end

	local money   = xPlayer.getAccount(0)
	local cost    = canoe.Cost

	if money < cost then
		SendNotification(_source, Locales['NOT_ENOUGH_MONEY'])
		cb( false )
		return
	end

	xPlayer.removeAccount(0, cost)
	
	SendNotification(_source, Locales['SUCCESSFULLY_RENTED'])

	TriggerClientEvent("jrs_canoe:client:close", _source)
	
	return cb( true )
end)