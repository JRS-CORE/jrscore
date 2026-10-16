-- jrs_goldclaim | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_goldclaim | client: menus and input windows on the JRS menu and JRS input
-- A menu is described once (OpenContext) and shown later by id (ShowContext).
--   def = { id, title, subtitle?, menu? (parent id), onBack?, options = { { title, description?, event?, args?, disabled? } } }

local menus = {}

function OpenContext(def)
    if def and def.id then menus[def.id] = def end
end

function ShowContext(id)
    local def = menus[id]
    if not def then return end

    local rows = {}
    for i, option in ipairs(def.options or {}) do
        rows[i] = { label = option.title or '', value = i, desc = option.description or '' }
    end

    JRS.OpenMenu('jrs_goldclaim_' .. id, def.title or '', def.subtitle or '', rows, function(row, menu)
        local option = def.options[row.value]
        if not option or not option.event or option.disabled then return end
        menu.close()
        TriggerEvent(option.event, option.args)
    end, function()
        if def.menu then ShowContext(def.menu) end
        if def.onBack then def.onBack() end
    end)
end

function HideContext() JRS.CloseMenu() end

-- asks for every field in turn; callback gets the list of answers, or nil when one is cancelled
-- fields = { { label, type = 'input' | 'number', default? } }
function OpenInputDialog(title, fields, done)
    CreateThread(function()
        local answers = {}
        for i, field in ipairs(fields) do
            local value = JRS.Input(field.label or title, field.default and tostring(field.default) or '', field.type == 'number')
            if value == nil then return done(nil) end
            answers[i] = value
        end
        done(answers)
    end)
end
