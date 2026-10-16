-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: the trains that run by themselves
-- The server picks one client to create them. Each one follows a route: it slows down near a stop, waits
-- there and drives on, and sets the junctions of its route as it passes them.

local ambientTrains = {}
local spawned = false

-- per route: its stops, the junctions to set, the two speeds (near a stop / between stops) and whether it whistles
local function routes()
    return {
        trainRouteOne = { stops = Config.RouteOneTrainStops, switches = Config.RouteOneTrainSwitches, near = 5.0, free = 15.0, whistle = true },
        tramRouteOne = { stops = Config.RouteOneTramStops, switches = Config.RouteOneTramSwitches, near = 1.0, free = 2.0 },
        trainRouteThree = { stops = Config.RouteThreeTrainStops, switches = Config.RouteThreeTrainSwitches, near = 8.0, free = 12.0 },
    }
end

local function createTrain(hash, at, direction)
    SetRandomTrains(false)
    for car = 0, GetNumCarsFromTrainConfig(hash) - 1 do
        local model = GetTrainModelFromTrainConfigByCarIndex(hash, car)
        while not HasModelLoaded(model) do
            RequestModel(model, 1)
            Wait(100)
        end
    end
    local train = CreateMissionTrain(hash, at.x, at.y, at.z, direction)
    SetTrainSpeed(train, 0.0)
    SetModelAsNoLongerNeeded(train)
    NetworkRegisterEntityAsNetworked(train)
    return train
end

function SpawnAmbientRouteTrains()
    if spawned then return end
    for _, setup in ipairs(Config.TrainSetup) do
        local train = createTrain(setup.trainhash, setup.startcoords, setup.reversed or false)
        SetTransportConfigFlag(train, 0, 1)
        TriggerEvent('jrs_railroad:ambient:trackswithches', train, setup.route)
        TriggerEvent('jrs_railroad:ambient:startroute', train, setup.route, setup.trainname)
        ambientTrains[#ambientTrains + 1] = train
    end
    spawned = true
end

function DespawnAmbientRouteTrains()
    for _, train in ipairs(ambientTrains) do
        if DoesEntityExist(train) then DeleteEntity(train) end
    end
    ambientTrains, spawned = {}, false
end

RegisterNetEvent('jrs_railroad:setAmbientState', function(active)
    if active and not spawned then
        if JRS.Await('jrs_railroad:shouldSpawnAmbient') then SpawnAmbientRouteTrains() end
    elseif not active and spawned then
        DespawnAmbientRouteTrains()
        TriggerServerEvent('jrs_railroad:ambientDespawned')
    end
end)

-- sets the junctions of the route when the train is within 15 m of one
AddEventHandler('jrs_railroad:ambient:trackswithches', function(train, route)
    local switches = routes()[route] and routes()[route].switches
    if not switches then return end

    while DoesEntityExist(train) do
        Wait(100)
        local at = GetEntityCoords(train)
        local here = vector3(at.x, at.y, at.z)
        for _, switch in ipairs(switches) do
            if #(switch.coords - here) < 15 then
                SetTrainTrackJunctionSwitch(switch.trainTrack, switch.junctionIndex, switch.enabled)
                Citizen.InvokeNative(0x3ABFA128F5BF5A70, switch.trainTrack, switch.junctionIndex, switch.enabled)
            end
        end
    end
end)

-- drives one train along its stops
AddEventHandler('jrs_railroad:ambient:startroute', function(train, route)
    local spec = routes()[route]
    if not spec then return end

    while DoesEntityExist(train) do
        Wait(0)
        local at = GetEntityCoords(train)
        local here = vector3(at.x, at.y, at.z)

        for _, stop in ipairs(spec.stops) do
            local away = #(stop.coords - here)
            if away < stop.dst then
                SetTrainCruiseSpeed(train, spec.near)
                Wait(1000)
                if away < stop.dst2 then
                    SetTrainCruiseSpeed(train, 0.0)
                    if spec.whistle then TriggerTrainWhistle(train, 'STOPPED', 1, 0) end
                    Wait(stop.waittime)
                    if spec.whistle then TriggerTrainWhistle(train, 'NEXT_STATION', 1, 0) end
                    SetTrainCruiseSpeed(train, spec.near)
                    Wait(10000)
                end
            elseif away > stop.dst then
                SetTrainCruiseSpeed(train, spec.free)
                Wait(25)
            end
        end
    end
end)

-- ------------------------------------------------------------------ blips for every train in the world

local function blipTrain(vehicle)
    if not IsThisModelATrain(GetEntityModel(vehicle)) then return end
    local cars = Citizen.InvokeNative(0x60B7D1DCC312697D, vehicle)
    if GetTrainCarriage(vehicle, cars - 1) ~= 0 and not Citizen.InvokeNative(0x9FA00E2FC134A9D0, vehicle) then
        local blip = Citizen.InvokeNative(0x23f74c2fda6e7c61, -399496385, vehicle)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, 'Train')
    end
end

-- RedM has no FindFirstVehicle: walk the vehicle pool
CreateThread(function()
    while true do
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do blipTrain(vehicle) end
        Wait(10000)
    end
end)

-- the name of the stop closest to a position, or 'En Route' when none is within 200 m
function FindNearestName(at)
    local best, bestAway = 'Unknown', math.huge
    for _, spec in pairs(routes()) do
        for _, stop in ipairs(spec.stops) do
            local away = #(stop.coords - at)
            if away < bestAway then best, bestAway = stop.name, away end
        end
    end
    return bestAway > 200 and 'En Route' or best
end

RegisterCommand('trainpos', function()
    local options = {}
    local function add(entity, title, icon)
        if entity and DoesEntityExist(entity) then
            options[#options + 1] = { title = title, description = FindNearestName(GetEntityCoords(entity)), icon = icon }
        end
    end

    add(ActiveTrain, ActiveTrainConfig and ActiveTrainConfig.label or 'Active Train', 'train')
    for _, train in ipairs(ambientTrains) do add(train, L('menu_route_train'), 'train') end
    add(ambientTram, L('menu_saint_denis_trolley'), 'tram')

    if #options == 0 then return Notify(L('no_trains_found'), 'error') end
    JRS.RegisterContext({ id = 'trainpos_menu', title = L('menu_train_locations'), options = options })
    JRS.ShowContext('trainpos_menu')
end, false)

-- /setjunction <track> <index> <0|1>   (for finding out which junction does what)
RegisterCommand('setjunction', function(_, args)
    if #args < 3 then
        print('Usage: /setjunction <trackName> <junctionIndex> <0|1>')
        return print('Example: /setjunction TRAINS_OLD_WEST03 2 1')
    end
    local track, index, on = joaat(args[1]), tonumber(args[2]), tonumber(args[3]) == 1
    SetTrainTrackJunctionSwitch(track, index, on)
    Citizen.InvokeNative(0x3ABFA128F5BF5A70, track, index, on and 1 or 0)
    print(('Set junction: hash=%d (%s), idx=%d, enabled=%s'):format(track, args[1], index, tostring(on)))
end, false)
