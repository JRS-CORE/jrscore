-- jrs_medic | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_medic | server
-- Duty, hiring, storage, healing items and emergency calls. Every request is checked here: the player's
-- job and grade, distance, and duty.

local Core = exports.jrs_core:GetCore()
local Inv  = exports.jrs_inventory
local Text = Config.Text[Config.Language] or Config.Text.en

local onDuty  = {}            -- player -> true while on duty
local calls   = {}            -- caller -> doctor answering
local waiting = {}            -- doctors on duty that are free to take a call

-- ------------------------------------------------------------------ small helpers

local function character(src)
    local user = Core.getUser(src)
    return user and user.getUsedCharacter, user
end

local function say(src, line, ms) Core.NotifyObjective(src, line, ms or 5000) end

local function rankOf(src)                       -- the grade table of this player's medic job, or nil
    local c = character(src)
    local grades = c and Config.Jobs[c.job]
    return grades and grades[c.jobGrade], c
end

local function isManager(src)
    local rank = rankOf(src)
    return rank and rank.manager == true
end

local function storageId(index)
    return Config.ShareStorage and 'jrs_medic_storage' or ('jrs_medic_storage_' .. index)
end

local function near(src, target, range)
    target = tonumber(target)
    if not target or target <= 0 or not GetPlayerName(target) then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) <= range
end

local function log(url, title, lines)
    if not url or url == '' then return end
    local L = Config.Logs
    Core.AddWebhook(title, url, table.concat(lines, '\n'), L.color, L.name, L.logo, L.footer, L.avatar)
end

local function who(src)
    local c = character(src)
    return ('%s %s (%s, id %d)'):format(c.firstname, c.lastname, GetPlayerName(src), src)
end

-- ------------------------------------------------------------------ storage

local function ensureStorage(index)
    local id = storageId(index)
    if not Inv:isCustomInventoryRegistered(id) then
        Inv:registerInventory({
            id = id, name = 'Medical storage', limit = Config.StorageLimit, acceptWeapons = true, shared = true,
            ignoreItemStackLimit = true, whitelistItems = false, UsePermissions = false, UseBlackList = false,
            whitelistWeapons = false, webhook = Config.Logs.Storage,
        })
    end
    return id
end

RegisterNetEvent('jrs_medic:Server:OpenStorage', function(index)
    local src = source
    if not rankOf(src) then return say(src, Text.notDoctor) end
    if not onDuty[src] then return say(src, Text.notOnDuty) end

    local station = Config.Stations[tonumber(index) or 0]
    if not station or #(GetEntityCoords(GetPlayerPed(src)) - station.storage) > Config.Reach + 3.0 then return end
    Inv:openInventory(src, ensureStorage(index))
end)

-- ------------------------------------------------------------------ duty

local function setDuty(src, on)
    onDuty[src] = on or nil
    waiting[src] = on or nil
    Player(src).state:set('isMedicDuty', on or false, true)
end

Core.Callback.Register('jrs_medic:server:checkDuty', function(src, cb)
    local rank = rankOf(src)
    if not rank then return cb(false) end

    local turnOn = not onDuty[src]
    setDuty(src, turnOn)
    log(Config.Logs.Duty, turnOn and 'Medic On Duty' or 'Medic Off Duty', { who(src) })
    cb(turnOn)
end)

local function openMenu(src)
    if not rankOf(src) then return say(src, Text.notDoctor) end
    TriggerClientEvent('jrs_medic:Client:OpenMedicMenu', src)
end

-- ------------------------------------------------------------------ hiring and firing

RegisterNetEvent('jrs_medic:server:hirePlayer', function(targetId, job, grade)
    local src = source
    if not isManager(src) then return say(src, Text.notDoctor) end

    local target = tonumber(targetId)
    local targetChar = target and character(target)
    if not targetChar then return say(src, Text.notFound) end

    grade = tonumber(grade)
    local rank = Config.Jobs[job] and grade and Config.Jobs[job][grade]
    if not rank then return say(src, Text.notDoctor) end
    if not rank.label then return print(Text.noLabel) end
    if targetChar.job == job then return say(src, Text.alreadyHired .. rank.label) end
    if not near(src, target, 5.0) then return say(src, Text.notNear) end

    targetChar.setJob(job, true)
    targetChar.setJobGrade(grade, true)
    targetChar.setJobLabel(rank.label, true)

    say(target, Text.hired .. rank.label)
    say(src, Text.hirePlayer)
    TriggerClientEvent('jrs_medic:Client:JobUpdate', target)
    log(Config.Logs.Hire, 'Medic Hired', { 'By: ' .. who(src), 'Hired: ' .. who(target), 'Job: ' .. rank.label })
end)

RegisterNetEvent('jrs_medic:server:firePlayer', function(targetId)
    local src = source
    if not isManager(src) then return say(src, Text.notDoctor) end

    local target = tonumber(targetId)
    local targetChar = target and character(target)
    if not targetChar then return say(src, Text.notFound) end

    local grades = Config.Jobs[targetChar.job]
    if not grades then return say(src, Text.cantFire) end
    if target == src then return say(src, Text.notDoctor) end

    targetChar.setJob('unemployed', true)
    targetChar.setJobGrade(0, true)
    targetChar.setJobLabel('Unemployed', true)

    say(target, Text.fired)
    say(src, Text.youFired)
    if onDuty[target] then setDuty(target, false) end
    TriggerClientEvent('jrs_medic:Client:JobUpdate', target)
    log(Config.Logs.Hire, 'Medic Fired', { 'By: ' .. who(src), 'Fired: ' .. who(target) })
end)

AddEventHandler('jrs:playerJobChange', function(src, newJob)
    if Config.Jobs[newJob] then TriggerClientEvent('jrs_medic:Client:JobUpdate', src) end
end)

-- ------------------------------------------------------------------ healing items

local function closestOther(src, selfIfNone)
    local here = GetEntityCoords(GetPlayerPed(src))
    local best, bestAway = nil, 3.0
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id ~= src then
            local away = #(here - GetEntityCoords(GetPlayerPed(id)))
            if away <= bestAway then best, bestAway = id, away end
        end
    end
    return best or (selfIfNone and src or nil)
end

local function deadPlayer(id)
    if not Core.getUser(id) then return false end
    local ped = GetPlayerPed(id)
    return Player(id).state.isDead == true or (ped ~= 0 and GetEntityHealth(ped) <= 0)
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

    for name, item in pairs(Config.Items) do
        Inv:registerUsableItem(name, function(data)
            local src = data.source
            Inv:closeInventory(src)

            if item.onDuty and not onDuty[src] then return say(src, Text.notOnDuty) end

            if item.revive then
                local patient = closestOther(src, false)
                if not patient then return say(src, Text.nobodyToRevive) end
                if not deadPlayer(patient) then return say(src, Text.notDead) end

                TriggerClientEvent('jrs_medic:Client:ReviveAnim', src)
                SetTimeout(3000, function() Core.Player.Revive(patient) end)
            else
                local patient = closestOther(src, true)
                TriggerClientEvent('jrs_medic:Client:HealAnim', src)
                TriggerClientEvent('jrs_medic:Client:HealPlayer', patient, item.health, item.stamina)
            end
            Inv:subItemById(src, data.item.id)
        end, GetCurrentResourceName())
    end
end)

-- ------------------------------------------------------------------ emergency calls

local function nearestFreeDoctor(origin)
    local best, bestAway = nil, math.huge
    for doctor in pairs(waiting) do
        local away = #(origin - GetEntityCoords(GetPlayerPed(doctor)))
        if away < bestAway then best, bestAway = doctor, away end
    end
    return best
end

local function callerOf(doctor)
    for caller, d in pairs(calls) do
        if d == doctor then return caller end
    end
end

RegisterCommand(Config.CallCommand, function(src)
    if src == 0 then return end
    if calls[src] then return Core.NotifyRightTip(src, Text.alreadyCalled, 5000) end
    if not next(waiting) then return Core.NotifyRightTip(src, Text.noDoctors, 5000) end

    local c = character(src)
    if Config.OnlyDeadCanCall and not (c and c.isdead) then return say(src, Text.notDeadCall) end

    local origin = GetEntityCoords(GetPlayerPed(src))
    local doctor = nearestFreeDoctor(origin)
    if not doctor then return Core.NotifyRightTip(src, Text.noDoctors, 5000) end

    waiting[doctor] = nil                      -- busy until the call ends
    calls[src] = doctor
    say(doctor, Text.needsHelp)
    TriggerClientEvent('jrs_medic:Client:AlertDoctor', doctor, origin)
    Core.NotifyRightTip(src, Text.alerted, 5000)
end, false)

RegisterCommand(Config.CancelCommand, function(src)
    if src == 0 then return end
    local doctor = calls[src]
    if not doctor then return Core.NotifyRightTip(src, Text.noCall, 5000) end

    if Core.getUser(doctor) then
        TriggerClientEvent('jrs_medic:Client:RemoveBlip', doctor)
        say(doctor, Text.canceledByPlayer)
        if onDuty[doctor] then waiting[doctor] = true end
    end
    calls[src] = nil
    Core.NotifyRightTip(src, Text.canceled, 5000)
end, false)

RegisterCommand(Config.FinishCommand, function(src)
    if src == 0 then return end
    if not rankOf(src) then return say(src, Text.notDoctor) end
    if not onDuty[src] and not callerOf(src) then return say(src, Text.notOnDuty) end

    local caller = callerOf(src)
    if not caller then return say(src, Text.notOnCall) end

    TriggerClientEvent('jrs_medic:Client:RemoveBlip', src)
    say(src, Text.canceled)
    Core.NotifyRightTip(caller, Text.canceledByDoctor, 5000)
    calls[caller] = nil
    if onDuty[src] then waiting[src] = true end
end, false)

RegisterCommand(Config.MenuCommand, function(src)
    if src ~= 0 and (Config.DevMode or rankOf(src)) then openMenu(src) end
end, false)

-- ------------------------------------------------------------------ cleanup

AddEventHandler('playerDropped', function()
    local src = source

    local doctor = calls[src]
    if doctor then
        TriggerClientEvent('jrs_medic:Client:RemoveBlip', doctor)
        say(doctor, Text.dropped)
        if onDuty[doctor] then waiting[doctor] = true end
        calls[src] = nil
    end

    local caller = callerOf(src)
    if caller then calls[caller] = nil end
    onDuty[src], waiting[src] = nil, nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for index in ipairs(Config.Stations) do Inv:removeInventory(storageId(index)) end
    for _, id in ipairs(GetPlayers()) do Player(id).state:set('isMedicDuty', nil, true) end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for index in ipairs(Config.Stations) do ensureStorage(index) end
end)

-- ------------------------------------------------------------------ for other resources

exports('isOnDuty', function(src) return onDuty[src] end)
exports('getDoctorFromCall', function(src) return calls[src] or 0 end)
