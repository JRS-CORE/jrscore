
local lastMessage = {}

local function notify(src, key, ...)
    JRS.Notify(src, L(key, ...), 4000)
end

-- In-character first + last name, falling back to the account name
local function GetCharacterName(src)
    local char = JRS.Char(src)
    if char and char.firstname and char.lastname then
        return ('%s %s'):format(char.firstname, char.lastname)
    end
    return GetPlayerName(src) or L('unknown_player')
end

-- Trims, length-caps and rate-limits a message. Returns the clean message or nil.
local function ValidateMessage(src, message)
    if type(message) ~= 'string' then return end
    message = message:match('^%s*(.-)%s*$')
    if message == '' then return end

    local now = GetGameTimer()
    if lastMessage[src] and now - lastMessage[src] < Config.MessageCooldown then
        notify(src, 'slow_down')
        return
    end
    lastMessage[src] = now

    return message:sub(1, Config.MaxMessageLength)
end

local function BroadcastOOC(src, message)
    local name = GetCharacterName(src)
    TriggerEvent('chatMessage', src, name, message) -- lets other resources hook/cancel
    if WasEventCanceled() then return end

    TriggerClientEvent('chat:addMessage', -1, {
        template = '<div class="chat-message"><b>[{2}] {0}:</b> {1}</div>',
        args = { name, message, L('ooc_prefix') },
    })
    print(('%s^7: %s^7'):format(name, message))
end

-- Plain chat from the NUI. The author is always resolved on the server.
RegisterNetEvent('_chat:messageEntered', function(_, _, message)
    local src = source
    message = ValidateMessage(src, message)
    if message then BroadcastOOC(src, message) end
end)

RegisterNetEvent('__cfx_internal:commandFallback', function(command)
    local src = source
    CancelEvent()
    if type(command) ~= 'string' then return end
    notify(src, 'unknown_command', (command:match('^(%S+)') or ''):sub(1, 32))
end)

-- Server-wide announcement. Usable from other server scripts, or by admins only from a client.
RegisterNetEvent('chat:server:ServerPSA', function(message)
    local src = tonumber(source) or 0
    if src > 0 and not JRS.IsAdmin(src) then
        notify(src, 'no_permission')
        return
    end
    if type(message) ~= 'string' or message == '' then return end

    TriggerClientEvent('chat:addMessage', -1, {
        template = '<div class="chat-message server">{1}: {0}</div>',
        args = { message:sub(1, Config.MaxMessageLength), L('server_prefix') },
    })
end)

AddEventHandler('playerDropped', function()
    lastMessage[source] = nil
end)

RegisterCommand('clearchat', function(source)
    if source > 0 then TriggerClientEvent('chat:clear', source) end
end, false)

RegisterCommand('ooc', function(source, _, rawCommand)
    if source == 0 then return end
    local message = ValidateMessage(source, rawCommand:sub(5))
    if message then BroadcastOOC(source, message) end
end, false)

