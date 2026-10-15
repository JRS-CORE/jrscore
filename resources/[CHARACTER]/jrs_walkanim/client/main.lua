-- jrs_walkanim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_walkanim | client
-- /walkanim opens a list of walk styles; the pick is applied at once and saved by the server.
-- The saved style comes back after character selection through "jrs_walkanim:Server:setwalk".

local Core = exports.jrs_core:GetCore()
local Menu = exports.jrs_core:GetMenuData()

local NONE = 'noanim'
local current                      -- style name we applied last (game name)

local function T(key)
    local set = Config.Text[Config.Language] or Config.Text.en
    return set[key] or Config.Text.en[key] or key
end

-- ------------------------------------------------------------------ applying a style

local function clear()
    if current then
        Citizen.InvokeNative(0xA6F67BEC53379A32, PlayerPedId(), current)   -- remove movement style
        current = nil
    end
end

local function apply(style)
    clear()
    if style and style ~= NONE then
        Citizen.InvokeNative(0xCB9401F918CB0F75, PlayerPedId(), style, true, -1)  -- add movement style
        current = style
    end
end

-- saved style for this character, sent by the server
RegisterNetEvent('jrs_walkanim:Server:setwalk', function(style)
    apply(style)
end)

-- chosen from the menu (or by another resource): apply and save
AddEventHandler('jrs_walkanim:Client:setAnim', function(style)
    apply(style)
    TriggerServerEvent('jrs_walkanim:setwalk', style or NONE)
end)

-- ------------------------------------------------------------------ menu

local open = false

local function closeMenu(menu)
    if menu then menu.close() end
    open = false
    DisplayRadar(true)
end

local function openMenu()
    if open then return end
    open = true
    DisplayRadar(false)
    Menu.CloseAll()

    local rows = {}
    for _, style in ipairs(Config.Styles) do
        rows[#rows + 1] = { label = T(style.key), value = style.name, desc = T('pick') }
    end
    rows[#rows + 1] = { label = T('reset'), value = NONE, desc = T('resetHint') }

    Menu.Open('default', GetCurrentResourceName(), 'walkstyles', {
        title = T('title'),
        subtext = T('subtitle'),
        align = Config.MenuAlign,
        elements = rows,
    }, function(data)
        if data.current and data.current.value then
            TriggerEvent('jrs_walkanim:Client:setAnim', data.current.value)
        end
    end, function(_, menu)
        closeMenu(menu)
    end)
end

TriggerEvent('chat:addSuggestion', '/' .. Config.MenuCommand, T('suggestMenu'), {})
RegisterCommand(Config.MenuCommand, openMenu, false)

-- the admin / user menus open it through this event
AddEventHandler('jrs_walkanim:OpenMenu', openMenu)

-- ------------------------------------------------------------------ slow walk

local slow = false

TriggerEvent('chat:addSuggestion', '/' .. Config.SlowCommand, T('suggestSlow'), {})
RegisterCommand(Config.SlowCommand, function(_, args)
    if slow then
        slow = false
        Core.NotifyObjective(T('slowOff'), 5000)
        return
    end

    local ratio = tonumber(args[1])
    if not ratio or ratio <= 0 then
        Core.NotifyObjective(T('slowNeedsValue'), 5000)
        return
    end

    slow = true
    Core.NotifyObjective(T('slowOn'), 5000)
    ratio = math.min(ratio, 3.0)
    CreateThread(function()
        while slow do
            SetPedMaxMoveBlendRatio(PlayerPedId(), ratio)
            Wait(0)
        end
        SetPedMaxMoveBlendRatio(PlayerPedId(), 3.0)
    end)
end, false)
