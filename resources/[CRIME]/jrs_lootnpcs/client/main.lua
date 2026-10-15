-- jrs_lootnpcs | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_lootnpcs | client
-- Watches for "loot finished" game events caused by this player and reports the body to the server,
-- which decides (and checks everything) about the reward.

local Game   <const> = Import 'events'
local reported       = {}            -- network ids already sent for this body

local LOOT_EVENT <const> = 'EVENT_LOOT_COMPLETE'

local watcher = Game.Events:Register(LOOT_EVENT, 0, function(args)
    local looter, body, finished = args[1], args[2], args[3]

    if finished ~= 1 or looter ~= CACHE.Ped then return end
    if not IsPedHuman(body) then return end
    if not Citizen.InvokeNative(0x8DE41E9902E85756, body) then return end   -- body is fully looted

    local netId = NetworkGetNetworkIdFromEntity(body)
    if reported[netId] then return end
    reported[netId] = true
    TriggerServerEvent('npcloot:give_reward', netId)
end, false)

-- only listen while a character is active and alive
RegisterNetEvent('jrs:SelectedCharacter', function() watcher:Start() end)
AddEventHandler('jrs_core:Client:OnPlayerDeath', function() watcher:Pause() end)
RegisterNetEvent('jrs_core:Client:OnPlayerRevive', function() watcher:Resume() end)

-- the server tells us when a body may pay out again
RegisterNetEvent('npcloot:looted', function(netId) reported[netId] = nil end)
