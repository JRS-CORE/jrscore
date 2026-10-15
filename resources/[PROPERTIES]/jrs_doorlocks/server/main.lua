-- jrs_doorlocks | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_doorlocks | server
-- Keeps the state of every door and decides who may change it: a per-player override (from other
-- resources, e.g. housing), the door's job/grade rule, or the character's id. Lockpicking is a separate
-- route started by using a lockpick item.

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local byId = {}                 -- door id -> door definition
local state = {}               -- door id -> 0 (open) or 1 (closed)
for _, d in ipairs(Config.Doors) do
    byId[d.id] = d
    state[d.id] = d.closed and 1 or 0
end

local override = {}            -- door id -> { [player] = true/false }
local picking  = {}            -- player -> true while a lockpick is being used

local function near(src, d, reach)
    return #(GetEntityCoords(GetPlayerPed(src)) - d.at) <= (reach or Config.ServerReach)
end

local function setState(d, value)
    state[d.id] = value
    if d.twin and byId[d.twin] then state[d.twin] = value end
    TriggerClientEvent('jrs_doorlocks:state', -1, d.id, value, d.twin)
end

-- true, or false plus the reason to show
local function mayUse(src, d)
    local own = override[d.id] and override[d.id][src]
    if own ~= nil then return own, Text.notAllowed end

    local user = Core.getUser(src)
    local character = user and user.getUsedCharacter
    if not character then return false end

    local reason = Text.notAllowed
    local needed = d.perm and Config.Permissions[d.perm] and Config.Permissions[d.perm][character.job]
    if needed then
        if (tonumber(character.jobGrade) or 0) >= needed then return true end
        reason = Text.wrongGrade
    elseif d.perm then
        reason = Text.wrongJob
    end

    local list = d.unique and Config.Unique[d.unique]
    if list then
        for _, id in ipairs(list) do
            if id == character.charIdentifier then return true end
        end
    end
    return false, reason
end

-- ------------------------------------------------------------------ using a door

Core.Callback.Register('jrs_doorlocks:use', function(src, cb, id, wanted)
    local d = byId[id]
    if not d or (wanted ~= 0 and wanted ~= 1) then return cb(false) end
    if not near(src, d) then
        print(('[jrs_doorlocks] %s (id %d) asked for a door that is too far away'):format(GetPlayerName(src), src))
        return cb(false)
    end

    local ok, why = mayUse(src, d)
    if not ok then
        if why then Core.NotifyObjective(src, why, 5000) end
        return cb(false)
    end
    setState(d, wanted)
    cb(true)
end)

-- ------------------------------------------------------------------ lockpicking

local function warnPolice(src, d)
    local origin = GetEntityCoords(GetPlayerPed(src))
    local officers = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if Player(id).state.isPoliceDuty then
            officers[#officers + 1] = { id = id, away = #(origin - GetEntityCoords(GetPlayerPed(id))) }
        end
    end
    table.sort(officers, function(a, b) return a.away < b.away end)
    for i = 1, math.min(Config.AlertOfficers, #officers) do
        Core.NotifyLeft(officers[i].id, Text.alertTitle, Text.alertText, 'inventory_items', 'provision_sheriff_star', 5000, 'COLOR_WHITE')
    end
end

-- the client reports the result of the lockpick game for the door it was standing at
RegisterNetEvent('jrs_doorlocks:picked', function(id)
    local src = source
    local d = byId[id]
    if not (d and d.lockpick and picking[src] and near(src, d)) then return end
    if math.random() < Config.AlertChance and d.alert then warnPolice(src, d) end
    setState(d, 0)
end)

CreateThread(function()
    local items = {}
    for _, d in ipairs(Config.Doors) do
        if d.lockpick then items[d.lockpick] = true end
    end

    for item in pairs(items) do
        exports.jrs_inventory:registerUsableItem(item, function(data)
            local src = data.source
            exports.jrs_inventory:closeInventory(src)
            picking[src] = true

            -- the client answers true when the lockpick was lost (the attempt failed)
            local lost = Core.Callback.TriggerAwait('jrs_doorlocks:pick', src, item)
            if lost and not exports.jrs_inventory:subItemById(src, data.item.id) then
                print(('[jrs_doorlocks] %s lost a lockpick that was no longer in the bag'):format(GetPlayerName(src)))
            end
            picking[src] = nil
        end, GetCurrentResourceName())
    end
end)

-- ------------------------------------------------------------------ keeping players in sync

AddEventHandler('jrs:SelectedCharacter', function(src)
    if Config.DevMode then return end
    TriggerClientEvent('jrs_doorlocks:sync', src, msgpack.pack(state))
end)

AddEventHandler('jrs:playerJobChange', function(src)
    SetTimeout(1000, function() TriggerClientEvent('jrs_doorlocks:perms', src) end)   -- statebags need a moment
end)

AddEventHandler('playerDropped', function()
    local src = source
    picking[src] = nil
    for _, players in pairs(override) do players[src] = nil end
end)

-- ------------------------------------------------------------------ for other resources

-- let (or stop) one player from using a door, whatever its normal rule says
exports('updateDoorPermission', function(src, id, allow)
    if not byId[id] then return print('[jrs_doorlocks] no door with id', id) end
    if not Player(src).state.IsInSession then return print('[jrs_doorlocks] player is not in session yet', src) end

    override[id] = override[id] or {}
    override[id][src] = allow
    TriggerClientEvent('jrs_doorlocks:perms', src, { door = id, allowed = allow })
end)

exports('getDoorCoords', function(id)
    local d = byId[tonumber(id) or id]
    return d and d.at or nil
end)
