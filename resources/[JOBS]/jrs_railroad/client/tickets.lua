-- jrs_railroad | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_railroad | client: train tickets
-- Getting on a train checks for a ticket: a valid one is fine, otherwise the server may sell one at a markup,
-- and if the player cannot pay they are put off the train. The ticket is taken back when they leave.

local onTrain, checked = false, false

local function resetState() onTrain, checked = false, false end

local function say(titleKey, text, kind, ms)
    JRS.NotifyT({ title = L(titleKey), description = text, type = kind, position = 'top-right', duration = ms })
end

-- the company whose ticket is needed: the one that owns our train, else the nearest station's
function GetNearestStationCompany()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped)
    if vehicle and DoesEntityExist(vehicle) and ActiveTrain and vehicle == ActiveTrain and ActiveTrainConfig then
        return ActiveTrainConfig.company
    end

    local here, best, bestAway = GetEntityCoords(ped), nil, math.huge
    for _, station in ipairs(Config.Stations) do
        local away = GetDistanceBetween(here, station.coords)
        if away < bestAway then best, bestAway = station.company, away end
    end
    return best
end

function KickOffTrain()
    CreateThread(function()
        Wait(2000)
        local ped = PlayerPedId()
        local at = GetEntityCoords(ped)
        ClearPedTasksImmediately(ped)
        SetEntityCoords(ped, at.x + 10.0, at.y + 10.0, at.z, false, false, false, false)
        Wait(500)
        PlaceEntityOnGroundProperly(ped)
        resetState()
    end)
end

local answers = {
    has_ticket = function() say('ticket_valid_title', L('ticket_valid_desc'), 'success', 5000) end,
    bought_ticket = function()
        say('ticket_purchased_title', L('ticket_purchased_desc', ('%.2f'):format(Config.MarkupPrice), ('%.2f'):format(Config.TicketPrice)), 'warning', 7000)
    end,
    no_ticket = function()
        say('no_ticket_title', L('no_ticket_desc', ('%.2f'):format(Config.MarkupPrice)), 'error', 5000)
        KickOffTrain()
    end,
}

function CheckTicket()
    JRS.TriggerCallback('jrs_traintickets:server:useTicket', function(result)
        local react = answers[result]
        if react then react() end
    end, GetNearestStationCompany())
end

CreateThread(function()
    while true do
        local riding = IsPedInAnyTrain(PlayerPedId())
        if riding == 1 or riding == true then
            if not checked then
                checked, onTrain = true, true
                CheckTicket()
            end
        elseif onTrain then
            TriggerServerEvent('jrs_traintickets:server:removeTicket')
            resetState()
        end
        Wait(500)
    end
end)

RegisterNetEvent('jrs_traintickets:client:ticketRemoved', function()
    say('journey_complete_title', L('journey_complete_desc'), 'success', 5000)
end)

function ResetState() resetState() end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then resetState() end
end)
