local AttachedProps = {}

---------------------------------------------------------------
--[[ Local Functions ]]--
---------------------------------------------------------------

local function HasPlayerPedAttachedPropType(attachedType)

	local foundResult = false

	if JRS.TableLength(AttachedProps) > 0 then

		for k, v in pairs(AttachedProps) do

			if v.type == attachedType then
				return true
			end

		end

	end

	return false
end


local ClearPlayerPedAttachedPropsByType = function(attachedType)

	-- First remove all entities belonging to this attached type.
	for k, v in pairs(AttachedProps) do

		if v.type == attachedType then

			for i, object in pairs(v.entities) do

				Wait(100)

				RemoveEntityProperly(
					object.entity,
					GetHashKey(object.model)
				)

			end

		end

	end

	Wait(1000)

	-- Rebuild the table without the removed attached type.
	-- This avoids modifying AttachedProps while iterating over it.
	local newAttachedProps = {}

	for k, v in ipairs(AttachedProps) do

		if v.type ~= attachedType then
			table.insert(newAttachedProps, v)
		end

	end

	AttachedProps = newAttachedProps
end


local function OnPlayerPedAttachedPropType(attachedType)

	Wait(1000)

	if Config.AttachedItemSets[attachedType] then

		local player = PlayerPedId()
		local hasAttachedAlready = HasPlayerPedAttachedPropType(attachedType)

		if not hasAttachedAlready then

			ClearPedTasksImmediately(player)
			ClearPedSecondaryTask(player)

			Citizen.InvokeNative(
				0xFCCC886EDE3C63EC,
				player,
				2,
				1
			) -- Removes Weapon from animation

			local entitiesList = {}
			local coords = GetEntityCoords(player)

			for obj_key, obj_table in pairs(Config.AttachedItemSets[attachedType]) do

				LoadModel(obj_table.EntityObject)

				local prop = CreateObject(
					obj_table.EntityObject,
					coords.x,
					coords.y,
					coords.z,
					0.2,
					true,
					true,
					false,
					false,
					true
				)

				table.insert(entitiesList, {
					entity = prop,
					model = obj_table.EntityObject
				})

				local boneIndex = GetEntityBoneIndexByName(
					player,
					obj_table.Attachment
				)

				AttachEntityToEntity(
					prop,
					player,
					boneIndex,
					obj_table.x,
					obj_table.y,
					obj_table.z,
					obj_table.xRot,
					obj_table.yRot,
					obj_table.zRot,
					true,
					true,
					false,
					true,
					1,
					true
				)

				Wait(100)

			end

			table.insert(AttachedProps, {
				type = attachedType,
				entities = entitiesList
			})

		else

			ClearPedTasksImmediately(player)
			ClearPedSecondaryTask(player)

			ClearPlayerPedAttachedPropsByType(attachedType)

		end

	else

		print(string.format(
			"This attached prop item set type (%s) does not exist",
			attachedType
		))

	end

end


---------------------------------------------------------------
--[[ Functions ]]--
---------------------------------------------------------------

ClearAllPlayerPedAttachedProps = function()

	local player = PlayerPedId()

	if JRS.TableLength(AttachedProps) > 0 then

		for k, v in pairs(AttachedProps) do

			for i, object in pairs(v.entities) do

				RemoveEntityProperly(
					object.entity,
					GetHashKey(object.model)
				)

			end

		end

		ClearPedTasksImmediately(player)
		ClearPedSecondaryTask(player)

		AttachedProps = {}

	end

end


---------------------------------------------------------------
--[[ Base Events ]]--
---------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)

	if resource ~= GetCurrentResourceName() then
		return
	end

	ClearAllPlayerPedAttachedProps()

end)


RegisterNetEvent('jrs_core:Client:OnPlayerSpawned')
AddEventHandler('jrs_core:Client:OnPlayerSpawned', function()

	if not Config.DeleteAllOnPlayerRespawn then
		return
	end

	ClearAllPlayerPedAttachedProps()

end)


---------------------------------------------------------------
--[[ General Events ]]--
---------------------------------------------------------------

RegisterNetEvent('jrs_attached_objects:client:attach')
AddEventHandler('jrs_attached_objects:client:attach', function(attachedType)

	OnPlayerPedAttachedPropType(attachedType)

end)
