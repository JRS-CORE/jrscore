-- jrs_mdt | server: attaching reports to issued charges
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local function audit(src, action, chargeId, reportId, details)
    MDT.Audit(src, action, 'charge_attachment', tostring(chargeId), 'Charge #' .. chargeId .. ' - Report #' .. reportId, details)
end

-- a callback for officers who may write records
local function writerCallback(name, fallback, handler)
    JRS.Callback(name, function(src, ...)
        if not MDT.Can(src, 'canCreateRecords') then return fallback end
        return handler(src, ...)
    end)
end

writerCallback('jrs_mdt:server:getAvailableReportsForAttachment', {}, function(_, search)
    local sql = 'SELECT id, title, type, officer, created_at FROM mdt_reports'
    local args = {}

    if search and #search > 0 then
        sql = sql .. ' WHERE title LIKE ? OR officer LIKE ? OR type LIKE ?'
        local pattern = '%' .. search .. '%'
        args = { pattern, pattern, pattern }
    end
    return MySQL.query.await(sql .. ' ORDER BY created_at DESC LIMIT 50', args) or {}
end)

-- the sentence the officer sees after attaching, from what happened to each report
local function summary(attached, already, missing)
    if attached > 0 and already > 0 and missing > 0 then return locale('notification_attach_success_notfound', attached, already, missing) end
    if attached > 0 and already > 0 then return locale('notification_attach_success_some', attached, already) end
    if attached > 0 then return locale('notification_attach_success', attached) end
    if already > 0 then return locale('notification_attach_already') end
    return locale('notification_attach_none')
end

writerCallback('jrs_mdt:server:attachReportsToCharge', MDT.Fail('notification_attach_permission'), function(src, data)
    local chargeId, reportIds = tonumber(data.chargeId), data.reportIds
    if not chargeId or not reportIds or #reportIds == 0 then return MDT.Fail('notification_charge_report_required') end

    local charge = MySQL.query.await('SELECT id FROM mdt_issued_charges WHERE id = ?', { chargeId })
    if not (charge and charge[1]) then return MDT.Fail('notification_charge_not_found_attach') end

    local officer, cid = MDT.Officer(src)
    if not officer then return MDT.Fail('notification_player_not_found') end

    local attached, already, missing = 0, 0, 0
    for _, raw in ipairs(reportIds) do
        local reportId = tonumber(raw)
        if reportId then
            local report = MySQL.query.await('SELECT id FROM mdt_reports WHERE id = ?', { reportId })
            if not (report and report[1]) then
                missing = missing + 1
            else
                local link = MySQL.query.await('SELECT id FROM mdt_charge_attachments WHERE charge_id = ? AND report_id = ?', { chargeId, reportId })
                if link and link[1] then
                    already = already + 1
                elseif MySQL.insert.await('INSERT INTO mdt_charge_attachments (charge_id, report_id, attached_by, attached_by_name) VALUES (?, ?, ?, ?)',
                    { chargeId, reportId, cid, officer }) then
                    attached = attached + 1
                    audit(src, 'report_attached', chargeId, reportId, { attachedBy = officer })
                end
            end
        end
    end

    return { success = attached > 0, message = summary(attached, already, missing), attachedCount = attached, alreadyAttached = already, notFound = missing }
end)

writerCallback('jrs_mdt:server:removeAttachmentFromCharge', MDT.Fail('notification_remove_attach_permission'), function(src, data)
    local chargeId, reportId = tonumber(data.chargeId), tonumber(data.reportId)
    if not chargeId or not reportId then return MDT.Fail('notification_charge_report_id_required') end

    local removed = MySQL.update.await('DELETE FROM mdt_charge_attachments WHERE charge_id = ? AND report_id = ?', { chargeId, reportId })
    if removed and removed > 0 then
        audit(src, 'report_detached', chargeId, reportId)
        return { success = true, message = locale('notification_report_detached') }
    end
    return MDT.Fail('notification_attachment_not_found')
end)

local ATTACHMENTS_OF_CHARGE <const> = [[
    SELECT ca.id AS attachment_id, ca.charge_id, ca.report_id, ca.attached_by, ca.attached_by_name, ca.attached_at,
           r.title AS report_title, r.type AS report_type, r.officer AS report_officer, r.created_at AS report_created_at
    FROM mdt_charge_attachments ca
    INNER JOIN mdt_reports r ON ca.report_id = r.id
    WHERE ca.charge_id = ?
    ORDER BY ca.attached_at DESC
]]

local CHARGES_OF_REPORT <const> = [[
    SELECT ca.id AS attachment_id, ca.charge_id, ca.report_id, ca.attached_at,
           ic.charge_name, ic.citizen_name, ic.fine, ic.jailtime, ic.officer
    FROM mdt_charge_attachments ca
    INNER JOIN mdt_issued_charges ic ON ca.charge_id = ic.id
    WHERE ca.report_id = ?
    ORDER BY ca.attached_at DESC
]]

writerCallback('jrs_mdt:server:getChargeAttachments', {}, function(_, chargeId)
    chargeId = tonumber(chargeId)
    return chargeId and MySQL.query.await(ATTACHMENTS_OF_CHARGE, { chargeId }) or {}
end)

writerCallback('jrs_mdt:server:getReportsWithCharges', {}, function(_, reportId)
    reportId = tonumber(reportId)
    return reportId and MySQL.query.await(CHARGES_OF_REPORT, { reportId }) or {}
end)

exports('getChargeAttachments', function(chargeId)
    chargeId = tonumber(chargeId)
    return chargeId and MySQL.query.await(ATTACHMENTS_OF_CHARGE, { chargeId }) or {}
end)

exports('getReportsWithCharges', function(reportId)
    reportId = tonumber(reportId)
    return reportId and MySQL.query.await(CHARGES_OF_REPORT, { reportId }) or {}
end)
