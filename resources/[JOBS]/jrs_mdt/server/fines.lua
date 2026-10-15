
local function getGracePeriodDays()
    return Config.Fines and Config.Fines.gracePeriodDays or 7
end

local function calculateDueDate()
    local graceDays = getGracePeriodDays()
    return os.date('!%Y-%m-%d %H:%M:%S', os.time() + (graceDays * 24 * 60 * 60))
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

local function createOrUpdateFine(citizenid, citizenName, chargeIds, totalAmount, officerName, officerCid)
    local existingFine = MySQL.query.await(
        "SELECT id, issued_charge_ids, total_amount FROM mdt_fines WHERE citizenid = ? AND status = 'unpaid'",
        { citizenid }
    )

    if existingFine and existingFine[1] then
        local fine = existingFine[1]
        local existingChargeIds = fine.issued_charge_ids and json.decode(fine.issued_charge_ids) or {}
        local newChargeIds = existingChargeIds

        for _, cid in ipairs(chargeIds) do
            table.insert(newChargeIds, cid)
        end

        local newTotal = fine.total_amount + totalAmount
        local newDueDate = calculateDueDate()

        MySQL.update.await(
            "UPDATE mdt_fines SET issued_charge_ids = ?, total_amount = ?, due_date = ? WHERE id = ?",
            { json.encode(newChargeIds), newTotal, newDueDate, fine.id }
        )

        return fine.id
    else
        local dueDate = calculateDueDate()
        local insertId = MySQL.insert.await(
            "INSERT INTO mdt_fines (citizenid, citizen_name, issued_charge_ids, total_amount, due_date, officer_name, officer_cid) VALUES (?, ?, ?, ?, ?, ?, ?)",
            { citizenid, citizenName, json.encode(chargeIds), totalAmount, dueDate, officerName, officerCid }
        )

        return insertId
    end
end

exports('createOrUpdateFine', createOrUpdateFine)

local function getCitizenFines(citizenid)
    local fines = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE citizenid = ? ORDER BY issued_at DESC",
        { citizenid }
    )

    return fines or {}
end

exports('getCitizenFines', getCitizenFines)

local function getUnpaidFines(citizenid)
    local fines = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE citizenid = ? AND status IN ('unpaid', 'overdue') ORDER BY due_date ASC",
        { citizenid }
    )

    return fines or {}
end

exports('getUnpaidFines', getUnpaidFines)

local function checkOverdueFines()
    MySQL.update.await(
        "UPDATE mdt_fines SET status = 'overdue' WHERE status = 'unpaid' AND due_date < NOW()"
    )
end

CreateThread(function()
    while true do
        Wait(60000)
        checkOverdueFines()
    end
end)

JRS.Callback('jrs_mdt:server:getCitizenFines', function(source, citizenid)
    if not hasCreateRecordsPermission(source) then return {} end

    local fines = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE citizenid = ? ORDER BY issued_at DESC",
        { citizenid }
    )

    for _, fine in ipairs(fines or {}) do
        if fine.issued_charge_ids and type(fine.issued_charge_ids) == 'string' then
            fine.issued_charge_ids = json.decode(fine.issued_charge_ids)
        end
    end

    return fines or {}
end)

JRS.Callback('jrs_mdt:server:getUnpaidFines', function(source, citizenid)
    if not citizenid or not selfOrLaw(source, citizenid) then return {} end
    local fines = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE citizenid = ? AND status IN ('unpaid', 'overdue') ORDER BY due_date ASC",
        { citizenid }
    )

    for _, fine in ipairs(fines or {}) do
        if fine.issued_charge_ids and type(fine.issued_charge_ids) == 'string' then
            fine.issued_charge_ids = json.decode(fine.issued_charge_ids)
        end
    end

    return fines or {}
end)

JRS.Callback('jrs_mdt:server:payFine', function(source, fineId)
    fineId = tonumber(fineId)
    if not fineId then
        return { success = false, message = locale('notification_invalid_fine_id') }
    end

    local player = MDTCore.GetPlayer(source)
    if not player then
        return { success = false, message = locale('notification_player_not_found') }
    end

    local citizenid = player.PlayerData.citizenid

    local fine = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE id = ? AND citizenid = ? AND status IN ('unpaid', 'overdue')",
        { fineId, citizenid }
    )

    if not fine or not fine[1] then
        return { success = false, message = locale('notification_fine_not_found') }
    end

    local fineData = fine[1]
    local totalAmount = fineData.total_amount

    local playerMoney = player.PlayerData.money
    local cashBalance = playerMoney and playerMoney.cash or 0

    if cashBalance < totalAmount then
        return { success = false, message = locale('notification_insufficient_funds', totalAmount) }
    end

    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local claimed = MySQL.update.await(
        "UPDATE mdt_fines SET status = 'paid', paid_at = ? WHERE id = ? AND citizenid = ? AND status IN ('unpaid', 'overdue')",
        { timestamp, fineId, citizenid }
    )
    if not claimed or claimed < 1 then
        return { success = false, message = locale('notification_fine_not_found') }
    end

    local removed = player.Functions.RemoveMoney('cash', totalAmount, 'mdt-fine-payment')
    if not removed then
        MySQL.update.await("UPDATE mdt_fines SET status = ?, paid_at = NULL WHERE id = ?", { fineData.status, fineId })
        return { success = false, message = locale('notification_payment_failed') }
    end

    local playerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname

    MySQL.insert.await(
        "INSERT INTO mdt_audit_logs (action, target_type, target_id, target_name, details, performed_by, performed_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
        { 'fine_paid', 'fine', tostring(fineId), playerName, json.encode({ amount = totalAmount, fine_id = fineId }), citizenid, playerName }
    )

    broadcastToOfficers('jrs_mdt:client:finePaid', {
        fineId = fineId,
        citizenid = citizenid,
        citizenName = playerName,
        amount = totalAmount
    })

    TriggerClientEvent('jrs_mdt:client:finePaymentResult', source, {
        success = true,
        message = locale('notification_fine_paid_success', totalAmount),
        fineId = fineId
    })

    return { success = true, message = locale('notification_fine_paid') }
end)

JRS.Callback('jrs_mdt:server:getPlayerFines', function(source)
    local player = MDTCore.GetPlayer(source)
    if not player then return {} end

    local citizenid = player.PlayerData.citizenid

    local fines = MySQL.query.await(
        "SELECT *, UNIX_TIMESTAMP(due_date) as due_timestamp FROM mdt_fines WHERE citizenid = ? AND status IN ('unpaid', 'overdue') ORDER BY due_date ASC",
        { citizenid }
    )

    for _, fine in ipairs(fines or {}) do
        if fine.issued_charge_ids and type(fine.issued_charge_ids) == 'string' then
            fine.issued_charge_ids = json.decode(fine.issued_charge_ids)
        end
        fine.due_timestamp = fine.due_timestamp or os.time() + 604800
    end

    return fines or {}
end)

JRS.Callback('jrs_mdt:server:hasUnpaidFines', function(source)
    local player = MDTCore.GetPlayer(source)
    if not player then return false end

    local result = MySQL.query.await(
        "SELECT COUNT(*) as count FROM mdt_fines WHERE citizenid = ? AND status IN ('unpaid', 'overdue')",
        { player.PlayerData.citizenid }
    )

    return result and result[1] and result[1].count > 0
end)

JRS.Callback('jrs_mdt:server:getUnpaidFinesCount', function(source, citizenid)
    if not selfOrLaw(source, citizenid) then return 0 end
    local query = citizenid 
        and "SELECT COUNT(*) as count FROM mdt_fines WHERE citizenid = ? AND status IN ('unpaid', 'overdue')"
        or "SELECT COUNT(*) as count FROM mdt_fines WHERE status IN ('unpaid', 'overdue')"

    local params = citizenid and { citizenid } or {}
    local result = MySQL.query.await(query, params)

    return result and result[1] and result[1].count or 0
end)

JRS.Callback('jrs_mdt:server:getAllUnpaidFines', function(source)
    if not hasCreateRecordsPermission(source) then return {} end

    local fines = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE status IN ('unpaid', 'overdue') ORDER BY due_date ASC LIMIT 500"
    )

    for _, fine in ipairs(fines or {}) do
        if fine.issued_charge_ids and type(fine.issued_charge_ids) == 'string' then
            fine.issued_charge_ids = json.decode(fine.issued_charge_ids)
        end
    end

    return fines or {}
end)

JRS.Callback('jrs_mdt:server:markFineOverdue', function(source, fineId)
    if not hasCreateRecordsPermission(source) then 
        return { success = false, message = locale('notification_no_permission') }
    end

    MySQL.update.await(
        "UPDATE mdt_fines SET status = 'overdue' WHERE id = ? AND status = 'unpaid'",
        { fineId }
    )

    return { success = true }
end)

JRS.Callback('jrs_mdt:server:markFinePaid', function(source, fineId)
    if not hasCreateRecordsPermission(source) then
        return { success = false, message = locale('notification_no_permission_mark_fines') }
    end

    fineId = tonumber(fineId)
    if not fineId then
        return { success = false, message = locale('notification_invalid_fine_id') }
    end

    local fine = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE id = ? AND status IN ('unpaid', 'overdue')",
        { fineId }
    )

    if not fine or not fine[1] then
        return { success = false, message = locale('notification_fine_not_found') }
    end

    local fineData = fine[1]

    local player = MDTCore.GetPlayer(source)
    local officerName = player and (player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname) or 'Unknown'
    local officerCid = player and player.PlayerData.citizenid or 'Unknown'

    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    MySQL.update.await(
        "UPDATE mdt_fines SET status = 'paid', paid_at = ?, paid_to_officer = ? WHERE id = ?",
        { timestamp, officerName, fineId }
    )

    MySQL.insert.await(
        "INSERT INTO mdt_audit_logs (action, target_type, target_id, target_name, details, performed_by, performed_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)",
        { 'fine_marked_paid', 'fine', tostring(fineId), fineData.citizen_name, json.encode({ amount = fineData.total_amount, fine_id = fineId }), officerCid, officerName }
    )

    local updatedFine = MySQL.query.await(
        "SELECT * FROM mdt_fines WHERE id = ?",
        { fineId }
    )

    local fineResult = updatedFine and updatedFine[1]
    if fineResult and fineResult.issued_charge_ids and type(fineResult.issued_charge_ids) == 'string' then
        fineResult.issued_charge_ids = json.decode(fineResult.issued_charge_ids)
    end

    broadcastToOfficers('jrs_mdt:client:fineStatusUpdated', {
        fineId = fineId,
        citizenid = fineData.citizenid,
        status = 'paid',
        fine = fineResult
    })

    TriggerClientEvent('jrs_mdt:client:playerFinePaid', -1, {
        fineId = fineId,
        citizenid = fineData.citizenid
    })

    return { 
        success = true, 
        message = locale('notification_fine_marked_paid'),
        fine = fineResult
    }
end)

RegisterNetEvent('jrs_mdt:server:syncPlayerFines', function()
    local source = source
    local player = MDTCore.GetPlayer(source)
    if not player then return end

    local fines = getUnpaidFines(player.PlayerData.citizenid)

    TriggerClientEvent('jrs_mdt:client:updatePlayerFines', source, fines)
end)
