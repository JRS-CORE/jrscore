local ticketCredited = {} -- [src] = true once this ride's ticket paid the company
local lastCheck = {}

AddEventHandler('playerDropped', function()
    ticketCredited[source] = nil
    lastCheck[source] = nil
end)

JRS.CreateCallback('jrs_traintickets:server:useTicket', function(source, cb, companyId)
    local src = source
    local Player = JRS.Player(src)

    local now = GetGameTimer()
    if lastCheck[src] and now - lastCheck[src] < 2000 then
        cb(ticketCredited[src] and 'has_ticket' or 'no_ticket')
        return
    end
    lastCheck[src] = now
    if companyId ~= nil and not Config.Companies[companyId] then companyId = nil end

    if not Player then
        cb('no_ticket')
        return
    end

    -- Company owners ride for free
    if companyId then
        local ownership = DB.GetCompanyOwnership(companyId)
        if ownership and ownership.owner_citizenid == Player.PlayerData.citizenid then
            cb('has_ticket')
            return
        end
    end

   
    local ticket = Player.Functions.GetItemByName(Config.TicketItem)

    if ticket and ticket.amount and ticket.amount > 0 then
       
        if companyId and not ticketCredited[src] then
            DB.AddToCashRegister(companyId, Config.TicketPrice)
        end
        ticketCredited[src] = true

        cb('has_ticket')
    else
        
        local cash = Player.PlayerData.money['cash'] or 0

        if cash >= Config.MarkupPrice then
           
            if not Player.Functions.RemoveMoney('cash', Config.MarkupPrice, 'train-ticket') then
                cb('no_ticket')
                return
            end
            Player.Functions.AddItem(Config.TicketItem, 1)
            ticketCredited[src] = true
            TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(Config.TicketItem), 'add', 1)

            if companyId then
                DB.AddToCashRegister(companyId, Config.MarkupPrice)
            end
           
            cb('bought_ticket')
        else
            
           
            cb('no_ticket')
        end
    end
end)


RegisterNetEvent('jrs_traintickets:server:removeTicket', function()
    local src = source
    local Player = JRS.Player(src)

    if not Player then return end

    local ticket = Player.Functions.GetItemByName(Config.TicketItem)

    if ticket and ticket.amount and ticket.amount > 0 then
        Player.Functions.RemoveItem(Config.TicketItem, 1)
        ticketCredited[src] = nil
        TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(Config.TicketItem), 'remove', 1)
        TriggerClientEvent('jrs_traintickets:client:ticketRemoved', src)
        
    end
end)





AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
end)

