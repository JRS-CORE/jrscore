-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: the player's train
-- Spawning (from the config, or an older save), parking, the wear that fuel, water and condition go through,
-- the look-at menu on the train and the repair / refuel jobs around it.

ActiveTrain = nil            -- the train entity
ActiveTrainBlip = nil
ActiveTrainData = nil        -- row-like table: id, model, fuel, water, condition, upgrades, miles
ActiveTrainConfig = nil      -- its entry in Config.Trains
ActiveTrainStation = nil     -- the station it was started at
EngineRunning = false
TrainFuel, TrainWater, TrainCondition = 0, 0, 0

local SET_TRAIN_CRUISE = 0x9F29999DFDF2AEB8

local function alive() return ActiveTrain and DoesEntityExist(ActiveTrain) end

-- ------------------------------------------------------------------ is the spawn point free?

local trainModels
local function isTrainModel(model)
    if not trainModels then
        trainModels = {}
        for _, t in ipairs(Config.Trains) do trainModels[joaat(t.model)] = true end
    end
    return trainModels[model]
end

-- no other train (of our models) within `radius` of `coords`
function IsTrainSpawnClear(coords, radius)
    radius = radius or 20.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and isTrainModel(GetEntityModel(vehicle)) and GetDistanceBetween(coords, GetEntityCoords(vehicle)) < radius then
            return false
        end
    end
    return true
end

-- ------------------------------------------------------------------ creating the train

-- creates the train entity (standing still) and its blip
local function putTrain(config, at, reversed)
    local hash = joaat(config.model)
    LoadTrainCars(hash)
    ActiveTrain = Citizen.InvokeNative(0xC239DBD9A57D2A71, hash, at.x, at.y, at.z, reversed, config.hasPassengerCars or false, true, false)
    SetTrainSpeed(ActiveTrain, 0.0)
    SetTrainCruiseSpeed(ActiveTrain, 0.0)
    Citizen.InvokeNative(0x05254BA0B44ADC16, ActiveTrain, false)

    ActiveTrainBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, Config.Blips.train.hash, ActiveTrain)
    SetBlipScale(ActiveTrainBlip, Config.Blips.train.scale)
    Citizen.InvokeNative(0x9CB1A1623062F402, ActiveTrainBlip, config.label)
end

local function startRunning()
    StartFuelDecrease()
    StartWaterDecrease()
    StartConditionDecrease()
    StartDistanceMonitor()
    StartMileageTracker()
end

local function takeState(data, config, station)
    ActiveTrainData, ActiveTrainConfig, ActiveTrainStation = data, config, station
    TrainFuel, TrainWater, TrainCondition = data.fuel, data.water, data.condition
    EngineRunning = false
end

-- a train that is saved in the database
function SpawnPlayerTrain(dbId, reversed, station)
    if alive() then return Notify(L('train_already_spawned'), 'error') end

    local data = JRS.Await('jrs_railroad:getTrainById', dbId)
    if not data then return Notify(L('train_not_found'), 'error') end
    local config = FindTrainConfig(data.train_model, data.company_id)
    if not config then return Notify(L('train_config_not_found'), 'error') end

    putTrain(config, station.spawnCoords, reversed)
    takeState(data, config, station)
    TriggerServerEvent('jrs_railroad:setTrainSpawned', true, data.id)
    Notify(L('train_spawned'), 'success')
    DebugPrint('Train spawned: ' .. config.label)

    SetupTrainTarget()
    SetupPassengerTarget()
    startRunning()
end

-- a train of the config: it belongs to the company, so it starts half full with the company's upgrades
function SpawnConfigTrain(config, reversed, station)
    if alive() then return Notify(L('train_already_spawned'), 'error') end

    putTrain(config, station.spawnCoords, reversed)
    local up = JRS.Await('jrs_railroad:getTrainModelUpgrade', config.company, config.model)
    takeState({
        id = 0, train_model = config.model, company_id = config.company, label = config.label,
        fuel = math.floor(config.maxFuel * 0.5), water = math.floor(config.maxWater * 0.5), condition = math.floor(config.maxCondition * 0.5),
        upgrade_speed = up and up.upgrade_speed or 0, upgrade_fuel_cap = up and up.upgrade_fuel_cap or 0,
        upgrade_water_cap = up and up.upgrade_water_cap or 0, upgrade_durability = up and up.upgrade_durability or 0,
        total_miles = 0,
    }, config, station)

    TriggerServerEvent('jrs_railroad:setTrainSpawned', true, 0)
    Notify(L('train_spawned'), 'success')
    DebugPrint('Config train spawned: ' .. config.label)

    SetupTrainTarget()
    startRunning()
end

-- ------------------------------------------------------------------ parking and removing

function ParkPlayerTrain()
    if not alive() then return end

    local station = GetCurrentStation()
    if not station then return Notify(L('must_be_at_station_park'), 'error') end
    if GetDistanceBetween(GetEntityCoords(PlayerPedId()), station.coords) > 50 then return Notify(L('too_far_to_park'), 'error') end

    TriggerServerEvent('jrs_railroad:parkTrain', ActiveTrainData.id, station.id, TrainFuel, TrainWater, TrainCondition)
    CleanupActiveTrain()
    Notify(L('train_parked_msg', station.label), 'success')
end

-- saves fuel, water and condition and takes the train away
local function saveAndRemove()
    TriggerServerEvent('jrs_railroad:updateTrainState', ActiveTrainData.id, TrainFuel, TrainWater, TrainCondition)
    TriggerServerEvent('jrs_railroad:setTrainSpawned', false, ActiveTrainData.id)
    CleanupActiveTrain()
end

function DespawnPlayerTrain()
    if not alive() then return end
    if ActiveTrainData then
        TriggerServerEvent('jrs_railroad:updateTrainState', ActiveTrainData.id, TrainFuel, TrainWater, TrainCondition)
        TriggerServerEvent('jrs_railroad:setTrainSpawned', false, ActiveTrainData.id)
    end
    CleanupActiveTrain()
    Notify(L('train_despawned'), 'inform')
end

local TARGETS <const> = { 'refuel', 'water', 'repair', 'engine', 'reverse', 'switch', 'check', 'sendyard', 'water_item', 'repair_item', 'board', 'unboard' }

function CleanupActiveTrain()
    if alive() then
        for _, name in ipairs(TARGETS) do JRS.RemoveEntityTarget(ActiveTrain, 'railroad_' .. name) end
    end
    if ActiveTrainBlip then
        RemoveBlip(ActiveTrainBlip)
        ActiveTrainBlip = nil
    end
    if alive() then DeleteEntity(ActiveTrain) end

    ActiveTrain, ActiveTrainData, ActiveTrainConfig, ActiveTrainStation = nil, nil, nil, nil
    EngineRunning = false
    TrainFuel, TrainWater, TrainCondition = 0, 0, 0

    CleanupPassengerTarget()
    CleanupDeliveryCargo()
    SendNUIMessage({ action = 'closeTrainHUD' })
end

function SendTrainToYard()
    if not alive() then return Notify(L('no_active_train'), 'error') end
    if not ActiveTrainData then return end
    saveAndRemove()
    Notify(L('train_despawned'), 'success')
end

-- ------------------------------------------------------------------ wear

-- runs `step` every `every` ms for as long as this train exists
local function whileRunning(every, step)
    CreateThread(function()
        while alive() do
            Wait(every)
            if EngineRunning then step() end
        end
    end)
end

-- the engine stops: slow the train down smoothly until it stands
local function coastToStop()
    for _ = 1, 50 do
        if not alive() or TrainFuel > 0 then return end             -- refuelled meanwhile
        local speed = GetEntitySpeed(ActiveTrain)
        if speed < 0.5 then break end
        local slower = speed * 0.92
        SetTrainSpeed(ActiveTrain, slower)
        Citizen.InvokeNative(SET_TRAIN_CRUISE, ActiveTrain, slower + 0.1)
        Wait(200)
    end
    if alive() and TrainFuel <= 0 then
        SetTrainSpeed(ActiveTrain, 0.0)
        Citizen.InvokeNative(SET_TRAIN_CRUISE, ActiveTrain, 0.0)
    end
end

function StartFuelDecrease()
    whileRunning(Config.Fuel.decreaseInterval, function()
        if TrainFuel <= 0 then return end
        TrainFuel = math.max(0, TrainFuel - Config.Fuel.decreaseAmount)
        TriggerServerEvent('jrs_railroad:updateFuel', ActiveTrainData.id, TrainFuel)
        if TrainFuel <= 0 then
            Notify(L('fuel_empty'), 'error')
            CreateThread(coastToStop)
        end
    end)
end

function StartWaterDecrease()
    whileRunning(Config.Water.decreaseInterval, function()
        if TrainWater <= 0 then return end
        TrainWater = math.max(0, TrainWater - Config.Water.decreaseAmount)
        TriggerServerEvent('jrs_railroad:updateWater', ActiveTrainData.id, TrainWater)
        if TrainWater <= 0 then Notify(L('water_empty'), 'warning') end
    end)
end

function StartConditionDecrease()
    whileRunning(Config.Condition.decreaseInterval, function()
        if TrainCondition <= 0 then return end
        local wear = Config.Condition.decreaseAmount
        if TrainWater <= 0 then wear = wear * 2 end                   -- a dry boiler wears the train twice as fast
        TrainCondition = math.max(0, TrainCondition - wear)
        TriggerServerEvent('jrs_railroad:updateCondition', ActiveTrainData.id, TrainCondition)
        if TrainCondition <= 0 then
            Notify(L('condition_critical'), 'error')
            Citizen.InvokeNative(SET_TRAIN_CRUISE, ActiveTrain, ActiveTrainConfig.maxSpeed * Config.Condition.lowConditionSpeedCap + 0.1)
        end
    end)
end

-- a train left far behind is taken away
function StartDistanceMonitor()
    CreateThread(function()
        while alive() do
            Wait(5000)
            if GetDistanceBetween(GetEntityCoords(PlayerPedId()), GetEntityCoords(ActiveTrain)) > Config.TrainDespawnDist then
                Notify(L('train_too_far'), 'error')
                DespawnPlayerTrain()
                return
            end
        end
    end)
end

function StartMileageTracker()
    CreateThread(function()
        local last = GetEntityCoords(ActiveTrain)
        while alive() do
            Wait(10000)
            if EngineRunning then
                local now = GetEntityCoords(ActiveTrain)
                local moved = GetDistanceBetween(last, now)
                if moved > 5 then TriggerServerEvent('jrs_railroad:addMiles', ActiveTrainData.id, moved / 100.0) end
                last = now
            end
        end
    end)
end

-- ------------------------------------------------------------------ jobs around the train

-- the ped stands still doing `scenario` while a progress bar runs; true when it finished
local function work(label, ms, scenario)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    if scenario then TaskStartScenarioInPlace(ped, joaat(scenario), 0, true, false, false, false) end
    local done = JRS.ProgressBar({ duration = ms, label = label, useWhileDead = false, canCancel = true, disable = { move = true, combat = true } })
    return done, function()
        ClearPedTasks(ped)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        FreezeEntityPosition(ped, false)
    end
end

local SHOVEL <const> = { model = 'p_shovel02x', dict = 'amb_work@world_human_gravedig@working@male_b@idle_a', name = 'idle_a', bone = 'skel_r_hand' }

-- shovel coal into the firebox (uses one coal item, the server adds the fuel)
local function shovelCoal()
    if not ActiveTrainData or not ActiveTrainConfig then return end
    if TrainFuel >= ActiveTrainConfig.maxFuel then return Notify(L('fuel_tank_full'), 'error') end
    if not JRS.HasItem(Config.Fuel.item, 1) then return Notify(L('need_item_1x', Config.Fuel.itemLabel), 'error') end

    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    FreezeEntityPosition(ped, true)

    local hash = joaat(SHOVEL.model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(10) end
    local shovel = CreateObject(hash, 0, 0, 0, true, true, true)
    AttachEntityToEntity(shovel, ped, GetEntityBoneIndexByName(ped, SHOVEL.bone), 0.06, -0.06, -0.03, 270.0, 165.0, 150.0, false, false, false, false, 2, true)

    RequestAnimDict(SHOVEL.dict)
    while not HasAnimDictLoaded(SHOVEL.dict) do Wait(10) end
    TaskPlayAnim(ped, SHOVEL.dict, SHOVEL.name, 8.0, -8.0, -1, 1, 0, false, false, false)

    if JRS.ProgressBar({ duration = 5000, label = L('progress_shoveling_coal'), useWhileDead = false, canCancel = true, disable = { move = true, combat = true } }) then
        TriggerServerEvent('jrs_railroad:useMaintenanceItem', Config.Fuel.item, 1, 'fuel', ActiveTrainData.id)
    end

    ClearPedTasks(ped)
    if DoesEntityExist(shovel) then DeleteEntity(shovel) end
    SetModelAsNoLongerNeeded(hash)
    RemoveAnimDict(SHOVEL.dict)
    FreezeEntityPosition(ped, false)
end

local function fillAtTower()
    if not ActiveTrainData or not ActiveTrainConfig then return end
    if not IsNearWaterTower() then return Notify(L('must_near_water_tower'), 'error') end
    if TrainWater >= ActiveTrainConfig.maxWater then return Notify(L('water_tank_full'), 'error') end

    local done, finish = work(L('progress_filling_water_tower'), 8000, 'WORLD_HUMAN_BUCKET_POUR_LOW')
    if done then
        TrainWater = ActiveTrainConfig.maxWater
        Notify(L('water_tank_filled_full'), 'success')
    end
    finish()
end

local function repairAtDepot()
    if not ActiveTrainData or not ActiveTrainConfig then return end
    if not IsNearMaintenanceDepot() then return Notify(L('must_near_maintenance_depot'), 'error') end
    if TrainCondition >= ActiveTrainConfig.maxCondition then return Notify(L('condition_full'), 'error') end

    local done, finish = work(L('progress_full_maintenance_repair'), 10000, 'WORLD_HUMAN_CROUCH_INSPECT')
    if done then
        TrainCondition = ActiveTrainConfig.maxCondition
        Notify(L('train_fully_repaired_full'), 'success')
    end
    finish()
end

-- emergency help with an item (a bucket of water, a repair kit): the server uses the item up
local function useItem(spec, kind, labelKey, scenario)
    return function()
        if not ActiveTrainData or not ActiveTrainConfig then return end
        if not JRS.HasItem(spec.item, 1) then return Notify(L('need_item_1x', spec.itemLabel), 'error') end

        local done, finish = work(L(labelKey), 4000, scenario)
        if done then TriggerServerEvent('jrs_railroad:useMaintenanceItem', spec.item, 1, kind, ActiveTrainData.id) end
        finish()
    end
end

-- turn the train around: it is taken away and put back where it stood, facing the other way
local function turnAround()
    if not alive() or not ActiveTrainConfig then return end
    if GetEntitySpeed(ActiveTrain) > 1 then return Notify(L('stop_before_reversing'), 'error') end

    local at = GetEntityCoords(ActiveTrain)
    local flipped = not (ActiveTrainData._reversed or false)
    local fuel, water, condition, config, station = TrainFuel, TrainWater, TrainCondition, ActiveTrainConfig, ActiveTrainStation

    CleanupActiveTrain()
    putTrain(config, at, flipped)
    takeState({
        id = 0, train_model = config.model, company_id = config.company, label = config.label,
        fuel = fuel, water = water, condition = condition,
        upgrade_speed = 0, upgrade_fuel_cap = 0, upgrade_water_cap = 0, upgrade_durability = 0, total_miles = 0, _reversed = flipped,
    }, config, station)

    TriggerServerEvent('jrs_railroad:setTrainSpawned', true, 0)
    SetupTrainTarget()
    startRunning()
    Notify(L('train_reversed'), 'success')
end

-- ------------------------------------------------------------------ what the player can do by looking at the train

function SetupTrainTarget()
    if not alive() then return end

    local function option(name, label, icon, onSelect, extra)
        local o = { name = 'railroad_' .. name, label = L(label), icon = icon, distance = 4.0, onSelect = onSelect }
        for k, v in pairs(extra or {}) do o[k] = v end
        return o
    end

    JRS.AddEntityTarget(ActiveTrain, {
        option('engine', 'menu_start_stop_engine', 'fas fa-power-off', function() ToggleEngine() end),
        option('refuel', 'menu_add_coal', 'fas fa-fire', shovelCoal),
        option('check', 'menu_check_condition', 'fas fa-clipboard-check', function() OpenConditionMenu() end),
        option('switch', 'menu_toggle_switches', 'fas fa-random', function() ToggleTrackSwitches() end),
        option('water', 'menu_fill_water_tower', 'fas fa-tint', fillAtTower),
        option('repair', 'menu_full_repair_depot', 'fas fa-wrench', repairAtDepot),
        option('water_item', 'menu_emergency_water', 'fas fa-tint', useItem(Config.Water, 'water', 'progress_emergency_water', 'WORLD_HUMAN_BUCKET_POUR_LOW'),
            { canInteract = function() return TrainWater <= 0 end }),
        option('repair_item', 'menu_emergency_repair', 'fas fa-wrench', useItem(Config.Condition, 'condition', 'progress_emergency_repair', 'WORLD_HUMAN_CROUCH_INSPECT'),
            { canInteract = function() return TrainCondition <= 0 end }),
        option('reverse', 'menu_reverse_direction', 'fas fa-exchange-alt', turnAround),
        option('all_aboard', 'menu_all_aboard', 'fas fa-users', function() if TriggerAllAboard then TriggerAllAboard() end end, {
            distance = 6.0,
            canInteract = function()
                return ActiveTrainConfig and ActiveTrainConfig.hasPassengerCars == true and GetNearestStoppedStation ~= nil and GetNearestStoppedStation() ~= nil
            end,
        }),
        option('sendyard', 'menu_send_train_yard', 'fas fa-warehouse', SendTrainToYard),
    })
end

-- ------------------------------------------------------------------ the condition report

function GetBarDisplay(percent)
    local filled = math.floor(percent / 10)
    return string.rep('\u{2588}', filled) .. string.rep('\u{2591}', 10 - filled)
end

local function capacity(base, kind)
    local level = ActiveTrainData[kind] or 0
    local step = Config.Upgrades[kind == 'upgrade_fuel_cap' and 'fuel_cap' or 'water_cap'][level]
    return level > 0 and step and base + step.bonus or base
end

function OpenConditionMenu()
    if not ActiveTrainData or not ActiveTrainConfig then return Notify(L('no_active_train'), 'error') end

    local maxFuel = capacity(ActiveTrainConfig.maxFuel, 'upgrade_fuel_cap')
    local maxWater = capacity(ActiveTrainConfig.maxWater, 'upgrade_water_cap')
    local maxCondition = ActiveTrainConfig.maxCondition

    local function bar(value, max)
        local percent = math.floor(value / max * 100)
        return ('%s  %s/%s (%s%%)'):format(GetBarDisplay(percent), value, max, percent)
    end

    local company = Config.Companies[ActiveTrainConfig.company]
    JRS.RegisterContext({
        id = 'railroad_condition_menu',
        title = L('report_condition_title'),
        options = {
            { title = L('report_fuel_title'), description = bar(TrainFuel, maxFuel), icon = 'fire' },
            { title = L('report_water_title'), description = bar(TrainWater, maxWater), icon = 'tint' },
            { title = L('report_condition_row_title'), description = bar(TrainCondition, maxCondition), icon = 'wrench' },
            { title = L('report_engine_title'), description = EngineRunning and L('report_engine_running') or L('report_engine_stopped'), icon = 'cog' },
            { title = L('report_speed_title'), description = GetCurrentSpeed() .. ' / ' .. GetMaxTrainSpeed() .. ' max', icon = 'tachometer-alt' },
            { title = L('report_miles_title'), description = string.format('%.1f', ActiveTrainData.total_miles or 0), icon = 'road' },
            { title = L('report_company_title'), description = company and company.label or L('report_company_unknown'), icon = 'building' },
        },
    })
    JRS.ShowContext('railroad_condition_menu')
end

-- ------------------------------------------------------------------ values the server corrects

RegisterNetEvent('jrs_railroad:syncFuel', function(v) TrainFuel = v end)
RegisterNetEvent('jrs_railroad:syncWater', function(v) TrainWater = v end)
RegisterNetEvent('jrs_railroad:syncCondition', function(v) TrainCondition = v end)

-- the server used up the item: apply the 10% here
RegisterNetEvent('jrs_railroad:maintenanceResult', function(kind, success)
    if not success or not ActiveTrainConfig then return end
    local steps = {
        fuel = { 'maxFuel', 'TrainFuel', 'fuel_added_pct' },
        water = { 'maxWater', 'TrainWater', 'water_added_pct' },
        condition = { 'maxCondition', 'TrainCondition', 'condition_repaired_pct' },
    }
    local step = steps[kind]
    if not step then return end

    local max = ActiveTrainConfig[step[1]]
    local value = math.min(_G[step[2]] + math.floor(max * 0.10), max)
    _G[step[2]] = value
    Notify(L(step[3], math.floor(value / max * 100)), 'success')
end)
