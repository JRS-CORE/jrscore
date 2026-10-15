-- jrs_mailbox | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_mailbox | server
-- Letters live in the table `mailbox_mails` (one row per letter, addressed to a character by account id and
-- name). The client asks through callbacks; every request is checked here: who the player is, who may read
-- or delete a letter, the price, and the cool-downs.

local Core = exports.jrs_core:GetCore()
local Text = Config.Text[Config.Language] or Config.Text.en

local directory, directoryAt = {}, 0
local lastLetter, lastShout = {}, {}

-- ------------------------------------------------------------------ helpers

local function me(src)
    local user = Core.getUser(src)
    if not user then return end
    return user.getUsedCharacter, user.getIdentifier()
end

local function say(src, line, vars)
    for key, value in pairs(vars or {}) do line = line:gsub('{' .. key .. '}', tostring(value)) end
    TriggerClientEvent('jrs:Tip', src, line, 4000)
end

-- letters are plain text: no markup can reach another player's page
local function plain(text, limit)
    text = tostring(text or ''):gsub('[<>]', ''):gsub('%c', function(c) return c == '\n' and c or ' ' end)
    return text:sub(1, limit)
end

local function wait(table_, src, seconds)
    if seconds <= 0 or not table_[src] then return 0 end
    local left = table_[src] + seconds * 1000 - GetGameTimer()
    return left > 0 and math.ceil(left / 1000) or 0
end

-- ------------------------------------------------------------------ list of everyone who can get mail

local function loadDirectory()
    MySQL.query('SELECT charidentifier, firstname, lastname FROM jrs_characters', {}, function(rows)
        local list = {}
        for _, row in ipairs(rows or {}) do
            list[#list + 1] = { id = tostring(row.charidentifier), name = ((row.firstname or '') .. ' ' .. (row.lastname or '')):gsub('^%s+', '') }
        end
        table.sort(list, function(a, b) return a.name:upper() < b.name:upper() end)
        directory, directoryAt = list, GetGameTimer()
    end)
end
CreateThread(loadDirectory)

Core.Callback.Register('jrs_mailbox:directory', function(_, cb)
    if Config.DirectoryRefresh > 0 and GetGameTimer() - directoryAt > Config.DirectoryRefresh * 1000 then loadDirectory() end
    cb(directory)
end)

-- ------------------------------------------------------------------ reading

Core.Callback.Register('jrs_mailbox:inbox', function(src, cb)
    local character, account = me(src)
    if not character then return cb({}) end
    MySQL.query(
        'SELECT id, sender_id, sender_firstname, sender_lastname, message, opened, received_at FROM mailbox_mails ' ..
        'WHERE receiver_id = ? AND receiver_firstname = ? AND receiver_lastname = ? ORDER BY id DESC',
        { account, character.firstname, character.lastname }, function(rows)
            local letters = {}
            for _, row in ipairs(rows or {}) do
                letters[#letters + 1] = {
                    id = tostring(row.id), from = (row.sender_firstname .. ' ' .. row.sender_lastname),
                    senderAccount = row.sender_id, first = row.sender_firstname, last = row.sender_lastname,
                    message = row.message, opened = row.opened == 1 or row.opened == true, at = row.received_at,
                }
            end
            cb(letters)
        end)
end)

-- the page reports which letters were deleted or read; only this character's own letters can change
local function ids(list)
    local out = {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        local n = tonumber(v)
        if n and #out < 200 then out[#out + 1] = math.floor(n) end
    end
    return out
end

RegisterNetEvent('jrs_mailbox:update', function(change)
    local src = source
    local character, account = me(src)
    if not character or type(change) ~= 'table' then return end
    local owner = { account, character.firstname, character.lastname }

    for _, id in ipairs(ids(change.delete)) do
        MySQL.update('DELETE FROM mailbox_mails WHERE id = ? AND receiver_id = ? AND receiver_firstname = ? AND receiver_lastname = ?',
            { id, owner[1], owner[2], owner[3] })
    end
    for _, id in ipairs(ids(change.read)) do
        MySQL.update('UPDATE mailbox_mails SET opened = 1 WHERE id = ? AND receiver_id = ? AND receiver_firstname = ? AND receiver_lastname = ?',
            { id, owner[1], owner[2], owner[3] })
    end
end)

-- ------------------------------------------------------------------ writing

local function charge(src, character, price)
    if price <= 0 then return true end
    if character.money < price then
        say(src, Text.poor, { price = price })
        return false
    end
    character.removeCurrency(0, price)
    return true
end

Core.Callback.Register('jrs_mailbox:send', function(src, cb, charId, body)
    local character, account = me(src)
    if not character then return cb(false) end

    local seconds = wait(lastLetter, src, Config.SendCooldown)
    if seconds > 0 then say(src, Text.wait, { seconds = seconds }) return cb(false) end

    local message = plain(body, 1000)
    local target = tonumber(charId) and MySQL.single.await(
        'SELECT charidentifier, identifier, firstname, lastname FROM jrs_characters WHERE charidentifier = ? LIMIT 1', { tonumber(charId) })
    if message == '' or not target then return cb(false) end
    if not charge(src, character, Config.SendPrice) then return cb(false) end

    lastLetter[src] = GetGameTimer()
    MySQL.insert(
        'INSERT INTO mailbox_mails (sender_id, sender_firstname, sender_lastname, receiver_id, receiver_firstname, receiver_lastname, message) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { account, character.firstname, character.lastname, target.identifier, target.firstname, target.lastname, message })
    say(src, Text.sent)

    for _, id in ipairs(GetPlayers()) do
        local other = me(tonumber(id))
        if other and other.charIdentifier == target.charidentifier then
            TriggerClientEvent('jrs_mailbox:got', tonumber(id), character.firstname .. ' ' .. character.lastname)
            break
        end
    end
    cb(true)
end)

Core.Callback.Register('jrs_mailbox:shout', function(src, cb, body)
    local character = me(src)
    if not character then return cb(false) end

    local seconds = wait(lastShout, src, Config.BroadcastCooldown)
    if seconds > 0 then say(src, Text.wait, { seconds = seconds }) return cb(false) end

    local message = plain(body, 300)
    if message == '' or not charge(src, character, Config.BroadcastPrice) then return cb(false) end

    lastShout[src] = GetGameTimer()
    say(src, Text.sent)
    TriggerClientEvent('jrs_mailbox:shouted', -1, character.firstname .. ' ' .. character.lastname, message)
    cb(true)
end)

AddEventHandler('playerDropped', function()
    lastLetter[source], lastShout[source] = nil, nil
end)
