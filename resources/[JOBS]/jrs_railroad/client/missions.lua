local activeMission = nil
local missionBlip = nil

local function CreateMissionBlip(coords, label, radius, color)
    local blip = Citizen.InvokeNative(0x45F13B7E0A15C880,
        -1282792512, coords.x, coords.y, coords.z, 20.0)
    Citizen.InvokeNative(0x662D364ABF16DE2A, blip, color)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, label)
    return blip
end

-- Returns the index of the entry in `list` closest to `fromCoords`, skipping
-- any index present in `exclude` (a set: exclude[i] = true). Falls back to
-- the closest entry overall if every entry has been excluded.
local function GetClosestIndex(list, fromCoords, exclude)
    local bestIdx, bestDist
    for i, entry in ipairs(list) do
        if not (exclude and exclude[i]) then
            local dist = GetDistanceBetween(fromCoords, entry.coords)
            if not bestDist or dist < bestDist then
                bestDist = dist
                bestIdx = i
            end
        end
    end
    if not bestIdx then
        for i, entry in ipairs(list) do
            local dist = GetDistanceBetween(fromCoords, entry.coords)
            if not bestDist or dist < bestDist then
                bestDist = dist
                bestIdx = i
            end
        end
    end
    return bestIdx
end

function IsOnMission()    return activeMission ~= nil end
function GetActiveMissionInfo() return activeMission end

---------------------------------------------------------------
-- START MISSION
---------------------------------------------------------------
function StartMission(missionType, station, destIndex)
    if activeMission then Notify(L('mission_active'), 'error') return end
    if missionType == 'delivery' then
        -- StartDeliveryMission handles its own train requirement (it can
        -- auto-spawn the correct one), so it doesn't need the generic check.
        StartDeliveryMission(station, destIndex)
    elseif missionType == 'maintenance' then
        if not ActiveTrain or not DoesEntityExist(ActiveTrain) then
            Notify(L('mission_no_train'), 'error') return
        end
        StartMaintenanceMission(station, destIndex)
    end
end

---------------------------------------------------------------
-- DELIVERY MISSION (job chain: closest stop each leg)
---------------------------------------------------------------
function StartDeliveryMission(station, destIndex)
    -- Delivery jobs need a physical flatbed car for the cargo barrels, and only
    -- appleseed_config is coupled with one. If the player doesn't already have a
    -- train out, auto-spawn the right one for this station's company (checking
    -- the track is clear first) instead of requiring a manual deploy beforehand.
    if Config.CargoDelivery and Config.CargoDelivery.Enabled then
        if ActiveTrain and DoesEntityExist(ActiveTrain) then
            if not ActiveTrainConfig or ActiveTrainConfig.model ~= Config.CargoDelivery.RequiredTrainModel then
                Notify(L('delivery_wrong_train'), 'error', 8000)
                return
            end
        else
            local trainConfig = FindTrainConfig(Config.CargoDelivery.RequiredTrainModel, station.company)
            if not trainConfig then
                Notify(L('delivery_wrong_train'), 'error', 8000)
                return
            end

            local canSpawn = JRS.Await('jrs_railroad:canSpawnTrain')
            if not canSpawn then
                Notify(L('train_already_spawned'), 'error')
                return
            end

            if not IsTrainSpawnClear(station.spawnCoords) then
                Notify(L('station_track_occupied'), 'error', 8000)
                return
            end

            SpawnConfigTrain(trainConfig, false, station)
            if not ActiveTrain or not DoesEntityExist(ActiveTrain) then
                return -- SpawnConfigTrain already notified on failure
            end
        end
    elseif not ActiveTrain or not DoesEntityExist(ActiveTrain) then
        Notify(L('mission_no_train'), 'error')
        return
    end

    local destList = Config.DeliveryDestinations
    if #destList == 0 then return end

    local visited = {}
    local idx
    if destIndex and destList[destIndex] then
        idx = destIndex
    else
        idx = GetClosestIndex(destList, GetEntityCoords(ActiveTrain), visited)
    end
    if not idx then return end
    visited[idx] = true

    activeMission = {
        type = 'delivery',
        startStation = station,
        leg = 1,
        -- Manual destIndex selections stay a single-stop mission; the
        -- "Start a Delivery Job" button (no destIndex) runs the full chain.
        totalLegs = destIndex and 1 or (Config.Missions.delivery.jobLegs or 1),
        visited = visited,
    }

    activeMission.cargoProps = SpawnDeliveryCargo(activeMission.totalLegs)
    Notify(L('cargo_load_instructions'), 'inform', 10000)

    BeginDeliveryLeg(destList[idx])
end

function BeginDeliveryLeg(dest)
    local cargo = Config.Missions.delivery.cargoTypes[math.random(1, #Config.Missions.delivery.cargoTypes)]
    activeMission.destination = dest
    activeMission.cargo = cargo

    if missionBlip then RemoveBlip(missionBlip) end
    missionBlip = CreateMissionBlip(dest.coords, dest.label, dest.radius or 25.0, 0xFF0000FF)

    SetCargoDestination(dest)

    local legTag = activeMission.totalLegs > 1 and L('mission_leg_tag', activeMission.leg, activeMission.totalLegs) or ''
    Notify(L('mission_cargo', cargo.label), 'inform', 7000)
    Wait(500)
    Notify(L('mission_go_to', dest.label) .. legTag .. L('mission_follow_blip'), 'success', 10000)

    local myLeg = activeMission.leg
    CreateThread(function()
        local notifiedClose = false
        local notifiedArrived = false
        while activeMission and activeMission.type == 'delivery' and activeMission.leg == myLeg do
            Wait(2000)
            if not ActiveTrain or not DoesEntityExist(ActiveTrain) or IsEntityDead(PlayerPedId()) then
                FailMission() break
            end
            local dist = GetDistanceBetween(GetEntityCoords(ActiveTrain), dest.coords)
            if dist < 200 and not notifiedClose then
                notifiedClose = true
                Notify(L('mission_approaching', dest.label), 'inform', 6000)
            end
            if dist < (dest.radius or 25.0) and not notifiedArrived then
                notifiedArrived = true
                Notify(L('mission_carry_to', dest.label), 'success', 8000)
            end
        end
    end)
end

function CompleteDeliveryLeg()
    if not activeMission then return end
    local companyId = (activeMission.startStation and activeMission.startStation.company)
        or (ActiveTrainConfig and ActiveTrainConfig.company)
    TriggerServerEvent('jrs_railroad:completeMission',
        activeMission.type, activeMission.destination, activeMission.cargo, companyId)

    if activeMission.leg >= activeMission.totalLegs then
        Notify(L('delivery_job_complete'), 'success', 8000)
        CleanupMission()
        return
    end

    local nextIdx = GetClosestIndex(Config.DeliveryDestinations, GetEntityCoords(ActiveTrain), activeMission.visited)
    if not nextIdx then
        Notify(L('delivery_job_complete'), 'success', 8000)
        CleanupMission()
        return
    end

    activeMission.leg = activeMission.leg + 1
    activeMission.visited[nextIdx] = true
    BeginDeliveryLeg(Config.DeliveryDestinations[nextIdx])
end

---------------------------------------------------------------
-- MAINTENANCE MISSION (job chain: closest stop each leg)
---------------------------------------------------------------
function StartMaintenanceMission(station, destIndex)
    local cfg = Config.Missions.maintenance
    if #cfg.locations == 0 then return end

    local visited = {}
    local idx
    if destIndex and cfg.locations[destIndex] then
        idx = destIndex
    else
        idx = GetClosestIndex(cfg.locations, GetEntityCoords(ActiveTrain), visited)
    end
    if not idx then return end
    visited[idx] = true

    activeMission = {
        type = 'maintenance',
        startStation = station,
        leg = 1,
        totalLegs = destIndex and 1 or (cfg.jobLegs or 1),
        visited = visited,
    }

    BeginMaintenanceLeg(cfg.locations[idx])
end

function BeginMaintenanceLeg(loc)
    activeMission.location = loc

    if missionBlip then RemoveBlip(missionBlip) end
    missionBlip = CreateMissionBlip(loc.coords, loc.label, 25.0, 0xFFFF00FF)

    local legTag = activeMission.totalLegs > 1 and (' (Job ' .. activeMission.leg .. '/' .. activeMission.totalLegs .. ')') or ''
    Notify(L('maintenance_travel_to', loc.label, legTag), 'success', 10000)

    local myLeg = activeMission.leg
    CreateThread(function()
        local cfg = Config.Missions.maintenance
        while activeMission and activeMission.type == 'maintenance' and activeMission.leg == myLeg do
            Wait(1000)
            if not ActiveTrain or not DoesEntityExist(ActiveTrain) or IsEntityDead(PlayerPedId()) then
                FailMission() break
            end
            local pcoords = GetEntityCoords(PlayerPedId())
            if GetDistanceBetween(pcoords, loc.coords) < 5 then
                Notify(L('mission_repair_start'), 'inform')
                local ped = PlayerPedId()
                FreezeEntityPosition(ped, true)
                TaskStartScenarioInPlace(ped, joaat('WORLD_HUMAN_CROUCH_INSPECT'), 0, true, false, false, false)
                if JRS.ProgressBar({
                    duration = cfg.repairTime,
                    label = L('mission_repair_start'),
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, combat = true },
                }) then
                    ClearPedTasks(ped) FreezeEntityPosition(ped, false)
                    Notify(L('mission_repair_complete'), 'success')
                    CompleteMaintenanceLeg()
                else
                    ClearPedTasks(ped) FreezeEntityPosition(ped, false)
                    Notify(L('mission_failed'), 'error')
                    FailMission()
                end
                break
            end
        end
    end)
end

function CompleteMaintenanceLeg()
    if not activeMission then return end
    local companyId = (activeMission.startStation and activeMission.startStation.company)
        or (ActiveTrainConfig and ActiveTrainConfig.company)
    TriggerServerEvent('jrs_railroad:completeMission',
        activeMission.type, activeMission.location, nil, companyId)

    if activeMission.leg >= activeMission.totalLegs then
        Notify(L('maintenance_job_complete'), 'success', 8000)
        CleanupMission()
        return
    end

    local nextIdx = GetClosestIndex(Config.Missions.maintenance.locations, GetEntityCoords(ActiveTrain), activeMission.visited)
    if not nextIdx then
        Notify(L('maintenance_job_complete'), 'success', 8000)
        CleanupMission()
        return
    end

    activeMission.leg = activeMission.leg + 1
    activeMission.visited[nextIdx] = true
    BeginMaintenanceLeg(Config.Missions.maintenance.locations[nextIdx])
end

---------------------------------------------------------------
-- FAIL / CLEANUP
---------------------------------------------------------------
function FailMission()
    Notify(L('mission_failed'), 'error')
    CleanupMission()
    if ActiveTrain and DoesEntityExist(ActiveTrain) then SendTrainToYard() end
end

function CleanupMission()
    activeMission = nil
    if missionBlip then RemoveBlip(missionBlip) missionBlip = nil end
    CleanupDeliveryCargo()
end
