local editorOpen = false
local savedLayout = {}
local layoutLoaded = false
local lastSuppressed = nil
-- Whether the server says this player may see the editor's Developer/"Export
-- Defaults" section (2026-09-05) - set from jrs_core:hud:applyLayout, fail
-- closed (false) until the server actually confirms it.
local canExportDefaults = false

-- Suppression is owned by client/hud_gate.lua: it merges the blockers scripts
-- register when their UI opens with the automatic UI detection (NUI focus,
-- menu state-bag flags, pause menu, map, death) and drives the jrs_metabolism
-- HUD from the same decision. Use /corehud and /hudgate to inspect it live.
local function hasExternalHudBlocker()
    return type(JrsHudGate) == 'table'
        and type(JrsHudGate.IsBlocked) == 'function'
        and JrsHudGate.IsBlocked() == true
end

-- Chat holds NUI focus while typing; it must never hide the HUD.
local function isChatOpenForHud()
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isChatOpen == true then
        return true
    end
    if GetResourceState('jrs_chat') == 'started' then
        local ok, open = pcall(function() return exports['jrs_chat']:isChatOpen() end)
        if ok and open == true then return true end
    end
    return false
end

local function setGateEditorOpen(state)
    if type(JrsHudGate) == 'table' and type(JrsHudGate.SetEditorOpen) == 'function' then
        JrsHudGate.SetEditorOpen(state == true)
    end
end

-- RDR2's base-game "info card" popups (Compendium/Survivalist/etc. award
-- toasts with a "Hold [key] for details" prompt) are not a JRS script; they
-- come from the story-mode stat/award system that still runs under RedM.
-- Disabling this HUD context suppresses those cards entirely.
local INFO_CARD_HUD_CTX = GetHashKey('HUD_CTX_INFO_CARD')
local function suppressBaseGameAwardCards()
    Citizen.InvokeNative(0x8BC7C1F929D07BF3, INFO_CARD_HUD_CTX)
end

local function isCharacterReady()
    if not LocalPlayer or not LocalPlayer.state then return false end
    return LocalPlayer.state.CharacterReady == true or LocalPlayer.state.jrsCharacterReady == true
end

local function isPlayerDead()
    if LocalPlayer and LocalPlayer.state then
        local s = LocalPlayer.state
        if s.jrsIncapacitated == true or s.isDead == true or s.dead == true or s.downed == true then
            return true
        end
    end
    if GetResourceState('jrs_doctors') == 'started' then
        local ok, res = pcall(function()
            return exports['jrs_doctors']:IsDeathScreenActive() or exports['jrs_doctors']:IsDead() or exports['jrs_doctors']:IsDowned()
        end)
        if ok and res == true then return true end
    end
    local ped = PlayerPedId()
    return ped == 0 or IsEntityDead(ped) or GetEntityHealth(ped) <= 0
end

local function notify(message)
    TriggerEvent('jrsCore:notify', 'HUD EDITOR', tostring(message or ''), 'placeholder', 3500)
end

local function setEditorOpen(value)
    editorOpen = value == true
    print(('^3[DEBUG:editcorehud]^7 setEditorOpen called => editorOpen=%s (v2.2.2)'):format(tostring(editorOpen)))
    -- Tell the gate first, otherwise the NUI focus the editor needs would be
    -- read as "a menu is open" and hide the HUD the player is editing.
    print('^3[DEBUG:editcorehud]^7 calling setGateEditorOpen...')
    setGateEditorOpen(editorOpen)
    print(('^3[DEBUG:editcorehud]^7 calling SetNuiFocus(%s, %s)'):format(tostring(editorOpen), tostring(editorOpen)))
    SetNuiFocus(editorOpen, editorOpen)
    print('^3[DEBUG:editcorehud]^7 SetNuiFocus done')
end

local function setHudSuppressed(suppressed, force)
    suppressed = suppressed == true
    if not force and lastSuppressed == suppressed then return end
    lastSuppressed = suppressed

    if editorOpen and (isPlayerDead() or not isCharacterReady()) then
        print(('^1[DEBUG:editcorehud]^7 editor CLOSED by death or character unload (v2.2.3) - char=%s dead=%s'):format(
            tostring(isCharacterReady()), tostring(isPlayerDead())))
        setEditorOpen(false)
        SendNUIMessage({ action = 'hudEditor:forceClose' })
    end

    SendNUIMessage({
        action = 'hud:setSuppressed',
        suppressed = suppressed,
    })
end

local function requestLayout()
    if not isCharacterReady() then return end
    TriggerServerEvent('jrs_core:hud:requestLayout')
end

RegisterNetEvent('jrs_core:hud:applyLayout', function(layout, charId, isExportAllowed)
    if not isCharacterReady() then return end

    local activeCharId = LocalPlayer.state.CharacterId
    if charId ~= nil and tostring(charId) ~= tostring(activeCharId) then return end

    savedLayout = type(layout) == 'table' and layout or {}
    layoutLoaded = true
    canExportDefaults = isExportAllowed == true
    SendNUIMessage({ action = 'hud:applyLayout', layout = savedLayout })
    TriggerEvent('jrs_core:crosshair:updateSettings', savedLayout.crosshair)
end)

RegisterNetEvent('jrs_core:client:characterReady', function()
    layoutLoaded = false
    setHudSuppressed(isPlayerDead(), true)
    requestLayout()
end)

RegisterNetEvent('jrs_core:client:characterUnloaded', function()
    savedLayout = {}
    layoutLoaded = false
    setHudSuppressed(true, true)
    SendNUIMessage({ action = 'hud:applyLayout', layout = {} })
    TriggerEvent('jrs_core:crosshair:updateSettings', nil)
end)

-- Cross-HUD hand-off (Config.HudEditor.link). The button is only offered when
-- the config allows it AND the target resource is actually running, so a server
-- that does not ship the other HUD never sees a button that leads nowhere.
local function hudEditorLink()
    local link = Config.HudEditor and Config.HudEditor.link
    if type(link) ~= 'table' or link.enabled ~= true then return nil end

    local resource = tostring(link.resource or '')
    if resource == '' or GetResourceState(resource) ~= 'started' then return nil end

    return {
        enabled = true,
        label = tostring(link.label or 'Other HUD'),
        hint = tostring(link.hint or ''),
    }
end

-- focusTab lets another part of this same resource (e.g. client/crosshair.lua's
-- /crosshair shortcut) open the editor straight to a specific rail tab instead
-- of always landing on General. nil/omitted keeps the old default.
local function openHudEditor(focusTab)
    print('^3[DEBUG:editcorehud]^7 openHudEditor called')
    if not Config.HudEditor or Config.HudEditor.enabled ~= true then
        print('^3[DEBUG:editcorehud]^7 STOPPED: HudEditor disabled in config')
        return false
    end
    if not isCharacterReady() then
        print('^3[DEBUG:editcorehud]^7 STOPPED: character not ready')
        notify(_U('core_character_data_is_still_loading'))
        return false
    end
    if isPlayerDead() then
        print('^3[DEBUG:editcorehud]^7 STOPPED: player is dead')
        notify(_U('core_you_cannot_edit_the_hud_while'))
        return false
    end
    if not layoutLoaded then
        print('^3[DEBUG:editcorehud]^7 layout not loaded yet, requesting and awaiting...')
        requestLayout()
        local waited = 0
        while not layoutLoaded and waited < 1000 do
            Wait(100)
            waited = waited + 100
        end
        if not layoutLoaded then
            print('^3[DEBUG:editcorehud]^7 layout request timed out, using default layout')
            savedLayout = Config.HudDefaultLayout or {}
            layoutLoaded = true
        end
    end
    if editorOpen then
        print('^3[DEBUG:editcorehud]^7 STOPPED: editor already open')
        return false
    end

    print('^3[DEBUG:editcorehud]^7 all checks passed => calling setEditorOpen(true)')
    setEditorOpen(true)
    -- Force the HUD unsuppressed NOW, before the editor message.  The periodic
    -- loop (every ~150 ms) would do this eventually, but the hudEditor:open
    -- message arrives in the SAME frame and the NUI guard blocks when
    -- hudSuppressed is still true — causing the editor to silently not open.
    setHudSuppressed(false, true)
    print('^3[DEBUG:editcorehud]^7 sending hudEditor:open to NUI...')
    SendNUIMessage({
        action = 'hudEditor:open',
        layout = savedLayout,
        link = hudEditorLink(),
        canExportDefaults = canExportDefaults,
        crosshairEnabled = (Config.JrsCrosshair or Config.Crosshair) and (Config.JrsCrosshair or Config.Crosshair).Enabled ~= false,
        focusTab = type(focusTab) == 'string' and focusTab or nil,
    })
    print('^3[DEBUG:editcorehud]^7 SendNUIMessage done => openHudEditor finished')
    return true
end

RegisterCommand((Config.HudEditor and Config.HudEditor.command) or 'editcorehud', function()
    openHudEditor()
end, false)

-- The entry point jrs_metabolism's editor calls to hand over to this one.
-- A plain client event rather than an export: an export on a stopped resource
-- raises, an event on a stopped resource is simply never handled.
AddEventHandler('jrs_core:hud:openEditor', function()
    if editorOpen then return end
    openHudEditor()
end)

-- Same entry point, but jumps straight to a given rail tab (used by
-- client/crosshair.lua's /crosshair shortcut to land on "Crosshair" directly).
AddEventHandler('jrs_core:hud:openEditorTab', function(tab)
    if editorOpen then return end
    openHudEditor(tab)
end)

RegisterNUICallback('hudEditorSave', function(data, cb)
    print('^3[DEBUG:editcorehud]^7 closed by NUI callback: hudEditorSave')
    local layout = type(data) == 'table' and data.layout or nil
    if editorOpen and isCharacterReady() and not isPlayerDead() and type(layout) == 'table' then
        savedLayout = layout
        layoutLoaded = true
        TriggerServerEvent('jrs_core:hud:saveLayout', layout)
        TriggerEvent('jrs_core:crosshair:updateSettings', savedLayout.crosshair)
        notify(_U('core_hud_settings_saved_for_this_character'))
    end
    setEditorOpen(false)
    cb({ ok = true })
end)

-- Export: the server decides whether this player may do it (server/hud_export.lua).
-- Does not touch savedLayout/close the editor - exporting is a side read of
-- whatever is currently laid out, not a save.
RegisterNUICallback('hudEditorExport', function(data, cb)
    local layout = type(data) == 'table' and data.layout or nil
    if editorOpen and type(layout) == 'table' then
        TriggerServerEvent('jrs_core:hud:exportDefaults', layout)
    end
    cb({ ok = true })
end)

-- The server has already applied the exported layout straight into the live
-- config.lua by the time this arrives (server/hud_export.lua) - this only
-- hands the same text to the NUI so html/hud-export-clipboard.js can put it
-- on the OS clipboard too. No console print (2026-09-06, explicit request).
RegisterNetEvent('jrs_core:client:hudExportReady', function(body)
    if type(body) ~= 'string' or body == '' then return end
    SendNUIMessage({ action = 'hudExport:copy', text = body })
end)

RegisterNUICallback('hudEditorCancel', function(_, cb)
    print('^3[DEBUG:editcorehud]^7 closed by NUI callback: hudEditorCancel')
    setEditorOpen(false)
    cb({ ok = true })
end)

-- Same save path as hudEditorSave, then hand the player straight to the other
-- HUD's editor. Saving first is deliberate: the button is a way to carry on
-- editing, not a way to discard what was just moved.
RegisterNUICallback('hudEditorSwitch', function(data, cb)
    print('^3[DEBUG:editcorehud]^7 closed by NUI callback: hudEditorSwitch')
    local layout = type(data) == 'table' and data.layout or nil
    if editorOpen and isCharacterReady() and not isPlayerDead() and type(layout) == 'table' then
        savedLayout = layout
        layoutLoaded = true
        TriggerServerEvent('jrs_core:hud:saveLayout', layout)
        TriggerEvent('jrs_core:crosshair:updateSettings', savedLayout.crosshair)
    end
    setEditorOpen(false)
    cb({ ok = true })

    local link = Config.HudEditor and Config.HudEditor.link
    if type(link) ~= 'table' or link.enabled ~= true then return end

    local resource = tostring(link.resource or '')
    local event = tostring(link.event or '')
    if event == '' then return end
    if resource ~= '' and GetResourceState(resource) ~= 'started' then
        notify((_U('core_is_not_running')):format(resource))
        return
    end

    -- One frame of daylight so this page has actually released NUI focus
    -- before the other editor asks for it; taking focus while it is still
    -- held leaves the player with a cursor and no keyboard.
    CreateThread(function()
        Wait(100)
        TriggerEvent(event)
    end)
end)

local function shouldSuppressHud()
    if editorOpen then
        return not isCharacterReady() or isPlayerDead()
    end
    return not Config.Hud.enabled
        or not isCharacterReady()
        or isPlayerDead()
        or IsPauseMenuActive()
        or (hasExternalHudBlocker() and not isChatOpenForHud())
end

-- React the moment the gate flips instead of waiting for the next poll, so the
-- HUD is already gone the instant a script UI opens.
AddEventHandler('jrs_hud:gateChanged', function()
    setHudSuppressed(shouldSuppressHud(), false)
end)

-- Diagnostic: one line a moment after chat opens, so "the HUD hides when I
-- open chat" can be traced to its exact cause instead of guessed at (F8).
AddEventHandler('jrs_hud:chat', function(state)
    if state ~= true or not (Config and Config.HudDebug) then return end
    CreateThread(function()
        Wait(400)
        print(('^3[jrs_core:hud]^7 chat open (v%s): suppress=%s gateBlocked=%s charReady=%s dead=%s pause=%s editor=%s'):format(
            tostring(GetResourceMetadata(GetCurrentResourceName(), 'version', 0)),
            tostring(shouldSuppressHud()), tostring(hasExternalHudBlocker()), tostring(isCharacterReady()),
            tostring(isPlayerDead()), tostring(IsPauseMenuActive()), tostring(editorOpen)))
    end)
end)

-- A restart mid-session can send the first hud:setSuppressed before this NUI
-- page has attached its message listener, silently losing it (see main.js).
-- Once the page confirms it is actually ready, force a fresh, guaranteed send.
RegisterNUICallback('jrsCoreHudNuiReady', function(_, cb)
    setHudSuppressed(shouldSuppressHud(), true)
    cb('ok')
end)

CreateThread(function()
    Wait(500)
    setHudSuppressed(shouldSuppressHud(), true)
    if isCharacterReady() then
        layoutLoaded = false
        requestLayout()
    end
    suppressBaseGameAwardCards()

    -- setHudSuppressed skips a send when the state has not changed, so if a
    -- single NUI message is ever dropped the page and Lua disagree forever and
    -- the HUD would stay hidden. Re-send the real state unconditionally every
    -- few seconds: whatever happens, the HUD is back within one interval.
    local interval = tonumber(Config.HudEditor and Config.HudEditor.visibilityCheckInterval) or 150
    local resyncEvery = math.max(1, math.floor(5000 / interval))
    local ticks = 0

    while true do
        ticks = ticks + 1
        local force = ticks >= resyncEvery
        if force then ticks = 0 end

        setHudSuppressed(shouldSuppressHud(), force)
        suppressBaseGameAwardCards()
        Wait(interval)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if editorOpen then SetNuiFocus(false, false) end
end)

-- /hudgate only reports the central gate's own blockers. The compact HUD's
-- suppression also depends on a few things the gate does not know about
-- (character-ready state, Config.Hud.enabled, pause menu), so this prints
-- every input to that decision in one shot.
RegisterCommand('corehud', function()
    print(('^3[jrs_core:hud]^7 currently suppressed: %s (last sent to NUI: %s)'):format(
        tostring(shouldSuppressHud()), tostring(lastSuppressed)
    ))
    print(('^3[jrs_core:hud]^7 Config.Hud.enabled=%s  isCharacterReady=%s  isPlayerDead=%s  IsPauseMenuActive=%s  hasExternalHudBlocker=%s'):format(
        tostring(Config.Hud.enabled), tostring(isCharacterReady()), tostring(isPlayerDead()),
        tostring(IsPauseMenuActive()), tostring(hasExternalHudBlocker())
    ))
    print(('^3[jrs_core:hud]^7 LocalPlayer.state.CharacterReady=%s'):format(
        tostring(LocalPlayer and LocalPlayer.state and LocalPlayer.state.CharacterReady)
    ))
    print(('^3[jrs_core:hud]^7 gate: %s'):format(
        (type(JrsHudGate) == 'table' and JrsHudGate.Describe and JrsHudGate.Describe()) or 'n/a (old hud_gate.lua still loaded - restart jrs_core)'
    ))
end, false)
