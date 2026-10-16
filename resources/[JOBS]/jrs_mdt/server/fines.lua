-- jrs_mdt | server: fines made out of issued charges, and paying them
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

local OPEN <const> = "('unpaid', 'overdue')"

local function dueDate()
    local days = Config.Fines and Config.Fines.gracePeriodDays or 7
    return os.date('!%Y-%m-%d %H:%M:%S', os.time() + days * 86400)
end

local function decodeCharges(fines)
    for _, fine in ipairs(fines or {}) do
        if type(fine.issued_charge_ids) == 'string' then fine.issued_charge_ids = json.decode(fine.issued_charge_ids) end
    end
    return fines or {}
end

-- A person has at most one open (unpaid) fine: new charges are added to it and the due date moves on.
function MDT.AddFine(citizenid, citizenName, chargeIds, amount, officer, officerCid)
    local open = MySQL.query.await("SELECT id, issued_charge_ids, total_amount FROM mdt_fines WHERE citizenid = ? AND status = 'unpaid'", { citizenid })
    open = open and open[1]

    if open then
        local ids = open.issued_charge_ids and json.decode(open.issued_charge_ids) or {}
        for _, id in ipairs(chargeIds) do ids[#ids + 1] = id end

        MySQL.update.await('UPDATE mdt_fines SET issued_charge_ids = ?, total_amount = ?, due_date = ? WHERE id = ?',
            { json.encode(ids), open.total_amount + amount, dueDate(), open.id })
        return open.id
    end

    return MySQL.insert.await(
        'INSERT INTO mdt_fines (citizenid, citizen_name, issued_charge_ids, total_amount, due_date, officer_name, officer_cid) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { citizenid, citizenName, json.encode(chargeIds), amount, dueDate(), officer, officerCid })
end

exports('createOrUpdateFine', MDT.AddFine)

local function citizenFines(citizenid)
    return MySQL.query.await('SELECT * FROM mdt_fines WHERE citizenid = ? ORDER BY issued_at DESC', { citizenid }) or {}
end

local function openFines(citizenid)
    return MySQL.query.await('SELECT * FROM mdt_fines WHERE citizenid = ? AND status IN ' .. OPEN .. ' ORDER BY due_date ASC', { citizenid }) or {}
end

exports('getCitizenFines', citizenFines)
exports('getUnpaidFines', openFines)

-- an unpaid fine becomes overdue once its date is past
CreateThread(function()
    while true do
        Wait(60000)
        MySQL.update.await("UPDATE mdt_fines SET status = 'overdue' WHERE status = 'unpaid' AND due_date < NOW()")
    end
end)

-- ------------------------------------------------------------------ officers looking at fines

JRS.Callback('jrs_mdt:server:getCitizenFines', function(src, citizenid)
    if not MDT.Can(src, 'canCreateRecords') then return {} end
    return decodeCharges(citizenFines(citizenid))
end)

JRS.Callback('jrs_mdt:server:getUnpaidFines', function(src, citizenid)
    if not citizenid or not MDT.SelfOrLaw(src, citizenid) then return {} end
    return decodeCharges(openFines(citizenid))
end)

JRS.Callback('jrs_mdt:server:getAllUnpaidFines', function(src)
    if not MDT.Can(src, 'canCreateRecords') then return {} end
    return decodeCharges(MySQL.query.await('SELECT * FROM mdt_fines WHERE status IN ' .. OPEN .. ' ORDER BY due_date ASC LIMIT 500'))
end)

JRS.Callback('jrs_mdt:server:getUnpaidFinesCount', function(src, citizenid)
    if not MDT.SelfOrLaw(src, citizenid) then return 0 end

    local sql = 'SELECT COUNT(*) AS count FROM mdt_fines WHERE status IN ' .. OPEN .. (citizenid and ' AND citizenid = ?' or '')
    local row = MySQL.query.await(sql, citizenid and { citizenid } or {})
    return row and row[1] and row[1].count or 0
end)

JRS.Callback('jrs_mdt:server:markFineOverdue', function(src, fineId)
    if not MDT.Can(src, 'canCreateRecords') then return MDT.Fail('notification_no_permission') end
    MySQL.update.await("UPDATE mdt_fines SET status = 'overdue' WHERE id = ? AND status = 'unpaid'", { fineId })
    return { success = true }
end)

-- an officer records that the fine was settled in person
JRS.Callback('jrs_mdt:server:markFinePaid', function(src, fineId)
    if not MDT.Can(src, 'canCreateRecords') then return MDT.Fail('notification_no_permission_mark_fines') end

    fineId = tonumber(fineId)
    if not fineId then return MDT.Fail('notification_invalid_fine_id') end

    local open = MySQL.query.await('SELECT * FROM mdt_fines WHERE id = ? AND status IN ' .. OPEN, { fineId })
    open = open and open[1]
    if not open then return MDT.Fail('notification_fine_not_found') end

    local officer, cid = MDT.Officer(src)
    officer, cid = officer or 'Unknown', cid or 'Unknown'

    MySQL.update.await("UPDATE mdt_fines SET status = 'paid', paid_at = ?, paid_to_officer = ? WHERE id = ?",
        { os.date('%Y-%m-%d %H:%M:%S'), officer, fineId })
    MySQL.insert.await(
        'INSERT INTO mdt_audit_logs (action, target_type, target_id, target_name, details, performed_by, performed_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { 'fine_marked_paid', 'fine', tostring(fineId), open.citizen_name, json.encode({ amount = open.total_amount, fine_id = fineId }), cid, officer })

    local fine = decodeCharges(MySQL.query.await('SELECT * FROM mdt_fines WHERE id = ?', { fineId }))[1]
    MDT.Broadcast('law', 'jrs_mdt:client:fineStatusUpdated', { fineId = fineId, citizenid = open.citizenid, status = 'paid', fine = fine })
    TriggerClientEvent('jrs_mdt:client:playerFinePaid', -1, { fineId = fineId, citizenid = open.citizenid })

    return { success = true, message = locale('notification_fine_marked_paid'), fine = fine }
end)

-- ------------------------------------------------------------------ the person paying

JRS.Callback('jrs_mdt:server:payFine', function(src, fineId)
    fineId = tonumber(fineId)
    if not fineId then return MDT.Fail('notification_invalid_fine_id') end

    local player = MDTCore.GetPlayer(src)
    if not player then return MDT.Fail('notification_player_not_found') end

    local citizenid = player.PlayerData.citizenid
    local row = MySQL.query.await('SELECT * FROM mdt_fines WHERE id = ? AND citizenid = ? AND status IN ' .. OPEN, { fineId, citizenid })
    local fine = row and row[1]
    if not fine then return MDT.Fail('notification_fine_not_found') end

    local owed = fine.total_amount
    local cash = player.PlayerData.money and player.PlayerData.money.cash or 0
    if cash < owed then return MDT.Fail('notification_insufficient_funds', owed) end

    -- the row is claimed first, so two quick requests cannot both pay
    local claimed = MySQL.update.await("UPDATE mdt_fines SET status = 'paid', paid_at = ? WHERE id = ? AND citizenid = ? AND status IN " .. OPEN,
        { os.date('%Y-%m-%d %H:%M:%S'), fineId, citizenid })
    if not claimed or claimed < 1 then return MDT.Fail('notification_fine_not_found') end

    if not player.Functions.RemoveMoney('cash', owed, 'mdt-fine-payment') then
        MySQL.update.await('UPDATE mdt_fines SET status = ?, paid_at = NULL WHERE id = ?', { fine.status, fineId })
        return MDT.Fail('notification_payment_failed')
    end

    local name = MDT.FullName(player)
    MySQL.insert.await(
        'INSERT INTO mdt_audit_logs (action, target_type, target_id, target_name, details, performed_by, performed_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { 'fine_paid', 'fine', tostring(fineId), name, json.encode({ amount = owed, fine_id = fineId }), citizenid, name })

    MDT.Broadcast('law', 'jrs_mdt:client:finePaid', { fineId = fineId, citizenid = citizenid, citizenName = name, amount = owed })
    TriggerClientEvent('jrs_mdt:client:finePaymentResult', src, { success = true, message = locale('notification_fine_paid_success', owed), fineId = fineId })
    return { success = true, message = locale('notification_fine_paid') }
end)

-- ------------------------------------------------------------------ your own fines

JRS.Callback('jrs_mdt:server:getPlayerFines', function(src)
    local player = MDTCore.GetPlayer(src)
    if not player then return {} end

    local fines = MySQL.query.await(
        'SELECT *, UNIX_TIMESTAMP(due_date) AS due_timestamp FROM mdt_fines WHERE citizenid = ? AND status IN ' .. OPEN .. ' ORDER BY due_date ASC',
        { player.PlayerData.citizenid })

    for _, fine in ipairs(decodeCharges(fines)) do fine.due_timestamp = fine.due_timestamp or os.time() + 604800 end
    return fines or {}
end)

JRS.Callback('jrs_mdt:server:hasUnpaidFines', function(src)
    local player = MDTCore.GetPlayer(src)
    if not player then return false end

    local row = MySQL.query.await('SELECT COUNT(*) AS count FROM mdt_fines WHERE citizenid = ? AND status IN ' .. OPEN, { player.PlayerData.citizenid })
    return row and row[1] and row[1].count > 0
end)

RegisterNetEvent('jrs_mdt:server:syncPlayerFines', function()
    local src = source
    local player = MDTCore.GetPlayer(src)
    if player then TriggerClientEvent('jrs_mdt:client:updatePlayerFines', src, openFines(player.PlayerData.citizenid)) end
end)
