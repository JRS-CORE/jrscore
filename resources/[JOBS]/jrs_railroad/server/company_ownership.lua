---------------------------------------------------------------
-- CALLBACKS: Company ownership + role detection
---------------------------------------------------------------

-- Get ownership data for a specific company
JRS.Callback('jrs_railroad:getCompanyOwnership', function(source, companyId)
    return DB.GetCompanyOwnership(companyId)
end)

-- Get ALL owned companies
JRS.Callback('jrs_railroad:getAllOwnedCompanies', function(source)
    return DB.GetAllOwnedCompanies()
end)

-- Determine player's role at a station's company
-- Returns: 'owner', 'driver', 'pending', 'visitor', 'unowned'
JRS.Callback('jrs_railroad:getPlayerRole', function(source, companyId)
    local Player = JRS.Player(source)
    if not Player then return 'visitor' end
    local citizenid = Player.PlayerData.citizenid

    -- Check if company is owned at all
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership then return 'unowned' end

    -- Check if this player is the owner
    if ownership.owner_citizenid == citizenid then return 'owner' end

    -- Check if this player is an employee
    local employee = DB.GetEmployeeByIds(companyId, citizenid)
    if employee then
        if employee.status == 'approved' then return 'driver' end
        if employee.status == 'pending' then return 'pending' end
    end

    return 'visitor'
end)

-- Get player's employee record for a company
JRS.Callback('jrs_railroad:getMyEmployeeData', function(source, companyId)
    local Player = JRS.Player(source)
    if not Player then return nil end
    return DB.GetEmployeeByIds(companyId, Player.PlayerData.citizenid)
end)

---------------------------------------------------------------
-- BUY COMPANY
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:buyCompany', function(companyId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    if not Config.Companies[companyId] then return end

    -- Check if already owned
    local existing = DB.GetCompanyOwnership(companyId)
    if existing then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_already_owned'), type = 'error', duration = 5000 })
        return
    end

    -- Check if player already owns a company
    local ownedByPlayer = DB.GetOwnedCompaniesByCitizen(citizenid)
    if #ownedByPlayer > 0 then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('already_own_company'), type = 'error', duration = 5000 })
        return
    end

    -- Check money
    local price = Config.CompanyPurchasePrice
    local cash = Player.PlayerData.money['cash'] or 0
    if cash < price then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('not_enough_money'), type = 'error', duration = 5000 })
        return
    end

    local charinfo = Player.PlayerData.charinfo
    local ownerName = (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')

    if not Player.Functions.RemoveMoney('cash', price) then return end
    local inserted = DB.PurchaseCompany(companyId, citizenid, ownerName)
    if not inserted or inserted == 0 then
        -- someone else bought it in the same moment
        Player.Functions.AddMoney('cash', price)
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_already_owned'), type = 'error', duration = 5000 })
        return
    end

    local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_purchased', companyLabel), type = 'success', duration = 7000 })

    Webhook.SendFields('economy', 'Company Purchased', {
        { 'Player', ownerName .. ' (' .. citizenid .. ')' },
        { 'Company', companyLabel },
        { 'Price', '$' .. price },
    }, 'success')

    local ownedCount = DB.GetOwnedCompanyCount()
    TriggerClientEvent('jrs_railroad:setAmbientState', -1, ownedCount == 0)
end)

---------------------------------------------------------------
-- SELL COMPANY
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:sellCompany', function(companyId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= citizenid then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('not_owner_of_company'), type = 'error', duration = 5000 })
        return
    end

    -- Refund
    local refund = math.floor(Config.CompanyPurchasePrice * Config.CompanySellPercent)
    -- Add cash register balance to refund
    refund = refund + math.floor(ownership.cash_register or 0)

    -- Delete the company row first; only the request that removed it pays.
    if not DB.SellCompany(companyId, citizenid) then return end
    DB.DeleteEmployeesByCompany(companyId)
    DB.DeleteSuppliesByCompany(companyId)

    Player.Functions.AddMoney('cash', refund)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_sold', refund), type = 'success', duration = 7000 })

    Webhook.SendFields('economy', 'Company Sold', {
        { 'Player', GetPlayerFullName(Player) .. ' (' .. citizenid .. ')' },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
        { 'Refund', '$' .. refund },
    }, 'info')

    local ownedCount = DB.GetOwnedCompanyCount()
    TriggerClientEvent('jrs_railroad:setAmbientState', -1, ownedCount == 0)
end)

---------------------------------------------------------------
-- RENAME COMPANY
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:renameCompany', function(companyId, newName)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= citizenid then return end

    if not newName or #newName < 3 or #newName > 50 then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_name_length'), type = 'error', duration = 5000 })
        return
    end

    DB.SetCompanyName(companyId, newName)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_renamed', newName), type = 'success', duration = 5000 })

    Webhook.SendFields('economy', 'Company Renamed', {
        { 'Player', GetPlayerFullName(Player) .. ' (' .. citizenid .. ')' },
        { 'Company ID', companyId },
        { 'New Name', newName },
    }, 'info')
end)

---------------------------------------------------------------
-- WITHDRAW FROM CASH REGISTER
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:withdrawFunds', function(companyId, amount)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= citizenid then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('not_owner_of_company'), type = 'error', duration = 5000 })
        return
    end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local balance = DB.GetCashRegister(companyId)
    if amount > balance or not DB.WithdrawFromCashRegister(companyId, amount) then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('insufficient_register_funds', math.floor(balance)), type = 'error', duration = 5000 })
        return
    end

    Player.Functions.AddMoney('cash', amount)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('funds_withdrawn', math.floor(amount)), type = 'success', duration = 5000 })

    Webhook.SendFields('economy', 'Funds Withdrawn', {
        { 'Player', GetPlayerFullName(Player) .. ' (' .. citizenid .. ')' },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
        { 'Amount', '$' .. math.floor(amount) },
    }, 'warn')
end)

---------------------------------------------------------------
-- COMPANY STATS (for Records tab)
---------------------------------------------------------------
JRS.Callback('jrs_railroad:getCompanyStats', function(source, companyId)
    local employees = DB.GetEmployeesByCompany(companyId) or {}
    local ownership = DB.GetCompanyOwnership(companyId)

    local totalDrivers = 0
    local totalMissions = 0
    local totalEarnings = 0
    local topEarner = 'None'
    local topEarnings = 0
    local mostMissionsName = 'None'
    local mostMissionsCount = 0
    local highestRank = 0
    local highestRankName = 'None'

    for _, emp in ipairs(employees) do
        if emp.status == 'approved' then
            totalDrivers = totalDrivers + 1
            totalMissions = totalMissions + (emp.missions_completed or 0)
            totalEarnings = totalEarnings + (emp.total_earnings or 0)
            if (emp.total_earnings or 0) > topEarnings then
                topEarnings = emp.total_earnings or 0
                topEarner = (emp.firstname or '') .. ' ' .. (emp.lastname or '')
            end
            if (emp.missions_completed or 0) > mostMissionsCount then
                mostMissionsCount = emp.missions_completed or 0
                mostMissionsName = (emp.firstname or '') .. ' ' .. (emp.lastname or '')
            end
            if (emp.rank or 1) > highestRank then
                highestRank = emp.rank or 1
                highestRankName = (emp.firstname or '') .. ' ' .. (emp.lastname or '')
            end
        end
    end

    local highestRankLabel = Config.Ranks[highestRank] and Config.Ranks[highestRank].label or '-'

    return {
        total_drivers = totalDrivers,
        total_missions = totalMissions,
        total_earnings = totalEarnings,
        cash_register = ownership and ownership.cash_register or 0,
        top_earner = topEarner,
        top_earnings = topEarnings,
        most_missions_name = mostMissionsName,
        most_missions_count = mostMissionsCount,
        highest_rank_name = highestRankName,
        highest_rank_label = highestRankLabel,
    }
end)

---------------------------------------------------------------
-- ALL COMPANY STATS (for leaderboard comparison)
---------------------------------------------------------------
JRS.Callback('jrs_railroad:getAllCompanyStats', function(source)
    local allOwned = DB.GetAllOwnedCompanies() or {}
    local results = {}

    for _, owned in ipairs(allOwned) do
        local compId = owned.company_id
        local employees = DB.GetEmployeesByCompany(compId) or {}
        local compConf = Config.Companies[compId]

        local totalDrivers = 0
        local totalMissions = 0
        local totalEarnings = 0

        for _, emp in ipairs(employees) do
            if emp.status == 'approved' then
                totalDrivers = totalDrivers + 1
                totalMissions = totalMissions + (emp.missions_completed or 0)
                totalEarnings = totalEarnings + (emp.total_earnings or 0)
            end
        end

        table.insert(results, {
            company_id = compId,
            company_label = compConf and compConf.label or compId,
            company_name = owned.company_name,
            owner_name = owned.owner_name,
            total_drivers = totalDrivers,
            total_missions = totalMissions,
            total_earnings = totalEarnings,
            cash_register = owned.cash_register or 0,
        })
    end

    return results
end)

---------------------------------------------------------------
-- GET COMPANY TRAINS (for station UI)
---------------------------------------------------------------
JRS.Callback('jrs_railroad:getCompanyTrains', function(source, companyId)
    return DB.GetCompanyTrains(companyId)
end)
