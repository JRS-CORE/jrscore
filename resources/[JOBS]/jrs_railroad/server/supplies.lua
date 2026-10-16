-- jrs_railroad | server: the company's stock of supplies
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

JRS.Callback('jrs_railroad:getCompanySupplies', function(_, companyId) return DB.GetCompanySupplies(companyId) end)

local function isSupplyItem(name)
    for _, entry in ipairs(Config.SupplyItems) do
        if entry.item == name then return true end
    end
    return false
end

local function labelOf(item)
    local def = JRS.ItemDef(item)
    return def and def.label or item
end

-- the owner puts items from their bag into the stock
RegisterNetEvent('jrs_railroad:addSupply', function(companyId, item, quantity)
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= player.PlayerData.citizenid then
        return Say(src, L('not_owner_of_company'), 'error')
    end

    quantity = math.floor(tonumber(quantity) or 0)
    if quantity <= 0 or quantity > 1000 or not isSupplyItem(item) then return end

    local have = player.Functions.GetItemByName(item)
    if not have or have.amount < quantity then return Say(src, L('missing_item_quantity'), 'error') end

    if not player.Functions.RemoveItem(item, quantity) then return end
    TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(item), 'remove')
    DB.AddSupplyItem(companyId, item, quantity)
    Say(src, L('supply_added_notify', quantity, labelOf(item)), 'success')
end)

-- the owner and the drivers take items out for free
RegisterNetEvent('jrs_railroad:takeSupply', function(companyId, item, quantity)
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    quantity = math.floor(tonumber(quantity) or 1)
    if quantity <= 0 or quantity > 100 or type(item) ~= 'string' then return end

    if not CompanyRole(companyId, player.PlayerData.citizenid) then return Say(src, L('not_authorized'), 'error') end

    local stock = DB.GetSupplyItem(companyId, item)
    if not stock or stock.quantity < quantity then return Say(src, L('not_enough_stock'), 'error') end

    -- the stock is reduced first (atomically); if the bag cannot take it, it goes back
    if not DB.TakeSupplyItem(companyId, item, quantity) then return end
    if not player.Functions.AddItem(item, quantity) then
        DB.AddSupplyItem(companyId, item, quantity)
        return
    end

    TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(item), 'add')
    Say(src, L('supply_taken_notify', quantity, labelOf(item)), 'success')
end)
