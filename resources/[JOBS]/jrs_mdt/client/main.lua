-- jrs_mdt | client: opening the MDT, talking to the page and the jail countdown
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local open = false
local access = { hasAccess = false, permissions = nil, jobLabel = nil }

local NOTEBOOK <const> = joaat('WORLD_HUMAN_WRITE_NOTEBOOK')
local OPEN_KEY <const> = 0x1F6D95E5                      -- F7

-- the officer writes in a notebook while the MDT is open
local function setOpen(value)
    if open == value then return end
    open = value

    local ped = PlayerPedId()
    ClearPedTasks(ped, true, true)
    if open then
        Wait(100)
        Citizen.InvokeNative(0x524B54361229154F, ped, NOTEBOOK, -1, true, false, 0, false, 0)
    end
end

local function refreshAccess() TriggerServerEvent('jrs_mdt:server:checkAccess') end

exports('hasAccess', function() return access.hasAccess end)
exports('getPermissions', function() return access.permissions end)
exports('hasPermission', function(permission) return access.permissions ~= nil and access.permissions[permission] == true end)
exports('getJobLabel', function() return access.jobLabel end)
exports('refreshAccess', refreshAccess)

-- ------------------------------------------------------------------ events from the server

RegisterNetEvent('jrs_mdt:client:accessResult', function(data)
    access.hasAccess, access.permissions, access.jobLabel = data.hasAccess, data.permissions, data.jobLabel
end)

RegisterNetEvent('jrs_mdt:client:permissionResult', function(data) TriggerEvent('jrs_mdt:permissionChecked', data.permission, data.hasPermission) end)
RegisterNetEvent('jrs_mdt:client:configUpdated', refreshAccess)
RegisterNetEvent('jrs_mdt:client:receiveConfig', function(data) TriggerEvent('jrs_mdt:configReceived', data) end)

RegisterNetEvent('jrs_mdt:client:notify', function(data)
    MDTNotify({ title = locale('mdt_title'), description = data.message, type = data.type })
end)

-- events the page wants to hear about, passed on unchanged
for event, action in pairs({
    ['jrs_mdt:client:staffUpdated'] = 'staffUpdated', ['jrs_mdt:client:rolesUpdated'] = 'rolesUpdated',
    ['jrs_mdt:client:jobAssigned'] = 'jobAssigned', ['jrs_mdt:client:departmentUpdated'] = 'departmentUpdated',
    ['jrs_mdt:client:chargesUpdated'] = 'chargesUpdated',
}) do
    RegisterNetEvent(event, function(data) NUI.Message(action, data) end)
end

CreateThread(function()
    Wait(2000)
    NUI.SetStateCallback(setOpen)
    refreshAccess()
end)

RegisterNetEvent('jrs:SelectedCharacter', function()
    Wait(1000)
    refreshAccess()
end)

RegisterNetEvent('jrs_core:client:jobChanged', function(data)
    if data then Wait(500) refreshAccess() end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then ClearPedTasks(PlayerPedId(), true, true) end
end)

-- ------------------------------------------------------------------ opening

RegisterCommand('mdt', function()
    if not access.hasAccess then
        return MDTNotify({ title = locale('mdt_title'), description = locale('notification_access_denied'), type = 'error' })
    end

    if open then return NUI.Close() end
    NUI.Open({ officer = JRS.Await('jrs_mdt:server:getOfficerInfo'), permissions = access.permissions, language = Config.Language })
end, false)

CreateThread(function()
    while true do
        Wait(0)
        if IsControlJustPressed(0, OPEN_KEY) and not IsPauseMenuActive() then
            ExecuteCommand('mdt')
            Wait(500)
        end
    end
end)

RegisterNuiCallback('close', function(_, cb)
    NUI.Close()
    cb({ success = true })
end)

-- ------------------------------------------------------------------ page -> server bridges

local FAILED <const> = function() return { success = false, message = locale('notification_unknown_error') } end

-- the page calls `name`; the server callback answers with data (or `empty`)
local function ask(name, serverName, argument, empty)
    RegisterNuiCallback(name, function(data, cb)
        local payload
        if argument then payload = argument(data or {}) end
        cb(JRS.Await(serverName, payload) or empty)
    end)
end

-- same, but the server answers true/false and the page gets { success }
local function tell(name, serverName)
    RegisterNuiCallback(name, function(data, cb) cb({ success = JRS.Await(serverName, data) }) end)
end

-- same, but the server already answers { success, message }
local function act(name, serverName, argument)
    RegisterNuiCallback(name, function(data, cb)
        local payload = data
        if argument then payload = argument(data or {}) end
        cb(JRS.Await(serverName, payload) or FAILED())
    end)
end

-- deletes are answered later through a message, so a slow database never freezes the page
local function remove(name, serverName, idKey, action, merge)
    RegisterNuiCallback(name, function(data, cb)
        cb('ok')
        local id = data[idKey]
        SetTimeout(0, function()
            JRS.TriggerCallback(serverName, function(result)
                if merge then
                    result = result or FAILED()
                    result[idKey] = result[idKey] or id
                    NUI.Message(action, result)
                else
                    NUI.Message(action, { success = result, id = id })
                end
            end, id)
        end)
    end)
end

local function field(key) return function(data) return data[key] end end

-- citizens
ask('getAllCitizens', 'jrs_mdt:server:getAllCitizens', nil, {})
ask('searchCitizens', 'jrs_mdt:server:searchCitizens', field('query'), {})
ask('getCitizen', 'jrs_mdt:server:getCitizen', field('citizenid'), {})
tell('setProfilePicture', 'jrs_mdt:server:setProfilePicture')

-- records, warrants, BOLOs
ask('getRecords', 'jrs_mdt:server:getRecords', field('citizenid'), {})
tell('addRecord', 'jrs_mdt:server:addRecord')
remove('deleteRecord', 'jrs_mdt:server:deleteRecord', 'id', 'recordDeleted')
ask('getWarrants', 'jrs_mdt:server:getWarrants', nil, {})
tell('addWarrant', 'jrs_mdt:server:addWarrant')
tell('updateWarrant', 'jrs_mdt:server:updateWarrant')
remove('deleteWarrant', 'jrs_mdt:server:deleteWarrant', 'id', 'warrantDeleted')
ask('getBolos', 'jrs_mdt:server:getBolos', nil, {})
tell('addBolo', 'jrs_mdt:server:addBolo')
remove('deleteBolo', 'jrs_mdt:server:deleteBolo', 'id', 'boloDeleted')

-- reports
ask('getReports', 'jrs_mdt:server:getReports', nil, {})
ask('getReport', 'jrs_mdt:server:getReport', field('id'), {})
tell('createReport', 'jrs_mdt:server:createReport')
remove('deleteReport', 'jrs_mdt:server:deleteReport', 'id', 'reportDeleted')
ask('getReportComments', 'jrs_mdt:server:getReportComments', field('reportId'), {})
tell('addReportComment', 'jrs_mdt:server:addReportComment')

-- officer and numbers
ask('getOfficerInfo', 'jrs_mdt:server:getOfficerInfo', nil, {})
ask('getStats', 'jrs_mdt:server:getStats', nil, {})
ask('getIncidentTypes', 'jrs_mdt:server:getIncidentTypes', nil, {})

-- staff, roles and departments (admins)
ask('getStaff', 'jrs_mdt:server:getStaff', nil, {})
ask('getRoles', 'jrs_mdt:server:getRoles', nil, {})
act('addStaff', 'jrs_mdt:server:addStaff')
act('removeStaff', 'jrs_mdt:server:removeStaff', field('citizenid'))
act('updateStaffPermissions', 'jrs_mdt:server:updateStaffPermissions')
act('createRole', 'jrs_mdt:server:createRole')
act('updateRole', 'jrs_mdt:server:updateRole')
remove('deleteRole', 'jrs_mdt:server:deleteRole', 'name', 'roleDeleted', true)
ask('getAuditLogs', 'jrs_mdt:server:getAuditLogs', function(data) return data end, {})
ask('searchCitizensForStaff', 'jrs_mdt:server:searchCitizensForStaff', field('query'), {})
ask('getLawJobs', 'jrs_mdt:server:getLawJobs', nil, {})
ask('getConfigRoles', 'jrs_mdt:server:getConfigRoles', nil, {})
ask('searchPlayersForJob', 'jrs_mdt:server:searchPlayersForJob', field('query'), {})
act('assignLawJob', 'jrs_mdt:server:assignLawJob')
ask('getJobGrades', 'jrs_mdt:server:getJobGrades', field('jobName'), {})
act('updateOfficerDepartment', 'jrs_mdt:server:updateOfficerDepartment')
ask('getOfficers', 'jrs_mdt:server:getOfficers', nil, {})
ask('getJobPlayerCounts', 'jrs_mdt:server:getJobPlayerCounts', nil, {})

RegisterNuiCallback('syncStaffFromJobs', function(data, cb)
    cb(JRS.Await('jrs_mdt:server:syncStaffFromJobs', data and data.job)
        or { success = false, message = locale('notification_unknown_error'), added = 0 })
end)

-- charges
ask('getChargeTemplates', 'jrs_mdt:server:getChargeTemplates', nil, {})
act('addChargeTemplate', 'jrs_mdt:server:addChargeTemplate')
act('updateChargeTemplate', 'jrs_mdt:server:updateChargeTemplate')
remove('deleteChargeTemplate', 'jrs_mdt:server:deleteChargeTemplate', 'id', 'chargeTemplateDeleted', true)
act('issueCharges', 'jrs_mdt:server:issueCharges')
ask('getIssuedCharges', 'jrs_mdt:server:getIssuedCharges', field('citizenid'), {})
ask('getAllIssuedCharges', 'jrs_mdt:server:getAllIssuedCharges', field('query'), {})
ask('getChargeDetails', 'jrs_mdt:server:getChargeDetails', field('id'), {})
ask('getAvailableReportsForAttachment', 'jrs_mdt:server:getAvailableReportsForAttachment', field('query'), {})
act('attachReportsToCharge', 'jrs_mdt:server:attachReportsToCharge')
act('removeAttachmentFromCharge', 'jrs_mdt:server:removeAttachmentFromCharge')
ask('getChargeAttachments', 'jrs_mdt:server:getChargeAttachments', field('chargeId'), {})
ask('getReportsWithCharges', 'jrs_mdt:server:getReportsWithCharges', field('reportId'), {})
ask('getJailConfig', 'jrs_mdt:server:getJailConfig', nil, {})
ask('getCitizenJailTotals', 'jrs_mdt:server:getCitizenJailTotals', field('citizenid'), { totalJailtime = 0, totalServed = 0, outstanding = 0, charges = {} })

-- ------------------------------------------------------------------ the jail countdown
-- The officer has to stay close to the person for a few seconds before the sentence starts.
-- The page follows along through 'jailStatus' messages: processing / cancelled / completed / failed.

local jailing = false

local function status(code, message, extra)
    local data = extra or {}
    data.status, data.message = code, message
    NUI.Message('jailStatus', data)
end

local function targetPed(serverId) return GetPlayerPed(GetPlayerFromServerId(serverId)) end

-- the jail settings when a sentence may start now, else nil and the key of the reason
local function mayStart(serverId)
    if jailing then return nil, 'notification_jail_in_progress' end

    local jail = JRS.Await('jrs_mdt:server:getJailConfig')
    if not jail or not jail.enabled then return nil, 'notification_jail_disabled' end
    if not serverId then return nil, 'notification_target_offline' end

    local ped = targetPed(serverId)
    if not ped or ped == 0 then return nil, 'notification_target_not_found' end
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) > jail.maxDistance then return nil, 'notification_target_too_far' end
    return jail
end

-- true when the whole delay passed with the person still in reach
local function waitDelay(jail, serverId, extra)
    local started, total = GetGameTimer(), jail.delaySeconds * 1000

    while jailing do
        local left = math.ceil((total - (GetGameTimer() - started)) / 1000)
        if left <= 0 then return true end

        local ped = targetPed(serverId)
        local away = ped ~= 0 and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) or 999
        if away > jail.maxDistance then
            jailing = false
            status('cancelled', locale('notification_target_moved'), { citizenName = extra and extra.citizenName })
            return false
        end

        local data = { remaining = left }
        if extra then data.citizenName = extra.citizenName end
        status('processing', nil, data)
        Wait(500)
    end
    return false                                         -- the officer aborted
end

-- runs the countdown and then `finish()`, which returns the server's answer
local function serveSentence(jail, serverId, extra, finish)
    jailing = true
    local first = { remaining = jail.delaySeconds }
    if extra then first.citizenName = extra.citizenName end
    status('processing', nil, first)

    if not waitDelay(jail, serverId, extra) then return end
    finish()
    jailing = false
end

-- a finished sentence: tell the page and, when charges were written, the new jail totals
local function report(result, citizenid, extra)
    local data = extra or {}
    if result and result.success then
        data.message, data.totalJailtime, data.totalServed, data.jailed = result.message, result.totalJailtime, result.totalServed, result.jailed
        status('completed', result.message, data)
        NUI.Message('chargesUpdated', { citizenid = citizenid, totalJailtime = result.totalJailtime, totalServed = result.totalServed })
    else
        status('failed', result and result.message or locale('notification_unknown_error'), data)
    end
end

RegisterNuiCallback('startJailProcess', function(data, cb)
    local jail, why = mayStart(data.targetPlayerId)
    if not jail then return cb({ success = false, message = locale(why) }) end
    cb({ success = true, delaySeconds = jail.delaySeconds })

    serveSentence(jail, data.targetPlayerId, nil, function()
        local result = JRS.Await('jrs_mdt:server:jailPlayer', { citizenid = data.citizenid, minutes = data.minutes, reason = data.reason })
        status(result and result.success and 'completed' or 'failed', result and result.message or locale('notification_unknown_error'))
    end)
end)

RegisterNuiCallback('commitCharges', function(data, cb)
    local jail, why = mayStart(data.targetPlayerId)
    if not jail then return cb({ success = false, message = locale(why) }) end
    cb({ success = true, delaySeconds = jail.delaySeconds })

    serveSentence(jail, data.targetPlayerId, nil, function()
        report(JRS.Await('jrs_mdt:server:commitCharges', data), data.citizenid)
    end)
end)

RegisterNuiCallback('submitCharges', function(data, cb)
    local sentence = data.totalJailtime and data.totalJailtime > 0 and data.targetPlayerId

    -- nothing to serve (or the person is not here): the charges are just written
    if not sentence then
        cb({ success = true, requiresDelay = false })
        return report(JRS.Await('jrs_mdt:server:submitCharges', data), data.citizenid)
    end

    local jail, why = mayStart(data.targetPlayerId)
    if not jail then return cb({ success = false, message = locale(why), requiresDelay = true }) end
    cb({ success = true, delaySeconds = jail.delaySeconds, requiresDelay = true })

    local extra = { citizenName = data.citizenName or locale('system_suspect') }
    serveSentence(jail, data.targetPlayerId, extra, function()
        report(JRS.Await('jrs_mdt:server:submitCharges', data), data.citizenid, extra)
    end)
end)

RegisterNuiCallback('abortJail', function(_, cb)
    if jailing then
        jailing = false
        status('cancelled', locale('notification_jail_aborted'))
    end
    cb({ success = true })
end)
