-- jrs_crawfish | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_crawfish | server
-- Two timed jobs, both checked here: searching a hole and harvesting a crawfish. A client first asks to
-- begin (we reserve the hole / the crawfish and fix the duration), later asks to finish (we check the
-- time really passed and the player is still in range), and only then give the items.

local Core = exports.jrs_core:GetCore()

local lastSearch = {}     -- hole index -> os.time() of the last search
local occupied   = {}     -- hole index -> player currently searching it
local jobs       = {}     -- player -> { kind = 'search'|'harvest', hole?, count?, readyAt }

local function bagLock(src, on) TriggerClientEvent('jrs_inventory:blockInventory', src, on) end

local function reach(src, hole)
    local at = Config.Holes[hole]
    return at and #(GetEntityCoords(GetPlayerPed(src)) - at) <= Config.HoleReach + 1.0
end

local function drop(src)
    local job = jobs[src]
    if not job then return end
    if job.kind == 'search' then occupied[job.hole] = nil end
    if job.kind == 'harvest' then bagLock(src, false) end
    jobs[src] = nil
end

-- ------------------------------------------------------------------ search

local function beginSearch(src, hole)
    if type(hole) ~= 'number' or not Config.Holes[hole] then return { ok = false } end
    if not reach(src, hole) then return { ok = false, why = Say('far') } end
    if occupied[hole] then return { ok = false, why = Say('busy') } end
    if lastSearch[hole] and os.time() < lastSearch[hole] + Config.SearchDelay then
        return { ok = false, why = Say('recent') }
    end

    local time = math.random(Config.SearchTime.min, Config.SearchTime.max)
    occupied[hole] = src
    jobs[src] = { kind = 'search', hole = hole, count = math.max(0, math.floor(RollAmount(Config.SearchCount))),
                  readyAt = GetGameTimer() + time - 1000 }
    return { ok = true, time = time, hole = hole }
end

local function pickExtras()
    local extra = Config.Extras
    if not (extra.enabled and #extra.pool > 0 and math.random(1, 100) <= extra.chance) then return {} end

    local bag = {}
    for i, entry in ipairs(extra.pool) do bag[i] = entry end
    local picked = {}
    for _ = 1, math.random(1, extra.most) do
        if #bag == 0 then break end
        local entry = table.remove(bag, math.random(#bag))
        local amount = RollAmount(entry.amount)
        if amount > 0 then picked[#picked + 1] = { item = entry.item, amount = amount } end
    end
    return picked
end

local function finishSearch(src, job)
    if not reach(src, job.hole) or GetGameTimer() < job.readyAt then
        return { ok = false, why = Say('notSearching') }
    end
    lastSearch[job.hole] = os.time()

    local result, foundMain, foundExtra = { ok = true }, false, false
    local main = Config.Crawfish

    if job.count > 0 then
        if exports.jrs_inventory:canCarryItem(src, main.item, job.count) then
            exports.jrs_inventory:addItem(src, main.item, job.count)
            foundMain = true
        else
            result = { ok = false, why = Say('noSpace') }
        end
    end

    for _, loot in ipairs(pickExtras()) do
        if exports.jrs_inventory:canCarryItem(src, loot.item, loot.amount) then
            exports.jrs_inventory:addItem(src, loot.item, loot.amount)
            foundExtra = true
        end
    end

    if foundMain then Core.NotifyObjective(src, Say('found', { count = job.count, item = main.label }), 5000) end
    if foundExtra then
        Core.NotifyRightTip(src, Say('foundExtra'), 5000)
        result = { ok = true }
    elseif not foundMain and result.ok then
        result = { ok = false, why = Say('foundNothing') }
    end
    return result
end

-- ------------------------------------------------------------------ harvest

local function beginHarvest(src)
    if jobs[src] and jobs[src].kind == 'harvest' then return { ok = false, why = Say('alreadyHarvesting') } end
    if exports.jrs_inventory:getItemCount(src, nil, Config.Crawfish.item) < 1 then
        bagLock(src, false)
        return { ok = false, why = Say('nothingToHarvest') }
    end
    jobs[src] = { kind = 'harvest', readyAt = GetGameTimer() + Config.HarvestTime - 1000 }
    return { ok = true, time = Config.HarvestTime }
end

local function finishHarvest(src, job)
    if GetGameTimer() < job.readyAt then return { ok = false, why = Say('notHarvesting') } end
    if not exports.jrs_inventory:subItem(src, Config.Crawfish.item, 1) then
        return { ok = false, why = Say('nothingToHarvest') }
    end

    local meat = Config.Meat
    local amount = RollAmount(meat.amount)
    if exports.jrs_inventory:canCarryItem(src, meat.item, amount) then
        exports.jrs_inventory:addItem(src, meat.item, amount)
        Core.NotifyObjective(src, Say('harvested', { count = amount, item = meat.label }), 5000)
        return { ok = true }
    end
    exports.jrs_inventory:addItem(src, Config.Crawfish.item, 1)       -- give the crawfish back
    return { ok = false, why = Say('noSpace') }
end

-- ------------------------------------------------------------------ client calls

Core.Callback.Register('jrs_crawfish:begin', function(src, cb, kind, hole)
    drop(src)
    if kind == 'search' then return cb(beginSearch(src, hole)) end
    if kind == 'harvest' then return cb(beginHarvest(src)) end
    cb({ ok = false })
end)

Core.Callback.Register('jrs_crawfish:finish', function(src, cb)
    local job = jobs[src]
    if not job then return cb({ ok = false, why = Say('notSearching') }) end
    jobs[src] = nil
    local result
    if job.kind == 'search' then
        occupied[job.hole] = nil
        result = finishSearch(src, job)
    else
        result = finishHarvest(src, job)
        bagLock(src, false)
    end
    cb(result)
end)

RegisterNetEvent('jrs_crawfish:abort', function() drop(source) end)
AddEventHandler('playerDropped', function() drop(source) end)

-- ------------------------------------------------------------------ using the item

AddEventHandler('onServerResourceStart', function(res)
    if res ~= GetCurrentResourceName() or Config.CustomUse then return end
    exports.jrs_inventory:registerUsableItem(Config.Crawfish.item, function(data)
        local src = data.source
        if jobs[src] and jobs[src].kind == 'harvest' then
            return Core.NotifyObjective(src, Say('alreadyHarvesting'), 5000)
        end
        exports.jrs_inventory:closeInventory(src)
        bagLock(src, true)
        TriggerClientEvent('jrs_crawfish:harvest', src)
    end)
end)
