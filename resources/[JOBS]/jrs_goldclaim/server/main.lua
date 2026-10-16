-- jrs_goldclaim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_goldclaim | server
-- Rockers are rows in `jrs_goldrockers` mirrored in Config.PlayerProps. Every action checks that the
-- player is at the rocker, has the items and is not repeating a request too fast. Output (gold, paydirt)
-- only exists if the server produced it for that character.

local loaded = false
local processing = {}       -- prop id -> char id of the player running the rocker
local pending = {}          -- prop id -> { cid, gold, paydirt }: outputs waiting to be picked up
local lastAt = {}           -- player -> key -> game timer until which the action is on cooldown

-- ------------------------------------------------------------------ small helpers

local function tell(src, title, text, _, _, ms)
    JRS.Notify(src, text and (title .. ': ' .. text) or title, ms or Config.NotifyDuration)
end

-- the Discord log is not part of this edition
local Log = { Log = function() end, Suspicious = function() end }

local function debug(...) if Config.Debug then print('[jrs_goldclaim]', ...) end end

-- true when `key` was done too recently (and starts the cooldown otherwise)
local function tooSoon(src, key, ms)
    lastAt[src] = lastAt[src] or {}
    local now = GetGameTimer()
    if (lastAt[src][key] or 0) > now then return true end
    lastAt[src][key] = now + ms
    return false
end

local function give(src, item, amount)
    if not JRS.CanCarry(src, item, amount) then
        tell(src, L('rocker_inventory_full'))
        return false
    end
    return exports.jrs_inventory:addItem(src, item, amount) == true
end

local function take(src, item, amount)
    if JRS.Count(src, item) < amount then return false end
    return JRS.Remove(src, item, amount)
end

local function who(src)
    local char = JRS.Char(src)
    if not char then return nil end
    return { src = src, cid = tostring(char.charIdentifier), first = char.firstname or '', last = char.lastname or '', job = char.job }
end

local function propOf(id)
    for i, p in ipairs(Config.PlayerProps) do
        if p.id == id then return p, i end
    end
end

local function near(src, at, radius)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - at) <= radius
end

local function nearProp(src, p, radius)
    return p ~= nil and near(src, vector3(p.x, p.y, p.z), radius or Config.InteractDistance)
end

-- the player, the rocker and its id, once the player really is at the rocker
local function check(src, propid, radius)
    local player = who(src)
    propid = tonumber(propid)
    local p = player and propid and propOf(propid)
    if not p then return end

    if not nearProp(src, p, radius) then
        tell(src, L('rocker_too_far'))
        return
    end
    return player, p, propid
end

-- oxmysql gives tinyint(1) as a boolean
local function flag(v) return (v == true or v == 1) and 1 or 0 end

local function broadcast(target)
    TriggerClientEvent('jrs_goldclaim:rocker:client:updatePropData', target or -1, Config.PlayerProps)
end

local function removeRocker(propid)
    local _, index = propOf(propid)
    if index then table.remove(Config.PlayerProps, index) end
    processing[propid], pending[propid] = nil, nil
    TriggerClientEvent('jrs_goldclaim:rocker:client:removePropObject', -1, propid)
    MySQL.update('DELETE FROM jrs_goldrockers WHERE propid = ?', { propid })
end

-- ------------------------------------------------------------------ start up and data for clients

CreateThread(function()
    Config.PlayerProps = {}
    for _, row in ipairs(MySQL.query.await('SELECT properties, licensed, claimname FROM jrs_goldrockers') or {}) do
        local p = json.decode(row.properties)
        if p then
            p.licensed, p.claimname, p.hash = flag(row.licensed), row.claimname, Config.GoldRocker
            Config.PlayerProps[#Config.PlayerProps + 1] = p
            debug('loaded rocker', p.id)
        end
    end
    loaded = true
    broadcast()
end)

JRS.Callback('jrs_goldclaim:server:getprops', function()
    while not loaded do Wait(100) end
    return Config.PlayerProps
end)

-- outputs of this character that were never picked up (so they survive a relog)
JRS.Callback('jrs_goldclaim:server:getpending', function(src)
    local player = who(src)
    local list = {}
    for propid, p in pairs(pending) do
        if player and p.cid == player.cid then list[#list + 1] = { propid = propid, gold = p.gold, paydirt = p.paydirt } end
    end
    return list
end)

JRS.Callback('jrs_goldclaim:server:countprops', function(src)
    local player = who(src)
    local n = 0
    for _, p in ipairs(Config.PlayerProps) do
        if player and p.builder == player.cid then n = n + 1 end
    end
    return n
end)

JRS.Callback('jrs_goldclaim:server:getrockerdata', function(src, propid)
    propid = tonumber(propid)
    local p = propid and propOf(propid)
    if not p or not nearProp(src, p, Config.ClaimZoneRadius) then return nil end

    local row = MySQL.single.await('SELECT propid, citizenid, owner, licensed, claimname, paydirt, water, quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    if row then
        row.processing = processing[propid] ~= nil
        row.licensed = flag(row.licensed)
    end
    return row
end)

JRS.Callback('jrs_goldclaim:server:me', function(src)
    local player = who(src)
    return player and { id = player.cid, job = player.job } or nil
end)

JRS.Callback('jrs_goldclaim:server:hasitem', function(src, item, amount)
    return type(item) == 'string' and JRS.Count(src, item) >= (tonumber(amount) or 1)
end)

AddEventHandler('playerDropped', function() lastAt[source] = nil end)

-- ------------------------------------------------------------------ usable items

JRS.Usable('goldrocker', function(src) TriggerClientEvent('jrs_goldclaim:rocker:client:createprop', src) end)
JRS.Usable('rocker_shovel', function(src) TriggerClientEvent('jrs_goldclaim:rocker:client:useshovel', src) end)
JRS.Usable('rocker_bucket', function(src) TriggerClientEvent('jrs_goldclaim:rocker:client:usebucket', src) end)

-- ------------------------------------------------------------------ gathering

RegisterNetEvent('jrs_goldclaim:rocker:server:digpaydirt', function()
    local src = source
    if not who(src) or tooSoon(src, 'gather', Config.ShovelDigTime - 500) then return end
    if JRS.Count(src, 'rocker_shovel') < 1 then return end
    give(src, 'paydirt', 1)
end)

RegisterNetEvent('jrs_goldclaim:rocker:server:fillbucket', function()
    local src = source
    if not who(src) or tooSoon(src, 'gather', Config.BucketFillTime - 500) then return end
    if JRS.Count(src, 'rocker_bucket') < 1 then return end

    if take(src, 'rocker_bucket', 1) and not give(src, 'rocker_bucket_full', 1) then
        give(src, 'rocker_bucket', 1)                    -- no room for the full one: give the empty bucket back
    end
end)

-- ------------------------------------------------------------------ placing, packing up, confiscating

RegisterNetEvent('jrs_goldclaim:rocker:server:newProp', function(location, heading)
    local src = source
    local player = who(src)
    if not player or tooSoon(src, 'place', 3000) then return end

    if type(location) ~= 'vector3' and (type(location) ~= 'table' or type(location.x) ~= 'number') then return end
    location = vector3(location.x + 0.0, location.y + 0.0, location.z + 0.0)
    heading = (tonumber(heading) or 0.0) % 360.0

    if not near(src, location, Config.PlaceMaxDistance) then
        tell(src, L('rocker_too_far'))
        return
    end

    local owned = 0
    for _, p in ipairs(Config.PlayerProps) do
        if p.builder == player.cid then owned = owned + 1 end
        if #(location - vector3(p.x, p.y, p.z)) < Config.MinRockerSpacing then return tell(src, L('rocker_too_close_other')) end
    end
    if owned >= Config.MaxGoldRockers then return tell(src, L('rocker_max_equipment')) end

    if not take(src, 'goldrocker', 1) then return end

    local owner = ('%s %s'):format(player.first, player.last)
    local licensed, claim = 0, nil
    if JRS.Count(src, Config.LicenseItem) > 0 and take(src, Config.LicenseItem, 1) then
        licensed, claim = 1, L('rocker_claim_default_name', owner)
    end

    local id
    repeat id = math.random(111111, 999999) until not propOf(id)

    local p = {
        id = id, proptype = 'goldrocker', x = location.x, y = location.y, z = location.z, h = heading,
        hash = Config.GoldRocker, builder = player.cid, buildtime = os.time(), licensed = licensed, claimname = claim,
    }
    Config.PlayerProps[#Config.PlayerProps + 1] = p
    MySQL.insert('INSERT INTO jrs_goldrockers (properties, propid, citizenid, owner, proptype, licensed, claimname) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { json.encode(p), id, player.cid, owner, 'goldrocker', licensed, claim })
    broadcast()

    if licensed == 0 then tell(src, L('rocker_unlicensed_notice_title'), L('rocker_unlicensed_notice_desc'), nil, nil, 10000) end
end)

-- the owner takes the rocker back (it has to be in perfect shape)
RegisterNetEvent('jrs_goldclaim:rocker:server:destroyProp', function(propid)
    local src = source
    local player, p
    player, p, propid = check(src, propid)
    if not player or p.builder ~= player.cid or tooSoon(src, 'packup', 2000) then return end

    local row = MySQL.single.await('SELECT quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    if not propOf(propid) then return end                 -- gone while we waited: no second item
    if not row or row.quality < 100 then return tell(src, L('rocker_needs_repair')) end
    if not JRS.CanCarry(src, 'goldrocker', 1) then return tell(src, L('rocker_inventory_full')) end

    removeRocker(propid)
    give(src, 'goldrocker', 1)
    tell(src, L('rocker_packed_up'))
end)

-- police take an unlicensed rocker as evidence
RegisterNetEvent('jrs_goldclaim:rocker:server:leodestroy', function(propid)
    local src = source
    local player, p
    player, p, propid = check(src, propid)
    if not player or not Config.LeoJobs[player.job or ''] or p.licensed == 1 then return end

    removeRocker(propid)
    give(src, 'goldrocker', 1)
    tell(src, L('rocker_claim_destroyed'), L('rocker_evidence_collected'))
end)

-- ------------------------------------------------------------------ loading and running a rocker

-- adds one paydirt / one water; the update is conditional, so a rocker filled by somebody else meanwhile refunds
local function load(src, propid, column, max, item, fullKey, okKey, returned, duration)
    local player, _p
    player, _p, propid = check(src, propid)
    if not player or tooSoon(src, 'load', duration - 1000) or JRS.Count(src, item) < 1 then return end

    local row = MySQL.single.await(('SELECT %s AS amount FROM jrs_goldrockers WHERE propid = ?'):format(column), { propid })
    if not row then return end
    if row.amount >= max then return tell(src, L(fullKey)) end
    if not take(src, item, 1) then return end

    local changed = MySQL.update.await(('UPDATE jrs_goldrockers SET %s = %s + 1 WHERE propid = ? AND %s < ?'):format(column, column, column), { propid, max })
    if not changed or changed < 1 then
        give(src, item, 1)
        return tell(src, L(fullKey))
    end
    if returned then give(src, returned, 1) end
    tell(src, L(okKey), L('rocker_level', math.min(row.amount + 1, max), max))
end

RegisterNetEvent('jrs_goldclaim:rocker:server:addpaydirt', function(propid)
    load(source, propid, 'paydirt', Config.MaxPaydirt, 'paydirt', 'rocker_paydirt_full', 'rocker_paydirt_added', nil, Config.AddPaydirtTime)
end)

RegisterNetEvent('jrs_goldclaim:rocker:server:addwater', function(propid)
    load(source, propid, 'water', Config.MaxWater, 'rocker_bucket_full', 'rocker_water_full', 'rocker_water_added', 'rocker_bucket', Config.AddWaterTime)
end)

-- the reason a rocker cannot run now, or nil
local function cannotRun(row)
    if row.quality <= 0 then return 'rocker_needs_repair' end
    if row.water <= 0 then return 'rocker_processing_no_water' end
    if row.paydirt <= 0 then return 'rocker_processing_no_paydirt' end
end

-- one cycle every Config.ProcessingTime: uses a water and a paydirt, produces gold or paydirt
local function runCycles(src, propid, cid)
    while true do
        Wait(Config.ProcessingTime)

        -- stop if the rocker is gone or the player left, before anything is used up
        local player = who(src)
        if not propOf(propid) or not player or player.cid ~= cid then break end

        local used = MySQL.update.await('UPDATE jrs_goldrockers SET water = water - 1, paydirt = paydirt - 1 WHERE propid = ? AND water > 0 AND paydirt > 0 AND quality > 0', { propid })
        if not used or used < 1 then break end

        local kind = math.random(1, 100) <= Config.GoldChance and 'gold' or 'paydirt'
        local box = pending[propid]
        if not box or box.cid ~= cid then
            box = { cid = cid, gold = 0, paydirt = 0 }
            pending[propid] = box
        end
        box[kind] = box[kind] + 1
        TriggerClientEvent('jrs_goldclaim:rocker:client:spawnoutputprop', src, propid, kind)
    end

    processing[propid] = nil
    if GetPlayerPed(src) ~= 0 then TriggerClientEvent('jrs_goldclaim:rocker:client:processingcomplete', src, propid) end
end

RegisterNetEvent('jrs_goldclaim:rocker:server:processrocker', function(propid)
    local src = source
    local player, p
    player, p, propid = check(src, propid)
    if not player then return end

    if Config.OwnerOnlyProcessing and p.builder ~= player.cid then return tell(src, L('rocker_not_owner')) end
    if processing[propid] then return tell(src, L('rocker_already_processing_title'), L('rocker_already_processing_desc')) end

    processing[propid] = player.cid                       -- claimed before the query so two requests cannot both start
    local row = MySQL.single.await('SELECT water, paydirt, quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    local why = row and propOf(propid) and cannotRun(row)
    if not row or not propOf(propid) or why then
        processing[propid] = nil
        if why then tell(src, L(why)) end
        return
    end

    tell(src, L('rocker_processing_started'), L('rocker_processing_will_run', math.min(row.water, row.paydirt)))
    CreateThread(function() runCycles(src, propid, player.cid) end)
end)

-- ------------------------------------------------------------------ picking up the output

-- takes one `kind` out of the character's pending output; nil when the server never produced it
local function claim(src, propid, kind)
    local player, _p
    player, _p, propid = check(src, propid, Config.PickupDistance)
    local box = player and pending[propid]
    if not box or box.cid ~= player.cid or box[kind] < 1 then return end
    box[kind] = box[kind] - 1
    return propid, box
end

-- a pickup that did not fit is put back and the prop spawns again
local function keep(src, propid, box, kind)
    box[kind] = box[kind] + 1
    TriggerClientEvent('jrs_goldclaim:rocker:client:spawnoutputprop', src, propid, kind, true)
end

RegisterNetEvent('jrs_goldclaim:rocker:server:pickupgold', function(propid)
    local src = source
    local id, box = claim(src, propid, 'gold')
    if not id then return end

    local amount = math.random(Config.GoldOreAmount.min, Config.GoldOreAmount.max)
    if give(src, Config.GoldOreItem, amount) then
        TriggerClientEvent('jrs_goldclaim:rocker:client:goldpickupresult', src, amount)
    else
        keep(src, id, box, 'gold')
    end
end)

RegisterNetEvent('jrs_goldclaim:rocker:server:pickuppaydirt', function(propid)
    local src = source
    local id, box = claim(src, propid, 'paydirt')
    if id and not give(src, 'paydirt', 1) then keep(src, id, box, 'paydirt') end
end)

-- ------------------------------------------------------------------ repairs and names

RegisterNetEvent('jrs_goldclaim:rocker:server:repairrocker', function(propid)
    local src = source
    local player, _p
    player, _p, propid = check(src, propid)
    if not player or tooSoon(src, 'repair', Config.RepairTime - 1000) then return end

    local row = MySQL.single.await('SELECT quality FROM jrs_goldrockers WHERE propid = ?', { propid })
    if not row or row.quality >= 100 then return end
    if JRS.Count(src, 'wood') < Config.RepairWoodAmount then return tell(src, L('rocker_not_enough_wood', Config.RepairWoodAmount)) end

    if take(src, 'wood', Config.RepairWoodAmount) then
        MySQL.update('UPDATE jrs_goldrockers SET quality = 100 WHERE propid = ?', { propid })
        tell(src, L('rocker_repaired'))
    end
end)

-- a name without control characters or markup, three to MaxClaimNameLength characters
local function cleanName(text)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[%c<>]', ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if #text < 3 or #text > Config.MaxClaimNameLength then return nil end
    return text
end

RegisterNetEvent('jrs_goldclaim:rocker:server:renameclaim', function(propid, newName)
    local src = source
    local player, p
    player, p, propid = check(src, propid, Config.ClaimZoneRadius)
    if not player or p.builder ~= player.cid or p.licensed ~= 1 or tooSoon(src, 'rename', 5000) then return end

    local name = cleanName(newName)
    if not name then return tell(src, L('rocker_rename_invalid', Config.MaxClaimNameLength)) end

    MySQL.update('UPDATE jrs_goldrockers SET claimname = ? WHERE propid = ?', { name, propid })
    p.claimname = name
    TriggerClientEvent('jrs_goldclaim:rocker:client:refreshclaim', -1, propid, name)
    tell(src, L('rocker_claim_renamed'), name)
end)

-- ------------------------------------------------------------------ wear

-- rockers that reached 0% are removed, the others may lose a point
CreateThread(function()
    while true do
        Wait(Config.DegradeEvery * 60000)

        local broken = MySQL.query.await('SELECT propid FROM jrs_goldrockers WHERE quality <= 0') or {}
        for _, row in ipairs(broken) do removeRocker(row.propid) end

        MySQL.update('UPDATE jrs_goldrockers SET quality = quality - 1 WHERE quality > 0 AND RAND() * 100 < ?', { Config.DegradeChance })
        if #broken > 0 then broadcast() end
        debug('wear ran')
    end
end)
