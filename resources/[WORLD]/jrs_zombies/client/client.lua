
local spawnedZombies = {}
local zombiespawned = false
local spawnedAmount = 0
local zombiedetected = false

---------------------------------------------------------
-- trigger server spawn zombies
---------------------------------------------------------
Citizen.CreateThread(function()

    AddRelationshipGroup("zombie")
    SetRelationshipBetweenGroups(5, joaat("zombie"), joaat("PLAYER"))
    SetRelationshipBetweenGroups(5, joaat("PLAYER"), joaat("zombie"))

    while true do
        Wait(1000)
        local player = PlayerPedId()
        local ZoneTypeId = 1
        local x,y,z =  table.unpack(GetEntityCoords(player))
        local town = Citizen.InvokeNative(0x43AD8FC02B429D33, x,y,z, ZoneTypeId)
		TriggerServerEvent('jrs_zombies:server:triggerzombies', town)
    end
end)

---------------------------------------------------------
-- spawn zombies
---------------------------------------------------------
RegisterNetEvent('jrs_zombies:client:spawnzombies', function(town)
	for k,v in pairs(Config.ZombieSpawnLocations) do
		if town == v.town then
			if spawnedAmount < v.maxamount then
				local zombiemodel = Config.ZombieModels[math.random(1, #Config.ZombieModels)]
				local spawnedPed = SpawnZombie(zombiemodel.model, v.spawnpoint, zombiemodel.outfit)
				table.insert(spawnedZombies, spawnedPed)
				spawnedAmount = spawnedAmount + 1
				Wait(1000)
			end
		elseif town == false then
			for k,v in pairs(spawnedZombies) do
				DeletePed(v)
				SetEntityAsNoLongerNeeded(v)
				table.remove(spawnedZombies, k)
				spawnedAmount = spawnedAmount - 1
			end
		end
	end
end)

---------------------------------------------------------
-- cleanup dead zombies for respawn
---------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        for k,v in pairs(spawnedZombies) do
            if IsEntityDead(v) then
                Wait(Config.ZombieDeleteTime)
                DeletePed(v)
                SetEntityAsNoLongerNeeded(v)
                table.remove(spawnedZombies, k)
                spawnedAmount = spawnedAmount - 1
            end
        end
    end
end)

---------------------------------------------------------
-- spawn zombie when in distance
---------------------------------------------------------
function SpawnZombie(model, spawnpoint, outfit)
    RequestModel(model)
    DecorRegister("zombie", 2)
    while not HasModelLoaded(model) do
        Citizen.Wait(50)
    end
    spawnedPed = CreatePed(model, spawnpoint.x, spawnpoint.y, spawnpoint.z - 1.0, spawnpoint.w, true, false, 0, 0)
    DecorSetBool(spawnedPed, "zombie", true)
    SetPedOutfitPreset(spawnedPed, outfit)

    -- zombie settings
    SetPedSeeingRange(spawnedPed, Config.ZombieSeeingRange)
    SetPedHearingRange(spawnedPed, Config.ZombieHearingRange)
    SetPedCombatAttributes(spawnedPed, 46, true)
    StopPedSpeaking(spawnedPed, true)
    SetPedRelationshipGroupHash(spawnedPed, joaat("zombie"))
    SetPedPromptName(spawnedPed, 'Zombie')
    SetPedFleeAttributes(spawnedPed, 0, 0)
    TaskSetBlockingOfNonTemporaryEvents(spawnedPed, true)

    -- set zombie walk
    walk = Config.Walks[math.random(1, #Config.Walks)]
    Citizen.InvokeNative(0x923583741DC87BCE, spawnedPed, walk[1])
    Citizen.InvokeNative(0x89F5E7ADECCCB49C, spawnedPed, walk[2])

    -- show zombie blips (config for on/off)
    if Config.ShowZombieBlips then
        Citizen.InvokeNative(0x23f74c2fda6e7c61, Config.ZombieBlipSprite, spawnedPed)
    end

    TaskWanderStandard(spawnedPed, 10.0, 10)

    return spawnedPed

end

---------------------------------------------------------
-- play zombie sounds when close to the player
---------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(3000)

        for _,v in pairs(spawnedZombies) do

            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local zpos = GetEntityCoords(v)
            local dist = #(pos - zpos)
            local zombieDead = IsEntityDead(v)
            local randomChance = math.random(1,99)
            
            if randomChance >= 50 then
                if dist <= 20.0 and zpos ~= nil then
                        exports['jrs_zombies_notify']:Alert("zombie_aggressive_1", "", 100, 'zombie_aggressive_1')
                      --  print("zombies_Notify 20 : ")
                end

                if dist <= 10.0 and zpos ~= nil then
                     exports['jrs_zombies_notify']:Alert("zombie_aggressive_1", "", 100, 'zombie_aggressive_1')
                   --  print("zombies_Notify 10 : ")
                end

                if dist <= 5.0 and zpos ~= nil then
                    exports['jrs_zombies_notify']:Alert("zombie_growl_2", "", 100, 'zombie_growl_2')
                  --  print("zombies_Notify 5 : ")
               end

            end
        end
    end
end)



---------------------------------------------------------
-- attack players based on distance
---------------------------------------------------------
if Config.AttackPlayersBasedOnDistance then

    CreateThread(function()
        while true do
            Wait(Config.DistanceAttackData.SleepTime)
            StartHuntingPlayerOnDistance()
        end
    end)

    StartHuntingPlayerOnDistance = function()

        for _,v in pairs(spawnedZombies) do

            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local zpos = GetEntityCoords(v)
            local distance = #(pos - zpos)

            local requiredDistance = 0

            local isdead = IsEntityDead(ped)
            local isPlayerCrouching = Citizen.InvokeNative(0xD5FE956C70FF370B, ped)
            local isPedRunning = Citizen.InvokeNative(0xC5286FFC176F28A2, ped)
            local isPedWalking = Citizen.InvokeNative(0xDE4C184B2B9B071A, ped)

            -- set crouching & walking
            if isPlayerCrouching and isPedWalking then
                requiredDistance = Config.DistanceAttackData.Crouching
            end

            -- set walking but not crouching
            if isPedWalking and not isPlayerCrouching then
                requiredDistance = Config.DistanceAttackData.Walking
            end

            -- set running
            if isPedRunning then
                requiredDistance = Config.DistanceAttackData.Running
            end

            if distance <= requiredDistance and not isDead and not zombiedetected then
                TaskGoToEntity(v, PlayerPedId(), -1, 0.0, 500.0, 1073741824, 0)
                TaskCombatPed(v, PlayerPedId())
                zombiedetected = true
            else
                TaskWanderStandard(v, 10.0, 10)
                zombiedetected = false
            end

        end
    end
end

---------------------------------------------------------
-- destroy zombies
---------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if (resource == GetCurrentResourceName()) then
        for k,v in pairs(spawnedZombies) do
            DeletePed(v)
            SetEntityAsNoLongerNeeded(v)
        end
    end
end)
