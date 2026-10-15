-- jrs_police | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_police | server
-- Duty, hiring, storage, handcuffs and dragging, jail (kept across relogs) and emergency calls.
-- Every request is checked here: the player's job and grade, duty, and distance.

local Core = exports.jrs_core:GetCore()
local Inv  = exports.jrs_inventory
local Text = Config.Text[Config.Language] or Config.Text.en
local Jail = Config.Jail

local onDuty  = {}            -- officer -> true
local waiting = {}            -- officers on duty and free to take a call
local calls   = {}            -- caller -> officer answering
local prisoners = {}          -- player -> { release = os.time() when the sentence ends }

-- ------------------------------------------------------------------ helpers

local function character(src)
    local user = Core.getUser(src)
    return user and user.getUsedCharacter, user
end

local function say(src, line, ms) Core.NotifyObjective(src, line, ms or 5000) end

local function rankOf(src)
    local c = character(src)
    local grades = c and Config.Jobs[c.job]
    return grades and grades[c.jobGrade]
end

local function can(src, right)
    local rank = rankOf(src)
    return rank and rank[right] == true
end

local function near(src, target, range)
    target = tonumber(target)
    if not target or target <= 0 or not GetPlayerName(target) then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) <= range
end

local function who(src)
    local c = character(src)
    return ('%s %s (%s, id %d)'):format(c.firstname, c.lastname, GetPlayerName(src), src)
end

local function log(url, title, lines)
    if not url or url == '' then return end
    local L = Config.Logs
    Core.AddWebhook(title, url, table.concat(lines, '\n'), L.color, L.name, L.logo, L.footer, L.avatar)
end

local function setDuty(src, on)
    onDuty[src] = on or nil
    waiting[src] = on or nil
    Player(src).state:set('isPoliceDuty', on or nil, true)
end

local function storageId(index)
    return Config.ShareStorage and 'jrs_police_storage' or ('jrs_police_storage_' .. index)
end

local function ensureStorage(index)
    local id, station = storageId(index), Config.Stations[index]
    if not Inv:isCustomInventoryRegistered(id) then
        Inv:registerInventory({
            id = id, name = station.storageName, limit = Config.StorageLimit, acceptWeapons = true, shared = true,
            ignoreItemStackLimit = true, whitelistItems = false, UsePermissions = false, UseBlackList = false,
            whitelistWeapons = false, webhook = Config.Logs.Storage,
        })
    end
    return id
end

-- ------------------------------------------------------------------ duty and the menu

Core.Callback.Register('jrs_police:server:checkDuty', function(src, cb)
    if not rankOf(src) then return cb(false) end
    local turnOn = not onDuty[src]
    setDuty(src, turnOn)
    log(Config.Logs.Duty, turnOn and 'Police On Duty' or 'Police Off Duty', { who(src) })
    cb(turnOn)
end)

RegisterCommand(Config.MenuCommand, function(src)
    if src == 0 then return end
    if not rankOf(src) then return say(src, Text.notOfficer) end
    TriggerClientEvent('jrs_police:Client:OpenPoliceMenu', src)
end, false)

-- ------------------------------------------------------------------ storage

RegisterNetEvent('jrs_police:Server:OpenStorage', function(index)
    local src = source
    if not rankOf(src) then return say(src, Text.notOfficer) end
    if not onDuty[src] then return say(src, Text.notOnDuty) end

    local station = Config.Stations[tonumber(index) or 0]
    if not station or #(GetEntityCoords(GetPlayerPed(src)) - station.storage) > Config.Reach + 3.0 then return end
    Inv:openInventory(src, ensureStorage(index))
end)

-- ------------------------------------------------------------------ hiring and firing

RegisterNetEvent('jrs_police:server:hirePlayer', function(targetId, choice)
    local src = source
    local rank = rankOf(src)
    if not (rank and rank.manager) or type(choice) ~= 'table' then return say(src, Text.noRights) end

    local target = tonumber(targetId)
    local targetChar = target and character(target)
    if not targetChar then return say(src, Text.notFound) end

    local grade = tonumber(choice.grade)
    local wanted = Config.Jobs[choice.job] and grade and Config.Jobs[choice.job][grade]
    if not wanted then return say(src, Text.noRights) end
    if not wanted.label then return print(Text.noLabel) end
    if targetChar.job == choice.job and targetChar.jobGrade == grade then return say(src, Text.alreadyHired .. wanted.label) end
    if not near(src, target, 5.0) then return say(src, Text.notNear) end

    targetChar.setJob(choice.job, true)
    targetChar.setJobGrade(grade, true)
    targetChar.setJobLabel(wanted.label, true)

    say(target, Text.hired .. wanted.label)
    say(src, Text.hirePlayer)
    TriggerClientEvent('jrs_police:Client:JobUpdate', target)
    log(Config.Logs.Hire, 'Police Hired', { 'By: ' .. who(src), 'Hired: ' .. who(target), 'Job: ' .. wanted.label })
end)

RegisterNetEvent('jrs_police:server:firePlayer', function(targetId)
    local src = source
    local rank = rankOf(src)
    if not (rank and rank.manager) then return say(src, Text.noRights) end

    local target = tonumber(targetId)
    local targetChar = target and character(target)
    if not targetChar then return say(src, Text.notFound) end
    if not Config.Jobs[targetChar.job] then return say(src, Text.cantFire) end
    if target == src then return say(src, Text.noRights) end

    targetChar.setJob('unemployed', true)
    targetChar.setJobLabel('Unemployed', true)

    say(target, Text.fired)
    say(src, Text.youFired)
    if onDuty[target] then setDuty(target, false) end
    TriggerClientEvent('jrs_police:Client:JobUpdate', target)
    log(Config.Logs.Hire, 'Police Fired', { 'By: ' .. who(src), 'Fired: ' .. who(target) })
end)

AddEventHandler('jrs:playerJobChange', function(src, newJob)
    if Config.Jobs[newJob] then TriggerClientEvent('jrs_police:Client:JobUpdate', src) end
end)

-- ------------------------------------------------------------------ handcuffs, keys, dragging

local function onDutyOfficer(src)
    return rankOf(src) and onDuty[src]
end

CreateThread(function()
    if Core.RegisterJobs then
        local jobs = {}
        for job, grades in pairs(Config.Jobs) do
            jobs[job] = { grades = {} }
            for grade, rank in pairs(grades) do jobs[job].grades[grade] = { label = rank.label } end
        end
        Core.RegisterJobs(jobs, GetCurrentResourceName())
    end

    if not Config.CuffItem or not Config.KeyItem then return end

    Inv:registerUsableItem(Config.CuffItem, function(data)
        local src = data.source
        Inv:closeInventory(src)

        if not Config.EveryoneCanCuff then
            if not rankOf(src) then return say(src, Text.notOfficer) end
            if not onDuty[src] then return say(src, Text.notOnDuty) end
        end

        local nearby = Core.Callback.TriggerAwait('jrs_police:Client:nearby', src)       -- { cuffed, id } of the closest player
        if not nearby or not nearby.id then return end
        if nearby.cuffed then return say(src, Text.alreadyCuffed) end
        if not near(src, nearby.id, 5.0) then return end

        if Config.CuffIsUsedUp then Inv:subItemById(src, data.item.id) end
        TriggerClientEvent('jrs_police:Client:PlayerCuff', nearby.id, 'cuff')
    end, GetCurrentResourceName())

    Inv:registerUsableItem(Config.KeyItem, function(data)
        local src = data.source
        Inv:closeInventory(src)

        local nearby = Core.Callback.TriggerAwait('jrs_police:Client:nearby', src)
        if not nearby or not nearby.id then return end
        if not nearby.cuffed then return say(src, Text.notCuffed) end
        if not near(src, nearby.id, 5.0) then return end

        if Config.CuffIsUsedUp then Inv:addItem(src, Config.CuffItem, 1) end
        TriggerClientEvent('jrs_police:Client:PlayerCuff', nearby.id, 'uncuff')
    end, GetCurrentResourceName())
end)

RegisterNetEvent('jrs_police:Server:dragPlayer', function(target)
    local src = source
    if not onDutyOfficer(src) then return end
    target = tonumber(target)
    if target and near(src, target, 5.0) and Core.getUser(target) then
        TriggerClientEvent('jrs_police:Client:dragPlayer', target, src)
    end
end)

-- ------------------------------------------------------------------ emergency calls

local function nearestFreeOfficer(origin)
    local best, bestAway = nil, math.huge
    for officer in pairs(waiting) do
        local away = #(origin - GetEntityCoords(GetPlayerPed(officer)))
        if away < bestAway then best, bestAway = officer, away end
    end
    return best
end

local function callerOf(officer)
    for caller, o in pairs(calls) do
        if o == officer then return caller end
    end
end

RegisterCommand(Config.CallCommand, function(src)
    if src == 0 then return end
    if prisoners[src] then return Core.NotifyRightTip(src, Text.callInJail, 5000) end
    if calls[src] then return Core.NotifyRightTip(src, Text.alreadyCalled, 5000) end
    if not next(waiting) then return Core.NotifyRightTip(src, Text.noOfficers, 5000) end

    local c = character(src)
    if Config.OnlyDeadCanCall and not (c and c.isdead) then return say(src, Text.notDeadCall) end

    local origin = GetEntityCoords(GetPlayerPed(src))
    local officer = nearestFreeOfficer(origin)
    if not officer then return Core.NotifyRightTip(src, Text.noOfficers, 5000) end

    waiting[officer] = nil
    calls[src] = officer
    say(officer, Text.needsHelp)
    TriggerClientEvent('jrs_police:Client:AlertPolice', officer, origin)
    Core.NotifyRightTip(src, Text.alerted, 5000)
end, false)

RegisterCommand(Config.CancelCommand, function(src)
    if src == 0 then return end
    local officer = calls[src]
    if not officer then return Core.NotifyRightTip(src, Text.noCall, 5000) end

    if Core.getUser(officer) then
        TriggerClientEvent('jrs_police:Client:RemoveBlip', officer)
        say(officer, Text.canceledByPlayer)
        if onDuty[officer] then waiting[officer] = true end
    end
    calls[src] = nil
    Core.NotifyRightTip(src, Text.canceled, 5000)
end, false)

RegisterCommand(Config.FinishCommand, function(src)
    if src == 0 then return end
    if not rankOf(src) then return say(src, Text.notOfficer) end
    if not onDuty[src] and not callerOf(src) then return say(src, Text.notOnDuty) end

    local caller = callerOf(src)
    if not caller then return say(src, Text.notOnCall) end

    TriggerClientEvent('jrs_police:Client:RemoveBlip', src)
    say(src, Text.canceled)
    Core.NotifyRightTip(caller, Text.canceledByOfficer, 5000)
    calls[caller] = nil
    if onDuty[src] then waiting[src] = true end
end, false)

-- ------------------------------------------------------------------ jail

local function kvp(charId) return ('jrs_police_jailTime_data_%s'):format(charId) end

local function release(src, why)
    local c = character(src)
    prisoners[src] = nil
    if c then DeleteResourceKvp(kvp(c.charIdentifier)) end
    TriggerClientEvent('jrs_police:Client:JailFinished', src)
    if why then log(Config.Logs.Jail, 'Released', { who(src), why }) end
end

local function mayJail(src)
    return onDutyOfficer(src) and (can(src, 'jail') or false)
end

local function minutesLeft(src)
    return math.max(0, math.floor((prisoners[src].release - os.time()) / 60))
end

RegisterCommand(Jail.commands.check, function(src)
    if src == 0 then return end
    local sentence = prisoners[src]
    if not sentence then return say(src, Text.jailNoTime) end

    local left = sentence.release - os.time()
    if left <= 0 then
        release(src, 'sentence served')
        return say(src, Text.released)
    end
    say(src, Text.jailLeft:format(math.floor(left / 60), left % 60))
end, false)

RegisterCommand(Jail.commands.jail, function(src, args)
    if src == 0 then return end
    local target = tonumber(args[1])
    if not target then return say(src, Text.jailNoId) end

    local minutes = math.floor(tonumber(args[2]) or 0)
    if minutes < 1 or minutes > Jail.maxMinutes then return say(src, Text.jailBadTime) end

    local targetChar = character(target)
    if not targetChar then return say(src, Text.jailNotOnline) end
    if prisoners[target] then return say(src, Text.jailAlready) end
    if not mayJail(src) then return say(src, Text.jailDenied) end

    prisoners[target] = { release = os.time() + minutes * 60 }
    SetResourceKvp(kvp(targetChar.charIdentifier), json.encode({ minutes = minutes }))

    say(target, Text.jailedFor:format(minutes))
    say(src, Text.jailed)
    log(Config.Logs.Jail, 'Jailed', { 'By: ' .. who(src), 'Prisoner: ' .. who(target), 'Minutes: ' .. minutes })
    SetTimeout(2000, function() TriggerClientEvent('jrs_police:Client:JailPlayer', target) end)
end, false)

RegisterCommand(Jail.commands.unjail, function(src, args)
    if src == 0 then return end
    if not mayJail(src) then return say(src, Text.unjailDenied) end

    local target = tonumber(args[1])
    if not target then return say(src, Text.jailNoId) end
    if not character(target) then return say(src, Text.jailNotOnline) end
    if not prisoners[target] then return say(src, Text.notJailed) end

    release(target, 'released by ' .. who(src))
    say(src, Text.released)
end, false)

RegisterCommand(Jail.commands.change, function(src, args)
    if src == 0 then return end
    if not mayJail(src) then return say(src, Text.changeDenied) end

    local target = tonumber(args[1])
    if not target then return say(src, Text.jailNoId) end

    local change = math.floor(tonumber(args[2]) or 0)
    if change == 0 or math.abs(change) > Jail.maxMinutes then return say(src, Text.noTime) end
    if not prisoners[target] then return say(src, Text.notJailed) end
    if not character(target) then return say(src, Text.jailNotOnline) end

    local before = minutesLeft(target)
    prisoners[target].release = prisoners[target].release + change * 60

    if prisoners[target].release <= os.time() then
        release(target, 'time reduced to nothing')
        return say(src, Text.jailExpired)
    end
    say(src, Text.jailChanged:format(before, minutesLeft(target)))
    log(Config.Logs.Jail, 'Jail time changed', { 'By: ' .. who(src), 'Prisoner: ' .. who(target), 'Change: ' .. change })
end, false)

-- a prisoner who dies is revived at once so they never respawn outside the prison
RegisterNetEvent('jrs_core:Server:OnPlayerDeath', function()
    local src = source
    if not prisoners[src] then return end
    SetTimeout(5000, function() Core.Player.Revive(src) end)
end)

-- the sentence is stored in minutes when the player leaves, and starts again when they come back
AddEventHandler('jrs:SelectedCharacter', function(src, char)
    if not Config.DevMode and Config.Jobs[char.job] then
        TriggerClientEvent('chat:addSuggestion', src, '/' .. Config.MenuCommand, Text.suggestMenu, {})
    end

    local saved = GetResourceKvpString(kvp(char.charIdentifier))
    local data = saved and json.decode(saved)
    if data and not data.minutes then data.minutes = tonumber(data.jailEnd) end     -- older saves
    if not (data and data.minutes) then
        if saved then DeleteResourceKvp(kvp(char.charIdentifier)) end
        return
    end

    SetTimeout(10000, function()
        prisoners[src] = { release = os.time() + data.minutes * 60 }
        TriggerClientEvent('jrs_police:Client:JailPlayer', src)
        TriggerClientEvent('chat:addSuggestion', src, '/' .. Jail.commands.check, Text.jailHint:format(Jail.commands.check), {})
    end)
end)

-- ------------------------------------------------------------------ leaving

AddEventHandler('playerDropped', function()
    local src = source

    local officer = calls[src]
    if officer then
        TriggerClientEvent('jrs_police:Client:RemoveBlip', officer)
        say(officer, Text.dropped)
        if onDuty[officer] then waiting[officer] = true end
        calls[src] = nil
    end
    local caller = callerOf(src)
    if caller then calls[caller] = nil end

    local sentence = prisoners[src]
    local c = character(src)
    if sentence and c then
        local left = sentence.release - os.time()
        if left > 0 then
            SetResourceKvp(kvp(c.charIdentifier), json.encode({ minutes = math.max(1, math.floor(left / 60)) }))
        else
            DeleteResourceKvp(kvp(c.charIdentifier))
        end
    end
    prisoners[src], onDuty[src], waiting[src] = nil, nil, nil
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for index in ipairs(Config.Stations) do ensureStorage(index) end
    if Config.DevMode then print('^1jrs_police dev mode is on^7: never use it on a live server') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for index in ipairs(Config.Stations) do Inv:removeInventory(storageId(index)) end
    for _, id in ipairs(GetPlayers()) do Player(id).state:set('isPoliceDuty', nil, true) end
end)

-- ------------------------------------------------------------------ for other resources

exports('isOnDuty', function(src) return onDuty[src] end)
exports('getPoliceFromCall', function(src) return calls[src] or 0 end)
