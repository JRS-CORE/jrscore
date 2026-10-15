-- ============================================================
--  jrs_railroad  |  passengers.lua
--  Continuous passenger system — runs alongside normal driving.
--  At each station stop, "All Aboard" lets the driver grab
--  ambient world NPCs. They walk to the train, board (hidden),
--  disembark at later stops, and pay per passenger per leg.
-- ============================================================

local boardedPassengers  = {}    -- handles of hidden boarded peds
local boardingInProgress = false
local passengerTargetAdded = false
local stationCooldown    = {}   -- prevent double-fire per station visit
local lastStation        = nil

-- ── Helper: is the current train a passenger train? ──────
local function IsPassengerTrain()
    return ActiveTrainConfig and ActiveTrainConfig.hasPassengerCars == true
end

-- ── Helper: is the train stopped near a station? ─────────
-- Global so train_spawn.lua canInteract can reference it.
function GetNearestStoppedStation()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return nil end
    if GetEntitySpeed(ActiveTrain) > Config.PassengerSystem.TrainStopSpeed then return nil end
    local tc = GetEntityCoords(ActiveTrain)
    for _, station in ipairs(Config.Stations) do
        if GetDistanceBetween(tc, station.coords) < Config.PassengerSystem.StationStopRadius then
            return station
        end
    end
    return nil
end

-- ── Get nearest point on the train (engine or any carriage) ──
local function GetNearestTrainCoords(fromCoords)
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then return fromCoords end
    local nearest = GetEntityCoords(ActiveTrain)
    local nearestDist = GetDistanceBetween(fromCoords, nearest)
    -- Check passenger carriages
    local numCars = Citizen.InvokeNative(0x60B7D1DCC312697D, ActiveTrain)
    for i = 1, (numCars or 1) - 1 do
        local carriage = GetTrainCarriage(ActiveTrain, i)
        if carriage and DoesEntityExist(carriage) then
            local cc = GetEntityCoords(carriage)
            local d  = GetDistanceBetween(fromCoords, cc)
            if d < nearestDist then
                nearestDist = d
                nearest = cc
            end
        end
    end
    return nearest
end

-- ── Scan for nearby ambient peds ─────────────────────────
local function FindNearbyPassengers(stationCoords)
    local cfg    = Config.PassengerSystem
    local found  = {}

    local function checkPed(ped)
        if not DoesEntityExist(ped) then return end
        if ped == PlayerPedId() then return end
        if IsEntityDead(ped) then return end
        if IsPedAPlayer(ped) then return end
        -- NOTE: Do NOT filter by IsPedInAnyVehicle -- seated NPCs on benches
        -- are flagged as "in a vehicle" in RDR2 and would all be excluded.
        local dist = GetDistanceBetween(GetEntityCoords(ped), stationCoords)
        if dist < cfg.SearchRadius then
            table.insert(found, ped)
        end
    end

    for _, ped in ipairs(GetGamePool('CPed')) do checkPed(ped) end
    DebugPrint('[Passengers] Found ' .. #found .. ' candidate peds within ' .. cfg.SearchRadius .. 'm')
    return found
end

-- ── Disembark a random portion at this station ───────────
local function ProcessDisembarkation(station)
    local cfg = Config.PassengerSystem
    if #boardedPassengers == 0 then return 0 end

    local disembarked = 0
    local remaining   = {}

    for _, ped in ipairs(boardedPassengers) do
        local canDisembark = (#boardedPassengers - disembarked) > cfg.MinBoardedToKeep
        local willDisembark = math.random(100) <= cfg.DisembarkChance

        if willDisembark and canDisembark and DoesEntityExist(ped) then
            -- Make visible near platform
            local ox = math.random(-6, 6)
            local oy = math.random(-6, 6)
            SetEntityCoords(ped,
                station.coords.x + ox,
                station.coords.y + oy,
                station.coords.z,
                false, false, false, false)
            SetEntityVisible(ped, true, false)
            PlaceEntityOnGroundProperly(ped)
            -- Walk away briefly then delete
            local tc = GetEntityCoords(ped)
            TaskGoToCoordAnyMeans(ped,
                tc.x + math.random(-20, 20),
                tc.y + math.random(-20, 20),
                tc.z, 1.0, 0, false, 786603, 0xbf800000)
            local pedRef = ped
            SetTimeout(12000, function()
                if DoesEntityExist(pedRef) then
                    SetEntityAsMissionEntity(pedRef, false, true)
                    DeleteEntity(pedRef)
                end
            end)
            disembarked = disembarked + 1
        elseif DoesEntityExist(ped) then
            table.insert(remaining, ped)
        end
    end

    boardedPassengers = remaining
    return disembarked
end

-- ── Pay out ticket revenue for this leg ──────────────────
local function PayTicketRevenue(passengerCount)
    if passengerCount <= 0 then return end
    if not ActiveTrainConfig then return end
    local companyId = ActiveTrainConfig.company
    TriggerServerEvent('jrs_railroad:ticketRevenue', companyId, passengerCount)
end

-- ── Handle arrival at a station ──────────────────────────
-- Called automatically when the monitoring thread detects a stop.
local function HandleStationArrival(station)
    if #boardedPassengers == 0 then return end
    if not IsPassengerTrain() then return end

    local onBoard = #boardedPassengers

    -- Disembark some passengers
    local disembarked = ProcessDisembarkation(station)
    if disembarked > 0 then
        Notify(L('passengers_disembarked', disembarked, station.label), 'inform', 6000)
    end

    -- Pay for everyone who completed this leg
    local paying = onBoard  -- count before disembarkation
    if paying > 0 then
        PayTicketRevenue(paying)
        local revenue = math.floor(paying * Config.PassengerSystem.TicketPrice
            * (1 - Config.PassengerSystem.CompanyShare))
        Notify(L('passengers_ticket_pay', revenue, paying), 'success', 7000)
    end

    if #boardedPassengers > 0 then
        Notify(L('passengers_remaining', #boardedPassengers), 'inform', 4000)
    end
end

-- ── "All Aboard" — global so SetupTrainTarget can call it ──
function TriggerAllAboard()
    local cfg = Config.PassengerSystem
    if not cfg.Enabled then return end

    if boardingInProgress then
        Notify(L('passengers_already_boarding'), 'error')
        return
    end
    if not IsPassengerTrain() then
        Notify(L('passengers_need_cars'), 'error')
        return
    end
    local station = GetNearestStoppedStation()
    if not station then
        Notify(L('passengers_not_at_station'), 'error')
        return
    end

    boardingInProgress = true
    Notify(L('passengers_boarding'), 'inform', cfg.BoardingWindowMs)

    CreateThread(function()
        local nearby = FindNearbyPassengers(station.coords)

        -- Shuffle and cap
        local maxBoard = math.random(cfg.MinBoardPerStop, cfg.MaxBoardPerStop)
        local selected = {}
        local pool = {}
        for _, p in ipairs(nearby) do table.insert(pool, p) end

        for i = 1, math.min(maxBoard, #pool) do
            local idx = math.random(1, #pool)
            table.insert(selected, pool[idx])
            table.remove(pool, idx)
        end

        if #selected == 0 then
            Notify(L('passengers_none_found'), 'inform')
            boardingInProgress = false
            return
        end

        -- Walk selected peds to the nearest part of the train (not just engine)
        for _, ped in ipairs(selected) do
            if DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                local target = GetNearestTrainCoords(GetEntityCoords(ped))
                TaskGoToCoordAnyMeans(ped, target.x, target.y, target.z,
                    cfg.BoardWalkSpeed, 0, false, 786603, 0xbf800000)
            end
        end

        -- Wait for boarding window
        Wait(cfg.BoardingWindowMs)

        -- Board any ped that reached any part of the train
        local boarded = 0
        if ActiveTrain and DoesEntityExist(ActiveTrain) then
            for _, ped in ipairs(selected) do
                if DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local nearestPt = GetNearestTrainCoords(GetEntityCoords(ped))
                    local dist = GetDistanceBetween(GetEntityCoords(ped), nearestPt)
                    if dist < cfg.BoardDistance then
                        -- Board: hide ped, keep as mission entity
                        SetEntityVisible(ped, false, false)
                        ClearPedTasksImmediately(ped)
                        table.insert(boardedPassengers, ped)
                        boarded = boarded + 1
                    else
                        -- Didn't make it: release
                        SetEntityAsMissionEntity(ped, false, true)
                        ClearPedTasks(ped)
                    end
                end
            end
        end

        boardingInProgress = false

        if boarded > 0 then
            Notify(L('passengers_boarded', boarded, #boardedPassengers), 'success', 7000)
        else
            Notify(L('passengers_none_found'), 'inform')
        end
    end)
end

-- ── Set up the JRS interaction prompt on the deployed train ────────────────
-- Called from SetupTrainTarget() in train_spawn.lua
function SetupPassengerTarget()
    if not ActiveTrain or not DoesEntityExist(ActiveTrain) then
        DebugPrint('[Passengers] SetupPassengerTarget: no active train')
        return
    end
    if passengerTargetAdded then return end

    local hasPassengerCars = ActiveTrainConfig and ActiveTrainConfig.hasPassengerCars == true
    DebugPrint('[Passengers] SetupPassengerTarget: hasPassengerCars=' .. tostring(hasPassengerCars))

    -- Always register the target; canInteract controls visibility at runtime
    JRS.AddEntityTarget(ActiveTrain, {
        {
            name     = 'railroad_all_aboard',
            label    = L('passengers_all_aboard'),
            icon     = 'fas fa-users',
            distance = 6.0,
            canInteract = function()
                return (ActiveTrainConfig and ActiveTrainConfig.hasPassengerCars == true)
                    and GetNearestStoppedStation() ~= nil
                    and not boardingInProgress
            end,
            onSelect = function()
                TriggerAllAboard()
            end,
        }
    })
    passengerTargetAdded = true
    DebugPrint('[Passengers] All Aboard target registered on train')
end

-- ── Remove target and clean up on train despawn ──────────
-- Called from CleanupActiveTrain() in train_spawn.lua
function CleanupPassengerTarget()
    if ActiveTrain and DoesEntityExist(ActiveTrain) and passengerTargetAdded then
        JRS.RemoveEntityTarget(ActiveTrain, { 'railroad_all_aboard' })
    end
    passengerTargetAdded = false
    boardingInProgress   = false
    stationCooldown      = {}
    lastStation          = nil

    -- Delete all hidden boarded passengers
    for _, ped in ipairs(boardedPassengers) do
        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, false, true)
            DeleteEntity(ped)
        end
    end
    boardedPassengers = {}
    DebugPrint('[Passengers] Passenger system cleaned up')
end

-- ── Station arrival monitoring thread ────────────────────
-- Runs continuously while a train is deployed.
-- Fires HandleStationArrival once per station visit.
CreateThread(function()
    while true do
        Wait(3000)

        if not ActiveTrain or not DoesEntityExist(ActiveTrain)
            or not IsPassengerTrain() then
            lastStation = nil
            Wait(2000)
        else
            local station = GetNearestStoppedStation()
            if station then
                if lastStation ~= station.id and not stationCooldown[station.id] then
                    lastStation = station.id
                    stationCooldown[station.id] = true
                    DebugPrint('[Passengers] Arrived at: ' .. station.label)
                    HandleStationArrival(station)

                    -- Release cooldown after train leaves the station
                    CreateThread(function()
                        while true do
                            Wait(3000)
                            local cur = GetNearestStoppedStation()
                            if not cur or cur.id ~= station.id then
                                stationCooldown[station.id] = false
                                break
                            end
                        end
                    end)
                end
            else
                lastStation = nil
            end
        end
    end
end)

-- ── Cleanup on resource stop ──────────────────────────────
AddEventHandler('onResourceStop', function(r)
    if r == GetCurrentResourceName() then
        CleanupPassengerTarget()
    end
end)
