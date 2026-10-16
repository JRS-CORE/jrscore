-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: missions
-- A delivery job takes barrels to destinations, a maintenance job repairs the track at places. Both run
-- as a chain of legs: after each leg the closest stop that was not visited yet comes next. The server pays
-- every finished leg (completeMission).

local mission                 -- the running job, or nil
local blip

local function markPlace(at, label, colour)
    local b = Citizen.InvokeNative(0x45F13B7E0A15C880, -1282792512, at.x, at.y, at.z, 20.0)
    Citizen.InvokeNative(0x662D364ABF16DE2A, b, colour)
    Citizen.InvokeNative(0x9CB1A1623062F402, b, label)
    return b
end

-- index of the closest entry of `list` that is not in `skip`; if all are skipped, the closest of all
local function closest(list, from, skip)
    local best, bestAway
    local function scan(allowSkipped)
        for i, entry in ipairs(list) do
            if allowSkipped or not (skip and skip[i]) then
                local away = GetDistanceBetween(from, entry.coords)
                if not bestAway or away < bestAway then best, bestAway = i, away end
            end
        end
    end
    scan(false)
    if not best then scan(true) end
    return best
end

function IsOnMission() return mission ~= nil end
function GetActiveMissionInfo() return mission end

local function trainAlive() return ActiveTrain and DoesEntityExist(ActiveTrain) end
local function companyOf() return (mission.startStation and mission.startStation.company) or (ActiveTrainConfig and ActiveTrainConfig.company) end

function CleanupMission()
    mission = nil
    if blip then RemoveBlip(blip) blip = nil end
    CleanupDeliveryCargo()
end

function FailMission()
    Notify(L('mission_failed'), 'error')
    CleanupMission()
    if trainAlive() then SendTrainToYard() end
end

-- the first stop: the one the player chose, else the closest
local function firstStop(list, picked)
    if #list == 0 then return nil end
    local index = (picked and list[picked]) and picked or closest(list, GetEntityCoords(ActiveTrain), {})
    return index
end

-- after a leg: the next stop of the chain, or nil when the chain is done
local function nextStop(list)
    if mission.leg >= mission.totalLegs then return nil end
    local index = closest(list, GetEntityCoords(ActiveTrain), mission.visited)
    if not index then return nil end
    mission.leg = mission.leg + 1
    mission.visited[index] = true
    return list[index]
end

-- ------------------------------------------------------------------ starting

function StartMission(kind, station, pickedIndex)
    if mission then return Notify(L('mission_active'), 'error') end

    if kind == 'delivery' then
        StartDeliveryMission(station, pickedIndex)             -- may start a train by itself
    elseif kind == 'maintenance' then
        if not trainAlive() then return Notify(L('mission_no_train'), 'error') end
        StartMaintenanceMission(station, pickedIndex)
    end
end

-- ------------------------------------------------------------------ delivery

-- a delivery needs the flat car, which only one train model pulls: put that train on the track if none is out
local function ensureDeliveryTrain(station)
    local cargo = Config.CargoDelivery
    if not (cargo and cargo.Enabled) then
        if not trainAlive() then Notify(L('mission_no_train'), 'error') return false end
        return true
    end

    if trainAlive() then
        if not ActiveTrainConfig or ActiveTrainConfig.model ~= cargo.RequiredTrainModel then
            Notify(L('delivery_wrong_train'), 'error', 8000)
            return false
        end
        return true
    end

    local config = FindTrainConfig(cargo.RequiredTrainModel, station.company)
    if not config then Notify(L('delivery_wrong_train'), 'error', 8000) return false end
    if not JRS.Await('jrs_railroad:canSpawnTrain') then Notify(L('train_already_spawned'), 'error') return false end
    if not IsTrainSpawnClear(station.spawnCoords) then Notify(L('station_track_occupied'), 'error', 8000) return false end

    SpawnConfigTrain(config, false, station)
    return trainAlive()
end

function StartDeliveryMission(station, pickedIndex)
    if not ensureDeliveryTrain(station) then return end

    local places = Config.DeliveryDestinations
    local index = firstStop(places, pickedIndex)
    if not index then return end

    mission = {
        type = 'delivery', startStation = station, leg = 1,
        -- a stop chosen by hand is a single trip; "start a job" runs the whole chain
        totalLegs = pickedIndex and 1 or (Config.Missions.delivery.jobLegs or 1),
        visited = { [index] = true },
    }
    mission.cargoProps = SpawnDeliveryCargo(mission.totalLegs)
    Notify(L('cargo_load_instructions'), 'inform', 10000)

    BeginDeliveryLeg(places[index])
end

function BeginDeliveryLeg(place)
    local types = Config.Missions.delivery.cargoTypes
    local cargo = types[math.random(1, #types)]
    mission.destination, mission.cargo = place, cargo

    if blip then RemoveBlip(blip) end
    blip = markPlace(place.coords, place.label, 0xFF0000FF)
    SetCargoDestination(place)

    local tag = mission.totalLegs > 1 and L('mission_leg_tag', mission.leg, mission.totalLegs) or ''
    Notify(L('mission_cargo', cargo.label), 'inform', 7000)
    Wait(500)
    Notify(L('mission_go_to', place.label) .. tag .. L('mission_follow_blip'), 'success', 10000)

    local leg = mission.leg
    CreateThread(function()
        local close, arrived = false, false
        while mission and mission.type == 'delivery' and mission.leg == leg do
            Wait(2000)
            if not trainAlive() or IsEntityDead(PlayerPedId()) then return FailMission() end

            local away = GetDistanceBetween(GetEntityCoords(ActiveTrain), place.coords)
            if away < 200 and not close then
                close = true
                Notify(L('mission_approaching', place.label), 'inform', 6000)
            end
            if away < (place.radius or 25.0) and not arrived then
                arrived = true
                Notify(L('mission_carry_to', place.label), 'success', 8000)
            end
        end
    end)
end

-- a barrel was delivered (called from cargo.lua)
function CompleteDeliveryLeg()
    if not mission then return end
    TriggerServerEvent('jrs_railroad:completeMission', mission.type, mission.destination, mission.cargo, companyOf())

    local nextPlace = nextStop(Config.DeliveryDestinations)
    if not nextPlace then
        Notify(L('delivery_job_complete'), 'success', 8000)
        return CleanupMission()
    end
    BeginDeliveryLeg(nextPlace)
end

-- ------------------------------------------------------------------ maintenance

function StartMaintenanceMission(station, pickedIndex)
    local spec = Config.Missions.maintenance
    local index = firstStop(spec.locations, pickedIndex)
    if not index then return end

    mission = {
        type = 'maintenance', startStation = station, leg = 1,
        totalLegs = pickedIndex and 1 or (spec.jobLegs or 1), visited = { [index] = true },
    }
    BeginMaintenanceLeg(spec.locations[index])
end

-- the repair itself: stand at the spot, the ped crouches and a progress bar runs
local function repairHere(spec)
    local ped = PlayerPedId()
    Notify(L('mission_repair_start'), 'inform')
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, joaat('WORLD_HUMAN_CROUCH_INSPECT'), 0, true, false, false, false)

    local done = JRS.ProgressBar({
        duration = spec.repairTime, label = L('mission_repair_start'), useWhileDead = false, canCancel = true,
        disable = { move = true, combat = true },
    })
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    return done
end

function BeginMaintenanceLeg(place)
    mission.location = place
    if blip then RemoveBlip(blip) end
    blip = markPlace(place.coords, place.label, 0xFFFF00FF)

    local tag = mission.totalLegs > 1 and (' (Job ' .. mission.leg .. '/' .. mission.totalLegs .. ')') or ''
    Notify(L('maintenance_travel_to', place.label, tag), 'success', 10000)

    local leg = mission.leg
    CreateThread(function()
        local spec = Config.Missions.maintenance
        while mission and mission.type == 'maintenance' and mission.leg == leg do
            Wait(1000)
            if not trainAlive() or IsEntityDead(PlayerPedId()) then return FailMission() end

            if GetDistanceBetween(GetEntityCoords(PlayerPedId()), place.coords) < 5 then
                if repairHere(spec) then
                    Notify(L('mission_repair_complete'), 'success')
                    CompleteMaintenanceLeg()
                else
                    Notify(L('mission_failed'), 'error')
                    FailMission()
                end
                return
            end
        end
    end)
end

function CompleteMaintenanceLeg()
    if not mission then return end
    TriggerServerEvent('jrs_railroad:completeMission', mission.type, mission.location, nil, companyOf())

    local nextPlace = nextStop(Config.Missions.maintenance.locations)
    if not nextPlace then
        Notify(L('maintenance_job_complete'), 'success', 8000)
        return CleanupMission()
    end
    BeginMaintenanceLeg(nextPlace)
end
