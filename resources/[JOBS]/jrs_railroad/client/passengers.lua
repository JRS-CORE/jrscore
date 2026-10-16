-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: passengers
-- Runs next to normal driving. At a stop the driver calls "All Aboard": ambient people nearby walk to the
-- train and board (they are hidden while they ride). At later stops some of them get off again, and every
-- passenger pays for the leg they rode.

local boarded = {}              -- hidden peds that ride the train
local boarding = false
local targeted = false
local cooldown = {}             -- station id -> true while the train still stands at that stop
local lastStation

local function cfg() return Config.PassengerSystem end
local function trainAlive() return ActiveTrain and DoesEntityExist(ActiveTrain) end
local function isPassengerTrain() return ActiveTrainConfig and ActiveTrainConfig.hasPassengerCars == true end

-- the station the train is standing at (slow enough, close enough), or nil; global because the train menu asks it too
function GetNearestStoppedStation()
    if not trainAlive() or GetEntitySpeed(ActiveTrain) > cfg().TrainStopSpeed then return nil end
    local at = GetEntityCoords(ActiveTrain)
    for _, station in ipairs(Config.Stations) do
        if GetDistanceBetween(at, station.coords) < cfg().StationStopRadius then return station end
    end
end

-- the point of the train (engine or any carriage) closest to `from`
local function nearestPartOfTrain(from)
    if not trainAlive() then return from end
    local best = GetEntityCoords(ActiveTrain)
    local bestAway = GetDistanceBetween(from, best)
    for i = 1, (Citizen.InvokeNative(0x60B7D1DCC312697D, ActiveTrain) or 1) - 1 do
        local car = GetTrainCarriage(ActiveTrain, i)
        if car and DoesEntityExist(car) then
            local at = GetEntityCoords(car)
            local away = GetDistanceBetween(from, at)
            if away < bestAway then best, bestAway = at, away end
        end
    end
    return best
end

-- people within the search radius of the station; seated NPCs count too (benches make peds "in a vehicle")
local function peopleAround(at)
    local found = {}
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and ped ~= PlayerPedId() and not IsEntityDead(ped) and not IsPedAPlayer(ped)
            and GetDistanceBetween(GetEntityCoords(ped), at) < cfg().SearchRadius then
            found[#found + 1] = ped
        end
    end
    DebugPrint('[Passengers] Found ' .. #found .. ' candidate peds within ' .. cfg().SearchRadius .. 'm')
    return found
end

-- ------------------------------------------------------------------ getting off

-- some of the passengers get off here: they appear on the platform, walk off and are removed
local function letSomeOff(station)
    local off, staying = 0, {}
    for _, ped in ipairs(boarded) do
        local mayLeave = (#boarded - off) > cfg().MinBoardedToKeep
        if math.random(100) <= cfg().DisembarkChance and mayLeave and DoesEntityExist(ped) then
            SetEntityCoords(ped, station.coords.x + math.random(-6, 6), station.coords.y + math.random(-6, 6), station.coords.z, false, false, false, false)
            SetEntityVisible(ped, true, false)
            PlaceEntityOnGroundProperly(ped)

            local at = GetEntityCoords(ped)
            TaskGoToCoordAnyMeans(ped, at.x + math.random(-20, 20), at.y + math.random(-20, 20), at.z, 1.0, 0, false, 786603, 0xbf800000)
            SetTimeout(12000, function()
                if DoesEntityExist(ped) then
                    SetEntityAsMissionEntity(ped, false, true)
                    DeleteEntity(ped)
                end
            end)
            off = off + 1
        elseif DoesEntityExist(ped) then
            staying[#staying + 1] = ped
        end
    end
    boarded = staying
    return off
end

local function arrived(station)
    if #boarded == 0 or not isPassengerTrain() then return end

    local riding = #boarded
    local left = letSomeOff(station)
    if left > 0 then Notify(L('passengers_disembarked', left, station.label), 'inform', 6000) end

    -- everybody who rode this leg pays, including those who just got off
    TriggerServerEvent('jrs_railroad:ticketRevenue', ActiveTrainConfig.company, riding)
    local revenue = math.floor(riding * cfg().TicketPrice * (1 - cfg().CompanyShare))
    Notify(L('passengers_ticket_pay', revenue, riding), 'success', 7000)

    if #boarded > 0 then Notify(L('passengers_remaining', #boarded), 'inform', 4000) end
end

-- ------------------------------------------------------------------ getting on

-- up to a random number of the nearby people, picked at random
local function pickPassengers(people)
    local pick = {}
    for _ = 1, math.min(math.random(cfg().MinBoardPerStop, cfg().MaxBoardPerStop), #people) do
        pick[#pick + 1] = table.remove(people, math.random(1, #people))
    end
    return pick
end

function TriggerAllAboard()
    if not cfg().Enabled then return end
    if boarding then return Notify(L('passengers_already_boarding'), 'error') end
    if not isPassengerTrain() then return Notify(L('passengers_need_cars'), 'error') end

    local station = GetNearestStoppedStation()
    if not station then return Notify(L('passengers_not_at_station'), 'error') end

    boarding = true
    Notify(L('passengers_boarding'), 'inform', cfg().BoardingWindowMs)

    CreateThread(function()
        local pick = pickPassengers(peopleAround(station.coords))
        if #pick == 0 then
            Notify(L('passengers_none_found'), 'inform')
            boarding = false
            return
        end

        for _, ped in ipairs(pick) do
            if DoesEntityExist(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                local to = nearestPartOfTrain(GetEntityCoords(ped))
                TaskGoToCoordAnyMeans(ped, to.x, to.y, to.z, cfg().BoardWalkSpeed, 0, false, 786603, 0xbf800000)
            end
        end

        Wait(cfg().BoardingWindowMs)

        -- whoever reached the train boards (and hides), the others are let go
        local count = 0
        if trainAlive() then
            for _, ped in ipairs(pick) do
                if DoesEntityExist(ped) and not IsEntityDead(ped) then
                    local there = GetDistanceBetween(GetEntityCoords(ped), nearestPartOfTrain(GetEntityCoords(ped)))
                    if there < cfg().BoardDistance then
                        SetEntityVisible(ped, false, false)
                        ClearPedTasksImmediately(ped)
                        boarded[#boarded + 1] = ped
                        count = count + 1
                    else
                        SetEntityAsMissionEntity(ped, false, true)
                        ClearPedTasks(ped)
                    end
                end
            end
        end

        boarding = false
        if count > 0 then Notify(L('passengers_boarded', count, #boarded), 'success', 7000)
        else Notify(L('passengers_none_found'), 'inform') end
    end)
end

-- ------------------------------------------------------------------ the look-at option on the train

-- called from SetupTrainTarget in train_spawn.lua
function SetupPassengerTarget()
    if not trainAlive() then return DebugPrint('[Passengers] SetupPassengerTarget: no active train') end
    if targeted then return end

    JRS.AddEntityTarget(ActiveTrain, { {
        name = 'railroad_all_aboard', label = L('passengers_all_aboard'), icon = 'fas fa-users', distance = 6.0,
        canInteract = function() return isPassengerTrain() and GetNearestStoppedStation() ~= nil and not boarding end,
        onSelect = TriggerAllAboard,
    } })
    targeted = true
end

-- called from CleanupActiveTrain: removes the option and every hidden passenger
function CleanupPassengerTarget()
    if trainAlive() and targeted then JRS.RemoveEntityTarget(ActiveTrain, { 'railroad_all_aboard' }) end
    targeted, boarding, cooldown, lastStation = false, false, {}, nil

    for _, ped in ipairs(boarded) do
        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, false, true)
            DeleteEntity(ped)
        end
    end
    boarded = {}
end

-- once per stop: when the train stands at a station that is not the last one handled
CreateThread(function()
    while true do
        Wait(3000)
        if not trainAlive() or not isPassengerTrain() then
            lastStation = nil
            Wait(2000)
        else
            local station = GetNearestStoppedStation()
            if not station then
                lastStation = nil
            elseif lastStation ~= station.id and not cooldown[station.id] then
                lastStation, cooldown[station.id] = station.id, true
                DebugPrint('[Passengers] Arrived at: ' .. station.label)
                arrived(station)

                -- the stop counts as done once the train has left
                CreateThread(function()
                    repeat
                        Wait(3000)
                        local now = GetNearestStoppedStation()
                    until not now or now.id ~= station.id
                    cooldown[station.id] = false
                end)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then CleanupPassengerTarget() end
end)
