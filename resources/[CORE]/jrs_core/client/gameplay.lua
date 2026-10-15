local gameplay = Config.Gameplay or {}
local PLAYER_GROUP = GetHashKey('PLAYER')
local characterReady = false
local lastPvpPed = 0
local currentPvp = gameplay.PVP ~= false
local lastPvpToggleAt = 0
local lastCombatAt = 0

-- Track entity damage to detect active combat for anti-abuse
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' then
        local victim = args[1]
        local attacker = args[2]
        local ped = PlayerPedId()
        if victim == ped or attacker == ped then
            lastCombatAt = GetGameTimer()
        end
    end
end)

local function isInCombat()
    local durationMs = (tonumber(gameplay.PVPCombatDuration) or 10) * 1000
    return (GetGameTimer() - lastCombatAt) < durationMs
end

-- PVP HUD idle fade: shared with the movement-polling thread further down so
-- an explicit state change (toggle, respawn, admin override) always wakes
-- the icon back up immediately instead of waiting on the next poll.
local pvpHudHidden = false
local pvpHudIdleSince = nil

local function wakePvpHud()
    pvpHudIdleSince = nil
    if pvpHudHidden then
        pvpHudHidden = false
        SendNUIMessage({ action = 'setPvpIdle', idle = false })
    end
end

local function applyPvp(state, silent)
    if state ~= nil then
        currentPvp = state == true
    end
    local ped = PlayerPedId()
    if ped and ped ~= 0 then
        SetPedRelationshipGroupHash(ped, PLAYER_GROUP)
    end
    NetworkSetFriendlyFireOption(currentPvp)
    SetRelationshipBetweenGroups(currentPvp and 5 or 1, PLAYER_GROUP, PLAYER_GROUP)
    lastPvpPed = ped

    -- Replicate state bag for instant access across scripts and server
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('jrsPvp', currentPvp, true)
    end

    -- Update JRS Core HUD (if enabled)
    local pvpHudCfg = gameplay.PVPHud or {}
    if pvpHudCfg.Enabled ~= false then
        SendNUIMessage({ action = 'setPvpState', enabled = currentPvp })
        wakePvpHud()
    end

    -- Native JRS Core event notification
    TriggerEvent('jrs_core:client:pvpChanged', currentPvp)
    TriggerEvent('jrs_metabolism:client:updatePvp', currentPvp)

    -- PVP ON/OFF toast removed on request; state is still shown on the HUD
    -- and broadcast via jrs_core:client:pvpChanged + the jrsPvp state bag.
end

local function togglePvp()
    if gameplay.PVPToggle == false then
        if CoreNotifications and CoreNotifications.NotifyRightTip then
            CoreNotifications.NotifyRightTip(_U('pvp_toggle_disabled'), 4000)
        end
        return currentPvp
    end

    -- Prevent toggling PVP ON while inside a safe zone
    if not currentPvp then
        local inSafeZone = false
        if GetResourceState('jrs_safezone') == 'started' then
            pcall(function()
                inSafeZone = exports['jrs_safezone']:IsSafeZoneActive()
            end)
        end
        if inSafeZone or (LocalPlayer and LocalPlayer.state and (LocalPlayer.state.safezoneBlockWeapons == true or LocalPlayer.state.inSafeZone == true)) then
            if CoreNotifications and CoreNotifications.NotifyRightTip then
                CoreNotifications.NotifyRightTip('لا يمكنك تفعيل القتال داخل المنطقة الآمنة', 4000)
            end
            return currentPvp
        end
    end

    local now = GetGameTimer()
    local cooldownMs = (tonumber(gameplay.PVPCooldown) or 5) * 1000
    if (now - lastPvpToggleAt) < cooldownMs then
        local remaining = math.ceil((cooldownMs - (now - lastPvpToggleAt)) / 1000)
        local msg = string.format(_U('pvp_cooldown'), remaining)
        if CoreNotifications and CoreNotifications.NotifyRightTip then
            CoreNotifications.NotifyRightTip(msg, 3000)
        end
        return currentPvp
    end

    -- Prevent disabling PVP while in combat
    if currentPvp and gameplay.PVPBlockInCombat ~= false and isInCombat() then
        if CoreNotifications and CoreNotifications.NotifyRightTip then
            CoreNotifications.NotifyRightTip(_U('pvp_combat_blocked'), 4000)
        end
        return currentPvp
    end

    lastPvpToggleAt = now
    applyPvp(not currentPvp, false)
    return currentPvp
end

-- ===================================================================
-- JRS PVP Network Events & Command (Pure JRS)
-- ===================================================================
RegisterNetEvent('jrs_core:client:setPvp', function(state, silent)
    applyPvp(state == true, silent == true)
end)

RegisterNetEvent('jrs_core:client:togglePvp', function()
    togglePvp()
end)

local pvpCommand = gameplay.CommandOnOffPVP or 'pvp'
RegisterCommand(pvpCommand, function()
    togglePvp()
end, false)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. pvpCommand, _U('pvp_command_desc'))
end)

local function applyAbilities()
    Citizen.InvokeNative(0xA63FCAD3A6FEC6D2, PlayerId(), gameplay.EagleEye ~= false)
    Citizen.InvokeNative(0x95EE1DEE1DCD9070, PlayerId(), gameplay.DeadEye == true)
end

local function applyRechargeOverrides()
    local health = gameplay.HealthRecharge
    if health and health.Override then
        local multiplier = tonumber(health.Multiplier) or 0.0
        Citizen.InvokeNative(0x8899C244EBCF70DE, PlayerId(), multiplier)
    end

    local stamina = gameplay.StaminaRecharge
    if stamina and stamina.Override then
        local multiplier = tonumber(stamina.Multiplier) or 0.0
        Citizen.InvokeNative(0xFECA17CF3343694B, PlayerId(), multiplier)
    end
end

local function applyCoreVisibility()
    if gameplay.HidePlayerCores then
        for index = 0, 5 do
            Citizen.InvokeNative(0xC116E6DF68DCE667, index, 2)
        end
    end

    if gameplay.HideHorseCores then
        for index = 6, 11 do
            Citizen.InvokeNative(0xC116E6DF68DCE667, index, 2)
        end
    end

    if gameplay.HideDeadEyeCoreOnly then
        Citizen.InvokeNative(0xC116E6DF68DCE667, 2, 2)
        Citizen.InvokeNative(0xC116E6DF68DCE667, 3, 2)
    end
end

local function applyStaticSettings()
    applyPvp()
    applyAbilities()
    applyRechargeOverrides()
    applyCoreVisibility()
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(250)
        applyStaticSettings()
    end)
end)

local function onCharacterLoaded()
    characterReady = true
    applyStaticSettings()
end

RegisterNetEvent('jrs_core:client:characterReady', onCharacterLoaded)
RegisterNetEvent('jrs_core:client:characterLoaded', onCharacterLoaded)
RegisterNetEvent('jrs:SelectedCharacter', onCharacterLoaded)

RegisterNetEvent('jrs_core:client:characterUnloaded', function()
    characterReady = false
end)

-- Combat flags and aim behavior. The loop sleeps when no per-frame setting is enabled.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local disableF4ItemWheel = gameplay.DisableF4ItemWheel == true
        local needsFrameLoop = gameplay.DisableAutoAim == true or disableF4ItemWheel

        local isReady = characterReady or (LocalPlayer and LocalPlayer.state and (LocalPlayer.state.CharacterReady == true or LocalPlayer.state.jrsCharacterReady == true))
        -- A respawn replaces the player ped. Reapply PVP so the configured
        -- relationship is never lost after death or character switching.
        if isReady and ped ~= 0 and ped ~= lastPvpPed then
            applyPvp()
        end

        if gameplay.DisableHeadshots then
            SetPedConfigFlag(ped, 263, true)
        end

        if gameplay.DisableGrapples then
            SetPedConfigFlag(ped, 169, true)
        end

        if gameplay.DisableMeleeTakeDowns then
            SetPedConfigFlag(ped, 340, true)
        end

        if gameplay.DisableAutoAim then
            Citizen.InvokeNative(0xD66A941F401E7302, 3)
            Citizen.InvokeNative(0x19B4F71703902238, 3)
        end

        -- F4 is the native keyboard shortcut for the item/quick-select wheel.
        -- Disable the F4 control itself instead of the wheel action so TAB remains untouched.
        if disableF4ItemWheel then
            local f4Control = tonumber(gameplay.F4ControlHash) or 0x1F6D95E5
            Citizen.InvokeNative(0xFE99B66D079CF6BC, 0, f4Control, true) -- DISABLE_CONTROL_ACTION
        end

        if characterReady then
            applyRechargeOverrides()
        end

        Wait(needsFrameLoop and 0 or 1000)
    end
end)

-- Fades the PVP HUD icon out once the player has stood still for a few
-- seconds (same idea as the compass) and brings it back the instant they
-- move again. Polls at 500ms since sub-second precision isn't needed here.
local pvpHud = gameplay.PVPHud or {}
if pvpHud.Enabled ~= false and pvpHud.IdleFade ~= false then
    CreateThread(function()
        local idleMs = math.max(1, tonumber(pvpHud.IdleFadeSeconds) or 5) * 1000
        local moveThreshold = 0.15 -- metres between polls counted as "moved"
        local lastCoords = nil

        while true do
            Wait(500)
            if characterReady then
                local ped = PlayerPedId()
                if ped ~= 0 then
                    local coords = GetEntityCoords(ped)
                    local moved = lastCoords == nil or #(coords - lastCoords) > moveThreshold
                    lastCoords = coords

                    if moved then
                        wakePvpHud()
                    else
                        pvpHudIdleSince = pvpHudIdleSince or GetGameTimer()
                        if not pvpHudHidden and (GetGameTimer() - pvpHudIdleSince) >= idleMs then
                            pvpHudHidden = true
                            SendNUIMessage({ action = 'setPvpIdle', idle = true })
                        end
                    end
                end
            end
        end
    end)
end

local mercyKill = gameplay.MercyKill or {}
if mercyKill.Enabled then
    CreateThread(function()
        local interval = math.max(1000, tonumber(mercyKill.RefreshIntervalMs) or 30000)
        while true do
            if type(SetPlayerCanMercyKill) == 'function' then
                SetPlayerCanMercyKill(PlayerId(), true)
            end
            Wait(interval)
        end
    end)
end

local disabledPrompts = gameplay.DisabledPromptTypes or {}
if disabledPrompts.Enabled and type(disabledPrompts.Types) == 'table' then
    CreateThread(function()
        while true do
            Wait(0)
            for _, promptType in ipairs(disabledPrompts.Types) do
                Citizen.InvokeNative(0xFC094EF26DD153FA, tonumber(promptType))
            end
        end
    end)
end

local focus = gameplay.PlayerFocus or {}
if focus.Enabled then
    CreateThread(function()
        local interval = math.max(100, tonumber(focus.UpdateIntervalMs) or 500)
        local text = tostring(focus.Text or 'STRANGER')
        local mode = string.upper(tostring(focus.Mode or 'TEXT'))

        while true do
            for _, playerId in ipairs(GetActivePlayers()) do
                if playerId ~= PlayerId() then
                    local ped = GetPlayerPed(playerId)
                    if ped ~= 0 and DoesEntityExist(ped) and type(SetPedPromptName) == 'function' then
                        if mode == 'ID' then
                            SetPedPromptName(ped, ('%s %s'):format(text, GetPlayerServerId(playerId)))
                        else
                            SetPedPromptName(ped, text)
                        end
                    end
                end
            end
            Wait(interval)
        end
    end)
end

-- ============================================================================
-- Vehicle & Wagon Camera Zoom Fix
-- ============================================================================
-- In RedM, switching to first-person inside wagons or vehicles clips through the
-- player body, spins or jitters wildly, and completely corrupts the camera/aiming.
-- This thread keeps the follow camera out of first person inside vehicles/wagons.
-- Weapon/scope zoom is never blocked: the scope view is its own camera, and the
-- follow-cam mode is only corrected while the player is NOT aiming, so resetting
-- it can never yank the player out of a scope mid-zoom.
local function callSafe(fn, ...)
    if fn == nil then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function isAimingNow(pid)
    local aiming = callSafe(IsPlayerFreeAiming, pid)
    return aiming == true or aiming == 1
        or IsControlPressed(0, 0x25066914) -- INPUT_VEH_AIM
        or IsControlPressed(0, 0xF84FA74F) -- INPUT_AIM
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false) then
            if not isAimingNow(PlayerId()) then
                callSafe(DisableFirstPersonCamThisFrame)

                -- If the camera is currently in first-person mode (4), reset to third-person
                if callSafe(GetFollowVehicleCamViewMode) == 4 then
                    callSafe(SetFollowVehicleCamViewMode, 1)
                end
                if callSafe(GetFollowPedCamViewMode) == 4 then
                    callSafe(SetFollowPedCamViewMode, 1)
                end
            end

            Wait(0)
        else
            Wait(350)
        end
    end
end)

exports('ApplyGameplaySettings', applyStaticSettings)
exports('TogglePVP', togglePvp)
exports('TogglePvp', togglePvp)
exports('SetPVP', function(state, silent)
    applyPvp(state == true, silent == true)
end)
exports('SetPvp', function(state, silent)
    applyPvp(state == true, silent == true)
end)
exports('IsPvpEnabled', function()
    return currentPvp
end)
exports('GetPvpState', function()
    return currentPvp
end)
exports('IsInCombat', function()
    return isInCombat()
end)
