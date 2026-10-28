-- JRS Menu Export (Native JRS Core)
local function menuData()
    local menu = JRSMenuAPI
    if type(menu) == 'table' then
        menu.IsInputActive = menu.IsInputActive or function() return false end
        menu.RegisterControls = menu.RegisterControls or function() end
        menu.UnregisterControls = menu.UnregisterControls or function() end
    end
    return menu
end

exports('GetMenuData', menuData)
exports('GetMenuAPI', menuData)

CreateThread(function()
    local wasOpen = false
    while true do
        local open = JRSMenuAPI and JRSMenuAPI.IsAnyOpen and JRSMenuAPI.IsAnyOpen() == true or false
        if open ~= wasOpen then
            wasOpen = open
            TriggerEvent(open and 'jrs_core:menu:opened' or 'jrs_core:menu:closed')
        end
        Wait(open and 100 or 250)
    end
end)
