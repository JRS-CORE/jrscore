-- jrs_railroad | server: tickets for riding a train
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local paid = {}                       -- source -> true once this ride's ticket has paid the company
local lastAsk = {}                    -- source -> game timer of the last ticket check

AddEventHandler('playerDropped', function()
    paid[source], lastAsk[source] = nil, nil
end)

local function itemBox(src, direction)
    TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(Config.TicketItem), direction, 1)
end

-- answers 'has_ticket', 'bought_ticket' or 'no_ticket'
JRS.CreateCallback('jrs_traintickets:server:useTicket', function(src, cb, companyId)
    local player = JRS.Player(src)

    -- asked again within two seconds: repeat the earlier answer instead of charging twice
    local now = GetGameTimer()
    if lastAsk[src] and now - lastAsk[src] < 2000 then
        return cb(paid[src] and 'has_ticket' or 'no_ticket')
    end
    lastAsk[src] = now

    if companyId ~= nil and not Config.Companies[companyId] then companyId = nil end
    if not player then return cb('no_ticket') end

    -- the owner of the company rides free
    if companyId then
        local ownership = DB.GetCompanyOwnership(companyId)
        if ownership and ownership.owner_citizenid == player.PlayerData.citizenid then return cb('has_ticket') end
    end

    local ticket = player.Functions.GetItemByName(Config.TicketItem)
    if ticket and ticket.amount and ticket.amount > 0 then
        if companyId and not paid[src] then DB.AddToCashRegister(companyId, Config.TicketPrice) end
        paid[src] = true
        return cb('has_ticket')
    end

    -- no ticket: buy one at the marked-up price
    if (player.PlayerData.money['cash'] or 0) < Config.MarkupPrice then return cb('no_ticket') end
    if not player.Functions.RemoveMoney('cash', Config.MarkupPrice, 'train-ticket') then return cb('no_ticket') end

    player.Functions.AddItem(Config.TicketItem, 1)
    paid[src] = true
    itemBox(src, 'add')
    if companyId then DB.AddToCashRegister(companyId, Config.MarkupPrice) end
    cb('bought_ticket')
end)

-- the ticket is used up when the ride ends
RegisterNetEvent('jrs_traintickets:server:removeTicket', function()
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    local ticket = player.Functions.GetItemByName(Config.TicketItem)
    if not (ticket and ticket.amount and ticket.amount > 0) then return end

    player.Functions.RemoveItem(Config.TicketItem, 1)
    paid[src] = nil
    itemBox(src, 'remove')
    TriggerClientEvent('jrs_traintickets:client:ticketRemoved', src)
end)
