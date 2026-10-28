-- ===================================================================
-- JRS CORE | Native Menu High-Level API (Client)
-- Copyright (C) 2026 JRS TEAM | All Rights Reserved
-- ===================================================================

JRSMenu = JRSMenu or {}

--- Opens a clean native JRS menu.
--- @param options table Options containing title, subtext, elements, etc.
--- @param onSelect function Callback when an item is selected: `onSelect(data, menu)`
--- @param onClose function Callback when the menu is closed: `onClose(menu)`
--- @param onChange function Callback when an item value changes: `onChange(data, menu)`
function JRSMenu.Open(options, onSelect, onClose, onChange)
    options = type(options) == 'table' and options or {}
    local menuId = options.id or ('menu_' .. GetGameTimer())
    local title = options.title or 'Menu'
    local subtext = options.subtext or options.subtitle or ''
    local elements = type(options.elements) == 'table' and options.elements or {}
    local align = options.align or 'top-left'

    if not JRSMenuAPI or not JRSMenuAPI.Open then
        return nil, 'menu_engine_not_ready'
    end

    local data = {
        title = title,
        subtext = subtext,
        align = align,
        elements = elements
    }

    return JRSMenuAPI.Open('default', GetCurrentResourceName(), menuId, data, onSelect, onClose, onChange, onClose)
end

function JRSMenu.Close(menuId)
    if JRSMenuAPI and JRSMenuAPI.Close then
        return JRSMenuAPI.Close('default', GetCurrentResourceName(), menuId)
    end
end

function JRSMenu.CloseAll()
    if JRSMenuAPI and JRSMenuAPI.CloseAll then
        JRSMenuAPI.CloseAll()
    end
end

function JRSMenu.IsOpen(menuId)
    if JRSMenuAPI and JRSMenuAPI.IsOpen then
        return JRSMenuAPI.IsOpen('default', GetCurrentResourceName(), menuId)
    end
    return false
end

-- Client Exports
exports('OpenMenu', JRSMenu.Open)
exports('CloseMenu', JRSMenu.Close)
exports('CloseAllMenus', JRSMenu.CloseAll)
exports('IsMenuOpen', JRSMenu.IsOpen)
