-- Minimum time between mission-complete payouts per player, so the
-- TriggerServerEvent can't just be spammed (or called directly, bypassing
-- the client-side travel/repair logic entirely) to farm money and XP.
local MISSION_COOLDOWN_MS = 15000
local lastMissionAt = {} -- [source] = GetGameTimer() of last payout

-- Finds the matching delivery destination in Config by label, so pay is
-- always taken from server config rather than whatever the client sent.
local function FindDeliveryDestination(label)
    for _, dest in ipairs(Config.DeliveryDestinations) do
        if dest.label == label then return dest end
    end
    return nil
end

-- Finds the matching cargo type in Config by label, for the same reason.
local function FindCargoType(label)
    for _, cargo in ipairs(Config.Missions.delivery.cargoTypes) do
        if cargo.label == label then return cargo end
    end
    return nil
end

----------------------------------------------------------------
-- COMPLETE MISSION
----------------------------------------------------------------
RegisterNetEvent('jrs_railroad:completeMission', function(missionType, destination, cargo, companyId)
    local src = source
    local Player = JRS.Player(src)
    if not Player then return end

    -- Anti-spam: also blocks the "just fire the event directly" exploit
    -- from paying out on every call.
    local now = GetGameTimer()
    if lastMissionAt[src] and (now - lastMissionAt[src]) < MISSION_COOLDOWN_MS then return end

    if missionType ~= 'delivery' and missionType ~= 'npc_transport' and missionType ~= 'maintenance' then return end

    local citizenid = Player.PlayerData.citizenid
    local pay = 0
    local xp = 0

    -- Fallback: derive company from owned trains if not provided
    if not companyId then
        local trains = DB.GetOwnedTrains(citizenid)
        if trains and #trains > 0 then
            companyId = trains[1].company_id
        end
    end
    if not companyId or not Config.Companies[companyId] then return end

    -- The player must actually be tied to this company (owner or
    -- approved employee) so mission pay can't be routed into a company
    -- they have nothing to do with.
    local ownership = DB.GetCompanyOwnership(companyId)
    local isOwner = ownership and ownership.owner_citizenid == citizenid
    local isDriver = false
    if not isOwner then
        local employee = DB.GetEmployeeByIds(companyId, citizenid)
        isDriver = employee ~= nil and employee.status == 'approved'
    end
    if not isOwner and not isDriver then return end

    if missionType == 'delivery' then
        -- Re-derive pay/xp from Config using only the destination LABEL and
        -- cargo LABEL sent by the client. This stops a forged destination
        -- or cargo table (e.g. {pay = 999999}) from being trusted directly.
        local cfg = Config.Missions.delivery
        local destCfg = destination and FindDeliveryDestination(destination.label)
        local cargoCfg = cargo and FindCargoType(cargo.label)
        if not destCfg then return end

        pay = cfg.basePay + destCfg.pay
        if cargoCfg then
            pay = math.floor(pay * cargoCfg.weight)
        end
        xp = cfg.xpReward

    elseif missionType == 'npc_transport' then
        local cfg = Config.Missions.npc_transport
        if not cfg then return end
        local destCfg = destination and FindDeliveryDestination(destination.label)
        pay = cfg.basePay + (destCfg and destCfg.pay or 0)
        xp = cfg.xpReward

    elseif missionType == 'maintenance' then
        local cfg = Config.Missions.maintenance
        pay = cfg.basePay
        xp = cfg.xpReward
    end

    lastMissionAt[src] = now

    -- ALL money goes to company cash register
    if ownership then
        DB.AddToCashRegister(companyId, pay)
    end

    if Config.Webhooks.LogMissionCompletions then
        Webhook.SendFields('economy', 'Mission Completed', {
            { 'Player', GetPlayerFullName(Player) .. ' (' .. citizenid .. ')' },
            { 'Company', Config.Companies[companyId] and Config.Companies[companyId].label or companyId },
            { 'Type', missionType },
            { 'Pay', '$' .. pay },
            { 'XP', xp },
        }, 'success')
    end

    -- Track XP (handles rank-up + notification) and missions
    AddCompanyXP(src, citizenid, companyId, xp)
    local membership = DB.GetCompanyMembership(citizenid, companyId)
    if membership then
        DB.IncrementMissions(citizenid, companyId)
        DB.AddEarnings(citizenid, companyId, pay)
    end

    -- Determine employee record for employee-specific tracking
    if not isOwner then
        local employee = DB.GetEmployeeByIds(companyId, citizenid)
        if employee then
            DB.IncrementEmployeeMissions(employee.id)
            DB.AddEmployeeEarnings(employee.id, pay)
        end
    end

    -- Notify
    TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, {
        title = L('notify_title'),
        description = L('mission_complete_summary', pay, xp),
        type = 'success',
        duration = 7000,
    })

    -- Tell client to refresh any open station data
    TriggerClientEvent('jrs_railroad:refreshStationData', src, companyId)

    -- Check railwayman rewards
    CheckRailwaymanRewards(src, citizenid, companyId)
end)

----------------------------------------------------------------
-- CHECK RAILWAYMAN REWARDS
----------------------------------------------------------------
function CheckRailwaymanRewards(src, citizenid, companyId)
    local Player = JRS.Player(src)
    if not Player then return end

    local trains = DB.GetOwnedTrains(citizenid)
    local membership = companyId and DB.GetCompanyMembership(citizenid, companyId) or nil

    for _, reward in ipairs(Config.RailwaymanRewards) do
        if not DB.HasClaimedReward(citizenid, reward.id) then
            local met = false

            if reward.condition == 'trains_owned' then
                met = (trains and #trains >= reward.threshold)
            elseif reward.condition == 'total_miles' then
                local totalMiles = 0
                if trains then
                    for _, t in ipairs(trains) do
                        totalMiles = totalMiles + (t.total_miles or 0)
                    end
                end
                met = (totalMiles >= reward.threshold)
            elseif reward.condition == 'missions_completed' then
                if membership then
                    met = (membership.missions_completed >= reward.threshold)
                end
            end

            if met then
                DB.ClaimReward(citizenid, reward.id)
                Player.Functions.AddMoney('cash', reward.cashReward)
                if companyId and reward.xpReward > 0 then
                    DB.AddCompanyXP(citizenid, companyId, reward.xpReward)
                end
                TriggerClientEvent(GetCurrentResourceName() .. ':notify', src, {
                    title = L('notify_title'),
                    description = reward.label .. ' - ' .. L('reward_claimed', reward.cashReward),
                    type = 'success',
                    duration = 8000
                })
            end
        end
    end
end
