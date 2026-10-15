-- JRS independent wildlife population & ambient spawner controller.
-- Ensures wild animals spawn reliably and consistently across all biomes in RedM OneSync.

local AMBIENT_ANIMAL_DENSITY = 0xC0258742B034DFAF
local SCENARIO_ANIMAL_DENSITY = 0xDB48E99F8E064E56
local AMBIENT_PED_RANGE = 0x0B919E1FB47CC4E0

local function clampDensity(value, fallback)
    value = tonumber(value) or fallback or 1.0
    if value < 0.0 then return 0.0 end
    if value > 5.0 then return 5.0 end
    return value
end

-- Safezone Wildlife Suppression:
-- Any jrs_safezone safezone (cities, towns, camps, RP zones, house zones)
-- completely suppresses wildlife and predators.
local inCityZone = false
local inAnySafeZone = false

Citizen.CreateThread(function()
    while true do
        local inCity = false
        local inSafe = false
        if LocalPlayer and LocalPlayer.state then
            if LocalPlayer.state.safezoneIsCity ~= nil then
                inCity = LocalPlayer.state.safezoneIsCity == true
            end
            if LocalPlayer.state.inSafeZone ~= nil then
                inSafe = LocalPlayer.state.inSafeZone == true
            end
        end
        if GetResourceState('jrs_safezone') == 'started' then
            if not inSafe then
                local ok, active = pcall(function() return exports['jrs_safezone']:IsSafeZoneActive() end)
                if ok and active then inSafe = true end
            end
            if not inCity then
                local ok, zone = pcall(function() return exports['jrs_safezone']:GetCurrentSafeZone() end)
                if ok and type(zone) == 'table' and zone.isCity == true then inCity = true end
            end
            if not inSafe then
                local ped = PlayerPedId()
                if ped ~= 0 and DoesEntityExist(ped) then
                    local pCoords = GetEntityCoords(ped)
                    local ok, near = pcall(function() return exports['jrs_safezone']:IsNearAnySafeZone(pCoords, 50.0) end)
                    if ok and near then inSafe = true end
                end
            end
        end
        inCityZone = inCity
        inAnySafeZone = inSafe
        Citizen.Wait(800)
    end
end)

-- Native per-frame density & range multiplier thread
Citizen.CreateThread(function()
    while true do
        local cfg = Config.Animals
        if cfg and cfg.enabled == true then
            if inCityZone or inAnySafeZone then
                local density = clampDensity(cfg.cityFrequency, 0.0)
                Citizen.InvokeNative(AMBIENT_ANIMAL_DENSITY, density)
                Citizen.InvokeNative(SCENARIO_ANIMAL_DENSITY, density)
            else
                local ambDensity = clampDensity(cfg.ambientFrequency, 1.0)
                local scenDensity = clampDensity(cfg.scenarioFrequency, 1.0)
                local rangeMult = clampDensity(cfg.pedRangeMultiplier, 1.0)
                Citizen.InvokeNative(AMBIENT_ANIMAL_DENSITY, ambDensity)
                Citizen.InvokeNative(SCENARIO_ANIMAL_DENSITY, scenDensity)
                Citizen.InvokeNative(AMBIENT_PED_RANGE, rangeMult)
            end
            Citizen.Wait(0)
        else
            Citizen.Wait(1000)
        end
    end
end)

--------------------------------------------------------------------------------
-- AMBIENT WILDLIFE SPAWNER
--------------------------------------------------------------------------------

local trackedSpawnedAnimals = {}

-- GET_MAP_ZONE_AT_COORDS zone types: 10 = district, 0 = state. The old code
-- asked for type 0 (state) but looked the answer up in a district table, so
-- almost nothing matched and every spot fell through to a coordinate guess
-- that put the Heartlands / Cumberland in 'plains' (a pool with no predators).
-- joaat() is case-insensitive, so spelling variants cost nothing.
local ZONE_BIOMES = {}
local function mapZones(biome, names)
    for _, name in ipairs(names) do ZONE_BIOMES[GetHashKey(name)] = biome end
end
mapZones('swamp', { 'BayouNwa', 'BluewaterMarsh' })
mapZones('lemoyne', { 'ScarlettMeadows', 'Lemoyne' })
mapZones('heartlands', { 'Heartlands', 'NewHanover' })
mapZones('cumberland', { 'Cumberland', 'CumberlandForest' })
mapZones('roanoke', { 'Roanoke', 'RoanokeRidge' })
mapZones('mountains', { 'GrizzliesEast', 'GrizzliesWest', 'Ambarino' })
mapZones('valley', { 'BigValley', 'TallTrees', 'WestElizabeth', 'UpperWestElizabeth' })
mapZones('greatplains', { 'GreatPlains', 'LowerWestElizabeth' })
mapZones('desert', { 'GaptoothRidge', 'ChollaSprings', 'RioBravo', 'HennigansStead', 'NewAustin' })

local function zoneAt(coords, zoneType)
    local ok, hash = pcall(Citizen.InvokeNative, 0x43AD8FC02B429D33, coords.x, coords.y, coords.z, zoneType, Citizen.ResultAsInteger())
    if ok and hash and hash ~= 0 then return ZONE_BIOMES[hash] end
    return nil
end

local function getBiomeCategory(coords)
    local biome = zoneAt(coords, 10) or zoneAt(coords, 0)
    if biome then return biome end

    -- Coordinate fallback laid out on the RDR2 map (x west->east, y south->north).
    local x, y = coords.x, coords.y
    if y < -2000.0 or (x < -2300.0 and y < -1400.0) then
        return 'desert'      -- New Austin
    elseif x >= 1800.0 and y > 500.0 then
        return 'forest'      -- Roanoke Ridge
    elseif y > 1100.0 then
        return 'mountains'   -- Grizzlies / Ambarino
    elseif x > 1800.0 and y < -500.0 then
        return 'swamp'       -- Bayou Nwa
    elseif x < -600.0 then
        return 'valley'      -- West Elizabeth
    elseif y < -700.0 then
        return 'lemoyne'     -- Scarlett Meadows
    end
    return 'heartlands'      -- Heartlands
end

-- Only land wildlife from the spawn pools counts toward the quota. Counting
-- every non-human ped let birds, fish, rats and parked horses fill the
-- "5 nearby" target, so the spawner almost never ran.
local wildlifeModels, predatorModels = nil, nil
local domesticModels = {
    [GetHashKey('a_c_pig_01')] = true,
    [GetHashKey('a_c_cow')] = true,
    [GetHashKey('a_c_bull_01')] = true,
    [GetHashKey('a_c_goat_01')] = true,
    [GetHashKey('a_c_sheep_01')] = true,
    [GetHashKey('a_c_chicken_01')] = true,
    [GetHashKey('a_c_rooster_01')] = true,
}
local function buildModelSets()
    wildlifeModels, predatorModels = {}, {}
    local cfg = Config.Animals or {}
    for _, pool in pairs(cfg.Pools or {}) do
        for _, name in ipairs(pool) do wildlifeModels[GetHashKey(name)] = true end
    end
    for _, pool in pairs(((cfg.Predators or {}).Pools) or {}) do
        for _, name in ipairs(pool) do
            local hash = GetHashKey(name)
            wildlifeModels[hash] = true
            predatorModels[hash] = true
        end
    end
end

local function isWildAnimal(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) or IsPedHuman(ped) then return false end
    if IsEntityDead(ped) then return false end
    if not wildlifeModels then buildModelSets() end
    return wildlifeModels[GetEntityModel(ped)] == true
end

-- Game-population animals can bypass our spawner pools.  Remove farm animals
-- that wander into the wilderness, while leaving jrs_ranch's replicated
-- animals untouched.  This prevents pigs appearing as wild game in Valentine.
local function isProtectedFarmAnimal(ped)
    local ok, state = pcall(function() return Entity(ped).state end)
    return ok and state and state.jrsFarmAnimalId ~= nil
end

local function isModelNativeToBiome(modelHash, biome)
    local cfg = Config.Animals or {}
    for _, pools in ipairs({ cfg.Pools or {}, (cfg.Predators or {}).Pools or {} }) do
        for _, name in ipairs(pools[biome] or {}) do
            if GetHashKey(name) == modelHash then return true end
        end
    end
    return false
end

local function removeOutOfHabitatAnimal(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsPedAPlayer(ped) or IsPedHuman(ped) then return end
    if not wildlifeModels then buildModelSets() end
    local model = GetEntityModel(ped)
    if type(IsThisModelAHorse) == 'function' and IsThisModelAHorse(model) then return end
    if isProtectedFarmAnimal(ped) then return end

    local coords = GetEntityCoords(ped)
    local isDomestic = domesticModels[model] == true
    local isKnownWildlife = wildlifeModels and wildlifeModels[model] == true
    if not isDomestic and (not isKnownWildlife or isModelNativeToBiome(model, getBiomeCategory(coords))) then return end

    SetEntityAsMissionEntity(ped, true, true)
    DeletePed(ped)
    if DoesEntityExist(ped) then DeleteEntity(ped) end
end

-- Returns (land wildlife count, predator count) within radius.
local function countNearbyAnimals(center, radius)
    local ok, pool = pcall(GetGamePool, 'CPed')
    if not ok or type(pool) ~= 'table' then return 0, 0 end

    local count, predators = 0, 0
    for i = 1, #pool do
        local ped = pool[i]
        if isWildAnimal(ped) and #(center - GetEntityCoords(ped)) <= radius then
            count = count + 1
            if predatorModels[GetEntityModel(ped)] then predators = predators + 1 end
        end
    end
    return count, predators
end

local function findGroundCoord(x, y, approxZ)
    pcall(RequestCollisionAtCoord, x, y, approxZ)

    if type(GetGroundZAndNormalFor_3dCoord) == 'function' then
        for _, offset in ipairs({ 15.0, 30.0, 5.0, 0.0, 50.0, -10.0, 80.0 }) do
            local ok, found, gz = pcall(GetGroundZAndNormalFor_3dCoord, x, y, approxZ + offset)
            if ok and found and tonumber(gz) and tonumber(gz) > -100.0 and tonumber(gz) < 2200.0 then
                return vector3(x, y, tonumber(gz)), true
            end
        end
    end

    if type(GetGroundZFor_3dCoord) == 'function' then
        for _, offset in ipairs({ 15.0, 30.0, 5.0, 0.0, 50.0, -10.0, 80.0 }) do
            local ok, found, gz = pcall(GetGroundZFor_3dCoord, x, y, approxZ + offset, false)
            if ok and found and tonumber(gz) and tonumber(gz) > -100.0 and tonumber(gz) < 2200.0 then
                return vector3(x, y, tonumber(gz)), true
            end
        end
    end

    return vector3(x, y, approxZ), false
end

local function isSubmergedInWater(x, y, z)
    local waterNative = type(GetWaterHeightNoWaves) == 'function' and GetWaterHeightNoWaves or GetWaterHeight
    if type(waterNative) == 'function' then
        local ok, wet, waterZ = pcall(waterNative, x, y, z + 2.0)
        if ok and wet and tonumber(waterZ) then
            if tonumber(waterZ) >= (z - 0.25) then
                return true
            end
        end
    end
    return false
end

local function loadModel(modelHash)
    if not IsModelValid(modelHash) then return false end
    RequestModel(modelHash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(modelHash) and GetGameTimer() < deadline do
        Citizen.Wait(50)
        RequestModel(modelHash)
    end
    return HasModelLoaded(modelHash)
end

local function chooseAnimalModel(biome, predator)
    local pools
    if predator then
        pools = ((Config.Animals and Config.Animals.Predators) or {}).Pools or {}
    else
        pools = (Config.Animals and Config.Animals.Pools) or {}
    end
    local pool = pools[biome] or pools.default or { 'a_c_deer_01', 'a_c_coyote_01', 'a_c_rabbit_01' }
    if #pool == 0 then return GetHashKey('a_c_deer_01') end

    local modelName = pool[math.random(1, #pool)]
    return type(modelName) == 'string' and GetHashKey(modelName) or tonumber(modelName) or GetHashKey('a_c_deer_01')
end

-- Script-created animals carry no kill quality, so the game labels them
-- "Ruined" and offers no skinning. _SET_PED_QUALITY gives them a real pelt.
local SET_PED_QUALITY = 0xCE6B874286D640BB
function JRSAnimalsSetCarcassQuality(ped, quality)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    quality = math.max(0, math.min(2, math.floor(tonumber(quality) or 1)))
    pcall(Citizen.InvokeNative, SET_PED_QUALITY, ped, quality)
end

local function spawnSingleAnimal(playerCoords, biome, minDist, maxDist, predator)

    local angle = math.random() * math.pi * 2.0
    local dist = minDist + (math.random() * (maxDist - minDist))
    local testX = playerCoords.x + math.cos(angle) * dist
    local testY = playerCoords.y + math.sin(angle) * dist

    local spawnCoords, foundGround = findGroundCoord(testX, testY, playerCoords.z)
    if not foundGround then return nil end

    -- Habitat is read where the animal appears (spawns are 45-115 m out and
    -- can cross a district border), so a Heartlands spot never gets a boar.
    biome = getBiomeCategory(spawnCoords) or biome
    local modelHash = chooseAnimalModel(biome, predator)
    if not modelHash then return nil end

    -- Safe zone check: do not spawn wild animals or predators inside or near ANY safe zone
    if GetResourceState('jrs_safezone') == 'started' then
        local inZone = false
        pcall(function()
            inZone = exports['jrs_safezone']:IsNearAnySafeZone(spawnCoords, 80.0)
        end)
        if not inZone then
            pcall(function()
                inZone = exports['jrs_safezone']:GetZoneAtCoords(spawnCoords) ~= nil
            end)
        end
        if inZone then return nil end
    end

    -- Water check: allow alligators in water, but keep land animals on dry ground
    local isAlligator = modelHash == GetHashKey('a_c_alligator_01') or modelHash == GetHashKey('a_c_alligator_03')
    if not isAlligator and isSubmergedInWater(spawnCoords.x, spawnCoords.y, spawnCoords.z) then
        return nil
    end

    if not loadModel(modelHash) then
        return nil
    end

    local heading = math.random() * 360.0
    local ped = CreatePed(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z + 0.2, heading, true, true, true, true)
    SetModelAsNoLongerNeeded(modelHash)

    if ped and ped ~= 0 and DoesEntityExist(ped) then
        pcall(Citizen.InvokeNative, 0x283978A15512B2FE, ped, true) -- SetRandomOutfitVariation (prevents invisible mesh)
        pcall(Citizen.InvokeNative, 0xCC8CA3E88256E58F, ped, false, true, true, true, false) -- UpdatePedVariation
        pcall(PlaceEntityOnGroundProperly, ped, true)
        pcall(SetEntityVisible, ped, true)
        pcall(SetEntityAlpha, ped, 255, false)

        JRSAnimalsSetCarcassQuality(ped, (Config.Animals or {}).carcassQuality)
        SetEntityAsMissionEntity(ped, false, false)
        SetPedAsNoLongerNeeded(ped)
        SetBlockingOfNonTemporaryEvents(ped, false)
        TaskWanderStandard(ped, 10.0, 10)

        trackedSpawnedAnimals[#trackedSpawnedAnimals + 1] = {
            entity = ped,
            spawnTime = GetGameTimer(),
        }
        return ped
    end

    return nil
end

--------------------------------------------------------------------------------
-- AMBIENT ANIMAL VISIBILITY & METAPED FIXER (Game Wildlife & OneSync Population Guard)
--------------------------------------------------------------------------------
Citizen.CreateThread(function()
    local checkedPeds = {}
    local lastCleanup = GetGameTimer()

    while true do
        Citizen.Wait(1200)

        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and DoesEntityExist(playerPed) then
            local pCoords = GetEntityCoords(playerPed)
            local ok, pool = pcall(GetGamePool, 'CPed')

            if ok and type(pool) == 'table' then
                for i = 1, #pool do
                    local ped = pool[i]
                    if ped and ped ~= 0 and DoesEntityExist(ped) then
                        -- Check if ped is an animal (not human, not player)
                        if not IsPedHuman(ped) and not IsPedAPlayer(ped) then
                            local pedCoords = GetEntityCoords(ped)
                            -- Only process animals within reasonable render/interaction distance
                            if #(pCoords - pedCoords) <= 150.0 then
                                -- Enforce biome pools for both our spawns and the game's
                                -- ambient population (which otherwise can place livestock
                                -- and predators in the wrong part of the map).
                                removeOutOfHabitatAnimal(ped)
                                if not DoesEntityExist(ped) then goto continue end
                                local pedInSafe = false
                                if GetResourceState('jrs_safezone') == 'started' then
                                    pcall(function()
                                        pedInSafe = exports['jrs_safezone']:IsNearAnySafeZone(pedCoords, 10.0)
                                    end)
                                    if not pedInSafe then
                                        pcall(function()
                                            pedInSafe = exports['jrs_safezone']:GetZoneAtCoords(pedCoords) ~= nil
                                        end)
                                    end
                                end

                                if pedInSafe then
                                    local model = GetEntityModel(ped)
                                    local isHorse = type(IsThisModelAHorse) == 'function' and IsThisModelAHorse(model)
                                    local inGroup = type(IsPedInGroup) == 'function' and IsPedInGroup(ped)
                                    if not isHorse and not inGroup then
                                        ClearPedTasksImmediately(ped)
                                        SetEntityVisible(ped, false)
                                        SetEntityAlpha(ped, 0, false)
                                        SetEntityCollision(ped, false, false)
                                        pcall(SetEntityCoordsNoOffset, ped, 0.0, 0.0, -500.0, false, false, false)
                                        SetEntityAsMissionEntity(ped, true, true)
                                        DeletePed(ped)
                                        if DoesEntityExist(ped) then DeleteEntity(ped) end
                                    end
                                else
                                    local isVisible = IsEntityVisible(ped)
                                    local alpha = GetEntityAlpha(ped)

                                    if not checkedPeds[ped] or not isVisible or alpha < 255 then
                                        checkedPeds[ped] = true

                                        -- Apply random outfit variation so animal metaped/skin renders properly
                                        pcall(Citizen.InvokeNative, 0x283978A15512B2FE, ped, true) -- _SET_RANDOM_OUTFIT_VARIATION
                                        pcall(Citizen.InvokeNative, 0xCC8CA3E88256E58F, ped, false, true, true, true, false) -- _UPDATE_PED_VARIATION

                                        -- Force visibility and restore alpha
                                        if not isVisible then
                                            pcall(SetEntityVisible, ped, true)
                                        end
                                        if alpha < 255 then
                                            pcall(ResetEntityAlpha, ped)
                                            pcall(SetEntityAlpha, ped, 255, false)
                                        end

                                        -- Set LOD and targeting capability
                                        pcall(Citizen.InvokeNative, 0xAAB0CD2C67A5C1E8, ped, 1.0) -- _SET_PED_LOD_MULTIPLIER
                                        pcall(SetPedCanBeTargetted, ped, true)
                                    end
                                end
                            end
                        end
                        ::continue::
                    end
                end
            end

            -- Periodically clean dead or removed peds from cache every 30 seconds
            local now = GetGameTimer()
            if now - lastCleanup > 30000 then
                lastCleanup = now
                for pedHandle, _ in pairs(checkedPeds) do
                    if not DoesEntityExist(pedHandle) then
                        checkedPeds[pedHandle] = nil
                    end
                end
            end
        end
    end
end)

local function cleanupDistantAnimals(playerCoords, maxDistance)
    local aliveTracked = {}
    for i = 1, #trackedSpawnedAnimals do
        local entry = trackedSpawnedAnimals[i]
        local entity = entry.entity
        if entity and DoesEntityExist(entity) then
            if IsEntityDead(entity) then
                -- Dead animals are handled by player skinning / jrs_hunting
            else
                local entityCoords = GetEntityCoords(entity)
                if #(playerCoords - entityCoords) > maxDistance then
                    -- Far away: delete cleanly to preserve entity budget
                    SetEntityAsMissionEntity(entity, true, true)
                    DeleteEntity(entity)
                else
                    aliveTracked[#aliveTracked + 1] = entry
                end
            end
        end
    end
    trackedSpawnedAnimals = aliveTracked
end

-- Wildlife Spawner Thread
Citizen.CreateThread(function()
    Citizen.Wait(5000) -- Initial warmup after connection

    while true do
        local cfg = Config.Animals
        local spawnerCfg = cfg and cfg.Spawner

        if cfg and cfg.enabled == true and spawnerCfg and spawnerCfg.enabled == true then
            local waitTime = tonumber(spawnerCfg.checkIntervalMs) or 10000
            local playerPed = PlayerPedId()

            if playerPed and playerPed ~= 0 and DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
                local pCoords = GetEntityCoords(playerPed)

                -- Always clean up distant animals to maintain budget
                cleanupDistantAnimals(pCoords, tonumber(spawnerCfg.despawnDistance) or 140.0)

                local interior = GetInteriorFromEntity(playerPed)
                local inInterior = interior and interior ~= 0

                local safeActive = inCityZone or inAnySafeZone
                if not safeActive and GetResourceState('jrs_safezone') == 'started' then
                    local ok, near = pcall(function() return exports['jrs_safezone']:IsNearAnySafeZone(pCoords, 100.0) end)
                    if ok and near then safeActive = true end
                end

                if not safeActive and not inInterior and not IsPedSwimming(playerPed) then
                    -- Count current living animals within detection radius
                    local detectRadius = tonumber(spawnerCfg.detectionRadius) or 90.0
                    local targetCount = tonumber(spawnerCfg.targetNearbyAnimals) or 5
                    local maxCount = tonumber(spawnerCfg.maxNearbyAnimals) or 8
                    local currentCount = countNearbyAnimals(pCoords, detectRadius)

                    -- Predator quota: RedM's own population almost never puts
                    -- wolves/bears/cougars near players, so keep a few around
                    -- on their own budget (spawned farther out, they come to you).
                    local pcfg = cfg.Predators
                    if pcfg and pcfg.enabled == true and not safeActive then
                        local pRadius = tonumber(pcfg.detectionRadius) or 160.0
                        local _, predatorCount = countNearbyAnimals(pCoords, pRadius)
                        local hour = GetClockHours()
                        local night = hour >= 20 or hour < 5
                        local target = tonumber(night and pcfg.targetNearbyNight or pcfg.targetNearby) or 1
                        local chance = tonumber(night and pcfg.spawnChanceNight or pcfg.spawnChance) or 0.5
                        if predatorCount < target and math.random() < chance then
                            local biome = getBiomeCategory(pCoords)
                            spawnSingleAnimal(pCoords, biome,
                                tonumber(pcfg.spawnMinDistance) or 70.0,
                                tonumber(pcfg.spawnMaxDistance) or 110.0, true)
                            Citizen.Wait(400)
                        end
                    end

                    if currentCount < targetCount then
                        local needed = math.min(targetCount - currentCount, 3)
                        local biome = getBiomeCategory(pCoords)
                        local minDist = tonumber(spawnerCfg.spawnMinDistance) or 35.0
                        local maxDist = tonumber(spawnerCfg.spawnMaxDistance) or 80.0

                        for _ = 1, needed do
                            spawnSingleAnimal(pCoords, biome, minDist, maxDist)
                            Citizen.Wait(250)
                        end

                        -- Chance to spawn a partner animal (pair/herd)
                        local groupChance = tonumber(spawnerCfg.groupSpawnChance) or 0.55
                        if math.random() < groupChance and (currentCount + needed) < maxCount then
                            spawnSingleAnimal(pCoords, biome, minDist, maxDist)
                        end
                    end
                end
            end

            Citizen.Wait(waitTime)
        else
            Citizen.Wait(2000)
        end
    end
end)

--------------------------------------------------------------------------------
-- DEBUG & COMMANDS
--------------------------------------------------------------------------------

-- Habitat API for other resources (hunting bait etc.).
exports('GetAnimalBiome', function(coords)
    coords = coords or GetEntityCoords(PlayerPedId())
    return getBiomeCategory(coords)
end)

-- true when the model is native to the habitat at coords (prey or predator pool).
exports('IsAnimalNativeAt', function(model, coords)
    local hash = type(model) == 'string' and GetHashKey(model) or tonumber(model)
    if not hash then return false end
    local biome = getBiomeCategory(coords or GetEntityCoords(PlayerPedId()))
    local cfg = Config.Animals or {}
    for _, pools in ipairs({ cfg.Pools or {}, (cfg.Predators or {}).Pools or {} }) do
        for _, name in ipairs(pools[biome] or pools.default or {}) do
            if GetHashKey(name) == hash then return true end
        end
    end
    return false
end)

RegisterNetEvent('jrs_core:animals:debug', function()
    local playerPed = PlayerPedId()
    if not playerPed or playerPed == 0 then return end

    local coords = GetEntityCoords(playerPed)
    local biome = getBiomeCategory(coords)
    local count = countNearbyAnimals(coords, 90.0)
    local _, predators = countNearbyAnimals(coords, 160.0)

    local msg = ('[WildLife Debug] Biome: %s | InCity: %s | Nearby Animals (90m): %d | Predators (160m): %d | Tracked: %d')
        :format(biome, tostring(inCityZone), count, predators, #trackedSpawnedAnimals)
    print(msg)
    TriggerEvent('jrsCore:notify', 'WILDLIFE', msg, 'placeholder', 5000)
end)

RegisterCommand('jrswildlife', function()
    TriggerEvent('jrs_core:animals:debug')
end, false)
