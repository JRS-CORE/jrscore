---------------------------------------------------------------
-- CALLBACKS
---------------------------------------------------------------
JRS.Callback('jrs_railroad:getCompanySupplies', function(source, companyId)
    return DB.GetCompanySupplies(companyId)
end)

---------------------------------------------------------------
-- OWNER: ADD SUPPLIES FROM INVENTORY
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:addSupply', function(companyId, itemName, quantity)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    -- Verify owner
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= Player.PlayerData.citizenid then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('not_owner_of_company'), type = 'error', duration = 5000 })
        return
    end

    quantity = math.floor(tonumber(quantity) or 0)
    if quantity <= 0 or quantity > 1000 then return end

    -- Validate item is a supply item
    local validItem = false
    for _, si in ipairs(Config.SupplyItems) do
        if si.item == itemName then validItem = true break end
    end
    if not validItem then return end

    -- Check player has the item
    local item = Player.Functions.GetItemByName(itemName)
    if not item or item.amount < quantity then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('missing_item_quantity'), type = 'error', duration = 5000 })
        return
    end

    -- Remove from player, add to company stock
    if not Player.Functions.RemoveItem(itemName, quantity) then return end
    TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(itemName), 'remove')
    DB.AddSupplyItem(companyId, itemName, quantity)

    local itemLabel = JRS.ItemDef(itemName) and JRS.ItemDef(itemName).label or itemName
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('supply_added_notify', quantity, itemLabel), type = 'success', duration = 5000 })
end)

---------------------------------------------------------------
-- DRIVER: TAKE SUPPLY (free from company stock)
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:takeSupply', function(companyId, itemName, quantity)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    quantity = math.floor(tonumber(quantity) or 1)
    if quantity <= 0 or quantity > 100 or type(itemName) ~= 'string' then return end

    -- Verify player is approved employee OR owner
    local ownership = DB.GetCompanyOwnership(companyId)
    local isOwner = ownership and ownership.owner_citizenid == citizenid
    local isDriver = false
    if not isOwner then
        local employee = DB.GetEmployeeByIds(companyId, citizenid)
        isDriver = employee and employee.status == 'approved'
    end

    if not isOwner and not isDriver then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('not_authorized'), type = 'error', duration = 5000 })
        return
    end

    -- Check stock
    local supply = DB.GetSupplyItem(companyId, itemName)
    if not supply or supply.quantity < quantity then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('not_enough_stock'), type = 'error', duration = 5000 })
        return
    end

    -- Take from stock (atomic), give to player; put it back if they can't carry it
    if not DB.TakeSupplyItem(companyId, itemName, quantity) then return end
    if not Player.Functions.AddItem(itemName, quantity) then
        DB.AddSupplyItem(companyId, itemName, quantity)
        return
    end
    TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(itemName), 'add')

    local itemLabel = JRS.ItemDef(itemName) and JRS.ItemDef(itemName).label or itemName
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('supply_taken_notify', quantity, itemLabel), type = 'success', duration = 5000 })
end)
