local ambientTrains = {}
local ambientSpawned = false

local function SpawnTrain(trainid, route, trainhash, startcoords, direction)
    SetRandomTrains(false)
    local trainWagons = GetNumCarsFromTrainConfig(trainhash)
    for wagonIndex = 0, trainWagons - 1 do
        local trainWagonModel = GetTrainModelFromTrainConfigByCarIndex(trainhash, wagonIndex)
        while not HasModelLoaded(trainWagonModel) do
            RequestModel(trainWagonModel, 1)
            Wait(100)
        end
    end
    local train = CreateMissionTrain(trainhash, startcoords.x, startcoords.y, startcoords.z, direction)
    SetTrainSpeed(train, 0.0)
    SetModelAsNoLongerNeeded(train)
    NetworkRegisterEntityAsNetworked(train)
    return train
end


function SpawnAmbientRouteTrains()
    if ambientSpawned then return end
    for k, v in ipairs(Config.TrainSetup) do
        local train = SpawnTrain(v.trainid, v.route, v.trainhash, v.startcoords, v.reversed or false)
        SetTransportConfigFlag(train, 0, 1)
        TriggerEvent('jrs_railroad:ambient:trackswithches', train, v.route)
        TriggerEvent('jrs_railroad:ambient:startroute', train, v.route, v.trainname)
        table.insert(ambientTrains, train)
    end
    ambientSpawned = true
end

function DespawnAmbientRouteTrains()
    for _, train in ipairs(ambientTrains) do
        if DoesEntityExist(train) then
            DeleteEntity(train)
        end
    end
    ambientTrains = {}
    ambientSpawned = false
end

RegisterNetEvent('jrs_railroad:setAmbientState', function(active)
    if active and not ambientSpawned then
        local shouldSpawn = JRS.Await('jrs_railroad:shouldSpawnAmbient')
        if shouldSpawn then
            SpawnAmbientRouteTrains()
        end
    elseif not active and ambientSpawned then
        DespawnAmbientRouteTrains()
        TriggerServerEvent('jrs_railroad:ambientDespawned')
    end
end)


AddEventHandler('jrs_railroad:ambient:trackswithches', function(train, route)

    while true do
        Wait(100)
        if not train or not DoesEntityExist(train) then return end
        local coords = GetEntityCoords(train)
        local traincoords = vector3(coords.x, coords.y, coords.z)
        
        if train ~= nil and route == 'trainRouteOne' then
           
            for i = 1, #Config.RouteOneTrainSwitches do
                local switchdist = #(Config.RouteOneTrainSwitches[i].coords - traincoords)
                if switchdist < 15 then
                    SetTrainTrackJunctionSwitch(Config.RouteOneTrainSwitches[i].trainTrack, Config.RouteOneTrainSwitches[i].junctionIndex, Config.RouteOneTrainSwitches[i].enabled)
                    Citizen.InvokeNative(0x3ABFA128F5BF5A70, Config.RouteOneTrainSwitches[i].trainTrack, Config.RouteOneTrainSwitches[i].junctionIndex, Config.RouteOneTrainSwitches[i].enabled)
                end
            end
        end
        
        if train ~= nil and route == 'tramRouteOne' then
            
            for i = 1, #Config.RouteOneTramSwitches do
                local switchdist = #(Config.RouteOneTramSwitches[i].coords - traincoords)
                if switchdist < 15 then
                    SetTrainTrackJunctionSwitch(Config.RouteOneTramSwitches[i].trainTrack, Config.RouteOneTramSwitches[i].junctionIndex, Config.RouteOneTramSwitches[i].enabled)
                    Citizen.InvokeNative(0x3ABFA128F5BF5A70, Config.RouteOneTramSwitches[i].trainTrack, Config.RouteOneTramSwitches[i].junctionIndex, Config.RouteOneTramSwitches[i].enabled)
                end
            end
        end
        
        if train ~= nil and route == 'trainRouteThree' then
            for i = 1, #Config.RouteThreeTrainSwitches do
                local switchdist = #(Config.RouteThreeTrainSwitches[i].coords - traincoords)
                if switchdist < 15 then
                    SetTrainTrackJunctionSwitch(Config.RouteThreeTrainSwitches[i].trainTrack, Config.RouteThreeTrainSwitches[i].junctionIndex, Config.RouteThreeTrainSwitches[i].enabled)
                    Citizen.InvokeNative(0x3ABFA128F5BF5A70, Config.RouteThreeTrainSwitches[i].trainTrack, Config.RouteThreeTrainSwitches[i].junctionIndex, Config.RouteThreeTrainSwitches[i].enabled)
                end
            end
        end
    end

end)


AddEventHandler('jrs_railroad:ambient:startroute', function(train, route, trainname)

    while true do
        Wait(0)
        if not train or not DoesEntityExist(train) then return end
        local coords = GetEntityCoords(train)
        local traincoords = vector3(coords.x, coords.y, coords.z)
        if train ~= nil and route == 'trainRouteOne' then
            
            for i = 1, #Config.RouteOneTrainStops do
                local distance = #(Config.RouteOneTrainStops[i].coords - traincoords)
                local stopspeed = 0.0
                local cruisespeed = 5.0
                local fullspeed = 15.0
                if distance < Config.RouteOneTrainStops[i].dst then
                    SetTrainCruiseSpeed(train, cruisespeed)
                    Wait(1000)
                    if distance < Config.RouteOneTrainStops[i].dst2 then
                        SetTrainCruiseSpeed(train, stopspeed)
                        TriggerTrainWhistle(train, "STOPPED", 1, 0)
                        if Config.Debug then
                            
                        end
                        Wait(Config.RouteOneTrainStops[i].waittime)
                        TriggerTrainWhistle(train, "NEXT_STATION", 1, 0)
                        if Config.Debug then
                            
                        end
                        SetTrainCruiseSpeed(train, cruisespeed)
                        Wait(10000)
                    end
                elseif distance > Config.RouteOneTrainStops[i].dst then
                    SetTrainCruiseSpeed(train, fullspeed)
                    Wait(25)
                end
            end
        end
        if train ~= nil and route == 'tramRouteOne' then
           
            for i = 1, #Config.RouteOneTramStops do
                local distance = #(Config.RouteOneTramStops[i].coords - traincoords)
                local stopspeed = 0.0
                local cruisespeed = 1.0
                local fullspeed = 2.0
                if distance < Config.RouteOneTramStops[i].dst then
                    SetTrainCruiseSpeed(train, cruisespeed)
                    Wait(1000)
                    if distance < Config.RouteOneTramStops[i].dst2 then
                        SetTrainCruiseSpeed(train, stopspeed)
                        if Config.Debug then
                            
                        end
                        Wait(Config.RouteOneTramStops[i].waittime)
                        if Config.Debug then
                           
                        end
                        SetTrainCruiseSpeed(train, cruisespeed)
                        Wait(10000)
                    end
                elseif distance > Config.RouteOneTramStops[i].dst then
                    SetTrainCruiseSpeed(train, fullspeed)
                    Wait(25)
                end
            end
        end
        if train ~= nil and route == 'trainRouteThree' then
            for i = 1, #Config.RouteThreeTrainStops do
                local distance = #(Config.RouteThreeTrainStops[i].coords - traincoords)
                local stopspeed = 0.0
                local cruisespeed = 8.0
                local fullspeed = 12.0
                if distance < Config.RouteThreeTrainStops[i].dst then
                    SetTrainCruiseSpeed(train, cruisespeed)
                    Wait(1000)
                    if distance < Config.RouteThreeTrainStops[i].dst2 then
                        SetTrainCruiseSpeed(train, stopspeed)
                        Wait(Config.RouteThreeTrainStops[i].waittime)
                        SetTrainCruiseSpeed(train, cruisespeed)
                        Wait(10000)
                    end
                elseif distance > Config.RouteThreeTrainStops[i].dst then
                    SetTrainCruiseSpeed(train, fullspeed)
                    Wait(25)
                end
            end
        end
    end
    
end)

-------------------------------------------------------------------------------
-- setup train blips
-------------------------------------------------------------------------------
function trainChecker(train)
    if IsThisModelATrain(GetEntityModel(train)) then
        local trainTrailerNumber = Citizen.InvokeNative(0x60B7D1DCC312697D, train)
        local isTrainIsReal = GetTrainCarriage(train,trainTrailerNumber-1)
        if isTrainIsReal ~= 0 then
            if not Citizen.InvokeNative(0x9FA00E2FC134A9D0, train) then
                local createdBlip = addBlipToTrain(-399496385, train, "Train")
                if Config.Debug then
                   
                end
            end
        end
    end
end

function addBlipToTrain(blipType,train,blipText)
    local blip = Citizen.InvokeNative(0x23f74c2fda6e7c61, blipType, train)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, blipText)
    return blip
end

-- RedM has no FindFirstVehicle / FindNextVehicle: walk the vehicle pool instead
function getTrains()
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        trainChecker(veh)
    end
end

Citizen.CreateThread(function()
    while true do
        getTrains()
        Wait(10000)
    end
end)

function FindNearestName(coords)
    local nearestDist = math.huge
    local nearestName = 'Unknown'
    for _, stop in ipairs(Config.RouteOneTrainStops) do
        local dist = #(stop.coords - coords)
        if dist < nearestDist then
            nearestDist = dist
            nearestName = stop.name
        end
    end
    for _, stop in ipairs(Config.RouteOneTramStops) do
        local dist = #(stop.coords - coords)
        if dist < nearestDist then
            nearestDist = dist
            nearestName = stop.name
        end
    end
    for _, stop in ipairs(Config.RouteThreeTrainStops) do
        local dist = #(stop.coords - coords)
        if dist < nearestDist then
            nearestDist = dist
            nearestName = stop.name
        end
    end
    if nearestDist > 200 then
        nearestName = 'En Route'
    end
    return nearestName
end

RegisterCommand('trainpos', function()
    local options = {}

    if ActiveTrain and DoesEntityExist(ActiveTrain) then
        local coords = GetEntityCoords(ActiveTrain)
        local label = ActiveTrainConfig and ActiveTrainConfig.label or 'Active Train'
        table.insert(options, { title = label, description = FindNearestName(coords), icon = 'train' })
    end

    for _, train in ipairs(ambientTrains) do
        if DoesEntityExist(train) then
            local coords = GetEntityCoords(train)
            table.insert(options, { title = L('menu_route_train'), description = FindNearestName(coords), icon = 'train' })
        end
    end

    if ambientTram and DoesEntityExist(ambientTram) then
        local coords = GetEntityCoords(ambientTram)
        table.insert(options, { title = L('menu_saint_denis_trolley'), description = FindNearestName(coords), icon = 'tram' })
    end

    if #options == 0 then
        Notify(L('no_trains_found'), 'error')
        return
    end

    JRS.RegisterContext({ id = 'trainpos_menu', title = L('menu_train_locations'), options = options })
    JRS.ShowContext('trainpos_menu')
end, false)

RegisterCommand('setjunction', function(source, args)
    if #args < 3 then
        print('Usage: /setjunction <trackName> <junctionIndex> <0|1>')
        print('Example: /setjunction TRAINS_OLD_WEST03 2 1')
        return
    end
    local hash = joaat(args[1])
    local idx = tonumber(args[2])
    local enabled = tonumber(args[3]) == 1
    SetTrainTrackJunctionSwitch(hash, idx, enabled)
    Citizen.InvokeNative(0x3ABFA128F5BF5A70, hash, idx, enabled and 1 or 0)
    print(string.format('Set junction: hash=%d (%s), idx=%d, enabled=%s', hash, args[1], idx, tostring(enabled)))
end, false)