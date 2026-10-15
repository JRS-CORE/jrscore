

-- activeBalloons[src] = { netId = number, dock = number, seats = { [1..4] = src or nil } }
local activeBalloons = {}

-- reverse lookup so two owners can never claim the same netId
-- claimedNetIds[netId] = src
local claimedNetIds = {}

local function GetPlayer(src)
    local Player = JRS.Char(src)
    if not Player then
        print(string.format('^1[jrs_hotair]^0 Player not found for source: %d', src))
    end
    return Player
end

local function FindBalloonByNetId(netId)
    local ownerSrc = claimedNetIds[netId]
    if not ownerSrc then return nil, nil end
    local data = activeBalloons[ownerSrc]
    if not data or data.netId ~= netId then return nil, nil end
    return ownerSrc, data
end

local function OccupantCount(data)
    local count = 0
    for i = 1, 4 do
        if data.seats[i] then
            count = count + 1
        end
    end
    return count
end

local function PushSeatUpdate(ownerSrc)
    local data = activeBalloons[ownerSrc]
    if not data then return end
    TriggerClientEvent('jrs_hotair:client:seatUpdate', ownerSrc, OccupantCount(data))
    for i = 1, 4 do
        if data.seats[i] then
            TriggerClientEvent('jrs_hotair:client:seatUpdate', data.seats[i], OccupantCount(data))
        end
    end
end

-- Frees an owner's slot and any netId claim it held. Does NOT refund/notify;
-- callers decide that.
local function ReleaseBalloon(ownerSrc)
    local data = activeBalloons[ownerSrc]
    if not data then return end
    if data.netId and claimedNetIds[data.netId] == ownerSrc then
        claimedNetIds[data.netId] = nil
    end
    activeBalloons[ownerSrc] = nil
end

-- Distance/speed sanity check against a networked entity, used to stop
-- passengers "boarding" a balloon they aren't actually near.
local function IsNearEntity(src, entity, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local playerCoords = GetEntityCoords(ped)
    local entityCoords = GetEntityCoords(entity)
    return #(playerCoords - entityCoords) <= maxDistance
end

-- Hire: validate (no active balloon + valid dock + can afford), charge, register slot.
-- Client spawns the balloon after a successful callback, then registers the netId.
JRS.CreateCallback('jrs_hotair:server:hireBalloon', function(source, cb, dock)
    local src = source
    if activeBalloons[src] then
        cb(false, L('error.already_have_balloon'))
        return
    end
    dock = tonumber(dock)
    if not dock or not Config.Docks[dock] then
        cb(false, L('error.dock_unavailable'))
        return
    end
    local Player = GetPlayer(src)
    if not Player then
        cb(false, L('error.no_player_data'))
        return
    end
    -- hire only at the dock (the menu can also be opened by /hotair within 50 m)
    if not JRS.Near(src, Config.Docks[dock].npcCoords, 60.0) then
        cb(false, L('error.dock_unavailable'))
        return
    end
    local price = Config.HirePrice
    if JRS.Money(src) < price then
        cb(false, L('error.not_enough_cash'))
        return
    end
    if not JRS.TakeMoney(src, price) then
        cb(false, L('error.payment_failed'))
        return
    end
    activeBalloons[src] = { netId = nil, dock = dock, seats = { nil, nil, nil, nil } }
    cb(true)
end)

-- Owner registers the spawned balloon network id. Validated so a client can't
-- claim ownership of someone else's balloon (or an arbitrary networked
-- entity) by reporting its netId here.
RegisterNetEvent('jrs_hotair:server:registerBalloon', function(netId)
    local src = source
    local data = activeBalloons[src]
    if not data then return end
    netId = tonumber(netId)
    if not netId or netId == 0 then return end
    if claimedNetIds[netId] then return end -- already owned by someone (or a stale claim)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then return end
    if GetEntityModel(entity) ~= GetHashKey(Config.Model) then return end
    -- must be the vehicle this player currently has network control of
    if NetworkGetEntityOwner(entity) ~= src then return end
    data.netId = netId
    claimedNetIds[netId] = src
end)

-- Owner reports spawn failure: refund + free the slot.
-- Only pays out if this player actually has an un-spawned hire pending --
-- otherwise this event could be spammed for free cash.
RegisterNetEvent('jrs_hotair:server:cancelHire', function()
    local src = source
    local data = activeBalloons[src]
    if not data or data.netId then return end
    local Player = GetPlayer(src)
    if Player then
        JRS.GiveMoney(src, Config.HirePrice)
    end
    ReleaseBalloon(src)
end)

local function WipeBalloonStorage() end -- JRS storage is personal and kept between hires

-- Owner stored the balloon: free the slot and wipe the storage that went
-- with it
RegisterNetEvent('jrs_hotair:server:storedBalloon', function()
    local src = source
    WipeBalloonStorage(src)
    ReleaseBalloon(src)
end)

-- Passenger requests a basket seat
JRS.CreateCallback('jrs_hotair:server:requestSeat', function(source, cb, netId)
    local src = source
    local ownerSrc, data = FindBalloonByNetId(tonumber(netId))
    if not data then
        cb(false, nil, L('error.balloon_unavailable'))
        return
    end
    if ownerSrc == src then
        cb(false, nil, L('error.use_pilot_option'))
        return
    end
    local entity = NetworkGetEntityFromNetworkId(data.netId)
    if not DoesEntityExist(entity) or not IsNearEntity(src, entity, Config.TargetDistance + 2.0) then
        cb(false, nil, L('error.too_far_from_balloon'))
        return
    end
    for i = 1, 4 do
        if data.seats[i] == src then
            cb(true, i) -- already seated (reattach)
            return
        end
    end
    for i = 1, 4 do
        if not data.seats[i] then
            data.seats[i] = src
            PushSeatUpdate(ownerSrc)
            cb(true, i)
            return
        end
    end
    cb(false, nil, L('error.basket_full'))
end)

-- Passenger leaves a basket seat
RegisterNetEvent('jrs_hotair:server:vacateSeat', function(netId, seat)
    local src = source
    seat = tonumber(seat)
    if not seat or seat < 1 or seat > 4 then return end
    local ownerSrc, data = FindBalloonByNetId(tonumber(netId))
    if not data then return end
    if data.seats[seat] == src then
        data.seats[seat] = nil
        PushSeatUpdate(ownerSrc)
    end
end)

-- Owner stored the balloon while passengers attached: force everyone off
RegisterNetEvent('jrs_hotair:server:disembarkAll', function(netId)
    local src = source
    local ownerSrc, data = FindBalloonByNetId(tonumber(netId))
    if not data or ownerSrc ~= src then return end
    for i = 1, 4 do
        if data.seats[i] then
            TriggerClientEvent('jrs_hotair:client:forceDisembark', data.seats[i])
            data.seats[i] = nil
        end
    end
end)

-- Balloon storage (JRS custom inventory per character).
-- A callback (not a fire-and-forget event) so a rejection is never silent --
-- the player always sees why nothing opened.
JRS.CreateCallback('jrs_hotair:server:openStorage', function(source, cb)
    local src = source

    if not GetPlayer(src) then
        cb(false, L('error.no_player_data'))
        return
    end
    local data = activeBalloons[src]
    if not data then
        cb(false, L('error.no_balloon_out'))
        return
    end
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if not DoesEntityExist(entity) or not IsNearEntity(src, entity, Config.TargetDistance + 2.0) then
            cb(false, L('error.too_far_from_balloon'))
            return
        end
    end

    local stashName = 'hotair_' .. tostring(JRS.CharId(src))
    exports.jrs_inventory:registerInventory({ id = stashName, name = L('storage.label'), limit = Config.StorageMaxSlots })
    exports.jrs_inventory:openInventory(src, stashName)
    cb(true)
end)

-- Cleanup on disconnect: free registry + force attached passengers off
AddEventHandler('playerDropped', function()
    local src = source
    local data = activeBalloons[src]
    if data then
        for i = 1, 4 do
            if data.seats[i] then
                TriggerClientEvent('jrs_hotair:client:forceDisembark', data.seats[i])
            end
        end
        ReleaseBalloon(src)
        return
    end
    -- dropped player may have been a passenger on someone else's balloon
    for ownerSrc, bdata in pairs(activeBalloons) do
        for i = 1, 4 do
            if bdata.seats[i] == src then
                bdata.seats[i] = nil
                PushSeatUpdate(ownerSrc)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        activeBalloons = {}
        claimedNetIds = {}
    end
end)
