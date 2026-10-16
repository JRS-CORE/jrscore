-- jrs_hotair | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_hotair | server
-- Hiring a balloon costs money and is tracked per player: which dock, which network id, who sits in the
-- four passenger seats. The balloon itself is created by the client; the server checks every claim.

local rides = {}            -- owner source -> { netId, dock, seats = { [1..4] = source } }
local claimed = {}          -- netId -> owner source, so two owners can never claim the same balloon

local SEATS <const> = 4

local function say(key) return L(key) end

local function owner(netId)
    local src = claimed[netId]
    local ride = src and rides[src]
    if ride and ride.netId == netId then return src, ride end
end

local function seated(ride)
    local n = 0
    for i = 1, SEATS do if ride.seats[i] then n = n + 1 end end
    return n
end

local function tellSeats(src)
    local ride = rides[src]
    if not ride then return end
    local n = seated(ride)
    TriggerClientEvent('jrs_hotair:client:seatUpdate', src, n)
    for i = 1, SEATS do
        if ride.seats[i] then TriggerClientEvent('jrs_hotair:client:seatUpdate', ride.seats[i], n) end
    end
end

-- frees an owner's slot and their claim; callers decide about refunds and messages
local function release(src)
    local ride = rides[src]
    if not ride then return end
    if ride.netId and claimed[ride.netId] == src then claimed[ride.netId] = nil end
    rides[src] = nil
end

local function isClose(src, entity, range)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= range
end

local function eject(ride)
    for i = 1, SEATS do
        if ride.seats[i] then
            TriggerClientEvent('jrs_hotair:client:forceDisembark', ride.seats[i])
            ride.seats[i] = nil
        end
    end
end

-- ------------------------------------------------------------------ hiring

JRS.CreateCallback('jrs_hotair:server:hireBalloon', function(src, reply, dock)
    if rides[src] then return reply(false, say('error.already_have_balloon')) end

    dock = tonumber(dock)
    local spot = dock and Config.Docks[dock]
    if not spot then return reply(false, say('error.dock_unavailable')) end

    if not JRS.Char(src) then return reply(false, say('error.no_player_data')) end
    -- only at the dock (the menu can also be opened with /hotair within 50 m)
    if not JRS.Near(src, spot.npcCoords, 60.0) then return reply(false, say('error.dock_unavailable')) end

    if JRS.Money(src) < Config.HirePrice then return reply(false, say('error.not_enough_cash')) end
    if not JRS.TakeMoney(src, Config.HirePrice) then return reply(false, say('error.payment_failed')) end

    rides[src] = { netId = nil, dock = dock, seats = {} }
    reply(true)
end)

-- the owner reports the balloon they spawned; it must really be that model and owned by them
RegisterNetEvent('jrs_hotair:server:registerBalloon', function(netId)
    local src = source
    local ride = rides[src]
    netId = tonumber(netId)
    if not ride or not netId or netId == 0 or claimed[netId] then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) or GetEntityModel(entity) ~= joaat(Config.Model) then return end
    if NetworkGetEntityOwner(entity) ~= src then return end

    ride.netId = netId
    claimed[netId] = src
end)

-- spawning failed: refund, but only while a hire is really waiting for its balloon
RegisterNetEvent('jrs_hotair:server:cancelHire', function()
    local src = source
    local ride = rides[src]
    if not ride or ride.netId then return end
    if JRS.Char(src) then JRS.GiveMoney(src, Config.HirePrice) end
    release(src)
end)

RegisterNetEvent('jrs_hotair:server:storedBalloon', function()
    release(source)
end)

-- ------------------------------------------------------------------ passengers

JRS.CreateCallback('jrs_hotair:server:requestSeat', function(src, reply, netId)
    local ownerSrc, ride = owner(tonumber(netId))
    if not ride then return reply(false, nil, say('error.balloon_unavailable')) end
    if ownerSrc == src then return reply(false, nil, say('error.use_pilot_option')) end

    local entity = NetworkGetEntityFromNetworkId(ride.netId)
    if not DoesEntityExist(entity) or not isClose(src, entity, Config.TargetDistance + 2.0) then
        return reply(false, nil, say('error.too_far_from_balloon'))
    end

    for i = 1, SEATS do
        if ride.seats[i] == src then return reply(true, i) end          -- sitting already, just reattach
    end
    for i = 1, SEATS do
        if not ride.seats[i] then
            ride.seats[i] = src
            tellSeats(ownerSrc)
            return reply(true, i)
        end
    end
    reply(false, nil, say('error.basket_full'))
end)

RegisterNetEvent('jrs_hotair:server:vacateSeat', function(netId, seat)
    local src = source
    seat = tonumber(seat)
    if not seat or seat < 1 or seat > SEATS then return end
    local ownerSrc, ride = owner(tonumber(netId))
    if ride and ride.seats[seat] == src then
        ride.seats[seat] = nil
        tellSeats(ownerSrc)
    end
end)

-- the owner stores the balloon while people are in the basket
RegisterNetEvent('jrs_hotair:server:disembarkAll', function(netId)
    local ownerSrc, ride = owner(tonumber(netId))
    if ride and ownerSrc == source then eject(ride) end
end)

-- ------------------------------------------------------------------ storage

-- a callback, so a refusal always tells the player why nothing opened
JRS.CreateCallback('jrs_hotair:server:openStorage', function(src, reply)
    if not JRS.Char(src) then return reply(false, say('error.no_player_data')) end
    local ride = rides[src]
    if not ride then return reply(false, say('error.no_balloon_out')) end

    if ride.netId then
        local entity = NetworkGetEntityFromNetworkId(ride.netId)
        if not DoesEntityExist(entity) or not isClose(src, entity, Config.TargetDistance + 2.0) then
            return reply(false, say('error.too_far_from_balloon'))
        end
    end

    local stash = 'hotair_' .. tostring(JRS.CharId(src))
    exports.jrs_inventory:registerInventory({ id = stash, name = L('storage.label'), limit = Config.StorageMaxSlots })
    exports.jrs_inventory:openInventory(src, stash)
    reply(true)
end)

-- ------------------------------------------------------------------ leaving

AddEventHandler('playerDropped', function()
    local src = source
    local mine = rides[src]
    if mine then
        eject(mine)
        return release(src)
    end
    -- the player may have been a passenger on somebody else's balloon
    for ownerSrc, ride in pairs(rides) do
        for i = 1, SEATS do
            if ride.seats[i] == src then
                ride.seats[i] = nil
                tellSeats(ownerSrc)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then rides, claimed = {}, {} end
end)
