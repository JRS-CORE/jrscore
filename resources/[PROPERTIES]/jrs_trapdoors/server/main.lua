local states      = {} -- id -> open
local busyUntil   = {} -- id -> game timer
local autoToken   = {} -- id -> int, invalidates stale auto-close timers
local lastRequest = {} -- src -> game timer
local codes       = {} -- id -> { code = '1234', owner = charId }  (never sent to clients)
local failures    = {} -- charId -> id -> { count, lockUntil }
local dbReady     = false

local function setState(id, open)
    states[id] = open
    GlobalState['trapdoor:' .. id] = open
    autoToken[id] = (autoToken[id] or 0) + 1
    if open and Config.AutoCloseTime > 0 then
        local token = autoToken[id]
        SetTimeout(Config.AutoCloseTime, function()
            if autoToken[id] == token and states[id] then
                busyUntil[id] = GetGameTimer() + Config.MoveDuration
                setState(id, false)
            end
        end)
    end
end

-- clients only learn who owns a door's code, never the code itself
local function publishCode(id)
    GlobalState['trapdoorCode:' .. id] = codes[id] and codes[id].owner or false
end

local function saveCode(id, data)
    codes[id] = data
    publishCode(id)
    if data then
        MySQL.insert('INSERT INTO jrs_trapdoors (door_id, passcode, owner) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE passcode = VALUES(passcode), owner = VALUES(owner)',
            { id, data.code, data.owner })
    else
        MySQL.update('DELETE FROM jrs_trapdoors WHERE door_id = ?', { id })
    end
end

for id in pairs(Config.Trapdoors) do
    setState(id, false)
    publishCode(id)
end

MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `jrs_trapdoors` (
        `door_id` VARCHAR(64) NOT NULL, `passcode` CHAR(4) NOT NULL, `owner` VARCHAR(50) NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`door_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    for _, row in ipairs(MySQL.query.await('SELECT door_id, passcode, owner FROM jrs_trapdoors') or {}) do
        if Config.Trapdoors[row.door_id] then
            codes[row.door_id] = { code = row.passcode, owner = row.owner }
            publishCode(row.door_id)
        end
    end
    dbReady = true
end)

local function isValidCode(code)
    return type(code) == 'string' and code:match('^%d%d%d%d$') ~= nil
end

-- returns door, charId or nil, errorText
local function validate(src, id)
    if type(id) ~= 'string' or not Config.Trapdoors[id] or not dbReady then return end
    local charId = JRS.CharId(src)
    if not charId then return end
    local now = GetGameTimer()
    if (lastRequest[src] or 0) > now then return end
    lastRequest[src] = now + Config.PlayerCooldown
    local door = Config.Trapdoors[id]
    if not JRS.Near(src, door.closedPosition, door.interactDistance + 3.0) then
        return nil, nil, L('too_far')
    end
    return door, tostring(charId)
end

local function lockoutRemaining(cid, id)
    local f = failures[cid] and failures[cid][id]
    return f and math.max(f.lockUntil - GetGameTimer(), 0) or 0
end

local function registerFailure(cid, id)
    failures[cid] = failures[cid] or {}
    local f = failures[cid][id] or { count = 0, lockUntil = 0 }
    f.count = f.count + 1
    if f.count >= Config.MaxCodeAttempts then
        f.count = 0
        f.lockUntil = GetGameTimer() + Config.CodeLockoutTime
    end
    failures[cid][id] = f
end

local function lockedText(ms) return L('locked_out', math.ceil(ms / 1000)) end

JRS.Callback('jrs_trapdoors:open', function(src, id, code)
    local door, cid, err = validate(src, id)
    if not door then return { ok = false, msg = err } end
    if states[id] then return { ok = false } end
    local lock = codes[id]
    if lock then
        local remaining = lockoutRemaining(cid, id)
        if remaining > 0 then return { ok = false, msg = lockedText(remaining) } end
        if not isValidCode(code) then return { ok = false, msg = L('invalid_code') } end
        if code ~= lock.code then
            registerFailure(cid, id)
            remaining = lockoutRemaining(cid, id)
            return { ok = false, msg = remaining > 0 and lockedText(remaining) or L('wrong_code') }
        end
        if failures[cid] then failures[cid][id] = nil end
    end
    if (busyUntil[id] or 0) > GetGameTimer() then return { ok = false, msg = L('busy') } end
    busyUntil[id] = GetGameTimer() + Config.MoveDuration
    setState(id, true)
    return { ok = true }
end)

RegisterNetEvent('jrs_trapdoors:server:close', function(id)
    local src = source
    local door, _, err = validate(src, id)
    if not door then
        if err then JRS.Notify(src, err) end
        return
    end
    if not states[id] then return end
    if (busyUntil[id] or 0) > GetGameTimer() then return JRS.Notify(src, L('busy')) end
    busyUntil[id] = GetGameTimer() + Config.MoveDuration
    setState(id, false)
end)

JRS.Callback('jrs_trapdoors:setCode', function(src, id, newCode)
    local door, cid, err = validate(src, id)
    if not door then return { ok = false, msg = err } end
    if codes[id] then return { ok = false, msg = L('code_already_set') } end
    if not isValidCode(newCode) then return { ok = false, msg = L('invalid_code') } end
    saveCode(id, { code = newCode, owner = cid })
    return { ok = true, msg = L('code_set') }
end)

JRS.Callback('jrs_trapdoors:changeCode', function(src, id, current, newCode)
    local door, cid, err = validate(src, id)
    if not door then return { ok = false, msg = err } end
    local lock = codes[id]
    if not lock then return { ok = false } end
    if lock.owner ~= cid then return { ok = false, msg = L('not_owner') } end
    local remaining = lockoutRemaining(cid, id)
    if remaining > 0 then return { ok = false, msg = lockedText(remaining) } end
    if not isValidCode(current) or not isValidCode(newCode) then return { ok = false, msg = L('invalid_code') } end
    if current ~= lock.code then
        registerFailure(cid, id)
        return { ok = false, msg = L('wrong_code') }
    end
    saveCode(id, { code = newCode, owner = lock.owner })
    return { ok = true, msg = L('code_changed') }
end)

JRS.Callback('jrs_trapdoors:myId', function(src)
    local cid = JRS.CharId(src)
    return cid and tostring(cid) or nil
end)

RegisterCommand(Config.AdminResetCommand, function(src, args)
    if src > 0 and not JRS.IsAdmin(src) then return end
    local id = args[1]
    local function reply(text)
        if src > 0 then JRS.Notify(src, text) else print(text) end
    end
    if not id or not Config.Trapdoors[id] then return reply(L('reset_unknown')) end
    saveCode(id, nil)
    reply(L('reset_done', id))
end, false)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)
