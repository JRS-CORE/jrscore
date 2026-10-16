-- jrs_mdt | server: helpers shared by the other server files
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
--
-- A "grade" in Config.LawJobs says what an officer of that rank may do:
-- canCreateRecords, canDeleteRecords, canManageWarrants, isAdmin.

MDT = {}

-- the player, their job config and their grade config (grade is Config.Defaults when the rank is not listed)
function MDT.Standing(src)
    local player = MDTCore.GetPlayer(src)
    local job = player and player.PlayerData.job
    local jobConfig = job and Config.LawJobs[job.name]
    if not jobConfig then return player, nil, nil end
    return player, jobConfig, jobConfig.grades[job.grade.level] or Config.Defaults.jobGrade
end

-- a law officer may open the MDT
function MDT.Access(src)
    local player, jobConfig = MDT.Standing(src)
    if not jobConfig then return false end
    return not (Config.Settings.requireOnDuty and not player.PlayerData.job.onduty)
end

-- does the officer's grade have this permission ('isAdmin', 'canCreateRecords', ...)
function MDT.Can(src, permission)
    local _, _, grade = MDT.Standing(src)
    return grade ~= nil and grade[permission] == true
end

-- the grade of the player, or nil when they are not law
function MDT.Grade(src)
    local _, _, grade = MDT.Standing(src)
    return grade
end

function MDT.FullName(player)
    local info = player.PlayerData.charinfo
    return info.firstname .. ' ' .. info.lastname
end

-- { name, citizenid } of the officer behind a source
function MDT.Officer(src)
    local player = MDTCore.GetPlayer(src)
    if not player then return nil end
    return MDT.FullName(player), player.PlayerData.citizenid, player
end

-- a character's name: from the online player, else from the character table; nil when unknown
function MDT.NameOf(citizenid)
    local online = MDTCore.GetPlayerByCitizenId(citizenid)
    if online then return MDT.FullName(online), online end

    local row = MySQL.query.await('SELECT charinfo FROM jrs_mdt_players WHERE citizenid = ?', { citizenid })
    if row and row[1] then
        local info = json.decode(row[1].charinfo)
        return info.firstname .. ' ' .. info.lastname
    end
end

-- { success = false, message = <translated> }
function MDT.Fail(key, ...)
    return { success = false, message = locale(key, ...) }
end

-- the callbacks that change things answer with the same shape when the table was not touched
function MDT.Touched(result)
    return type(result) == 'table' and (result.affectedRows or 0) > 0
end

function MDT.Audit(src, action, targetType, targetId, targetName, details)
    local name, cid = MDT.Officer(src)
    if not name then return end
    MySQL.insert.await(
        'INSERT INTO mdt_audit_logs (action, target_type, target_id, target_name, details, performed_by, performed_by_name) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { action, targetType, targetId, targetName, details and json.encode(details) or nil, cid, name })
end

-- sends an event to every online officer ('law') or every online MDT admin ('admin')
function MDT.Broadcast(group, event, data)
    for _, id in ipairs(MDTCore.GetPlayers()) do
        local src = tonumber(id)
        local send
        if group == 'admin' then
            send = MDT.Can(src, 'isAdmin')
        else
            local _, jobConfig = MDT.Standing(src)
            send = jobConfig ~= nil
        end
        if send then TriggerClientEvent(event, src, data) end
    end
end

-- a player may read their own data; everything else needs the records permission
function MDT.SelfOrLaw(src, citizenid)
    local player = MDTCore.GetPlayer(src)
    if not player then return false end
    if citizenid ~= nil and citizenid == player.PlayerData.citizenid then return true end
    return MDT.Can(src, 'canCreateRecords')
end

-- rows with JSON columns decoded in place
function MDT.Decode(rows, ...)
    local columns = { ... }
    rows = rows or {}
    for _, row in ipairs(rows) do
        for _, column in ipairs(columns) do
            if type(row[column]) == 'string' then row[column] = json.decode(row[column]) or {} end
        end
    end
    return rows
end

-- "(?, ?, ?)" for a list
function MDT.Marks(list)
    local marks = {}
    for i = 1, #list do marks[i] = '?' end
    return '(' .. table.concat(marks, ',') .. ')'
end
