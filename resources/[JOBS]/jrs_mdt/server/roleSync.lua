-- jrs_mdt | server: keeps every client told what rank each online officer has
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- The server's copy is the truth; clients may ask for it and report theirs so a mismatch can be corrected.

local roles = {}                       -- source -> role data of an online officer
local version = 1

local function checkLawJobs()
    if type(Config.LawJobs) ~= 'table' then
        print('[jrs_mdt] ERROR: Config.LawJobs must be a table!')
        return false
    end

    local valid = 0
    for name, job in pairs(Config.LawJobs) do
        if type(name) ~= 'string' then
            print('[jrs_mdt] WARNING: LawJob key must be a string, skipping: ' .. tostring(name))
        elseif not job.label then
            print('[jrs_mdt] WARNING: LawJob "' .. name .. '" has no label')
        elseif type(job.grades) ~= 'table' then
            print('[jrs_mdt] WARNING: LawJob "' .. name .. '" has no grades table')
        else
            for level in pairs(job.grades) do
                if type(level) ~= 'number' then print('[jrs_mdt] WARNING: LawJob "' .. name .. '" has a non numeric grade: ' .. tostring(level)) end
            end
            valid = valid + 1
        end
    end

    if valid == 0 then print('[jrs_mdt] ERROR: no valid law job in Config.LawJobs!') return false end
    print('[jrs_mdt] Config.LawJobs checked: ' .. valid .. ' law job(s)')
    return true
end

-- role data of an online officer, nil when the player is not law
local function roleOf(src)
    local player, department, grade = MDT.Standing(src)
    if not department then return nil end

    local info = player.PlayerData.charinfo
    local level = player.PlayerData.job.grade and player.PlayerData.job.grade.level or 0
    return {
        source = src,
        citizenid = player.PlayerData.citizenid,
        name = info and info.firstname and info.firstname .. ' ' .. info.lastname or 'Unknown',
        job = { name = player.PlayerData.job.name, label = department.label, grade = level, gradeLabel = grade.label or 'Unknown' },
        permissions = {
            canCreateRecords = grade.canCreateRecords == true, canDeleteRecords = grade.canDeleteRecords == true,
            canManageWarrants = grade.canManageWarrants == true, isAdmin = grade.isAdmin == true,
        },
        configVersion = version,
    }
end

local function tellAll(src, data, change)
    TriggerClientEvent('jrs_mdt:roleSync:roleUpdated', -1, { source = src, roleData = data, changeType = change })
end

-- re-reads one player: announces the add, the change or the removal
local function refresh(src)
    local fresh, old = roleOf(src), roles[src]
    roles[src] = fresh

    if fresh and not old then tellAll(src, fresh, 'add')
    elseif fresh and (old.job.name ~= fresh.job.name or old.job.grade ~= fresh.job.grade) then tellAll(src, fresh, 'update')
    elseif old and not fresh then tellAll(src, old, 'remove') end
    return fresh
end

local function everyRole()
    local list = {}
    for _, role in pairs(roles) do list[#list + 1] = role end
    return list
end

local function refreshAll()
    version = version + 1
    for src in pairs(roles) do refresh(src) end
    TriggerClientEvent('jrs_mdt:roleSync:forceRefresh', -1, { configVersion = version, roles = everyRole() })
    print('[jrs_mdt] roles refreshed, version ' .. version)
end

-- ------------------------------------------------------------------ what clients ask for

RegisterNetEvent('jrs_mdt:roleSync:requestRoles', function()
    local src = source
    TriggerClientEvent('jrs_mdt:roleSync:receiveRoles', src, { configVersion = version, roles = everyRole(), yourRole = roles[src] })
end)

RegisterNetEvent('jrs_mdt:roleSync:requestMyRole', function()
    local src = source
    TriggerClientEvent('jrs_mdt:roleSync:receiveMyRole', src, roles[src])
end)

RegisterNetEvent('jrs_mdt:roleSync:validateLocalState', function(theirs)
    local src = source
    local mine = roles[src]

    local function mismatch(message) TriggerClientEvent('jrs_mdt:roleSync:stateMismatch', src, { localState = theirs, serverState = mine, message = message }) end

    if theirs and mine then
        if theirs.job.name ~= mine.job.name or theirs.job.grade ~= mine.job.grade or theirs.configVersion ~= mine.configVersion then
            mismatch(locale('role_state_mismatch'))
        end
    elseif theirs then
        mismatch(locale('role_local_no_server'))
    elseif mine then
        mismatch(locale('role_server_no_local'))
    end
end)

RegisterNetEvent('jrs_mdt:roleSync:adminForceRefresh', function()
    local src = source
    local allowed = roles[src] and roles[src].permissions.isAdmin

    if allowed then refreshAll() end
    TriggerClientEvent('jrs_mdt:roleSync:refreshComplete', src, allowed
        and { success = true, message = locale('role_refresh_success'), configVersion = version }
        or { success = false, message = locale('role_refresh_denied') })
end)

-- ------------------------------------------------------------------ keeping it current

AddEventHandler('jrs:SelectedCharacter', function(src)
    if not src then return end
    Wait(1000)
    refresh(src)
end)

AddEventHandler('jrs_core:server:jobChanged', function(src)
    Wait(500)
    refresh(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if roles[src] then
        tellAll(src, roles[src], 'remove')
        roles[src] = nil
    end
end)

-- ------------------------------------------------------------------ callbacks

JRS.Callback('jrs_mdt:roleSync:getRoles', everyRole)
JRS.Callback('jrs_mdt:roleSync:getMyRole', function(src) return roles[src] end)
JRS.Callback('jrs_mdt:roleSync:getConfigVersion', function() return version end)

JRS.Callback('jrs_mdt:roleSync:getValidatedJobs', function()
    local jobs = {}
    for name, job in pairs(Config.LawJobs) do jobs[name] = { label = job.label, grades = job.grades } end
    return jobs
end)

-- every department with the permissions of each rank, for the admin screen
JRS.Callback('jrs_mdt:server:getConfigRoles', function()
    local list = {}
    for name, job in pairs(Config.LawJobs) do
        local grades = {}
        for level, grade in pairs(job.grades) do
            grades[#grades + 1] = {
                level = level, label = grade.label,
                permissions = {
                    canCreateRecords = grade.canCreateRecords == true, canDeleteRecords = grade.canDeleteRecords == true,
                    canManageWarrants = grade.canManageWarrants == true, isAdmin = grade.isAdmin == true,
                },
            }
        end
        table.sort(grades, function(a, b) return a.level < b.level end)
        list[#list + 1] = { name = name, label = job.label, grades = grades, isConfigRole = true }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)

-- ------------------------------------------------------------------ exports

exports('getPlayerRole', function(src) return roles[src] end)
exports('getAllPlayerRoles', everyRole)
exports('getValidatedLawJobs', function() return Config.LawJobs end)
exports('isLawJob', function(name) return Config.LawJobs[name] ~= nil end)
exports('hasPermission', function(src, permission) return roles[src] ~= nil and roles[src].permissions[permission] == true end)
exports('isAdmin', function(src) return roles[src] ~= nil and roles[src].permissions.isAdmin == true end)
exports('forceRefreshRoles', refreshAll)

CreateThread(function()
    Wait(2000)
    if not checkLawJobs() then return end

    for _, id in ipairs(MDTCore.GetPlayers()) do refresh(tonumber(id)) end
    print('[jrs_mdt] role sync is running with ' .. #everyRole() .. ' law officer(s)')
end)
