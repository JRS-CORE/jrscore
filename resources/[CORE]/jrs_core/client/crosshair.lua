-- ============================================================================
-- JRS Crosshair - Custom Aiming Reticle
-- Built directly into jrs_core as part of the core HUD.
-- ============================================================================
--
-- Shape 0      = the game's own reticle, untouched (default).
-- Shapes 1..12 = custom NUI reticles (html/img/crosshair/crosshairN.png).
--
-- 2026-09-14: shape 1 used to double as "game default", but the editor drew
-- it as a dotted-circle image and let you tint it, so picking it (or any
-- colour on it) silently did nothing in game. Game default is now its own
-- tile (0). Saves made before that carry no `v = 2` stamp; for those a stored
-- shape 1 still means game default, so nobody's current reticle changes.

local isAimingState = false
local lastShootTime = 0
local UNARMED_HASH = GetHashKey('WEAPON_UNARMED')
local CROSSHAIR_LAYOUT_VERSION = 2
local SHAPE_COUNT = 12

local currentCrosshairSettings = { shape = 0, color = 'white' }
local isCustomActive = false
local loopErrorReported = false

local function crosshairConfig()
    return Config.JrsCrosshair or Config.Crosshair
end

local function customCrosshairEnabled()
    local cfg = crosshairConfig()
    return cfg and cfg.Enabled ~= false
end

local function debugPrint(fmt, ...)
    local cfg = crosshairConfig()
    if cfg and cfg.Debug then
        print(('[jrs_core:crosshair] ' .. fmt):format(...))
    end
end

local function notify(text)
    TriggerEvent('jrsCore:notify', _U('core_crosshair_notify_title'), tostring(text or ''), 'placeholder', 4000)
end

-- Natives are looked up at call time and guarded: an unguarded call to a
-- native this build does not expose throws inside the thread and kills the
-- reticle for the rest of the session.
local function callNative(fn, ...)
    if fn == nil then return false end
    local ok, res = pcall(fn, ...)
    if not ok then return false end
    return res == true or res == 1
end

local function setAiming(state)
    state = state == true
    if isAimingState == state then return end
    isAimingState = state
    SendNUIMessage({ action = 'jrs_crosshair:visibility', visible = isAimingState })
    debugPrint('aiming: %s', tostring(isAimingState))
end

local function restoreGameReticle()
    Citizen.InvokeNative(0x1CFB749AD4317BDE)
end

local function normalizeShape(settings)
    if type(settings) ~= 'table' then return 0 end
    local shape = math.floor(tonumber(settings.shape) or 0)
    if shape ~= shape then shape = 0 end
    if tonumber(settings.v) ~= CROSSHAIR_LAYOUT_VERSION and shape == 1 then
        shape = 0
    end
    return math.max(0, math.min(SHAPE_COUNT, shape))
end

local function updateCrosshairSettings(settings)
    currentCrosshairSettings.shape = normalizeShape(settings)
    currentCrosshairSettings.color = type(settings) == 'table' and tostring(settings.color or 'white') or 'white'

    local wasCustom = isCustomActive
    isCustomActive = currentCrosshairSettings.shape >= 1
    debugPrint('settings: shape=%s color=%s custom=%s', tostring(currentCrosshairSettings.shape),
        currentCrosshairSettings.color, tostring(isCustomActive))

    if wasCustom and not isCustomActive then
        setAiming(false)
        restoreGameReticle()
    end
end

AddEventHandler('jrs_core:crosshair:updateSettings', function(settings)
    updateCrosshairSettings(settings)
end)

-- Shortcut straight into the HUD editor's Crosshair tab.
local function openCrosshairTab()
    local cfg = crosshairConfig()
    if not cfg or cfg.EnableCommand == false then
        notify(_U('core_edit_crosshair_via_corehud'))
        return
    end
    if not customCrosshairEnabled() then
        notify(_U('core_crosshair_disabled'))
        return
    end
    TriggerEvent('jrs_core:hud:openEditorTab', 'crosshair')
end

local primaryCmd = (Config.JrsCrosshair and Config.JrsCrosshair.Command)
    or (Config.Crosshair and Config.Crosshair.Command)
    or 'jrs_crosshair'

RegisterCommand(primaryCmd, openCrosshairTab, false)

if primaryCmd ~= 'jrs_crosshair' then
    RegisterCommand('jrs_crosshair', openCrosshairTab, false)
end
if primaryCmd ~= 'crosshair' then
    RegisterCommand('crosshair', openCrosshairTab, false)
end

local TOOL_WEAPONS = {
    [GetHashKey('WEAPON_KIT_BINOCULARS')] = true,
    [GetHashKey('WEAPON_KIT_CAMERA')] = true,
    [GetHashKey('WEAPON_FISHINGROD')] = true,
    [GetHashKey('WEAPON_MELEE_LANTERN')] = true,
    [GetHashKey('WEAPON_MELEE_DAVY_LANTERN')] = true,
}

local function isArmedWithCombatWeapon(ped)
    local hasWeapon, weaponHash = GetCurrentPedWeapon(ped, true)
    if not hasWeapon or weaponHash == UNARMED_HASH or weaponHash == 0 then
        hasWeapon, weaponHash = GetCurrentPedWeapon(ped, true, 0, true)
    end
    if not hasWeapon or weaponHash == UNARMED_HASH or weaponHash == 0 then
        return false
    end
    return not TOOL_WEAPONS[weaponHash]
end

local AIM_CONTROLS = { 0xF84FA74F, 0x25066914 }          -- INPUT_AIM, INPUT_VEH_AIM
local ATTACK_CONTROLS = { 0x07CE1E61, 0x07CE1E02 }      -- INPUT_ATTACK, INPUT_ATTACK2

local function anyControlPressed(list)
    for i = 1, #list do
        if IsControlPressed(0, list[i]) or IsDisabledControlPressed(0, list[i]) then
            return true
        end
    end
    return false
end

-- One frame of the custom-reticle logic. Returns nothing; runs inside pcall.
local function customCrosshairFrame()
    local ped = PlayerPedId()
    local pid = PlayerId()

    if not DoesEntityExist(ped) or IsEntityDead(ped) or not isArmedWithCombatWeapon(ped) then
        setAiming(false)
        restoreGameReticle()
        return 'idle'
    end

    local isPressingAim = anyControlPressed(AIM_CONTROLS)
        or callNative(IsPlayerFreeAiming, pid)
        or callNative(IsPlayerTargettingAnything, pid)
        or callNative(IsPedAimingFromCover, ped)

    local isPressingAttack = anyControlPressed(ATTACK_CONTROLS)
    local isShooting = callNative(IsPedShooting, ped)
    local isWeaponReady = callNative(IsPedWeaponReadyToShoot, ped)

    local now = GetGameTimer()
    if isShooting or (isPressingAttack and isWeaponReady) then
        lastShootTime = now
    end
    -- Keep the reticle up through the shot cycle (recoil, hammer, pump).
    local isRecentlyShooting = (now - lastShootTime) < 550

    -- Hide the overlay while looking through a scope.
    local inScope = callNative(IsPlayerInScope, pid) or callNative(IsPedLookingThroughScope, ped)

    setAiming(not inScope and (isPressingAim or isShooting or isRecentlyShooting))

    -- Suppress the base game reticle/dot only while the custom one is in use.
    Citizen.InvokeNative(0x4CC5F2FC1332577F, 1058184710)
    Citizen.InvokeNative(0x4CC5F2FC1332577F, -66088566)
    Citizen.InvokeNative(0x4CC5F2FC1332577F, 0xBB47198C)
end

CreateThread(function()
    while true do
        if not customCrosshairEnabled() or not isCustomActive then
            setAiming(false)
            Wait(350)
        else
            local ok, err = pcall(customCrosshairFrame)
            if not ok then
                setAiming(false)
                if not loopErrorReported then
                    loopErrorReported = true
                    print(('^1[jrs_core:crosshair] frame error (reticle keeps running): %s^7'):format(tostring(err)))
                end
                Wait(250)
            elseif err == 'idle' then
                -- Unarmed / tool in hand: nothing to draw. Drawing a weapon takes
                -- far longer than 100ms, so there is no need to poll every frame.
                Wait(100)
            else
                Wait(0)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    restoreGameReticle()
    SendNUIMessage({ action = 'jrs_crosshair:visibility', visible = false })
end)
