
---------------------------------------------------------------
--[[ General Events ]]--
---------------------------------------------------------------

RegisterNetEvent("jrs_usable_items:remove")
AddEventHandler("jrs_usable_items:remove", function(itemName)
	local _source = source

	if Config.UsableItems[itemName] == nil then
		return
	end

	JRS.Remove(_source, itemName, 1)

end)

---------------------------------------------------------------
--[[ Items ]]--
---------------------------------------------------------------

Citizen.CreateThread(function()

	for item, itemData in pairs (Config.UsableItems) do

		JRS.UsableData(item, "jrs_usable_items", function(data)
			local _source = data.source

			if itemData.RequiredItemUse.Enabled then 
				local itemQuantity = JRS.Count(_source, itemData.RequiredItemUse.Item)

				if itemQuantity < itemData.RequiredItemUse.Quantity then
					SendNotification(_source, itemData.RequiredItemUse.Warning, "error")
					return
				end

			end

			if itemData.RemoveDurabilityOnUse.Enabled then
				local randomValueRemove = math.random(itemData.RemoveDurabilityOnUse.RemoveValue.min, itemData.RemoveDurabilityOnUse.RemoveValue.max)
				JRS.Noop(_source, item, randomValueRemove, item.itemId, true)
			end

			if itemData.RequiredItemUse.Enabled and itemData.RequiredItemUse.Remove then 
				JRS.Remove(_source, itemData.RequiredItemUse.Item, itemData.RequiredItemUse.Quantity)
			end

			TriggerClientEvent("jrs_usable_items:client:use", _source, item)
			TriggerClientEvent('jrs_inventory:CloseInv', _source)
		end)

	end

end)
