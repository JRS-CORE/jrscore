-- jrs_stables | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- JRS horse selection, paid revival and server-controlled ability training.
local Core = exports.jrs_core:GetCore()
local Settings = Config.HorseTraining
local ready, locks, active, sessions, cooldowns, revivers = false, {}, {}, {}, {}, {}
HorseCare = {}
local function character(src)
    local user = Core.getUser(src)
    local c = user and user.getUsedCharacter
    return c and c.identifier and c.charIdentifier and c or nil
end
local function identity(c) return c.identifier .. ':' .. tostring(c.charIdentifier) end
local function integer(value)
    local n = tonumber(value)
    return n and n > 0 and n % 1 == 0 and n < 2147483647 and n or nil
end
local function owns(c, id)
    id = integer(id)
    if not id then return end
    return MySQL.single.await('SELECT * FROM player_horses WHERE id = ? AND identifier = ? AND charid = ? LIMIT 1',
        {id, c.identifier, c.charIdentifier})
end
local function needsRevive(row) return tonumber(row.dead) == 1 or tonumber(row.writhe) == 1 end
local function ok(data) return {ok=true, data=data} end
local function fail(code) return {ok=false, code=code} end
local function nearby(src, coords, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and DoesEntityExist(ped) and #(GetEntityCoords(ped)-coords) <= distance
end
local function stable(src, site)
    local cfg = type(site) == 'string' and Stables[site]
    return cfg and nearby(src, cfg.npc.coords, Settings.shopDistance)
end
function HorseCare.Decorate(row)
    row.components = json.encode(StableTack.List(row.components))
    local xp = ready and MySQL.single.await('SELECT health_xp, stamina_xp FROM jrs_horse_training WHERE horse_id = ?', {row.id}) or nil
    row.training = HorseAbilities.Stats(row.model, xp and xp.health_xp, xp and xp.stamina_xp)
    row.needsRevive = needsRevive(row)
    return row
end
local function live(src, c, id)
    local entry = active[src]
    if not entry or entry.id ~= integer(id) or entry.owner ~= identity(c) then return end
    local entity = NetworkGetEntityFromNetworkId(entry.netId)
    if entity == 0 or not DoesEntityExist(entity) or NetworkGetEntityOwner(entity) ~= src
        or GetEntityModel(entity) ~= joaat(entry.model) or GetEntityHealth(entity) <= 0 then return end
    return entry, entity
end
local function cancel(src, notify)
    if not sessions[src] then return end
    sessions[src] = nil
    if notify then TriggerClientEvent('jrs_stables:horse:trainingEnded', src, false) end
end
local function exclusive(src, fn)
    local c = character(src)
    if not ready or not Settings.enabled then return fail('horseUnavailable') end
    if not c then return fail('horseForbidden') end
    local key = identity(c)
    if locks[key] then return fail('horseBusy') end
    locks[key] = true
    local success, result = xpcall(function() return fn(c) end, debug.traceback)
    locks[key] = nil
    if not success then print('[jrs_stables] Horse action failed: '..tostring(result)); return fail('horseUnavailable') end
    return result or fail('horseInvalid')
end
local function register(name, fn)
    Core.Callback.Register('jrs_stables:horse:'..name, function(src, cb, data)
        cb(exclusive(src, function(c) return fn(src, c, type(data)=='table' and data or {}) end))
    end)
end
MySQL.ready(function()
    local success, err = pcall(function()
        MySQL.query.await(LoadResourceFile(GetCurrentResourceName(), 'sql/horse_training.sql'))
        ready = true
    end)
    if not success then print('^1[jrs_stables] Horse training database unavailable: '..tostring(err)..'^7') end
end)
register('select', function(src, c, data)
    if not stable(src, data.site) then return fail('horseTooFar') end
    if sessions[src] then return fail('horseBusy') end
    local row = owns(c, data.id)
    if not row then return fail('horseForbidden') end
    if needsRevive(row) then return fail('horseNeedRevive') end
    local success = MySQL.transaction.await({
        {query='UPDATE player_horses SET selected = 0 WHERE identifier = ? AND charid = ?', values={c.identifier,c.charIdentifier}},
        {query='UPDATE player_horses SET selected = 1 WHERE id = ? AND identifier = ? AND charid = ? AND dead = 0 AND writhe = 0',
            values={row.id,c.identifier,c.charIdentifier}},
    })
    if not success then return fail('horseUnavailable') end
    row.selected = 1
    return ok(HorseCare.Decorate(row))
end)
register('revive', function(src, c, data)
    if not stable(src, data.site) then return fail('horseTooFar') end
    if sessions[src] then return fail('horseBusy') end
    local row = owns(c, data.id)
    if not row then return fail('horseForbidden') end
    if not needsRevive(row) then return fail('horseAlive') end
    local price = math.max(0, tonumber(Settings.revivePrice) or 10)
    if tonumber(c.money) < price then return fail('horseCash') end
    if c.removeCurrency(0, price) == false then return fail('horseCash') end
    local success, changed = pcall(MySQL.update.await,
        'UPDATE player_horses SET dead = 0, writhe = 0, health = 100, stamina = 100 WHERE id = ? AND identifier = ? AND charid = ? AND (dead = 1 OR writhe = 1)',
        {row.id,c.identifier,c.charIdentifier})
    if not success or not changed or changed < 1 then
        c.addCurrency(0, price)
        return fail('horseUnavailable')
    end
    row.dead,row.writhe,row.health,row.stamina = 0,0,100,100
    if active[src] and active[src].id == row.id then active[src] = nil end
    TriggerClientEvent('jrs_stables:horse:revived', src, row.id)
    return ok(HorseCare.Decorate(row))
end)
register('register', function(src, c, data)
    local row = owns(c, data.id)
    if not row or needsRevive(row) or tonumber(row.selected) ~= 1 then return fail('horseForbidden') end
    local netId = integer(data.netId)
    if not netId then return fail('horseInvalid') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 or not DoesEntityExist(entity) or NetworkGetEntityOwner(entity) ~= src
        or GetEntityModel(entity) ~= joaat(row.model) or not nearby(src, GetEntityCoords(entity), 40) then return fail('horseCallFirst') end
    cancel(src, true)
    active[src] = {id=row.id, owner=identity(c), netId=netId, model=row.model}
    return ok(HorseCare.Decorate(row))
end)
register('train', function(src, c, data)
    local stat = data.stat
    if stat ~= 'health' and stat ~= 'stamina' then return fail('horseInvalid') end
    if sessions[src] then return fail('horseBusy') end
    local row = owns(c, data.id)
    if not row then return fail('horseForbidden') end
    if needsRevive(row) then return fail('horseNeedRevive') end
    local entry, entity = live(src, c, row.id)
    if not entry then return fail('horseCallFirst') end
    if not nearby(src, GetEntityCoords(entity), 5) then return fail('horseTooFar') end
    if Config.trainerOnly then
        local allowed = false
        for _, job in ipairs(Config.trainerJob) do
            if c.job == job.name and (tonumber(c.jobGrade) or 0) >= job.grade then allowed = true end
        end
        if not allowed then return fail('horseForbidden') end
    end
    local key = identity(c)..':'..row.id
    if (cooldowns[key] or 0) > GetGameTimer() then return fail('horseCooldown') end
    row = HorseCare.Decorate(row)
    if row.training[stat].percent >= 100 then return fail('horseMaxed') end
    local seconds = math.max(1, tonumber(stat=='health' and Settings.healthSeconds or Settings.staminaSeconds) or 30)
    sessions[src] = {id=row.id, owner=identity(c), stat=stat, started=GetGameTimer(), elapsed=0,
        distance=0, last=GetEntityCoords(entity), seconds=seconds, key=key}
    return ok({id=row.id, stat=stat, seconds=seconds, distance=stat=='stamina' and Settings.staminaDistance or 0})
end)
function HorseCare.Tick()
    for src, session in pairs(sessions) do
        local c = character(src)
        local row = c and owns(c, session.id)
        local entry, entity
        if row then entry, entity = live(src,c,session.id) end
        if not c or identity(c) ~= session.owner or not entry or not row or needsRevive(row)
            or not nearby(src, GetEntityCoords(entity), 5)
            or GetGameTimer()-session.started > math.max(session.seconds,Settings.sessionTimeout)*1000 then
            cancel(src, true)
        else
            local coords = GetEntityCoords(entity)
            local delta = #(coords-session.last)
            session.last = coords
            if delta > Settings.maxTrainingSpeed then
                cancel(src, true)
            else
                if session.stat == 'stamina' or delta < 1 then session.elapsed = session.elapsed + 1 end
                session.distance = session.distance + delta
                local complete = session.elapsed >= session.seconds and
                    (session.stat=='health' or session.distance >= Settings.staminaDistance)
                if complete then
                    sessions[src] = nil -- Exactly one award, including repeated finish requests.
                    local updated = exclusive(src, function(current)
                        local fresh = owns(current, session.id)
                        if not fresh or needsRevive(fresh) then return fail('horseForbidden') end
                        local stat = session.stat == 'health' and 'health_xp' or 'stamina_xp'
                        local amount = math.max(1, math.floor(tonumber(Settings.xpPerSession) or 10))
                        MySQL.query.await('INSERT INTO jrs_horse_training (horse_id, health_xp, stamina_xp) VALUES (?, 0, 0) ON DUPLICATE KEY UPDATE horse_id = horse_id', {fresh.id})
                        MySQL.update.await('UPDATE jrs_horse_training SET '..stat..' = LEAST(?, '..stat..' + ?) WHERE horse_id = ?', {Settings.xpToMax,amount,fresh.id})
                        return ok(HorseCare.Decorate(fresh))
                    end)
                    if updated.ok then
                        cooldowns[session.key] = GetGameTimer()+Settings.sessionCooldown*1000
                        TriggerClientEvent('jrs_stables:horse:progress',src,updated.data)
                    end
                    TriggerClientEvent('jrs_stables:horse:trainingEnded',src,updated.ok)
                end
            end
        end
    end
end
CreateThread(function() while true do Wait(1000); HorseCare.Tick() end end)
function HorseCare.Cleanup(src) cancel(src,true); active[src],revivers[src] = nil,nil end
function HorseCare.AuthorizeItemRevive(src)
    local c = character(src)
    local entry = c and active[src]
    local row = entry and owns(c,entry.id)
    if not row or tonumber(row.dead)==1 or tonumber(row.writhe)~=1 then return false end
    revivers[src] = {id=row.id, expires=GetGameTimer()+15000}
    return true
end
function HorseCare.CanClearWrithe(src, id)
    local token = revivers[src]
    if token and token.id==integer(id) and token.expires>=GetGameTimer() then revivers[src]=nil; return true end
    return false
end
function HorseCare.Forget(id)
    MySQL.update.await('DELETE FROM jrs_horse_training WHERE horse_id = ?', {id})
end
RegisterNetEvent('jrs_stables:horse:cancel',function() cancel(source,true) end)
RegisterNetEvent('jrs_stables:horse:cleanup',function() HorseCare.Cleanup(source) end)
AddEventHandler('playerDropped',function() HorseCare.Cleanup(source) end)
AddEventHandler('jrs_core:server:characterUnloaded',function(src) HorseCare.Cleanup(tonumber(src) or source) end)
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    for src in pairs(sessions) do cancel(src,true) end
end)
