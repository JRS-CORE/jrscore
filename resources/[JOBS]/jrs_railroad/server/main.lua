-- jrs_railroad | server: owned trains (buy, sell, park, state), ticket pay and the maintenance items
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local out = {}                             -- source -> id of the train that player has on the track (0 = company train)

local function configOf(train)
    for _, entry in ipairs(Config.Trains) do
        if entry.model == train.train_model and entry.company == train.company_id then return entry end
    end
end

local function clamp(value, max)
    value = tonumber(value) or 0
    return value < 0 and 0 or (value > max and max or value)
end

-- the train row, but only when `src` owns it and is the one driving it (stops spoofed update events)
local function drivenTrain(src, trainId)
    local player = JRS.Player(src)
    if not player or out[src] ~= trainId then return nil end
    local train = DB.GetTrainById(trainId)
    if train and train.citizenid == player.PlayerData.citizenid then return train, player end
end

-- tank sizes of a train row, defaulting to 100
local function limits(train)
    local entry = configOf(train)
    return entry and entry.maxFuel or 100, entry and entry.maxWater or 100, entry and entry.maxCondition or 100
end

local function companyLabel(companyId)
    return Config.Companies[companyId] and Config.Companies[companyId].label or companyId
end

-- ------------------------------------------------------------------ lookups

JRS.Callback('jrs_railroad:getOwnedTrains', function(src)
    local player = JRS.Player(src)
    return player and DB.GetOwnedTrains(player.PlayerData.citizenid) or {}
end)

JRS.Callback('jrs_railroad:getTrainById', function(src, trainId)
    local player = JRS.Player(src)
    local train = player and DB.GetTrainById(trainId)
    if train and train.citizenid == player.PlayerData.citizenid then return train end
    return nil
end)

JRS.Callback('jrs_railroad:canSpawnTrain', function(src) return out[src] == nil end)
JRS.Callback('jrs_railroad:getAmbientState', function() return DB.GetOwnedCompanyCount() == 0 end)

JRS.Callback('jrs_railroad:getMyCompanyMembership', function(src, companyId)
    local player = JRS.Player(src)
    return player and DB.GetCompanyMembership(player.PlayerData.citizenid, companyId) or nil
end)

JRS.Callback('jrs_railroad:getCompanyData', function(src)
    local player = JRS.Player(src)
    return player and DB.GetCompanyData(player.PlayerData.citizenid) or {}
end)

-- ------------------------------------------------------------------ buying and selling

RegisterNetEvent('jrs_railroad:buyTrain', function(index)
    local src = source
    local player = JRS.Player(src)
    local entry = Config.Trains[index]
    if not player or not entry then return end

    local citizenid = player.PlayerData.citizenid
    if DB.CountTrains(citizenid) >= Config.MaxTrainsPerPlayer then
        return Say(src, L('train_limit_reached', Config.MaxTrainsPerPlayer), 'error')
    end

    -- the rank needed; somebody who is not a member yet joins at rank 1
    local rankName = Config.Ranks[entry.requiredRank] and Config.Ranks[entry.requiredRank].label or 'Unknown'
    local membership = DB.GetCompanyMembership(citizenid, entry.company)
    local rank = membership and membership.rank or 1
    if rank < entry.requiredRank then return Say(src, L('rank_too_low', rankName), 'error') end
    if not membership then DB.JoinCompany(citizenid, entry.company) end

    if (player.PlayerData.money['cash'] or 0) < entry.cost then return Say(src, L('not_enough_money'), 'error') end
    if not player.Functions.RemoveMoney('cash', entry.cost) then return end

    -- a new train starts half full and half repaired
    DB.InsertTrain(citizenid, entry.company, entry.model, entry.label,
        math.floor(entry.maxFuel * 0.5), math.floor(entry.maxWater * 0.5), math.floor(entry.maxCondition * 0.5))
    Say(src, L('train_bought_half', L('train_bought')), 'success', 7000)

    Webhook.SendFields('economy', 'Train Purchased', {
        { 'Player', GetPlayerFullName(player) .. ' (' .. citizenid .. ')' },
        { 'Company', companyLabel(entry.company) },
        { 'Train', entry.label },
        { 'Cost', '$' .. entry.cost },
    }, 'success')
end)

RegisterNetEvent('jrs_railroad:sellTrain', function(trainId)
    local src = source
    local player = JRS.Player(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local train = DB.GetTrainById(trainId)
    if not train or train.citizenid ~= citizenid then return end
    if out[src] == trainId then return Say(src, L('park_before_selling'), 'error') end

    local entry = configOf(train)
    local price = entry and entry.sellPrice or 0

    if not DB.DeleteTrain(trainId, citizenid) then return end
    player.Functions.AddMoney('cash', math.floor(price))
    Say(src, L('train_sold', price), 'success')

    Webhook.SendFields('economy', 'Train Sold', {
        { 'Player', GetPlayerFullName(player) .. ' (' .. citizenid .. ')' },
        { 'Train', train.train_model },
        { 'Sell Price', '$' .. price },
    }, 'info')
end)

-- ------------------------------------------------------------------ ticket pay at a station

local lastPay = {}                         -- source -> { t = os.time(), station = id }

-- the station of this company the player is standing at, if any
local function stationOf(src, companyId)
    local at = GetEntityCoords(GetPlayerPed(src))
    local radius = Config.PassengerSystem.StationStopRadius or 135.0
    for _, station in ipairs(Config.Stations) do
        if station.company == companyId and #(at - station.coords) <= radius then return station end
    end
end

RegisterNetEvent('jrs_railroad:ticketRevenue', function(companyId, riders)
    local src = source
    local player = JRS.Player(src)
    if not player or not companyId or not Config.Companies[companyId] then return end

    -- only people who work for the company can be driving its trains
    local citizenid = player.PlayerData.citizenid
    local role, ownership = CompanyRole(companyId, citizenid)
    if not role then return end

    riders = math.floor(tonumber(riders) or 0)
    if riders <= 0 or out[src] == nil then return end

    local cfg = Config.PassengerSystem
    riders = math.min(riders, cfg.MaxBoardPerStop or 10)

    local station = stationOf(src, companyId)
    if not station then return end

    -- 30 s between payouts, 5 min before the same station pays again
    local now, last = os.time(), lastPay[src]
    if last and (now - last.t < 30 or (last.station == station.id and now - last.t < 300)) then return end
    lastPay[src] = { t = now, station = station.id }

    local total = riders * cfg.TicketPrice
    local driver, company = math.floor(total * (1 - cfg.CompanyShare)), math.floor(total * cfg.CompanyShare)

    player.Functions.AddMoney('cash', driver)
    if ownership then DB.AddToCashRegister(companyId, company) end

    local xp = riders * cfg.TicketXP
    DB.AddCompanyXP(citizenid, companyId, xp)
    Say(src, L('ticket_revenue_summary', driver, company, xp), 'success', 7000)
end)

-- ------------------------------------------------------------------ which train a player has out

RegisterNetEvent('jrs_railroad:setTrainSpawned', function(spawned, trainId)
    local src = source
    if not spawned then out[src] = nil return end

    local player = JRS.Player(src)
    if not player or out[src] then return end

    -- company trains have no row (id 0); a personally owned one has to belong to the player
    trainId = tonumber(trainId) or 0
    if trainId > 0 then
        local train = DB.GetTrainById(trainId)
        if not train or train.citizenid ~= player.PlayerData.citizenid then return end
        DB.UnparkTrain(trainId)
    end
    out[src] = trainId
end)

RegisterNetEvent('jrs_railroad:parkTrain', function(trainId, stationId, fuel, water, condition)
    local src = source
    local train = drivenTrain(src, trainId)
    if not train then return end

    local maxFuel, maxWater, maxCondition = limits(train)
    DB.ParkTrain(trainId, stationId, clamp(fuel, maxFuel), clamp(water, maxWater), clamp(condition, maxCondition))
    out[src] = nil
end)

-- ------------------------------------------------------------------ state saved while driving

RegisterNetEvent('jrs_railroad:updateTrainState', function(trainId, fuel, water, condition)
    local train = drivenTrain(source, trainId)
    if not train then return end
    local maxFuel, maxWater, maxCondition = limits(train)
    DB.UpdateTrainState(trainId, clamp(fuel, maxFuel), clamp(water, maxWater), clamp(condition, maxCondition))
end)

RegisterNetEvent('jrs_railroad:updateFuel', function(trainId, fuel)
    local train = drivenTrain(source, trainId)
    if train then DB.UpdateTrainFuel(trainId, clamp(fuel, (limits(train)))) end
end)

RegisterNetEvent('jrs_railroad:updateWater', function(trainId, water)
    local train = drivenTrain(source, trainId)
    if train then DB.UpdateTrainWater(trainId, clamp(water, select(2, limits(train)))) end
end)

RegisterNetEvent('jrs_railroad:updateCondition', function(trainId, condition)
    local train = drivenTrain(source, trainId)
    if train then DB.UpdateTrainCondition(trainId, clamp(condition, select(3, limits(train)))) end
end)

-- one call may credit this many miles, so a forged event cannot inflate the reward counters
local MAX_MILES <const> = 25

RegisterNetEvent('jrs_railroad:addMiles', function(trainId, miles)
    if not drivenTrain(source, trainId) then return end
    miles = tonumber(miles) or 0
    if miles > 0 then DB.AddMiles(trainId, math.min(miles, MAX_MILES)) end
end)

-- ------------------------------------------------------------------ fuel, water and repair items
-- one item restores a tenth of the tank; `size` is the position of that tank in limits()

local TENTH <const> = 0.10

-- everything that differs between the three kinds of maintenance
local KINDS <const> = {
    fuel = {
        cfg = 'Fuel', column = 'fuel', size = 1, save = 'UpdateTrainFuel', sync = 'jrs_railroad:syncFuel',
        full = 'fuel_tank_full', missing = 'no_fuel_item', added = 'fuel_added_pct',
    },
    water = {
        cfg = 'Water', column = 'water', size = 2, save = 'UpdateTrainWater', sync = 'jrs_railroad:syncWater',
        full = 'water_tank_full', missing = 'no_water_item', added = 'water_added_pct',
    },
    condition = {
        cfg = 'Condition', column = 'condition', size = 3, save = 'UpdateTrainCondition', sync = 'jrs_railroad:syncCondition',
        full = 'condition_full', missing = 'no_repair_item', added = 'condition_repaired_pct',
    },
}

local function topUp(spec)
    return function(trainId)
        local src = source
        local player = JRS.Player(src)
        if not player then return end

        local train = DB.GetTrainById(trainId)
        if not train or train.citizenid ~= player.PlayerData.citizenid then return end

        local settings = Config[spec.cfg]
        local max = select(spec.size, limits(train))
        local have = train[spec.column]
        if have >= max then return Say(src, L(spec.full), 'error') end

        local item = player.Functions.GetItemByName(settings.item)
        if not item or item.amount < 1 then return Say(src, L(spec.missing, 1, settings.itemLabel), 'error') end

        if not player.Functions.RemoveItem(settings.item, 1) then return end
        TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(settings.item), 'remove')

        local now = math.min(have + math.floor(max * TENTH), max)
        DB[spec.save](trainId, now)
        TriggerClientEvent(spec.sync, src, now)
        Say(src, L(spec.added, math.floor(now / max * 100)), 'success')
    end
end

RegisterNetEvent('jrs_railroad:refuelTrain', topUp(KINDS.fuel))
RegisterNetEvent('jrs_railroad:refillWater', topUp(KINDS.water))
RegisterNetEvent('jrs_railroad:repairTrain', topUp(KINDS.condition))

-- works for company trains too: the item is taken here and the client applies the effect
RegisterNetEvent('jrs_railroad:useMaintenanceItem', function(itemName, quantity, kind, trainId)
    local src = source
    local player = JRS.Player(src)
    local spec = KINDS[kind]
    if not player or not spec or itemName ~= Config[spec.cfg].item then return end

    local function result(ok) TriggerClientEvent('jrs_railroad:maintenanceResult', src, kind, ok) end

    quantity = math.max(1, math.min(math.floor(tonumber(quantity) or 1), 10))

    local have = player.Functions.GetItemByName(itemName)
    if not have or have.amount < quantity then
        Say(src, L('missing_required_item'), 'error')
        return result(false)
    end

    local train
    if trainId and trainId > 0 then
        train = DB.GetTrainById(trainId)
        if not train or train.citizenid ~= player.PlayerData.citizenid then return result(false) end
    end

    if not player.Functions.RemoveItem(itemName, quantity) then return result(false) end
    TriggerClientEvent('inventory:client:ItemBox', src, JRS.ItemDef(itemName), 'remove')

    if train then
        local max = select(spec.size, limits(train))
        DB[spec.save](trainId, math.min(train[spec.column] + math.floor(max * TENTH), max))
    end
    result(true)
end)

AddEventHandler('playerDropped', function()
    out[source], lastPay[source] = nil, nil
end)
