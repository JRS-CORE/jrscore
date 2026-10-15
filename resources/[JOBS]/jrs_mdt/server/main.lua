
-- ============================================
-- Configuration State & Validation
-- ============================================
local configVersion = 1

local function validateConfig()
    if not Config.LawJobs then
        Config.LawJobs = {}
        print('[jrs_mdt] ' .. locale('config_warning_missing'))
    end
    
    for jobName, jobConfig in pairs(Config.LawJobs) do
        if not jobConfig.label then
            jobConfig.label = jobName
        end
        if not jobConfig.grades then
            jobConfig.grades = {}
        end
        
        for grade, gradeConfig in pairs(jobConfig.grades) do
            for key, value in pairs(Config.Defaults.jobGrade) do
                if gradeConfig[key] == nil then
                    gradeConfig[key] = value
                end
            end
        end
    end
    
    if not Config.Settings then
        Config.Settings = {
            command = 'mdt',
            requireOnDuty = true,
            maxSearchResults = 50,
            recordRetentionDays = 0,
            warrantExpirationDays = 0,
            debug = false
        }
    end
    
    configVersion = configVersion + 1
    
    if Config.Settings.debug then
        print('[jrs_mdt] ' .. locale('config_validated', configVersion))
    end
end

-- ============================================
-- Config Helper Functions
-- ============================================
local function isLawJob(jobName)
    return Config.LawJobs[jobName] ~= nil
end

local function getGradeConfig(jobName, grade)
    local jobConfig = Config.LawJobs[jobName]
    if not jobConfig then return nil end
    
    local gradeConfig = jobConfig.grades[grade]
    if not gradeConfig then
        return Config.Defaults.jobGrade
    end
    
    return gradeConfig
end

local function hasJobPermission(jobName, grade, permission)
    local gradeConfig = getGradeConfig(jobName, grade)
    if not gradeConfig then return false end
    return gradeConfig[permission] == true
end

-- ============================================
-- Access Validation Functions
-- ============================================
local function hasAccess(source)
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local job = player.PlayerData.job
    if not job then return false end
    
    if not isLawJob(job.name) then return false end
    
    if Config.Settings.requireOnDuty and not job.onduty then
        return false
    end
    
    return true
end

local function hasPermission(source, permission)
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local job = player.PlayerData.job
    if not job then return false end
    
    return hasJobPermission(job.name, job.grade.level, permission)
end

local function getPermissions(source)
    local player = MDTCore.GetPlayer(source)
    if not player then return nil end
    
    local job = player.PlayerData.job
    if not job or not isLawJob(job.name) then
        return nil
    end
    
    return getGradeConfig(job.name, job.grade.level)
end

-- ============================================
-- Server Exports
-- ============================================
exports('hasAccess', hasAccess)
exports('hasPermission', hasPermission)
exports('getPermissions', getPermissions)

exports('getLawJobs', function()
    local jobs = {}
    for jobName, jobConfig in pairs(Config.LawJobs) do
        jobs[jobName] = {
            label = jobConfig.label,
            grades = jobConfig.grades
        }
    end
    return jobs
end)

exports('getSettings', function()
    return Config.Settings
end)

exports('getConfigVersion', function()
    return configVersion
end)

exports('reloadConfig', function()
    Config.LawJobs = {}
    Config.Settings = {}
    
    local configFile = LoadResourceFile(GetCurrentResourceName(), 'shared/config.lua')
    if configFile then
        local loadFunc, err = load(configFile, 'config.lua')
        if loadFunc then
            loadFunc()
            validateConfig()
            return true, locale('config_reloaded', configVersion)
        else
            return false, locale('config_parse_failed', tostring(err))
        end
    end
    return false, locale('config_load_failed')
end)

-- ============================================
-- Server Events (Config)
-- ============================================
RegisterNetEvent('jrs_mdt:server:checkAccess', function()
    local source = source
    local access = hasAccess(source)
    local permissions = access and getPermissions(source) or nil
    
    TriggerClientEvent('jrs_mdt:client:accessResult', source, {
        hasAccess = access,
        permissions = permissions,
        jobLabel = access and MDTCore.GetPlayer(source).PlayerData.job.label or nil
    })
end)

RegisterNetEvent('jrs_mdt:server:checkPermission', function(permission)
    local source = source
    TriggerClientEvent('jrs_mdt:client:permissionResult', source, {
        permission = permission,
        hasPermission = hasPermission(source, permission)
    })
end)

RegisterNetEvent('jrs_mdt:server:reloadConfig', function()
    local source = source
    
    if not hasPermission(source, 'isAdmin') then
        TriggerClientEvent('jrs_mdt:client:notify', source, {
            type = 'error',
            message = locale('notification_no_permission_reload')
        })
        return
    end
    
    local success, message = exports[GetCurrentResourceName()]:reloadConfig()
    
    TriggerClientEvent('jrs_mdt:client:notify', source, {
        type = success and 'success' or 'error',
        message = message
    })
    
    if success then
        local players = MDTCore.GetPlayers()
        for _, playerId in ipairs(players) do
            local target = tonumber(playerId)
            if hasAccess(target) then
                TriggerClientEvent('jrs_mdt:client:configUpdated', target, configVersion)
            end
        end
    end
end)

RegisterNetEvent('jrs_mdt:server:getConfig', function()
    local source = source
    if not hasPermission(source, 'isAdmin') then return end
    
    TriggerClientEvent('jrs_mdt:client:receiveConfig', source, {
        lawJobs = Config.LawJobs,
        settings = Config.Settings,
        version = configVersion
    })
end)

-- ============================================
-- Resource Events
-- ============================================
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    validateConfig()
end)

-- ============================================
-- Callbacks: Citizens
-- ============================================
JRS.Callback('jrs_mdt:server:getAllCitizens', function(source)
    if not hasAccess(source) then return {} end

    local results = MySQL.query.await("SELECT citizenid, charinfo, job FROM jrs_mdt_players")
    if not results then return {} end

    local citizenids = {}
    local citizensMap = {}
    for _, row in ipairs(results) do
        local charinfo = row.charinfo and json.decode(row.charinfo) or {}
        local job = row.job and json.decode(row.job) or {}
        table.insert(citizenids, row.citizenid)
        citizensMap[row.citizenid] = {
            citizenid = row.citizenid,
            charinfo = charinfo,
            job = job,
            isWanted = false
        }
    end

    if #citizenids > 0 then
        local placeholders = {}
        for i = 1, #citizenids do
            table.insert(placeholders, '?')
        end
        local warrantQuery = 'SELECT DISTINCT citizenid FROM mdt_warrants WHERE citizenid IN (' .. table.concat(placeholders, ',') .. ") AND status = 'active'"
        local warrantResults = MySQL.query.await(warrantQuery, citizenids)
        if warrantResults then
            for _, warrant in ipairs(warrantResults) do
                if citizensMap[warrant.citizenid] then
                    citizensMap[warrant.citizenid].isWanted = true
                end
            end
        end
    end

    local citizens = {}
    for _, citizen in pairs(citizensMap) do
        table.insert(citizens, citizen)
    end

    return citizens
end)

JRS.Callback('jrs_mdt:server:searchCitizens', function(source, query)
    if not hasAccess(source) then return {} end

    query = string.lower(query or '')
    if #query < 2 then return {} end

    local searchTerms = {}
    for term in string.gmatch(query, '%S+') do
        table.insert(searchTerms, term)
    end

    local results = MySQL.query.await("SELECT citizenid, charinfo, job FROM jrs_mdt_players")
    if not results then return {} end

    local citizenids = {}
    local citizensMap = {}
    for _, row in ipairs(results) do
        local charinfo = row.charinfo and json.decode(row.charinfo) or {}
        local job = row.job and json.decode(row.job) or {}

        local citizenid = string.lower(row.citizenid or '')
        local firstname = string.lower(charinfo.firstname or '')
        local lastname = string.lower(charinfo.lastname or '')
        local fullname = firstname .. ' ' .. lastname

        local matchesAll = true
        for _, term in ipairs(searchTerms) do
            local matchesTerm = (
                string.find(citizenid, term, 1, true) or
                string.find(firstname, term, 1, true) or
                string.find(lastname, term, 1, true) or
                string.find(fullname, term, 1, true)
            )
            if not matchesTerm then
                matchesAll = false
                break
            end
        end

        if matchesAll then
            table.insert(citizenids, row.citizenid)
            citizensMap[row.citizenid] = {
                citizenid = row.citizenid,
                charinfo = charinfo,
                job = job,
                isWanted = false
            }
        end
    end

    if #citizenids > 0 then
        local placeholders = {}
        for i = 1, #citizenids do
            table.insert(placeholders, '?')
        end
        local warrantQuery = 'SELECT DISTINCT citizenid FROM mdt_warrants WHERE citizenid IN (' .. table.concat(placeholders, ',') .. ") AND status = 'active'"
        local warrantResults = MySQL.query.await(warrantQuery, citizenids)
        if warrantResults then
            for _, warrant in ipairs(warrantResults) do
                if citizensMap[warrant.citizenid] then
                    citizensMap[warrant.citizenid].isWanted = true
                end
            end
        end
    end

    local citizens = {}
    for _, citizen in pairs(citizensMap) do
        table.insert(citizens, citizen)
    end

    return citizens
end)

JRS.Callback('jrs_mdt:server:getCitizen', function(source, citizenid)
    if not hasAccess(source) then return nil end

    local citizen = nil

    local target = MDTCore.GetPlayerByCitizenId(citizenid)
    if target then
        local data = target.PlayerData
        citizen = {
            citizenid = data.citizenid,
            charinfo = data.charinfo,
            job = data.job,
            money = data.money,
            metadata = data.metadata,
            playerId = data.source
        }
    else
        local result = MySQL.query.await(
            'SELECT citizenid, charinfo, job, money, metadata FROM jrs_mdt_players WHERE citizenid = ?',
            { citizenid }
        )

        if result and result[1] then
            local row = result[1]
            citizen = {
                citizenid = row.citizenid,
                charinfo = row.charinfo and json.decode(row.charinfo) or {},
                job = row.job and json.decode(row.job) or {},
                money = row.money and json.decode(row.money) or {},
                metadata = row.metadata and json.decode(row.metadata) or {}
            }
        end
    end

    if citizen then
        local profileResult = MySQL.query.await(
            'SELECT profile_picture FROM mdt_citizen_profiles WHERE citizenid = ?',
            { citizenid }
        )
        citizen.profilePicture = profileResult and profileResult[1] and profileResult[1].profile_picture or nil

        local warrantResult = MySQL.query.await(
            "SELECT id FROM mdt_warrants WHERE citizenid = ? AND status = 'active' LIMIT 1",
            { citizenid }
        )
        citizen.isWanted = warrantResult and warrantResult[1] ~= nil

        local recordsResult = MySQL.query.await(
            'SELECT * FROM mdt_records WHERE citizenid = ? ORDER BY created_at DESC',
            { citizenid }
        )
        citizen.records = recordsResult or {}
    end

    return citizen
end)

JRS.Callback('jrs_mdt:server:setProfilePicture', function(source, data)
    if not hasAccess(source) or not hasPermission(source, 'canCreateRecords') then return false end

    local citizenid = data.citizenid
    local pictureUrl = data.url

    if not citizenid then return false end

    -- Use INSERT ... ON DUPLICATE KEY UPDATE for upsert
    MySQL.query.await(
        'INSERT INTO mdt_citizen_profiles (citizenid, profile_picture) VALUES (?, ?) ON DUPLICATE KEY UPDATE profile_picture = ?',
        { citizenid, pictureUrl, pictureUrl }
    )

    return true
end)

-- ============================================
-- Callbacks: Criminal Records
-- ============================================
JRS.Callback('jrs_mdt:server:getRecords', function(source, citizenid)
    if not hasAccess(source) then return {} end
    
    local query = citizenid 
        and 'SELECT * FROM mdt_records WHERE citizenid = ? ORDER BY created_at DESC'
        or 'SELECT * FROM mdt_records ORDER BY created_at DESC'
    
    local params = citizenid and { citizenid } or {}
    local results = MySQL.query.await(query, params)
    return results or {}
end)

JRS.Callback('jrs_mdt:server:addRecord', function(source, data)
    if not hasAccess(source) or not hasPermission(source, 'canCreateRecords') then return false end
    
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    
    local insertId = MySQL.insert.await(
        'INSERT INTO mdt_records (citizenid, name, crime, description, fine, jailtime, officer, officer_cid) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { data.citizenid, data.name, data.crime, data.description, data.fine or 0, data.jailtime or 0, officerName, officerCid }
    )
    
    return insertId and true or false
end)

JRS.Callback('jrs_mdt:server:deleteRecord', function(source, recordId)
    if not hasAccess(source) or not hasPermission(source, 'canDeleteRecords') then return false end
    
    local affectedRows = MySQL.query.await('DELETE FROM mdt_records WHERE id = ?', { recordId })
    return affectedRows and affectedRows.affectedRows > 0
end)

-- ============================================
-- Callbacks: Warrants
-- ============================================
JRS.Callback('jrs_mdt:server:getWarrants', function(source)
    if not hasAccess(source) then return {} end
    
    local results = MySQL.query.await('SELECT * FROM mdt_warrants ORDER BY created_at DESC')
    return results or {}
end)

JRS.Callback('jrs_mdt:server:addWarrant', function(source, data)
    if not hasAccess(source) or not hasPermission(source, 'canManageWarrants') then return false end
    
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    
    local insertId = MySQL.insert.await(
        'INSERT INTO mdt_warrants (citizenid, name, reason, status, officer, officer_cid) VALUES (?, ?, ?, ?, ?, ?)',
        { data.citizenid, data.name, data.reason, 'active', officerName, officerCid }
    )
    
    return insertId and true or false
end)

JRS.Callback('jrs_mdt:server:updateWarrant', function(source, data)
    if not hasAccess(source) or not hasPermission(source, 'canManageWarrants') then return false end
    
    local affectedRows = MySQL.query.await(
        'UPDATE mdt_warrants SET status = ? WHERE id = ?',
        { data.status, data.id }
    )
    return affectedRows and affectedRows.affectedRows > 0
end)

JRS.Callback('jrs_mdt:server:deleteWarrant', function(source, warrantId)
    if not hasAccess(source) or not hasPermission(source, 'canManageWarrants') then return false end
    
    local affectedRows = MySQL.query.await('DELETE FROM mdt_warrants WHERE id = ?', { warrantId })
    return affectedRows and affectedRows.affectedRows > 0
end)

-- ============================================
-- Callbacks: BOLOs
-- ============================================
JRS.Callback('jrs_mdt:server:getBolos', function(source)
    if not hasAccess(source) then return {} end
    
    local results = MySQL.query.await('SELECT * FROM mdt_bolos ORDER BY created_at DESC')
    return results or {}
end)

JRS.Callback('jrs_mdt:server:addBolo', function(source, data)
    if not hasAccess(source) then return false end
    
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    
    local insertId = MySQL.insert.await(
        'INSERT INTO mdt_bolos (title, description, last_seen, officer, officer_cid) VALUES (?, ?, ?, ?, ?)',
        { data.title, data.description, data.lastSeen, officerName, officerCid }
    )
    
    return insertId and true or false
end)

JRS.Callback('jrs_mdt:server:deleteBolo', function(source, boloId)
    if not hasAccess(source) or not hasPermission(source, 'canDeleteRecords') then return false end
    
    local affectedRows = MySQL.query.await('DELETE FROM mdt_bolos WHERE id = ?', { boloId })
    return affectedRows and affectedRows.affectedRows > 0
end)

-- ============================================
-- Callbacks: Reports
-- ============================================
JRS.Callback('jrs_mdt:server:getReports', function(source)
    if not hasAccess(source) then return {} end
    
    local results = MySQL.query.await('SELECT * FROM mdt_reports ORDER BY created_at DESC')
    if not results then return {} end
    
    for _, report in ipairs(results) do
        if type(report.officers) == 'string' then
            report.officers = json.decode(report.officers) or {}
        end
        if type(report.suspects) == 'string' then
            report.suspects = json.decode(report.suspects) or {}
        end
        if type(report.evidence) == 'string' then
            report.evidence = json.decode(report.evidence) or {}
        end
        
        local linkedCharges = MySQL.query.await([[
            SELECT 
                ca.charge_id,
                ic.charge_name,
                ic.citizen_name,
                ic.fine,
                ic.jailtime,
                ic.officer
            FROM mdt_charge_attachments ca
            INNER JOIN mdt_issued_charges ic ON ca.charge_id = ic.id
            WHERE ca.report_id = ?
            ORDER BY ca.attached_at DESC
            LIMIT 1
        ]], { report.id })
        
        if linkedCharges and linkedCharges[1] then
            report.linkedCharge = linkedCharges[1]
        else
            report.linkedCharge = nil
        end
    end
    
    return results
end)

JRS.Callback('jrs_mdt:server:getReport', function(source, reportId)
    if not hasAccess(source) then return nil end
    
    local results = MySQL.query.await('SELECT * FROM mdt_reports WHERE id = ?', { reportId })
    local report = results and results[1] or nil
    
    if report then
        if type(report.officers) == 'string' then
            report.officers = json.decode(report.officers) or {}
        end
        if type(report.suspects) == 'string' then
            report.suspects = json.decode(report.suspects) or {}
        end
        if type(report.evidence) == 'string' then
            report.evidence = json.decode(report.evidence) or {}
        end
    end
    
    return report
end)

JRS.Callback('jrs_mdt:server:createReport', function(source, data)
    if not hasAccess(source) or not hasPermission(source, 'canCreateRecords') then return false end
    
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    
    local insertId = MySQL.insert.await(
        'INSERT INTO mdt_reports (title, type, description, officers, suspects, evidence, officer, officer_cid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { 
            data.title, 
            data.type or 'incident', 
            data.description,
            json.encode(data.officers or {}),
            json.encode(data.suspects or {}),
            json.encode(data.evidence or {}),
            officerName,
            officerCid,
            timestamp
        }
    )
    
    return insertId and true or false
end)

JRS.Callback('jrs_mdt:server:deleteReport', function(source, reportId)
    if not hasAccess(source) or not hasPermission(source, 'canDeleteRecords') then return false end
    
    local affectedRows = MySQL.query.await('DELETE FROM mdt_reports WHERE id = ?', { reportId })
    return affectedRows and affectedRows.affectedRows > 0
end)

-- Report Comments
JRS.Callback('jrs_mdt:server:getReportComments', function(source, reportId)
    if not hasAccess(source) then return {} end
    
    local results = MySQL.query.await('SELECT * FROM mdt_report_comments WHERE report_id = ? ORDER BY created_at ASC', { reportId })
    return results or {}
end)

JRS.Callback('jrs_mdt:server:addReportComment', function(source, data)
    if not hasAccess(source) or not hasPermission(source, 'canCreateRecords') then return false end
    
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    
    local insertId = MySQL.insert.await(
        'INSERT INTO mdt_report_comments (report_id, author, author_cid, content, created_at) VALUES (?, ?, ?, ?, ?)',
        { data.reportId, officerName, officerCid, data.content, timestamp }
    )
    
    return insertId and true or false
end)

-- ============================================
-- Callbacks: Officer Info & Stats
-- ============================================
JRS.Callback('jrs_mdt:server:getOfficerInfo', function(source)
    if not hasAccess(source) then return nil end
    
    local player = MDTCore.GetPlayer(source)
    if not player then return nil end
    
    return {
        name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
        citizenid = player.PlayerData.citizenid,
        job = player.PlayerData.job,
        permissions = getPermissions(source)
    }
end)

JRS.Callback('jrs_mdt:server:getStats', function(source)
    if not hasAccess(source) then return nil end
    
    local recordCount = MySQL.query.await('SELECT COUNT(*) as count FROM mdt_records')
    local activeWarrants = MySQL.query.await("SELECT COUNT(*) as count FROM mdt_warrants WHERE status = 'active'")
    local boloCount = MySQL.query.await('SELECT COUNT(*) as count FROM mdt_bolos')
    local reportCount = MySQL.query.await('SELECT COUNT(*) as count FROM mdt_reports')
    local unpaidFines = MySQL.query.await("SELECT COUNT(*) as count FROM mdt_fines WHERE status IN ('unpaid', 'overdue')")
    
    return {
        records = recordCount and recordCount[1] and recordCount[1].count or 0,
        activeWarrants = activeWarrants and activeWarrants[1] and activeWarrants[1].count or 0,
        activeBolos = boloCount and boloCount[1] and boloCount[1].count or 0,
        reports = reportCount and reportCount[1] and reportCount[1].count or 0,
        unpaidFines = unpaidFines and unpaidFines[1] and unpaidFines[1].count or 0
    }
end)

-- ============================================
-- Callbacks: Config Data
-- ============================================
JRS.Callback('jrs_mdt:server:getIncidentTypes', function(source)
    if not hasAccess(source) then return {} end
    return Config.IncidentTypes or {}
end)
