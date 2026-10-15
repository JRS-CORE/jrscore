local upgradeColumns = {
    speed        = 'upgrade_speed',
    fuel_cap     = 'upgrade_fuel_cap',
    water_cap    = 'upgrade_water_cap',
    durability   = 'upgrade_durability',
}

---------------------------------------------------------------
-- CALLBACKS
---------------------------------------------------------------
JRS.Callback('jrs_railroad:getCompanyUpgrades', function(source, companyId)
    return DB.GetCompanyUpgrades(companyId)
end)

JRS.Callback('jrs_railroad:getTrainModelUpgrade', function(source, companyId, trainModel)
    return DB.GetCompanyTrainUpgrade(companyId, trainModel)
end)

---------------------------------------------------------------
-- PURCHASE UPGRADE  (company-level, owner only)
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:purchaseUpgrade', function(companyId, trainModel, upgradeType)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Must be owner OR an approved employee of rank 3+ (Engineer)
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership then return end

    local isOwner = (ownership.owner_citizenid == citizenid)
    if not isOwner then
        local employee = DB.GetEmployeeByIds(companyId, citizenid)
        if not employee or employee.status ~= 'approved' or (employee.rank or 1) < 3 then
            TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, {
                title = L('notify_title'),
                description = L('upgrade_owner_engineer_required'),
                type = 'error', duration = 6000,
            })
            return
        end
    end

    -- Find train config
    local trainConfig = nil
    for _, tc in ipairs(Config.Trains) do
        if tc.model == trainModel and tc.company == companyId then
            trainConfig = tc
            break
        end
    end
    if not trainConfig then return end

    if not trainConfig.upgradeable then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('upgrade_not_upgradeable'), type = 'error', duration = 5000 })
        return
    end

    -- Validate upgrade type
    local upgradeTiers = Config.Upgrades[upgradeType]
    local column = upgradeColumns[upgradeType]
    if not upgradeTiers or not column then return end

    -- Get current company upgrade level for this train model
    local current = DB.GetCompanyTrainUpgrade(companyId, trainModel)
    local currentLevel = current and (current[column] or 0) or 0
    local nextLevel = currentLevel + 1

    if nextLevel > 3 then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('upgrade_max'), type = 'error', duration = 5000 })
        return
    end

    local upgradeData = upgradeTiers[nextLevel]
    if not upgradeData then return end

    -- No per-tier rank gate — access is controlled by the owner/engineer check above.

    -- Check money
    local cash = Player.PlayerData.money['cash'] or 0
    if cash < upgradeData.cost then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('not_enough_money'), type = 'error', duration = 5000 })
        return
    end

    -- Check item cost
    if upgradeData.itemCost then
        local item = Player.Functions.GetItemByName(upgradeData.itemCost.item)
        if not item or item.amount < upgradeData.itemCost.amount then
            TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('upgrade_cost', upgradeData.cost, upgradeData.itemCost.amount, upgradeData.itemCost.item), type = 'error', duration = 5000 })
            return
        end
    end

    if not Player.Functions.RemoveMoney('cash', upgradeData.cost) then return end
    if upgradeData.itemCost then
        if not Player.Functions.RemoveItem(upgradeData.itemCost.item, upgradeData.itemCost.amount) then
            Player.Functions.AddMoney('cash', upgradeData.cost)
            return
        end
        TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(upgradeData.itemCost.item), 'remove')
    end

    -- Save and notify
    DB.UpsertCompanyUpgrade(companyId, trainModel, column, nextLevel)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('upgrade_purchased', upgradeData.label), type = 'success', duration = 5000 })
    print('[jrs_railroad] Company upgrade: ' .. companyId .. ' / ' .. trainModel .. ' / ' .. upgradeType .. ' -> Lvl ' .. nextLevel)

    Webhook.SendFields('economy', 'Upgrade Purchased', {
        { 'Player', GetPlayerFullName(Player) .. ' (' .. citizenid .. ')' },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
        { 'Train Model', trainModel },
        { 'Upgrade', upgradeData.label },
        { 'New Level', nextLevel },
        { 'Cost', '$' .. upgradeData.cost },
    }, 'success')
end)
