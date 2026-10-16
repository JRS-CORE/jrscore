-- jrs_railroad | server: drivers who apply to a company, and the owner who decides
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local function labelOf(companyId)
    return Config.Companies[companyId] and Config.Companies[companyId].label or companyId
end

-- tells a player by character id, if they are online; the company name is the notification title
local function tell(citizenid, companyId, text, kind)
    local target = JRS.PlayerByCharId(citizenid)
    if target then Say(target.PlayerData.source, text, kind, 10000, labelOf(companyId)) end
end

local function isOwner(player, companyId)
    local ownership = DB.GetCompanyOwnership(companyId)
    return ownership ~= nil and ownership.owner_citizenid == player.PlayerData.citizenid, ownership
end

-- the employee row with this id inside one company
local function employeeOf(companyId, employeeId)
    for _, employee in ipairs(DB.GetEmployeesByCompany(companyId)) do
        if employee.id == employeeId then return employee end
    end
end

JRS.Callback('jrs_railroad:getEmployees', function(_, companyId) return DB.GetEmployeesByCompany(companyId) end)
JRS.Callback('jrs_railroad:getPendingApplications', function(_, companyId) return DB.GetPendingApplications(companyId) end)

JRS.Callback('jrs_railroad:getMyEmployment', function(src)
    local player = JRS.Player(src)
    return player and DB.GetPlayerEmployment(player.PlayerData.citizenid) or {}
end)

-- ------------------------------------------------------------------ applying

RegisterNetEvent('jrs_railroad:applyAsDriver', function(companyId)
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local info = player.PlayerData.charinfo

    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership then return Say(src, L('company_no_owner'), 'error') end

    local existing = DB.GetEmployeeByIds(companyId, citizenid)
    if existing then
        return Say(src, existing.status == 'pending' and L('application_pending') or L('already_employed'), 'error')
    end
    if ownership.owner_citizenid == citizenid then return Say(src, L('own_this_company'), 'error') end

    DB.ApplyAsDriver(companyId, citizenid, info.firstname or '', info.lastname or '')
    Say(src, L('application_submitted'), 'success', 7000)

    Webhook.SendFields('employees', 'Driver Application', {
        { 'Applicant', GetPlayerFullName(player) .. ' (' .. citizenid .. ')' },
        { 'Company', labelOf(companyId) },
    }, 'info')

    tell(ownership.owner_citizenid, companyId, L('driver_applied_notify', GetPlayerFullName(player)), 'inform')
end)

-- ------------------------------------------------------------------ the owner decides

RegisterNetEvent('jrs_railroad:approveDriver', function(companyId, employeeId)
    local src = source
    local player = JRS.Player(src)
    if not player or not isOwner(player, companyId) then return end

    DB.ApproveEmployee(employeeId)

    -- the driver also needs a membership row for experience and rank
    local employee = employeeOf(companyId, employeeId)
    if employee then DB.EnsureCompanyMembership(employee.citizenid, companyId) end

    Say(src, L('driver_approved'), 'success')
    Webhook.SendFields('employees', 'Driver Approved', {
        { 'Approved By', GetPlayerFullName(player) },
        { 'Company', labelOf(companyId) },
    }, 'success')

    if employee then tell(employee.citizenid, companyId, L('application_approved_notify'), 'success') end
end)

RegisterNetEvent('jrs_railroad:rejectDriver', function(companyId, employeeId)
    local src = source
    local player = JRS.Player(src)
    if not player or not isOwner(player, companyId) then return end

    DB.RejectEmployee(employeeId)
    Say(src, L('application_rejected'), 'inform')
    Webhook.SendFields('employees', 'Driver Application Rejected', {
        { 'Rejected By', GetPlayerFullName(player) },
        { 'Company', labelOf(companyId) },
    }, 'warn')
end)

RegisterNetEvent('jrs_railroad:fireDriver', function(companyId, employeeId)
    local src = source
    local player = JRS.Player(src)
    if not player or not isOwner(player, companyId) then return end

    local employee = employeeOf(companyId, employeeId)
    local name = employee and ((employee.firstname or '') .. ' ' .. (employee.lastname or '')) or ''

    DB.FireEmployee(employeeId)
    Say(src, L('driver_fired', name), 'success')
    Webhook.SendFields('employees', 'Driver Fired', {
        { 'Fired By', GetPlayerFullName(player) },
        { 'Company', labelOf(companyId) },
        { 'Driver', name },
    }, 'error')

    if employee then tell(employee.citizenid, companyId, L('fired_notify'), 'error') end
end)

-- ------------------------------------------------------------------ the driver's own rank

function AddDriverXP(src, companyId, citizenid, xpAmount)
    local employee = DB.GetEmployeeByIds(companyId, citizenid)
    if not employee or employee.status ~= 'approved' then return end

    DB.AddEmployeeXP(employee.id, xpAmount)

    local newXP, rank = employee.xp + xpAmount, employee.rank
    for candidate = 5, 1, -1 do
        if newXP >= Config.Ranks[candidate].xpRequired then rank = candidate break end
    end
    if rank <= employee.rank then return end

    DB.SetEmployeeRank(employee.id, rank)
    Say(src, L('rank_up', Config.Ranks[rank].label, labelOf(companyId)), 'success', 8000)

    local reward = Config.CompanyRankRewards[rank]
    local winner = JRS.Player(src)
    if reward and reward.cashReward > 0 and winner then
        winner.Functions.AddMoney('cash', reward.cashReward)
        Say(src, L('rank_reward', reward.cashReward), 'success')
    end
end
