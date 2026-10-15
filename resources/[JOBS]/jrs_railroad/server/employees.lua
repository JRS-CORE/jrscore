---------------------------------------------------------------
-- CALLBACKS
---------------------------------------------------------------
JRS.Callback('jrs_railroad:getEmployees', function(source, companyId)
    return DB.GetEmployeesByCompany(companyId)
end)

JRS.Callback('jrs_railroad:getPendingApplications', function(source, companyId)
    return DB.GetPendingApplications(companyId)
end)

JRS.Callback('jrs_railroad:getMyEmployment', function(source)
    local Player = JRS.Player(source)
    if not Player then return {} end
    return DB.GetPlayerEmployment(Player.PlayerData.citizenid)
end)

---------------------------------------------------------------
-- APPLY AS DRIVER
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:applyAsDriver', function(companyId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local charinfo = Player.PlayerData.charinfo

    -- Check company is owned
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('company_no_owner'), type = 'error', duration = 5000 })
        return
    end

    -- Check not already applied/employed
    local existing = DB.GetEmployeeByIds(companyId, citizenid)
    if existing then
        local msg = existing.status == 'pending' and L('application_pending') or L('already_employed')
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = msg, type = 'error', duration = 5000 })
        return
    end

    -- Check player doesn't own this company
    if ownership.owner_citizenid == citizenid then
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('own_this_company'), type = 'error', duration = 5000 })
        return
    end

    DB.ApplyAsDriver(companyId, citizenid, charinfo.firstname or '', charinfo.lastname or '')
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('application_submitted'), type = 'success', duration = 7000 })

    Webhook.SendFields('employees', 'Driver Application', {
        { 'Applicant', GetPlayerFullName(Player) .. ' (' .. citizenid .. ')' },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
    }, 'info')

    -- Notify owner if online
    local ownerPlayer = JRS.PlayerByCharId(ownership.owner_citizenid)
    if ownerPlayer then
        local applicantName = (charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')
        local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', ownerPlayer.PlayerData.source, {
            title = companyLabel,
            description = L('driver_applied_notify', applicantName),
            type = 'inform',
            duration = 10000,
        })
    end
end)

---------------------------------------------------------------
-- APPROVE DRIVER
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:approveDriver', function(companyId, employeeId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    -- Verify caller is owner
    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= Player.PlayerData.citizenid then return end

    DB.ApproveEmployee(employeeId)

    -- Ensure the driver has a company membership row for XP/rank tracking
    local employees = DB.GetEmployeesByCompany(companyId)
    for _, emp in ipairs(employees) do
        if emp.id == employeeId then
            DB.EnsureCompanyMembership(emp.citizenid, companyId)
            break
        end
    end

    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('driver_approved'), type = 'success', duration = 5000 })

    Webhook.SendFields('employees', 'Driver Approved', {
        { 'Approved By', GetPlayerFullName(Player) },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
    }, 'success')

    -- Notify the driver if online
    local employees = DB.GetEmployeesByCompany(companyId)
    for _, emp in ipairs(employees) do
        if emp.id == employeeId then
            local driverPlayer = JRS.PlayerByCharId(emp.citizenid)
            if driverPlayer then
                local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
                TriggerClientEvent(GetCurrentResourceName() .. ':notify', driverPlayer.PlayerData.source, {
                    title = companyLabel,
                    description = L('application_approved_notify'),
                    type = 'success',
                    duration = 10000,
                })
            end
            break
        end
    end
end)

---------------------------------------------------------------
-- REJECT DRIVER
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:rejectDriver', function(companyId, employeeId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= Player.PlayerData.citizenid then return end

    DB.RejectEmployee(employeeId)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('application_rejected'), type = 'inform', duration = 5000 })

    Webhook.SendFields('employees', 'Driver Application Rejected', {
        { 'Rejected By', GetPlayerFullName(Player) },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
    }, 'warn')
end)

---------------------------------------------------------------
-- FIRE DRIVER
---------------------------------------------------------------
RegisterNetEvent('jrs_railroad:fireDriver', function(companyId, employeeId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    local ownership = DB.GetCompanyOwnership(companyId)
    if not ownership or ownership.owner_citizenid ~= Player.PlayerData.citizenid then return end

    -- Get employee info for notification
    local employees = DB.GetEmployeesByCompany(companyId)
    local firedCid = nil
    local firedName = ''
    for _, emp in ipairs(employees) do
        if emp.id == employeeId then
            firedCid = emp.citizenid
            firedName = (emp.firstname or '') .. ' ' .. (emp.lastname or '')
            break
        end
    end

    DB.FireEmployee(employeeId)
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, { title = L('notify_title'), description = L('driver_fired', firedName), type = 'success', duration = 5000 })

    Webhook.SendFields('employees', 'Driver Fired', {
        { 'Fired By', GetPlayerFullName(Player) },
        { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
        { 'Driver', firedName },
    }, 'error')

    -- Notify fired player if online
    if firedCid then
        local firedPlayer = JRS.PlayerByCharId(firedCid)
        if firedPlayer then
            local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
            TriggerClientEvent(GetCurrentResourceName() .. ':notify', firedPlayer.PlayerData.source, {
                title = companyLabel,
                description = L('fired_notify'),
                type = 'error',
                duration = 10000,
            })
        end
    end
end)

---------------------------------------------------------------
-- EMPLOYEE XP + RANK UP (called from missions)
---------------------------------------------------------------
function AddDriverXP(src, companyId, citizenid, xpAmount)
    local employee = DB.GetEmployeeByIds(companyId, citizenid)
    if not employee or employee.status ~= 'approved' then return end

    DB.AddEmployeeXP(employee.id, xpAmount)

    -- Check rank up
    local newXP = employee.xp + xpAmount
    local currentRank = employee.rank
    local newRank = currentRank

    for rank = 5, 1, -1 do
        if newXP >= Config.Ranks[rank].xpRequired then
            newRank = rank
            break
        end
    end

    if newRank > currentRank then
        DB.SetEmployeeRank(employee.id, newRank)
        local rankLabel = Config.Ranks[newRank].label
        local companyLabel = Config.Companies[companyId] and Config.Companies[companyId].label or companyId
        TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, {
            title = L('notify_title'),
            description = L('rank_up', rankLabel, companyLabel),
            type = 'success',
            duration = 8000,
        })

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
