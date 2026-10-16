-- jrs_basemenu | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local opening = false

local function money(n)
    return ('$%.2f'):format(tonumber(n) or 0)
end

local function openMenu()
    if opening then return end
    opening = true
    local info = JRS.Await('jrs_basemenu:info')
    opening = false
    if not info then return end

    local elements = {
        { label = L('name'),    value = 'info', desc = info.name },
        { label = L('job'),     value = 'info', desc = ('%s  |  %s'):format(info.job, L('grade', info.grade)) },
        { label = L('money'),   value = 'info', desc = money(info.money) },
        { label = L('gold'),    value = 'info', desc = ('%.2f'):format(tonumber(info.gold) or 0) },
        { label = L('players'), value = 'info', desc = ('%s / %s'):format(info.players, info.max) },
    }
    if GetResourceState('jrs_multijob') == 'started' then
        elements[#elements + 1] = { label = L('my_jobs'), value = 'jobs', desc = L('my_jobs_d') }
    end
    for _, link in ipairs(Config.Links or {}) do
        elements[#elements + 1] = { label = link.label, value = 'link', desc = link.text, text = link.text }
    end
    elements[#elements + 1] = { label = L('close'), value = 'close', desc = '' }

    JRS.OpenMenu('jrs_basemenu', Config.ServerName, L('subtitle', info.name, info.id), elements, function(el, menu)
        if el.value == 'jobs' then
            menu.close()
            ExecuteCommand('myjobs')
        elseif el.value == 'link' then
            JRS.Notify(('%s: %s'):format(el.label, el.text), 8000)
        elseif el.value == 'close' then
            menu.close()
        end
    end)
end

RegisterCommand(Config.Command, function() CreateThread(openMenu) end, false)
TriggerEvent('chat:addSuggestion', '/' .. Config.Command, L('cmd_help'))

if Config.Key then
    CreateThread(function()
        while true do
            Wait(0)
            if IsControlJustPressed(0, Config.Key) and not IsPauseMenuActive() then
                CreateThread(openMenu)
            end
        end
    end)
end
