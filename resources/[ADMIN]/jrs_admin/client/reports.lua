-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local T = Translation.Current()
function AdminReports()
    if not IsAdminAllowed('view_reports_menu') then return end
    local reports = JRS.Callback.TriggerAwait('jrs_admin:getReports')
    if type(reports) ~= 'table' then return end
    local elements = {}
    for i = #reports, 1, -1 do
        local report = reports[i]
        elements[#elements + 1] = {
            label = function() return ('#%d · %s · %s'):format(report.id, report.name, report.closed and T.Menus.Reports.closed or T.Menus.Reports.open) end,
            desc = tostring(report.text) .. '<br>' .. tostring(report.created), value = report.id, disabled = report.closed,
        }
    end
    if #elements == 0 then elements[1] = { label=T.Notify.reportsEmpty, value='none', disabled=true } end
    MenuData.CloseAll()
    MenuData.Open('default', GetCurrentResourceName(), 'AdminReports', {
        title=T.Menus.DefaultsMenusTitle.menuTitle, subtext=T.Menus.MainAdminOptions.viewReports, elements=elements, lastmenu='Admin',
    }, function(data)
        if type(data.current.value) ~= 'number' then return end
        local reportId = data.current.value
        local prompt = Inputs('input', T.Menus.DefaultsInputs.confirm, T.Menus.Reports.confirm, T.Menus.Reports.closeTitle, 'text', '', 'yes|no|نعم|لا')
        AdminInput(prompt, function(value)
            if value:lower() == 'yes' or value == 'نعم' then TriggerServerEvent('jrs_admin:closeReport', reportId) end
            AdminReports()
        end)
    end)
end

RegisterNetEvent('jrs_admin:clearAmmo', function()
    RemoveAllPedWeapons(PlayerPedId(), true, true)
end)
