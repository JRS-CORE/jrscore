-- ===================================================================
-- JRS CHAT | Native RedM Client
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

local isChatOpen = false

local function setChatFocus(state)
    isChatOpen = state == true
    SetNuiFocus(isChatOpen, isChatOpen)
    SetNuiFocusKeepInput(false)
    TriggerEvent('jrs_chat:client:focusChanged', isChatOpen)
end

local function openChat()
    if isChatOpen or IsPauseMenuActive() then return end
    setChatFocus(true)
    SendNUIMessage({ action = 'open' })
end

local function addMessage(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage({
        action = 'addMessage',
        message = data
    })
end

RegisterNUICallback('closeChat', function(_, cb)
    setChatFocus(false)
    cb('ok')
end)

RegisterNUICallback('submitMessage', function(data, cb)
    setChatFocus(false)
    local msg = data and data.message
    if type(msg) == 'string' and msg ~= '' then
        if msg:sub(1, 1) == '/' then
            ExecuteCommand(msg:sub(2))
        else
            TriggerServerEvent('jrs_chat:server:sendMessage', msg)
        end
    end
    cb('ok')
end)

-- Key binding to open chat (T / INPUT_MP_TEXT_CHAT_ALL)
CreateThread(function()
    while true do
        Wait(0)
        if not isChatOpen and not IsPauseMenuActive() then
            if IsControlJustReleased(0, 0x9720E02E) or IsDisabledControlJustReleased(0, 0x9720E02E) then
                openChat()
            end
        else
            Wait(150)
        end
    end
end)

-- Events
RegisterNetEvent('jrs_chat:client:addMessage', addMessage)
RegisterNetEvent('chat:addMessage', function(data)
    if type(data) == 'table' then
        local text = data.args and data.args[2] or (data.args and data.args[1]) or data.template or ''
        local author = data.args and data.args[2] and data.args[1] or nil
        addMessage({
            tag = 'CHAT',
            type = 'local',
            author = author,
            text = text
        })
    end
end)

RegisterNetEvent('jrs_chat:client:clear', function()
    SendNUIMessage({ action = 'clear' })
end)
RegisterNetEvent('chat:clear', function()
    SendNUIMessage({ action = 'clear' })
end)

RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    SendNUIMessage({
        action = 'addSuggestion',
        suggestion = {
            name = name:gsub('^/', ''),
            help = help,
            params = params
        }
    })
end)

-- Register standard suggestions
CreateThread(function()
    Wait(1500)
    local suggestions = {
        { name = 'me', help = 'وصف حركة أو فعل يقوم به اللاعب (حركة RP)' },
        { name = 'do', help = 'وصف مشهد أو حالة محيطة باللاعب (وصف RP)' },
        { name = 'ooc', help = 'كتابة كلام عام خارج إطار اللعب (Out Of Character)' },
        { name = 's', help = 'صراخ يسمعه اللاعبون من مسافة 35 متر' },
        { name = 'w', help = 'همس يسمعه اللاعبون القريبون جداً (3 متر)' },
        { name = 'clear', help = 'مسح سجل رسائل الشات الخاصة بك' },
    }
    SendNUIMessage({
        action = 'setSuggestions',
        suggestions = suggestions
    })
end)

-- Client Exports
exports('isChatOpen', function() return isChatOpen end)
exports('addMessage', addMessage)
exports('openChat', openChat)
