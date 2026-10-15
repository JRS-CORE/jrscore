-- ============================================
-- Authoritative Role Synchronization System
-- Server-side role management using Config.LawJobs
-- ============================================


-- Authoritative server state for player roles
local PlayerRoles = {}
local ConfigVersion = 1
local ConfigValidated = false

-- ============================================
-- Config Validation
-- ============================================
local function validateLawJobsConfig()
    if not Config.LawJobs then
        print('[jrs_mdt] ERROR: Config.LawJobs is not defined!')
        return false
    end
    
    if type(Config.LawJobs) ~= 'table' then
        print('[jrs_mdt] ERROR: Config.LawJobs must be a table!')
        return false
    end
    
    local validCount = 0
    for jobName, jobConfig in pairs(Config.LawJobs) do
        if type(jobName) ~= 'string' then
            print('[jrs_mdt] WARNING: LawJob key must be a string, skipping: ' .. tostring(jobName))
        elseif not jobConfig.label then
            print('[jrs_mdt] WARNING: LawJob "' .. jobName .. '" missing label')
        elseif not jobConfig.grades or type(jobConfig.grades) ~= 'table' then
            print('[jrs_mdt] WARNING: LawJob "' .. jobName .. '" missing grades table')
        else
            for gradeLevel, gradeConfig in pairs(jobConfig.grades) do
                if type(gradeLevel) ~= 'number' then
                    print('[jrs_mdt] WARNING: LawJob "' .. jobName .. '" has non-numeric grade key: ' .. tostring(gradeLevel))
                end
            end
            validCount = validCount + 1
        end
    end
    
    if validCount == 0 then
        print('[jrs_mdt] ERROR: No valid LawJobs defined in Config.LawJobs!')
        return false
    end
    
    print('[jrs_mdt] Config.LawJobs validated: ' .. validCount .. ' law job(s) defined')
    return true
end

-- ============================================
-- Player Role Management
-- ============================================
local function getPlayerRoleData(src)
    local player = MDTCore.GetPlayer(src)
    if not player then return nil end
    
    local job = player.PlayerData.job
    if not job or not job.name then return nil end
    
    local jobConfig = Config.LawJobs[job.name]
    if not jobConfig then return nil end
    
    local gradeLevel = job.grade and job.grade.level or 0
    local gradeConfig = jobConfig.grades[gradeLevel] or Config.Defaults.jobGrade
    
    return {
        source = src,
        citizenid = player.PlayerData.citizenid,
        name = player.PlayerData.charinfo and player.PlayerData.charinfo.firstname and 
               player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname or 'Unknown',
        job = {
            name = job.name,
            label = jobConfig.label,
            grade = gradeLevel,
            gradeLabel = gradeConfig.label or 'Unknown'
        },
        permissions = {
            canCreateRecords = gradeConfig.canCreateRecords == true,
            canDeleteRecords = gradeConfig.canDeleteRecords == true,
            canManageWarrants = gradeConfig.canManageWarrants == true,
            isAdmin = gradeConfig.isAdmin == true
        },
        configVersion = ConfigVersion
    }
end

local function updatePlayerRole(src)
    local roleData = getPlayerRoleData(src)
    
    if roleData then
        local previousRole = PlayerRoles[src]
        PlayerRoles[src] = roleData
        
        if previousRole then
            if previousRole.job.name ~= roleData.job.name or previousRole.job.grade ~= roleData.job.grade then
                TriggerClientEvent('jrs_mdt:roleSync:roleUpdated', -1, {
                    source = src,
                    roleData = roleData,
                    changeType = 'update'
                })
            end
        else
            TriggerClientEvent('jrs_mdt:roleSync:roleUpdated', -1, {
                source = src,
                roleData = roleData,
                changeType = 'add'
            })
        end
        
        return roleData
    else
        if PlayerRoles[src] then
            local oldData = PlayerRoles[src]
            PlayerRoles[src] = nil
            TriggerClientEvent('jrs_mdt:roleSync:roleUpdated', -1, {
                source = src,
                roleData = oldData,
                changeType = 'remove'
            })
        end
        return nil
    end
end

local function removePlayerRole(src)
    if PlayerRoles[src] then
        local oldData = PlayerRoles[src]
        PlayerRoles[src] = nil
        TriggerClientEvent('jrs_mdt:roleSync:roleUpdated', -1, {
            source = src,
            roleData = oldData,
            changeType = 'remove'
        })
    end
end

-- ============================================
-- Get All Current Roles
-- ============================================
local function getAllPlayerRoles()
    local roles = {}
    for source, roleData in pairs(PlayerRoles) do
        roles[#roles + 1] = roleData
    end
    return roles
end

-- ============================================
-- Force Refresh All Roles
-- ============================================
local function forceRefreshAllRoles()
    ConfigVersion = ConfigVersion + 1
    
    for source, _ in pairs(PlayerRoles) do
        updatePlayerRole(source)
    end
    
    TriggerClientEvent('jrs_mdt:roleSync:forceRefresh', -1, {
        configVersion = ConfigVersion,
        roles = getAllPlayerRoles()
    })
    
    print('[jrs_mdt] Force refreshed all roles, new config version: ' .. ConfigVersion)
end

RegisterNetEvent('jrs_mdt:roleSync:requestRoles', function()
    local src = source
    TriggerClientEvent('jrs_mdt:roleSync:receiveRoles', src, {
        configVersion = ConfigVersion,
        roles = getAllPlayerRoles(),
        yourRole = PlayerRoles[src]
    })
end)

RegisterNetEvent('jrs_mdt:roleSync:requestMyRole', function()
    local src = source
    local roleData = PlayerRoles[src]
    TriggerClientEvent('jrs_mdt:roleSync:receiveMyRole', src, roleData)
end)

RegisterNetEvent('jrs_mdt:roleSync:validateLocalState', function(localRole)
    local src = source
    local serverRole = PlayerRoles[src]
    
    if localRole and serverRole then
        if localRole.job.name ~= serverRole.job.name or 
           localRole.job.grade ~= serverRole.job.grade or
           localRole.configVersion ~= serverRole.configVersion then
            TriggerClientEvent('jrs_mdt:roleSync:stateMismatch', src, {
                localState = localRole,
                serverState = serverRole,
                message = locale('role_state_mismatch')
            })
        end
    elseif localRole and not serverRole then
        TriggerClientEvent('jrs_mdt:roleSync:stateMismatch', src, {
            localState = localRole,
            serverState = nil,
            message = locale('role_local_no_server')
        })
    elseif not localRole and serverRole then
        TriggerClientEvent('jrs_mdt:roleSync:stateMismatch', src, {
            localState = nil,
            serverState = serverRole,
            message = locale('role_server_no_local')
        })
    end
end)

RegisterNetEvent('jrs_mdt:roleSync:adminForceRefresh', function()
    local src = source
    local roleData = PlayerRoles[src]
    
    if roleData and roleData.permissions.isAdmin then
        forceRefreshAllRoles()
        TriggerClientEvent('jrs_mdt:roleSync:refreshComplete', src, {
            success = true,
            message = locale('role_refresh_success'),
            configVersion = ConfigVersion
        })
    else
        TriggerClientEvent('jrs_mdt:roleSync:refreshComplete', src, {
            success = false,
            message = locale('role_refresh_denied')
        })
    end
end)

-- ============================================
-- Player Connection Handlers
-- ============================================
AddEventHandler('jrs:SelectedCharacter', function(src)
    if not src then return end
    Wait(1000)
    updatePlayerRole(src)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    removePlayerRole(src)
end)

AddEventHandler('jrs_core:server:jobChanged', function(src)
    Wait(500)
    updatePlayerRole(src)
end)

-- ============================================
-- Callbacks
-- ============================================
JRS.Callback('jrs_mdt:roleSync:getRoles', function(source)
    return getAllPlayerRoles()
end)

JRS.Callback('jrs_mdt:roleSync:getMyRole', function(source)
    return PlayerRoles[source]
end)

JRS.Callback('jrs_mdt:roleSync:getConfigVersion', function(source)
    return ConfigVersion
end)

JRS.Callback('jrs_mdt:roleSync:getValidatedJobs', function(source)
    local jobs = {}
    for jobName, jobConfig in pairs(Config.LawJobs) do
        jobs[jobName] = {
            label = jobConfig.label,
            grades = jobConfig.grades
        }
    end
    return jobs
end)

JRS.Callback('jrs_mdt:server:getConfigRoles', function(source)
    local roles = {}
    for jobName, jobConfig in pairs(Config.LawJobs) do
        local grades = {}
        for gradeLevel, gradeConfig in pairs(jobConfig.grades) do
            table.insert(grades, {
                level = gradeLevel,
                label = gradeConfig.label,
                permissions = {
                    canCreateRecords = gradeConfig.canCreateRecords == true,
                    canDeleteRecords = gradeConfig.canDeleteRecords == true,
                    canManageWarrants = gradeConfig.canManageWarrants == true,
                    isAdmin = gradeConfig.isAdmin == true
                }
            })
        end
        table.sort(grades, function(a, b) return a.level < b.level end)
        table.insert(roles, {
            name = jobName,
            label = jobConfig.label,
            grades = grades,
            isConfigRole = true
        })
    end
    table.sort(roles, function(a, b) return a.label < b.label end)
    return roles
end)

-- ============================================
-- Exports
-- ============================================
exports('getPlayerRole', function(source)
    return PlayerRoles[source]
end)

exports('getAllPlayerRoles', getAllPlayerRoles)

exports('getValidatedLawJobs', function()
    local jobs = {}
    for jobName, jobConfig in pairs(Config.LawJobs) do
        jobs[jobName] = jobConfig
    end
    return jobs
end)

exports('isLawJob', function(jobName)
    return Config.LawJobs[jobName] ~= nil
end)

exports('hasPermission', function(source, permission)
    local role = PlayerRoles[source]
    if not role then return false end
    return role.permissions[permission] == true
end)

exports('isAdmin', function(source)
    return exports[GetCurrentResourceName()]:hasPermission(source, 'isAdmin')
end)

exports('forceRefreshRoles', forceRefreshAllRoles)

-- ============================================
-- Initialization
-- ============================================
CreateThread(function()
    Wait(2000)
    
    ConfigValidated = validateLawJobsConfig()
    
    if ConfigValidated then
        local players = MDTCore.GetPlayers()
        for _, src in ipairs(players) do
            updatePlayerRole(src)
        end
        print('[jrs_mdt] Role sync initialized with ' .. #getAllPlayerRoles() .. ' active law officers')
    end
end)
