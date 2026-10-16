-- jrs_robbery | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local Core = exports.jrs_core:GetCore()

local cuffedBy  = {}   -- victim -> robber
local robbing   = {}   -- robber -> victim
local cooldowns = {}   -- robber -> os.time() when allowed again

local function notify(src, key, ms)
    Core.NotifyRightTip(src, L(key), ms or 4000)
end

local function distance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return math.huge end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function character(src)
    local user = Core.getUser(src)
    return user and user.getUsedCharacter
end

local function release(victim, key)
    local robber = cuffedBy[victim]
    if not robber then return end
    cuffedBy[victim] = nil
    if robbing[robber] == victim then robbing[robber] = nil end
    Player(victim).state:set('jrs_robbery_cuffed', false, true)
    TriggerClientEvent('jrs_robbery:client:setCuffed', victim, false)
    if key then notify(victim, key) end
end

RegisterNetEvent('jrs_robbery:server:rob', function(target)
    local src = source
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return end
    if not character(src) or not character(target) then return end

    if cuffedBy[src] then return notify(src, 'you_cuffed') end
    if robbing[src] then return end
    if cooldowns[src] and os.time() < cooldowns[src] then return notify(src, 'cooldown') end
    if cuffedBy[target] then return notify(src, 'already_cuffed') end
    if distance(src, target) > Config.RobDistance then return notify(src, 'too_far') end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 or GetVehiclePedIsIn(GetPlayerPed(target), false) ~= 0 then
        return notify(src, 'in_vehicle')
    end
    if Player(target).state.jrs_handsup ~= true then return notify(src, 'not_handsup') end

    local victimJob = character(target).job
    if victimJob and Config.ProtectedJobs[victimJob] then return notify(src, 'protected') end

    if (tonumber(exports.jrs_inventory:getItemCount(src, nil, Config.HandcuffItem)) or 0) < 1 then
        return notify(src, 'need_cuffs')
    end
    if Config.ConsumeHandcuffs and not exports.jrs_inventory:subItem(src, Config.HandcuffItem, 1) then
        return notify(src, 'need_cuffs')
    end

    cooldowns[src] = os.time() + Config.RobCooldown
    cuffedBy[target] = src
    robbing[src] = target
    Player(target).state:set('jrs_robbery_cuffed', true, true)
    TriggerClientEvent('jrs_robbery:client:setCuffed', target, true)
    notify(target, 'being_robbed', 7000)
    notify(src, 'cuffing', 3000)

    SetTimeout(1200, function()
        if robbing[src] ~= target then return end
        exports.jrs_inventory:OpenPlayerInventoryAdmin(src, target, Config.SearchDistance)
    end)

    if Config.AutoUncuffTime > 0 then
        SetTimeout(Config.AutoUncuffTime * 1000, function()
            if cuffedBy[target] == src then release(target, 'broke_free') end
        end)
    end
end)

-- The robber closed the search window: let the victim go.
RegisterNetEvent('jrsCore:closestorage', function(id)
    local src = source
    local victim = robbing[src]
    if victim and tostring(id) == ('admin_search:%d'):format(victim) then
        release(victim, 'uncuffed_you')
    end
end)

RegisterNetEvent('jrs_robbery:server:uncuff', function(target)
    local src = source
    target = tonumber(target)
    if not target or not cuffedBy[target] then return notify(src, 'not_cuffed') end
    if cuffedBy[src] then return end
    if distance(src, target) > Config.RobDistance then return notify(src, 'too_far') end
    release(target, 'uncuffed_you')
    notify(src, 'uncuffed_other')
end)

AddEventHandler('playerDropped', function()
    local src = source
    if robbing[src] then release(robbing[src], 'broke_free') end
    if cuffedBy[src] then
        local robber = cuffedBy[src]
        cuffedBy[src] = nil
        if robbing[robber] == src then
            robbing[robber] = nil
            TriggerClientEvent('jrs_inventory:CloseInv', robber)
        end
    end
    cooldowns[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for victim in pairs(cuffedBy) do
        Player(victim).state:set('jrs_robbery_cuffed', false, true)
    end
end)
