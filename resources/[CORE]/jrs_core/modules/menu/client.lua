local Menu = {}
local resourceName = GetCurrentResourceName()
local UI_OWNER = 'jrs_core:menu'

local function moduleMessage(payload)
    SendNUIMessage({ __jrsModule = 'menu', payload = payload })
end

Menu.Opened = {}
Menu.RegisteredTypes = {}

-- Mouse + keyboard: while a menu is up jrs_core holds the NUI focus (with the
-- cursor) and the page handles the keys. Another dialog (input, ext input,
-- lib dialog) may take the focus over the menu; the menu takes it back after.
local menuFocus = false

local function otherDialogOpen()
    if JRSExtInputOpen then return true end
    if JRSUI and JRSUI.GetState then
        local st = JRSUI.GetState()
        if st.focusOwner and st.focusOwner ~= UI_OWNER then return true end
    end
    return false
end

local function syncMenuFocus()
    local open = #Menu.Opened > 0
    if open then
        if not otherDialogOpen() and (not menuFocus or not IsNuiFocused()) then
            SetNuiFocus(true, true)
            menuFocus = true
        end
    elseif menuFocus then
        menuFocus = false
        if not otherDialogOpen() then SetNuiFocus(false, false) end
    end
end

local function updateUiState()
    local open = #Menu.Opened > 0
    if JRSUI then
        if open then
            local ok = JRSUI.Acquire(UI_OWNER, { focus = false, cursor = false, kind = 'menu' })
            if ok ~= true then return false end
        else
            JRSUI.Release(UI_OWNER)
        end
    else
        TriggerEvent('jrs_hud:busy', resourceName, open)
    end
    if not open then
        -- a submit often closes this menu and opens the next one right away:
        -- give it a frame before dropping the cursor so it does not flicker
        SetTimeout(60, syncMenuFocus)
    else
        syncMenuFocus()
    end
    return true
end

Menu.RegisteredTypes['default'] = {
    open = function(_, namespace, name, data)
        moduleMessage({ ac = 'open', ns = namespace, id = name, dt = data })
    end,
    close = function(_, namespace, name)
        moduleMessage({ ac = 'close', ns = namespace, id = name })
    end
}

function Menu.Open(typeName, namespace, name, data, submit, cancel, change, close)
    typeName = tostring(typeName or 'default')
    namespace = tostring(namespace or GetInvokingResource() or resourceName)
    name = tostring(name or 'menu')
    data = type(data) == 'table' and data or {}
    data.elements = type(data.elements) == 'table' and data.elements or {}

    local renderer = Menu.RegisteredTypes[typeName]
    if not renderer then return nil, 'unknown_menu_type' end
    if JRSUI then
        local busy, owner = JRSUI.IsBusy(UI_OWNER)
        if busy then return nil, 'ui_busy:' .. tostring(owner) end
    end

    -- Avoid duplicate instances with the same identity.
    Menu.Close(typeName, namespace, name)

    local inst = {
        type = typeName,
        namespace = namespace,
        name = name,
        data = data,
        submit = submit,
        cancel = cancel,
        change = change,
    }

    inst.close = function()
        renderer.close(typeName, namespace, name)
        for i = #Menu.Opened, 1, -1 do
            local item = Menu.Opened[i]
            if item == inst or (item.type == typeName and item.namespace == namespace and item.name == name) then
                table.remove(Menu.Opened, i)
            end
        end
        updateUiState()
        if close then pcall(close) end
    end

    inst.update = function(query, newData)
        query = type(query) == 'table' and query or {}
        newData = type(newData) == 'table' and newData or {}
        for i = 1, #inst.data.elements do
            local matched = true
            for k, v in pairs(query) do
                if inst.data.elements[i][k] ~= v then matched = false break end
            end
            if matched then
                for k, v in pairs(newData) do inst.data.elements[i][k] = v end
            end
        end
    end

    inst.refresh = function()
        renderer.open(typeName, namespace, name, inst.data)
    end
    inst.setElement = function(i, key, val)
        if inst.data.elements[i] then inst.data.elements[i][key] = val end
    end
    inst.setElements = function(newElements)
        inst.data.elements = type(newElements) == 'table' and newElements or {}
    end
    inst.setTitle = function(val) inst.data.title = val end
    inst.removeElement = function(query)
        query = type(query) == 'table' and query or {}
        for i = #inst.data.elements, 1, -1 do
            local matched = true
            for k, v in pairs(query) do
                if not inst.data.elements[i] or inst.data.elements[i][k] ~= v then matched = false break end
            end
            if matched then table.remove(inst.data.elements, i) end
        end
    end

    Menu.Opened[#Menu.Opened + 1] = inst
    renderer.open(typeName, namespace, name, data)
    updateUiState()
    PlaySoundFrontend('SELECT', 'RDRO_Character_Creator_Sounds', true, 0)
    return inst
end

function Menu.Close(typeName, namespace, name)
    for i = #Menu.Opened, 1, -1 do
        local item = Menu.Opened[i]
        if item and item.type == typeName and item.namespace == namespace and item.name == name then
            item.close()
            return true
        end
    end
    return false
end

function Menu.CloseAll()
    while #Menu.Opened > 0 do
        local item = Menu.Opened[#Menu.Opened]
        if item and item.close then item.close() else table.remove(Menu.Opened) end
    end
    updateUiState()
end

function Menu.GetOpened(typeName, namespace, name)
    for i = #Menu.Opened, 1, -1 do
        local item = Menu.Opened[i]
        if item and item.type == typeName and item.namespace == namespace and item.name == name then
            return item
        end
    end
end

function Menu.GetOpenedMenus() return Menu.Opened end
function Menu.IsOpen(typeName, namespace, name) return Menu.GetOpened(typeName, namespace, name) ~= nil end
function Menu.IsAnyOpen() return #Menu.Opened > 0 end
function Menu.ReOpen(old)
    if not old then return nil end
    return Menu.Open(old.type, old.namespace, old.name, old.data, old.submit, old.cancel, old.change, old.close)
end

RegisterNUICallback('jrs:select', function(data, cb)
    PlaySoundFrontend('SELECT', 'RDRO_Character_Creator_Sounds', true, 0)
    local inst = Menu.GetOpened('default', data and data._ns, data and data._id)
    if inst and inst.submit then pcall(inst.submit, data, inst) end
    if cb then cb('ok') end
end)

RegisterNUICallback('jrs:sfx', function(_, cb)
    PlaySoundFrontend('NAV_LEFT', 'PAUSE_MENU_SOUNDSET', true, 0)
    if cb then cb('ok') end
end)

RegisterNUICallback('jrs:back', function(data, cb)
    PlaySoundFrontend('SELECT', 'RDRO_Character_Creator_Sounds', true, 0)
    local inst = Menu.GetOpened('default', data and data._ns, data and data._id)
    if inst and inst.cancel then pcall(inst.cancel, data, inst) end
    if cb then cb('ok') end
end)

RegisterNUICallback('jrs:sync', function(data, cb)
    local inst = Menu.GetOpened('default', data and data._ns, data and data._id)
    if inst and type(data.elements) == 'table' then
        for i = 1, #data.elements do
            inst.setElement(i, 'value', data.elements[i].value)
            inst.setElement(i, 'selected', data.elements[i].selected == true)
        end
        if inst.change then pcall(inst.change, data, inst) end
    end
    if cb then cb('ok') end
end)

-- keep the focus while a menu is open (another dialog may have dropped it)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(#Menu.Opened > 0 and 150 or 500)
        if #Menu.Opened > 0 then syncMenuFocus() end
    end
end)

Citizen.CreateThread(function()
    local paused = false
    local queue = {}
    while true do
        Citizen.Wait(#Menu.Opened > 0 and 0 or 150)

        if #Menu.Opened > 0 then
            if IsControlJustReleased(0, 0x43DBF61F) or IsDisabledControlJustReleased(0, 0x43DBF61F) then
                moduleMessage({ ac = 'key', key = 'ENTER' })
            end
            if IsControlJustReleased(0, 0x308588E6) or IsDisabledControlJustReleased(0, 0x308588E6) then
                moduleMessage({ ac = 'key', key = 'BACKSPACE' })
            end
            if IsControlJustReleased(0, 0x911CB09E) or IsDisabledControlJustReleased(0, 0x911CB09E) then
                moduleMessage({ ac = 'key', key = 'TOP' })
            end
            if IsControlJustReleased(0, 0x4403F97F) or IsDisabledControlJustReleased(0, 0x4403F97F) then
                moduleMessage({ ac = 'key', key = 'DOWN' })
            end
            if IsControlJustReleased(0, 0xAD7FCC5B) or IsDisabledControlJustReleased(0, 0xAD7FCC5B) then
                moduleMessage({ ac = 'key', key = 'LEFT' })
            end
            if IsControlJustReleased(0, 0x65F9EC5B) or IsDisabledControlJustReleased(0, 0x65F9EC5B) then
                moduleMessage({ ac = 'key', key = 'RIGHT' })
            end

            if IsPauseMenuActive() and not paused then
                paused = true
                queue = {}
                for i = 1, #Menu.Opened do queue[#queue + 1] = Menu.Opened[i] end
                Menu.CloseAll()
            end
        elseif paused and not IsPauseMenuActive() then
            paused = false
            Citizen.Wait(250)
            local reopen = queue
            queue = {}
            for _, item in ipairs(reopen) do Menu.ReOpen(item) end
        end
    end
end)

-- Legacy event plus unified core API.
AddEventHandler('jrs_menu:getmenu', function(cb)
    if type(cb) == 'function' then cb(Menu) end
end)
JRSMenuAPI = Menu

AddEventHandler('onClientResourceStop', function(stopped)
    if stopped ~= resourceName then return end
    Menu.CloseAll()
    if menuFocus then SetNuiFocus(false, false) end
    if JRSUI then JRSUI.Release(UI_OWNER) else TriggerEvent('jrs_hud:busy', resourceName, false) end
end)
