-----------------------------------------------------------------------------------------------
-- context menus + input dialogs on the JRS menu / JRS inputs (same API the rest of the script uses)
-- def = { id, title, subtitle?, menu?, onBack?, options = { { title, description?, event?, args?, arrow?, disabled? } } }
-----------------------------------------------------------------------------------------------
local registeredContexts = {}

function OpenContext(def)
    if def and def.id then registeredContexts[def.id] = def end
end

function ShowContext(id)
    local def = registeredContexts[id]
    if not def then return end
    local elements = {}
    for i, o in ipairs(def.options or {}) do
        elements[#elements + 1] = { label = o.title or '', value = i, desc = o.description or '' }
    end
    JRS.OpenMenu('jrs_goldclaim_' .. id, def.title or '', def.subtitle or '', elements, function(el, menu)
        local option = def.options[el.value]
        if not option or not option.event or option.disabled then return end
        menu.close()
        TriggerEvent(option.event, option.args)
    end, function()
        if def.menu then ShowContext(def.menu) end
        if def.onBack then def.onBack() end
    end)
end

function HideContext()
    JRS.CloseMenu()
end

-- fields = { { label, type = 'input'|'number', default?, min?, max?, maxLength? } } ; callback(values | nil)
function OpenInputDialog(title, fields, callback)
    CreateThread(function()
        local values = {}
        for i, f in ipairs(fields) do
            local v = JRS.Input(f.label or title, f.default and tostring(f.default) or '', f.type == 'number')
            if v == nil then return callback(nil) end
            values[i] = v
        end
        callback(values)
    end)
end
