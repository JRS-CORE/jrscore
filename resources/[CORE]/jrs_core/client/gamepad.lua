-- JRS controller support: input-device tracking, no lock-on aim assist,
-- and the policy/diagnostics side of shared/pad_guard.lua (see config/gamepad.lua).

local padCfg = Config.Gamepad or {}
local aimCfg = padCfg.AimAssist or {}
local guardCfg = padCfg.PadGuard or {}

local usingPad = false
local padDiag = false

local function isTrue(v)
    return v == true or (type(v) == 'number' and v ~= 0)
end

local function readUsingPad()
    return not isTrue(IsUsingKeyboardAndMouse(0))
end

local function guardPolicy()
    local resources = {}
    for resource, controls in pairs(guardCfg.Resources or {}) do
        local normalized = {}
        for hash, mode in pairs(controls) do
            if mode == 'hold' or mode == 'block' or mode == 'double' then
                normalized[hash & 0xFFFFFFFF] = mode
            end
        end
        resources[resource] = normalized
    end
    local uiCfg = padCfg.UI or {}
    return {
        enabled = guardCfg.Enabled ~= false,
        holdMs = tonumber(guardCfg.HoldMs) or 600,
        doubleTapMs = tonumber(guardCfg.DoubleTapMs) or 350,
        resources = resources,
        diag = padDiag,
        ui = {
            enabled = uiCfg.Enabled ~= false,
            cursorSpeed = tonumber(uiCfg.CursorSpeed) or 1.0,
            scrollSpeed = tonumber(uiCfg.ScrollSpeed) or 1.0,
        },
    }
end

local function broadcastPolicy()
    TriggerEvent('jrs_core:padGuard:policy', guardPolicy())
end

exports('IsUsingGamepad', function() return usingPad end)
exports('GetInputDevice', function() return usingPad and 'pad' or 'kbm' end)
exports('GetPadGuardPolicy', guardPolicy)

-- Resources that start after core ask for the policy once pad_guard.lua loads.
AddEventHandler('jrs_core:padGuard:request', broadcastPolicy)

RegisterCommand('paddiag', function()
    padDiag = not padDiag
    print(('[pad-guard] diagnostics %s - press controller buttons and watch F8 for "[pad-guard] fired" lines.'):format(padDiag and 'ON' or 'OFF'))
    broadcastPolicy()
end, false)

-- Input device watcher. Everything else reads the export / state bag / event.
CreateThread(function()
    while true do
        local nowPad = readUsingPad()
        if nowPad ~= usingPad then
            usingPad = nowPad
            if LocalPlayer and LocalPlayer.state and type(LocalPlayer.state.set) == 'function' then
                LocalPlayer.state:set('jrsInputDevice', usingPad and 'pad' or 'kbm', false)
            end
            TriggerEvent('jrs_core:inputDeviceChanged', usingPad and 'pad' or 'kbm')
        end
        Wait(250)
    end
end)

-- Lock-on & Free Aim handling:
-- Targeting mode 3 (Free Aim) is enforced per frame in client/gameplay.lua
-- when Config.Gameplay.DisableAutoAim is on. Free Aim natively removes all aim-assist / auto-aim snap
-- on both controller and mouse & keyboard.
-- SetPlayerLockon must remain enabled (true) so the engine can smoothly transition into
-- over-the-shoulder aim zoom, crosshair reticle, and bow/gun zoom.
-- Lock-on is only touched on a state change of our own. Forcing it back to true
-- every second undid jrs_metabolism (water) and jrs_theftsystem (grenades), which
-- switch lock-on off for the length of their action.
CreateThread(function()
    local friendlyApplied = false
    local weDisabled = false
    SetPlayerLockon(PlayerId(), true)

    while true do
        local wait = 1000
        local player = PlayerId()
        local ped = PlayerPedId()

        if aimCfg.DisableFriendlyLockon ~= false and not friendlyApplied then
            pcall(SetLockonToFriendlyPlayers, player, false)
            friendlyApplied = true
        end

        if aimCfg.DisableLockonWhenArmed == true and ped ~= 0 and isTrue(IsPedArmed(ped, 4)) then
            SetPlayerLockon(player, false)
            weDisabled = true
            wait = 0
        elseif weDisabled then
            SetPlayerLockon(player, true)
            weDisabled = false
        end

        Wait(wait)
    end
end)

AddEventHandler('playerSpawned', function()
    -- Ensure player lock-on is restored so aim zoom works after respawn
    SetPlayerLockon(PlayerId(), true)
    if aimCfg.DisableFriendlyLockon ~= false then
        pcall(SetLockonToFriendlyPlayers, PlayerId(), false)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        SetPlayerLockon(PlayerId(), true)
        broadcastPolicy()
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetPlayerLockon(PlayerId(), true)
    -- Guards keep their last policy otherwise; switch them off until core is back.
    TriggerEvent('jrs_core:padGuard:policy', { enabled = false, holdMs = 600, resources = {}, diag = false, ui = { enabled = false } })
end)

-- Universal NUI Gamepad Isolation:
-- While ANY NUI page has focus and the player is on a controller, the pad must not
-- also drive the character (in RedM NUI focus does not swallow pad input, so A/B/X
-- in a menu jumped, punched, whistled...). All gameplay actions are disabled, but:
--   * FRONTEND_* stays enabled (except Start/pause) so scripts that close their UI
--     from Lua on FRONTEND_CANCEL etc. still work on the pad.
--   * UIs opened with SetNuiFocusKeepInput(true) are meant to be walked with, so
--     they are left alone (same as on keyboard).
--   * SetPlayerControl is NOT touched: toggling it back on when a menu closed
--     unfroze players that another script had frozen (creator, cuffs, cutscenes).
--   * After the page closes, the button that closed it is usually still down, and
--     the game would read it as a fresh B = melee / A = jump. Action buttons stay
--     blocked until every face/trigger button is released (max 1 s); moving and
--     looking come back instantly.
local FRONTEND_KEEP = {
    0xC7B5340A, 0x156F7119, 0x6DB8C62F, 0x7C0162C0, -- accept, cancel, X, Y
    0x6319DB71, 0x05CA7C52, 0xA65EBAB4, 0xDEB34313, -- d-pad
    0xE885EF16, 0x17BEC168, 0x51104035, 0x6FED71BC, -- LB, RB, LT, RT
    0x4A60E6E2, 0x2A111956, 0xB6494F37,             -- select, LS, RS
}
local MOVE_LOOK = { 0x4D8FB4C1, 0xFDA83190, 0xA987235F, 0xD2047988 }
local HELD_CHECK = {
    0xC7B5340A, 0x156F7119, 0x6DB8C62F, 0x7C0162C0,
    0xE885EF16, 0x17BEC168, 0x51104035, 0x6FED71BC,
}

local function nuiKeepsInput()
    if type(IsNuiFocusKeepingInput) ~= 'function' then return false end
    local ok, keep = pcall(IsNuiFocusKeepingInput)
    return ok and isTrue(keep)
end

local function anyPadButtonHeld()
    for i = 1, #HELD_CHECK do
        if isTrue(IsDisabledControlPressed(0, HELD_CHECK[i])) or isTrue(IsControlPressed(0, HELD_CHECK[i])) then
            return true
        end
    end
    return false
end

CreateThread(function()
    local locked = false
    local releaseUntil = 0
    while true do
        if isTrue(IsNuiFocused()) and usingPad and not nuiKeepsInput() then
            locked = true
            DisableAllControlActions(0)
            DisableAllControlActions(1)
            DisableAllControlActions(2)
            for i = 1, #FRONTEND_KEEP do
                EnableControlAction(0, FRONTEND_KEEP[i], true)
                EnableControlAction(2, FRONTEND_KEEP[i], true)
            end
            Wait(0)
        elseif locked then
            -- Page just closed: swallow the still-held button, keep walking/looking.
            if releaseUntil == 0 then releaseUntil = GetGameTimer() + 1000 end
            if anyPadButtonHeld() and GetGameTimer() < releaseUntil then
                DisableAllControlActions(0)
                for i = 1, #MOVE_LOOK do
                    EnableControlAction(0, MOVE_LOOK[i], true)
                end
                Wait(0)
            else
                locked = false
                releaseUntil = 0
            end
        else
            Wait(100)
        end
    end
end)
