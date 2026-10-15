local isOpen = false

local function startNotebookAnimation()
    local ped = PlayerPedId()
    ClearPedTasks(ped, true, true)
    Wait(100)
    Citizen.InvokeNative(0x524B54361229154F, ped, joaat('WORLD_HUMAN_WRITE_NOTEBOOK'), -1, true, false, 0, false, 0)
end

local function stopNotebookAnimation()
    local ped = PlayerPedId()
    ClearPedTasks(ped, true, true)
end

local function setIsOpen(value)
    if isOpen == value then return end
    isOpen = value
    
    if isOpen then
        startNotebookAnimation()
    else
        stopNotebookAnimation()
    end
end

-- ============================================
-- Client Access State
-- ============================================
local playerAccess = {
    hasAccess = false,
    permissions = nil,
    jobLabel = nil
}

-- ============================================
-- Client API Functions
-- ============================================
local function HasMDTAccess()
    return playerAccess.hasAccess
end

local function GetMDTPermissions()
    return playerAccess.permissions
end

local function HasMDTPermission(permission)
    if not playerAccess.permissions then return false end
    return playerAccess.permissions[permission] == true
end

local function GetMDTJobLabel()
    return playerAccess.jobLabel
end

local function RefreshMDTAccess()
    TriggerServerEvent('jrs_mdt:server:checkAccess')
end

-- ============================================
-- Client Exports
-- ============================================
exports('hasAccess', HasMDTAccess)
exports('getPermissions', GetMDTPermissions)
exports('hasPermission', HasMDTPermission)
exports('getJobLabel', GetMDTJobLabel)
exports('refreshAccess', RefreshMDTAccess)

-- ============================================
-- Client Events (Server Responses)
-- ============================================
RegisterNetEvent('jrs_mdt:client:accessResult', function(data)
    playerAccess.hasAccess = data.hasAccess
    playerAccess.permissions = data.permissions
    playerAccess.jobLabel = data.jobLabel
end)

RegisterNetEvent('jrs_mdt:client:permissionResult', function(data)
    TriggerEvent('jrs_mdt:permissionChecked', data.permission, data.hasPermission)
end)

RegisterNetEvent('jrs_mdt:client:configUpdated', function(version)
    RefreshMDTAccess()
end)

RegisterNetEvent('jrs_mdt:client:notify', function(data)
    if data.type == 'success' then
        MDTNotify({ title = locale('mdt_title'), description = data.message, type = 'success' })
    elseif data.type == 'error' then
        MDTNotify({ title = locale('mdt_title'), description = data.message, type = 'error' })
    else
        MDTNotify({ title = locale('mdt_title'), description = data.message })
    end
end)

RegisterNetEvent('jrs_mdt:client:receiveConfig', function(data)
    TriggerEvent('jrs_mdt:configReceived', data)
end)

RegisterNetEvent('jrs_mdt:client:staffUpdated', function(data)
    SendNUIMessage(json.encode({ action = 'staffUpdated', data = data }))
end)

RegisterNetEvent('jrs_mdt:client:rolesUpdated', function(data)
    SendNUIMessage(json.encode({ action = 'rolesUpdated', data = data }))
end)

-- ============================================
-- Initialization
-- ============================================
CreateThread(function()
    Wait(2000)
    NUI.SetStateCallback(setIsOpen)
    RefreshMDTAccess()
end)

RegisterNetEvent('jrs:SelectedCharacter', function()
    Wait(1000)
    RefreshMDTAccess()
end)

RegisterNetEvent('jrs_core:client:jobChanged', function(data)
    if data then
        Wait(500)
        RefreshMDTAccess()
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() and isOpen then
        stopNotebookAnimation()
    end
end)

-- ============================================
-- MDT Command
-- ============================================
RegisterCommand('mdt', function()
    if not HasMDTAccess() then
        MDTNotify({ title = locale('mdt_title'), description = locale('notification_access_denied'), type = 'error' })
        return
    end
    
    if isOpen then
        NUI.Close()
    else
        local officerInfo = JRS.Await('jrs_mdt:server:getOfficerInfo')
        NUI.Open({ officer = officerInfo, permissions = GetMDTPermissions() })
    end
end, false)

-- F7 opens the MDT
CreateThread(function()
    while true do
        Wait(0)
        if IsControlJustPressed(0, 0x1F6D95E5) and not IsPauseMenuActive() then ExecuteCommand('mdt') Wait(500) end
    end
end)

-- ============================================
-- NUI Callbacks
-- ============================================
RegisterNuiCallback('close', function(_, cb)
    NUI.Close()
    cb({ success = true })
end)

-- Citizens
RegisterNuiCallback('getAllCitizens', function(_, cb)
    local results = JRS.Await('jrs_mdt:server:getAllCitizens')
    cb(results or {})
end)

RegisterNuiCallback('searchCitizens', function(data, cb)
    local results = JRS.Await('jrs_mdt:server:searchCitizens', data.query)
    cb(results or {})
end)

RegisterNuiCallback('getCitizen', function(data, cb)
    local citizen = JRS.Await('jrs_mdt:server:getCitizen', data.citizenid)
    cb(citizen or {})
end)

RegisterNuiCallback('setProfilePicture', function(data, cb)
    local success = JRS.Await('jrs_mdt:server:setProfilePicture', data)
    cb({ success = success })
end)

-- Records
RegisterNuiCallback('getRecords', function(data, cb)
    local records = JRS.Await('jrs_mdt:server:getRecords', data.citizenid)
    cb(records or {})
end)

RegisterNuiCallback('addRecord', function(data, cb)
    local success = JRS.Await('jrs_mdt:server:addRecord', data)
    cb({ success = success })
end)

RegisterNuiCallback('deleteRecord', function(data, cb)
    cb('ok')
    local recordId = data.id
    SetTimeout(0, function()
        JRS.TriggerCallback('jrs_mdt:server:deleteRecord', function(success)
            SendNUIMessage(json.encode({ action = 'recordDeleted', data = { success = success, id = recordId } }))
        end, recordId)
    end)
end)

-- Warrants
RegisterNuiCallback('getWarrants', function(_, cb)
    local warrants = JRS.Await('jrs_mdt:server:getWarrants')
    cb(warrants or {})
end)

RegisterNuiCallback('addWarrant', function(data, cb)
    local success = JRS.Await('jrs_mdt:server:addWarrant', data)
    cb({ success = success })
end)

RegisterNuiCallback('updateWarrant', function(data, cb)
    local success = JRS.Await('jrs_mdt:server:updateWarrant', data)
    cb({ success = success })
end)

RegisterNuiCallback('deleteWarrant', function(data, cb)
    cb('ok')
    local warrantId = data.id
    SetTimeout(0, function()
        JRS.TriggerCallback('jrs_mdt:server:deleteWarrant', function(success)
            SendNUIMessage(json.encode({ action = 'warrantDeleted', data = { success = success, id = warrantId } }))
        end, warrantId)
    end)
end)

-- BOLOs
RegisterNuiCallback('getBolos', function(_, cb)
    local bolos = JRS.Await('jrs_mdt:server:getBolos')
    cb(bolos or {})
end)

RegisterNuiCallback('addBolo', function(data, cb)
    local success = JRS.Await('jrs_mdt:server:addBolo', data)
    cb({ success = success })
end)

RegisterNuiCallback('deleteBolo', function(data, cb)
    cb('ok')
    local boloId = data.id
    SetTimeout(0, function()
        JRS.TriggerCallback('jrs_mdt:server:deleteBolo', function(success)
            SendNUIMessage(json.encode({ action = 'boloDeleted', data = { success = success, id = boloId } }))
        end, boloId)
    end)
end)

-- Reports
RegisterNuiCallback('getReports', function(_, cb)
    local reports = JRS.Await('jrs_mdt:server:getReports')
    cb(reports or {})
end)

RegisterNuiCallback('getReport', function(data, cb)
    local report = JRS.Await('jrs_mdt:server:getReport', data.id)
    cb(report or {})
end)

RegisterNuiCallback('createReport', function(data, cb)
    local success = JRS.Await('jrs_mdt:server:createReport', data)
    cb({ success = success })
end)

RegisterNuiCallback('deleteReport', function(data, cb)
    cb('ok')
    local reportId = data.id
    SetTimeout(0, function()
        JRS.TriggerCallback('jrs_mdt:server:deleteReport', function(success)
            SendNUIMessage(json.encode({ action = 'reportDeleted', data = { success = success, id = reportId } }))
        end, reportId)
    end)
end)

RegisterNuiCallback('getReportComments', function(data, cb)
    local comments = JRS.Await('jrs_mdt:server:getReportComments', data.reportId)
    cb(comments or {})
end)

RegisterNuiCallback('addReportComment', function(data, cb)
    local success = JRS.Await('jrs_mdt:server:addReportComment', data)
    cb({ success = success })
end)

-- Officer Info
RegisterNuiCallback('getOfficerInfo', function(_, cb)
    local info = JRS.Await('jrs_mdt:server:getOfficerInfo')
    cb(info or {})
end)

-- Stats
RegisterNuiCallback('getStats', function(_, cb)
    local stats = JRS.Await('jrs_mdt:server:getStats')
    cb(stats or {})
end)

-- Config
RegisterNuiCallback('getIncidentTypes', function(_, cb)
    local types = JRS.Await('jrs_mdt:server:getIncidentTypes')
    cb(types or {})
end)

-- Staff Management
RegisterNuiCallback('getStaff', function(_, cb)
    local staff = JRS.Await('jrs_mdt:server:getStaff')
    cb(staff or {})
end)

RegisterNuiCallback('getRoles', function(_, cb)
    local roles = JRS.Await('jrs_mdt:server:getRoles')
    cb(roles or {})
end)

RegisterNuiCallback('addStaff', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:addStaff', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('removeStaff', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:removeStaff', data.citizenid)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('updateStaffPermissions', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:updateStaffPermissions', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('createRole', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:createRole', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('updateRole', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:updateRole', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('deleteRole', function(data, cb)
    cb('ok')
    local roleName = data.name
    SetTimeout(0, function()
        JRS.TriggerCallback('jrs_mdt:server:deleteRole', function(result)
            SendNUIMessage(json.encode({ action = 'roleDeleted', data = result or { success = false, message = locale('notification_unknown_error'), name = roleName } }))
        end, roleName)
    end)
end)

RegisterNuiCallback('getAuditLogs', function(data, cb)
    local logs = JRS.Await('jrs_mdt:server:getAuditLogs', data)
    cb(logs or {})
end)

RegisterNuiCallback('searchCitizensForStaff', function(data, cb)
    local results = JRS.Await('jrs_mdt:server:searchCitizensForStaff', data.query)
    cb(results or {})
end)

RegisterNuiCallback('getLawJobs', function(_, cb)
    local jobs = JRS.Await('jrs_mdt:server:getLawJobs')
    cb(jobs or {})
end)

RegisterNuiCallback('getConfigRoles', function(_, cb)
    local roles = JRS.Await('jrs_mdt:server:getConfigRoles')
    cb(roles or {})
end)

RegisterNuiCallback('searchPlayersForJob', function(data, cb)
    local results = JRS.Await('jrs_mdt:server:searchPlayersForJob', data.query)
    cb(results or {})
end)

RegisterNuiCallback('assignLawJob', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:assignLawJob', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('getJobGrades', function(data, cb)
    local grades = JRS.Await('jrs_mdt:server:getJobGrades', data.jobName)
    cb(grades or {})
end)

RegisterNetEvent('jrs_mdt:client:jobAssigned', function(data)
    SendNUIMessage(json.encode({ action = 'jobAssigned', data = data }))
end)

RegisterNuiCallback('updateOfficerDepartment', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:updateOfficerDepartment', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('getOfficers', function(_, cb)
    local officers = JRS.Await('jrs_mdt:server:getOfficers')
    cb(officers or {})
end)

RegisterNuiCallback('getJobPlayerCounts', function(_, cb)
    local counts = JRS.Await('jrs_mdt:server:getJobPlayerCounts')
    cb(counts or {})
end)

RegisterNuiCallback('syncStaffFromJobs', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:syncStaffFromJobs', data and data.job)
    cb(result or { success = false, message = locale('notification_unknown_error'), added = 0 })
end)

RegisterNetEvent('jrs_mdt:client:departmentUpdated', function(data)
    SendNUIMessage(json.encode({ action = 'departmentUpdated', data = data }))
end)

-- Charges
RegisterNuiCallback('getChargeTemplates', function(_, cb)
    local templates = JRS.Await('jrs_mdt:server:getChargeTemplates')
    cb(templates or {})
end)

RegisterNuiCallback('addChargeTemplate', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:addChargeTemplate', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('updateChargeTemplate', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:updateChargeTemplate', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('deleteChargeTemplate', function(data, cb)
    cb('ok')
    local templateId = data.id
    SetTimeout(0, function()
        JRS.TriggerCallback('jrs_mdt:server:deleteChargeTemplate', function(result)
            SendNUIMessage(json.encode({ action = 'chargeTemplateDeleted', data = result or { success = false, message = locale('notification_unknown_error'), id = templateId } }))
        end, templateId)
    end)
end)

RegisterNuiCallback('issueCharges', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:issueCharges', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('getIssuedCharges', function(data, cb)
    local charges = JRS.Await('jrs_mdt:server:getIssuedCharges', data.citizenid)
    cb(charges or {})
end)

RegisterNetEvent('jrs_mdt:client:chargesUpdated', function(data)
    SendNUIMessage(json.encode({ action = 'chargesUpdated', data = data }))
end)

RegisterNuiCallback('getAllIssuedCharges', function(data, cb)
    local charges = JRS.Await('jrs_mdt:server:getAllIssuedCharges', data and data.query)
    cb(charges or {})
end)

RegisterNuiCallback('getChargeDetails', function(data, cb)
    local charge = JRS.Await('jrs_mdt:server:getChargeDetails', data.id)
    cb(charge or {})
end)

RegisterNuiCallback('getAvailableReportsForAttachment', function(data, cb)
    local reports = JRS.Await('jrs_mdt:server:getAvailableReportsForAttachment', data and data.query)
    cb(reports or {})
end)

RegisterNuiCallback('attachReportsToCharge', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:attachReportsToCharge', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('removeAttachmentFromCharge', function(data, cb)
    local result = JRS.Await('jrs_mdt:server:removeAttachmentFromCharge', data)
    cb(result or { success = false, message = locale('notification_unknown_error') })
end)

RegisterNuiCallback('getChargeAttachments', function(data, cb)
    local attachments = JRS.Await('jrs_mdt:server:getChargeAttachments', data.chargeId)
    cb(attachments or {})
end)

RegisterNuiCallback('getReportsWithCharges', function(data, cb)
    local charges = JRS.Await('jrs_mdt:server:getReportsWithCharges', data.reportId)
    cb(charges or {})
end)

RegisterNuiCallback('getJailConfig', function(_, cb)
    local config = JRS.Await('jrs_mdt:server:getJailConfig')
    cb(config or {})
end)

local jailInProgress = false

RegisterNuiCallback('startJailProcess', function(data, cb)
    if jailInProgress then
        cb({ success = false, message = locale('notification_jail_in_progress') })
        return
    end
    
    local config = JRS.Await('jrs_mdt:server:getJailConfig')
    if not config or not config.enabled then
        cb({ success = false, message = locale('notification_jail_disabled') })
        return
    end
    
    local targetPlayerId = data.targetPlayerId
    if not targetPlayerId then
        cb({ success = false, message = locale('notification_target_offline') })
        return
    end
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
    
    if not targetPed or targetPed == 0 then
        cb({ success = false, message = locale('notification_target_not_found') })
        return
    end
    
    local targetCoords = GetEntityCoords(targetPed)
    local distToTarget = #(playerCoords - targetCoords)
    
    if distToTarget > config.maxDistance then
        cb({ success = false, message = locale('notification_target_too_far') })
        return
    end
    
    cb({ success = true, delaySeconds = config.delaySeconds })
    
    jailInProgress = true
    local targetPlayerId = data.targetPlayerId
    
    SendNUIMessage(json.encode({ 
        action = 'jailStatus', 
        data = { status = 'processing', remaining = config.delaySeconds } 
    }))
    
    local delayMs = config.delaySeconds * 1000
    local startTime = GetGameTimer()
    
    while jailInProgress do
        local elapsed = GetGameTimer() - startTime
        local remaining = math.ceil((delayMs - elapsed) / 1000)
        
        if remaining <= 0 then
            break
        end
        
        local currentPed = PlayerPedId()
        local currentCoords = GetEntityCoords(currentPed)
        local distToTarget = targetPlayerId and #(currentCoords - GetEntityCoords(GetPlayerPed(GetPlayerFromServerId(targetPlayerId)))) or 999
        
        if distToTarget > config.maxDistance then
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { status = locale('jail_cancelled'), message = locale('notification_target_moved') } 
            }))
            jailInProgress = false
            return
        end
        
        SendNUIMessage(json.encode({ 
            action = 'jailStatus', 
            data = { status = locale('jail_processing'), remaining = remaining } 
        }))
        
        Wait(500)
    end
    
    if not jailInProgress then
        return
    end
    
    local result = JRS.Await('jrs_mdt:server:jailPlayer', {
        citizenid = data.citizenid,
        minutes = data.minutes,
        reason = data.reason
    })
    
    SendNUIMessage(json.encode({ 
        action = 'jailStatus', 
        data = { 
            status = result and result.success and locale('jail_completed') or locale('jail_failed'),
            message = result and result.message or locale('notification_unknown_error')
        } 
    }))
    
    jailInProgress = false
end)

RegisterNuiCallback('commitCharges', function(data, cb)
    if jailInProgress then
        cb({ success = false, message = locale('notification_jail_in_progress') })
        return
    end
    
    local config = JRS.Await('jrs_mdt:server:getJailConfig')
    if not config or not config.enabled then
        cb({ success = false, message = locale('notification_jail_disabled') })
        return
    end
    
    local targetPlayerId = data.targetPlayerId
    if not targetPlayerId then
        cb({ success = false, message = locale('notification_target_offline') })
        return
    end
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
    
    if not targetPed or targetPed == 0 then
        cb({ success = false, message = locale('notification_target_not_found') })
        return
    end
    
    local targetCoords = GetEntityCoords(targetPed)
    local distToTarget = #(playerCoords - targetCoords)
    
    if distToTarget > config.maxDistance then
        cb({ success = false, message = locale('notification_target_too_far') })
        return
    end
    
    cb({ success = true, delaySeconds = config.delaySeconds })
    
    jailInProgress = true
    local targetPlayerId = data.targetPlayerId
    
    SendNUIMessage(json.encode({ 
        action = 'jailStatus', 
        data = { status = locale('jail_processing'), remaining = config.delaySeconds } 
    }))
    
    local delayMs = config.delaySeconds * 1000
    local startTime = GetGameTimer()
    
    while jailInProgress do
        local elapsed = GetGameTimer() - startTime
        local remaining = math.ceil((delayMs - elapsed) / 1000)
        
        if remaining <= 0 then
            break
        end
        
        local currentPed = PlayerPedId()
        local currentCoords = GetEntityCoords(currentPed)
        local targetPed = targetPlayerId and GetPlayerPed(GetPlayerFromServerId(targetPlayerId)) or nil
        local distToTarget = targetPed and #(currentCoords - GetEntityCoords(targetPed)) or 999
        
        if distToTarget > config.maxDistance then
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { status = locale('jail_cancelled'), message = locale('notification_target_moved') } 
            }))
            jailInProgress = false
            return
        end
        
        SendNUIMessage(json.encode({ 
            action = 'jailStatus', 
            data = { status = locale('jail_processing'), remaining = remaining } 
        }))
        
        Wait(500)
    end
    
    if not jailInProgress then
        return
    end
    
    local result = JRS.Await('jrs_mdt:server:commitCharges', data)
    
    if result and result.success then
        SendNUIMessage(json.encode({ 
            action = 'jailStatus', 
            data = { 
                status = locale('jail_completed'),
                message = result.message,
                totalJailtime = result.totalJailtime,
                totalServed = result.totalServed
            } 
        }))
        
        SendNUIMessage(json.encode({
            action = 'chargesUpdated',
            data = {
                citizenid = data.citizenid,
                totalJailtime = result.totalJailtime,
                totalServed = result.totalServed
            }
        }))
    else
        SendNUIMessage(json.encode({ 
            action = 'jailStatus', 
            data = { 
                status = locale('jail_failed'),
                message = result and result.message or locale('notification_unknown_error')
            } 
        }))
    end
    
    jailInProgress = false
end)

RegisterNuiCallback('getCitizenJailTotals', function(data, cb)
    local totals = JRS.Await('jrs_mdt:server:getCitizenJailTotals', data.citizenid)
    cb(totals or { totalJailtime = 0, totalServed = 0, outstanding = 0, charges = {} })
end)

RegisterNuiCallback('abortJail', function(_, cb)
    if jailInProgress then
        jailInProgress = false
        SendNUIMessage(json.encode({ 
            action = 'jailStatus', 
            data = { status = locale('jail_cancelled'), message = locale('notification_jail_aborted') } 
        }))
    end
    cb({ success = true })
end)

RegisterNuiCallback('submitCharges', function(data, cb)
    local hasJailTime = data.totalJailtime and data.totalJailtime > 0
    local targetPlayerId = data.targetPlayerId
    
    if hasJailTime and targetPlayerId then
        if jailInProgress then
            cb({ success = false, message = locale('notification_jail_in_progress'), requiresDelay = true })
            return
        end
        
        local config = JRS.Await('jrs_mdt:server:getJailConfig')
        if not config or not config.enabled then
            cb({ success = false, message = locale('notification_jail_disabled'), requiresDelay = true })
            return
        end
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
        
        if not targetPed or targetPed == 0 then
            cb({ success = false, message = locale('notification_target_not_found'), requiresDelay = true })
            return
        end
        
        local targetCoords = GetEntityCoords(targetPed)
        local distToTarget = #(playerCoords - targetCoords)
        
        if distToTarget > config.maxDistance then
            cb({ success = false, message = locale('notification_target_too_far'), requiresDelay = true })
            return
        end
        
        cb({ success = true, delaySeconds = config.delaySeconds, requiresDelay = true })
        
        jailInProgress = true
        
        local citizenName = data.citizenName or locale('system_suspect')
        
        SendNUIMessage(json.encode({ 
            action = 'jailStatus', 
            data = { status = locale('jail_processing'), remaining = config.delaySeconds, citizenName = citizenName } 
        }))
        
        local delayMs = config.delaySeconds * 1000
        local startTime = GetGameTimer()
        
        while jailInProgress do
            local elapsed = GetGameTimer() - startTime
            local remaining = math.ceil((delayMs - elapsed) / 1000)
            
            if remaining <= 0 then
                break
            end
            
            local currentPed = PlayerPedId()
            local currentCoords = GetEntityCoords(currentPed)
            local checkPed = targetPlayerId and GetPlayerPed(GetPlayerFromServerId(targetPlayerId)) or nil
            local checkDist = checkPed and #(currentCoords - GetEntityCoords(checkPed)) or 999
            
            if checkDist > config.maxDistance then
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { status = locale('jail_cancelled'), message = locale('notification_target_moved'), citizenName = citizenName } 
            }))
                jailInProgress = false
                return
            end
            
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { status = locale('jail_processing'), remaining = remaining, citizenName = citizenName } 
            }))
            
            Wait(500)
        end
        
        if not jailInProgress then
            return
        end
        
        local result = JRS.Await('jrs_mdt:server:submitCharges', data)
        
        if result and result.success then
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { 
                    status = locale('jail_completed'),
                    message = result.message,
                    totalJailtime = result.totalJailtime,
                    totalServed = result.totalServed,
                    jailed = result.jailed,
                    citizenName = citizenName
                } 
            }))
            
            SendNUIMessage(json.encode({
                action = 'chargesUpdated',
                data = {
                    citizenid = data.citizenid,
                    totalJailtime = result.totalJailtime,
                    totalServed = result.totalServed
                }
            }))
        else
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { 
                    status = locale('jail_failed'),
                    message = result and result.message or locale('notification_unknown_error'),
                    citizenName = citizenName
                } 
            }))
        end
        
        jailInProgress = false
    else
        cb({ success = true, requiresDelay = false })
        
        local result = JRS.Await('jrs_mdt:server:submitCharges', data)
        
        if result and result.success then
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { 
                    status = locale('jail_completed'),
                    message = result.message,
                    totalJailtime = result.totalJailtime,
                    totalServed = result.totalServed,
                    jailed = result.jailed
                } 
            }))
        else
            SendNUIMessage(json.encode({ 
                action = 'jailStatus', 
                data = { 
                    status = locale('jail_failed'),
                    message = result and result.message or locale('notification_unknown_error')
                } 
            }))
        end
    end
end)
