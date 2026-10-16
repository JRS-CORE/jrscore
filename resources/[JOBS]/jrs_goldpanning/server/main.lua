-- jrs_goldpanning | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local panning = {}   -- source -> os.time() the pan started

JRS.Usable(Config.PanItem, function(src)
    if panning[src] then return JRS.Notify(src, L('busy')) end
    if not JRS.Cooldown(src, 'pan', Config.Cooldown) then return end
    panning[src] = os.time()
    JRS.CloseInventory(src)
    TriggerClientEvent('jrs_goldpanning:client:start', src)
end)

RegisterNetEvent('jrs_goldpanning:server:finish', function(success)
    local src = source
    local started = panning[src]
    panning[src] = nil
    if not started or success == nil then return end
    -- the animation + skill checks cannot be done faster than this
    if os.time() - started < Config.MinTime then return end
    if not JRS.Has(src, Config.PanItem) then return end

    if success ~= true then
        if math.random(100) <= Config.BreakChance and JRS.Remove(src, Config.PanItem, 1) then
            return JRS.Notify(src, L('broke'))
        end
        return JRS.Notify(src, L('nothing'))
    end

    local amount = math.random(Config.Reward.min, Config.Reward.max)
    if not JRS.Add(src, Config.Reward.item, amount) then return JRS.Notify(src, L('no_space')) end
    JRS.Notify(src, L('found', amount))
end)

AddEventHandler('playerDropped', function() panning[source] = nil end)
