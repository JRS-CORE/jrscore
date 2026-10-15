-- small JRS helpers the MDT client uses (notifications, confirm dialogs, context menus)
local contexts = {}

function MDTNotify(d)
    if type(d) ~= 'table' then return end
    local text = d.description and d.description ~= '' and d.description or d.title
    JRS.Notify(text or '', d.duration or 5000)
end

-- returns 'confirm' or 'cancel'
function MDTConfirm(d)
    local p = promise.new()
    local labels = d.labels or {}
    JRS.OpenMenu('jrs_mdt_confirm', d.header or '', d.content or '', {
        { label = labels.confirm or 'Confirm', value = 'confirm', desc = '' },
        { label = labels.cancel or 'Cancel', value = 'cancel', desc = '' },
    }, function(el, menu)
        menu.close()
        p:resolve(el.value)
    end, function() p:resolve('cancel') end)
    return Citizen.Await(p)
end

function MDTRegisterContext(def)
    if def and def.id then contexts[def.id] = def end
end

function MDTShowContext(id)
    local def = contexts[id]
    if not def then return end
    local elements = {}
    for i, o in ipairs(def.options or {}) do
        elements[#elements + 1] = { label = o.title or '', value = i, desc = o.description or '' }
    end
    JRS.OpenMenu('jrs_mdt_' .. id, def.title or '', '', elements, function(el, menu)
        local o = def.options[el.value]
        if not o then return end
        menu.close()
        if o.onSelect then o.onSelect() elseif o.event then TriggerEvent(o.event, o.args) end
    end)
end

RegisterNetEvent('jrs_mdt:client:runJail', function(target, minutes)
    ExecuteCommand(('jail %d %d'):format(tonumber(target) or 0, math.floor(tonumber(minutes) or 0)))
end)
