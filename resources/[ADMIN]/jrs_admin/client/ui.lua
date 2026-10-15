-- jrs_admin | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- Resource-local mouse menu. The existing action callbacks stay in Lua.
AdminUI = {}
AdminMenuData = {}
local owner = GetCurrentResourceName()
local active, lastClosed, input, busy = nil, nil, nil, false
local menus = {}
local serial = 0
local focused = false
local sections = {
    {id='administration', key='administration', permission='admin_menu', open='Admin'},
    {id='boost', key='booster', permission='boosters_menu', open='Boost'},
    {id='database', key='database', permission='database_menu', open='DataBase'},
    {id='teleport', key='teleport', permission='teleport_menu', open='Teleport'},
    {id='devtools', key='devTools', permission='devtools_menu', open='OpenDevTools'},
}
local sectionNames = {Admin='administration', Boost='boost', DataBase='database', Teleport='teleport', OpenDevTools='devtools'}

local function sectionOf(menu)
    local seen = {}
    while menu and not seen[menu.name] do
        seen[menu.name] = true
        if sectionNames[menu.name] then return sectionNames[menu.name] end
        menu = menus[menu.data.lastmenu]
    end
    return 'home'
end


-- Local artwork keys are independent of the selected UI language.
local sectionIcons = {home='home', administration='badge', boost='health', database='records', teleport='compass', devtools='tools'}
local actionIcons = {
    administration='badge', boost='health', database='records', teleport='compass', devtools='tools',
    players='badge', actions='tools', offline='records', view='records', search='binoculars',
    simpleaction='badge', advancedaction='badge', trollactions='tools',
    spectate='binoculars', freeze='badge', revive='health', heal='health', respawn='health',
    ['goto']='compass', goback='compass', sendback='compass', bring='compass',
    kick='badge', ban='badge', unban='badge', unwhitelist='badge', setjob='records', setgroup='badge',
    killplayer='weapon', invisplayer='binoculars', lightningstrikeplayer='tools', setplayeronfire='tools',
    tptoheaven='compass', ragdollplayer='badge', drainplayerstam='health', cuffplayer='badge', temphighplayer='health',
    delhorse='horse', delwagon='wagon', delwagonradius='wagon', getcoords='compass', announce='records',
    v2='compass', v3='compass', v4='compass', heading='compass', bans='badge', whites='badge',
    god='badge', noclip='compass', goldcores='health', infiniteammo='ammo',
    spawnwagon='wagon', spawnhorse='horse', selfheal='health', selfrevive='health', invisibility='binoculars',
    give='inventory', remove='inventory', inventory='inventory', addItem='inventory', addWeapon='weapon',
    addMoneygold='money', addHorse='horse', addWagon='wagon', showinventory='inventory',
    clearmoney='money', cleargold='gold', clearitems='inventory', clearweapons='weapon',
    pedlist='badge', spawnped='badge', wagonlist='wagon', delobject='tools', imap='compass',
    scenario='tools', interiorid='home', print='records', del='tools', devlaser='tools',
    autotpm='compass', tpm='compass', tptocoords='compass', tptoplayer='compass',
    admingoback='compass', bringplayer='compass', tptoguarma='compass',
    report='records', requeststaff='badge', showinfo='records', commands='records', menu='badge',
    scoreboard='badge', new='records', bug='tools', rules='records', cheating='badge', hideui='binoculars', cancelanim='tools',
}
local menuIcons = {
    PlayerList='badge', OpenOnePlayerMenu='badge', DatabasePlayers='badge', ScoreBoard='badge', SpawnPeds='badge',
    AdminReports='records', RequestStaff='records', OpenCommands='records', ShowOwnInfo='records', OpenInventory='inventory',
}

local function iconOf(menu, element)
    return actionIcons[element.value] or menuIcons[menu.name] or sectionIcons[sectionOf(menu)] or 'badge'
end

local function language() return JrsLang.Current() end
local function notify(key)
    TriggerEvent('jrs:TipRight', Translation.Current().Notify[key] or key, 4000)
end

local function focus(state)
    if state == focused then return true end
    if state then
        local ok, acquired = pcall(function()
            return exports.jrs_core:AcquireUI(owner, { focus = true, cursor = true, manageFocus = false, kind = 'admin' })
        end)
        if not ok or acquired ~= true then notify('uiBusy'); return false end
    else
        pcall(function() exports.jrs_core:ReleaseUI(owner, { manageFocus = false }) end)
    end
    focused = state
    Inmenu = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
    return true
end

local function unavailable(menu, element)
    if element.disabled then return true end
    if menu.name == 'GivePlayers' and element.value == 'addWagon' then
        local resource = Config.Integrations.wagonResource
        return resource == '' or GetResourceState(resource) ~= 'started'
    end
    if menu.name == 'GivePlayers' and element.value == 'addHorse' then
        local resource = Config.Integrations.horseResource
        return resource == '' or GetResourceState(resource) ~= 'started'
    end
    if menu.name == 'OpenDevTools' and element.value == 'imap' then
        return GetResourceState('jrs_imapviewtool') ~= 'started'
    end
    if menu.name == 'OpenUsersMenu' and element.value == 'menu' then
        return GetResourceState('jrs_walkanim') ~= 'started'
    end
    return false
end

function AdminUI.Render()
    if not active and not input then return end
    local payload = { action = 'admin:open', language = language(), token = serial, busy = busy }
    if active then
        payload.name = active.name
        payload.section = sectionOf(active)
        if menus.OpenMenu then
            payload.navigation = {}
            local options = Translation.Current().Menus.MainMenuOptions
            for _, section in ipairs(sections) do
                payload.navigation[#payload.navigation + 1] = {id=section.id, label=options[section.key], desc=options[section.key .. '_desc']}
            end
        end
        payload.title = Translation.RenderText(active.data.title, language())
        payload.subtitle = Translation.RenderText(active.data.subtext, language())
        payload.canBack = active.data.lastmenu ~= nil
        payload.elements = {}
        for i, element in ipairs(active.data.elements) do
            local disabled = unavailable(active, element)
            payload.elements[#payload.elements + 1] = {
                index = i, icon = iconOf(active, element), label = Translation.RenderText(type(element.label) == 'function' and element.label() or element.label, language()),
                desc = disabled and not element.disabled and Translation.Current().Notify.integrationMissing or Translation.RenderText(element.desc, language()),
                disabled = disabled,
            }
        end
    end
    if input then
        local data = input.data
        payload.input = {
            title = Translation.RenderText(data.attributes.inputHeader, language()),
            placeholder = Translation.RenderText(data.placeholder, language()),
            button = Translation.RenderText(data.button, language()),
            multiline = data.inputType == 'textarea',
            type = data.attributes.type == 'number' and 'number' or 'text',
            pattern = data.attributes.pattern, help = Translation.RenderText(data.attributes.title, language()),
        }
    end
    SendNUIMessage(payload)
end

local function display(menu)
    if not focus(true) then return false end
    active = menu
    serial = serial + 1
    AdminUI.Render()
    return true
end

function AdminMenuData.Open(typeName, namespace, name, data, submit, cancel)
    data.elements = data.elements or {}
    if data.lastmenu and lastClosed and lastClosed.name ~= name then data.lastmenu = lastClosed.name end
    local menu = { name = name, data = data, submit = submit, cancel = cancel }
    menu.close = function()
        -- Old callbacks can finish after a newer menu/input opened.
        if active ~= menu then return end
        lastClosed = active
        active = nil
        if not input then focus(false); SendNUIMessage({ action = 'admin:close' }) end
    end
    menu.update = function(query, updates)
        for _, row in ipairs(data.elements) do
            local matches = true
            for key, value in pairs(query) do if row[key] ~= value then matches = false end end
            if matches then for key, value in pairs(updates) do row[key] = value end end
        end
    end
    menu.refresh = function() if active == menu then AdminUI.Render() end end
    menu.setElement = function(index, key, value)
        if data.elements[index] then data.elements[index][key] = value end
    end
    menus[name] = menu
    if name == 'menuapi' then menus.OpenMenu = menu end
    display(menu)
    return menu
end

function AdminMenuData.CloseAll()
    lastClosed = active or lastClosed
    active = nil
    if not input then focus(false); SendNUIMessage({ action = 'admin:close' }) end
end

function AdminUI.Close()
    active, input, lastClosed, busy = nil, nil, nil, false
    menus = {}
    serial = serial + 1
    focus(false)
    SendNUIMessage({ action = 'admin:close' })
end

local function run(callback)
    busy = true
    AdminUI.Render()
    CreateThread(function()
        local ok, err = pcall(callback)
        busy = false
        if not ok then
            print(('[jrs_admin] action failed: %s'):format(tostring(err)))
            notify('actionFailed')
        end
        AdminUI.Render()
    end)
end

function AdminInput(data, callback)
    if type(data) == 'string' then
        local ok, decoded = pcall(json.decode, data)
        if not ok then return end
        data = decoded
    end
    if type(data) ~= 'table' or type(callback) ~= 'function' then return end
    if not focus(true) then return end
    data.attributes = data.attributes or {}
    input = { data = data, callback = callback, previous = active or lastClosed }
    active = active or lastClosed
    serial = serial + 1
    AdminUI.Render()
end

function AdminSimpleInput(button, placeholder, callback)
    AdminInput(Inputs('input', button, placeholder, placeholder, 'number', '', '[0-9]{1,5}'), callback)
end

RegisterNUICallback('adminSelect', function(data, cb)
    local index = tonumber(data.index)
    local menu = active
    local row = menu and index and index == math.floor(index) and menu.data.elements[index]
    if busy or input or data.token ~= serial or not row or unavailable(menu, row) then return cb({ ok = false }) end
    cb({ ok = true })
    run(function() if menu.submit then menu.submit({ current = row }, menu) end end)
end)

RegisterNUICallback('adminBack', function(data, cb)
    cb({ ok = true })
    if busy or input or not active or data.token ~= serial then return end
    local previous = menus[active.data.lastmenu]
    if previous then display(previous) else AdminUI.Close() end
end)

RegisterNUICallback('adminNavigate', function(data, cb)
    if busy or input or not active or not menus.OpenMenu or data.token ~= serial then return cb({ok=false}) end
    local destination
    for _, section in ipairs(sections) do if data.section == section.id then destination = section end end
    if data.section ~= 'home' and not destination then return cb({ok=false}) end
    cb({ok=true})
    run(function()
        if not IsAdminAllowed('open_menu') then return end
        if not destination then display(menus.OpenMenu); return end
        if not IsAdminAllowed(destination.permission) then return end
        active = nil
        lastClosed = menus.OpenMenu
        _G[destination.open]()
    end)
end)

RegisterNUICallback('adminClose', function(data, cb)
    cb({ ok = true })
    if data.token == serial then AdminUI.Close() end
end)

RegisterNUICallback('adminInput', function(data, cb)
    if not input or data.token ~= serial then return cb({ ok = false }) end
    local current = input
    local value = type(data.value) == 'string' and data.value or ''
    if #value > 2000 then return cb({ ok = false }) end
    input = nil
    active = current.previous
    serial = serial + 1
    cb({ ok = true })
    if data.cancelled == true then
        if active then display(active) else AdminUI.Close() end
        return
    end
    if value == '' then
        if active then display(active) else AdminUI.Close() end
        return
    end
    run(function() current.callback(value) end)
    if not active and not input then AdminUI.Close() end
end)

RegisterNUICallback('adminReady', function(_, cb)
    cb({ ok = true })
    JrsPushLanguageToNUI()
    AdminUI.Render()
end)

AddEventHandler('jrs_core:language:changed', function() AdminUI.Render() end)
RegisterNetEvent('jrs_core:client:characterUnloaded', function() AdminUI.Close() end)
AddEventHandler('onResourceStop', function(resource)
    if resource == owner or resource == 'jrs_core' then AdminUI.Close() end
end)

function AdminLoadModel(model)
    local hash = type(model) == 'number' and model or joaat(tostring(model or ''))
    if not IsModelValid(hash) or not IsModelInCdimage(hash) then notify('invalidModel'); return nil end
    RequestModel(hash, false)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(hash) then notify('invalidModel'); return nil end
    return hash
end

function AdminWaitEntity(entity)
    local deadline = GetGameTimer() + 5000
    while entity ~= 0 and not DoesEntityExist(entity) and GetGameTimer() < deadline do Wait(10) end
    return entity ~= 0 and DoesEntityExist(entity)
end
