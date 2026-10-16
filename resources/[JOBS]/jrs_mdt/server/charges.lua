-- jrs_mdt | server: charge templates, issuing charges and the jail time that follows
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local function adminOnly(name, handler)
    JRS.Callback(name, function(src, ...)
        if not MDT.Can(src, 'isAdmin') then return MDT.Fail('notification_charge_permission') end
        return handler(src, ...)
    end)
end

-- ------------------------------------------------------------------ templates (the list of known charges)

local function allTemplates() return MySQL.query.await('SELECT * FROM mdt_charge_templates ORDER BY category, name') or {} end

JRS.Callback('jrs_mdt:server:getChargeTemplates', function(src)
    if not MDTCore.GetPlayer(src) then return {} end
    return allTemplates()
end)

exports('getChargeTemplates', allTemplates)

adminOnly('jrs_mdt:server:addChargeTemplate', function(src, data)
    local name = data.name
    if not name or #name < 2 then return MDT.Fail('notification_charge_name_required') end

    local existing = MySQL.query.await('SELECT id FROM mdt_charge_templates WHERE name = ?', { name })
    if existing and existing[1] then return MDT.Fail('notification_charge_exists') end

    local fine, jail, category = tonumber(data.fine) or 0, tonumber(data.jailtime) or 0, data.category or 'misdemeanor'
    local officer, cid = MDT.Officer(src)

    local id = MySQL.insert.await(
        'INSERT INTO mdt_charge_templates (name, description, fine, jailtime, category, created_by, created_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { name, data.description or '', fine, jail, category, cid, officer or 'System' })
    if not id then return MDT.Fail('notification_failed_create_charge') end

    MDT.Audit(src, 'charge_template_created', 'charge_template', tostring(id), name, { name = name, fine = fine, jailtime = jail, category = category })
    MDT.Broadcast('admin', 'jrs_mdt:client:chargesUpdated', { action = 'created', id = id, name = name })
    return { success = true, id = id }
end)

adminOnly('jrs_mdt:server:updateChargeTemplate', function(src, data)
    local id = tonumber(data.id)
    if not id then return MDT.Fail('notification_charge_id_required') end

    local old = MySQL.query.await('SELECT name FROM mdt_charge_templates WHERE id = ?', { id })
    if not (old and old[1]) then return MDT.Fail('notification_charge_not_found') end

    local fine, jail = tonumber(data.fine), tonumber(data.jailtime)
    if not MySQL.update.await('UPDATE mdt_charge_templates SET name = ?, description = ?, fine = ?, jailtime = ?, category = ? WHERE id = ?',
        { data.name, data.description, fine, jail, data.category, id }) then
        return MDT.Fail('notification_failed_update_charge')
    end

    MDT.Audit(src, 'charge_template_updated', 'charge_template', tostring(id), old[1].name,
        { oldName = old[1].name, newName = data.name, fine = fine, jailtime = jail, category = data.category })
    MDT.Broadcast('admin', 'jrs_mdt:client:chargesUpdated', { action = 'updated', id = id, name = data.name })
    return { success = true }
end)

adminOnly('jrs_mdt:server:deleteChargeTemplate', function(src, id)
    id = tonumber(id)
    if not id then return MDT.Fail('notification_charge_id_required') end

    local row = MySQL.query.await('SELECT name FROM mdt_charge_templates WHERE id = ?', { id })
    if not (row and row[1]) then return MDT.Fail('notification_charge_not_found') end

    local removed = MySQL.update.await('DELETE FROM mdt_charge_templates WHERE id = ?', { id })
    if not (removed and removed > 0) then return MDT.Fail('notification_failed_delete_charge') end

    MDT.Audit(src, 'charge_template_deleted', 'charge_template', tostring(id), row[1].name)
    MDT.Broadcast('admin', 'jrs_mdt:client:chargesUpdated', { action = 'deleted', id = id, name = row[1].name })
    return { success = true }
end)

-- ------------------------------------------------------------------ issuing

-- how many jail minutes one month of a sentence is worth
local function minutesPerMonth() return Config.Jail.minutesPerMonth or 1 end

local function jailTotals(citizenid)
    local row = MySQL.query.await(
        'SELECT COALESCE(SUM(jailtime), 0) AS total_jailtime, COALESCE(SUM(time_served), 0) AS total_served FROM mdt_issued_charges WHERE citizenid = ?',
        { citizenid })
    row = row and row[1] or {}
    return tonumber(row.total_jailtime) or 0, tonumber(row.total_served) or 0
end

-- writes the charges; `served` marks them as already served (the sentence is carried out right now)
local function writeCharges(officer, officerCid, citizenid, citizenName, charges, reportId, served)
    local issued, fine, jail = {}, 0, 0
    for _, charge in ipairs(charges) do
        local owed, months = tonumber(charge.fine) or 0, tonumber(charge.jailtime) or 0
        local id = MySQL.insert.await(
            'INSERT INTO mdt_issued_charges (citizenid, citizen_name, charge_template_id, charge_name, charge_description, fine, jailtime, time_served, is_served, officer, officer_cid, report_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { citizenid, citizenName, tonumber(charge.templateId), charge.name, charge.description, owed, months,
              served and months or 0, served and 1 or 0, officer, officerCid, reportId })

        if id then
            fine, jail = fine + owed, jail + months
            issued[#issued + 1] = { id = id, name = charge.name, fine = owed, jailtime = months, time_served = served and months or nil, is_served = served or nil }
        end
    end
    return issued, fine, jail
end

local function idsOf(issued)
    local ids = {}
    for i, charge in ipairs(issued) do ids[i] = charge.id end
    return ids
end

-- the first issued charge carries the reports attached while issuing
local function attachReports(chargeId, reportIds, officerCid, officer)
    for _, reportId in ipairs(reportIds) do
        MySQL.insert.await('INSERT INTO mdt_charge_attachments (charge_id, report_id, attached_by, attached_by_name) VALUES (?, ?, ?, ?)',
            { chargeId, reportId, officerCid, officer })
    end
end

JRS.Callback('jrs_mdt:server:issueCharges', function(src, data)
    if not MDT.Can(src, 'canCreateRecords') then return MDT.Fail('notification_issue_permission') end
    if not data.citizenid or not data.charges or #data.charges == 0 then return MDT.Fail('notification_citizen_and_charge_required') end

    local citizenName, target = MDT.NameOf(data.citizenid)
    if not citizenName then return MDT.Fail('notification_citizen_not_found') end

    local officer, cid = MDT.Officer(src)
    if not officer then return MDT.Fail('notification_officer_not_found') end

    local issued, fine, jail = writeCharges(officer, cid, data.citizenid, citizenName, data.charges, data.reportId, false)
    if #issued == 0 then return MDT.Fail('notification_failed_issue_charges') end

    if fine > 0 then MDT.AddFine(data.citizenid, citizenName, idsOf(issued), fine, officer, cid) end

    MDT.Audit(src, 'charges_issued', 'citizen', data.citizenid, citizenName,
        { charges = issued, totalFine = fine, totalJailtime = jail, reportId = data.reportId })
    if target then
        TriggerClientEvent('jrs_mdt:client:notify', target.PlayerData.source,
            { type = 'warning', message = locale('notification_charges_notification', #issued, fine, jail) })
    end
    MDT.Broadcast('law', 'jrs_mdt:client:chargesUpdated', { action = 'issued', citizenid = data.citizenid, citizenName = citizenName, count = #issued })

    return {
        success = true, message = locale('notification_charges_issued', #issued, citizenName), issuedCharges = issued,
        totalFine = fine, totalJailtime = jail, requiresJail = jail > 0 and target ~= nil,
    }
end)

-- Writes charges and, when the sentence has to be served now, sends the person to jail.
-- mode 'submit': jail only if there is time to serve and the person is online.
-- mode 'commit': the person must be online and the sentence is always carried out.
local function processCharges(src, data, mode)
    if not MDT.Can(src, 'canCreateRecords') then return MDT.Fail('notification_issue_permission') end

    local citizenid, charges = data.citizenid, data.charges
    if not citizenid or not charges or #charges == 0 then return MDT.Fail('notification_citizen_and_charge_required') end

    local target = data.targetPlayerId and MDTCore.GetPlayer(tonumber(data.targetPlayerId)) or nil
    local months = tonumber(data.totalJailtime) or 0

    if mode == 'commit' then
        if not data.targetPlayerId or not target then return MDT.Fail('notification_player_online_required') end
        if months <= 0 then return MDT.Fail('notification_invalid_jail_time') end
    else
        target = target or MDTCore.GetPlayerByCitizenId(citizenid)
        months = 0
        for _, charge in ipairs(charges) do months = months + (tonumber(charge.jailtime) or 0) end
    end

    local citizenName = target and MDT.FullName(target) or MDT.NameOf(citizenid)
    if not citizenName then return MDT.Fail('notification_citizen_not_found') end

    local officer, cid = MDT.Officer(src)
    if not officer then return MDT.Fail('notification_officer_not_found') end

    local jailing = target ~= nil and months > 0
    local issued, fine = writeCharges(officer, cid, citizenid, citizenName, charges, nil, jailing)
    if #issued == 0 then return MDT.Fail('notification_failed_issue_charges') end

    local ids = idsOf(issued)
    if fine > 0 then MDT.AddFine(citizenid, citizenName, ids, fine, officer, cid) end
    if #(data.attachedReportIds or {}) > 0 then attachReports(ids[1], data.attachedReportIds, cid, officer) end

    local minutes = 0
    if jailing then
        minutes = months * minutesPerMonth()
        MDTJail(src, target.PlayerData.source, minutes)
        TriggerClientEvent('jrs_mdt:client:notify', target.PlayerData.source,
            { type = 'warning', message = locale('notification_charges_committed_notification', #issued, minutes) })
    end

    local total, served = jailTotals(citizenid)
    MDT.Audit(src, jailing and 'charges_committed' or 'charges_issued', 'citizen', citizenid, citizenName, {
        charges = issued, totalFine = fine, totalJailtimeMonths = months, jailMinutes = minutes,
        minutesPerMonth = minutesPerMonth(), jailed = jailing,
    })
    MDT.Broadcast('law', 'jrs_mdt:client:chargesUpdated', {
        action = jailing and 'committed' or 'issued', citizenid = citizenid, citizenName = citizenName, count = #issued,
        jailMinutes = minutes, totalJailtime = total, totalServed = served,
    })

    return {
        success = true,
        message = jailing and locale('notification_charges_comitted', #issued, citizenName, minutes) or locale('notification_charges_issued', #issued, citizenName),
        issuedCharges = issued, totalFine = fine, totalJailtime = total, totalServed = served,
        jailMinutes = minutes, minutesPerMonth = minutesPerMonth(), jailed = jailing,
    }
end

JRS.Callback('jrs_mdt:server:submitCharges', function(src, data) return processCharges(src, data, 'submit') end)
JRS.Callback('jrs_mdt:server:commitCharges', function(src, data) return processCharges(src, data, 'commit') end)

-- ------------------------------------------------------------------ reading the issued charges

JRS.Callback('jrs_mdt:server:getIssuedCharges', function(src, citizenid)
    if not citizenid or not MDT.SelfOrLaw(src, citizenid) then return {} end

    local charges = MySQL.query.await(
        'SELECT id, citizenid, citizen_name, charge_template_id, charge_name, charge_description, fine, jailtime, time_served, is_served, officer, officer_cid, report_id, created_at, served_at FROM mdt_issued_charges WHERE citizenid = ? ORDER BY created_at DESC',
        { citizenid }) or {}

    -- which fine (and what state it is in) covers each charge
    local fineOf = {}
    for _, fine in ipairs(MySQL.query.await('SELECT id, issued_charge_ids, due_date, status, paid_at FROM mdt_fines WHERE citizenid = ?', { citizenid }) or {}) do
        if type(fine.issued_charge_ids) == 'string' then
            for _, chargeId in ipairs(json.decode(fine.issued_charge_ids) or {}) do
                fineOf[chargeId] = { fine_id = fine.id, due_date = fine.due_date, fine_status = fine.status, paid_at = fine.paid_at }
            end
        end
    end

    for _, charge in ipairs(charges) do
        local covered = fineOf[charge.id]
        if covered then
            charge.fine_id, charge.due_date, charge.fine_status, charge.paid_at = covered.fine_id, covered.due_date, covered.fine_status, covered.paid_at
        else
            charge.fine_status = charge.fine and charge.fine > 0 and 'unpaid' or nil
        end
    end
    return charges
end)

JRS.Callback('jrs_mdt:server:getAllIssuedCharges', function(src, search)
    if not MDT.Can(src, 'canCreateRecords') then return {} end

    local sql = [[
        SELECT ic.*, COALESCE((SELECT category FROM mdt_charge_templates WHERE id = ic.charge_template_id), 'misdemeanor') AS category
        FROM mdt_issued_charges ic
    ]]
    local args = {}

    if search and #search > 0 then
        sql = sql .. ' WHERE ic.citizenid LIKE ? OR ic.citizen_name LIKE ? OR ic.charge_name LIKE ? OR ic.officer LIKE ? OR ic.id = ?'
        local pattern = '%' .. search .. '%'
        args = { pattern, pattern, pattern, pattern, tonumber(search) or 0 }
    end

    return MySQL.query.await(sql .. ' ORDER BY ic.created_at DESC LIMIT 500', args) or {}
end)

JRS.Callback('jrs_mdt:server:getChargeDetails', function(src, chargeId)
    chargeId = tonumber(chargeId)
    if not chargeId or not MDT.Can(src, 'canCreateRecords') then return nil end

    local row = MySQL.query.await([[
        SELECT ic.*, ct.category
        FROM mdt_issued_charges ic
        LEFT JOIN mdt_charge_templates ct ON ic.charge_template_id = ct.id
        WHERE ic.id = ?
    ]], { chargeId })
    return row and row[1] or nil
end)

-- ------------------------------------------------------------------ jail

JRS.Callback('jrs_mdt:server:jailPlayer', function(src, data)
    if not MDT.Can(src, 'canCreateRecords') then return MDT.Fail('notification_jail_permission') end

    local target = MDTCore.GetPlayerByCitizenId(data.citizenid)
    if not target then return MDT.Fail('notification_player_online_required') end

    local minutes = tonumber(data.minutes) or 0
    if minutes <= 0 then return MDT.Fail('notification_invalid_jail_time') end

    MDTJail(src, target.PlayerData.source, minutes)
    MDT.Audit(src, 'player_jailed', 'citizen', data.citizenid, MDT.FullName(target), { minutes = minutes, reason = data.reason })
    return { success = true, message = locale('notification_player_jailed') }
end)

JRS.Callback('jrs_mdt:server:getJailConfig', function()
    local jail = Config.Jail
    return {
        delaySeconds = jail.delaySeconds, maxDistance = jail.maxDistance, jailCoords = jail.jailCoords, jailHeading = jail.jailHeading,
        enabled = jail.enabled, minutesPerMonth = jail.minutesPerMonth, maxJailDistance = jail.maxJailDistance,
    }
end)

JRS.Callback('jrs_mdt:server:getCitizenJailTotals', function(src, citizenid)
    if not citizenid or not MDT.SelfOrLaw(src, citizenid) then return { totalJailtime = 0, totalServed = 0, charges = {} } end

    local charges = MySQL.query.await(
        'SELECT id, charge_name, jailtime, time_served, is_served, created_at FROM mdt_issued_charges WHERE citizenid = ? ORDER BY created_at DESC',
        { citizenid }) or {}

    local total, served, outstanding = 0, 0, 0
    for _, charge in ipairs(charges) do
        total, served = total + (charge.jailtime or 0), served + (charge.time_served or 0)
        if not charge.is_served then outstanding = outstanding + (charge.jailtime or 0) - (charge.time_served or 0) end
    end
    return { totalJailtime = total, totalServed = served, outstanding = outstanding, charges = charges }
end)
