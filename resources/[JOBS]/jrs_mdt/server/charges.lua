
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

local function hasCreateRecordsPermission(source)
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    
    local job = player.PlayerData.job
    if not job then return false end
    
    local jobConfig = Config.LawJobs[job.name]
    if not jobConfig then return false end
    
    local gradeConfig = jobConfig.grades[job.grade.level]
    if not gradeConfig then return false end
    
    return gradeConfig.canCreateRecords == true
end

local function selfOrLaw(source, citizenid)
    local player = MDTCore.GetPlayer(source)
    if not player then return false end
    if citizenid ~= nil and citizenid == player.PlayerData.citizenid then return true end
    return hasCreateRecordsPermission(source)
end

local function logChargeAction(source, action, targetType, targetId, targetName, details)
    local player = MDTCore.GetPlayer(source)
    if not player then return end
    
    local performerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local performerCid = player.PlayerData.citizenid
    
    MySQL.insert.await(
        "INSERT INTO mdt_audit_logs (action, target_type, target_id, target_name, details, performed_by, performed_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
        { action, targetType, targetId, targetName, details and json.encode(details) or nil, performerCid, performerName }
    )
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

local function broadcastToAdmins(event, data)
    local admins = getAdmins()
    for _, adminId in ipairs(admins) do
        TriggerClientEvent(event, adminId, data)
    end
end

local function getLawOfficers()
    local officers = {}
    local players = MDTCore.GetPlayers()
    for _, playerId in ipairs(players) do
        local src = tonumber(playerId)
        local player = MDTCore.GetPlayer(src)
        if player and player.PlayerData.job then
            local jobName = player.PlayerData.job.name
            if Config.LawJobs[jobName] then
                table.insert(officers, src)
            end
        end
    end
    return officers
end

local function broadcastToOfficers(event, data)
    local officers = getLawOfficers()
    for _, officerId in ipairs(officers) do
        TriggerClientEvent(event, officerId, data)
    end
end

JRS.Callback('jrs_mdt:server:getChargeTemplates', function(source)
    if not MDTCore.GetPlayer(source) then return {} end
    local templates = MySQL.query.await(
        "SELECT * FROM mdt_charge_templates ORDER BY category, name"
    )
    
    return templates or {}
end)

JRS.Callback('jrs_mdt:server:addChargeTemplate', function(source, data)
    if not hasAdminPermission(source) then
        return { success = false, message = locale('notification_charge_permission') }
    end
    
    local name = data.name
    local description = data.description or ''
    local fine = tonumber(data.fine) or 0
    local jailtime = tonumber(data.jailtime) or 0
    local category = data.category or 'misdemeanor'
    
    if not name or #name < 2 then
        return { success = false, message = locale('notification_charge_name_required') }
    end
    
    local existing = MySQL.query.await("SELECT id FROM mdt_charge_templates WHERE name = ?", { name })
    if existing and existing[1] then
        return { success = false, message = locale('notification_charge_exists') }
    end
    
    local player = MDTCore.GetPlayer(source)
    local createdBy = player and player.PlayerData.citizenid or nil
    local createdByName = player and (player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname) or 'System'
    
    local insertId = MySQL.insert.await(
        "INSERT INTO mdt_charge_templates (name, description, fine, jailtime, category, created_by, created_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
        { name, description, fine, jailtime, category, createdBy, createdByName }
    )
    
    if insertId then
        logChargeAction(source, 'charge_template_created', 'charge_template', tostring(insertId), name, {
            name = name,
            fine = fine,
            jailtime = jailtime,
            category = category
        })
        
        broadcastToAdmins('jrs_mdt:client:chargesUpdated', { action = 'created', id = insertId, name = name })
        
        return { success = true, id = insertId }
    end
    
    return { success = false, message = locale('notification_failed_create_charge') }
end)

JRS.Callback('jrs_mdt:server:updateChargeTemplate', function(source, data)
    if not hasAdminPermission(source) then
        return { success = false, message = locale('notification_charge_permission') }
    end
    
    local id = tonumber(data.id)
    local name = data.name
    local description = data.description
    local fine = tonumber(data.fine)
    local jailtime = tonumber(data.jailtime)
    local category = data.category
    
    if not id then
        return { success = false, message = locale('notification_charge_id_required') }
    end
    
    local existing = MySQL.query.await("SELECT name FROM mdt_charge_templates WHERE id = ?", { id })
    if not existing or not existing[1] then
        return { success = false, message = locale('notification_charge_not_found') }
    end
    
    local oldName = existing[1].name
    
    local affected = MySQL.update.await(
        "UPDATE mdt_charge_templates SET name = ?, description = ?, fine = ?, jailtime = ?, category = ? WHERE id = ?",
        { name, description, fine, jailtime, category, id }
    )
    
    if affected then
        logChargeAction(source, 'charge_template_updated', 'charge_template', tostring(id), oldName, {
            oldName = oldName,
            newName = name,
            fine = fine,
            jailtime = jailtime,
            category = category
        })
        
        broadcastToAdmins('jrs_mdt:client:chargesUpdated', { action = 'updated', id = id, name = name })
        
        return { success = true }
    end
    
    return { success = false, message = locale('notification_failed_update_charge') }
end)

JRS.Callback('jrs_mdt:server:deleteChargeTemplate', function(source, id)
    if not hasAdminPermission(source) then
        return { success = false, message = locale('notification_charge_permission') }
    end
    
    id = tonumber(id)
    if not id then
        return { success = false, message = locale('notification_charge_id_required') }
    end
    
    local template = MySQL.query.await("SELECT name FROM mdt_charge_templates WHERE id = ?", { id })
    if not template or not template[1] then
        return { success = false, message = locale('notification_charge_not_found') }
    end
    
    local templateName = template[1].name
    
    local affected = MySQL.update.await("DELETE FROM mdt_charge_templates WHERE id = ?", { id })
    
    if affected and affected > 0 then
        logChargeAction(source, 'charge_template_deleted', 'charge_template', tostring(id), templateName)
        
        broadcastToAdmins('jrs_mdt:client:chargesUpdated', { action = 'deleted', id = id, name = templateName })
        
        return { success = true }
    end
    
    return { success = false, message = locale('notification_failed_delete_charge') }
end)

JRS.Callback('jrs_mdt:server:issueCharges', function(source, data)
    if not hasCreateRecordsPermission(source) then
        return { success = false, message = locale('notification_issue_permission') }
    end
    
    local citizenid = data.citizenid
    local charges = data.charges
    local reportId = data.reportId
    
    if not citizenid or not charges or #charges == 0 then
        return { success = false, message = locale('notification_citizen_and_charge_required') }
    end
    
    local targetPlayer = MDTCore.GetPlayerByCitizenId(citizenid)
    local citizenName
    
    if targetPlayer then
        citizenName = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname
    else
        local result = MySQL.query.await("SELECT charinfo FROM jrs_mdt_players WHERE citizenid = ?", { citizenid })
        if result and result[1] then
            local charinfo = json.decode(result[1].charinfo)
            citizenName = charinfo.firstname .. ' ' .. charinfo.lastname
        else
            return { success = false, message = locale('notification_citizen_not_found') }
        end
    end
    
    local player = MDTCore.GetPlayer(source)
    if not player then
        return { success = false, message = locale('notification_officer_not_found') }
    end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    
    local totalFine = 0
    local totalJailtime = 0
    local issuedCharges = {}
    
    for _, charge in ipairs(charges) do
        local templateId = tonumber(charge.templateId)
        local chargeName = charge.name
        local chargeDescription = charge.description
        local fine = tonumber(charge.fine) or 0
        local jailtime = tonumber(charge.jailtime) or 0
        
        local insertId = MySQL.insert.await(
            "INSERT INTO mdt_issued_charges (citizenid, citizen_name, charge_template_id, charge_name, charge_description, fine, jailtime, officer, officer_cid, report_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            { citizenid, citizenName, templateId, chargeName, chargeDescription, fine, jailtime, officerName, officerCid, reportId }
        )
        
        if insertId then
            totalFine = totalFine + fine
            totalJailtime = totalJailtime + jailtime
            table.insert(issuedCharges, {
                id = insertId,
                name = chargeName,
                fine = fine,
                jailtime = jailtime
            })
        end
    end
    
    if #issuedCharges > 0 then
        local chargeIds = {}
        for _, issued in ipairs(issuedCharges) do
            table.insert(chargeIds, issued.id)
        end
        
        if totalFine > 0 then
            exports[GetCurrentResourceName()]:createOrUpdateFine(citizenid, citizenName, chargeIds, totalFine, officerName, officerCid)
        end
        
        logChargeAction(source, 'charges_issued', 'citizen', citizenid, citizenName, {
            charges = issuedCharges,
            totalFine = totalFine,
            totalJailtime = totalJailtime,
            reportId = reportId
        })
        
        if targetPlayer then
            local targetSource = targetPlayer.PlayerData.source
            TriggerClientEvent('jrs_mdt:client:notify', targetSource, {
                type = 'warning',
                message = locale('notification_charges_notification', #issuedCharges, totalFine, totalJailtime)
            })
        end
        
        broadcastToOfficers('jrs_mdt:client:chargesUpdated', { 
            action = 'issued', 
            citizenid = citizenid, 
            citizenName = citizenName,
            count = #issuedCharges 
        })
        
        return {
            success = true,
            message = locale('notification_charges_issued', #issuedCharges, citizenName),
            issuedCharges = issuedCharges,
            totalFine = totalFine,
            totalJailtime = totalJailtime,
            requiresJail = totalJailtime > 0 and targetPlayer ~= nil
        }
    end
    
    return { success = false, message = locale('notification_failed_issue_charges') }
end)

JRS.Callback('jrs_mdt:server:submitCharges', function(source, data)
    if not hasCreateRecordsPermission(source) then
        return { success = false, message = locale('notification_issue_permission') }
    end
    
    local citizenid = data.citizenid
    local targetPlayerId = data.targetPlayerId
    local charges = data.charges
    local attachedReportIds = data.attachedReportIds or {}
    
    if not citizenid or not charges or #charges == 0 then
        return { success = false, message = locale('notification_citizen_and_charge_required') }
    end
    
    local targetPlayer = targetPlayerId and MDTCore.GetPlayer(tonumber(targetPlayerId)) or nil
    local targetPlayerByCid = MDTCore.GetPlayerByCitizenId(citizenid)
    local citizenName
    
    if targetPlayer then
        citizenName = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname
    elseif targetPlayerByCid then
        citizenName = targetPlayerByCid.PlayerData.charinfo.firstname .. ' ' .. targetPlayerByCid.PlayerData.charinfo.lastname
        targetPlayer = targetPlayerByCid
    else
        local result = MySQL.query.await("SELECT charinfo FROM jrs_mdt_players WHERE citizenid = ?", { citizenid })
        if result and result[1] then
            local charinfo = json.decode(result[1].charinfo)
            citizenName = charinfo.firstname .. ' ' .. charinfo.lastname
        else
            return { success = false, message = locale('notification_citizen_not_found') }
        end
    end
    
    local player = MDTCore.GetPlayer(source)
    if not player then
        return { success = false, message = locale('notification_officer_not_found') }
    end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    
    local totalFine = 0
    local totalJailtime = 0
    local issuedCharges = {}
    local minutesPerMonth = Config.Jail.minutesPerMonth or 1
    
    for _, charge in ipairs(charges) do
        local templateId = tonumber(charge.templateId)
        local chargeName = charge.name
        local chargeDescription = charge.description
        local fine = tonumber(charge.fine) or 0
        local jailtimeMonths = tonumber(charge.jailtime) or 0
        
        local insertId = MySQL.insert.await(
            "INSERT INTO mdt_issued_charges (citizenid, citizen_name, charge_template_id, charge_name, charge_description, fine, jailtime, officer, officer_cid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            { citizenid, citizenName, templateId, chargeName, chargeDescription, fine, jailtimeMonths, officerName, officerCid }
        )
        
        if insertId then
            totalFine = totalFine + fine
            totalJailtime = totalJailtime + jailtimeMonths
            table.insert(issuedCharges, {
                id = insertId,
                name = chargeName,
                fine = fine,
                jailtime = jailtimeMonths
            })
        end
    end
    
    if #issuedCharges == 0 then
        return { success = false, message = locale('notification_failed_issue_charges') }
    end
    
    local chargeIds = {}
    for _, issued in ipairs(issuedCharges) do
        table.insert(chargeIds, issued.id)
    end
    
    if totalFine > 0 then
        exports[GetCurrentResourceName()]:createOrUpdateFine(citizenid, citizenName, chargeIds, totalFine, officerName, officerCid)
    end
    
    if #attachedReportIds > 0 and #chargeIds > 0 then
        local firstChargeId = chargeIds[1]
        for _, reportId in ipairs(attachedReportIds) do
            MySQL.insert.await(
                "INSERT INTO mdt_charge_attachments (charge_id, report_id, attached_by, attached_by_name) VALUES (?, ?, ?, ?)",
                { firstChargeId, reportId, officerCid, officerName }
            )
        end
    end
    
    local jailed = false
    local jailMinutes = 0
    
    if totalJailtime > 0 and targetPlayer then
        jailMinutes = totalJailtime * minutesPerMonth
        
        
        local targetSource = targetPlayer.PlayerData.source
        MDTJail(source, targetSource, jailMinutes)
        
        MySQL.update.await(
            "UPDATE mdt_issued_charges SET time_served = jailtime, is_served = 1 WHERE id IN (" .. table.concat(chargeIds, ",") .. ")"
        )
        
        for _, issued in ipairs(issuedCharges) do
            issued.time_served = issued.jailtime
            issued.is_served = true
        end
        
        jailed = true
        
        TriggerClientEvent('jrs_mdt:client:notify', targetSource, {
            type = 'warning',
            message = locale('notification_charges_committed_notification', #issuedCharges, jailMinutes)
        })
    end
    
    local updatedTotals = MySQL.query.await(
        "SELECT COALESCE(SUM(jailtime), 0) as total_jailtime, COALESCE(SUM(time_served), 0) as total_served FROM mdt_issued_charges WHERE citizenid = ?",
        { citizenid }
    )
    local totalsData = updatedTotals and updatedTotals[1] or { total_jailtime = 0, total_served = 0 }
    
    logChargeAction(source, jailed and 'charges_committed' or 'charges_issued', 'citizen', citizenid, citizenName, {
        charges = issuedCharges,
        totalFine = totalFine,
        totalJailtimeMonths = totalJailtime,
        jailMinutes = jailMinutes,
        minutesPerMonth = minutesPerMonth,
        jailed = jailed
    })
    
    broadcastToOfficers('jrs_mdt:client:chargesUpdated', { 
        action = jailed and 'committed' or 'issued', 
        citizenid = citizenid, 
        citizenName = citizenName,
        count = #issuedCharges,
        jailMinutes = jailMinutes,
        totalJailtime = tonumber(totalsData.total_jailtime) or 0,
        totalServed = tonumber(totalsData.total_served) or 0
    })
    
    local message
    if jailed then
        message = locale('notification_charges_comitted', #issuedCharges, citizenName, jailMinutes)
    else
        message = locale('notification_charges_issued', #issuedCharges, citizenName)
    end
    
    return {
        success = true,
        message = message,
        issuedCharges = issuedCharges,
        totalFine = totalFine,
        totalJailtime = tonumber(totalsData.total_jailtime) or 0,
        totalServed = tonumber(totalsData.total_served) or 0,
        jailMinutes = jailMinutes,
        minutesPerMonth = minutesPerMonth,
        jailed = jailed
    }
end)

JRS.Callback('jrs_mdt:server:getIssuedCharges', function(source, citizenid)
    if not citizenid or not selfOrLaw(source, citizenid) then return {} end
    
    local charges = MySQL.query.await(
        "SELECT id, citizenid, citizen_name, charge_template_id, charge_name, charge_description, fine, jailtime, time_served, is_served, officer, officer_cid, report_id, created_at, served_at FROM mdt_issued_charges WHERE citizenid = ? ORDER BY created_at DESC",
        { citizenid }
    )
    
    local finesResult = MySQL.query.await(
        "SELECT id, issued_charge_ids, due_date, status, paid_at FROM mdt_fines WHERE citizenid = ?",
        { citizenid }
    )
    
    local chargeIdToFine = {}
    for _, fine in ipairs(finesResult or {}) do
        if fine.issued_charge_ids and type(fine.issued_charge_ids) == 'string' then
            local chargeIds = json.decode(fine.issued_charge_ids)
            for _, chargeId in ipairs(chargeIds or {}) do
                chargeIdToFine[chargeId] = {
                    fine_id = fine.id,
                    due_date = fine.due_date,
                    fine_status = fine.status,
                    paid_at = fine.paid_at
                }
            end
        end
    end
    
    for _, charge in ipairs(charges or {}) do
        local fineInfo = chargeIdToFine[charge.id]
        if fineInfo then
            charge.fine_id = fineInfo.fine_id
            charge.due_date = fineInfo.due_date
            charge.fine_status = fineInfo.fine_status
            charge.paid_at = fineInfo.paid_at
        else
            charge.fine_id = nil
            charge.due_date = nil
            charge.fine_status = charge.fine and charge.fine > 0 and 'unpaid' or nil
            charge.paid_at = nil
        end
    end
    
    return charges or {}
end)

exports('getChargeTemplates', function()
    return MySQL.query.await("SELECT * FROM mdt_charge_templates ORDER BY category, name") or {}
end)

JRS.Callback('jrs_mdt:server:getAllIssuedCharges', function(source, searchQuery)
    if not hasCreateRecordsPermission(source) then
        return {}
    end
    
    local query
    local params = {}
    
    if searchQuery and #searchQuery > 0 then
        query = [[
            SELECT ic.*, 
                   CASE 
                       WHEN ic.charge_template_id IS NOT NULL THEN 
                           (SELECT category FROM mdt_charge_templates WHERE id = ic.charge_template_id)
                       ELSE 'misdemeanor'
                   END as category
            FROM mdt_issued_charges ic
            WHERE ic.citizenid LIKE ? 
               OR ic.citizen_name LIKE ? 
               OR ic.charge_name LIKE ? 
               OR ic.officer LIKE ?
               OR ic.id = ?
            ORDER BY ic.created_at DESC
            LIMIT 500
        ]]
        local searchPattern = '%' .. searchQuery .. '%'
        local searchId = tonumber(searchQuery) or 0
        params = { searchPattern, searchPattern, searchPattern, searchPattern, searchId }
    else
        query = [[
            SELECT ic.*,
                   CASE 
                       WHEN ic.charge_template_id IS NOT NULL THEN 
                           (SELECT category FROM mdt_charge_templates WHERE id = ic.charge_template_id)
                       ELSE 'misdemeanor'
                   END as category
            FROM mdt_issued_charges ic
            ORDER BY ic.created_at DESC
            LIMIT 500
        ]]
    end
    
    local charges = MySQL.query.await(query, params)
    return charges or {}
end)

JRS.Callback('jrs_mdt:server:getChargeDetails', function(source, chargeId)
    if not hasCreateRecordsPermission(source) then
        return nil
    end
    
    chargeId = tonumber(chargeId)
    if not chargeId then return nil end
    
    local charge = MySQL.query.await([[
        SELECT ic.*, ct.category
        FROM mdt_issued_charges ic
        LEFT JOIN mdt_charge_templates ct ON ic.charge_template_id = ct.id
        WHERE ic.id = ?
    ]], { chargeId })
    
    if charge and charge[1] then
        return charge[1]
    end
    
    return nil
end)

JRS.Callback('jrs_mdt:server:jailPlayer', function(source, data)
    if not hasCreateRecordsPermission(source) then
        return { success = false, message = locale('notification_jail_permission') }
    end
    
    local targetPlayer = MDTCore.GetPlayerByCitizenId(data.citizenid)
    if not targetPlayer then
        return { success = false, message = locale('notification_player_online_required') }
    end
    
    local targetSource = targetPlayer.PlayerData.source
    local minutes = tonumber(data.minutes) or 0
    
    if minutes <= 0 then
        return { success = false, message = locale('notification_invalid_jail_time') }
    end
    
    MDTJail(source, targetSource, minutes)
    
    local officer = MDTCore.GetPlayer(source)
    local officerName = officer and (officer.PlayerData.charinfo.firstname .. ' ' .. officer.PlayerData.charinfo.lastname) or 'Unknown'
    
    logChargeAction(source, 'player_jailed', 'citizen', data.citizenid, targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname, {
        minutes = minutes,
        reason = data.reason
    })
    
    return { success = true, message = locale('notification_player_jailed') }
end)

JRS.Callback('jrs_mdt:server:getJailConfig', function(source)
    return {
        delaySeconds = Config.Jail.delaySeconds,
        maxDistance = Config.Jail.maxDistance,
        jailCoords = Config.Jail.jailCoords,
        jailHeading = Config.Jail.jailHeading,
        enabled = Config.Jail.enabled,
        minutesPerMonth = Config.Jail.minutesPerMonth,
        maxJailDistance = Config.Jail.maxJailDistance
    }
end)

JRS.Callback('jrs_mdt:server:getCitizenJailTotals', function(source, citizenid)
    if not citizenid or not selfOrLaw(source, citizenid) then return { totalJailtime = 0, totalServed = 0, charges = {} } end
    
    local charges = MySQL.query.await(
        "SELECT id, charge_name, jailtime, time_served, is_served, created_at FROM mdt_issued_charges WHERE citizenid = ? ORDER BY created_at DESC",
        { citizenid }
    )
    
    local totalJailtime = 0
    local totalServed = 0
    local outstanding = 0
    
    for _, charge in ipairs(charges or {}) do
        totalJailtime = totalJailtime + (charge.jailtime or 0)
        totalServed = totalServed + (charge.time_served or 0)
        if not charge.is_served then
            outstanding = outstanding + ((charge.jailtime or 0) - (charge.time_served or 0))
        end
    end
    
    return {
        totalJailtime = totalJailtime,
        totalServed = totalServed,
        outstanding = outstanding,
        charges = charges or {}
    }
end)

JRS.Callback('jrs_mdt:server:commitCharges', function(source, data)
    if not hasCreateRecordsPermission(source) then
        return { success = false, message = locale('notification_issue_permission') }
    end
    
    local citizenid = data.citizenid
    local targetPlayerId = data.targetPlayerId
    local charges = data.charges
    local totalJailtimeMonths = tonumber(data.totalJailtime) or 0
    local attachedReportIds = data.attachedReportIds or {}
    
    if not citizenid or not charges or #charges == 0 then
        return { success = false, message = locale('notification_citizen_and_charge_required') }
    end
    
    if not targetPlayerId then
        return { success = false, message = locale('notification_player_online_required') }
    end
    
    if totalJailtimeMonths <= 0 then
        return { success = false, message = locale('notification_invalid_jail_time') }
    end
    
    local targetPlayer = MDTCore.GetPlayer(tonumber(targetPlayerId))
    if not targetPlayer then
        return { success = false, message = locale('notification_player_online_required') }
    end
    
    local targetSource = targetPlayer.PlayerData.source
    local citizenName = targetPlayer.PlayerData.charinfo.firstname .. ' ' .. targetPlayer.PlayerData.charinfo.lastname
    
    local player = MDTCore.GetPlayer(source)
    if not player then
        return { success = false, message = locale('notification_officer_not_found') }
    end
    
    local officerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    local officerCid = player.PlayerData.citizenid
    
    local totalFine = 0
    local issuedCharges = {}
    local minutesPerMonth = Config.Jail.minutesPerMonth or 1
    
    for _, charge in ipairs(charges) do
        local templateId = tonumber(charge.templateId)
        local chargeName = charge.name
        local chargeDescription = charge.description
        local fine = tonumber(charge.fine) or 0
        local jailtimeMonths = tonumber(charge.jailtime) or 0
        
        local insertId = MySQL.insert.await(
            "INSERT INTO mdt_issued_charges (citizenid, citizen_name, charge_template_id, charge_name, charge_description, fine, jailtime, time_served, is_served, officer, officer_cid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)",
            { citizenid, citizenName, templateId, chargeName, chargeDescription, fine, jailtimeMonths, jailtimeMonths, officerName, officerCid }
        )
        
        if insertId then
            totalFine = totalFine + fine
            table.insert(issuedCharges, {
                id = insertId,
                name = chargeName,
                fine = fine,
                jailtime = jailtimeMonths,
                time_served = jailtimeMonths,
                is_served = true
            })
        end
    end
    
    if #issuedCharges == 0 then
        return { success = false, message = locale('notification_failed_issue_charges') }
    end
    
    local chargeIds = {}
    for _, issued in ipairs(issuedCharges) do
        table.insert(chargeIds, issued.id)
    end
    
    if totalFine > 0 then
        exports[GetCurrentResourceName()]:createOrUpdateFine(citizenid, citizenName, chargeIds, totalFine, officerName, officerCid)
    end
    
    if #attachedReportIds > 0 and #chargeIds > 0 then
        local firstChargeId = chargeIds[1]
        for _, reportId in ipairs(attachedReportIds) do
            MySQL.insert.await(
                "INSERT INTO mdt_charge_attachments (charge_id, report_id, attached_by, attached_by_name) VALUES (?, ?, ?, ?)",
                { firstChargeId, reportId, officerCid, officerName }
            )
        end
    end
    
    local jailMinutes = totalJailtimeMonths * minutesPerMonth
    
    MDTJail(source, targetSource, jailMinutes)
    
    local updatedTotals = MySQL.query.await(
        "SELECT COALESCE(SUM(jailtime), 0) as total_jailtime, COALESCE(SUM(time_served), 0) as total_served FROM mdt_issued_charges WHERE citizenid = ?",
        { citizenid }
    )
    
    local totalsData = updatedTotals and updatedTotals[1] or { total_jailtime = 0, total_served = 0 }
    
    logChargeAction(source, 'charges_committed', 'citizen', citizenid, citizenName, {
        charges = issuedCharges,
        totalFine = totalFine,
        totalJailtimeMonths = totalJailtimeMonths,
        jailMinutes = jailMinutes,
        minutesPerMonth = minutesPerMonth
    })
    
    TriggerClientEvent('jrs_mdt:client:notify', targetSource, {
        type = 'warning',
        message = locale('notification_charges_committed_notification', #issuedCharges, jailMinutes)
    })
    
    broadcastToOfficers('jrs_mdt:client:chargesUpdated', { 
        action = 'committed', 
        citizenid = citizenid, 
        citizenName = citizenName,
        count = #issuedCharges,
        jailMinutes = jailMinutes,
        totalJailtime = tonumber(totalsData.total_jailtime) or 0,
        totalServed = tonumber(totalsData.total_served) or 0
    })
    
    return {
        success = true,
        message = locale('notification_charges_comitted', #issuedCharges, citizenName, jailMinutes),
        issuedCharges = issuedCharges,
        totalFine = totalFine,
        totalJailtime = tonumber(totalsData.total_jailtime) or 0,
        totalServed = tonumber(totalsData.total_served) or 0,
        jailMinutes = jailMinutes,
        minutesPerMonth = minutesPerMonth
    }
end)
