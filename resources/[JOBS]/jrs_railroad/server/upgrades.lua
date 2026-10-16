-- jrs_railroad | server: company-wide train upgrades
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

-- upgrade kind -> column of railroad_company_upgrades
local COLUMN <const> = {
    speed = 'upgrade_speed', fuel_cap = 'upgrade_fuel_cap', water_cap = 'upgrade_water_cap', durability = 'upgrade_durability',
}
local MAX_LEVEL <const> = 3
local MIN_ENGINEER_RANK <const> = 3

JRS.Callback('jrs_railroad:getCompanyUpgrades', function(_, companyId) return DB.GetCompanyUpgrades(companyId) end)
JRS.Callback('jrs_railroad:getTrainModelUpgrade', function(_, companyId, trainModel) return DB.GetCompanyTrainUpgrade(companyId, trainModel) end)

-- the owner, or an approved employee of engineer rank or better, may buy upgrades
local function mayUpgrade(ownership, companyId, citizenid)
    if ownership.owner_citizenid == citizenid then return true end
    local employee = DB.GetEmployeeByIds(companyId, citizenid)
    return employee ~= nil and employee.status == 'approved' and (employee.rank or 1) >= MIN_ENGINEER_RANK
end

local function trainOf(companyId, model)
    for _, train in ipairs(Config.Trains) do
        if train.model == model and train.company == companyId then return train end
    end
end

RegisterNetEvent('jrs_railroad:purchaseUpgrade', function(companyId, trainModel, kind)
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership then return end

    if not mayUpgrade(ownership, companyId, citizenid) then
        return Say(src, L('upgrade_owner_engineer_required'), 'error', 6000)
    end

    local train = trainOf(companyId, trainModel)
    if not train then return end
    if not train.upgradeable then return Say(src, L('upgrade_not_upgradeable'), 'error') end

    local tiers, column = Config.Upgrades[kind], COLUMN[kind]
    if not tiers or not column then return end

    local current = DB.GetCompanyTrainUpgrade(companyId, trainModel)
    local level = (current and current[column] or 0) + 1
    if level > MAX_LEVEL then return Say(src, L('upgrade_max'), 'error') end

    local tier = tiers[level]
    if not tier then return end

    if (player.PlayerData.money['cash'] or 0) < tier.cost then return Say(src, L('not_enough_money'), 'error') end

    local needs = tier.itemCost
    if needs then
        local have = player.Functions.GetItemByName(needs.item)
        if not have or have.amount < needs.amount then
            return Say(src, L('upgrade_cost', tier.cost, needs.amount, needs.item), 'error')
        end
    end

    if not player.Functions.RemoveMoney('cash', tier.cost) then return end
    if needs then
        if not player.Functions.RemoveItem(needs.item, needs.amount) then
            player.Functions.AddMoney('cash', tier.cost)             -- could not take the item: give the money back
            return
        end
        TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(needs.item), 'remove')
    end

    DB.UpsertCompanyUpgrade(companyId, trainModel, column, level)
    Say(src, L('upgrade_purchased', tier.label), 'success')
    print(('[jrs_railroad] company upgrade: %s / %s / %s -> level %d'):format(companyId, trainModel, kind, level))

    Webhook.SendFields('economy', 'Upgrade Purchased', {
        { 'Player', GetPlayerFullName(player) .. ' (' .. citizenid .. ')' },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
        { 'Train Model', trainModel },
        { 'Upgrade', tier.label },
        { 'New Level', level },
        { 'Cost', '$' .. tier.cost },
    }, 'success')
end)
