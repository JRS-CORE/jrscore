
-----------------------------------------------------------
--[[ Items Registration  ]]--
-----------------------------------------------------------

JRS.UsableData(Config.PassportItem, "jrs_passports", function(data)
	local _source  = data.source
	local metadata = data.metadata

	exports.oxmysql:execute('SELECT * FROM `passports` WHERE `identityId` = @identityId', { ['identityId'] = metadata.identityId }, function(result)
		
		-- If the player is has no passport registration, we don't display, we return.
		if (result == nil ) or ( result and result[1] == nil ) then
			return
		end

		local res = result[1] -- retrieves all passport data since identityId is valid.


		-- Expiration Date to string.
		local date_string = os.date("%Y-%m-%d %H:%M:%S", res.expiration_date)
		local new_date_string = date_string:gsub("^%d%d%d%d", Config.Year)

		res.expiration_date = new_date_string

		local coords        = GetEntityCoords(GetPlayerPed(_source))
		local onlinePlayers = JRS.Players()

		for index, player in pairs(onlinePlayers.players) do

			local targetSource = tonumber(player.source)
			local targetCoords = GetEntityCoords(GetPlayerPed(targetSource))
			local distance     = #(coords - targetCoords)

			if distance <= Config.DisplayPassportCardDistance then

				TriggerClientEvent('jrs_inventory:CloseInv', targetSource)
				Wait(500)
				TriggerClientEvent('jrs_passports:client:onPassportItemUse', targetSource, res)

			end

		end

	end)

end)
