---------------------------------------------------------------
-- OPEN TRAIN HUD (when entering driver seat)
---------------------------------------------------------------
function OpenTrainHUD()
    if not ActiveTrain or not ActiveTrainConfig then return end

    SendNUIMessage({
        action = 'openTrainHUD',
        train = {
            label = ActiveTrainConfig.label,
            model = ActiveTrainConfig.model,
            company = ActiveTrainConfig.company,
            companyLabel = Config.Companies[ActiveTrainConfig.company] and Config.Companies[ActiveTrainConfig.company].label or '',
            maxSpeed = GetMaxTrainSpeed(),
            maxFuel = ActiveTrainConfig.maxFuel + (ActiveTrainData.upgrade_fuel_cap > 0 and Config.Upgrades.fuel_cap[ActiveTrainData.upgrade_fuel_cap].bonus or 0),
            maxWater = ActiveTrainConfig.maxWater + (ActiveTrainData.upgrade_water_cap > 0 and Config.Upgrades.water_cap[ActiveTrainData.upgrade_water_cap].bonus or 0),
            maxCondition = ActiveTrainConfig.maxCondition,
            trainId = ActiveTrainData.id,
        },
        lang = GetLocaleTable(),
    })
end

---------------------------------------------------------------
-- CLOSE TRAIN HUD
---------------------------------------------------------------
function CloseTrainHUD()
    SendNUIMessage({ action = 'closeTrainHUD' })
end

---------------------------------------------------------------
-- UPDATE HUD DATA (called periodically from train_control)
---------------------------------------------------------------
function UpdateTrainHUDData()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return end

    -- Find nearest station
    local tcoords = GetEntityCoords(ActiveTrain)
    local nearestStation, _ = GetNearestStation(tcoords)

    -- Junction info
    local juncInfo = GetNearestJunctionInfo()
    local juncText = '--'
    if juncInfo then
        local stateLabel = (juncInfo.state == 1) and 'ALT' or 'MAIN'
        juncText = stateLabel .. ' (' .. juncInfo.dist .. 'm)'
    end

    SendNUIMessage({
        action = 'updateHUD',
        speed = GetCurrentSpeed(),
        maxSpeed = GetMaxTrainSpeed(),
        fuel = TrainFuel,
        maxFuel = ActiveTrainConfig.maxFuel + (ActiveTrainData.upgrade_fuel_cap > 0 and Config.Upgrades.fuel_cap[ActiveTrainData.upgrade_fuel_cap].bonus or 0),
        water = TrainWater,
        maxWater = ActiveTrainConfig.maxWater + (ActiveTrainData.upgrade_water_cap > 0 and Config.Upgrades.water_cap[ActiveTrainData.upgrade_water_cap].bonus or 0),
        condition = TrainCondition,
        maxCondition = ActiveTrainConfig.maxCondition,
        engine = EngineRunning,
        cruiseForward = IsCruiseForward(),
        cruiseBackward = IsCruiseBackward(),
        nearestStation = nearestStation and nearestStation.label or 'Unknown',
        switchState = GetSwitchState(),
        junctionText = juncText,
        missionActive = IsOnMission(),
        missionInfo = GetActiveMissionInfo(),
    })
end
