
---------------------------------------------------------------
--[[ Items ]]--
---------------------------------------------------------------

Citizen.CreateThread(function()

	for item, data in pairs (Config.AttachedItemSets) do

		JRS.UsableData(item, "jrs_attached_objects", function(data)
			local _source = data.source

			TriggerClientEvent("jrs_attached_objects:client:attach", _source, item)
			TriggerClientEvent('jrs_inventory:CloseInv', _source)
		end)

	end

end)
