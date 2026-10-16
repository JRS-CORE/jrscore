-- jrs_canoe | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_canoe | server
-- A store builds one canoe at a time. A player claims the store while the menu is open; the claim ends when
-- they leave, finish or drop.

local busyBy = {}                      -- store index -> player who has the store
BusyStores = {}                        -- store index -> true, read by the callbacks

function GetBusyStoresList() return BusyStores end

local function close(store) return (store.DistanceOpenStore or 3.0) + 5.0 end

RegisterServerEvent('jrs_canoe:server:start_building', function(index)
    local src = source
    local store = Config.Stores[tonumber(index) or index]
    if not store or busyBy[index] ~= src then return end
    local at = vector3(store.SpawnCoords.x, store.SpawnCoords.y, store.SpawnCoords.z)
    JRS.TriggerNearby('jrs_canoe:client:start_building', { index = index }, at, 50.0)
end)

RegisterServerEvent('jrs_canoe:server:setBusyState', function(index, claim)
    local src = source
    local store = Config.Stores[index]
    if not store then return end

    if claim == true then
        if (busyBy[index] and busyBy[index] ~= src) or not JRS.Near(src, store.Coords, close(store)) then return end
        busyBy[index], BusyStores[index] = src, true
    elseif busyBy[index] == src then
        busyBy[index], BusyStores[index] = nil, nil
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for index, who in pairs(busyBy) do
        if who == src then busyBy[index], BusyStores[index] = nil, nil end
    end
end)
