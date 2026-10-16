-- jrs_mdt | server: MDT staff, roles, the audit log and moving officers between departments
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local DEFAULT_ROLES <const> = { admin = true, supervisor = true, officer = true }

-- a callback for MDT admins only; `fallback` (a value or a function) answers everybody else
local function adminCallback(name, fallback, handler)
    JRS.Callback(name, function(src, ...)
        if not MDT.Can(src, 'isAdmin') then
            if type(fallback) == 'function' then return fallback() end
            return fallback
        end
        return handler(src, ...)
    end)
end

local function denied() return MDT.Fail('notification_permission_denied') end

local function isStaff(citizenid)
    local row = MySQL.query.await('SELECT id FROM mdt_staff WHERE citizenid = ?', { citizenid })
    return row ~= nil and row[1] ~= nil
end

local function staffRow(citizenid, columns)
    local row = MySQL.query.await('SELECT ' .. columns .. ' FROM mdt_staff WHERE citizenid = ?', { citizenid })
    return row and row[1]
end

-- LIKE pattern for a search text
local function like(query) return '%' .. query .. '%' end

-- ------------------------------------------------------------------ jobs of law officers

local function lawJobOf(player)
    local job = player.PlayerData.job
    return job and job.name and Config.LawJobs[job.name] ~= nil
end

-- takes the law job(s) off a player so the new one is the only one
local function clearLawJobs(player)
    if lawJobOf(player) then player.Functions.SetJob('unemployed', 0) end
    for jobName in pairs(Config.LawJobs) do
        exports.jrs_core:RemoveJob(player.PlayerData.source, jobName)
    end
end

-- gives the player `jobName` at `grade`; returns the old job's name and label
local function switchJob(player, jobName, grade)
    local old = player.PlayerData.job
    local replaced = lawJobOf(player)

    clearLawJobs(player)
    local ok, err = pcall(function() player.Functions.SetJob(jobName, grade) end)
    if not ok then print('[jrs_mdt] could not set the job: ' .. tostring(err)) end

    return ok, old and old.name or 'none', old and old.label or 'None', replaced
end

local function previousLabel(oldName, oldLabel) return oldName ~= 'none' and oldLabel or nil end

-- ------------------------------------------------------------------ staff

adminCallback('jrs_mdt:server:getStaff', {}, function()
    local staff = MDT.Decode(MySQL.query.await([[
        SELECT s.id, s.citizenid, s.name, s.role, s.permissions, s.created_at, s.updated_at, p.job
        FROM mdt_staff s
        LEFT JOIN jrs_mdt_players p ON s.citizenid = p.citizenid
        ORDER BY s.created_at DESC
    ]]), 'permissions')

    for _, member in ipairs(staff) do
        local job = type(member.job) == 'string' and json.decode(member.job)
        if job then
            member.department = job.label
            local department = job.name and Config.LawJobs[job.name]
            local level = type(job.grade) == 'table' and job.grade.level or tonumber(job.grade)
            if department and level and department.grades[level] then member.role_label = department.grades[level].label end
        end
        member.job = nil
    end
    return staff
end)

adminCallback('jrs_mdt:server:getRoles', {}, function()
    return MDT.Decode(MySQL.query.await('SELECT * FROM mdt_roles ORDER BY name'), 'permissions')
end)

adminCallback('jrs_mdt:server:addStaff', denied, function(src, data)
    local citizenid = data.citizenid
    if not citizenid then return MDT.Fail('notification_citizenid_required') end
    if isStaff(citizenid) then return MDT.Fail('notification_already_staff') end

    local name = MDT.NameOf(citizenid)
    if not name then return MDT.Fail('notification_citizen_not_found') end

    local role = data.role or 'officer'
    local id = MySQL.insert.await('INSERT INTO mdt_staff (citizenid, name, role, permissions) VALUES (?, ?, ?, ?)',
        { citizenid, name, role, json.encode(data.permissions or {}) })
    if not id then return MDT.Fail('notification_failed_add_staff') end

    MDT.Audit(src, 'staff_added', 'staff', citizenid, name, { role = role })
    MDT.Broadcast('admin', 'jrs_mdt:client:staffUpdated', { action = 'added', citizenid = citizenid, name = name, role = role })
    return { success = true, id = id }
end)

adminCallback('jrs_mdt:server:removeStaff', denied, function(src, citizenid)
    if not citizenid then return MDT.Fail('notification_citizenid_required') end

    local member = staffRow(citizenid, 'name')
    if not member then return MDT.Fail('notification_staff_not_found') end

    if not MDT.Touched(MySQL.query.await('DELETE FROM mdt_staff WHERE citizenid = ?', { citizenid })) then
        return MDT.Fail('notification_failed_remove_staff')
    end

    MDT.Audit(src, 'staff_removed', 'staff', citizenid, member.name)
    MDT.Broadcast('admin', 'jrs_mdt:client:staffUpdated', { action = 'removed', citizenid = citizenid, name = member.name })
    return { success = true }
end)

adminCallback('jrs_mdt:server:updateStaffPermissions', denied, function(src, data)
    local citizenid = data.citizenid
    if not citizenid then return MDT.Fail('notification_citizenid_required') end

    local member = staffRow(citizenid, 'name, role')
    if not member then return MDT.Fail('notification_staff_not_found') end

    if not MySQL.query.await('UPDATE mdt_staff SET role = ?, permissions = ? WHERE citizenid = ?', { data.role, json.encode(data.permissions), citizenid }) then
        return MDT.Fail('notification_failed_update_staff')
    end

    MDT.Audit(src, 'staff_updated', 'staff', citizenid, member.name, { oldRole = member.role, newRole = data.role, permissions = data.permissions })
    MDT.Broadcast('admin', 'jrs_mdt:client:staffUpdated',
        { action = 'updated', citizenid = citizenid, name = member.name, role = data.role, permissions = data.permissions })
    return { success = true }
end)

-- ------------------------------------------------------------------ roles

adminCallback('jrs_mdt:server:createRole', denied, function(src, data)
    if not data.name or not data.label then return MDT.Fail('notification_name_label_required') end

    local existing = MySQL.query.await('SELECT id FROM mdt_roles WHERE name = ?', { data.name })
    if existing and existing[1] then return MDT.Fail('notification_role_exists') end

    local id = MySQL.insert.await('INSERT INTO mdt_roles (name, label, permissions) VALUES (?, ?, ?)', { data.name, data.label, json.encode(data.permissions or {}) })
    if not id then return MDT.Fail('notification_failed_create_role') end

    MDT.Audit(src, 'role_created', 'role', data.name, data.label, { permissions = data.permissions or {} })
    MDT.Broadcast('admin', 'jrs_mdt:client:rolesUpdated', { action = 'created', name = data.name, label = data.label })
    return { success = true, id = id }
end)

adminCallback('jrs_mdt:server:updateRole', denied, function(src, data)
    if not data.name then return MDT.Fail('notification_role_name_required') end

    if not MySQL.query.await('UPDATE mdt_roles SET label = ?, permissions = ? WHERE name = ?', { data.label, json.encode(data.permissions), data.name }) then
        return MDT.Fail('notification_failed_update_role')
    end

    MDT.Audit(src, 'role_updated', 'role', data.name, data.label, { permissions = data.permissions })
    MDT.Broadcast('admin', 'jrs_mdt:client:rolesUpdated', { action = 'updated', name = data.name, label = data.label })
    return { success = true }
end)

adminCallback('jrs_mdt:server:deleteRole', denied, function(src, name)
    if DEFAULT_ROLES[name] then return MDT.Fail('notification_cannot_delete_default') end

    local role = MySQL.query.await('SELECT label FROM mdt_roles WHERE name = ?', { name })
    if not (role and role[1]) then return MDT.Fail('notification_role_not_found') end

    if not MDT.Touched(MySQL.query.await('DELETE FROM mdt_roles WHERE name = ?', { name })) then
        return MDT.Fail('notification_failed_delete_role')
    end

    MDT.Audit(src, 'role_deleted', 'role', name, role[1].label)
    MDT.Broadcast('admin', 'jrs_mdt:client:rolesUpdated', { action = 'deleted', name = name })
    return { success = true }
end)

-- ------------------------------------------------------------------ audit log

adminCallback('jrs_mdt:server:getAuditLogs', {}, function(_, filter)
    filter = filter or {}
    local where, args = {}, {}
    if filter.action then where[#where + 1] = 'action = ?' args[#args + 1] = filter.action end
    if filter.targetType then where[#where + 1] = 'target_type = ?' args[#args + 1] = filter.targetType end

    local sql = 'SELECT * FROM mdt_audit_logs' .. (#where > 0 and ' WHERE ' .. table.concat(where, ' AND ') or '')
        .. ' ORDER BY created_at DESC LIMIT ? OFFSET ?'
    args[#args + 1] = filter.limit or 100
    args[#args + 1] = filter.offset or 0
    return MySQL.query.await(sql, args) or {}
end)

-- ------------------------------------------------------------------ looking people up

-- up to 20 characters matching the text, each shaped by `shape(row, charinfo, job)`
local function findPeople(query, shape)
    query = string.lower(query or '')
    if #query < 2 then return {} end

    local rows = MySQL.query.await(
        'SELECT citizenid, charinfo, job FROM jrs_mdt_players WHERE LOWER(citizenid) LIKE ? OR LOWER(charinfo) LIKE ? LIMIT 20',
        { like(query), like(query) })

    local found = {}
    for _, row in ipairs(rows or {}) do
        found[#found + 1] = shape(row, row.charinfo and json.decode(row.charinfo) or {}, row.job and json.decode(row.job) or {})
    end
    return found
end

adminCallback('jrs_mdt:server:searchCitizensForStaff', {}, function(_, query)
    return findPeople(query, function(row, info, job)
        return { citizenid = row.citizenid, charinfo = info, job = job, isStaff = isStaff(row.citizenid) }
    end)
end)

adminCallback('jrs_mdt:server:searchPlayersForJob', {}, function(_, query)
    return findPeople(query, function(row, info, job)
        local law = job.name ~= nil and Config.LawJobs[job.name] ~= nil
        return { citizenid = row.citizenid, charinfo = info, job = job, hasLawJob = law, lawJobName = law and (job.label or job.name) or nil }
    end)
end)

-- ------------------------------------------------------------------ departments

adminCallback('jrs_mdt:server:getLawJobs', {}, function()
    local jobs = {}
    for name, job in pairs(Config.LawJobs) do jobs[#jobs + 1] = { name = name, label = job.label } end
    table.sort(jobs, function(a, b) return a.label < b.label end)
    return jobs
end)

adminCallback('jrs_mdt:server:getJobGrades', {}, function(_, jobName)
    local job = jobName and Config.LawJobs[jobName]
    if not job then return {} end

    local grades = {}
    for level, grade in pairs(job.grades) do grades[#grades + 1] = { level = level, label = grade.label, isAdmin = grade.isAdmin or false } end
    table.sort(grades, function(a, b) return a.level < b.level end)
    return grades
end)

-- tells everybody involved that somebody got a law job
local function announceJob(src, target, event, byField, data, ownMessage)
    TriggerClientEvent('jrs_mdt:client:notify', target.PlayerData.source, { type = 'success', message = ownMessage })

    local by = MDTCore.GetPlayer(src)
    data[byField] = by and MDT.FullName(by) or 'Unknown'
    MDT.Broadcast('admin', event, data)
end

adminCallback('jrs_mdt:server:assignLawJob', denied, function(src, data)
    local citizenid, jobName, level = data.citizenid, data.job, data.grade or 0
    if not citizenid or not jobName then return MDT.Fail('notification_citizen_and_job_required') end

    local department = Config.LawJobs[jobName]
    if not department then return MDT.Fail('notification_invalid_law_job') end
    if not department.grades[level] then return MDT.Fail('notification_invalid_grade') end

    local target = MDTCore.GetPlayerByCitizenId(citizenid)
    if not target then
        local known = MySQL.query.await('SELECT citizenid FROM jrs_mdt_players WHERE citizenid = ?', { citizenid })
        return MDT.Fail(known and known[1] and 'notification_online_required' or 'notification_player_not_found')
    end

    local current = target.PlayerData.job
    if current and current.name == jobName then return MDT.Fail('notification_already_has_job') end

    local ok, oldName, oldLabel, replaced = switchJob(target, jobName, level)
    if not ok then return MDT.Fail('notification_failed_assign_job') end

    local who, gradeLabel = MDT.FullName(target), department.grades[level].label
    MDT.Audit(src, 'job_assigned', 'player', citizenid, who, {
        job = jobName, jobLabel = department.label, grade = level, gradeLabel = gradeLabel,
        previousJob = oldName, previousJobLabel = oldLabel, replaced = replaced,
    })
    announceJob(src, target, 'jrs_mdt:client:jobAssigned', 'assignedBy', {
        citizenid = citizenid, name = who, job = jobName, jobLabel = department.label, grade = level, gradeLabel = gradeLabel,
        replacedJob = previousLabel(oldName, oldLabel),
    }, locale('notification_job_assigned', department.label, gradeLabel))

    return {
        success = true, message = locale('notification_job_assigned_format', who, department.label, gradeLabel),
        playerName = who, jobLabel = department.label, gradeLabel = gradeLabel, replacedJob = previousLabel(oldName, oldLabel),
    }
end)

adminCallback('jrs_mdt:server:updateOfficerDepartment', denied, function(src, data)
    local citizenid, jobName = data.citizenid, data.job
    if not citizenid or not jobName then return MDT.Fail('notification_citizenid_department_required') end

    local department = Config.LawJobs[jobName]
    if not department then return MDT.Fail('notification_invalid_department') end

    -- a rank that does not exist falls back to the lowest one of the department
    local level = data.grade or 0
    if not department.grades[level] then
        local lowest
        for l in pairs(department.grades) do lowest = (lowest == nil or l < lowest) and l or lowest end
        level = lowest or 0
    end

    if not staffRow(citizenid, 'name, role') then return MDT.Fail('notification_officer_not_found_staff') end

    local target = MDTCore.GetPlayerByCitizenId(citizenid)
    if not target then return MDT.Fail('notification_target_online_required') end

    local current = target.PlayerData.job
    if current and current.name == jobName then return MDT.Fail('notification_already_in_department') end
    local oldGrade = current and current.grade and current.grade.level or 0

    local ok, oldName, oldLabel, replaced = switchJob(target, jobName, level)
    if not ok then return MDT.Fail('notification_failed_update_department') end

    local who, gradeLabel = MDT.FullName(target), department.grades[level].label
    MDT.Audit(src, 'department_changed', 'staff', citizenid, who, {
        previousDepartment = oldName, previousDepartmentLabel = oldLabel, previousGrade = oldGrade,
        newDepartment = jobName, newDepartmentLabel = department.label, newGrade = level, replaced = replaced,
    })
    announceJob(src, target, 'jrs_mdt:client:departmentUpdated', 'changedBy', {
        citizenid = citizenid, name = who, oldJob = oldName, oldJobLabel = oldLabel, newJob = jobName,
        newJobLabel = department.label, newGrade = level, newGradeLabel = gradeLabel,
    }, locale('notification_department_changed', department.label))

    return {
        success = true, message = locale('notification_department_changed_format', who, department.label),
        playerName = who, jobLabel = department.label, gradeLabel = gradeLabel, replacedJob = previousLabel(oldName, oldLabel),
    }
end)

-- the staff list with the current job of each person
adminCallback('jrs_mdt:server:getOfficers', {}, function()
    local staff = MySQL.query.await([[
        SELECT s.citizenid, s.name, s.role, p.job
        FROM mdt_staff s
        LEFT JOIN jrs_mdt_players p ON s.citizenid = p.citizenid
        ORDER BY s.name
    ]]) or {}

    local officers = {}
    for _, member in ipairs(staff) do
        local entry = { citizenid = member.citizenid, name = member.name, role = member.role, isLaw = false }
        local job = type(member.job) == 'string' and json.decode(member.job)

        if job then
            local level = job.grade and job.grade.level or 0
            local department = Config.LawJobs[job.name]
            entry.jobName, entry.jobLabel, entry.gradeLevel = job.name, job.label, level
            entry.isLaw = department ~= nil

            if department then
                entry.jobLabel = department.label
                entry.gradeLabel = department.grades[level] and department.grades[level].label
                entry.role_label = entry.gradeLabel
            else
                entry.gradeLabel = job.grade and job.grade.name or 'Unknown'
            end
        end
        officers[#officers + 1] = entry
    end
    return officers
end)

adminCallback('jrs_mdt:server:getJobPlayerCounts', {}, function()
    local counts = {}
    for name, job in pairs(Config.LawJobs) do counts[name] = { name = name, label = job.label, count = 0 } end

    for _, row in ipairs(MySQL.query.await('SELECT job FROM jrs_mdt_players WHERE job IS NOT NULL') or {}) do
        local job = type(row.job) == 'string' and json.decode(row.job)
        if job and job.name and counts[job.name] then counts[job.name].count = counts[job.name].count + 1 end
    end

    local list = {}
    for _, entry in pairs(counts) do list[#list + 1] = entry end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)

-- adds everybody who already has a law job (of one department, or all) to the staff list
adminCallback('jrs_mdt:server:syncStaffFromJobs', function() return { success = false, message = locale('notification_permission_denied'), added = 0 } end,
    function(src, only)
    local wanted = {}
    for name in pairs(Config.LawJobs) do
        if not only or name == only then wanted[name] = true end
    end
    if next(wanted) == nil then return { success = true, message = locale('staff_sync_no_jobs'), added = 0 } end

    local rows = MySQL.query.await('SELECT citizenid, charinfo, job FROM jrs_mdt_players WHERE job IS NOT NULL')
    if not rows then return { success = true, message = locale('staff_sync_no_players'), added = 0 } end

    local added = {}
    for _, row in ipairs(rows) do
        local job = type(row.job) == 'string' and json.decode(row.job)
        if job and job.name and wanted[job.name] and not isStaff(row.citizenid) then
            local info = row.charinfo and json.decode(row.charinfo) or {}
            local name = (info.firstname or 'Unknown') .. ' ' .. (info.lastname or '')
            local id = MySQL.insert.await('INSERT INTO mdt_staff (citizenid, name, role, permissions) VALUES (?, ?, ?, ?)', { row.citizenid, name, 'officer', json.encode({}) })
            if id then added[#added + 1] = { citizenid = row.citizenid, name = name, job = job.label or job.name } end
        end
    end

    if #added > 0 then
        MDT.Audit(src, 'staff_synced', 'system', 'sync', 'Staff Sync', { filter = only or 'all', added = #added, players = added })
        MDT.Broadcast('admin', 'jrs_mdt:client:staffUpdated', { action = 'synced', added = #added })
    end

    return {
        success = true, message = #added > 0 and locale('staff_sync_added', #added) or locale('staff_sync_none'),
        added = #added, players = added,
    }
end)

exports('isStaffMember', isStaff)
exports('hasAdminPermission', function(src) return MDT.Can(src, 'isAdmin') end)
exports('getStaffPermissions', function(citizenid)
    local member = staffRow(citizenid, 'permissions')
    return member and member.permissions and json.decode(member.permissions) or nil
end)
