

local isOnTrain = false
local ticketChecked = false


CreateThread(function()
    
end)


CreateThread(function()

    

    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local onTrain = IsPedInAnyTrain(ped)

        if onTrain == 1 or onTrain == true then
            if not ticketChecked then
                
                ticketChecked = true
                isOnTrain = true
                CheckTicket()
            end
        else
            if isOnTrain then
               
                TriggerServerEvent('jrs_traintickets:server:removeTicket')
                ResetState()
            end
        end

        Wait(sleep)
    end
end)


function GetNearestStationCompany()
    local ped = PlayerPedId()
    local train = GetVehiclePedIsIn(ped)

    -- If on a company-owned train, use that company
    if train and DoesEntityExist(train) and ActiveTrain and train == ActiveTrain and ActiveTrainConfig then
        return ActiveTrainConfig.company
    end

    -- Otherwise fall back to nearest station
    local pcoords = GetEntityCoords(ped)
    local nearestDist = math.huge
    local nearestCompany = nil
    for _, station in ipairs(Config.Stations) do
        local dist = GetDistanceBetween(pcoords, station.coords)
        if dist < nearestDist then
            nearestDist = dist
            nearestCompany = station.company
        end
    end
    return nearestCompany
end

function CheckTicket()
    local companyId = GetNearestStationCompany()

    JRS.TriggerCallback('jrs_traintickets:server:useTicket', function(result)
       

        if result == 'has_ticket' then
            JRS.NotifyT({
                title = L('ticket_valid_title'),
                description = L('ticket_valid_desc'),
                type = 'success',
                position = 'top-right',
                duration = 5000,
            })

        elseif result == 'bought_ticket' then
            JRS.NotifyT({
                title = L('ticket_purchased_title'),
                description = L('ticket_purchased_desc', string.format('%.2f', Config.MarkupPrice), string.format('%.2f', Config.TicketPrice)),
                type = 'warning',
                position = 'top-right',
                duration = 7000,
            })

        elseif result == 'no_ticket' then
            JRS.NotifyT({
                title = L('no_ticket_title'),
                description = L('no_ticket_desc', string.format('%.2f', Config.MarkupPrice)),
                type = 'error',
                position = 'top-right',
                duration = 5000,
            })

            KickOffTrain()
        end
    end, companyId)
end


function KickOffTrain()
    CreateThread(function()
        Wait(2000)

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        ClearPedTasksImmediately(ped)
        SetEntityCoords(ped, coords.x + 10.0, coords.y + 10.0, coords.z, false, false, false, false)
        Wait(500)
        PlaceEntityOnGroundProperly(ped)

        ResetState()
    end)
end


RegisterNetEvent('jrs_traintickets:client:ticketRemoved', function()
    JRS.NotifyT({
        title = L('journey_complete_title'),
        description = L('journey_complete_desc'),
        type = 'success',
        position = 'top-right',
        duration = 5000,
    })
end)

function ResetState()
    isOnTrain = false
    ticketChecked = false
end


AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    ResetState()
end)

