-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: the driver HUD (a page) and what it shows

-- tank size with the upgrade bonus of that tank
local function tank(base, level, steps)
    local step = level and level > 0 and steps[level]
    return step and base + step.bonus or base
end

local function maxFuel() return tank(ActiveTrainConfig.maxFuel, ActiveTrainData.upgrade_fuel_cap, Config.Upgrades.fuel_cap) end
local function maxWater() return tank(ActiveTrainConfig.maxWater, ActiveTrainData.upgrade_water_cap, Config.Upgrades.water_cap) end

-- sent when the driver sits down
function OpenTrainHUD()
    if not ActiveTrain or not ActiveTrainConfig then return end
    local company = Config.Companies[ActiveTrainConfig.company]
    SendNUIMessage({
        action = 'openTrainHUD',
        train = {
            label = ActiveTrainConfig.label, model = ActiveTrainConfig.model, company = ActiveTrainConfig.company,
            companyLabel = company and company.label or '',
            maxSpeed = GetMaxTrainSpeed(), maxFuel = maxFuel(), maxWater = maxWater(),
            maxCondition = ActiveTrainConfig.maxCondition, trainId = ActiveTrainData.id,
        },
        lang = GetLocaleTable(),
    })
end

function CloseTrainHUD() SendNUIMessage({ action = 'closeTrainHUD' }) end

-- sent about twice a second while the HUD is up
function UpdateTrainHUDData()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return end

    local station = GetNearestStation(GetEntityCoords(ActiveTrain))
    local junction = GetNearestJunctionInfo()
    local junctionText = '--'
    if junction then junctionText = (junction.state == 1 and 'ALT' or 'MAIN') .. ' (' .. junction.dist .. 'm)' end

    SendNUIMessage({
        action = 'updateHUD',
        speed = GetCurrentSpeed(), maxSpeed = GetMaxTrainSpeed(),
        fuel = TrainFuel, maxFuel = maxFuel(), water = TrainWater, maxWater = maxWater(),
        condition = TrainCondition, maxCondition = ActiveTrainConfig.maxCondition,
        engine = EngineRunning, cruiseForward = IsCruiseForward(), cruiseBackward = IsCruiseBackward(),
        nearestStation = station and station.label or 'Unknown',
        switchState = GetSwitchState(), junctionText = junctionText,
        missionActive = IsOnMission(), missionInfo = GetActiveMissionInfo(),
    })
end
