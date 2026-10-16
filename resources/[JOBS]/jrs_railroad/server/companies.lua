-- jrs_railroad | server: company membership, experience and ranks
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local function labelOf(companyId)
    return Config.Companies[companyId] and Config.Companies[companyId].label or companyId
end

RegisterNetEvent('jrs_railroad:joinCompany', function(companyId)
    local src = source
    local player = JRS.Player(src)
    if not player or not Config.Companies[companyId] then return end

    local citizenid = player.PlayerData.citizenid
    if DB.GetCompanyMembership(citizenid, companyId) then
        return Say(src, L('already_member', labelOf(companyId)), 'error')
    end

    DB.JoinCompany(citizenid, companyId)
    Say(src, L('company_joined', labelOf(companyId)), 'success')
end)

-- the highest rank whose experience requirement is met
local function rankFor(xp)
    for rank = 5, 1, -1 do
        if xp >= Config.Ranks[rank].xpRequired then return rank end
    end
    return 1
end

-- gives experience and, when it carries the player up a rank, pays that rank's reward
function AddCompanyXP(src, citizenid, companyId, xpAmount)
    if not companyId or companyId == '' then return end

    DB.EnsureCompanyMembership(citizenid, companyId)
    local before = DB.GetCompanyMembership(citizenid, companyId)
    if not before then return end

    DB.AddCompanyXP(citizenid, companyId, xpAmount)

    local rank = rankFor(before.xp + xpAmount)
    if rank <= before.rank then return end

    DB.SetCompanyRank(citizenid, companyId, rank)
    Say(src, L('rank_up', Config.Ranks[rank].label, labelOf(companyId)), 'success', 8000)

    local reward = Config.CompanyRankRewards[rank]
    local player = JRS.Player(src)
    if reward and reward.cashReward > 0 and player then
        player.Functions.AddMoney('cash', reward.cashReward)
        Say(src, L('rank_reward', reward.cashReward), 'success')
    end
end

-- 'owner', 'driver' (approved employee) or nil; also returns the ownership row and the employee row
function CompanyRole(companyId, citizenid)
    local ownership = DB.GetCompanyOwnership(companyId)
    if ownership and ownership.owner_citizenid == citizenid then return 'owner', ownership end

    local employee = DB.GetEmployeeByIds(companyId, citizenid)
    if employee and employee.status == 'approved' then return 'driver', ownership, employee end
    return nil, ownership
end

function GetPlayerCompanyRank(citizenid, companyId)
    local membership = DB.GetCompanyMembership(citizenid, companyId)
    return membership and membership.rank or 0
end
