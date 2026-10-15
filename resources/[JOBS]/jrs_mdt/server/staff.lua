
local StaffPermissions = {
    'canCreateRecords',
    'canDeleteRecords', 
    'canManageWarrants',
    'isAdmin'
}

local function hasAdminPermission(source)
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local job = player.PlayerData.job
    if not job then return false end
    
    local jobConfig = Config.LawJobs[job.name]
    if not jobConfig then return false end
    
    local gradeConfig = jobConfig.grades[job.grade.level]
    if not gradeConfig then return false end
    
    return gradeConfig.isAdmin == true
end

local function getPlayerLawJobs(player)
    local lawJobs = {}
    if not player or not player.PlayerData then return lawJobs end
    
    local job = player.PlayerData.job
    if job and job.name and Config.LawJobs[job.name] then
        table.insert(lawJobs, {
            name = job.name,
            label = job.label,
            grade = job.grade and job.grade.level or 0,
            gradeLabel = job.grade and job.grade.name or 'Unknown'
        })
    end
    
    return lawJobs
end

local function removeLawJob(player)
    if not player then return false end
    
    local currentJob = player.PlayerData.job
    if currentJob and currentJob.name and Config.LawJobs[currentJob.name] then
        player.Functions.SetJob('unemployed', 0)
        return true
    end
    
    return false
end

local function removeLawJobFromDatabase(citizenid)
    if not citizenid then return false end
    -- JRS keeps extra jobs in jrs_core (multijob list); only online characters can be changed
    local target = MDTCore.GetPlayerByCitizenId(citizenid)
    if not target then return false end
    local removed = false
    for jobName in pairs(Config.LawJobs) do
        if exports.jrs_core:RemoveJob(target.PlayerData.source, jobName) then removed = true end
    end
    return removed
end

local function isStaffMember(citizenid)
    local result = MySQL.query.await("SELECT id FROM mdt_staff WHERE citizenid = ?", { citizenid })
    return result and result[1] ~= nil
end

local function getAdmins()
    local admins = {}
    local players = MDTCore.GetPlayers()
    for _, playerId in ipairs(players) do
        local src = tonumber(playerId)
        if hasAdminPermission(src) then
            table.insert(admins, src)
        end
    end
    return admins
end

local function logAction(source, action, targetType, targetId, targetName, details)
    local player = MDTCore.GetPlayer(source)
    if not player then return end
    
    local performerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local performerCid = player.PlayerData.citizenid
    
    MySQL.insert.await(
        "INSERT INTO mdt_audit_logs (action, target_type, target_id, target_name, details, performed_by, performed_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
        { action, targetType, targetId, targetName, details and json.encode(details) or nil, performerCid, performerName }
    )
end

local function broadcastToAdmins(event, data)
    local admins = getAdmins()
    for _, adminId in ipairs(admins) do
        TriggerClientEvent(event, adminId, data)
    end
end

JRS.Callback('jrs_mdt:server:getStaff', function(source)
    if not hasAdminPermission(source) then return {} end
    
    local staff = MySQL.query.await([[
        SELECT s.id, s.citizenid, s.name, s.role, s.permissions, s.created_at, s.updated_at,
               p.job
        FROM mdt_staff s
        LEFT JOIN jrs_mdt_players p ON s.citizenid = p.citizenid
        ORDER BY s.created_at DESC
    ]])
    
    if not staff then return {} end
    
    for _, member in ipairs(staff) do
        if member.permissions and type(member.permissions) == 'string' then
            member.permissions = json.decode(member.permissions)
        end
        if member.job and type(member.job) == 'string' then
            local job = json.decode(member.job)
            if job then
                if job.label then
                    member.department = job.label
                end
                if job.name and job.grade and Config.LawJobs[job.name] then
                    local deptConfig = Config.LawJobs[job.name]
                    local gradeLevel = type(job.grade) == 'table' and job.grade.level or tonumber(job.grade)
                    if gradeLevel and deptConfig.grades[gradeLevel] then
                        member.role_label = deptConfig.grades[gradeLevel].label
                    end
                end
            end
        end
        member.job = nil
    end
    
    return staff
end)

JRS.Callback('jrs_mdt:server:getRoles', function(source)
    if not hasAdminPermission(source) then return {} end
    
    local roles = MySQL.query.await("SELECT * FROM mdt_roles ORDER BY name")
    
    if not roles then return {} end
    
    for _, role in ipairs(roles) do
        if role.permissions and type(role.permissions) == 'string' then
            role.permissions = json.decode(role.permissions)
        end
    end
    
    return roles
end)

JRS.Callback('jrs_mdt:server:addStaff', function(source, data)
    if not hasAdminPermission(source) then return { success = false, message = locale('notification_permission_denied') } end
    
    local citizenid = data.citizenid
    local role = data.role or 'officer'
    local permissions = data.permissions or {}
    
    if not citizenid then
        return { success = false, message = locale('notification_citizenid_required') }
    end
    
    if isStaffMember(citizenid) then
        return { success = false, message = locale('notification_already_staff') }
    end
    
    local targetPlayer = MDTCore.GetPlayerByCitizenId(citizenid)
    local name
    
    if targetPlayer then
        name = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname
    else
        local result = MySQL.query.await("SELECT charinfo FROM jrs_mdt_players WHERE citizenid = ?", { citizenid })
        if result and result[1] then
            local charinfo = json.decode(result[1].charinfo)
            name = charinfo.firstname .. ' ' .. charinfo.lastname
        else
            return { success = false, message = locale('notification_citizen_not_found') }
        end
    end
    
    local insertId = MySQL.insert.await(
        "INSERT INTO mdt_staff (citizenid, name, role, permissions) VALUES (?, ?, ?, ?)",
        { citizenid, name, role, json.encode(permissions) }
    )
    
    if insertId then
        logAction(source, 'staff_added', 'staff', citizenid, name, { role = role })
        
        broadcastToAdmins('jrs_mdt:client:staffUpdated', { action = 'added', citizenid = citizenid, name = name, role = role })
        
        return { success = true, id = insertId }
    end
    
    return { success = false, message = locale('notification_failed_add_staff') }
end)

JRS.Callback('jrs_mdt:server:removeStaff', function(source, citizenid)
    if not hasAdminPermission(source) then return { success = false, message = locale('notification_permission_denied') } end
    
    if not citizenid then
        return { success = false, message = locale('notification_citizenid_required') }
    end
    
    local staffInfo = MySQL.query.await("SELECT name FROM mdt_staff WHERE citizenid = ?", { citizenid })
    if not staffInfo or not staffInfo[1] then
        return { success = false, message = locale('notification_staff_not_found') }
    end
    
    local staffName = staffInfo[1].name
    
    local affected = MySQL.query.await("DELETE FROM mdt_staff WHERE citizenid = ?", { citizenid })
    
    if affected and affected.affectedRows > 0 then
        logAction(source, 'staff_removed', 'staff', citizenid, staffName)
        
        broadcastToAdmins('jrs_mdt:client:staffUpdated', { action = 'removed', citizenid = citizenid, name = staffName })
        
        return { success = true }
    end
    
    return { success = false, message = locale('notification_failed_remove_staff') }
end)

JRS.Callback('jrs_mdt:server:updateStaffPermissions', function(source, data)
    if not hasAdminPermission(source) then return { success = false, message = locale('notification_permission_denied') } end
    
    local citizenid = data.citizenid
    local role = data.role
    local permissions = data.permissions
    
    if not citizenid then
        return { success = false, message = locale('notification_citizenid_required') }
    end
    
    local staffInfo = MySQL.query.await("SELECT name, role FROM mdt_staff WHERE citizenid = ?", { citizenid })
    if not staffInfo or not staffInfo[1] then
        return { success = false, message = locale('notification_staff_not_found') }
    end
    
    local staffName = staffInfo[1].name
    local oldRole = staffInfo[1].role
    
    local affected = MySQL.query.await(
        "UPDATE mdt_staff SET role = ?, permissions = ? WHERE citizenid = ?",
        { role, json.encode(permissions), citizenid }
    )
    
    if affected then
        logAction(source, 'staff_updated', 'staff', citizenid, staffName, { 
            oldRole = oldRole, 
            newRole = role, 
            permissions = permissions 
        })
        
        broadcastToAdmins('jrs_mdt:client:staffUpdated', { 
            action = 'updated', 
            citizenid = citizenid, 
            name = staffName, 
            role = role,
            permissions = permissions
        })
        
        return { success = true }
    end
    
    return { success = false, message = locale('notification_failed_update_staff') }
end)

JRS.Callback('jrs_mdt:server:createRole', function(source, data)
    if not hasAdminPermission(source) then return { success = false, message = locale('notification_permission_denied') } end
    
    local name = data.name
    local label = data.label
    local permissions = data.permissions or {}
    
    if not name or not label then
        return { success = false, message = locale('notification_name_label_required') }
    end
    
    local existing = MySQL.query.await("SELECT id FROM mdt_roles WHERE name = ?", { name })
    if existing and existing[1] then
        return { success = false, message = locale('notification_role_exists') }
    end
    
    local insertId = MySQL.insert.await(
        "INSERT INTO mdt_roles (name, label, permissions) VALUES (?, ?, ?)",
        { name, label, json.encode(permissions) }
    )
    
    if insertId then
        logAction(source, 'role_created', 'role', name, label, { permissions = permissions })
        
        broadcastToAdmins('jrs_mdt:client:rolesUpdated', { action = 'created', name = name, label = label })
        
        return { success = true, id = insertId }
    end
    
    return { success = false, message = locale('notification_failed_create_role') }
end)

JRS.Callback('jrs_mdt:server:updateRole', function(source, data)
    if not hasAdminPermission(source) then return { success = false, message = locale('notification_permission_denied') } end
    
    local name = data.name
    local label = data.label
    local permissions = data.permissions
    
    if not name then
        return { success = false, message = locale('notification_role_name_required') }
    end
    
    local affected = MySQL.query.await(
        "UPDATE mdt_roles SET label = ?, permissions = ? WHERE name = ?",
        { label, json.encode(permissions), name }
    )
    
    if affected then
        logAction(source, 'role_updated', 'role', name, label, { permissions = permissions })
        
        broadcastToAdmins('jrs_mdt:client:rolesUpdated', { action = 'updated', name = name, label = label })
        
        return { success = true }
    end
    
    return { success = false, message = locale('notification_failed_update_role') }
end)

JRS.Callback('jrs_mdt:server:deleteRole', function(source, roleName)
    if not hasAdminPermission(source) then return { success = false, message = locale('notification_permission_denied') } end
    
    if roleName == 'admin' or roleName == 'supervisor' or roleName == 'officer' then
        return { success = false, message = locale('notification_cannot_delete_default') }
    end
    
    local roleInfo = MySQL.query.await("SELECT label FROM mdt_roles WHERE name = ?", { roleName })
    if not roleInfo or not roleInfo[1] then
        return { success = false, message = locale('notification_role_not_found') }
    end
    
    local affected = MySQL.query.await("DELETE FROM mdt_roles WHERE name = ?", { roleName })
    
    if affected and affected.affectedRows > 0 then
        logAction(source, 'role_deleted', 'role', roleName, roleInfo[1].label)
        
        broadcastToAdmins('jrs_mdt:client:rolesUpdated', { action = 'deleted', name = roleName })
        
        return { success = true }
    end
    
    return { success = false, message = locale('notification_failed_delete_role') }
end)

JRS.Callback('jrs_mdt:server:getAuditLogs', function(source, data)
    if not hasAdminPermission(source) then return {} end
    
    local limit = data and data.limit or 100
    local offset = data and data.offset or 0
    local actionFilter = data and data.action
    local targetTypeFilter = data and data.targetType
    
    local query = "SELECT * FROM mdt_audit_logs"
    local params = {}
    local conditions = {}
    
    if actionFilter then
        table.insert(conditions, "action = ?")
        table.insert(params, actionFilter)
    end
    
    if targetTypeFilter then
        table.insert(conditions, "target_type = ?")
        table.insert(params, targetTypeFilter)
    end
    
    if #conditions > 0 then
        query = query .. " WHERE " .. table.concat(conditions, " AND ")
    end
    
    query = query .. " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    table.insert(params, limit)
    table.insert(params, offset)
    
    local logs = MySQL.query.await(query, params)
    
    return logs or {}
end)

JRS.Callback('jrs_mdt:server:searchCitizensForStaff', function(source, query)
    if not hasAdminPermission(source) then return {} end
    
    query = string.lower(query or '')
    if #query < 2 then return {} end
    
    local results = MySQL.query.await(
        "SELECT citizenid, charinfo, job FROM jrs_mdt_players WHERE LOWER(citizenid) LIKE ? OR LOWER(charinfo) LIKE ? LIMIT 20",
        { '%' .. query .. '%', '%' .. query .. '%' }
    )
    
    if not results then return {} end
    
    local citizens = {}
    for _, row in ipairs(results) do
        local charinfo = row.charinfo and json.decode(row.charinfo) or {}
        local job = row.job and json.decode(row.job) or {}
        
        table.insert(citizens, {
            citizenid = row.citizenid,
            charinfo = charinfo,
            job = job,
            isStaff = isStaffMember(row.citizenid)
        })
    end
    
    return citizens
end)

JRS.Callback('jrs_mdt:server:assignLawJob', function(source, data)
    if not hasAdminPermission(source) then
        return { success = false, message = locale('notification_permission_denied') }
    end
    
    local targetCitizenid = data.citizenid
    local jobName = data.job
    local gradeLevel = data.grade or 0
    
    if not targetCitizenid or not jobName then
        return { success = false, message = locale('notification_citizen_and_job_required') }
    end
    
    if not Config.LawJobs[jobName] then
        return { success = false, message = locale('notification_invalid_law_job') }
    end
    
    local jobConfig = Config.LawJobs[jobName]
    if not jobConfig.grades[gradeLevel] then
        return { success = false, message = locale('notification_invalid_grade') }
    end
    
    local targetPlayer = MDTCore.GetPlayerByCitizenId(targetCitizenid)
    if not targetPlayer then
        local offlineResult = MySQL.query.await("SELECT citizenid FROM jrs_mdt_players WHERE citizenid = ?", { targetCitizenid })
        if not offlineResult or not offlineResult[1] then
            return { success = false, message = locale('notification_player_not_found') }
        end
        return { success = false, message = locale('notification_online_required') }
    end
    
    local targetSource = targetPlayer.PlayerData.source
    local currentJob = targetPlayer.PlayerData.job
    local previousLawJobs = getPlayerLawJobs(targetPlayer)
    local previousJobName = currentJob and currentJob.name or 'none'
    local previousJobLabel = currentJob and currentJob.label or 'None'
    
    if previousJobName == jobName then
        return { success = false, message = locale('notification_already_has_job') }
    end
    
    if #previousLawJobs > 0 then
        removeLawJob(targetPlayer)
    end
    
    removeLawJobFromDatabase(targetCitizenid)
    
    local success, err = pcall(function()
        targetPlayer.Functions.SetJob(jobName, gradeLevel)
    end)
    
    if not success then
        print('[jrs_mdt] Error assigning job: ' .. tostring(err))
        return { success = false, message = locale('notification_failed_assign_job') }
    end
    
    local jobLabel = jobConfig.label
    local gradeLabel = jobConfig.grades[gradeLevel].label
    local playerName = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname
    
    logAction(source, 'job_assigned', 'player', targetCitizenid, playerName, { 
        job = jobName, 
        jobLabel = jobLabel,
        grade = gradeLevel,
        gradeLabel = gradeLabel,
        previousJob = previousJobName,
        previousJobLabel = previousJobLabel,
        replaced = #previousLawJobs > 0
    })
    
    TriggerClientEvent('jrs_mdt:client:notify', targetSource, {
        type = 'success',
        message = locale('notification_job_assigned', jobLabel, gradeLabel)
    })
    
    local performer = MDTCore.GetPlayer(source)
    local performerName = performer and performer.PlayerData.charinfo.firstname .. ' ' .. performer.PlayerData.charinfo.lastname or 'Unknown'
    
    broadcastToAdmins('jrs_mdt:client:jobAssigned', {
        citizenid = targetCitizenid,
        name = playerName,
        job = jobName,
        jobLabel = jobLabel,
        grade = gradeLevel,
        gradeLabel = gradeLabel,
        assignedBy = performerName,
        replacedJob = previousJobName ~= 'none' and previousJobLabel or nil
    })
    
    return { 
        success = true, 
        message = locale('notification_job_assigned_format', playerName, jobLabel, gradeLabel),
        playerName = playerName,
        jobLabel = jobLabel,
        gradeLabel = gradeLabel,
        replacedJob = previousJobName ~= 'none' and previousJobLabel or nil
    }
end)

JRS.Callback('jrs_mdt:server:getLawJobs', function(source)
    if not hasAdminPermission(source) then return {} end
    
    local jobs = {}
    for jobName, jobConfig in pairs(Config.LawJobs) do
        table.insert(jobs, {
            name = jobName,
            label = jobConfig.label
        })
    end
    
    table.sort(jobs, function(a, b) return a.label < b.label end)
    
    return jobs
end)

JRS.Callback('jrs_mdt:server:getJobGrades', function(source, jobName)
    if not hasAdminPermission(source) then return {} end
    
    if not jobName or not Config.LawJobs[jobName] then
        return {}
    end
    
    local grades = {}
    local jobConfig = Config.LawJobs[jobName]
    
    for gradeLevel, gradeConfig in pairs(jobConfig.grades) do
        table.insert(grades, {
            level = gradeLevel,
            label = gradeConfig.label,
            isAdmin = gradeConfig.isAdmin or false
        })
    end
    
    table.sort(grades, function(a, b) return a.level < b.level end)
    
    return grades
end)

JRS.Callback('jrs_mdt:server:searchPlayersForJob', function(source, query)
    if not hasAdminPermission(source) then return {} end
    
    query = string.lower(query or '')
    if #query < 2 then return {} end
    
    local results = MySQL.query.await(
        "SELECT citizenid, charinfo, job FROM jrs_mdt_players WHERE LOWER(citizenid) LIKE ? OR LOWER(charinfo) LIKE ? LIMIT 20",
        { '%' .. query .. '%', '%' .. query .. '%' }
    )
    
    if not results then return {} end
    
    local players = {}
    for _, row in ipairs(results) do
        local charinfo = row.charinfo and json.decode(row.charinfo) or {}
        local job = row.job and json.decode(row.job) or {}
        
        local hasLawJob = false
        local lawJobName = nil
        if job and job.name and Config.LawJobs[job.name] then
            hasLawJob = true
            lawJobName = job.label or job.name
        end
        
        table.insert(players, {
            citizenid = row.citizenid,
            charinfo = charinfo,
            job = job,
            hasLawJob = hasLawJob,
            lawJobName = lawJobName
        })
    end
    
    return players
end)

JRS.Callback('jrs_mdt:server:updateOfficerDepartment', function(source, data)
    if not hasAdminPermission(source) then
        return { success = false, message = locale('notification_permission_denied') }
    end
    
    local targetCitizenid = data.citizenid
    local newJobName = data.job
    local newGradeLevel = data.grade
    
    if not targetCitizenid or not newJobName then
        return { success = false, message = locale('notification_citizenid_department_required') }
    end
    
    if not Config.LawJobs[newJobName] then
        return { success = false, message = locale('notification_invalid_department') }
    end
    
    local jobConfig = Config.LawJobs[newJobName]
    local gradeLevel = newGradeLevel or 0
    
    if not jobConfig.grades[gradeLevel] then
        local grades = {}
        for level, _ in pairs(jobConfig.grades) do
            table.insert(grades, level)
        end
        table.sort(grades)
        gradeLevel = grades[1] or 0
    end
    
    local staffInfo = MySQL.query.await("SELECT name, role FROM mdt_staff WHERE citizenid = ?", { targetCitizenid })
    if not staffInfo or not staffInfo[1] then
        return { success = false, message = locale('notification_officer_not_found_staff') }
    end
    
    local targetPlayer = MDTCore.GetPlayerByCitizenId(targetCitizenid)
    if not targetPlayer then
        return { success = false, message = locale('notification_target_online_required') }
    end
    
    local targetSource = targetPlayer.PlayerData.source
    local currentJob = targetPlayer.PlayerData.job
    local previousLawJobs = getPlayerLawJobs(targetPlayer)
    local previousJobName = currentJob and currentJob.name or 'none'
    local previousJobLabel = currentJob and currentJob.label or 'None'
    local previousGradeLevel = currentJob and currentJob.grade and currentJob.grade.level or 0
    
    if previousJobName == newJobName then
        return { success = false, message = locale('notification_already_in_department') }
    end
    
    if #previousLawJobs > 0 then
        removeLawJob(targetPlayer)
    end
    
    removeLawJobFromDatabase(targetCitizenid)
    
    local success, err = pcall(function()
        targetPlayer.Functions.SetJob(newJobName, gradeLevel)
    end)
    
    if not success then
        print('[jrs_mdt] Error updating department: ' .. tostring(err))
        return { success = false, message = locale('notification_failed_update_department') }
    end
    
    local playerName = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname
    local newJobLabel = jobConfig.label
    local newGradeLabel = jobConfig.grades[gradeLevel].label
    
    logAction(source, 'department_changed', 'staff', targetCitizenid, playerName, {
        previousDepartment = previousJobName,
        previousDepartmentLabel = previousJobLabel,
        previousGrade = previousGradeLevel,
        newDepartment = newJobName,
        newDepartmentLabel = newJobLabel,
        newGrade = gradeLevel,
        replaced = #previousLawJobs > 0
    })
    
    TriggerClientEvent('jrs_mdt:client:notify', targetSource, {
        type = 'success',
        message = locale('notification_department_changed', newJobLabel)
    })
    
    local performer = MDTCore.GetPlayer(source)
    local performerName = performer and performer.PlayerData.charinfo.firstname .. ' ' .. performer.PlayerData.charinfo.lastname or 'Unknown'
    
    broadcastToAdmins('jrs_mdt:client:departmentUpdated', {
        citizenid = targetCitizenid,
        name = playerName,
        oldJob = previousJobName,
        oldJobLabel = previousJobLabel,
        newJob = newJobName,
        newJobLabel = newJobLabel,
        newGrade = gradeLevel,
        newGradeLabel = newGradeLabel,
        changedBy = performerName
    })
    
    return {
        success = true,
        message = locale('notification_department_changed_format', playerName, newJobLabel),
        playerName = playerName,
        jobLabel = newJobLabel,
        gradeLabel = newGradeLabel,
        replacedJob = previousJobName ~= 'none' and previousJobLabel or nil
    }
end)

JRS.Callback('jrs_mdt:server:getOfficers', function(source)
    if not hasAdminPermission(source) then return {} end
    
    local staff = MySQL.query.await([[
        SELECT s.citizenid, s.name, s.role,
               p.job
        FROM mdt_staff s
        LEFT JOIN jrs_mdt_players p ON s.citizenid = p.citizenid
        ORDER BY s.name
    ]])
    
    if not staff then return {} end
    
    local officers = {}
    for _, member in ipairs(staff) do
        local job = nil
        local jobName = nil
        local jobLabel = nil
        local gradeLevel = nil
        local gradeLabel = nil
        local roleLabel = nil
        local isLaw = false
        
        if member.job and type(member.job) == 'string' then
            job = json.decode(member.job)
            if job then
                jobName = job.name
                jobLabel = job.label
                gradeLevel = job.grade and job.grade.level or 0
                isLaw = Config.LawJobs[job.name] ~= nil
                
                if isLaw then
                    local deptConfig = Config.LawJobs[job.name]
                    jobLabel = deptConfig.label
                    if deptConfig.grades[gradeLevel] then
                        gradeLabel = deptConfig.grades[gradeLevel].label
                        roleLabel = gradeLabel
                    end
                else
                    gradeLabel = job.grade and job.grade.name or 'Unknown'
                end
            end
        end
        
        table.insert(officers, {
            citizenid = member.citizenid,
            name = member.name,
            role = member.role,
            role_label = roleLabel,
            jobName = jobName,
            jobLabel = jobLabel,
            gradeLevel = gradeLevel,
            gradeLabel = gradeLabel,
            isLaw = isLaw
        })
    end
    
    return officers
end)

JRS.Callback('jrs_mdt:server:getJobPlayerCounts', function(source)
    if not hasAdminPermission(source) then return {} end
    
    local counts = {}
    local lawJobNames = {}
    for jobName, _ in pairs(Config.LawJobs) do
        table.insert(lawJobNames, jobName)
        counts[jobName] = { name = jobName, label = Config.LawJobs[jobName].label, count = 0 }
    end
    
    if #lawJobNames == 0 then return {} end
    
    local placeholders = {}
    for _ in ipairs(lawJobNames) do
        table.insert(placeholders, '?')
    end
    
    local query = "SELECT job FROM jrs_mdt_players WHERE job IS NOT NULL"
    local results = MySQL.query.await(query)
    
    if results then
        for _, row in ipairs(results) do
            if row.job and type(row.job) == 'string' then
                local job = json.decode(row.job)
                if job and job.name and counts[job.name] then
                    counts[job.name].count = counts[job.name].count + 1
                end
            end
        end
    end
    
    local countsList = {}
    for _, countData in pairs(counts) do
        table.insert(countsList, countData)
    end
    
    table.sort(countsList, function(a, b) return a.label < b.label end)
    
    return countsList
end)

JRS.Callback('jrs_mdt:server:syncStaffFromJobs', function(source, filterJob)
    if not hasAdminPermission(source) then
        return { success = false, message = locale('notification_permission_denied'), added = 0 }
    end
    
    local lawJobNames = {}
    for jobName, _ in pairs(Config.LawJobs) do
        if not filterJob or jobName == filterJob then
            table.insert(lawJobNames, jobName)
        end
    end
    
    if #lawJobNames == 0 then
        return { success = true, message = locale('staff_sync_no_jobs'), added = 0 }
    end
    
    local placeholders = {}
    for _ in ipairs(lawJobNames) do
        table.insert(placeholders, '?')
    end
    
    local query = "SELECT citizenid, charinfo, job FROM jrs_mdt_players WHERE job IS NOT NULL"
    local results = MySQL.query.await(query)
    
    if not results then
        return { success = true, message = locale('staff_sync_no_players'), added = 0 }
    end
    
    local addedCount = 0
    local addedPlayers = {}
    local performer = MDTCore.GetPlayer(source)
    local performerName = performer and performer.PlayerData.charinfo.firstname .. ' ' .. performer.PlayerData.charinfo.lastname or 'System'
    
    for _, row in ipairs(results) do
        if row.job and type(row.job) == 'string' then
            local job = json.decode(row.job)
            if job and job.name then
                local isLawJob = false
                for _, lawJobName in ipairs(lawJobNames) do
                    if job.name == lawJobName then
                        isLawJob = true
                        break
                    end
                end
                
                if isLawJob then
                    local citizenid = row.citizenid
                    local charinfo = row.charinfo and json.decode(row.charinfo) or {}
                    local name = (charinfo.firstname or 'Unknown') .. ' ' .. (charinfo.lastname or '')
                    
                    if not isStaffMember(citizenid) then
                        local insertId = MySQL.insert.await(
                            "INSERT INTO mdt_staff (citizenid, name, role, permissions) VALUES (?, ?, ?, ?)",
                            { citizenid, name, 'officer', json.encode({}) }
                        )
                        
                        if insertId then
                            addedCount = addedCount + 1
                            table.insert(addedPlayers, { citizenid = citizenid, name = name, job = job.label or job.name })
                        end
                    end
                end
            end
        end
    end
    
    if addedCount > 0 then
        logAction(source, 'staff_synced', 'system', 'sync', 'Staff Sync', { 
            filter = filterJob or 'all',
            added = addedCount,
            players = addedPlayers
        })
        
        broadcastToAdmins('jrs_mdt:client:staffUpdated', { action = 'synced', added = addedCount })
    end
    
    return {
        success = true,
        message = addedCount > 0 and locale('staff_sync_added', addedCount) or locale('staff_sync_none'),
        added = addedCount,
        players = addedPlayers
    }
end)

exports('isStaffMember', isStaffMember)
exports('hasAdminPermission', hasAdminPermission)
exports('getStaffPermissions', function(citizenid)
    local result = MySQL.query.await("SELECT permissions FROM mdt_staff WHERE citizenid = ?", { citizenid })
    if result and result[1] and result[1].permissions then
        return json.decode(result[1].permissions)
    end
    return nil
end)
