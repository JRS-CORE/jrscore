-- ===========================================================================
-- Social Interactions
-- ===========================================================================

local playerInteractions = Config.GetPlayerInteractions()

RegisterNetEvent('jrs_inventory:hostage')
AddEventHandler('jrs_inventory:hostage', function(who, arg)
	if arg == true then
		if isAttachedToPlayer == false then
			isAttachedToPlayer = true
			playAnim2(Config.Animations.hostageTakeLoop.dict, Config.Animations.hostageTakeLoop.name, Config.Animations.hostageTakeLoop.duration, 25)
			Citizen.CreateThread(function()
				while isAttachedToPlayer == true do
					if IsEntityPlayingAnim(PlayerPedId(), Config.Animations.hostageTakeLoop.dict, Config.Animations.hostageTakeLoop.name, 3) == false then
						playAnim2(Config.Animations.hostageTakeLoop.dict, Config.Animations.hostageTakeLoop.name, Config.Animations.hostageTakeLoop.duration, 25)
						Citizen.Wait(100)
					end
					if GetEntityHealth(PlayerPedId()) <= 0.0 then
						TriggerServerEvent("jrs_inventory:clearHostage", who)
						isAttachedToPlayer = false
						ClearPedTasks(PlayerPedId())
						break
					end
					if Citizen.InvokeNative(0x9682F850056C9ADE, PlayerPedId()) ~= false then
						TriggerServerEvent("jrs_inventory:clearHostage", who)
						isAttachedToPlayer = false
						ClearPedTasks(PlayerPedId())
						break
					end
					if Citizen.InvokeNative(0x305C8DCD79DA8B0F, 0, playerInteractions.ReleaseControlHash) then
						TriggerServerEvent("jrs_inventory:clearHostage", who)
						isAttachedToPlayer = false
						ClearPedTasks(PlayerPedId())
						break
					end
					Citizen.Wait(5)
				end
			end)
		else
			isAttachedToPlayer = false
			ClearPedTasks(PlayerPedId())
			Citizen.Wait(10)
			playAnim2(Config.Animations.hostageRelease.dict, Config.Animations.hostageRelease.name, Config.Animations.hostageRelease.duration, 25)
		end
	else
		if isAttachedToPlayer == false then
			isAttachedToPlayer = true
			playAnim2(Config.Animations.hostageHeldLoop.dict, Config.Animations.hostageHeldLoop.name, Config.Animations.hostageHeldLoop.duration, 1)
			AttachEntityToEntity(PlayerPedId(), GetPlayerPed(GetPlayerFromServerId(who)), 0, -0.15, 0.28, 0.11, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
			Citizen.CreateThread(function()
				while isAttachedToPlayer == true do
					if IsEntityPlayingAnim(PlayerPedId(), Config.Animations.hostageHeldLoop.dict, Config.Animations.hostageHeldLoop.name, 3)  == false then
						playAnim2(Config.Animations.hostageHeldLoop.dict, Config.Animations.hostageHeldLoop.name, Config.Animations.hostageHeldLoop.duration, 25)
						Citizen.Wait(100)
					end
					Citizen.Wait(5)
				end
			end)
		else
			isAttachedToPlayer = false
			ClearPedTasks(PlayerPedId())
			DetachEntity(PlayerPedId(), true, false)
		end
	end
end)

RegisterNetEvent('jrs_inventory:clearHostage')
AddEventHandler('jrs_inventory:clearHostage', function()
	isAttachedToPlayer = false
	ClearPedTasks(PlayerPedId())
	DetachEntity(PlayerPedId(), 1, 1)
end)

RegisterNetEvent('jrs_inventory:send_slap')
AddEventHandler('jrs_inventory:send_slap', function(who, random, take_or_give)
	local closestPlayer, closestDistance, playerid, tgt1 = GetClosestPlayer()
	if closestPlayer ~= -1 and closestDistance <= 2.5 then
		if tonumber(who) == tonumber(playerid) then
			TaskTurnPedToFaceEntity(PlayerPedId(), tgt1, 2000)
			Citizen.Wait(2000)
			local slapAnim = Config.Animations.Slaps[tonumber(random)]
			if slapAnim ~= nil then
				if take_or_give then
					playAnim(slapAnim.dict, slapAnim.attackerName, slapAnim.attackerDuration, 1)
				else
					if slapAnim.victimExtraWaitMs > 0 then
						Citizen.Wait(slapAnim.victimExtraWaitMs)
					end
					playAnim(slapAnim.dict, slapAnim.victimName, slapAnim.victimDuration, 1)
				end
			end
		end
	end
end)

RegisterNetEvent('jrs_inventory:send_hand')
AddEventHandler('jrs_inventory:send_hand', function(who, take_or_give)
	local closestPlayer, closestDistance, playerid, tgt1 = GetClosestPlayer()
	if closestPlayer ~= -1 and closestDistance <= 2.5 then
		if tonumber(who) == tonumber(playerid) then
			TaskTurnPedToFaceEntity(PlayerPedId(), tgt1, 2000)
			Citizen.Wait(1500)
			FreezeEntityPosition(PlayerPedId(), true)
			Citizen.Wait(500)
			if take_or_give then
				SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId())-17.0)
				playAnim2(Config.Animations.giveHandGreet.dict, Config.Animations.giveHandGreet.name, Config.Animations.giveHandGreet.duration, 1)
			else
				SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId())-17.0)
				playAnim2(Config.Animations.giveHandGreet.dict, Config.Animations.giveHandGreet.name, Config.Animations.giveHandGreet.duration, 1)
			end
			Citizen.Wait(100)
			FreezeEntityPosition(PlayerPedId(), false)
		end
	end
end)

RegisterNetEvent('jrs_inventory:turn_client')
AddEventHandler('jrs_inventory:turn_client', function(who, manipulation)
	TriggerEvent('jrs_inventory:CloseInv')

	local targetPed = nil
	local targetServerId = tonumber(who)
	if targetServerId then
		local playerIndex = GetPlayerFromServerId(targetServerId)
		if playerIndex and playerIndex ~= -1 then
			local ped = GetPlayerPed(playerIndex)
			if ped and ped ~= 0 and DoesEntityExist(ped) then
				targetPed = ped
			end
		end
	end

	if not targetPed then
		local closestPlayer, closestDistance, playerid, tgt1 = GetClosestPlayer()
		if closestPlayer ~= -1 and closestDistance <= 5.0 then
			if not targetServerId or targetServerId == tonumber(playerid) then
				targetPed = tgt1
			end
		end
	end

	if targetPed and DoesEntityExist(targetPed) then
		if tonumber(manipulation) == 1 then
			TaskTurnPedToFaceEntity(PlayerPedId(), targetPed, 3000)
			Citizen.Wait(2000)
			playAnim(Config.Animations.giveRat.dict, Config.Animations.giveRat.name, Config.Animations.giveRat.duration, 25)
		else
			TaskTurnPedToFaceEntity(PlayerPedId(), targetPed, 2500)
			Citizen.Wait(3200)
			playAnim(Config.Animations.holsterPocketwatch.dict, Config.Animations.holsterPocketwatch.name, Config.Animations.holsterPocketwatch.duration, 25)
		end
	end
end)
