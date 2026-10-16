-- jrs_railroad | server: paying for finished mission legs and the railwayman rewards
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

-- The client only says "I finished a leg"; the pay is worked out here from the config, and a player
-- can be paid for a leg at most once per cooldown, so firing the event by hand does not farm money.
local COOLDOWN_MS <const> = 15000
local lastPaid = {}                                  -- source -> game timer of the last payout

AddEventHandler('playerDropped', function() lastPaid[source] = nil end)

local function byLabel(list, label)
    for _, entry in ipairs(list) do
        if entry.label == label then return entry end
    end
end

-- { pay, xp } for a finished leg, or nil when the request makes no sense
local function worth(kind, destination, cargo)
    local spec = Config.Missions[kind]
    if kind == 'maintenance' then return spec.basePay, spec.xpReward end

    local place = destination and byLabel(Config.DeliveryDestinations, destination.label)
    if kind == 'delivery' then
        if not place then return nil end
        local pay = spec.basePay + place.pay
        local load = cargo and byLabel(spec.cargoTypes, cargo.label)
        if load then pay = math.floor(pay * load.weight) end
        return pay, spec.xpReward
    end

    if kind == 'npc_transport' and spec then
        return spec.basePay + (place and place.pay or 0), spec.xpReward
    end
end

RegisterNetEvent('jrs_railroad:completeMission', function(kind, destination, cargo, companyId)
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    local now = GetGameTimer()
    if lastPaid[src] and now - lastPaid[src] < COOLDOWN_MS then return end

    local citizenid = player.PlayerData.citizenid

    if not companyId then
        local trains = DB.GetOwnedTrains(citizenid)
        companyId = trains and trains[1] and trains[1].company_id
    end
    if not companyId or not Config.Companies[companyId] then return end

    -- the pay goes into this company's register, so the player has to belong to it
    local role, ownership, employee = CompanyRole(companyId, citizenid)
    if not role then return end

    local pay, xp = worth(kind, destination, cargo)
    if not pay then return end
    lastPaid[src] = now

    if ownership then DB.AddToCashRegister(companyId, pay) end

    if Config.Webhooks.LogMissionCompletions then
        Webhook.SendFields('economy', 'Mission Completed', {
            { 'Player', GetPlayerFullName(player) .. ' (' .. citizenid .. ')' },
            { 'Company', Config.Companies[companyId].label },
            { 'Type', kind },
            { 'Pay', '$' .. pay },
            { 'XP', xp },
        }, 'success')
    end

    AddCompanyXP(src, citizenid, companyId, xp)
    if DB.GetCompanyMembership(citizenid, companyId) then
        DB.IncrementMissions(citizenid, companyId)
        DB.AddEarnings(citizenid, companyId, pay)
    end

    if employee then
        DB.IncrementEmployeeMissions(employee.id)
        DB.AddEmployeeEarnings(employee.id, pay)
    end

    Say(src, L('mission_complete_summary', pay, xp), 'success', 7000)
    TriggerClientEvent('jrs_railroad:refreshStationData', src, companyId)
    CheckRailwaymanRewards(src, citizenid, companyId)
end)

-- ------------------------------------------------------------------ railwayman rewards

local function totalMiles(trains)
    local sum = 0
    for _, train in ipairs(trains or {}) do sum = sum + (train.total_miles or 0) end
    return sum
end

-- true when the player has reached what the reward asks for
local function reached(reward, trains, membership)
    if reward.condition == 'trains_owned' then return trains ~= nil and #trains >= reward.threshold end
    if reward.condition == 'total_miles' then return totalMiles(trains) >= reward.threshold end
    if reward.condition == 'missions_completed' then return membership ~= nil and membership.missions_completed >= reward.threshold end
    return false
end

function CheckRailwaymanRewards(src, citizenid, companyId)
    local player = JRS.Player(src)
    if not player then return end

    local trains = DB.GetOwnedTrains(citizenid)
    local membership = companyId and DB.GetCompanyMembership(citizenid, companyId) or nil

    for _, reward in ipairs(Config.RailwaymanRewards) do
        if not DB.HasClaimedReward(citizenid, reward.id) and reached(reward, trains, membership) then
            DB.ClaimReward(citizenid, reward.id)
            player.Functions.AddMoney('cash', reward.cashReward)
            if companyId and reward.xpReward > 0 then DB.AddCompanyXP(citizenid, companyId, reward.xpReward) end
            Say(src, reward.label .. ' - ' .. L('reward_claimed', reward.cashReward), 'success', 8000)
        end
    end
end
