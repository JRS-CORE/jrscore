-- JRS boss menu (server). A boss license (table `jobmanager`) makes a character
-- boss of one job; the boss can only manage people of that job.
local function n(v) return tonumber(v) end

local function notify(src, key, ...) TriggerClientEvent('jrs_bossmanager:notify', src, L(key, ...), 5000) end

local function bossJob(src)
    local c = JRS.Char(src)
    if not c then return nil end
    local row = MySQL.single.await('SELECT jobname FROM jobmanager WHERE identifier = ? AND charidentifier = ? LIMIT 1',
        { c.identifier, c.charIdentifier })
    return row and row.jobname or nil
end

local function sourceOfChar(charId)
    for _, s in ipairs(GetPlayers()) do
        if tostring(JRS.CharId(s)) == tostring(charId) then return tonumber(s) end
    end
end

local function cleanJob(job)
    job = tostring(job or ''):gsub('[^%w_%-]', '')
    return job ~= '' and job:sub(1, 50) or nil
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `jobmanager` (
        `identifier` VARCHAR(50) NOT NULL,
        `charidentifier` INT(11) NOT NULL,
        `jobname` VARCHAR(50) NOT NULL,
        PRIMARY KEY (`identifier`, `charidentifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end)

-- ─── boss menu ─────────────────────────────────────────────────────────────
JRS.Callback('jrs_bossmanager:open', function(src)
    local job = bossJob(src)
    if not job then return nil end
    local rows = MySQL.query.await([[SELECT firstname, lastname, charidentifier, jobgrade FROM jrs_characters
        WHERE job = ? ORDER BY jobgrade DESC, firstname ASC]], { job }) or {}
    local list = {}
    for _, r in ipairs(rows) do
        local cid = n(r.charidentifier)
        if cid ~= n(JRS.CharId(src)) then
            local online = sourceOfChar(cid)
            local grade = n(r.jobgrade) or 0
            if online then
                local c = JRS.Char(online)
                grade = c and n(c.jobGrade) or grade
            end
            list[#list + 1] = { charId = cid, name = ('%s %s'):format(r.firstname or '', r.lastname or ''), grade = grade, online = online ~= nil }
        end
    end
    return job, list
end)

JRS.Callback('jrs_bossmanager:nearby', function(src, ids)
    if not bossJob(src) or type(ids) ~= 'table' then return {} end
    local out = {}
    for i = 1, math.min(#ids, 8) do
        local id = n(ids[i])
        if id and id ~= src and GetPlayerName(id) and JRS.Char(id) and JRS.Distance(src, id) <= Config.HireRange + 1.0 then
            out[#out + 1] = { id = id, name = JRS.Name(id) }
        end
    end
    return out
end)

JRS.Callback('jrs_bossmanager:hire', function(src, target, grade)
    local job = bossJob(src)
    if not job then return false, L('not_boss') end
    target, grade = n(target), math.floor(n(grade) or -1)
    if grade < 0 or grade > Config.MaxGrade then return false, L('bad_grade') end
    if not target or target == src or JRS.Distance(src, target) > Config.HireRange + 1.0 then return false, L('too_far') end
    local c = JRS.Char(target)
    if not c then return false, L('too_far') end
    c.setJob(job, true)
    c.setJobGrade(grade, true)
    notify(target, 'you_hired', job, grade)
    return true, L('hired', JRS.Name(target), grade)
end)

JRS.Callback('jrs_bossmanager:setGrade', function(src, charId, grade)
    local job = bossJob(src)
    if not job then return false, L('not_boss') end
    charId, grade = n(charId), math.floor(n(grade) or -1)
    if not charId or charId == n(JRS.CharId(src)) then return false end
    if grade < 0 or grade > Config.MaxGrade then return false, L('bad_grade') end
    local online = sourceOfChar(charId)
    if online then
        local c = JRS.Char(online)
        if not c or c.job ~= job then return false end
        c.setJobGrade(grade, true)
        notify(online, 'your_grade', job, grade)
        return true, L('grade_set', JRS.Name(online), grade)
    end
    local changed = MySQL.update.await('UPDATE jrs_characters SET jobgrade = ? WHERE charidentifier = ? AND job = ?', { grade, charId, job })
    return (changed or 0) > 0, L('grade_set', '#' .. charId, grade)
end)

JRS.Callback('jrs_bossmanager:fire', function(src, charId)
    local job = bossJob(src)
    if not job then return false, L('not_boss') end
    charId = n(charId)
    if not charId or charId == n(JRS.CharId(src)) then return false end
    local online = sourceOfChar(charId)
    if online then
        local c = JRS.Char(online)
        if not c or c.job ~= job then return false end
        local name = JRS.Name(online)
        c.setJob(Config.Unemployed, true)
        c.setJobGrade(0, true)
        notify(online, 'you_fired', job)
        return true, L('fired', name)
    end
    local changed = MySQL.update.await('UPDATE jrs_characters SET job = ?, jobgrade = 0 WHERE charidentifier = ? AND job = ?',
        { Config.Unemployed, charId, job })
    return (changed or 0) > 0, L('fired', '#' .. charId)
end)

-- ─── admin commands ────────────────────────────────────────────────────────
local function reply(src, text)
    if src == 0 then print(text) else JRS.Notify(src, text, 5000) end
end

RegisterCommand(Config.GiveLicenseCommand, function(src, args)
    if src ~= 0 and not JRS.IsAdmin(src) then return end
    local target, job = n(args[1]), cleanJob(args[2])
    if not target or not job then return reply(src, L('usage_give', Config.GiveLicenseCommand)) end
    local c = JRS.Char(target)
    if not c then return reply(src, L('no_player')) end
    MySQL.insert.await('INSERT INTO jobmanager (identifier, charidentifier, jobname) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE jobname = VALUES(jobname)',
        { c.identifier, c.charIdentifier, job })
    reply(src, L('license_set', target, job))
end, false)

RegisterCommand(Config.RevokeLicenseCommand, function(src, args)
    if src ~= 0 and not JRS.IsAdmin(src) then return end
    local target = n(args[1])
    if not target then return reply(src, L('usage_revoke', Config.RevokeLicenseCommand)) end
    local c = JRS.Char(target)
    if not c then return reply(src, L('no_player')) end
    MySQL.update.await('DELETE FROM jobmanager WHERE identifier = ? AND charidentifier = ?', { c.identifier, c.charIdentifier })
    reply(src, L('license_off', target))
end, false)

exports('IsBoss', function(src) return bossJob(src) end)
