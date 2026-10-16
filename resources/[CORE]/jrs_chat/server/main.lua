-- jrs_chat | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_chat | server
-- Plain chat and /ooc show the character's name, with the account name as fallback. The author is always
-- decided here, never taken from the client. Messages are trimmed, cut to a length and rate limited.

local sentAt = {}               -- player -> game timer of their last message

local function tell(src, key, ...) JRS.Notify(src, L(key, ...), 4000) end

local function authorOf(src)
    local char = JRS.Char(src)
    if char and char.firstname and char.lastname then return ('%s %s'):format(char.firstname, char.lastname) end
    return GetPlayerName(src) or L('unknown_player')
end

-- returns the cleaned message, or nil when it is empty or sent too fast
local function accept(src, message)
    if type(message) ~= 'string' then return end
    message = message:match('^%s*(.-)%s*$')
    if message == '' then return end

    local now = GetGameTimer()
    if sentAt[src] and now - sentAt[src] < Config.MessageCooldown then
        return tell(src, 'slow_down')
    end
    sentAt[src] = now
    return message:sub(1, Config.MaxMessageLength)
end

local function say(src, message)
    local name = authorOf(src)
    TriggerEvent('chatMessage', src, name, message)          -- other resources may hook or cancel it
    if WasEventCanceled() then return end

    TriggerClientEvent('chat:addMessage', -1, {
        template = '<div class="chat-message"><b>[{2}] {0}:</b> {1}</div>',
        args = { name, message, L('ooc_prefix') },
    })
    print(('%s^7: %s^7'):format(name, message))
end

RegisterNetEvent('_chat:messageEntered', function(_, _, message)
    local src = source
    message = accept(src, message)
    if message then say(src, message) end
end)

RegisterNetEvent('__cfx_internal:commandFallback', function(command)
    local src = source
    CancelEvent()
    if type(command) == 'string' then tell(src, 'unknown_command', (command:match('^(%S+)') or ''):sub(1, 32)) end
end)

-- a server-wide announcement: from other server scripts, or from a client who is an admin
RegisterNetEvent('chat:server:ServerPSA', function(message)
    local src = tonumber(source) or 0
    if src > 0 and not JRS.IsAdmin(src) then return tell(src, 'no_permission') end
    if type(message) ~= 'string' or message == '' then return end

    TriggerClientEvent('chat:addMessage', -1, {
        template = '<div class="chat-message server">{1}: {0}</div>',
        args = { message:sub(1, Config.MaxMessageLength), L('server_prefix') },
    })
end)

RegisterCommand('clearchat', function(src)
    if src > 0 then TriggerClientEvent('chat:clear', src) end
end, false)

RegisterCommand('ooc', function(src, _, raw)
    if src == 0 then return end
    local message = accept(src, raw:sub(5))
    if message then say(src, message) end
end, false)

AddEventHandler('playerDropped', function() sentAt[source] = nil end)
