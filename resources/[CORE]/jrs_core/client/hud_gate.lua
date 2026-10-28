-- JRS - central HUD gate
--
-- One place decides whether the player HUDs are allowed on screen. When a
-- script opens its UI, BOTH the jrs_core compact HUD and the jrs_metabolism
-- status HUD are hidden, and they come back when that UI is closed.
--
-- Other resources never have to know about the individual HUDs:
--
--     TriggerEvent('jrs_hud:busy', 'jrs_mining', true)   -- UI opened
--     TriggerEvent('jrs_hud:busy', 'jrs_mining', false)  -- UI closed
--
-- or exports.jrs_core:setHudBusy(state, name, timeoutMs).
--
-- THE HUD CAN NEVER STAY HIDDEN FOREVER. Three independent safety nets:
--   1. every blocker expires by itself after Config.HudGate.maxBlockMs,
--   2. a blocker dies with the resource that registered it,
--   3. /hudgate prints what is hiding the HUD, /hudshow force clears it.

JrsHudGate = JrsHudGate or {}

local METABOLISM_BLOCKER = 'jrs_core:gate'
local WEAPON_WHEEL_BLOCKER = 'jrs_core:weaponwheel'

local manualBlockers = {}      -- name -> { owner = resourceName|nil, expires = ms|nil }
local editorOpen = false       -- a HUD editor needs NUI focus and must stay visible
local blocked = false          -- the published gate state
local clearPendingAt = nil     -- release delay bookkeeping
local lastPublished = nil
local lastReason = nil         -- why the HUD is hidden right now (/hudgate)

local function gateConfig()
    local cfg = Config and Config.HudGate
    if type(cfg) ~= 'table' then return {} end
    return cfg
end

local function autoHideConfig()
    local auto = gateConfig().autoHide
    if type(auto) ~= 'table' then return {} end
    return auto
end

local function isEnabled()
    return gateConfig().enabled ~= false
end

local function nativeCall(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

-----------------------------------------------------------
--[[ Automatic detection ]]--
-----------------------------------------------------------

local MENU_STATE_FLAGS = {
    'invOpen', 'inventoryOpen', 'isInventoryOpen',
    'menuOpen', 'isMenuOpen',
    'nuiOpen', 'isNuiOpen',
}

local function hasMenuStateFlag()
    local state = LocalPlayer and LocalPlayer.state
    if not state then return false end

    for _, flag in ipairs(MENU_STATE_FLAGS) do
        if state[flag] == true then return true, flag end
    end

    return false
end

local function isPlayerDead(ped)
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
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsEntityDead(ped) then return true end
    if nativeCall(IsPedDeadOrDying, ped, true) == true then return true end
    if GetEntityHealth(ped) <= 0 then return true end
    return false
end

local chatFocusActive = false

local function isChatOpen()
    if chatFocusActive == true then
        return true
    end
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isChatOpen == true then
        return true
    end
    if GetResourceState('jrs_chat') == 'started' then
        local ok, active = pcall(function() return exports['jrs_chat']:isChatOpen() end)
        if ok and active == true then return true end
    end
    if GetResourceState('chat') == 'started' then
        local ok, active = pcall(function() return exports['chat']:isChatOpen() end)
        if ok and active == true then return true end
    end
    return false
end

local function isUiAppRunning(h, name)
    if type(IsUiappRunning) == "function" and type(name) == "string" and name ~= "" then
        local ok, r = pcall(IsUiappRunning, name)
        if ok and (r == 1 or r == true) then return true end
    end
    if not h or h == 0 then return false end
    if type(IsUiappRunningByHash) == "function" then
        local ok, r = pcall(IsUiappRunningByHash, h)
        if ok and (r == 1 or r == true) then return true end
    end
    if type(IsAppActive) == "function" then
        local ok, r = pcall(IsAppActive, h)
        if ok and (r == 1 or r == true) then return true end
    end
    local ok, r = pcall(Citizen.InvokeNative, 0x4E511D093A86AD49, h)
    if ok and (r == 1 or r == true) then return true end
    return false
end

-- A wheel whose native app reports "running" while TAB is NOT held is only
-- believed for a short grace period (the close animation). Past that it is a
-- stuck/false reading (a wheel app left running, or a native answering true for
-- an app that is not there) and must never hide the HUD for the whole session.
local WHEEL_STALE_AFTER_MS = 1500
local wheelRunningNotHeldSince = nil

local function isWeaponWheelActive()
    local ctrl = 0xAC4BD4F1
    local held = IsControlPressed(0, ctrl) or IsDisabledControlPressed(0, ctrl)
        or IsControlPressed(2, ctrl) or IsDisabledControlPressed(2, ctrl)
    if held then
        wheelRunningNotHeldSince = nil
        return true
    end

    if isUiAppRunning(GetHashKey("hud_quick_select"), "hud_quick_select") or isUiAppRunning(joaat("hud_quick_select"), "hud_quick_select") then
        local now = GetGameTimer()
        wheelRunningNotHeldSince = wheelRunningNotHeldSince or now
        return (now - wheelRunningNotHeldSince) < WHEEL_STALE_AFTER_MS
    end

    wheelRunningNotHeldSince = nil
    return false
end

-- Returns true (plus the reason, for /hudgate) while a script UI is on screen.
--
-- Deliberately UI only. Animations, frozen peds and scripted cameras are NOT
-- detected here: those states have no reliable "finished" signal, so a script
-- that leaves one behind would hide the HUD forever. A script that really
-- needs the HUD gone for something else asks for it explicitly through
-- jrs_hud:busy, which is time limited and released when its resource stops.
local function evaluateAuto()
    local auto = autoHideConfig()
    local ped = PlayerPedId()

    if auto.OnDeath ~= false and isPlayerDead(ped) then return true, 'death' end

    if auto.OnWeaponWheel ~= false and isWeaponWheelActive() then
        return true, 'weapon wheel'
    end

    -- HUD editors legitimately hold NUI focus while the HUD must stay visible.
    -- Chat input also holds NUI focus for typing, but HUD should remain visible.
    if not editorOpen then
        if auto.OnNuiFocus ~= false and nativeCall(IsNuiFocused) == true then
            if not isChatOpen() then
                return true, 'script ui open'
            end
        end
        if auto.OnStateBagMenu ~= false and not isChatOpen() then
            local flagged, flag = hasMenuStateFlag()
            if flagged then return true, 'script ui flag: ' .. tostring(flag) end
        end
    end

    if auto.OnPauseMenu ~= false then
        if IsPauseMenuActive() or Citizen.InvokeNative(0xB0034A223497FFCB) then return true, 'pause menu' end
        if isUiAppRunning(GetHashKey("settings_menu")) or isUiAppRunning(joaat("settings_menu")) then return true, 'settings menu' end
        if isUiAppRunning(GetHashKey("pause_menu")) or isUiAppRunning(joaat("pause_menu")) then return true, 'pause menu' end
        if GetResourceState('jrs_pausemenu') == 'started' then
            local ok, open = pcall(function() return exports['jrs_pausemenu']:IsOpen() end)
            if ok and open == true then return true, 'jrs pause menu' end
        end
    end

    if auto.OnMap ~= false then
        if isUiAppRunning(GetHashKey("map")) or isUiAppRunning(joaat("map")) or isUiAppRunning(joaat("MAP")) or isUiAppRunning(GetHashKey("MAP_APP")) then
            return true, 'map'
        end
    end

    return false, nil
end

-----------------------------------------------------------
--[[ Manual blockers ]]--
-----------------------------------------------------------

local function pruneBlockers()
    local now = GetGameTimer()

    for name, entry in pairs(manualBlockers) do
        if entry.expires and now >= entry.expires then
            manualBlockers[name] = nil
            if Config and Config.HudDebug then
                print(('^3[jrs_core:hudgate]^7 blocker ^1%s^7 expired without being released - HUD restored.'):format(name))
            end
        elseif entry.owner and GetResourceState(entry.owner) ~= 'started' then
            -- The resource that hid the HUD is gone; never keep the HUD hidden for it.
            manualBlockers[name] = nil
        end
    end
end

local function hasManualBlocker()
    for _, entry in pairs(manualBlockers) do
        if entry then return true end
    end
    return false
end

-----------------------------------------------------------
--[[ Publishing ]]--
-----------------------------------------------------------

local function publish(force)
    if force ~= true and lastPublished == blocked then return end
    lastPublished = blocked

    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('jrsHudBlocked', blocked, false)
        LocalPlayer.state:set('uiOpen', blocked, false)
    end

    -- Keep native HUD subsystem enabled so game notifications and feeds are never suppressed
    pcall(DisplayHud, true)

    -- jrs_metabolism keeps its own blocker table; one named blocker from the
    -- gate cannot fight with its inventory/death/bath blockers.
    TriggerEvent('jrs_metabolism:setHudBlocked', blocked, METABOLISM_BLOCKER)

    -- Anything else that wants to follow the HUD state (custom HUDs, etc.).
    TriggerEvent('jrs_hud:gateChanged', blocked)

    -- Notify the unified notification toast system so toasts can reposition
    -- (e.g. bottom-center) when menus are open and not be covered!
    if type(JRSNotifySetMenuOpen) == 'function' then
        JRSNotifySetMenuOpen(blocked, 'hud_gate')
    else
        TriggerEvent('jrs_notify:setMenuOpen', blocked, 'hud_gate')
    end

    if Config and Config.HudDebug then
        print(('^3[jrs_core:hudgate]^7 HUD %s'):format(blocked and 'hidden' or 'shown'))
    end
end

local function evaluate(force)
    if not isEnabled() then
        blocked = false
        clearPendingAt = nil
        publish(force)
        return
    end

    pruneBlockers()

    local busy, reason = false, nil
    if editorOpen then
        -- A HUD editor is open: the HUD it edits must stay on screen no matter
        -- what a script blocker or the NUI-focus detection says (the editor
        -- itself holds NUI focus). Only death hides it.
        if isPlayerDead(PlayerPedId()) then busy, reason = true, 'death' end
    elseif isChatOpen() then
        -- Typing in chat must never take the HUD away, whatever else is
        -- registered (stale blockers, script-UI flags, NUI focus held by chat
        -- itself). Only death hides it, exactly like an open HUD editor.
        if isPlayerDead(PlayerPedId()) then busy, reason = true, 'death' end
    elseif hasManualBlocker() then
        busy, reason = true, 'script blocker'
    else
        busy, reason = evaluateAuto()
    end
    local prevReason = lastReason
    lastReason = busy and reason or nil

    if busy then
        clearPendingAt = nil
        if not blocked then
            blocked = true
            publish(true)
        end
        return
    end

    -- If weapon wheel just closed, or chat is open while the HUD was previously blocked, unblock immediately without delay
    if (prevReason == 'weapon wheel' or isChatOpen()) and blocked then
        blocked = false
        clearPendingAt = nil
        publish(true)
        return
    end

    if not blocked then
        publish(force)
        return
    end

    -- Nothing is blocking any more. Wait out the short release delay so the HUD
    -- returns once the UI is really gone, instead of flashing back during a
    -- menu's close animation or between two menus opening back to back.
    -- No delay while an editor is open: the release delay used to keep the gate
    -- "blocked" for a moment after the chat/menu that launched the editor
    -- closed, and jrs_core's poll read that as "HUD hidden" and shut the editor.
    local delay = editorOpen and 0 or (tonumber(gateConfig().releaseDelayMs) or 400)
    if delay <= 0 then
        blocked = false
        clearPendingAt = nil
        publish(true)
        return
    end

    local now = GetGameTimer()
    if not clearPendingAt then
        clearPendingAt = now + delay
        return
    end

    if now >= clearPendingAt then
        blocked = false
        clearPendingAt = nil
        publish(true)
    end
end

-----------------------------------------------------------
--[[ Public API ]]--
-----------------------------------------------------------

local function setBusy(name, state, options)
    name = tostring(name or 'external')

    if state == true then
        local owner, timeout

        if type(options) == 'table' then
            owner = options.resource
            timeout = tonumber(options.timeout)
        elseif type(options) == 'number' then
            timeout = options
        elseif type(options) == 'string' then
            owner = options
        end

        if owner == nil and GetResourceState(name) == 'started' then
            owner = name
        end

        -- Every blocker gets an expiry, even when the caller does not ask for
        -- one. A script that opens its UI and never reports closing it can slow
        -- the HUD down for a minute, never remove it permanently.
        if not timeout or timeout <= 0 then
            timeout = tonumber(gateConfig().maxBlockMs) or 60000
        end

        manualBlockers[name] = {
            owner = owner,
            expires = (timeout > 0) and (GetGameTimer() + timeout) or nil,
        }
    else
        manualBlockers[name] = nil
    end

    evaluate(false)
end

function JrsHudGate.SetBusy(name, state, options)
    setBusy(name, state, options)
end

function JrsHudGate.IsBlocked()
    return blocked == true
end

function JrsHudGate.GetReason()
    return lastReason
end

function JrsHudGate.IsWeaponWheel()
    return lastReason == 'weapon wheel' or isWeaponWheelActive()
end

-- Why the gate is blocked right now (for diagnostics): reason + blocker names.
function JrsHudGate.Describe()
    local names = {}
    for name, entry in pairs(manualBlockers) do
        names[#names + 1] = ('%s%s'):format(name, entry.owner and (' <- ' .. entry.owner) or '')
    end
    return ('blocked=%s reason=%s editorOpen=%s blockers=[%s]'):format(
        tostring(blocked), tostring(lastReason), tostring(editorOpen), table.concat(names, ', '))
end

-- Opening an editor is a deliberate player action, so any script blocker still
-- registered at that moment is stale (a UI that never reported closing). Drop
-- them, otherwise they would hide the HUD again the moment the editor closes.
local function setEditorState(state)
    editorOpen = state == true
    if editorOpen then
        manualBlockers = {}
        clearPendingAt = nil
    end
    evaluate(false)
end

function JrsHudGate.SetEditorOpen(state)
    setEditorState(state)
end

function JrsHudGate.Clear()
    manualBlockers = {}
    evaluate(false)
end

-- exports.jrs_core:setHudBusy(state, name, timeoutMs)
exports('setHudBusy', function(state, name, timeout)
    setBusy(name, state == true, timeout)
end)

-- exports.jrs_core:isHudBlocked()
exports('isHudBlocked', function()
    return blocked == true
end)

-- TriggerEvent('jrs_hud:busy', 'my_resource', true|false, timeoutMs)
RegisterNetEvent('jrs_hud:busy')
AddEventHandler('jrs_hud:busy', function(name, state, timeout)
    setBusy(name, state == true, timeout)
end)

-- A HUD editor (jrs_core /editcorehud, jrs_metabolism /edithud) needs NUI focus
-- while the HUD it edits must stay on screen.
RegisterNetEvent('jrs_hud:editor')
AddEventHandler('jrs_hud:editor', function(state)
    setEditorState(state)
end)

exports('setHudEditorOpen', function(state)
    setEditorState(state)
end)

-- Backwards compatible with the old per-HUD blocker events/exports.
RegisterNetEvent('jrs_core:setHudBlocked')
AddEventHandler('jrs_core:setHudBlocked', function(state, name)
    setBusy(name, state == true)
end)

exports('setHudBlocked', function(state, name)
    setBusy(name, state == true)
end)

-- Evaluate HUD gate immediately when chat opens or closes
local function setChatGateState(state)
    chatFocusActive = state == true
    evaluate(false)
end

AddEventHandler('jrs_chat:client:focusChanged', setChatGateState)
RegisterNetEvent('jrs_chat:client:focusChanged', setChatGateState)
AddEventHandler('jrs_hud:chat', setChatGateState)
RegisterNetEvent('jrs_hud:chat', setChatGateState)
AddEventHandler('chat:focusChanged', setChatGateState)
RegisterNetEvent('chat:focusChanged', setChatGateState)

AddStateBagChangeHandler('isChatOpen', nil, function(bagName, key, value)
    chatFocusActive = value == true
    evaluate(false)
end)

-- Prints the live gate state and the exact reason the HUD is hidden, so a
-- script that keeps the HUD down can be identified instead of guessed at.
RegisterCommand('hudgate', function()
    local busy, reason = evaluateAuto()

    print(('^3[jrs_core:hudgate]^7 HUD is currently %s (%s)'):format(
        blocked and '^1HIDDEN^7' or '^2VISIBLE^7',
        lastReason or 'nothing blocking'
    ))
    print(('^3[jrs_core:hudgate]^7 live detection: %s (%s)'):format(tostring(busy), reason or 'none'))

    local names = {}
    for name, entry in pairs(manualBlockers) do
        names[#names + 1] = ('%s%s'):format(name, entry.owner and (' <- ' .. entry.owner) or '')
    end

    if #names == 0 then
        print('^3[jrs_core:hudgate]^7 script blockers: none')
    else
        print(('^3[jrs_core:hudgate]^7 script blockers: %s'):format(table.concat(names, ', ')))
    end
end, false)

-- Escape hatch: drops every script blocker and brings the HUD straight back.
local function forceClearHudBlockers()
    manualBlockers = {}
    clearPendingAt = nil
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('jrsHudBlocked', false, false)
        LocalPlayer.state:set('uiOpen', false, false)
    end
    blocked = false
    publish(true)
    pcall(DisplayHud, true)
    print('^3[jrs_core:hudgate]^7 all script blockers cleared - HUD restored.')
end

RegisterCommand('hudshow', forceClearHudBlockers, false)
RegisterCommand('showhud', forceClearHudBlockers, false)

-- Central bath integration so both HUDs hide cleanly during bathing
RegisterNetEvent('jrs_metabolism:bathing:setActive')
AddEventHandler('jrs_metabolism:bathing:setActive', function(state)
    setBusy('jrs_bathing', state == true)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Do not leave the metabolism HUD hidden behind us.
        TriggerEvent('jrs_metabolism:setHudBlocked', false, METABOLISM_BLOCKER)
        TriggerEvent('jrs_metabolism:setHudBlocked', false, WEAPON_WHEEL_BLOCKER)
        return
    end

    local changed = false
    for name, entry in pairs(manualBlockers) do
        if name == resourceName or (entry and entry.owner == resourceName) then
            manualBlockers[name] = nil
            changed = true
        end
    end

    if resourceName == 'jrs_chat' or resourceName == 'chat' then
        chatFocusActive = false
        changed = true
    end

    if changed then evaluate(false) end
end)

CreateThread(function()
    Wait(500)
    evaluate(true)

    while true do
        evaluate(false)
        Wait(math.max(50, tonumber(gateConfig().checkInterval) or 100))
    end
end)

-----------------------------------------------------------
--[[ Weapon wheel: instant reaction watcher ]]--
-----------------------------------------------------------
-- Reacts on the exact frame TAB is pressed or released so HUD hides and returns instantly
CreateThread(function()
    while true do
        if isEnabled() and autoHideConfig().OnWeaponWheel ~= false then
            local ctrl = 0xAC4BD4F1
            if IsControlJustPressed(0, ctrl) or IsControlJustPressed(2, ctrl)
                or IsControlJustReleased(0, ctrl) or IsControlJustReleased(2, ctrl) then
                evaluate(false)
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

