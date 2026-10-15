-- JRS menu export (the menu lives in jrs_core/modules/menu).
--   local MenuData = exports.jrs_core:GetMenuData()
--   MenuData.Open('default', GetCurrentResourceName(), 'my_menu', { title = 'Title', align = 'top-left', elements = {...} },
--       function(data, menu) end,  -- submit
--       function(data, menu) menu.close() end) -- cancel
-- Old scripts can keep using exports.jrs_menu:GetMenuData() (jrs_core provides 'jrs_menu').
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

-- local events other scripts listen to (lib prompts pause while a menu is open)
CreateThread(function()
    local wasOpen = false
    while true do
        local open = JRSMenuAPI and JRSMenuAPI.IsAnyOpen and JRSMenuAPI.IsAnyOpen() == true or false
        if open ~= wasOpen then
            wasOpen = open
            TriggerEvent(open and 'jrs_menu:openmenu' or 'jrs_menu:closemenu')
        end
        Wait(open and 100 or 250)
    end
end)
