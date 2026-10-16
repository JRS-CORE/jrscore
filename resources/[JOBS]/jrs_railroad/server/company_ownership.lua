-- jrs_railroad | server: owning a company (buy, sell, rename, cash register) and its statistics
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local function labelOf(companyId)
    return Config.Companies[companyId] and Config.Companies[companyId].label or companyId
end

-- the owner row when `src` owns the company, else nil
local function ownedBy(player, companyId)
    local ownership = DB.GetCompanyOwnership(companyId)
    if ownership and ownership.owner_citizenid == player.PlayerData.citizenid then return ownership end
end

-- everybody learns whether the ambient train may run (it only runs while no company is owned)
local function broadcastAmbient()
    TriggerClientEvent('jrs_railroad:setAmbientState', -1, DB.GetOwnedCompanyCount() == 0)
end

-- ------------------------------------------------------------------ lookups

JRS.Callback('jrs_railroad:getCompanyOwnership', function(_, companyId) return DB.GetCompanyOwnership(companyId) end)
JRS.Callback('jrs_railroad:getAllOwnedCompanies', function() return DB.GetAllOwnedCompanies() end)
JRS.Callback('jrs_railroad:getCompanyTrains', function(_, companyId) return DB.GetCompanyTrains(companyId) end)

-- 'owner', 'driver', 'pending', 'visitor' or 'unowned'
JRS.Callback('jrs_railroad:getPlayerRole', function(src, companyId)
    local player = JRS.Player(src)
    if not player then return 'visitor' end

    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership then return 'unowned' end

    local citizenid = player.PlayerData.citizenid
    if ownership.owner_citizenid == citizenid then return 'owner' end

    local employee = DB.GetEmployeeByIds(companyId, citizenid)
    if employee and employee.status == 'approved' then return 'driver' end
    if employee and employee.status == 'pending' then return 'pending' end
    return 'visitor'
end)

JRS.Callback('jrs_railroad:getMyEmployeeData', function(src, companyId)
    local player = JRS.Player(src)
    return player and DB.GetEmployeeByIds(companyId, player.PlayerData.citizenid) or nil
end)

-- ------------------------------------------------------------------ buying and selling

RegisterNetEvent('jrs_railroad:buyCompany', function(companyId)
    local src = source
    local player = JRS.Player(src)
    if not player or not Config.Companies[companyId] then return end

    local citizenid = player.PlayerData.citizenid
    if DB.GetCompanyOwnership(companyId) then return Say(src, L('company_already_owned'), 'error') end
    if #DB.GetOwnedCompaniesByCitizen(citizenid) > 0 then return Say(src, L('already_own_company'), 'error') end

    local price = Config.CompanyPurchasePrice
    if (player.PlayerData.money['cash'] or 0) < price then return Say(src, L('not_enough_money'), 'error') end

    local owner = GetPlayerFullName(player)
    if not player.Functions.RemoveMoney('cash', price) then return end

    local inserted = DB.PurchaseCompany(companyId, citizenid, owner)
    if not inserted or inserted == 0 then
        player.Functions.AddMoney('cash', price)             -- somebody bought it a moment earlier
        return Say(src, L('company_already_owned'), 'error')
    end

    Say(src, L('company_purchased', labelOf(companyId)), 'success', 7000)
    Webhook.SendFields('economy', 'Company Purchased', {
        { 'Player', owner .. ' (' .. citizenid .. ')' },
        { 'Company', labelOf(companyId) },
        { 'Price', '$' .. price },
    }, 'success')
    broadcastAmbient()
end)

RegisterNetEvent('jrs_railroad:sellCompany', function(companyId)
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    local ownership = ownedBy(player, companyId)
    if not ownership then return Say(src, L('not_owner_of_company'), 'error') end

    -- part of the price back plus whatever is in the register
    local refund = math.floor(Config.CompanyPurchasePrice * Config.CompanySellPercent) + math.floor(ownership.cash_register or 0)

    -- the row goes first: only the request that really removed it gets paid
    if not DB.SellCompany(companyId, player.PlayerData.citizenid) then return end
    DB.DeleteEmployeesByCompany(companyId)
    DB.DeleteSuppliesByCompany(companyId)

    player.Functions.AddMoney('cash', refund)
    Say(src, L('company_sold', refund), 'success', 7000)
    Webhook.SendFields('economy', 'Company Sold', {
        { 'Player', GetPlayerFullName(player) .. ' (' .. player.PlayerData.citizenid .. ')' },
        { 'Company', labelOf(companyId) },
        { 'Refund', '$' .. refund },
    }, 'info')
    broadcastAmbient()
end)

RegisterNetEvent('jrs_railroad:renameCompany', function(companyId, name)
    local src = source
    local player = JRS.Player(src)
    if not player or not ownedBy(player, companyId) then return end

    if type(name) ~= 'string' or #name < 3 or #name > 50 then return Say(src, L('company_name_length'), 'error') end

    DB.SetCompanyName(companyId, name)
    Say(src, L('company_renamed', name), 'success')
    Webhook.SendFields('economy', 'Company Renamed', {
        { 'Player', GetPlayerFullName(player) .. ' (' .. player.PlayerData.citizenid .. ')' },
        { 'Company ID', companyId },
        { 'New Name', name },
    }, 'info')
end)

RegisterNetEvent('jrs_railroad:withdrawFunds', function(companyId, amount)
    local src = source
    local player = JRS.Player(src)
    if not player then return end
    if not ownedBy(player, companyId) then return Say(src, L('not_owner_of_company'), 'error') end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local balance = DB.GetCashRegister(companyId)
    if amount > balance or not DB.WithdrawFromCashRegister(companyId, amount) then
        return Say(src, L('insufficient_register_funds', math.floor(balance)), 'error')
    end

    player.Functions.AddMoney('cash', amount)
    Say(src, L('funds_withdrawn', amount), 'success')
    Webhook.SendFields('economy', 'Funds Withdrawn', {
        { 'Player', GetPlayerFullName(player) .. ' (' .. player.PlayerData.citizenid .. ')' },
        { 'Company', labelOf(companyId) },
        { 'Amount', '$' .. amount },
    }, 'warn')
end)

-- ------------------------------------------------------------------ statistics

local function fullName(employee) return (employee.firstname or '') .. ' ' .. (employee.lastname or '') end

-- totals over the approved drivers of a company
local function tally(companyId)
    local sum = { drivers = 0, missions = 0, earnings = 0 }
    local top = { earner = 'None', earnings = 0, missions = 'None', missionCount = 0, rank = 0, rankName = 'None' }

    for _, employee in ipairs(DB.GetEmployeesByCompany(companyId)) do
        if employee.status == 'approved' then
            local missions, earnings, rank = employee.missions_completed or 0, employee.total_earnings or 0, employee.rank or 1
            sum.drivers, sum.missions, sum.earnings = sum.drivers + 1, sum.missions + missions, sum.earnings + earnings

            if earnings > top.earnings then top.earnings, top.earner = earnings, fullName(employee) end
            if missions > top.missionCount then top.missionCount, top.missions = missions, fullName(employee) end
            if rank > top.rank then top.rank, top.rankName = rank, fullName(employee) end
        end
    end
    return sum, top
end

JRS.Callback('jrs_railroad:getCompanyStats', function(_, companyId)
    local sum, top = tally(companyId)
    local ownership = DB.GetCompanyOwnership(companyId)

    return {
        total_drivers = sum.drivers,
        total_missions = sum.missions,
        total_earnings = sum.earnings,
        cash_register = ownership and ownership.cash_register or 0,
        top_earner = top.earner,
        top_earnings = top.earnings,
        most_missions_name = top.missions,
        most_missions_count = top.missionCount,
        highest_rank_name = top.rankName,
        highest_rank_label = Config.Ranks[top.rank] and Config.Ranks[top.rank].label or '-',
    }
end)

-- one line per owned company, for the comparison board
JRS.Callback('jrs_railroad:getAllCompanyStats', function()
    local board = {}
    for _, owned in ipairs(DB.GetAllOwnedCompanies()) do
        local sum = tally(owned.company_id)
        board[#board + 1] = {
            company_id = owned.company_id,
            company_label = labelOf(owned.company_id),
            company_name = owned.company_name,
            owner_name = owned.owner_name,
            total_drivers = sum.drivers,
            total_missions = sum.missions,
            total_earnings = sum.earnings,
            cash_register = owned.cash_register or 0,
        }
    end
    return board
end)
