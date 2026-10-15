local closed = false
local closing = false
local selectorSkipReady = false
local selectorSkipDeadline = 0
local selectorSkipGeneration = 0

-- Character must know whether the manual loadscreen is actually still visible.
-- The resource itself remains 'started' after ShutdownLoadingScreenNui(), so
-- GetResourceState() alone is not a valid cursor-handoff test.
exports('IsLoadingScreenActive', function()
    return closed ~= true
end)

local function debugPrint(message)
    if Config.Debug then
-- REMOVED-PRINT:         print(('[jrs_loadingscreen] %s'):format(message))
    end
end

local function isResourceStarted(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function isCharacterFlowActive()
    return isResourceStarted(Config.JRS.characterResource)
end

local function notifyCharacterSkipAvailable()
    if not selectorSkipReady or closed then return end
    if not isCharacterFlowActive() then return end

    local seconds = math.max(1, tonumber(Config.CharacterSkip and Config.CharacterSkip.autoCloseSeconds) or 60)
    local label = tostring((Config.CharacterSkip and Config.CharacterSkip.buttonText) or 'SKIP')

    TriggerEvent(Config.JRS.characterSkipShowEvent, {
        label = label,
        seconds = seconds,
        deadline = selectorSkipDeadline,
    })
end

local function shutdownNow(reason)
    if closed then return end

    local selectorWasWaiting = selectorSkipReady == true
    selectorSkipReady = false
    selectorSkipDeadline = 0
    selectorSkipGeneration = selectorSkipGeneration + 1

    closed = true
    closing = false

    local closeReason = reason or 'unknown'
    debugPrint(('closing loading screen (%s)'):format(closeReason))

    -- Do not force Character NUI focus while loadscreen_cursor is still active.
    -- jrs_character already prepared its selector focus without moving the mouse;
    -- the final ownership latch happens after ShutdownLoadingScreenNui().

    -- The loading resource never owns regular NUI focus and therefore never
    -- hides/releases the mouse. Character Selection owns the cursor completely.
    ShutdownLoadingScreenNui()
    ShutdownLoadingScreen()

    if Config.JRS.characterDismissedEvent
        and isCharacterFlowActive() then
        TriggerEvent(Config.JRS.characterDismissedEvent, closeReason)
    end
end

local function scheduleShutdown(reason, delayMs)
    if closed or closing then return end
    closing = true

    CreateThread(function()
        local delay = math.max(0, tonumber(delayMs) or 0)
        if delay > 0 then Wait(delay) end
        shutdownNow(reason)
    end)
end

local function isCoreCharacterReady()
    if not isResourceStarted(Config.JRS.coreResource) then return false end

    local ok, ready = pcall(function()
        return exports[Config.JRS.coreResource]:IsCharacterReady()
    end)

    return ok and ready == true
end

-- Character Selection is fully prepared. jrs_character owns the visible SKIP
-- control because its fullscreen NUI is guaranteed to sit above the Cfx
-- loadscreen surface on RedM. jrs_loadingscreen remains the timer/close owner.
-- 2.8.0: handoff events are local (jrs_character uses TriggerEvent), so they
-- are AddEventHandler - nothing on the network can close or skip the screen.
AddEventHandler(Config.JRS.characterSelectionReadyEvent, function(reason)
    if closed then
        if Config.JRS.characterDismissedEvent and isCharacterFlowActive() then
            TriggerEvent(Config.JRS.characterDismissedEvent, 'already_closed')
        end
        return
    end

    selectorSkipReady = true
    selectorSkipGeneration = selectorSkipGeneration + 1
    local generation = selectorSkipGeneration

    -- Default JRS flow: as soon as Character Selector confirms it has painted,
    -- shut the manual loadscreen down and hand the cursor to jrs_character.
    -- Keeping two cursor-owning CEF surfaces alive at once is what caused the
    -- missing/resized mouse issue. The old delayed SKIP flow is still available
    -- only when holdAfterSelectorReady is explicitly enabled.
    if not Config.CharacterSkip or Config.CharacterSkip.holdAfterSelectorReady ~= true then
        shutdownNow(reason or 'character_selector_ready')
        return
    end

    if Config.CharacterSkip.enabled ~= true then
        shutdownNow(reason or 'character_selector_ready_skip_disabled')
        return
    end

    local seconds = math.max(1, tonumber(Config.CharacterSkip.autoCloseSeconds) or 60)
    selectorSkipDeadline = GetGameTimer() + math.floor(seconds * 1000)

    debugPrint(('character selector ready; SKIP available; auto close in %ss'):format(seconds))
    notifyCharacterSkipAvailable()

    -- Send the SKIP presentation once. Re-sending this event used to make
    -- jrs_character re-claim mouse focus every 250 ms, which caused the pointer
    -- to resize and repeatedly snap toward the centre of the screen.

    CreateThread(function()
        while not closed
            and selectorSkipReady
            and generation == selectorSkipGeneration do
            local remaining = selectorSkipDeadline - GetGameTimer()
            if remaining <= 0 then
                shutdownNow('character_selector_auto_timeout')
                return
            end
            Wait(math.min(250, math.max(25, remaining)))
        end
    end)
end)

-- Reliable click path: the SKIP button is in jrs_character NUI, which posts to
-- jrs_character Lua, then emits this local event. No fetch() is performed from
-- the special loadscreen document.
AddEventHandler('jrs_loadingscreen:client:skip', function(reason)
    if not selectorSkipReady or closed then return end
    shutdownNow(reason or 'character_selector_skip')
end)

-- Primary close signal from jrs_character (creator path / forced recovery).
AddEventHandler(Config.JRS.characterCloseEvent, function(reason)
    shutdownNow(reason or 'jrs_character_ui_ready')
end)

RegisterNetEvent('jrs_loadingscreen:close', function(reason)
    shutdownNow(reason or 'external_close')
end)

AddEventHandler('playerSpawned', function()
    debugPrint(('playerSpawned received; characterFlow=%s'):format(tostring(isCharacterFlowActive())))

    if not isCharacterFlowActive() then
        scheduleShutdown('standalone_initial_player_spawned', Config.JRS.closeAfterInitialSpawnMs)
    end
end)

RegisterNetEvent(Config.JRS.coreReadyEvent, function()
    if not isCharacterFlowActive() then
        scheduleShutdown('standalone_jrs_core_ready_backup', Config.JRS.readyBackupDelayMs)
    end
end)

RegisterNetEvent(Config.JRS.selectedCharacterEvent, function()
    if selectorSkipReady then return end
    scheduleShutdown('selected_character_backup', 0)
end)

RegisterNetEvent(Config.JRS.finalReadyEvent, function()
    if selectorSkipReady then return end
    scheduleShutdown('jrs_character_ready_backup', 0)
end)

RegisterNetEvent(Config.JRS.legacyReadyEvent, function()
    if not isCharacterFlowActive() then
        scheduleShutdown('standalone_legacy_ready_backup', Config.JRS.readyBackupDelayMs)
    end
end)

if Config.JRS.legacyReadyEventLower and Config.JRS.legacyReadyEventLower ~= Config.JRS.legacyReadyEvent then
    RegisterNetEvent(Config.JRS.legacyReadyEventLower, function()
        if not isCharacterFlowActive() then
            scheduleShutdown('standalone_legacy_ready_lower_backup', Config.JRS.readyBackupDelayMs)
        end
    end)
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    if isCoreCharacterReady() then
        scheduleShutdown('resource_started_while_character_ready', 0)
    end
end)

CreateThread(function()
    local waitMs = isCharacterFlowActive()
        and math.max(15000, tonumber(Config.JRS.characterUiFallbackMs) or 90000)
        or math.max(5000, tonumber(Config.JRS.standaloneWatchdogMs) or 30000)

    Wait(waitMs)
    if closed or closing or selectorSkipReady then return end

    if isCharacterFlowActive() then
        -- This only fires when jrs_character never confirmed the Character
        -- Selector/Creator UI as painted within the fallback window - a real
        -- stall (heavy join load, a stuck DB round trip, etc.), not a normal
        -- close. Always print it (not gated by Config.Debug like the other
        -- reasons) because closing the loadscreen here exposes whatever raw,
        -- unhidden state the player's ped is currently in, which reads as
        -- "spawned wrong" with no explanation in the console otherwise.
        print('^1[jrs_loadingscreen] character_ui_watchdog_fallback fired after '
            .. tostring(waitMs) .. 'ms - jrs_character never signalled selector/creator ready.^7')
        scheduleShutdown('character_ui_watchdog_fallback', 0)
    else
        scheduleShutdown('standalone_watchdog_fallback', 0)
    end
end)

if Config.Dev.enabled then
    RegisterCommand(Config.Dev.forceCloseCommand, function()
        shutdownNow('dev_force_close')
    end, false)
end
