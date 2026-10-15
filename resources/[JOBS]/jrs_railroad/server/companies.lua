---------------------------------------------------------------
-- JOIN COMPANY
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:joinCompany', function(companyId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    if not Config.Companies[companyId] then return end

    local existing = DB.GetCompanyMembership(citizenid, companyId)
    if existing then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('already_member', Config.Companies[companyId].label), type = 'error', duration = 5000 })
        return
    end

    DB.JoinCompany(citizenid, companyId)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_joined', Config.Companies[companyId].label), type = 'success', duration = 5000 })
end)

---------------------------------------------------------------
-- ADD XP AND CHECK RANK UP
---------------------------------------------------------------
function AddCompanyXP(src, citizenid, companyId, xpAmount)
    if not companyId or companyId == '' then return end

    DB.EnsureCompanyMembership(citizenid, companyId)

    local membership = DB.GetCompanyMembership(citizenid, companyId)
    if not membership then return end

    DB.AddCompanyXP(citizenid, companyId, xpAmount)

    -- Check for rank up
    local newXP = membership.xp + xpAmount
    local currentRank = membership.rank
    local newRank = currentRank

    for rank = 5, 1, -1 do
        if newXP >= Config.Ranks[rank].xpRequired then
            newRank = rank
            break
        end
    end

    if newRank > currentRank then
        DB.SetCompanyRank(citizenid, companyId, newRank)
        local rankLabel = Config.Ranks[newRank].label
        local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('rank_up', rankLabel, companyLabel), type = 'success', duration = 8000 })

        -- Rank reward
        if Config.CompanyRankRewards[newRank] then
            local reward = Config.CompanyRankRewards[newRank]
            if reward.cashReward > 0 then
                local Player = JRS.Player(src)
                if Player then
                    Player.Functions.AddMoney('cash', reward.cashReward)
                    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('rank_reward', reward.cashReward), type = 'success', duration = 5000 })
                end
            end
        end
    end
end

---------------------------------------------------------------
-- GET RANK FOR PLAYER IN COMPANY
---------------------------------------------------------------
function GetPlayerCompanyRank(citizenid, companyId)
    local membership = DB.GetCompanyMembership(citizenid, companyId)
    if not membership then return 0 end
    return membership.rank
end
