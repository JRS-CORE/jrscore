-- JRS pad guard (client). Include FIRST in a resource's client_scripts:
--     '@jrs_core/shared/pad_guard.lua',
-- It wraps the control natives in THAT resource only, so keyboard hotkeys which
-- are also bound to controller buttons stop opening menus from normal controller
-- play. Which hashes and how (hold/block) comes from jrs_core config/gamepad.lua,
-- per resource. Keyboard + mouse input is never changed, and nothing is gated
-- while this client has NUI focus.

if IsDuplicityVersion() or _G.__jrsPadGuardLoaded then return end
_G.__jrsPadGuardLoaded = true

local RESOURCE = GetCurrentResourceName()

local rawJustPressed = IsControlJustPressed
local rawJustReleased = IsControlJustReleased
local rawPressed = IsControlPressed
local rawDisJustPressed = IsDisabledControlJustPressed
local rawDisJustReleased = IsDisabledControlJustReleased
local rawDisPressed = IsDisabledControlPressed
local rawDisable = DisableControlAction
local rawUsingKbm = IsUsingKeyboardAndMouse
local rawNuiFocused = IsNuiFocused
local getFrame = GetFrameCount
local getTimer = GetGameTimer

local function isTrue(v)
    return v == true or (type(v) == 'number' and v ~= 0)
end

local enabled, holdMs, doubleTapMs, diagOn = true, 600, 350, false
local controls = {}

AddEventHandler('jrs_core:padGuard:policy', function(p)
    if type(p) ~= 'table' then return end
    local mine = type(p.resources) == 'table' and p.resources[RESOURCE] or nil
    controls = type(mine) == 'table' and mine or {}
    enabled = p.enabled == true
    holdMs = tonumber(p.holdMs) or 600
    doubleTapMs = tonumber(p.doubleTapMs) or 350
    diagOn = p.diag == true
end)
TriggerEvent('jrs_core:padGuard:request')

local cachedFrame, cachedPad, cachedGated = -1, false, false
local function refresh()
    local frame = getFrame()
    if frame ~= cachedFrame then
        cachedFrame = frame
        cachedPad = not isTrue(rawUsingKbm(0))
        cachedGated = enabled and cachedPad and not isTrue(rawNuiFocused())
    end
end

local function gatingActive()
    refresh()
    return cachedGated
end

local function onPad()
    refresh()
    return cachedPad
end

local function norm(action)
    local t = type(action)
    if t == 'number' then
        local i = math.tointeger(action)
        return i and (i & 0xFFFFFFFF) or nil
    end
    if t == 'string' then return GetHashKey(action) & 0xFFFFFFFF end
    return nil
end

local lastDiag = {}
local function diag(fn, hash, verdict)
    local now = getTimer()
    local key = fn .. hash
    if lastDiag[key] and lastDiag[key] + 1000 > now then return end
    lastDiag[key] = now
    print(('[pad-guard] fired  resource=%s  %s(0x%08X)  -> %s'):format(RESOURCE, fn, hash, verdict))
end

-- Hold tracking per hash, advanced at most once per frame by whichever poll comes
-- first. `fireFrame` lets every poll in that frame (JustPressed OR
-- DisabledJustPressed, several threads) see the same single press.
local holdState = {}
local function track(pad, hash, mode)
    local st = holdState[hash]
    if not st then st = {}; holdState[hash] = st end
    local frame = getFrame()
    if st.frame == frame then return st end
    st.frame = frame
    st.releasedLong = false
    local down = isTrue(rawPressed(pad, hash)) or isTrue(rawDisPressed(pad, hash))
    local now = getTimer()
    if mode == 'double' then
        -- Two taps inside doubleTapMs: press polls fire on the 2nd press, release
        -- polls on the 2nd release. A single tap or a long hold never fires.
        if down and not st.wasDown then
            if st.lastTap and now - st.lastTap <= doubleTapMs then
                st.fireFrame = frame
                st.armRelease = true
                st.lastTap = nil
            else
                st.lastTap = now
            end
        elseif not down and st.wasDown and st.armRelease then
            st.armRelease = false
            st.releasedLong = true
        end
        st.wasDown = down
        return st
    end
    if down then
        if not st.since then st.since = now; st.fired = false end
        if not st.fired and now - st.since >= holdMs then
            st.fired = true
            st.fireFrame = frame
        end
    else
        if st.since and now - st.since >= holdMs then
            st.releasedLong = true
        end
        st.since = nil
        st.fired = false
    end
    return st
end

local function wrapJust(raw, name, isPress)
    return function(pad, action)
        local result = raw(pad, action)
        local hash = norm(action)
        local mode = hash and controls[hash]
        if not mode or not gatingActive() then
            if diagOn and hash and isTrue(result) and onPad() then diag(name, hash, 'passed') end
            return result
        end
        if mode == 'block' then
            if diagOn and isTrue(result) then diag(name, hash, 'blocked') end
            return false
        end
        local st = track(pad, hash, mode)
        if isPress then
            return st.fireFrame == getFrame()
        end
        return st.releasedLong == true
    end
end

-- The scripts disable their hotkey every frame so the keyboard key does nothing
-- else. On a pad that same hash is a real gameplay button: leave it enabled.
local function guardedDisable(pad, action, related)
    local hash = norm(action)
    if hash and controls[hash] and gatingActive() then return end
    return rawDisable(pad, action, related)
end

IsControlJustPressed = wrapJust(rawJustPressed, 'IsControlJustPressed', true)
IsDisabledControlJustPressed = wrapJust(rawDisJustPressed, 'IsDisabledControlJustPressed', true)
IsControlJustReleased = wrapJust(rawJustReleased, 'IsControlJustReleased', false)
IsDisabledControlJustReleased = wrapJust(rawDisJustReleased, 'IsDisabledControlJustReleased', false)
DisableControlAction = guardedDisable

-- Some scripts (jrs_inventory, jrs_animmenu) call these natives by hash through
-- Citizen.InvokeNative, which skips the globals above. Route those hashes to the
-- same wrappers. The native loader keeps its own InvokeNative reference, so the
-- raw* functions above never come back through here.
local byNativeHash = {
    [0x580417101DDB492F] = IsControlJustPressed,
    [0x91AEF906BCA88877] = IsDisabledControlJustPressed,
    [0x50F940259D3841E6] = IsControlJustReleased,
    [0x305C8DCD79DA8B0F] = IsDisabledControlJustReleased,
    [0xFE99B66D079CF6BC] = guardedDisable,
}
local rawInvoke = Citizen.InvokeNative
Citizen.InvokeNative = function(hash, ...)
    local fn = byNativeHash[hash]
    -- Only divert when this resource actually gates something; otherwise keep
    -- the exact raw InvokeNative result (some callers compare it with 1).
    if fn and next(controls) ~= nil then
        local _, action = ...
        local h = norm(action)
        if h and controls[h] and gatingActive() then return fn(...) end
    end
    return rawInvoke(hash, ...)
end

---------------------------------------------------------------------------
-- Every resource can ask "is this player on a controller?"
---------------------------------------------------------------------------
JRSPad = JRSPad or {}
JRSPad.IsUsingPad = onPad
JRSPad.Device = function() return onPad() and 'pad' or 'kbm' end

---------------------------------------------------------------------------
-- Controller -> NUI bridge. While THIS resource owns NUI focus and the player
-- is on a controller, the pad drives the page through
-- nui://jrs_core/html/jrs-pad.js (virtual cursor, click, back, scroll, tabs,
-- on-screen keyboard). "Owns" = the last resource that called
-- SetNuiFocus(true, ...); when it lets go, anyone still holding focus reclaims.
---------------------------------------------------------------------------
local uiEnabled, uiSpeed, uiScroll = true, 1.0, 1.0
AddEventHandler('jrs_core:padGuard:policy', function(p)
    local ui = type(p) == 'table' and p.ui or nil
    uiEnabled = type(ui) == 'table' and ui.enabled == true
    uiSpeed = type(ui) == 'table' and tonumber(ui.cursorSpeed) or 1.0
    uiScroll = type(ui) == 'table' and tonumber(ui.scrollSpeed) or 1.0
end)

local ownFocus, ownKeepInput = false, false
local focusOwner = nil

-- The bridge only ever talks to a page that loaded jrs-pad.js and said so. A
-- page without it gets no messages and the player's controls are never
-- touched, so resources that have not opted in behave exactly as before.
local pageReady = false
if type(RegisterNUICallback) == 'function' then
    RegisterNUICallback('jrsPadReady', function(_, cb)
        pageReady = true
        cb('ok')
    end)
end

AddEventHandler('jrs_core:padFocus:claim', function(res) focusOwner = res end)
AddEventHandler('jrs_core:padFocus:release', function(res)
    if focusOwner ~= res then return end
    focusOwner = nil
    if ownFocus and res ~= RESOURCE then TriggerEvent('jrs_core:padFocus:claim', RESOURCE) end
end)

if type(SetNuiFocus) == 'function' then
    local rawSetNuiFocus = SetNuiFocus
    SetNuiFocus = function(hasFocus, hasCursor, ...)
        local result = rawSetNuiFocus(hasFocus, hasCursor, ...)
        if isTrue(hasFocus) then
            ownFocus = true
            TriggerEvent('jrs_core:padFocus:claim', RESOURCE)
        elseif ownFocus then
            ownFocus = false
            ownKeepInput = false
            TriggerEvent('jrs_core:padFocus:release', RESOURCE)
        end
        return result
    end
end

if type(SetNuiFocusKeepInput) == 'function' then
    local rawKeepInput = SetNuiFocusKeepInput
    SetNuiFocusKeepInput = function(keep, ...)
        ownKeepInput = isTrue(keep)
        return rawKeepInput(keep, ...)
    end
end

AddEventHandler('onClientResourceStop', function(res)
    if res == RESOURCE and ownFocus then
        ownFocus = false
        TriggerEvent('jrs_core:padFocus:release', RESOURCE)
    elseif res == focusOwner then
        -- A resource that stopped while holding focus never released it.
        TriggerEvent('jrs_core:padFocus:release', res)
    end
end)

local PAD_BUTTONS = {
    { 'a', 0xC7B5340A },      -- INPUT_FRONTEND_ACCEPT
    { 'b', 0x156F7119 },      -- INPUT_FRONTEND_CANCEL
    { 'x', 0x6DB8C62F },      -- INPUT_FRONTEND_X
    { 'y', 0x7C0162C0 },      -- INPUT_FRONTEND_Y
    { 'up', 0x6319DB71 },     -- INPUT_FRONTEND_UP
    { 'down', 0x05CA7C52 },   -- INPUT_FRONTEND_DOWN
    { 'left', 0xA65EBAB4 },   -- INPUT_FRONTEND_LEFT
    { 'right', 0xDEB34313 },  -- INPUT_FRONTEND_RIGHT
    { 'lb', 0xE885EF16 },     -- INPUT_FRONTEND_LB
    { 'rb', 0x17BEC168 },     -- INPUT_FRONTEND_RB
    { 'lt', 0x51104035 },     -- INPUT_FRONTEND_LT
    { 'rt', 0x6FED71BC },     -- INPUT_FRONTEND_RT
    { 'select', 0x4A60E6E2 }, -- INPUT_FRONTEND_SELECT
    { 'start', 0xD82E0BD2 },  -- INPUT_FRONTEND_PAUSE
    { 'l3', 0x2A111956 },     -- INPUT_FRONTEND_LS
    { 'r3', 0xB6494F37 },     -- INPUT_FRONTEND_RS
}
-- Frontend actions stay enabled so resources that close their UI from Lua on
-- INPUT_FRONTEND_CANCEL etc. keep working; everything else (walking, camera,
-- attack...) is switched off while the pad is driving a page.
local KEEP_ENABLED = {
    0xC7B5340A, 0x156F7119, 0x6DB8C62F, 0x7C0162C0, 0x6319DB71, 0x05CA7C52,
    0xA65EBAB4, 0xDEB34313, 0xE885EF16, 0x17BEC168, 0x51104035, 0x6FED71BC,
    0x4A60E6E2, 0xD82E0BD2, 0x2A111956, 0xB6494F37,
}
local AXIS_LX, AXIS_LY = 0x4D8FB4C1, 0xFDA83190 -- INPUT_MOVE_LR / INPUT_MOVE_UD
local AXIS_RX, AXIS_RY = 0xA987235F, 0xD2047988 -- INPUT_LOOK_LR / INPUT_LOOK_UD

local rawAxis = GetDisabledControlNormal
local rawDisableAll = DisableAllControlActions
local rawEnable = EnableControlAction
local rawSend = SendNUIMessage

local function q(v)
    v = tonumber(v) or 0.0
    if v > -0.12 and v < 0.12 then return 0.0 end
    return math.floor(v * 50 + 0.5) / 50
end

CreateThread(function()
    local wasActive = false
    local held = {}
    local lx, ly, rx, ry = 0.0, 0.0, 0.0, 0.0
    while true do
        local active = uiEnabled and pageReady and ownFocus and (focusOwner == RESOURCE or not focusOwner)
            and onPad() and isTrue(rawNuiFocused())
        if active then
            if not ownKeepInput then
                rawDisableAll(0)
                rawDisableAll(1)
                rawDisableAll(2)
                -- Frontend stays live (not Start/pause, which would open the map).
                -- SetPlayerControl is never touched: see jrs_core client/gamepad.lua.
                for i = 1, #KEEP_ENABLED do
                    if KEEP_ENABLED[i] ~= 0xD82E0BD2 then
                        rawEnable(0, KEEP_ENABLED[i], true)
                        rawEnable(2, KEEP_ENABLED[i], true)
                    end
                end
            end
            local down, up
            for i = 1, #PAD_BUTTONS do
                local name, hash = PAD_BUTTONS[i][1], PAD_BUTTONS[i][2]
                local now = isTrue(rawDisPressed(0, hash)) or isTrue(rawPressed(0, hash))
                if not wasActive then
                    -- A button still held from opening the UI is not a new press.
                    held[name] = now
                elseif now ~= (held[name] == true) then
                    held[name] = now
                    if now then down = down or {}; down[#down + 1] = name
                    else up = up or {}; up[#up + 1] = name end
                end
            end
            local nlx, nly = q(rawAxis(0, AXIS_LX)), q(rawAxis(0, AXIS_LY))
            local nrx, nry = q(rawAxis(0, AXIS_RX)), q(rawAxis(0, AXIS_RY))
            local axesChanged = nlx ~= lx or nly ~= ly or nrx ~= rx or nry ~= ry
            if not wasActive or down or up or axesChanged then
                lx, ly, rx, ry = nlx, nly, nrx, nry
                rawSend({
                    action = 'jrsPad',
                    jrsPad = {
                        active = true, speed = uiSpeed, scrollSpeed = uiScroll,
                        lx = lx, ly = ly, rx = rx, ry = ry, down = down, up = up,
                    },
                })
            end
            wasActive = true
            Wait(0)
        else
            if wasActive then
                wasActive = false
                held = {}
                lx, ly, rx, ry = 0.0, 0.0, 0.0, 0.0
                rawSend({ action = 'jrsPad', jrsPad = { active = false } })
            end
            Wait(ownFocus and 100 or 500)
        end
    end
end)
