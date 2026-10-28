-- ===================================================================
-- JRS CHAT | Native RedM Server Engine
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local LastMessageTime = {}

local function getPlayerCharacterName(source)
    local src = tonumber(source)
    if not src then return 'Unknown' end

    local char = exports['jrs_core']:GetCharacter(src)
    if char and char.firstname and char.lastname then
        return ('%s %s'):format(char.firstname, char.lastname)
    end
    return GetPlayerName(src) or ('Player ' .. src)
end

local function isRateLimited(source)
    local src = tonumber(source)
    local now = GetGameTimer()
    if LastMessageTime[src] and (now - LastMessageTime[src]) < (Config.MessageCooldown or 750) then
        TriggerClientEvent('jrs_core:sendRightTipNotification', src, 'يرجى التمهل في إرسال الرسائل', 3000)
        return true
    end
    LastMessageTime[src] = now
    return false
end

local function getNearbyPlayers(source, maxDistance)
    local src = tonumber(source)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { src } end

    local srcCoords = GetEntityCoords(ped)
    local targets = {}

    for _, playerId in ipairs(GetPlayers()) do
        local targetSrc = tonumber(playerId)
        local targetPed = GetPlayerPed(targetSrc)
        if targetPed and targetPed ~= 0 then
            local dist = #(srcCoords - GetEntityCoords(targetPed))
            if dist <= maxDistance then
                targets[#targets + 1] = targetSrc
            end
        end
    end

    return targets
end

local function sanitize(text)
    if type(text) ~= 'string' then return '' end
    text = text:match('^%s*(.-)%s*$') or ''
    if #text > (Config.MaxMessageLength or 250) then
        text = text:sub(1, Config.MaxMessageLength)
    end
    return text
end

-- ===================================================================
-- Standard Local Speech
-- ===================================================================
RegisterNetEvent('jrs_chat:server:sendMessage', function(rawMessage)
    local src = source
    if isRateLimited(src) then return end

    local msg = sanitize(rawMessage)
    if msg == '' then return end

    local author = getPlayerCharacterName(src)
    local targets = getNearbyPlayers(src, Config.Proximity.Local or 15.0)

    for _, target in ipairs(targets) do
        TriggerClientEvent('jrs_chat:client:addMessage', target, {
            tag = 'قريب',
            type = 'local',
            author = author,
            text = msg
        })
    end
end)

-- ===================================================================
-- Roleplay Commands (/me, /do, /ooc, /s, /w, /ann, /clear)
-- ===================================================================

RegisterCommand('me', function(source, args)
    if source == 0 then return end
    if isRateLimited(source) then return end

    local action = sanitize(table.concat(args, ' '))
    if action == '' then return end

    local author = getPlayerCharacterName(source)
    local targets = getNearbyPlayers(source, Config.Proximity.Me or 15.0)

    for _, target in ipairs(targets) do
        TriggerClientEvent('jrs_chat:client:addMessage', target, {
            tag = 'ME',
            type = 'me',
            author = author,
            text = action
        })
    end
end, false)

RegisterCommand('do', function(source, args)
    if source == 0 then return end
    if isRateLimited(source) then return end

    local desc = sanitize(table.concat(args, ' '))
    if desc == '' then return end

    local author = getPlayerCharacterName(source)
    local targets = getNearbyPlayers(source, Config.Proximity.Do or 15.0)

    for _, target in ipairs(targets) do
        TriggerClientEvent('jrs_chat:client:addMessage', target, {
            tag = 'DO',
            type = 'do',
            author = author,
            text = ('* %s *'):format(desc)
        })
    end
end, false)

RegisterCommand('ooc', function(source, args)
    if source == 0 then return end
    if isRateLimited(source) then return end

    local msg = sanitize(table.concat(args, ' '))
    if msg == '' then return end

    local name = GetPlayerName(source) or tostring(source)
    TriggerClientEvent('jrs_chat:client:addMessage', -1, {
        tag = 'OOC',
        type = 'ooc',
        author = name,
        text = msg
    })
end, false)

RegisterCommand('s', function(source, args)
    if source == 0 then return end
    if isRateLimited(source) then return end

    local msg = sanitize(table.concat(args, ' '))
    if msg == '' then return end

    local author = getPlayerCharacterName(source)
    local targets = getNearbyPlayers(source, Config.Proximity.Shout or 35.0)

    for _, target in ipairs(targets) do
        TriggerClientEvent('jrs_chat:client:addMessage', target, {
            tag = 'صراخ',
            type = 'shout',
            author = author,
            text = msg
        })
    end
end, false)

RegisterCommand('w', function(source, args)
    if source == 0 then return end
    if isRateLimited(source) then return end

    local msg = sanitize(table.concat(args, ' '))
    if msg == '' then return end

    local author = getPlayerCharacterName(source)
    local targets = getNearbyPlayers(source, Config.Proximity.Whisper or 3.0)

    for _, target in ipairs(targets) do
        TriggerClientEvent('jrs_chat:client:addMessage', target, {
            tag = 'همس',
            type = 'whisper',
            author = author,
            text = msg
        })
    end
end, false)

RegisterCommand('ann', function(source, args)
    if source ~= 0 then
        local isAdmin = exports['jrs_core']:IsAdmin(source)
        if not isAdmin then
            TriggerClientEvent('jrs_core:sendRightTipNotification', source, 'ليس لديك صلاحية استخدام هذا الأمر', 4000)
            return
        end
    end

    local msg = sanitize(table.concat(args, ' '))
    if msg == '' then return end

    TriggerClientEvent('jrs_chat:client:addMessage', -1, {
        tag = 'إعلان خادم',
        type = 'ann',
        author = 'الإدارة',
        text = msg
    })
end, false)

RegisterCommand('clear', function(source)
    if source > 0 then
        TriggerClientEvent('jrs_chat:client:clear', source)
    end
end, false)

AddEventHandler('playerDropped', function()
    LastMessageTime[source] = nil
end)

-- Server Exports
exports('Broadcast', function(data)
    TriggerClientEvent('jrs_chat:client:addMessage', -1, data)
end)
exports('SendToPlayer', function(target, data)
    TriggerClientEvent('jrs_chat:client:addMessage', tonumber(target), data)
end)
