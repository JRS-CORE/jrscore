-- jrs_hunting | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_hunting | server
-- Pays for hunting. Three kinds of sale, each verified before anything is given:
--   skinned  the player just skinned/plucked an animal in the field   -> a dead animal of that model is next to them
--   carcass  a whole animal handed in at a butcher                    -> that very entity, once, near the player and a butcher
--   pelt     a pelt handed in at a butcher                            -> paid by model and quality, near a butcher

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local skinnable, butchered = {}, {}
for _, def in ipairs(Config.Skinnable) do skinnable[def.model] = def end
for _, def in ipairs(Config.Butchered) do butchered[def.model] = def end

local usedEntity = {}       -- entities that already paid out
local lastSale   = {}       -- player -> time of the last sale

-- ------------------------------------------------------------------ job-locked butchers

CreateThread(function()
    if not (Config.JobLocked and Core.RegisterJobs) then return end
    local jobs = {}
    for _, shop in ipairs(Config.Butchers) do
        if shop.job and shop.job ~= '' then jobs[shop.job] = {} end
    end
    if next(jobs) then Core.RegisterJobs(jobs, GetCurrentResourceName()) end
end)

local function jobOf(src)
    local user = Core.getUser(src)
    local character = user and user.getUsedCharacter
    return character and character.job
end

Core.Callback.Register('jrs_hunting:GetPlayerJob', function(src, cb) cb(jobOf(src)) end)

-- the butcher the player stands at (the job check is part of it when butchers are job-locked)
local function butcherNear(src)
    local here = GetEntityCoords(GetPlayerPed(src))
    local job = Config.JobLocked and jobOf(src) or nil
    for _, shop in ipairs(Config.Butchers) do
        if #(here - shop.at) <= shop.radius + 7.0 then
            if not Config.JobLocked or shop.job == '' or shop.job == job then return shop end
        end
    end
end

-- ------------------------------------------------------------------ rewards

local function amountOf(entry)
    local amount = entry[2]
    if type(amount) == 'table' then return math.random(amount[1], amount[2]) end
    if type(amount) == 'number' and amount > 0 then return amount end
    return math.random(Config.DefaultAmount.min, Config.DefaultAmount.max)
end

-- money, gold, points and xp (scaled by `factor`); returns the text parts that were paid
local function payCurrency(character, reward, factor)
    local parts = {}
    local money = (reward.money or 0) * factor
    local gold = (reward.gold or 0) * factor
    local points = (reward.points or 0) * factor
    local xp = (reward.xp or 0) * factor

    if money ~= 0 then character.addCurrency(0, money); parts[#parts + 1] = Text.dollar .. ('%.2f'):format(money) end
    if gold ~= 0 then character.addCurrency(1, gold); parts[#parts + 1] = gold .. ' gold' end
    if points ~= 0 then character.addCurrency(2, points); parts[#parts + 1] = points .. ' points' end
    if xp ~= 0 then character.addXp(xp) end
    return parts
end

-- items; returns false (and tells the player) when the bag cannot take all of them
local function giveLoot(src, loot, verb)
    local rolled = {}
    for i, entry in ipairs(loot or {}) do
        rolled[i] = { item = entry[1], amount = amountOf(entry), label = entry[3] }
        if not exports.jrs_inventory:canCarryItem(src, rolled[i].item, rolled[i].amount) then
            Core.NotifyObjective(src, Text.bagFull, 4000)
            return false
        end
    end
    if #rolled == 0 then return true end

    local names = {}
    for _, line in ipairs(rolled) do
        exports.jrs_inventory:addItem(src, line.item, line.amount)
        names[#names + 1] = (line.label or line.item) .. ((line.amount > 1 and line.label) and 's' or '')
    end
    Core.NotifyRightTip(src, verb .. table.concat(names, Text.join), 5000)
    return true
end

local function qualityFactor(def, quality)
    if def.quality.poor and quality == def.quality.poor then return def.factor.poor or 1.0 end
    if def.quality.good and quality == def.quality.good then return def.factor.good or 1.0 end
    if def.quality.perfect and quality == def.quality.perfect then return def.factor.perfect or 1.0 end
    return 1.0
end

-- ------------------------------------------------------------------ checks

local function deadAnimalNear(src, model)
    local here = GetEntityCoords(GetPlayerPed(src))
    for _, ped in ipairs(GetAllPeds()) do
        if not usedEntity[ped] and GetEntityModel(ped) == model and GetEntityHealth(ped) <= 0
           and #(GetEntityCoords(ped) - here) <= 6.0 then
            return ped
        end
    end
end

-- returns the table to reward from, the multiplier, and the entity to delete (carcass only)
local function verify(src, kind, data)
    if type(data) ~= 'table' then return end
    local model = tonumber(data.model)
    if not model then return end

    if kind == 'skinned' then
        local def = skinnable[model]
        local ped = def and deadAnimalNear(src, model)
        if not ped then return end
        usedEntity[ped] = true
        return def, 1.0

    elseif kind == 'carcass' then
        local def = butchered[model]
        if not def or not butcherNear(src) then return end
        local netId = tonumber(data.netid)
        local body = netId and NetworkGetEntityFromNetworkId(netId) or 0
        if body == 0 or not DoesEntityExist(body) or usedEntity[body] or GetEntityModel(body) ~= model then return end
        if #(GetEntityCoords(body) - GetEntityCoords(GetPlayerPed(src))) > 15.0 then return end
        usedEntity[body] = true
        return def, 1.0, body

    elseif kind == 'pelt' then
        local def = butchered[model]
        if not def or not butcherNear(src) then return end
        return def, qualityFactor(def, tonumber(data.quality)), nil, true
    end
end

AddEventHandler('playerDropped', function() lastSale[source] = nil end)
AddEventHandler('entityRemoved', function(entity) usedEntity[entity] = nil end)

-- ------------------------------------------------------------------ the sale

Core.Callback.Register('jrs_hunting:sell', function(src, cb, kind, data)
    local user = Core.getUser(src)
    if not user then return cb(false) end

    local now = GetGameTimer()
    if lastSale[src] and now - lastSale[src] < 1500 then return cb(false) end

    local def, factor, body, isPelt = verify(src, kind, data)
    if not def then return cb(false) end
    lastSale[src] = now

    local character = user.getUsedCharacter

    -- items first: if the bag is full nothing is paid and the animal stays with the player
    local verb = kind == 'skinned' and Text.obtained or Text.received
    if not isPelt and not giveLoot(src, def.loot, verb) then
        if body then usedEntity[body] = nil end
        return cb(false)
    end

    local paid = payCurrency(character, def.reward, factor)
    if #paid > 0 then Core.NotifyObjective(src, Text.sold .. table.concat(paid, Text.join), 4000) end

    if body and DoesEntityExist(body) then DeleteEntity(body) end
    cb(true)
end)
