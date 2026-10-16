-- jrs_trapdoors | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_trapdoors | server
-- The server owns every door: open/closed state, passcodes (kept in the database and never sent to clients),
-- wrong-code lockouts and the auto-close timer.

local open       = {}      -- id -> true while open
local moveUntil  = {}      -- id -> game timer until which the door is moving
local closeToken = {}      -- id -> counter, so an old auto-close timer can tell it is out of date
local nextAsk    = {}      -- player -> game timer before which they may not act again
local codes      = {}      -- id -> { code, owner }
local misses     = {}      -- char id -> door id -> { count, lockedUntil }
local ready      = false

local function now() return GetGameTimer() end

local function setOpen(id, value)
    open[id] = value
    GlobalState['trapdoor:' .. id] = value

    closeToken[id] = (closeToken[id] or 0) + 1
    if value and Config.AutoCloseTime > 0 then
        local mine = closeToken[id]
        SetTimeout(Config.AutoCloseTime, function()
            if closeToken[id] == mine and open[id] then
                moveUntil[id] = now() + Config.MoveDuration
                setOpen(id, false)
            end
        end)
    end
end

-- everybody may learn WHO set a door's code, nobody learns the code
local function publish(id)
    GlobalState['trapdoorCode:' .. id] = codes[id] and codes[id].owner or false
end

local function store(id, entry)
    codes[id] = entry
    publish(id)
    if entry then
        MySQL.insert('INSERT INTO jrs_trapdoors (door_id, passcode, owner) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE passcode = VALUES(passcode), owner = VALUES(owner)',
            { id, entry.code, entry.owner })
    else
        MySQL.update('DELETE FROM jrs_trapdoors WHERE door_id = ?', { id })
    end
end

for id in pairs(Config.Trapdoors) do
    setOpen(id, false)
    publish(id)
end

MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `jrs_trapdoors` (
        `door_id` VARCHAR(64) NOT NULL, `passcode` CHAR(4) NOT NULL, `owner` VARCHAR(50) NOT NULL,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`door_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    for _, row in ipairs(MySQL.query.await('SELECT door_id, passcode, owner FROM jrs_trapdoors') or {}) do
        if Config.Trapdoors[row.door_id] then
            codes[row.door_id] = { code = row.passcode, owner = row.owner }
            publish(row.door_id)
        end
    end
    ready = true
end)

local function fourDigits(text) return type(text) == 'string' and text:match('^%d%d%d%d$') ~= nil end

-- who is asking: returns the door config and the char id, or nil plus a message
local function caller(src, id)
    if type(id) ~= 'string' or not Config.Trapdoors[id] or not ready then return end
    local char = JRS.CharId(src)
    if not char then return end

    if (nextAsk[src] or 0) > now() then return end
    nextAsk[src] = now() + Config.PlayerCooldown

    local cfg = Config.Trapdoors[id]
    if not JRS.Near(src, cfg.closedPosition, cfg.interactDistance + 3.0) then return nil, nil, L('too_far') end
    return cfg, tostring(char)
end

-- ------------------------------------------------------------------ wrong codes

local function lockLeft(char, id)
    local m = misses[char] and misses[char][id]
    return m and math.max(m.lockedUntil - now(), 0) or 0
end

local function miss(char, id)
    misses[char] = misses[char] or {}
    local m = misses[char][id] or { count = 0, lockedUntil = 0 }
    m.count = m.count + 1
    if m.count >= Config.MaxCodeAttempts then
        m.count, m.lockedUntil = 0, now() + Config.CodeLockoutTime
    end
    misses[char][id] = m
end

local function lockedMessage(ms) return L('locked_out', math.ceil(ms / 1000)) end
local function no(message) return { ok = false, msg = message } end

-- ------------------------------------------------------------------ actions

JRS.Callback('jrs_trapdoors:open', function(src, id, code)
    local cfg, char, why = caller(src, id)
    if not cfg then return no(why) end
    if open[id] then return no() end

    local lock = codes[id]
    if lock then
        local left = lockLeft(char, id)
        if left > 0 then return no(lockedMessage(left)) end
        if not fourDigits(code) then return no(L('invalid_code')) end
        if code ~= lock.code then
            miss(char, id)
            left = lockLeft(char, id)
            return no(left > 0 and lockedMessage(left) or L('wrong_code'))
        end
        if misses[char] then misses[char][id] = nil end
    end

    if (moveUntil[id] or 0) > now() then return no(L('busy')) end
    moveUntil[id] = now() + Config.MoveDuration
    setOpen(id, true)
    return { ok = true }
end)

RegisterNetEvent('jrs_trapdoors:server:close', function(id)
    local src = source
    local cfg, _, why = caller(src, id)
    if not cfg then
        if why then JRS.Notify(src, why) end
        return
    end
    if not open[id] then return end
    if (moveUntil[id] or 0) > now() then return JRS.Notify(src, L('busy')) end
    moveUntil[id] = now() + Config.MoveDuration
    setOpen(id, false)
end)

JRS.Callback('jrs_trapdoors:setCode', function(src, id, fresh)
    local cfg, char, why = caller(src, id)
    if not cfg then return no(why) end
    if codes[id] then return no(L('code_already_set')) end
    if not fourDigits(fresh) then return no(L('invalid_code')) end
    store(id, { code = fresh, owner = char })
    return { ok = true, msg = L('code_set') }
end)

JRS.Callback('jrs_trapdoors:changeCode', function(src, id, current, fresh)
    local cfg, char, why = caller(src, id)
    if not cfg then return no(why) end

    local lock = codes[id]
    if not lock then return no() end
    if lock.owner ~= char then return no(L('not_owner')) end

    local left = lockLeft(char, id)
    if left > 0 then return no(lockedMessage(left)) end
    if not (fourDigits(current) and fourDigits(fresh)) then return no(L('invalid_code')) end
    if current ~= lock.code then
        miss(char, id)
        return no(L('wrong_code'))
    end
    store(id, { code = fresh, owner = lock.owner })
    return { ok = true, msg = L('code_changed') }
end)

JRS.Callback('jrs_trapdoors:myId', function(src)
    local char = JRS.CharId(src)
    return char and tostring(char) or nil
end)

RegisterCommand(Config.AdminResetCommand, function(src, args)
    if src > 0 and not JRS.IsAdmin(src) then return end
    local function say(text) if src > 0 then JRS.Notify(src, text) else print(text) end end
    local id = args[1]
    if not (id and Config.Trapdoors[id]) then return say(L('reset_unknown')) end
    store(id, nil)
    say(L('reset_done', id))
end, false)

AddEventHandler('playerDropped', function() nextAsk[source] = nil end)
