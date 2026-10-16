-- jrs_mdt | server: access, citizens, records, warrants, BOLOs, reports and the home numbers
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local configVersion = 1

-- fills in whatever the config left out
local function normaliseConfig()
    Config.LawJobs = Config.LawJobs or {}
    Config.Settings = Config.Settings or {
        command = 'mdt', requireOnDuty = true, maxSearchResults = 50, recordRetentionDays = 0, warrantExpirationDays = 0, debug = false,
    }

    for jobName, job in pairs(Config.LawJobs) do
        job.label = job.label or jobName
        job.grades = job.grades or {}
        for _, grade in pairs(job.grades) do
            for key, value in pairs(Config.Defaults.jobGrade) do
                if grade[key] == nil then grade[key] = value end
            end
        end
    end

    configVersion = configVersion + 1
    if Config.Settings.debug then print('[jrs_mdt] ' .. locale('config_validated', configVersion)) end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then normaliseConfig() end
end)

-- ------------------------------------------------------------------ exports

exports('hasAccess', MDT.Access)
exports('getPermissions', MDT.Grade)
exports('getSettings', function() return Config.Settings end)
exports('getConfigVersion', function() return configVersion end)

exports('getLawJobs', function()
    local jobs = {}
    for name, job in pairs(Config.LawJobs) do jobs[name] = { label = job.label, grades = job.grades } end
    return jobs
end)

-- loads shared/config.lua again without a restart
exports('reloadConfig', function()
    local text = LoadResourceFile(GetCurrentResourceName(), 'shared/config.lua')
    if not text then return false, locale('config_load_failed') end

    Config.LawJobs, Config.Settings = {}, {}
    local chunk, err = load(text, 'config.lua')
    if not chunk then return false, locale('config_parse_failed', tostring(err)) end

    chunk()
    normaliseConfig()
    return true, locale('config_reloaded', configVersion)
end)

-- ------------------------------------------------------------------ access events

RegisterNetEvent('jrs_mdt:server:checkAccess', function()
    local src = source
    local allowed = MDT.Access(src)
    TriggerClientEvent('jrs_mdt:client:accessResult', src, {
        hasAccess = allowed,
        permissions = allowed and MDT.Grade(src) or nil,
        jobLabel = allowed and MDTCore.GetPlayer(src).PlayerData.job.label or nil,
    })
end)

RegisterNetEvent('jrs_mdt:server:checkPermission', function(permission)
    local src = source
    TriggerClientEvent('jrs_mdt:client:permissionResult', src, { permission = permission, hasPermission = MDT.Can(src, permission) })
end)

RegisterNetEvent('jrs_mdt:server:reloadConfig', function()
    local src = source
    if not MDT.Can(src, 'isAdmin') then
        return TriggerClientEvent('jrs_mdt:client:notify', src, { type = 'error', message = locale('notification_no_permission_reload') })
    end

    local ok, message = exports[GetCurrentResourceName()]:reloadConfig()
    TriggerClientEvent('jrs_mdt:client:notify', src, { type = ok and 'success' or 'error', message = message })

    if ok then
        for _, id in ipairs(MDTCore.GetPlayers()) do
            if MDT.Access(tonumber(id)) then TriggerClientEvent('jrs_mdt:client:configUpdated', tonumber(id), configVersion) end
        end
    end
end)

RegisterNetEvent('jrs_mdt:server:getConfig', function()
    local src = source
    if not MDT.Can(src, 'isAdmin') then return end
    TriggerClientEvent('jrs_mdt:client:receiveConfig', src, { lawJobs = Config.LawJobs, settings = Config.Settings, version = configVersion })
end)

-- a callback that only runs for officers; `fallback` is what everybody else gets
local function lawCallback(name, fallback, permission, handler)
    JRS.Callback(name, function(src, ...)
        if not MDT.Access(src) or (permission and not MDT.Can(src, permission)) then return fallback end
        return handler(src, ...)
    end)
end

-- ------------------------------------------------------------------ citizens

-- marks every citizen in `byId` that has an active warrant
local function markWanted(byId)
    local ids = {}
    for id in pairs(byId) do ids[#ids + 1] = id end
    if #ids == 0 then return end

    local rows = MySQL.query.await("SELECT DISTINCT citizenid FROM mdt_warrants WHERE citizenid IN " .. MDT.Marks(ids) .. " AND status = 'active'", ids)
    for _, row in ipairs(rows or {}) do
        if byId[row.citizenid] then byId[row.citizenid].isWanted = true end
    end
end

-- every character that passes `keep(row, charinfo)`
local function citizenList(keep)
    local byId = {}
    for _, row in ipairs(MySQL.query.await('SELECT citizenid, charinfo, job FROM jrs_mdt_players') or {}) do
        local info = row.charinfo and json.decode(row.charinfo) or {}
        if not keep or keep(row, info) then
            byId[row.citizenid] = { citizenid = row.citizenid, charinfo = info, job = row.job and json.decode(row.job) or {}, isWanted = false }
        end
    end

    markWanted(byId)
    local list = {}
    for _, citizen in pairs(byId) do list[#list + 1] = citizen end
    return list
end

lawCallback('jrs_mdt:server:getAllCitizens', {}, nil, function() return citizenList() end)

-- every word of the search has to appear in the id or the name
lawCallback('jrs_mdt:server:searchCitizens', {}, nil, function(_, query)
    query = string.lower(query or '')
    if #query < 2 then return {} end

    local words = {}
    for word in query:gmatch('%S+') do words[#words + 1] = word end

    return citizenList(function(row, info)
        local first, last = (info.firstname or ''):lower(), (info.lastname or ''):lower()
        local haystack = (row.citizenid or ''):lower() .. ' ' .. first .. ' ' .. last .. ' ' .. first .. ' ' .. last
        for _, word in ipairs(words) do
            if not haystack:find(word, 1, true) then return false end
        end
        return true
    end)
end)

-- the full file of one citizen: live data when online, the character table otherwise
lawCallback('jrs_mdt:server:getCitizen', nil, nil, function(_, citizenid)
    local citizen
    local online = MDTCore.GetPlayerByCitizenId(citizenid)
    if online then
        local data = online.PlayerData
        citizen = {
            citizenid = data.citizenid, charinfo = data.charinfo, job = data.job, money = data.money,
            metadata = data.metadata, playerId = data.source,
        }
    else
        local row = MySQL.query.await('SELECT citizenid, charinfo, job, money, metadata FROM jrs_mdt_players WHERE citizenid = ?', { citizenid })
        row = row and row[1]
        if row then
            citizen = {
                citizenid = row.citizenid,
                charinfo = row.charinfo and json.decode(row.charinfo) or {}, job = row.job and json.decode(row.job) or {},
                money = row.money and json.decode(row.money) or {}, metadata = row.metadata and json.decode(row.metadata) or {},
            }
        end
    end
    if not citizen then return nil end

    local profile = MySQL.query.await('SELECT profile_picture FROM mdt_citizen_profiles WHERE citizenid = ?', { citizenid })
    citizen.profilePicture = profile and profile[1] and profile[1].profile_picture or nil

    local warrant = MySQL.query.await("SELECT id FROM mdt_warrants WHERE citizenid = ? AND status = 'active' LIMIT 1", { citizenid })
    citizen.isWanted = warrant ~= nil and warrant[1] ~= nil

    citizen.records = MySQL.query.await('SELECT * FROM mdt_records WHERE citizenid = ? ORDER BY created_at DESC', { citizenid }) or {}
    return citizen
end)

lawCallback('jrs_mdt:server:setProfilePicture', false, 'canCreateRecords', function(_, data)
    if not data.citizenid then return false end
    MySQL.query.await('INSERT INTO mdt_citizen_profiles (citizenid, profile_picture) VALUES (?, ?) ON DUPLICATE KEY UPDATE profile_picture = ?',
        { data.citizenid, data.url, data.url })
    return true
end)

-- ------------------------------------------------------------------ criminal records

lawCallback('jrs_mdt:server:getRecords', {}, nil, function(_, citizenid)
    if citizenid then return MySQL.query.await('SELECT * FROM mdt_records WHERE citizenid = ? ORDER BY created_at DESC', { citizenid }) or {} end
    return MySQL.query.await('SELECT * FROM mdt_records ORDER BY created_at DESC') or {}
end)

lawCallback('jrs_mdt:server:addRecord', false, 'canCreateRecords', function(src, data)
    local officer, cid = MDT.Officer(src)
    if not officer then return false end

    local id = MySQL.insert.await(
        'INSERT INTO mdt_records (citizenid, name, crime, description, fine, jailtime, officer, officer_cid) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { data.citizenid, data.name, data.crime, data.description, data.fine or 0, data.jailtime or 0, officer, cid })
    return id ~= nil
end)

lawCallback('jrs_mdt:server:deleteRecord', false, 'canDeleteRecords', function(_, id)
    return MDT.Touched(MySQL.query.await('DELETE FROM mdt_records WHERE id = ?', { id }))
end)

-- ------------------------------------------------------------------ warrants

lawCallback('jrs_mdt:server:getWarrants', {}, nil, function()
    return MySQL.query.await('SELECT * FROM mdt_warrants ORDER BY created_at DESC') or {}
end)

lawCallback('jrs_mdt:server:addWarrant', false, 'canManageWarrants', function(src, data)
    local officer, cid = MDT.Officer(src)
    if not officer then return false end

    local id = MySQL.insert.await('INSERT INTO mdt_warrants (citizenid, name, reason, status, officer, officer_cid) VALUES (?, ?, ?, ?, ?, ?)',
        { data.citizenid, data.name, data.reason, 'active', officer, cid })
    return id ~= nil
end)

lawCallback('jrs_mdt:server:updateWarrant', false, 'canManageWarrants', function(_, data)
    return MDT.Touched(MySQL.query.await('UPDATE mdt_warrants SET status = ? WHERE id = ?', { data.status, data.id }))
end)

lawCallback('jrs_mdt:server:deleteWarrant', false, 'canManageWarrants', function(_, id)
    return MDT.Touched(MySQL.query.await('DELETE FROM mdt_warrants WHERE id = ?', { id }))
end)

-- ------------------------------------------------------------------ BOLOs

lawCallback('jrs_mdt:server:getBolos', {}, nil, function()
    return MySQL.query.await('SELECT * FROM mdt_bolos ORDER BY created_at DESC') or {}
end)

lawCallback('jrs_mdt:server:addBolo', false, nil, function(src, data)
    local officer, cid = MDT.Officer(src)
    if not officer then return false end

    local id = MySQL.insert.await('INSERT INTO mdt_bolos (title, description, last_seen, officer, officer_cid) VALUES (?, ?, ?, ?, ?)',
        { data.title, data.description, data.lastSeen, officer, cid })
    return id ~= nil
end)

lawCallback('jrs_mdt:server:deleteBolo', false, 'canDeleteRecords', function(_, id)
    return MDT.Touched(MySQL.query.await('DELETE FROM mdt_bolos WHERE id = ?', { id }))
end)

-- ------------------------------------------------------------------ reports

lawCallback('jrs_mdt:server:getReports', {}, nil, function()
    local reports = MDT.Decode(MySQL.query.await('SELECT * FROM mdt_reports ORDER BY created_at DESC'), 'officers', 'suspects', 'evidence')

    -- the newest charge attached to each report, for the list view
    for _, report in ipairs(reports) do
        local linked = MySQL.query.await([[
            SELECT ca.charge_id, ic.charge_name, ic.citizen_name, ic.fine, ic.jailtime, ic.officer
            FROM mdt_charge_attachments ca
            INNER JOIN mdt_issued_charges ic ON ca.charge_id = ic.id
            WHERE ca.report_id = ?
            ORDER BY ca.attached_at DESC
            LIMIT 1
        ]], { report.id })
        report.linkedCharge = linked and linked[1] or nil
    end
    return reports
end)

lawCallback('jrs_mdt:server:getReport', nil, nil, function(_, id)
    local rows = MDT.Decode(MySQL.query.await('SELECT * FROM mdt_reports WHERE id = ?', { id }), 'officers', 'suspects', 'evidence')
    return rows[1]
end)

lawCallback('jrs_mdt:server:createReport', false, 'canCreateRecords', function(src, data)
    local officer, cid = MDT.Officer(src)
    if not officer then return false end

    local id = MySQL.insert.await(
        'INSERT INTO mdt_reports (title, type, description, officers, suspects, evidence, officer, officer_cid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { data.title, data.type or 'incident', data.description, json.encode(data.officers or {}), json.encode(data.suspects or {}),
          json.encode(data.evidence or {}), officer, cid, os.date('%Y-%m-%d %H:%M:%S') })
    return id ~= nil
end)

lawCallback('jrs_mdt:server:deleteReport', false, 'canDeleteRecords', function(_, id)
    return MDT.Touched(MySQL.query.await('DELETE FROM mdt_reports WHERE id = ?', { id }))
end)

lawCallback('jrs_mdt:server:getReportComments', {}, nil, function(_, reportId)
    return MySQL.query.await('SELECT * FROM mdt_report_comments WHERE report_id = ? ORDER BY created_at ASC', { reportId }) or {}
end)

lawCallback('jrs_mdt:server:addReportComment', false, 'canCreateRecords', function(src, data)
    local officer, cid = MDT.Officer(src)
    if not officer then return false end

    local id = MySQL.insert.await('INSERT INTO mdt_report_comments (report_id, author, author_cid, content, created_at) VALUES (?, ?, ?, ?, ?)',
        { data.reportId, officer, cid, data.content, os.date('%Y-%m-%d %H:%M:%S') })
    return id ~= nil
end)

-- ------------------------------------------------------------------ the officer and the home numbers

lawCallback('jrs_mdt:server:getOfficerInfo', nil, nil, function(src)
    local officer, cid, player = MDT.Officer(src)
    if not officer then return nil end
    return { name = officer, citizenid = cid, job = player.PlayerData.job, permissions = MDT.Grade(src) }
end)

local function countOf(sql)
    local row = MySQL.query.await(sql)
    return row and row[1] and row[1].count or 0
end

lawCallback('jrs_mdt:server:getStats', nil, nil, function()
    return {
        records = countOf('SELECT COUNT(*) AS count FROM mdt_records'),
        activeWarrants = countOf("SELECT COUNT(*) AS count FROM mdt_warrants WHERE status = 'active'"),
        activeBolos = countOf('SELECT COUNT(*) AS count FROM mdt_bolos'),
        reports = countOf('SELECT COUNT(*) AS count FROM mdt_reports'),
        unpaidFines = countOf("SELECT COUNT(*) AS count FROM mdt_fines WHERE status IN ('unpaid', 'overdue')"),
    }
end)

lawCallback('jrs_mdt:server:getIncidentTypes', {}, nil, function() return Config.IncidentTypes or {} end)
