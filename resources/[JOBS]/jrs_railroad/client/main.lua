local StationPromptGroup = GetRandomIntInRange(0, 0xffffff)
local StationPrompt = nil
local stationBlips = {}
local currentStation = nil

---------------------------------------------------------------
-- INIT: Disable random trains, create prompts, create blips
---------------------------------------------------------------
CreateThread(function()
    SetRandomTrains(false)
    CreateStationPrompt()
    CreateStationBlips()
    CreateFacilityBlips()
    SpawnAmbientTram()
    -- Spawn ambient route trains (server ensures only one client does it)
    local shouldSpawn = JRS.Await('jrs_railroad:shouldSpawnAmbient')
    if shouldSpawn then
        local ambientActive = JRS.Await('jrs_railroad:getAmbientState')
        if ambientActive then
            SpawnAmbientRouteTrains()
        end
    end
end)

---------------------------------------------------------------
-- AMBIENT TRAM (NPC-driven, no player interaction)
-- Spawns once on script start, runs around Saint Denis
---------------------------------------------------------------
local ambientTram = nil
local ambientTramConductor = nil
local ambientTramBlip = nil

function SpawnAmbientTram()
    if not Config.AmbientTram or not Config.AmbientTram.enabled then return end

    local cfg = Config.AmbientTram
    local coords = cfg.spawnCoords
    local trainHash = joaat(cfg.model)

    -- Load wagon models
    local wagons = N_0x635423d55ca84fc8(trainHash)
    for i = 0, wagons - 1 do
        local wagonModel = N_0x8df5f6a19f99f0d5(trainHash, i)
        RequestModel(wagonModel)
        while not HasModelLoaded(wagonModel) do Wait(0) end
    end

    -- Spawn tram with NPC conductor + passengers
    ambientTram = Citizen.InvokeNative(0xC239DBD9A57D2A71, trainHash, coords.x, coords.y, coords.z, cfg.direction, cfg.passengers, true, true)
    SetTrainSpeed(ambientTram, cfg.speed)
    SetTrainCruiseSpeed(ambientTram, cfg.speed)

    -- Wait for conductor to appear, then protect them
    local conductor = GetPedInVehicleSeat(ambientTram, -1)
    local attempts = 0
    while not DoesEntityExist(conductor) and attempts < 100 do
        conductor = GetPedInVehicleSeat(ambientTram, -1)
        attempts = attempts + 1
        Wait(10)
    end
    if DoesEntityExist(conductor) then
        SetEntityAsMissionEntity(conductor, true, true)
        SetPedCanBeKnockedOffVehicle(conductor, 1)
        SetEntityInvincible(conductor, true)
        SetBlockingOfNonTemporaryEvents(conductor, true)
        SetEntityCanBeDamaged(conductor, false)
        ambientTramConductor = conductor
    end

    -- Create blip for the tram
    ambientTramBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, Config.Blips.train.hash, ambientTram)
    SetBlipScale(ambientTramBlip, Config.Blips.train.scale)
    Citizen.InvokeNative(0x9CB1A1623062F402, ambientTramBlip, cfg.label or 'Saint Denis Trolley')

    DebugPrint('Ambient tram spawned in Saint Denis')
end

---------------------------------------------------------------
-- STATION PROMPT
---------------------------------------------------------------
function CreateStationPrompt()
    StationPrompt = PromptRegisterBegin()
    PromptSetControlAction(StationPrompt, 0x760A9C6F) -- G key
    local str = CreateVarString(10, 'LITERAL_STRING', L('station_prompt'))
    PromptSetText(StationPrompt, str)
    PromptSetEnabled(StationPrompt, true)
    PromptSetVisible(StationPrompt, true)
    PromptSetHoldMode(StationPrompt, true)
    PromptSetGroup(StationPrompt, StationPromptGroup)
    PromptRegisterEnd(StationPrompt)
end

---------------------------------------------------------------
-- STATION BLIPS
---------------------------------------------------------------
function CreateStationBlips()
    for _, station in ipairs(Config.Stations) do
        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, station.coords.x, station.coords.y, station.coords.z)
        SetBlipSprite(blip, Config.Blips.station.hash, true)
        SetBlipScale(blip, Config.Blips.station.scale)
        local company = Config.Companies[station.company]
        if company then
            Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(company.blipColor))
        end
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, station.label)
        table.insert(stationBlips, blip)
    end
end

---------------------------------------------------------------
-- WATER TOWER + MAINTENANCE DEPOT BLIPS
---------------------------------------------------------------
local facilityBlips = {}

function CreateFacilityBlips()
    for _, station in ipairs(Config.Stations) do
        if station.hasWaterTower and station.waterTowerCoords then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, station.waterTowerCoords.x, station.waterTowerCoords.y, station.waterTowerCoords.z)
            SetBlipSprite(blip, joaat("blip_donate_food"), true)
            SetBlipScale(blip, Config.Blips.water.scale)
            Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat('BLIP_MODIFIER_MP_COLOR_13'))
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, station.label .. ' - Water Tower')
            table.insert(facilityBlips, blip)
        end

        if station.hasMaintenanceDepot and station.depotCoords then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, station.depotCoords.x, station.depotCoords.y, station.depotCoords.z)
            SetBlipSprite(blip, joaat("blip_event_railroad_camp"), true)
            SetBlipScale(blip, Config.Blips.depot.scale)
            Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat('BLIP_MODIFIER_MP_COLOR_11'))
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, station.label .. ' - Maintenance Depot')
            table.insert(facilityBlips, blip)
        end
    end
end

-- Helper: check if player is near a water tower
function IsNearWaterTower()
    local pcoords = GetEntityCoords(PlayerPedId())
    for _, station in ipairs(Config.Stations) do
        if station.hasWaterTower and station.waterTowerCoords then
            if GetDistanceBetween(pcoords, station.waterTowerCoords) < 20 then
                return true
            end
        end
    end
    return false
end

-- Helper: check if player is near a maintenance depot
function IsNearMaintenanceDepot()
    local pcoords = GetEntityCoords(PlayerPedId())
    for _, station in ipairs(Config.Stations) do
        if station.hasMaintenanceDepot and station.depotCoords then
            if GetDistanceBetween(pcoords, station.depotCoords) < 20 then
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------------
-- MAIN LOOP: Station proximity detection
---------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5)
        local sleep = true
        local pcoords = GetEntityCoords(PlayerPedId())

        for _, station in ipairs(Config.Stations) do
            local dist = GetDistanceBetween(pcoords, station.coords)
            if dist < Config.StationInteractRadius then
                sleep = false
                local groupLabel = CreateVarString(10, 'LITERAL_STRING', station.label)
                PromptSetActiveGroupThisFrame(StationPromptGroup, groupLabel)
                if PromptHasHoldModeCompleted(StationPrompt) then
                    currentStation = station
                    OpenStationHUD(station)
                end
            end
        end

        if sleep then
            Wait(1500)
        end
    end
end)

---------------------------------------------------------------
-- OPEN STATION HUD (V2: role-based)
---------------------------------------------------------------
function OpenStationHUD(station)
    DebugPrint('Opening station HUD: ' .. station.label)

    local companyId = station.company

    -- V2: Determine player's role at this station
    local playerRole = JRS.Await('jrs_railroad:getPlayerRole', companyId)
    local ownership = JRS.Await('jrs_railroad:getCompanyOwnership', companyId)
    local canSpawn = JRS.Await('jrs_railroad:canSpawnTrain')

    -- Build trains list for this company
    local companyTrainConfigs = {}
    for i, train in ipairs(Config.Trains) do
        if train.company == companyId then
            table.insert(companyTrainConfigs, {
                index = i,
                model = train.model,
                label = train.label,
                cost = train.cost,
                sellPrice = train.sellPrice,
                maxSpeed = train.maxSpeed,
                maxFuel = train.maxFuel,
                maxWater = train.maxWater,
                maxCondition = train.maxCondition,
                requiredRank = train.requiredRank,
                upgradeable = train.upgradeable,
                hasPassengerCars = train.hasPassengerCars or false,
                company = train.company,
            })
        end
    end

    -- Get company trains from DB
    local companyTrains = JRS.Await('jrs_railroad:getCompanyTrains', companyId) or {}

    -- Get role-specific data
    local employees = nil
    local pendingApps = nil
    local supplies = nil
    local myEmployeeData = nil
    local myMembership = nil
    local cashRegister = 0

    myMembership = JRS.Await('jrs_railroad:getMyCompanyMembership', companyId)
    local companyUpgrades = JRS.Await('jrs_railroad:getCompanyUpgrades', companyId) or {}

    if playerRole == 'owner' then
        employees = JRS.Await('jrs_railroad:getEmployees', companyId)
        pendingApps = JRS.Await('jrs_railroad:getPendingApplications', companyId)
        supplies = JRS.Await('jrs_railroad:getCompanySupplies', companyId)
        cashRegister = ownership and ownership.cash_register or 0
    elseif playerRole == 'driver' then
        myEmployeeData = JRS.Await('jrs_railroad:getMyEmployeeData', companyId)
        supplies = JRS.Await('jrs_railroad:getCompanySupplies', companyId)
    end

    local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
    if ownership and ownership.company_name then
        companyLabel = ownership.company_name
    end

    SendNUIMessage({
        action = 'openStation',
        station = {
            id = station.id,
            label = station.label,
            company = companyId,
            companyLabel = companyLabel,
        },
        playerRole = playerRole,
        ownership = ownership,
        companyTrains = companyTrains,
        companyTrainConfigs = companyTrainConfigs,
        companyUpgrades = companyUpgrades,
        canSpawn = canSpawn,
        employees = employees or {},
        pendingApps = pendingApps or {},
        supplies = supplies or {},
        myEmployeeData = myEmployeeData,
        myMembership = myMembership,
        cashRegister = cashRegister,
        ranks = Config.Ranks,
        companies = Config.Companies,
        upgrades = Config.Upgrades,
        supplyItems = Config.SupplyItems,
        companyPurchasePrice = Config.CompanyPurchasePrice,
        deliveryDestinations = Config.DeliveryDestinations,
        maintenanceLocations = Config.Missions.maintenance.locations,
        missions = Config.Missions,
        hasPassengerCars = ActiveTrainConfig and ActiveTrainConfig.hasPassengerCars or false,
        companyStats = JRS.Await('jrs_railroad:getCompanyStats', companyId) or {},
        allCompanyStats = JRS.Await('jrs_railroad:getAllCompanyStats') or {},
        lang = GetLocaleTable(),
    })

    SetNuiFocus(true, true)
end

---------------------------------------------------------------
-- GET CURRENT STATION
---------------------------------------------------------------
function GetCurrentStation()
    return currentStation
end

---------------------------------------------------------------
-- NUI CALLBACKS
---------------------------------------------------------------
RegisterNUICallback('closeStation', function(data, cb)
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('buyTrain', function(data, cb)
    TriggerServerEvent('jrs_railroad:buyTrain', data.trainIndex, currentStation.id)
    Wait(500)
    -- Refresh data
    local ownedTrains = JRS.Await('jrs_railroad:getOwnedTrains')
    cb({ success = true, ownedTrains = ownedTrains or {} })
end)

RegisterNUICallback('sellTrain', function(data, cb)
    -- If the train being sold is currently spawned, despawn it first
    if ActiveTrain and DoesEntityExist(ActiveTrain) and ActiveTrainData and ActiveTrainData.id == data.trainId then
        CleanupActiveTrain()
        TriggerServerEvent('jrs_railroad:setTrainSpawned', false, data.trainId)
    end
    TriggerServerEvent('jrs_railroad:sellTrain', data.trainId)
    Wait(500)
    local ownedTrains = JRS.Await('jrs_railroad:getOwnedTrains')
    cb({ success = true, ownedTrains = ownedTrains or {} })
end)

RegisterNUICallback('spawnTrain', function(data, cb)
    SendNUIMessage({ action = 'closeStation' })
    SetNuiFocus(false, false)
    cb({ success = true })

    local canSpawn = JRS.Await('jrs_railroad:canSpawnTrain')
    if not canSpawn then
        Notify(L('train_already_spawned'), 'error')
        return
    end

    -- V2: Spawn from Config index (no DB train record needed)
    if data.trainIndex then
        local trainConfig = Config.Trains[data.trainIndex]
        if not trainConfig then
            Notify(L('train_config_not_found'), 'error')
            return
        end
        SpawnConfigTrain(trainConfig, data.direction or false, currentStation)
    elseif data.trainId then
        -- Legacy: spawn from DB id
        SpawnPlayerTrain(data.trainId, data.direction or false, currentStation)
    end
end)

RegisterNUICallback('parkTrain', function(data, cb)
    SendNUIMessage({ action = 'closeStation' })
    SetNuiFocus(false, false)
    cb({ success = true })
    ParkPlayerTrain()
end)

RegisterNUICallback('despawnTrain', function(data, cb)
    SendNUIMessage({ action = 'closeStation' })
    SetNuiFocus(false, false)
    cb({ success = true })
    DespawnPlayerTrain()
end)

RegisterNUICallback('purchaseUpgrade', function(data, cb)
    TriggerServerEvent('jrs_railroad:purchaseUpgrade', data.companyId, data.trainModel, data.upgradeType)
    Wait(500)
    local upgrades = JRS.Await('jrs_railroad:getCompanyUpgrades', data.companyId)
    cb({ success = true, companyUpgrades = upgrades or {} })
end)

RegisterNUICallback('startMission', function(data, cb)
    SendNUIMessage({ action = 'closeStation' })
    SetNuiFocus(false, false)
    cb({ success = true })
    StartMission(data.missionType, currentStation, data.destIndex)
end)

---------------------------------------------------------------
-- V2: COMPANY MANAGEMENT NUI CALLBACKS
---------------------------------------------------------------
RegisterNUICallback('buyCompany', function(data, cb)
    TriggerServerEvent('jrs_railroad:buyCompany', data.companyId)
    Wait(500)
    cb({ success = true })
end)

RegisterNUICallback('sellCompany', function(data, cb)
    TriggerServerEvent('jrs_railroad:sellCompany', data.companyId)
    Wait(500)
    cb({ success = true })
end)

RegisterNUICallback('renameCompany', function(data, cb)
    TriggerServerEvent('jrs_railroad:renameCompany', data.companyId, data.newName)
    Wait(300)
    cb({ success = true })
end)

RegisterNUICallback('withdrawFunds', function(data, cb)
    TriggerServerEvent('jrs_railroad:withdrawFunds', data.companyId, data.amount)
    Wait(500)
    local ownership = JRS.Await('jrs_railroad:getCompanyOwnership', data.companyId)
    cb({ success = true, cashRegister = ownership and ownership.cash_register or 0 })
end)

RegisterNUICallback('applyAsDriver', function(data, cb)
    TriggerServerEvent('jrs_railroad:applyAsDriver', data.companyId)
    Wait(500)
    cb({ success = true })
end)

RegisterNUICallback('approveDriver', function(data, cb)
    TriggerServerEvent('jrs_railroad:approveDriver', data.companyId, data.employeeId)
    Wait(500)
    local employees = JRS.Await('jrs_railroad:getEmployees', data.companyId)
    local pending = JRS.Await('jrs_railroad:getPendingApplications', data.companyId)
    cb({ success = true, employees = employees or {}, pendingApps = pending or {} })
end)

RegisterNUICallback('rejectDriver', function(data, cb)
    TriggerServerEvent('jrs_railroad:rejectDriver', data.companyId, data.employeeId)
    Wait(500)
    local pending = JRS.Await('jrs_railroad:getPendingApplications', data.companyId)
    cb({ success = true, pendingApps = pending or {} })
end)

RegisterNUICallback('fireDriver', function(data, cb)
    TriggerServerEvent('jrs_railroad:fireDriver', data.companyId, data.employeeId)
    Wait(500)
    local employees = JRS.Await('jrs_railroad:getEmployees', data.companyId)
    cb({ success = true, employees = employees or {} })
end)

RegisterNUICallback('addSupply', function(data, cb)
    TriggerServerEvent('jrs_railroad:addSupply', data.companyId, data.itemName, data.quantity)
    Wait(500)
    local supplies = JRS.Await('jrs_railroad:getCompanySupplies', data.companyId)
    cb({ success = true, supplies = supplies or {} })
end)

RegisterNUICallback('takeSupply', function(data, cb)
    TriggerServerEvent('jrs_railroad:takeSupply', data.companyId, data.itemName, data.quantity)
    Wait(500)
    local supplies = JRS.Await('jrs_railroad:getCompanySupplies', data.companyId)
    cb({ success = true, supplies = supplies or {} })
end)

RegisterNUICallback('buyCompanyTrain', function(data, cb)
    TriggerServerEvent('jrs_railroad:buyTrain', data.trainIndex, currentStation.id)
    Wait(500)
    local trains = JRS.Await('jrs_railroad:getCompanyTrains', currentStation.company)
    cb({ success = true, companyTrains = trains or {} })
end)

---------------------------------------------------------------
-- REFRESH STATION DATA (after mission complete)
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:refreshStationData', function(companyId)
    -- Data was updated server-side. Player sees notification with XP/pay info.
    -- Next time they open a station HUD, fresh data will be fetched.
end)

----------------------------------------------------------------
-- CLEANUP
---------------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        DespawnPlayerTrain()
        DespawnAmbientRouteTrains()
        if ambientTramBlip then
            RemoveBlip(ambientTramBlip)
            ambientTramBlip = nil
        end
        for _, blip in ipairs(stationBlips) do
            RemoveBlip(blip)
        end
        for _, blip in ipairs(facilityBlips) do
            RemoveBlip(blip)
        end
    end
end)

AddEventHandler('playerDropped', function()
    DespawnPlayerTrain()
end)
