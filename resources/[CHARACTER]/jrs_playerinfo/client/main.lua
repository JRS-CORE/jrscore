local MenuData = exports.jrs_core:GetMenuData()

TriggerEvent('chat:addSuggestion', '/' .. Config.Command, L('cmd_help'))

RegisterNetEvent('jrs_playerinfo:client:show', function(name, rows)
    MenuData.CloseAll()

    local elements = {}
    for _, row in ipairs(rows or {}) do
        elements[#elements + 1] = { label = row.label, value = row.label, desc = row.value }
    end
    if #elements == 0 then
        elements[1] = { label = L('no_data'), value = 'none', desc = '' }
    end

    MenuData.Open('default', GetCurrentResourceName(), 'jrs_playerinfo', {
        title    = L('title'),
        subtext  = name,
        align    = Config.Align,
        elements = elements,
    }, function() end, function(_, menu)
        menu.close()
    end)
end)
