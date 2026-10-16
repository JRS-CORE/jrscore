-- jrs_chat | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_chat | client
-- Feeds the chat page: messages, suggestions, templates and themes arrive as events from other resources
-- (chat:addMessage and friends), the page sends back what the player typed.

local typing, opening, loaded, covered = false, false, false, true

local OPEN_KEY <const> = `INPUT_MP_TEXT_CHAT_ALL`

local function page(kind, extra)
    extra = extra or {}
    extra.type = kind
    SendNUIMessage(extra)
end

-- events other resources trigger
for _, name in ipairs({ 'chatMessage', 'chat:addTemplate', 'chat:addMessage', 'chat:addSuggestion', 'chat:addSuggestions',
                        'chat:removeSuggestion', 'chat:clear', '__cfx_internal:serverPrint' }) do
    RegisterNetEvent(name)
end

-- old signature: (author, colour, text)
AddEventHandler('chatMessage', function(author, color, text)
    local args = { text }
    if author ~= '' then table.insert(args, 1, author) end
    page('ON_MESSAGE', { message = { color = color, multiline = true, args = args } })
end)

AddEventHandler('__cfx_internal:serverPrint', function(text)
    print(text)
    page('ON_MESSAGE', { message = { templateId = 'print', multiline = true, args = { text } } })
end)

AddEventHandler('chat:addMessage', function(message) page('ON_MESSAGE', { message = message }) end)
AddEventHandler('chat:addSuggestion', function(name, help, params)
    page('ON_SUGGESTION_ADD', { suggestion = { name = name, help = help, params = params } })
end)
AddEventHandler('chat:addSuggestions', function(list)
    for _, suggestion in ipairs(list) do page('ON_SUGGESTION_ADD', { suggestion = suggestion }) end
end)
AddEventHandler('chat:removeSuggestion', function(name) page('ON_SUGGESTION_REMOVE', { name = name }) end)
AddEventHandler('chat:addTemplate', function(id, html) page('ON_TEMPLATE_ADD', { template = { id = id, html = html } }) end)
AddEventHandler('chat:clear', function() page('ON_CLEAR') end)

-- ------------------------------------------------------------------ what the player typed

RegisterNUICallback('chatResult', function(data, done)
    typing = false
    SetNuiFocus(false)

    local text = type(data.message) == 'string' and data.message or ''
    if not data.canceled and text ~= '' then
        if text:sub(1, 1) == '/' then
            ExecuteCommand(text:sub(2))
        else
            TriggerServerEvent('_chat:messageEntered', nil, nil, text)     -- the author is decided by the server
        end
    end
    done('ok')
end)

-- ------------------------------------------------------------------ suggestions and themes

local function suggestCommands()
    if GetRegisteredCommands then
        local list = {}
        for _, command in ipairs(GetRegisteredCommands()) do
            if IsAceAllowed(('command.%s'):format(command.name)) then
                list[#list + 1] = { name = '/' .. command.name, help = '' }
            end
        end
        TriggerEvent('chat:addSuggestions', list)
    end

    -- this resource's own commands, with translated help
    local message = { { name = L('param_message'), help = L('param_message_help') } }
    TriggerEvent('chat:addSuggestions', {
        { name = '/ooc', help = L('help_ooc'), params = message },
        { name = '/clearchat', help = L('help_clearchat') },
    })
end

-- every started resource may ship a chat theme in its manifest
local function sendThemes()
    local themes = {}
    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)
        if GetResourceState(resource) == 'started' and GetNumResourceMetadata(resource, 'chat_theme') > 0 then
            local name = GetResourceMetadata(resource, 'chat_theme')
            local data = json.decode(GetResourceMetadata(resource, 'chat_theme_extra') or 'null')
            if name and data then
                data.baseUrl = 'nui://' .. resource .. '/'
                themes[name] = data
            end
        end
    end
    page('ON_UPDATE_THEMES', { themes = themes })
end

local function refresh()
    suggestCommands()
    sendThemes()
end

AddEventHandler('onClientResourceStart', function() Wait(500) refresh() end)
AddEventHandler('onClientResourceStop', function() Wait(500) refresh() end)

RegisterNUICallback('loaded', function(_, done)
    refresh()
    loaded = true
    done('ok')
end)

-- ------------------------------------------------------------------ opening the input

CreateThread(function()
    SetTextChatEnabled(false)
    SetNuiFocus(false)

    while true do
        Wait(0)
        local held = IsControlPressed(0, OPEN_KEY)

        if held and not typing then
            typing, opening = true, true
            page('ON_OPEN')
        elseif opening and not held then
            -- focus is taken once the key is up, or the key press would be typed into the box
            SetNuiFocus(true, true)
            opening = false
        end

        if loaded then
            local hide = IsScreenFadedOut() or IsPauseMenuActive()
            if hide ~= covered then
                covered = hide
                page('ON_SCREEN_STATE_CHANGE', { shouldHide = hide })
            end
        end
    end
end)

-- jrs_core hides parts of the HUD while the input is open
exports('isChatOpen', function() return typing == true end)

CreateThread(function()
    local reported = false
    while true do
        Wait(100)
        if typing ~= reported then
            reported = typing
            TriggerEvent('jrs_chat:client:focusChanged', reported)
        end
    end
end)
