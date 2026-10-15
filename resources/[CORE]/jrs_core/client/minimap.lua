-- JRS - native RedM minimap mode controller

local INPUT_SELECT_RADAR_MODE = 0x0F39B3D4
local INPUT_REGULAR_RADAR     = 0x51AA7A35
local INPUT_EXPAND_RADAR      = 0xCF0B11DE
local INPUT_DISABLE_RADAR     = 0x70CBD78D

local NATIVE_SET_CONTROL_VALUE_NEXT_FRAME = 0xE8A25867FBA3B05E
local NATIVE_DISPLAY_RADAR                 = 0x1B3DA717B9AFF828
local NATIVE_DISABLE_CONTROL_ACTION         = 0xFE99B66D079CF6BC

local MODE_CONTROLS = {
    small = INPUT_REGULAR_RADAR,
    medium = INPUT_EXPAND_RADAR,
    hidden = INPUT_DISABLE_RADAR,
}

local applyingMode = false
local lastAppliedMode = nil
local applyGeneration = 0
local isRadarSuppressed = false

local function debugPrint(message)
    if Config.MiniMap and Config.MiniMap.debug then
        print(("^3[jrs_core:minimap]^7 %s"):format(message))
    end
end

local function getSettings()
    local settings = Config.MiniMap
    if type(settings) ~= "table" then
        return nil
    end
    return settings
end

local function normalizeMode(mode)
    mode = string.lower(tostring(mode or "small"))
    if MODE_CONTROLS[mode] then
        return mode
    end

    debugPrint(("Invalid mode '%s'; falling back to 'small'."):format(mode))
    return "small"
end

local function displayRadar(toggle)
    Citizen.InvokeNative(NATIVE_DISPLAY_RADAR, toggle == true)
end

local function pressControl(action, frames)
    frames = tonumber(frames) or 4
    if frames < 1 then frames = 1 end

    for _ = 1, frames do
        Citizen.InvokeNative(NATIVE_SET_CONTROL_VALUE_NEXT_FRAME, 0, action, 1.0)
        Wait(0)
    end
end

local function applyMiniMapMode(mode, force)
    if isRadarSuppressed then
        displayRadar(false)
        return false
    end

    local settings = getSettings()
    if not settings or settings.enabled ~= true then
        return false
    end

    mode = normalizeMode(mode or settings.mode)
    if not force and lastAppliedMode == mode then
        return true
    end

    applyingMode = true

    -- DISPLAY_RADAR is kept separate so the hidden option remains reliable
    -- even if another script previously changed radar visibility.
    if mode == "hidden" then
        displayRadar(true)
        Wait(0)
        pressControl(INPUT_SELECT_RADAR_MODE, 3)
        Wait(50)
        pressControl(INPUT_DISABLE_RADAR, 4)
        Wait(0)
        displayRadar(false)
    else
        displayRadar(true)
        Wait(0)
        pressControl(INPUT_SELECT_RADAR_MODE, 3)
        Wait(50)
        pressControl(MODE_CONTROLS[mode], 4)
    end

    lastAppliedMode = mode
    applyingMode = false
    debugPrint(("Applied mode: %s"):format(mode))
    return true
end

local function scheduleApply(delay)
    local settings = getSettings()
    if not settings or settings.enabled ~= true then
        return
    end

    applyGeneration = applyGeneration + 1
    local generation = applyGeneration

    CreateThread(function()
        Wait(math.max(0, tonumber(delay) or tonumber(settings.applyDelay) or 1500))
        if generation ~= applyGeneration then return end
        if isRadarSuppressed then return end
        applyMiniMapMode(settings.mode, true)
    end)
end

-- Apply on core/resource start for reconnects and resource restarts.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    scheduleApply(tonumber((Config.MiniMap or {}).applyDelay) or 1500)
end)

-- Re-apply after the character is actually ready/spawned.
RegisterNetEvent('jrs_core:client:characterReady', function()
    scheduleApply()
end)

RegisterNetEvent('jrs:isPlayerReady', function()
    scheduleApply()
end)

RegisterNetEvent('jrs:isPlayerready', function()
    scheduleApply()
end)

-- If requested, block only the radar-mode selector itself. We intentionally
-- do not disable the individual C/X/Z/V actions globally because they may be
-- used by normal gameplay outside the radar selector context.
CreateThread(function()
    while true do
        local settings = getSettings()
        if settings and settings.enabled == true and settings.lockMode == true and not applyingMode then
            Citizen.InvokeNative(NATIVE_DISABLE_CONTROL_ACTION, 0, INPUT_SELECT_RADAR_MODE, false)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

local function setRadarSuppressed(state)
    local suppressed = state == true
    if isRadarSuppressed == suppressed then return end
    isRadarSuppressed = suppressed

    if isRadarSuppressed then
        displayRadar(false)
        debugPrint("Radar suppressed due to active UI / HUD gate")
    else
        debugPrint("Radar restored after UI closed")
        displayRadar(true)
        local settings = getSettings()
        if settings and settings.enabled == true then
            if normalizeMode(settings.mode) ~= "hidden" then
                if lastAppliedMode ~= normalizeMode(settings.mode) then
                    applyMiniMapMode(settings.mode, false)
                end
            else
                displayRadar(false)
            end
        end
    end
end

RegisterNetEvent('jrs_hud:gateChanged')
AddEventHandler('jrs_hud:gateChanged', function(blocked)
    setRadarSuppressed(blocked == true)
end)

AddStateBagChangeHandler('jrsHudBlocked', nil, function(bagName, key, value)
    if bagName == ('player:%s'):format(GetPlayerServerId(PlayerId())) then
        setRadarSuppressed(value == true)
    end
end)

AddStateBagChangeHandler('uiOpen', nil, function(bagName, key, value)
    if bagName == ('player:%s'):format(GetPlayerServerId(PlayerId())) then
        setRadarSuppressed(value == true)
    end
end)

local function isMountedOrInVehicle()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsPedOnMount(ped) then return true end
    if IsPedInAnyVehicle(ped, false) then return true end
    return false
end

-- Hidden mode is enforced at a low frequency so another resource cannot
-- permanently re-enable the radar, without running a heavy per-frame loop.
-- Also ensures radar remains hidden while any UI is open, but automatically
-- stays active whenever the player is riding a horse or inside a vehicle/wagon.
CreateThread(function()
    local wasMounted = false
    while true do
        local settings = getSettings()
        local allowVehicleRadar = settings and (settings.showOnMountOrVehicle ~= false)
        local mounted = allowVehicleRadar and isMountedOrInVehicle()

        if isRadarSuppressed then
            displayRadar(false)
            Wait(100)
        elseif mounted then
            if not wasMounted or lastAppliedMode == "hidden" then
                wasMounted = true
                displayRadar(true)
                local vMode = (settings and settings.vehicleMode) or "small"
                applyMiniMapMode(vMode, true)
            else
                displayRadar(true)
            end
            Wait(400)
        else
            if wasMounted then
                wasMounted = false
                local targetMode = (settings and settings.mode) or "hidden"
                if normalizeMode(targetMode) == "hidden" then
                    applyMiniMapMode("hidden", true)
                else
                    applyMiniMapMode(targetMode, true)
                end
            elseif (settings and settings.enabled == true and normalizeMode(settings.mode) == "hidden") then
                displayRadar(false)
                Wait(500)
            else
                Wait(1000)
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    local settings = getSettings()
    if settings and settings.restoreOnResourceStop == true then
        displayRadar(true)
    end
end)

-- Other JRS resources can request a mode at runtime without editing this file.
exports('SetMiniMapMode', function(mode)
    local settings = getSettings()
    if not settings then return false end

    settings.mode = normalizeMode(mode)
    return applyMiniMapMode(settings.mode, true)
end)

exports('GetMiniMapMode', function()
    return lastAppliedMode or normalizeMode((Config.MiniMap or {}).mode)
end)

exports('SetRadarSuppressed', setRadarSuppressed)
exports('IsRadarSuppressed', function()
    return isRadarSuppressed == true
end)
