-- jrs_stables | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- JRS Stables | Wagon ownership and storage.
-- Written by the JRS TEAM.
local Core = exports.jrs_core:GetCore()
local Settings = Config.Wagons
local ready, locks, active, activeById, models, cargoCounts = false, {}, {}, {}, {}, {}
for _, category in ipairs(StableWagons) do
    for model,cfg in pairs(category.types) do models[model] = cfg end
end

local function character(src)
    local user = Core.getUser(tonumber(src))
    local c = user and user.getUsedCharacter
    if c and c.identifier and c.charIdentifier then return c end
end
local function identity(c) return tostring(c.identifier) .. ':' .. tostring(c.charIdentifier) end
local function ok(data) return { ok=true, data=data } end
local function fail(code) return { ok=false, code=code or 'invalid' } end
local function integer(value)
    local n = tonumber(value)
    if n and n > 0 and n % 1 == 0 and n < 2147483647 then return n end
end
local function cleanName(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    local count = utf8.len(value)
    if value == '' or not count or count > 30 then return nil end
    return value
end
local function owned(c, id)
    id = integer(id)
    if not id then return nil end
    return MySQL.single.await('SELECT * FROM player_wagons WHERE id = ? AND identifier = ? AND charid = ? LIMIT 1',
        { id, c.identifier, c.charIdentifier })
end
local function matchesJob(c, jobs)
    if type(jobs) ~= 'table' or next(jobs) == nil then return true end
    for _, job in pairs(jobs) do
        if type(job) == 'string' and c.job == job then return true end
        if type(job) == 'table' and c.job == job.name and (tonumber(c.jobGrade) or 0) >= (tonumber(job.grade) or 0) then return true end
    end
    return false
end
local function limit(c)
    if c.job == Settings.wainwrightJob and (tonumber(c.jobGrade) or 0) >= Settings.wainwrightGrade then
        return Settings.maxWainwrightWagons
    end
    return Settings.maxPlayerWagons
end
local function count(c)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM player_wagons WHERE identifier = ? AND charid = ?',
        { c.identifier, c.charIdentifier })) or 0
end
local function nearby(src, coords, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and DoesEntityExist(ped) and #(GetEntityCoords(ped) - coords) <= distance
end
local function shop(src, c, site)
    local cfg = type(site) == 'string' and Stables[site]
    if not cfg or not nearby(src, cfg.npc.coords, Settings.shopDistance) then return false end
    if cfg.shop.jobsEnabled and not matchesJob(c, cfg.shop.jobs) then return false end
    return true
end
local function conditionMax(model)
    return math.max(1, tonumber(models[model] and models[model].condition.maxAmount) or 100)
end
local function boundedCondition(row)
    return math.max(0, math.min(tonumber(row.condition) or conditionMax(row.model), conditionMax(row.model)))
end
local function liveWagon(id)
    local src = activeById[integer(id)]
    local entry = src and active[src]
    if not entry or entry.netId == 0 then return nil end
    local entity = NetworkGetEntityFromNetworkId(entry.netId)
    if entity == 0 or not DoesEntityExist(entity) then return nil end
    local c = character(src)
    if not c or identity(c) ~= entry.owner then return nil end
    return entry, entity
end
local function nearWagon(src, id)
    local entry,entity = liveWagon(id)
    if not entry then return nil end
    if not nearby(src, GetEntityCoords(entity), tonumber(models[entry.model].distance) or 5) then return nil end
    return entry, entity
end
local function forget(src, removeEntity)
    local entry = active[src]
    if not entry then return end
    activeById[entry.id], active[src] = nil, nil
    if removeEntity and entry.netId ~= 0 then
        local entity = NetworkGetEntityFromNetworkId(entry.netId)
        if entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end
local function exclusive(src, fn)
    local c = character(src)
    if not ready or not Settings.enabled then return fail('unavailable') end
    if not c then return fail('forbidden') end
    local key = identity(c)
    if locks[key] then return fail('busy') end
    locks[key] = true
    local success,result = xpcall(function() return fn(c) end, debug.traceback)
    locks[key] = nil
    if not success then
        print('[jrs_stables] Wagon action failed: ' .. tostring(result))
        return fail('unavailable')
    end
    return result or fail('invalid')
end
local function register(name, fn)
    Core.Callback.Register('jrs_stables:wagon:' .. name, function(src, cb, data)
        cb(exclusive(src, function(c) return fn(src, c, type(data) == 'table' and data or {}) end))
    end)
end

MySQL.ready(function()
    local success,err = pcall(function()
        MySQL.query.await(LoadResourceFile(GetCurrentResourceName(), 'sql/wagons.sql'))
        local columns = MySQL.query.await('SHOW COLUMNS FROM player_wagons') or {}
        local hasCondition = false
        for _, column in ipairs(columns) do if column.Field == 'condition' then hasCondition = true end end
        if not hasCondition then MySQL.query.await('ALTER TABLE player_wagons ADD COLUMN `condition` DOUBLE NOT NULL DEFAULT 100') end
        -- An existing legacy table keeps its ownership, IDs, selections and names.
        ready = true
    end)
    if not success then print('^1[jrs_stables] Wagon database is unavailable: ' .. tostring(err) .. '^7') end
end)

register('menu', function(src, c, data)
    local catalog = {}
    if shop(src, c, data.site) then
        for _, category in ipairs(StableWagons) do
            local colors = {}
            for model,cfg in pairs(category.types) do
                if matchesJob(c, cfg.job) then
                    colors[model] = { color=WagonLabel(cfg.label,src), cashPrice=cfg.cashPrice, goldPrice=cfg.goldPrice }
                end
            end
            if next(colors) then catalog[#catalog+1] = { breed=WagonLabel(category.name,src), colors=colors } end
        end
    end
    local rows = MySQL.query.await('SELECT * FROM player_wagons WHERE identifier = ? AND charid = ? ORDER BY id',
        { c.identifier, c.charIdentifier }) or {}
    for _,row in ipairs(rows) do
        row.condition = boundedCondition(row)
        row.maxCondition = conditionMax(row.model)
        row.components, row.gender = '{}', 'male' -- Legacy stable view contract; no gender choice for wagons.
    end
    return ok({ catalog=catalog, owned=rows, activeId=active[src] and active[src].id,
        language=StableLanguage(src), limit=limit(c) })
end)

register('buy', function(src, c, data)
    local cfg = models[data.model]
    local name = cleanName(data.name)
    if not cfg or not name or type(data.cash) ~= 'boolean' then return fail('invalid') end
    if not shop(src, c, data.site) then return fail('tooFar') end
    if not matchesJob(c, cfg.job) then return fail('job') end
    if WagonSites[data.site] and WagonSites[data.site].wainwrightBuy
        and (c.job ~= Settings.wainwrightJob or (tonumber(c.jobGrade) or 0) < Settings.wainwrightGrade) then return fail('job') end
    if count(c) >= limit(c) then return fail('limit') end
    if Settings.currencyType == 0 and not data.cash or Settings.currencyType == 1 and data.cash then return fail('invalid') end
    local currency = data.cash and 0 or 1
    local price = tonumber(data.cash and cfg.cashPrice or cfg.goldPrice)
    if not price or price < 0 or price ~= price then return fail('invalid') end
    if (tonumber(data.cash and c.money or c.gold) or 0) < price then return fail(data.cash and 'cash' or 'gold') end
    if price > 0 and c.removeCurrency(currency, price) ~= true then return fail(data.cash and 'cash' or 'gold') end
    local success,id = pcall(MySQL.insert.await,
        'INSERT INTO player_wagons (identifier, charid, selected, name, model, `condition`) VALUES (?, ?, 0, ?, ?, ?)',
        { c.identifier, c.charIdentifier, name, data.model, conditionMax(data.model) })
    if not success or not id then
        if price > 0 then c.addCurrency(currency, price) end
        return fail('unavailable')
    end
    return ok({ id=id, name=name, model=data.model })
end)

register('rename', function(src, c, data)
    local row, name = owned(c, data.id), cleanName(data.name)
    if not row then return fail('forbidden') end
    if not name then return fail('invalid') end
    MySQL.update.await('UPDATE player_wagons SET name = ? WHERE id = ? AND identifier = ? AND charid = ?',
        { name, row.id, c.identifier, c.charIdentifier })
    return ok()
end)

register('select', function(src, c, data)
    local row = owned(c, data.id)
    if not row then return fail('forbidden') end
    local saved = MySQL.transaction.await({
        { query='UPDATE player_wagons SET selected = 0 WHERE identifier = ? AND charid = ?', values={ c.identifier, c.charIdentifier } },
        { query='UPDATE player_wagons SET selected = 1 WHERE id = ? AND identifier = ? AND charid = ?', values={ row.id, c.identifier, c.charIdentifier } },
    })
    return saved and ok({ id=row.id, condition=boundedCondition(row), maxCondition=conditionMax(row.model) }) or fail('unavailable')
end)

register('sell', function(src, c, data)
    if not shop(src, c, data.site) then return fail('tooFar') end
    local row = owned(c, data.id)
    if not row then return fail('forbidden') end
    if activeById[row.id] then return fail('returnFirst') end
    local cfg = models[row.model]
    if not cfg then return fail('invalid') end
    local items = MySQL.scalar.await('SELECT items FROM jrs_inventory_storage WHERE identifier = ? LIMIT 1', { 'jrs:wagonID_' .. row.id })
    if items then
        local success, contents = pcall(json.decode, items)
        if not success or type(contents) ~= 'table' or next(contents) then return fail('emptyCargo') end
    end
    local paid = math.floor(math.max(0, tonumber(cfg.cashPrice) or 0) * math.max(0, math.min(1, Settings.sellPrice)) * 100) / 100
    local deleted = MySQL.update.await('DELETE FROM player_wagons WHERE id = ? AND identifier = ? AND charid = ?',
        { row.id, c.identifier, c.charIdentifier })
    if deleted ~= 1 then return fail('unavailable') end
    if paid > 0 and c.addCurrency(0, paid) ~= true then
        -- Restore the row on a failed currency write, keeping the same cargo ID.
        MySQL.insert.await('INSERT INTO player_wagons (id, identifier, charid, selected, name, model, `condition`) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { row.id, row.identifier, row.charid, row.selected, row.name, row.model, boundedCondition(row) })
        return fail('unavailable')
    end
    exports.jrs_inventory:deleteCustomInventory('wagonID_' .. row.id)
    return ok({ cash=paid })
end)

register('prepare', function(src, c, data)
    if not Settings.callEnabled and not shop(src, c, data.site) then return fail('tooFar') end
    local row
    if data.id then row = owned(c, data.id)
    else row = MySQL.single.await('SELECT * FROM player_wagons WHERE identifier = ? AND charid = ? AND selected = 1 LIMIT 1',
        { c.identifier, c.charIdentifier }) end
    if not row or not models[row.model] then return fail('select') end
    for _,entry in pairs(active) do
        if entry.owner == identity(c) then return fail('alreadyOut') end
    end
    if activeById[row.id] then return fail('alreadyOut') end
    local token = tostring(os.time()) .. ':' .. tostring(math.random(100000,999999))
    active[src] = { id=row.id, model=row.model, owner=identity(c), identifier=c.identifier, charid=c.charIdentifier,
        netId=0, token=token, prepared=os.time(), lastDecay=os.time(), condition=boundedCondition(row) }
    activeById[row.id] = src
    return ok({ row=row, token=token, maxCondition=conditionMax(row.model) })
end)

register('commit', function(src, c, data)
    local entry = active[src]
    if not entry or entry.owner ~= identity(c) or entry.token ~= data.token or entry.netId ~= 0 then return fail('invalid') end
    local netId = integer(data.netId)
    local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0
    local started = GetGameTimer()
    while entity == 0 and netId and GetGameTimer()-started < 2500 do
        Wait(50)
        entity = NetworkGetEntityFromNetworkId(netId)
    end
    if os.time()-entry.prepared > 20 or entity == 0 or not DoesEntityExist(entity)
        or NetworkGetEntityOwner(entity) ~= src or GetEntityModel(entity) ~= joaat(entry.model)
        or not nearby(src, GetEntityCoords(entity), 100.0) then
        forget(src, false)
        return fail('spawnFailed')
    end
    entry.netId = netId
    Entity(entity).state:set('jrsStableWagonId', entry.id, true)
    return ok({ id=entry.id, condition=entry.condition, maxCondition=conditionMax(entry.model) })
end)

register('cancelSpawn', function(src, c, data)
    local entry = active[src]
    if entry and entry.owner == identity(c) and entry.netId == 0 and data.token == entry.token then forget(src, false) end
    return ok()
end)

register('return', function(src, c, data)
    local entry = active[src]
    if not entry or entry.owner ~= identity(c) then return fail('noWagon') end
    if not Settings.returnEnabled and not shop(src, c, data.site) then return fail('tooFar') end
    local entity = entry.netId ~= 0 and NetworkGetEntityFromNetworkId(entry.netId) or 0
    if entity ~= 0 and DoesEntityExist(entity) then
        if not nearby(src, GetEntityCoords(entity), Settings.callDistance) then return fail('tooFar') end
        -- Avoid deleting a wagon while another player is using it.
        for _,id in ipairs(GetPlayers()) do
            local player = tonumber(id)
            local ped = GetPlayerPed(player)
            if player ~= src and ped ~= 0 and GetVehiclePedIsIn(ped, false) == entity then return fail('busy') end
        end
    end
    forget(src, true)
    return ok()
end)

local function storageAllowed(src, id, direction, data)
    local entry = nearWagon(src, id)
    local c = character(src)
    if not entry or not c then return false end
    local cfg = models[entry.model].inventory
    if not cfg.enabled or not cfg.shared and identity(c) ~= entry.owner then return false end
    if cfg.usePermissions then
        local jobs = direction == 'deposit' and cfg.permissions.allowedJobsMoveTo or cfg.permissions.allowedJobsTakeFrom
        if not matchesJob(c, jobs) then return false end
    end
    if data and data.kind == 'weapon' then
        if not cfg.weapons then return false end
        if cfg.whitelistWeapons then
            local allowed = false
            for _,weapon in ipairs(cfg.weaponsLimitWhiteList) do
                if weapon.name == data.weapon then
                    allowed = true
                    if direction == 'deposit' then
                        if not cargoCounts[entry.id] then return false end
                        local stored = cargoCounts[entry.id]['weapon:' .. weapon.name] or 0
                        if stored + 1 > (tonumber(weapon.limit) or 0) then return false end
                    end
                end
            end
            if not allowed then return false end
        end
        return true -- JRS's native storage handlers validate serials and move weapon ownership.
    end
    if data and data.kind ~= 'item' then return false end
    if data then
        if cfg.useBlackList then
            for _,name in ipairs(cfg.itemsBlackList) do if data.item == name then return false end end
        end
        if cfg.useWhiteList then
            local allowed = false
            for _,item in ipairs(cfg.itemsLimitWhiteList) do
                if item.name == data.item then
                    allowed = true
                    if direction == 'deposit' then
                        if not cargoCounts[entry.id] then return false end
                        local stored = cargoCounts[entry.id][item.name] or 0
                        if (tonumber(stored) or 0) + (tonumber(data.amount) or 0) > (tonumber(item.limit) or 0) then return false end
                    end
                end
            end
            if not allowed then return false end
        end
    end
    return true
end

register('cargo', function(src, c, data)
    local id = integer(data.id)
    local entry = id and nearWagon(src, id)
    if not entry then return fail('tooFar') end
    if not models[entry.model].inventory.enabled then return fail('cargoDisabled') end
    if not storageAllowed(src, id, 'open') then return fail('forbidden') end
    local row = owned(c, id) or MySQL.single.await('SELECT name FROM player_wagons WHERE id = ? LIMIT 1', { id })
    exports.jrs_inventory:registerInventory({ id='wagonID_' .. id, name=WagonText('cargo',src) .. ' · ' .. (row and row.name or ''),
        limit=models[entry.model].inventory.limit, acceptWeapons=models[entry.model].inventory.weapons, shared=models[entry.model].inventory.shared })
    cargoCounts[id] = {}
    for _,item in ipairs(exports.jrs_inventory:getCustomInventoryItems('wagonID_' .. id) or {}) do
        cargoCounts[id][item.name] = (cargoCounts[id][item.name] or 0) + (tonumber(item.count or item.amount) or 0)
    end
    local rawItems = MySQL.scalar.await('SELECT items FROM jrs_inventory_storage WHERE identifier = ? LIMIT 1', { 'jrs:wagonID_' .. id })
    for _,item in ipairs(json.decode(rawItems or '[]')) do
        if item.weapon and item.name then
            local key = 'weapon:' .. item.name
            cargoCounts[id][key] = (cargoCounts[id][key] or 0) + 1
        end
    end
    -- Let the client release stable focus before opening jrs_inventory.
    return ok({ id=id })
end)
RegisterNetEvent('jrs_stables:wagon:openCargo', function(id)
    local src = source
    id = integer(id)
    if id and storageAllowed(src, id, 'open') then exports.jrs_inventory:openInventory(src, 'wagonID_' .. id) end
end)
AddEventHandler('jrs_inventory:server:storagePermission', function(src, storageId, direction, data, respond)
    local id = tonumber(tostring(storageId):match('^jrs:wagonID_(%d+)$'))
    if not id then return end
    local success,allowed = pcall(storageAllowed, src, id, direction, data)
    if not success or not allowed then respond(false, 'wagon_access_denied', WagonText('forbidden',src)) end
end)
AddEventHandler('jrs_inventory:server:storageTransaction', function(src, storageId, direction, data)
    local id = tonumber(tostring(storageId):match('^jrs:wagonID_(%d+)$'))
    if not id or not cargoCounts[id] or type(data) ~= 'table' then return end
    local item = data.kind == 'weapon' and data.weapon and 'weapon:' .. data.weapon or data.item
    if not item then return end
    local amount = data.kind == 'weapon' and 1 or tonumber(data.amount or data.count) or 0
    cargoCounts[id][item] = math.max(0, (cargoCounts[id][item] or 0) + (direction == 'deposit' and amount or -amount))
end)

register('repair', function(src, c, data)
    local entry,entity = nearWagon(src, data.id)
    if not entry or entry.owner ~= identity(c) then return fail('tooFar') end
    local cfg = models[entry.model].condition
    if entry.condition >= conditionMax(entry.model) then return fail('fullCondition') end
    if exports.jrs_inventory:subItem(src, Settings.repairItem, Settings.repairUsage) ~= true then return fail('repairItem') end
    local value = math.min(conditionMax(entry.model), entry.condition + math.max(0, tonumber(cfg.repairValue) or 25))
    local success,result = pcall(MySQL.update.await,
        'UPDATE player_wagons SET `condition` = ? WHERE id = ? AND identifier = ? AND charid = ?',
        { value, entry.id, c.identifier, c.charIdentifier })
    if not success or result ~= 1 then
        exports.jrs_inventory:addItem(src, Settings.repairItem, Settings.repairUsage)
        return fail('unavailable')
    end
    entry.condition, entry.lastDecay = value, os.time()
    TriggerClientEvent('jrs_stables:wagon:condition', src, entry.id, value, conditionMax(entry.model))
    return ok({ condition=value, maxCondition=conditionMax(entry.model) })
end)

register('trade', function(src, c, data)
    local row, target = owned(c, data.id), integer(data.target)
    if not row then return fail('forbidden') end
    if activeById[row.id] then return fail('returnFirst') end
    local recipient = target and target ~= src and character(target)
    if not recipient or identity(recipient) == identity(c) then return fail('target') end
    local ped = GetPlayerPed(target)
    if ped == 0 or not nearby(src, GetEntityCoords(ped), 5.0) then return fail('target') end
    local targetKey = identity(recipient)
    if locks[targetKey] then return fail('busy') end
    locks[targetKey] = true
    local success,result = xpcall(function()
        if count(recipient) >= limit(recipient) then return fail('targetLimit') end
        local updated = MySQL.update.await('UPDATE player_wagons SET identifier = ?, charid = ?, selected = 0 WHERE id = ? AND identifier = ? AND charid = ?',
            { recipient.identifier, recipient.charIdentifier, row.id, c.identifier, c.charIdentifier })
        if updated ~= 1 then return fail('unavailable') end
        Core.NotifyRightTip(target, WagonText('traded',target) .. ' · ' .. row.name, 5000)
        TriggerClientEvent('jrs_stables:wagon:refresh', target)
        return ok()
    end, debug.traceback)
    locks[targetKey] = nil
    if not success then error(result) end
    return result
end)

exports('GrantWagon', function(target, model, name)
    local resource = GetInvokingResource()
    if not resource or not Settings.trustedGrantResources[resource] then return false end
    local result = exclusive(tonumber(target), function(c)
        name = cleanName(name)
        if not name or not models[model] or count(c) >= limit(c) then return fail('invalid') end
        local id = MySQL.insert.await('INSERT INTO player_wagons (identifier, charid, selected, name, model, `condition`) VALUES (?, ?, 0, ?, ?, ?)',
            { c.identifier, c.charIdentifier, name, model, conditionMax(model) })
        return id and ok({ id=id }) or fail('unavailable')
    end)
    if result.ok then TriggerClientEvent('jrs_stables:wagon:refresh', tonumber(target)) end
    return result.ok == true, result.code
end)

AddEventHandler('playerDropped', function() forget(tonumber(source), true) end)
RegisterNetEvent('jrs_stables:wagon:cleanup', function() forget(tonumber(source), true) end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(active) do forget(src, true) end
end)
CreateThread(function()
    while true do
        Wait(10000)
        for src,entry in pairs(active) do
            local _,entity = liveWagon(entry.id)
            if entry.netId == 0 then
                if os.time()-entry.prepared > 20 then forget(src, false) end
            elseif not entity then
                forget(src, true)
                TriggerClientEvent('jrs_stables:wagon:removed', src)
            else
                local cfg = models[entry.model].condition
                local interval = math.max(10, tonumber(cfg.decreaseTime) or 60)
                local elapsed = math.floor((os.time()-entry.lastDecay)/interval)
                if cfg.enabled and elapsed > 0 and entry.condition > 0 and not locks[entry.owner] then
                    locks[entry.owner] = true
                    local value = math.max(0, entry.condition - elapsed * math.max(0, tonumber(cfg.decreaseValue) or 1))
                    local success,changed = pcall(MySQL.update.await,
                        'UPDATE player_wagons SET `condition` = ? WHERE id = ? AND identifier = ? AND charid = ?',
                        { value, entry.id, entry.identifier, entry.charid })
                    if success and changed == 1 then
                        entry.condition = value
                        entry.lastDecay = entry.lastDecay + elapsed * interval
                        TriggerClientEvent('jrs_stables:wagon:condition', src, entry.id, value, conditionMax(entry.model))
                    end
                    locks[entry.owner] = nil
                end
            end
        end
    end
end)
