-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: stations
-- Stations have a blip and a hold prompt that opens the station window (NUI). What the window shows depends on
-- the player's role at the company of that station (owner, driver, or nobody). The window talks back through
-- the NUI callbacks at the end of this file; each one asks the server and then returns fresh data.

local stationGroup = GetRandomIntInRange(0, 0xffffff)
local stationPrompt
local stationBlips, facilityBlips = {}, {}
local current                               -- the station whose window is open

local ambientConductor, ambientBlip        -- (ambientTram is global: /trainpos lists it)

-- ------------------------------------------------------------------ start up

CreateThread(function()
    SetRandomTrains(false)
    CreateStationPrompt()
    CreateStationBlips()
    CreateFacilityBlips()
    SpawnAmbientTram()

    -- ambient route trains: the server lets only one client spawn them
    if JRS.Await('jrs_railroad:shouldSpawnAmbient') and JRS.Await('jrs_railroad:getAmbientState') then
        SpawnAmbientRouteTrains()
    end
end)

-- ------------------------------------------------------------------ the tram that always runs in Saint Denis

local function loadWagons(model)
    for i = 0, N_0x635423d55ca84fc8(model) - 1 do
        local wagon = N_0x8df5f6a19f99f0d5(model, i)
        RequestModel(wagon)
        while not HasModelLoaded(wagon) do Wait(0) end
    end
end

function SpawnAmbientTram()
    local cfg = Config.AmbientTram
    if not cfg or not cfg.enabled then return end

    local model = joaat(cfg.model)
    loadWagons(model)

    local at = cfg.spawnCoords
    ambientTram = Citizen.InvokeNative(0xC239DBD9A57D2A71, model, at.x, at.y, at.z, cfg.direction, cfg.passengers, true, true)
    SetTrainSpeed(ambientTram, cfg.speed)
    SetTrainCruiseSpeed(ambientTram, cfg.speed)

    -- the conductor appears a moment later; make him untouchable
    local conductor, tries = GetPedInVehicleSeat(ambientTram, -1), 0
    while not DoesEntityExist(conductor) and tries < 100 do
        conductor = GetPedInVehicleSeat(ambientTram, -1)
        tries = tries + 1
        Wait(10)
    end
    if DoesEntityExist(conductor) then
        SetEntityAsMissionEntity(conductor, true, true)
        SetPedCanBeKnockedOffVehicle(conductor, 1)
        SetEntityInvincible(conductor, true)
        SetBlockingOfNonTemporaryEvents(conductor, true)
        SetEntityCanBeDamaged(conductor, false)
        ambientConductor = conductor
    end

    ambientBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, Config.Blips.train.hash, ambientTram)
    SetBlipScale(ambientBlip, Config.Blips.train.scale)
    Citizen.InvokeNative(0x9CB1A1623062F402, ambientBlip, cfg.label or 'Saint Denis Trolley')
    DebugPrint('Ambient tram spawned in Saint Denis')
end

-- ------------------------------------------------------------------ prompt and blips

function CreateStationPrompt()
    stationPrompt = PromptRegisterBegin()
    PromptSetControlAction(stationPrompt, 0x760A9C6F)                  -- G
    PromptSetText(stationPrompt, CreateVarString(10, 'LITERAL_STRING', L('station_prompt')))
    PromptSetEnabled(stationPrompt, true)
    PromptSetVisible(stationPrompt, true)
    PromptSetHoldMode(stationPrompt, true)
    PromptSetGroup(stationPrompt, stationGroup)
    PromptRegisterEnd(stationPrompt)
end

local function blipAt(at, sprite, scale, colour, name)
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, at.x, at.y, at.z)
    SetBlipSprite(blip, sprite, true)
    SetBlipScale(blip, scale)
    if colour then Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(colour)) end
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name)
    return blip
end

function CreateStationBlips()
    for _, station in ipairs(Config.Stations) do
        local company = Config.Companies[station.company]
        stationBlips[#stationBlips + 1] = blipAt(station.coords, Config.Blips.station.hash, Config.Blips.station.scale, company and company.blipColor, station.label)
    end
end

-- water towers and maintenance depots of the stations that have them
function CreateFacilityBlips()
    for _, s in ipairs(Config.Stations) do
        if s.hasWaterTower and s.waterTowerCoords then
            facilityBlips[#facilityBlips + 1] = blipAt(s.waterTowerCoords, joaat('blip_donate_food'), Config.Blips.water.scale, 'BLIP_MODIFIER_MP_COLOR_13', s.label .. ' - Water Tower')
        end
        if s.hasMaintenanceDepot and s.depotCoords then
            facilityBlips[#facilityBlips + 1] = blipAt(s.depotCoords, joaat('blip_event_railroad_camp'), Config.Blips.depot.scale, 'BLIP_MODIFIER_MP_COLOR_11', s.label .. ' - Maintenance Depot')
        end
    end
end

local function nearFacility(flag, key)
    local here = GetEntityCoords(PlayerPedId())
    for _, s in ipairs(Config.Stations) do
        if s[flag] and s[key] and GetDistanceBetween(here, s[key]) < 20 then return true end
    end
    return false
end

function IsNearWaterTower() return nearFacility('hasWaterTower', 'waterTowerCoords') end
function IsNearMaintenanceDepot() return nearFacility('hasMaintenanceDepot', 'depotCoords') end

CreateThread(function()
    while true do
        Wait(5)
        local near = false
        local here = GetEntityCoords(PlayerPedId())
        for _, station in ipairs(Config.Stations) do
            if GetDistanceBetween(here, station.coords) < Config.StationInteractRadius then
                near = true
                PromptSetActiveGroupThisFrame(stationGroup, CreateVarString(10, 'LITERAL_STRING', station.label))
                if PromptHasHoldModeCompleted(stationPrompt) then
                    current = station
                    OpenStationHUD(station)
                end
            end
        end
        if not near then Wait(1500) end
    end
end)

-- ------------------------------------------------------------------ the station window

-- the trains of the config that belong to a company, with the fields the window needs
local function trainsOf(companyId)
    local list = {}
    for i, t in ipairs(Config.Trains) do
        if t.company == companyId then
            list[#list + 1] = {
                index = i, model = t.model, label = t.label, cost = t.cost, sellPrice = t.sellPrice, maxSpeed = t.maxSpeed,
                maxFuel = t.maxFuel, maxWater = t.maxWater, maxCondition = t.maxCondition, requiredRank = t.requiredRank,
                upgradeable = t.upgradeable, hasPassengerCars = t.hasPassengerCars or false, company = t.company,
            }
        end
    end
    return list
end

function OpenStationHUD(station)
    DebugPrint('Opening station HUD: ' .. station.label)
    local id = station.company

    local role = JRS.Await('jrs_railroad:getPlayerRole', id)
    local ownership = JRS.Await('jrs_railroad:getCompanyOwnership', id)

    -- owners see everything, drivers see their own record and the supplies, others see neither
    local employees, applications, supplies, mine, cash
    if role == 'owner' then
        employees = JRS.Await('jrs_railroad:getEmployees', id)
        applications = JRS.Await('jrs_railroad:getPendingApplications', id)
        supplies = JRS.Await('jrs_railroad:getCompanySupplies', id)
        cash = ownership and ownership.cash_register or 0
    elseif role == 'driver' then
        mine = JRS.Await('jrs_railroad:getMyEmployeeData', id)
        supplies = JRS.Await('jrs_railroad:getCompanySupplies', id)
    end

    local label = ownership and ownership.company_name or (Config.Companies[id] and Config.Companies[id].label) or id

    SendNUIMessage({
        action = 'openStation',
        station = { id = station.id, label = station.label, company = id, companyLabel = label },
        playerRole = role,
        ownership = ownership,
        companyTrains = JRS.Await('jrs_railroad:getCompanyTrains', id) or {},
        companyTrainConfigs = trainsOf(id),
        companyUpgrades = JRS.Await('jrs_railroad:getCompanyUpgrades', id) or {},
        canSpawn = JRS.Await('jrs_railroad:canSpawnTrain'),
        employees = employees or {}, pendingApps = applications or {}, supplies = supplies or {},
        myEmployeeData = mine,
        myMembership = JRS.Await('jrs_railroad:getMyCompanyMembership', id),
        cashRegister = cash or 0,
        ranks = Config.Ranks, companies = Config.Companies, upgrades = Config.Upgrades, supplyItems = Config.SupplyItems,
        companyPurchasePrice = Config.CompanyPurchasePrice, deliveryDestinations = Config.DeliveryDestinations,
        maintenanceLocations = Config.Missions.maintenance.locations, missions = Config.Missions,
        hasPassengerCars = ActiveTrainConfig and ActiveTrainConfig.hasPassengerCars or false,
        companyStats = JRS.Await('jrs_railroad:getCompanyStats', id) or {},
        allCompanyStats = JRS.Await('jrs_railroad:getAllCompanyStats') or {},
        lang = GetLocaleTable(),
    })
    SetNuiFocus(true, true)
end

function GetCurrentStation() return current end

-- ------------------------------------------------------------------ callbacks from the window

local function closeWindow()
    SendNUIMessage({ action = 'closeStation' })
    SetNuiFocus(false, false)
end

RegisterNUICallback('closeStation', function(_, done)
    SetNuiFocus(false, false)
    done({})
end)

-- An action that sends one event to the server, waits for it to settle and answers with fresh data.
-- `args(data)` gives the event's arguments, `fresh(data)` the answer (a table merged into { success = true }).
local function action(name, event, args, wait, fresh)
    RegisterNUICallback(name, function(data, done)
        TriggerServerEvent(event, table.unpack(args(data)))
        Wait(wait or 500)
        local answer = { success = true }
        for k, v in pairs(fresh and fresh(data) or {}) do answer[k] = v end
        done(answer)
    end)
end

local function ask(callback, ...) return JRS.Await(callback, ...) or {} end

action('buyTrain', 'jrs_railroad:buyTrain', function(d) return { d.trainIndex, current.id } end, 500,
    function() return { ownedTrains = ask('jrs_railroad:getOwnedTrains') } end)

action('buyCompanyTrain', 'jrs_railroad:buyTrain', function(d) return { d.trainIndex, current.id } end, 500,
    function() return { companyTrains = ask('jrs_railroad:getCompanyTrains', current.company) } end)

action('purchaseUpgrade', 'jrs_railroad:purchaseUpgrade', function(d) return { d.companyId, d.trainModel, d.upgradeType } end, 500,
    function(d) return { companyUpgrades = ask('jrs_railroad:getCompanyUpgrades', d.companyId) } end)

action('buyCompany', 'jrs_railroad:buyCompany', function(d) return { d.companyId } end)
action('sellCompany', 'jrs_railroad:sellCompany', function(d) return { d.companyId } end)
action('renameCompany', 'jrs_railroad:renameCompany', function(d) return { d.companyId, d.newName } end, 300)
action('applyAsDriver', 'jrs_railroad:applyAsDriver', function(d) return { d.companyId } end)

action('withdrawFunds', 'jrs_railroad:withdrawFunds', function(d) return { d.companyId, d.amount } end, 500, function(d)
    local ownership = JRS.Await('jrs_railroad:getCompanyOwnership', d.companyId)
    return { cashRegister = ownership and ownership.cash_register or 0 }
end)

action('approveDriver', 'jrs_railroad:approveDriver', function(d) return { d.companyId, d.employeeId } end, 500, function(d)
    return { employees = ask('jrs_railroad:getEmployees', d.companyId), pendingApps = ask('jrs_railroad:getPendingApplications', d.companyId) }
end)

action('rejectDriver', 'jrs_railroad:rejectDriver', function(d) return { d.companyId, d.employeeId } end, 500,
    function(d) return { pendingApps = ask('jrs_railroad:getPendingApplications', d.companyId) } end)

action('fireDriver', 'jrs_railroad:fireDriver', function(d) return { d.companyId, d.employeeId } end, 500,
    function(d) return { employees = ask('jrs_railroad:getEmployees', d.companyId) } end)

action('addSupply', 'jrs_railroad:addSupply', function(d) return { d.companyId, d.itemName, d.quantity } end, 500,
    function(d) return { supplies = ask('jrs_railroad:getCompanySupplies', d.companyId) } end)

action('takeSupply', 'jrs_railroad:takeSupply', function(d) return { d.companyId, d.itemName, d.quantity } end, 500,
    function(d) return { supplies = ask('jrs_railroad:getCompanySupplies', d.companyId) } end)

RegisterNUICallback('sellTrain', function(data, done)
    -- a train that is out has to be taken away before it is sold
    if ActiveTrain and DoesEntityExist(ActiveTrain) and ActiveTrainData and ActiveTrainData.id == data.trainId then
        CleanupActiveTrain()
        TriggerServerEvent('jrs_railroad:setTrainSpawned', false, data.trainId)
    end
    TriggerServerEvent('jrs_railroad:sellTrain', data.trainId)
    Wait(500)
    done({ success = true, ownedTrains = ask('jrs_railroad:getOwnedTrains') })
end)

-- these close the window and then do their thing
local function leaving(name, run)
    RegisterNUICallback(name, function(data, done)
        closeWindow()
        done({ success = true })
        run(data)
    end)
end

leaving('spawnTrain', function(data)
    if not JRS.Await('jrs_railroad:canSpawnTrain') then return Notify(L('train_already_spawned'), 'error') end

    if data.trainIndex then
        local config = Config.Trains[data.trainIndex]
        if not config then return Notify(L('train_config_not_found'), 'error') end
        SpawnConfigTrain(config, data.direction or false, current)
    elseif data.trainId then
        SpawnPlayerTrain(data.trainId, data.direction or false, current)          -- an older save that has a database id
    end
end)

leaving('parkTrain', function() ParkPlayerTrain() end)
leaving('despawnTrain', function() DespawnPlayerTrain() end)
leaving('startMission', function(data) StartMission(data.missionType, current, data.destIndex) end)

-- the server finished a job; the next time a window opens it fetches fresh data anyway
RegisterNetEvent('jrs_railroad:refreshStationData', function() end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    DespawnPlayerTrain()
    DespawnAmbientRouteTrains()
    if ambientBlip then RemoveBlip(ambientBlip) end
    for _, blip in ipairs(stationBlips) do RemoveBlip(blip) end
    for _, blip in ipairs(facilityBlips) do RemoveBlip(blip) end
end)

AddEventHandler('playerDropped', function() DespawnPlayerTrain() end)
