-- JRS Character client runtime
-- Consolidated from the legacy loader, selector, creator, clothing, barber, and aging modules.
-- Each former module is isolated in a do/end block so local variables keep their original scope.

JRSCreatorSceneShifted = false
CreateThread(function()
    local n = 0
    while n < 60 do -- 5 minutes of 5s heartbeats
        n = n + 1
        local ped = PlayerPedId()
        local ls = 'n/a'
        if GetResourceState('jrs_loadingscreen') == 'started' then
            local ok, v = pcall(function() return exports['jrs_loadingscreen']:IsLoadingScreenActive() end)
            ls = ok and tostring(v) or 'err'
        end
        local c = GetEntityCoords(ped)
        Wait(5000)
    end
end)

-- Shared helpers are declared at chunk scope so every consolidated do/end module
-- resolves the same function references. Do not move these declarations inside a module.
local JRSApplyNuiFocus
local JRSSetSpawnBookCharacterHidden
local JRSApplyPlayerControl
local JRSSetSelectorCursorOwnership
local JRSCommitNuiFocus
local JRSForceNativeCursorThisFrame
local JRSRecoverNuiCursor
local RequestPlayerModelSafely
local function JRSNativeTrue(value)
    return value == true or value == 1
end

-- Creator preparation runs under a fade with the ped frozen. Do not start the
-- asynchronous teleport task here: it can remain active when room streaming
-- times out and keep the ped hidden during the subsequent model request.
local function JRSTeleportToScene(x, y, z, heading, timeoutMs)
    -- Use verified RDR3 hashes, including an explicit boolean return, rather
    -- than relying on the client's generated native aliases.
    Citizen.InvokeNative(0x0858B86146601BE8) -- STOP_PLAYER_TELEPORT
    local function teleportActive()
        return JRSNativeTrue(Citizen.InvokeNative(0x085EEAEB8783FEB5, Citizen.ResultAsInteger()))
    end
    local deadline = GetGameTimer() + math.min(tonumber(timeoutMs) or 1000, 1000)
    while teleportActive() and GetGameTimer() < deadline do Wait(0) end
    if teleportActive() then
        return false
    end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, heading)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    RequestCollisionAtCoord(x, y, z)
    return true
end
local jrsSelectorCursorOwned = false

-- Shared NUI/cursor state. These must live at chunk scope because the
-- consolidated client file isolates former modules inside do/end blocks.
local jrsNuiFocusWanted = false
local jrsNuiCursorWanted = false
local jrsNuiFocusApplied = false
local jrsNuiCursorApplied = false
local jrsNuiFocusAcquireGeneration = 0
local jrsLoadingScreenCursorHandoffActive = false

-- True while a different resource's own NUI page (jrs_idcard's identity
-- registry) is the one the player is typing into. jrs_character keeps
-- jrsNuiFocusWanted true across that handoff so it can reclaim focus on
-- return, but the periodic watchdog below used to keep forcing
-- SetNuiFocus(false,false) -> (true,true) edges every ~4s regardless of who
-- owned the focused input - each edge blurs whatever text field jrs_idcard
-- currently has focused, so typing there would randomly stop working a few
-- seconds in. Gate those forced re-commits off while this is true.
local jrsExternalUiFocusActive = false

-- NETWORK_CONCEAL_PLAYER (native 0xBBDF066252829606) hides this player from
-- other clients' network view during creation/death cutscenes. Calling it
-- before the local player is a fully registered network entity (e.g. in the
-- first frames after a brand-new player joins, right as the creator opens)
-- can hard-crash the game process rather than raise a catchable Lua error -
-- pcall does not protect against that. Skip the call entirely until the
-- player is confirmed network-active.
-- SET_PLAYER_MODEL (native 0xED40380076A31506) with a model that is not
-- streamed in raises a native access violation that takes the whole game
-- process down ("exception at address RDR2+CC439A", crash hash
-- oklahoma-dakota-table); pcall cannot catch it. It happened whenever model
-- streaming stalled and a caller went on "best-effort". Every SetPlayerModel in
-- this resource goes through here: valid + loaded, otherwise the call is
-- skipped and the current ped is kept. No waiting added.
function JRSSafeSetPlayerModel(model)
    if type(model) == 'string' then model = GetHashKey(model) end
    model = tonumber(model)
    if not model or model == 0 or not IsModelValid(model) then return false end
    local curPed = PlayerPedId()
    if curPed and curPed ~= 0 and DoesEntityExist(curPed) and GetEntityModel(curPed) == model then return true end
    if not HasModelLoaded(model) then
        RequestModel(model)
        print(('^1[jrs_character] SetPlayerModel skipped: model %s not streamed (crash guard)^7'):format(tostring(model)))
        return false
    end
    SetPlayerModel(PlayerId(), model)
    return true
end

function JRSSafeNetworkConceal(hidden)
    if type(NetworkConcealPlayer) ~= 'function' then return end
    local pid = PlayerId()
    if type(NetworkIsPlayerActive) == 'function' then
        local ok, active = pcall(NetworkIsPlayerActive, pid)
        if not ok or active ~= true then return end
    end
    pcall(NetworkConcealPlayer, pid, hidden == true)
end

-- ============================================================================
-- Aging state push
-- The server fires `jrs_character:ageUpdated` whenever a character's age or
-- playtime snapshot changes. Registering it as a net event here stops RedM
-- from warning "event jrs_character:ageUpdated was not safe for net" on every
-- push, and exposes the latest values on LocalPlayer.state for any resource
-- (HUD, jobs, ranch, ...) that wants to read them.
-- ============================================================================
RegisterNetEvent('jrs_character:ageUpdated', function(data)
    if type(data) ~= 'table' then return end
    -- Cache the latest aging snapshot so other client modules / resources can
    -- read it. Use the player state bag when available, but never assume the
    -- FiveM-only LocalPlayer global exists on RedM.
    jrsAgeState = {
        age = data.age,
        playtimeSeconds = data.playtimeSeconds,
        secondsToNextYear = data.secondsToNextYear,
    }
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state.jrsAge = data.age
        LocalPlayer.state.jrsPlaytimeSeconds = data.playtimeSeconds
        LocalPlayer.state.jrsSecondsToNextYear = data.secondsToNextYear
    end
end)

-- ============================================================================
-- Module: callbacks
-- ============================================================================
do
local currentRequestId = 0
local responseCallback = {}
local registeredCallback = {}

local server = IsDuplicityVersion()

Callback = {}

local function executeCallback(name, ...)
  if not registeredCallback[name] then return printconsole(('No callback for: %s'):format(name)) end
  return registeredCallback[name].cb(...)
end

local function executeResponse(requestId, fromRessource, ...)
  local pending = responseCallback[requestId]
  if not pending then return end
  responseCallback[requestId] = nil
  pending(...)
end


---@param name string the name of the event
---@param cb function
function Callback.register(name, cb)
  if registeredCallback[name] then return printconsole('Callback already registered:', name) end
  registeredCallback[name] = {
    cb = cb,
    resource = GetInvokingResource()
  }
end


if server then

  ---@param name string Name of the callback event
  ---@param cb function return of the event
  ---@param ...? any
  function Callback.triggerClient(name, source, cb, ...)
    if not GetPlayerIdentifier(source) then
      return printconsole('Callback Module: Player is not connected - source: ' .. source)
    end
    responseCallback[currentRequestId] = cb

    TriggerClientEvent('jrs_character_creator:triggerCallback', source, name, currentRequestId, GetInvokingResource() or "unknown", ...)

    currentRequestId = currentRequestId < 65535 and currentRequestId + 1 or 0
  end

  function Callback.triggerServer(name, cb, ...)
    if not registeredCallback[name] then return printconsole('No server callback for:', name) end

    if cb then
      cb(executeCallback(name, ...))
    else
      return executeCallback(name, ...)
    end
  end

  RegisterServerEvent('jrs_character_creator:responseCallback', executeResponse)

  RegisterServerEvent('jrs_character_creator:triggerCallback', function(name, requestId, fromRessource, ...)
    local source = source
    TriggerClientEvent('jrs_character_creator:responseCallback', source, requestId, fromRessource, executeCallback(name, source, ...))
  end)

else

  function Callback.clearPending()
    responseCallback = {}
  end

  RegisterNetEvent('jrs_character_creator:clearPendingCallbacks', Callback.clearPending)

  -- Do not clear pending server callbacks when NUI focus changes.
  -- Character creation intentionally removes NUI focus before the server
  -- finishes creating/selecting the character. Clearing callbacks here caused
  -- the response to be lost and left the player on a permanent black screen.
  -- Pending callbacks are still cleared explicitly when the resource stops or
  -- when a new selector lifecycle starts.

  ---@param name string Name of the callback event
  ---@param cb function return of the event
  ---@param ...? any
  function Callback.triggerServer(name, cb, ...)
    local requestId = currentRequestId
    responseCallback[requestId] = cb

    TriggerServerEvent('jrs_character_creator:triggerCallback', name, requestId, GetInvokingResource() or 'unknown', ...)

    -- Prevent stale callback closures from accumulating forever if a resource
    -- restarts, a request is rate-limited, or the server never answers.
    SetTimeout(35000, function()
      if responseCallback[requestId] == cb then
        responseCallback[requestId] = nil
        if name == 'jrs_character_creator:SaveAppearance' and type(cb) == 'function' then
          cb(false, 'timeout')
        end
      end
    end)

    currentRequestId = currentRequestId < 65535 and currentRequestId + 1 or 0
  end


  function Callback.triggerClient(name, cb, ...)
    if not registeredCallback[name] then return printconsole('No client callback for:', name) end
    if cb then
      cb(executeCallback(name, ...))
    else
      return executeCallback(name, ...)
    end
  end

  RegisterNetEvent('jrs_character_creator:responseCallback', executeResponse)

  RegisterNetEvent('jrs_character_creator:triggerCallback', function(name, requestId, fromRessource, ...)
    TriggerServerEvent('jrs_character_creator:responseCallback', requestId, fromRessource, executeCallback(name, ...))
  end)


end

function printconsole(...)
  if IsDuplicityVersion() then
    return print("^1" .. GetCurrentResourceName() .. ":", ..., "^0")
  end
  return print("^1", ...)
end

AddEventHandler('onResourceStop', function(resource)
  for name, callback in pairs(registeredCallback) do
    if callback.resource == resource then
      registeredCallback[name] = nil
    end
  end
end)
end

-- ============================================================================
-- Module: legacy/main.lua
-- ============================================================================
-- Shared across the legacy character module and the presentation/NUI module.
-- Keep this declaration at chunk scope: declaring it local inside legacy/main.lua
-- makes later callbacks resolve the name as a missing global.
local JRSIsExternalLoadingScreenActive

do
-- ===== Global State =====


function CharacterNotify(title, message, duration)
    if type(IsJRSCharacterUiSuppressed) == 'function' and IsJRSCharacterUiSuppressed() then return end
    TriggerEvent('jrs_core:sendLeftNotification', title, message, 'hud_toasts', 'toast_catalogue', duration or 3000, 'COLOR_WHITE')
end
heading = Config.CreatorCam.heading
z_position = Config.CreatorCam.z
Skin_Table = {}
Clothe_Table = {}
Beard_Table = {}
Hair_Table = {}
zoom = Config.CreatorCam.zoom
hair_write = -1
beard_write = -1
HeadCategory = 1
HeadTexture = 1
BodyTexture = 1
LegsTexture = 1
Gauntlet_set = 0
Accesori_set = 0
HeadType = 0
BodyType = 1
LegsType = 0
HeadSize = 0
EyeBrowH = 0
EyeBrowW = 0
EyeBrowD = 0
EarsH = 0
EarsW = 0
EarsD = 0
EarsL = 0
EyeLidH = 0
EyeLidW = 0
EyeD = 0
EyeAng = 0
EyeDis = 0
EyeH = 0
NoseW = 0
NoseS = 0
NoseH = 0
NoseAng = 0
NoseC = 0
NoseDis = 0
CheekBonesH = 0
CheekBonesW = 0
CheekBonesD = 0
MouthW = 0
MouthD = 0
MouthX = 0
MouthY = 0
ULiphH = 0
ULiphW = 0
ULiphD = 0
LLiphH = 0
LLiphW = 0
LLiphD = 0
JawH = 0
JawW = 0
JawD = 0
ChinH = 0
ChinW = 0
ChinD = 0
Beard = -1
Hair = -1
CharacterBodyIndex = 1
CharacterWaistIndex = 1
CharacterEyesIndex = 1
Scale = 100
current_texture_settings = Config.texture_types["male"]
textureId = -1
is_overlay_change_active = false
scars_enable = 1
scars_texture = 1
scars_opacity = 10
blush_enable = 1
blush_texture = 1
blush_opacity = 10
blush_color_1 = 0.0
shadow_enable = 1
shadow_color_1 = 0
shadow_color_2 = 0
shadow_color_3 = 0
shadow_texture = 1
shadow_opacity = 10
eyeliners_enable = 0
eyeliners_color_1 = 0
eyeliners_color_2 = 0
eyeliners_color_3 = 0
eyeliners_texture = 1
eyeliners_opacity = 10
lipsticks_enable = 0
lipsticks_color_1 = 0
lipsticks_color_2 = 0
lipsticks_color_3 = 0
lipsticks_texture = 1
lipsticks_opacity = 10
spots_enable = 0
spots_texture = 1
spots_opacity = 10
disc_enable = 0
disc_texture = 1
disc_opacity = 10
complex_enable = 0
complex_texture = 1
complex_opacity = 10
acne_visibility = 0
acne_texture = 1
acne_opacity = 10
ageing_enable = 0
ageing_texture = 1
ageing_opacity = 10
freckles_enable = 0
freckles_texture = 1
freckles_opacity = 10
moles_enable = 0
moles_texture = 1
moles_opacity = 10
eyebrows_enable = 0
eyebrows_texture = 1
eyebrows_opacity = 10
eyebrows_color_1 = 0
beardstabble_enable = 0
beardstabble_texture = 1
beardstabble_opacity = 10
beardstabble_color_1 = 0
HatsTable = {}
EyewearTable = {}
ScarftTable = {}
MaskTable = {}
NecktieTable = {}
ShirtTable = {}
SuspenderTable = {}
VestTable = {}
CoatTable = {}
ClosedCoatTable = {}
PonchoTable = {}
CloakTable = {}
GloveTable = {}
RRingTable = {}
SpatsTable = {}
LRingTable = {}
LoadoutsTable = {}
BraceletTable = {}
GunbeltTable = {}
GunbeltAcsTable = {}
BeltsTable = {}
BucklesTable = {}
LHolsterTable = {}
SkirtTable = {}
RHolsterTable = {}
PantTable = {}
ChapTable = {}
BootTable = {}
SpurTable = {}
SatchelTable = {}
GauntletTable = {}
AccesorieTable = {}
Coord_Table = {}
Satchel_set = 0
hats_set = 0
eyewear_set = 0
Scarf_set = 0
GunbeltAcs_set = 0
Mask_set = 0
Spat_set = 0
Necktie_set = 0
Shirt_set = 0
Skirt_set = 0
Suspender_set = 0
Vest_set = 0
Coat_set = 0
CCoat_set = 0
Poncho_set = 0
Loadouts_set = 0
Cloak_set = 0
Glove_set = 0
RRing_set = 0
LRing_set = 0
Bracelet_set = 0
Gunbelt_set = 0
Belt_set = 0
Buckles_set = 0
LHolster_set = 0
Pant_set = 0
Chap_set = 0
Boot_set = 0
Spur_set = 0
have_character = true
isDead = false

-- Publish the authoritative JRS death state for voice and other client resources.
-- pma-voice reads LocalPlayer.state.isDead, so changing the push-to-talk key
-- cannot bypass the death voice block.
local publishedDeathState = nil

-- This helper is intentionally global because client.lua is built from multiple
-- isolated do/end modules. Spawn/selector/event modules all need the same death
-- state publisher; keeping it local to legacy/main.lua makes later modules resolve
-- PublishJRSDeathState as a missing global and abort the spawn finalizer.
function PublishJRSDeathState(dead)
    dead = dead == true

    local currentState = nil
    if LocalPlayer and LocalPlayer.state then
        currentState = LocalPlayer.state.isDead == true
    end

    if publishedDeathState == dead and currentState == dead then
        return true
    end

    publishedDeathState = dead

    -- Death-state publishing must never be able to abort character spawning.
    -- State bags are the primary source for pma-voice; the local event remains
    -- available for other JRS resources that listen for death-state changes.
    if LocalPlayer and LocalPlayer.state then
        local ok, err = pcall(function()
            LocalPlayer.state:set('isDead', dead, true)
        end)
        if not ok then
-- REMOVED-PRINT:             print(('^3[jrs_character] Could not publish LocalPlayer death state: %s^7'):format(tostring(err)))
        end
    end

    TriggerEvent('jrs_character:deathStateChanged', dead)
    return true
end
is_loaded_character = false

set_dead = false
TimeToRespawn = Config.TimeToRespawn
cam = nil
angleY = 0.0
angleZ = 0.0

spawned = false
carrier = nil
active_block = false

-- ===== Export Functions =====

local characterLoading = true
local characterGateActive = true
local characterGateReason = 'initializing'
-- NUI focus/cursor state is declared at chunk scope above so the selector
-- integration module and the legacy/main module share the exact same state.
jrsNuiFocusWanted = false
jrsNuiCursorWanted = false
jrsNuiFocusApplied = false
jrsNuiCursorApplied = false
jrsNuiFocusAcquireGeneration = 0
local jrsPostGateGuardUntil = 0
local jrsPlayerControlLocked = false
-- True only while the external loading screen is still visible over Character
-- Selection. During this phase, do not draw RedM's native cursor on top of the
-- loadscreen/CEF cursor; doing so changes its apparent size.
jrsLoadingScreenCursorHandoffActive = false

JRSIsExternalLoadingScreenActive = function()
    if GetResourceState('jrs_loadingscreen') ~= 'started' then return false end

    local ok, active = pcall(function()
        local loadscreen = exports['jrs_loadingscreen']
        if not loadscreen then return false end
        return loadscreen:IsLoadingScreenActive()
    end)

    -- Older loading builds may not expose the state API. A started resource
    -- alone does not mean its frontend is still visible, so fail closed.
    return ok == true and active == true
end

-- While the Character Selector is open it is the sole owner of the mouse.
-- The loading frontend is allowed to disappear at any time without releasing it.

local function publishCharacterGateState()
    local ready = characterGateActive ~= true and is_loaded_character == true
    if LocalPlayer and LocalPlayer.state then
        pcall(function()
            LocalPlayer.state:set('jrsCharacterReady', ready, true)
            LocalPlayer.state:set('jrsCharacterGate', characterGateActive == true, true)
        end)
    end
    TriggerEvent('jrs_character:gateChanged', characterGateActive == true, ready, characterGateReason)
end

function SetJRSCharacterGate(state, reason)
    local wasActive = characterGateActive == true
    characterGateActive = state == true
    characterGateReason = tostring(reason or (characterGateActive and 'character_pending' or 'character_ready'))
    characterLoading = characterGateActive

    -- Consume any queued frontend input when ownership returns to gameplay.
    if wasActive and not characterGateActive then
        jrsPostGateGuardUntil = GetGameTimer() + 850
    elseif characterGateActive then
        jrsPostGateGuardUntil = 0
    end

    publishCharacterGateState()
end

function IsJRSCharacterUiSuppressed()
    return characterGateActive == true
end

-- Shared across all consolidated modules. Do not localize this function: the
-- spawn-book callbacks and the final spawn module live in separate do/end scopes.
JRSSetSpawnBookCharacterHidden = function(hidden)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    hidden = hidden == true
    FreezeEntityPosition(ped, hidden)
    SetEntityVisible(ped, not hidden, false)
    SetEntityCollision(ped, not hidden, not hidden)
    SetPlayerInvincible(PlayerId(), hidden)

    if type(SetEntityAlpha) == 'function' then
        if hidden then
            SetEntityAlpha(ped, 0, false)
        else
            ResetEntityAlpha(ped)
        end
    end

    JRSSafeNetworkConceal(hidden)

    return true
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    pcall(JRSSetSpawnBookCharacterHidden, false)
    if type(JRSApplyNuiFocus) == 'function' then
        pcall(JRSApplyNuiFocus, false, false, false)
    else
        pcall(SetNuiFocus, false, false)
    end
    if type(SetPauseMenuActive) == 'function' then pcall(SetPauseMenuActive, false) end
    pcall(SetPlayerControl, PlayerId(), true, 0)
    pcall(DisplayHud, true)
    pcall(DisplayRadar, true)
end)

exports('loading', function(state)
    characterLoading = state == true
end)
exports('IsCharacterReady', function()
    return characterGateActive ~= true and is_loaded_character == true
end)
exports('IsCharacterGateActive', function()
    return characterGateActive == true
end)

JRSForceNativeCursorThisFrame = function()
    if jrsNuiFocusWanted ~= true or jrsNuiCursorWanted ~= true then return end
    if jrsLoadingScreenCursorHandoffActive == true then return end

    -- SetNuiFocus(true, true) gives Chromium mouse focus, but on RedM the
    -- native pointer can remain hidden after the loading frontend is removed.
    -- Explicitly keep the native cursor visible/active while character UI owns
    -- the mouse. These calls are intentionally guarded for build compatibility.
    if type(SetMouseCursorVisible) == 'function' then
        pcall(SetMouseCursorVisible, true)
    end
    if type(SetMouseCursorThisFrame) == 'function' then
        pcall(SetMouseCursorThisFrame)
    elseif type(SetMouseCursorActiveThisFrame) == 'function' then
        pcall(SetMouseCursorActiveThisFrame)
    end
end

JRSCommitNuiFocus = function(centerCursor)
    local focus = jrsNuiFocusWanted == true
    local cursor = focus and jrsNuiCursorWanted == true

    -- RedM can report the CEF page as alive while its mouse focus was lost by
    -- the loading-screen frontend. Only mark our local state as applied when
    -- SetNuiFocus itself actually executed successfully.
    local ok = pcall(SetNuiFocus, focus, cursor)
    if type(SetNuiFocusKeepInput) == 'function' then
        pcall(SetNuiFocusKeepInput, false)
    end

    jrsNuiFocusApplied = ok and focus or false
    jrsNuiCursorApplied = ok and cursor or false
    if ok and focus and cursor then
        JRSForceNativeCursorThisFrame()
        if centerCursor then
            JRSNudgeCursorLocation(0.5, 0.5)
        end
    end

    return ok
end

-- SetCursorLocation(0.5, 0.5) is a no-op if RedM already believes the
-- cursor sits there from a previous recenter - no position delta, no
-- redraw. Land on a neighbouring point first so the real target is always
-- a genuine move.
JRSNudgeCursorLocation = function(x, y)
    if type(SetCursorLocation) ~= 'function' then return end
    local nx = x >= 0.5 and (x - 0.01) or (x + 0.01)
    local ny = y >= 0.5 and (y - 0.01) or (y + 0.01)
    pcall(SetCursorLocation, nx, ny)
    pcall(SetCursorLocation, x, y)
end

-- Acquiring CEF focus once is not reliable during the character bootstrap:
-- jrs_core/RedM may close their loading NUI a few frames later and silently
-- clear the cursor. A short, generation-safe acquisition burst survives that
-- race without continuously resetting the mouse while the player edits sliders.
local function JRSStartNuiFocusAcquire(centerCursor)
    if jrsNuiFocusWanted ~= true then return end

    jrsNuiFocusAcquireGeneration = jrsNuiFocusAcquireGeneration + 1
    local generation = jrsNuiFocusAcquireGeneration
    local delays = { 35, 90, 180, 360, 700, 1200, 1900 }

    CreateThread(function()
        local elapsed = 0
        for _, delay in ipairs(delays) do
            Wait(math.max(0, delay - elapsed))
            elapsed = delay
            if generation ~= jrsNuiFocusAcquireGeneration or jrsNuiFocusWanted ~= true then
                return
            end
            JRSCommitNuiFocus(false)
        end
    end)
end

JRSRecoverNuiCursor = function(centerCursor)
    if jrsNuiFocusWanted ~= true or jrsNuiCursorWanted ~= true then return false end
    -- RedM can silently no-op SetNuiFocus(true, true) when it already
    -- believes that is the current state - no state transition, no CEF
    -- pointer redraw - leaving the cursor invisible even though our tracked
    -- flags say focus/cursor are applied. Force a genuine off->on edge
    -- before recommitting, instead of repeating the same value.
    pcall(SetNuiFocus, false, false)
    -- Force the next commit to be treated as a real reacquisition even when
    -- IsNuiFocused() still returns true but the native cursor is invisible.
    jrsNuiFocusApplied = false
    jrsNuiCursorApplied = false
    JRSCommitNuiFocus(centerCursor == true)
    JRSStartNuiFocusAcquire(false)
    return true
end

JRSApplyNuiFocus = function(hasFocus, hasCursor, centerCursor, skipAcquireBurst)
    if GetResourceState('jrs_core') == 'started' then
        if hasFocus == true then
            pcall(function()
                exports.jrs_core:AcquireUI('jrs_character', {
                    focus = true, cursor = hasCursor == true, manageFocus = false,
                    force = true, kind = 'character'
                })
            end)
        else
            pcall(function()
                exports.jrs_core:ReleaseUI('jrs_character', { manageFocus = false, force = true })
            end)
        end
    end

    local previousFocus = jrsNuiFocusWanted == true
    local previousCursor = jrsNuiCursorWanted == true

    jrsNuiFocusWanted = hasFocus == true
    jrsNuiCursorWanted = jrsNuiFocusWanted and hasCursor == true

    if not jrsNuiFocusWanted then
        -- Cancel any delayed focus acquisition immediately when a menu closes.
        jrsNuiFocusAcquireGeneration = jrsNuiFocusAcquireGeneration + 1
        JRSCommitNuiFocus(false)
        return true
    end

    JRSCommitNuiFocus(centerCursor == true)

    -- While the external loading screen cursor is still visible, repeatedly
    -- re-applying SetNuiFocus causes RedM to resize/recenter the pointer. The
    -- selector can request a single focus acquisition and let the normal focus
    -- watchdog recover only genuine focus loss.
    if skipAcquireBurst ~= true and (
        not previousFocus
        or previousCursor ~= jrsNuiCursorWanted
        or centerCursor == true
    ) then
        JRSStartNuiFocusAcquire(false)
    end

    return true
end

JRSSetSelectorCursorOwnership = function(enabled, centerCursor)
    local wantsOwnership = enabled == true
    local alreadyReady = jrsSelectorCursorOwned == true
        and jrsNuiFocusWanted == true
        and jrsNuiCursorWanted == true

    jrsSelectorCursorOwned = wantsOwnership
    if not wantsOwnership then return true end

    -- Do not re-run SetNuiFocus / cursor recovery when the selector already has
    -- mouse focus. This is important while loadscreen_cursor 'yes' is active:
    -- repeated ownership calls otherwise snap the pointer back to screen centre.
    if alreadyReady then
        JRSForceNativeCursorThisFrame()
        return true
    end

    if jrsNuiFocusWanted == true and jrsNuiCursorWanted == true then
        JRSForceNativeCursorThisFrame()
        return true
    end

    JRSApplyNuiFocus(true, true, centerCursor == true)
    return true
end

-- jrs_loadingscreen may use this as a final ownership handoff. Never centre the
-- pointer here; preserve the exact position the player had on the loading UI.
RegisterNetEvent('jrs_character:client:claimSelectorCursor', function()
    JRSSetSelectorCursorOwnership(true, false)
end)

-- Release the loading-handoff cursor latch when Character Selection closes.
-- We intentionally do NOT claim it merely because the selector starts building:
-- until the SKIP control is exposed, the external loading screen must remain the
-- active interactive surface. loadingSkipAvailable/claimSelectorCursor enables it.
RegisterNetEvent('jrs_character:creatorSelectorState', function(open)
    if open ~= true then
        jrsSelectorCursorOwned = false
        jrsLoadingScreenCursorHandoffActive = false
    end
end)

JRSApplyPlayerControl = function(enabled)
    local requested = enabled == true
    local uiLockActive = characterGateActive == true or jrsNuiFocusWanted == true
    local allow = requested and not uiLockActive and GetGameTimer() >= jrsPostGateGuardUntil
    pcall(SetPlayerControl, PlayerId(), allow, 0)
    jrsPlayerControlLocked = not allow
    return allow
end

exports('ApplyNuiFocus', function(hasFocus, hasCursor, centerCursor)
    return JRSApplyNuiFocus(hasFocus, hasCursor, centerCursor)
end)

function loadingcharacter(state)
    characterLoading = state == true
end

CreateThread(function()
    Wait(0)
    publishCharacterGateState()

    local lastFocusEnforce = 0
    local lastCursorRecoveryForce = 0
    while true do
        local now = GetGameTimer()

        -- Selector owns the cursor until the player selects a character. If the
        -- Cfx loading frontend or another startup transition clears NUI focus,
        -- restore it immediately instead of waiting for a one-shot retry window.
        if jrsSelectorCursorOwned == true
            and (jrsNuiFocusWanted ~= true or jrsNuiCursorWanted ~= true) then
            jrsNuiFocusWanted = true
            jrsNuiCursorWanted = true
            JRSCommitNuiFocus(false)
            JRSStartNuiFocusAcquire(false)
        end

        local postGateGuard = now < jrsPostGateGuardUntil
        local uiLockActive = characterGateActive == true or jrsNuiFocusWanted == true or postGateGuard

        if uiLockActive then
            DisableAllControlActions(0)
            DisableAllControlActions(1)
            DisableAllControlActions(2)

            if characterGateActive == true then
                DisplayHud(false)
                DisplayRadar(false)
            end

            -- Never fight the frontend every frame. Calling
            -- SetPauseMenuActive(false) continuously can race CEF mouse ownership on
            -- some RedM builds. Controls are already disabled, so only close the
            -- pause frontend when it is actually active.
            if type(SetPauseMenuActive) == 'function' then
                local shouldClosePause = false
                if type(IsPauseMenuActive) == 'function' then
                    local ok, active = pcall(IsPauseMenuActive)
                    shouldClosePause = ok and active == true
                end
                if shouldClosePause then
                    pcall(SetPauseMenuActive, false)
                end
            end

            if not jrsPlayerControlLocked then
                pcall(SetPlayerControl, PlayerId(), false, 0)
                jrsPlayerControlLocked = true
            end

            -- Recover genuine focus theft (another resource, alt-tab, frontend).
            -- Cursor-only loss during loading-screen shutdown is handled by the
            -- bounded acquisition burst above and by the presentation-ready hook.
            -- Unlike SetNuiFocus, native cursor visibility is frame-scoped on
            -- some RedM builds. Keep drawing it every frame for selector/creator.
            if jrsNuiFocusWanted == true and jrsNuiCursorWanted == true then
                JRSForceNativeCursorThisFrame()
            end

            if jrsNuiFocusWanted and not jrsExternalUiFocusActive and now - lastFocusEnforce >= 450 then
                local needsFocus = jrsNuiFocusApplied ~= true or jrsNuiCursorApplied ~= jrsNuiCursorWanted
                if type(IsNuiFocused) == 'function' then
                    local ok, focused = pcall(IsNuiFocused)
                    if ok and focused ~= true then needsFocus = true end
                end
                if needsFocus then
                    JRSCommitNuiFocus(false)
                    JRSStartNuiFocusAcquire(false)
                end
                lastFocusEnforce = now
            end

            -- Safety net for the case above where SetNuiFocus/SetCursorLocation
            -- silently no-op because the engine already thinks that value is
            -- current: the tracked flags look correct so the 450ms check never
            -- re-fires, yet the native cursor was never actually redrawn. Force
            -- a genuine recovery periodically regardless of flag state. Coarse
            -- interval (4s) to avoid visible flicker while sliders are in use.
            if jrsNuiFocusWanted == true and jrsNuiCursorWanted == true and not jrsExternalUiFocusActive
                and now - lastCursorRecoveryForce >= 4000 then
                JRSRecoverNuiCursor(false)
                lastCursorRecoveryForce = now
            end

            Wait(0)
        else
            if jrsPlayerControlLocked then
                pcall(SetPlayerControl, PlayerId(), true, 0)
                jrsPlayerControlLocked = false
            end
            Wait(250)
        end
    end
end)

function getMaleFromLang()
    return 'Male'
end

-- ===== Utility Functions =====

function startanim(dict, name, time, flag, blendInSpeed, blendOutSpeed, loadTimeoutMs)
    dict = tostring(dict or '')
    name = tostring(name or '')
    if dict == '' or name == '' then return false end

    RequestAnimDict(dict)
    local deadline = GetGameTimer() + math.max(1000, math.floor(tonumber(loadTimeoutMs) or 8000))
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do
        Citizen.Wait(0)
    end

    if not HasAnimDictLoaded(dict) then
-- REMOVED-PRINT:         print(('^3[jrs_character] Could not load animation dictionary: %s^7'):format(dict))
        return false
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then
        return false
    end

    TaskPlayAnim(
        ped,
        dict,
        name,
        tonumber(blendInSpeed) or 1.0,
        tonumber(blendOutSpeed) or 1.0,
        math.floor(tonumber(time) or -1),
        math.floor(tonumber(flag) or 0),
        0.0,
        true,
        0,
        false,
        0,
        false
    )

    return true
end

function JRSPlaySpawnAnimation(context)
    local settings = type(Config.SpawnAnimation) == 'table' and Config.SpawnAnimation or {}
    if settings.Enabled == false then return false end

    context = tostring(context or 'characterSelect')
    if context == 'characterSelect' and settings.ApplyOnCharacterSelect == false then
        return false
    end
    if context == 'deathRespawn' and settings.ApplyAfterDeathRespawn == false then
        return false
    end

    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then return false end
    if IsPedInAnyVehicle(ped, false) or IsPedOnMount(ped) then return false end

    return startanim(
        settings.Dictionary or 'script_rc@bch2@leadout@rsc_6',
        settings.Name or 'wakeup_slow_charles',
        settings.Duration or -1,
        settings.Flag or 0,
        settings.BlendInSpeed or 1.0,
        settings.BlendOutSpeed or 1.0,
        settings.LoadTimeoutMs or 8000
    )
end

function CheckControls(func, pad, controls)
	if type(controls) == 'number' then
		return func(pad, controls)
	end

	for _, control in ipairs(controls) do
		if func(pad, control) then
			return true
		end
	end

	return false
end

function LoadModel(model)
	if IsModelInCdimage(model) then
		RequestModel(model)

		local deadline = GetGameTimer() + 10000
		while not HasModelLoaded(model) and GetGameTimer() < deadline do
			Wait(0)
		end

		return HasModelLoaded(model)
	else
		return false
	end
end

-- Shared across the consolidated modules; do not shadow the chunk declaration.
-- Scene preparation owns streaming focus. Model loading must not stop its scene.
RequestPlayerModelSafely = function(model, timeoutMs, context)
    timeoutMs = tonumber(timeoutMs) or 30000
    context = tostring(context or 'player-model')

    if not model or model == 0 or not JRSNativeTrue(IsModelValid(model)) or not JRSNativeTrue(IsModelInCdimage(model)) then
        CreatorDebug('^1[jrs_character] ' .. context .. ': invalid player model hash ' .. tostring(model) .. '^7')
        return false
    end

    if JRSNativeTrue(HasModelLoaded(model)) then return true end

    local deadline = GetGameTimer() + timeoutMs
    local nextRequestAt = 0
    while not JRSNativeTrue(HasModelLoaded(model)) and GetGameTimer() < deadline do
        local now = GetGameTimer()
        if now >= nextRequestAt then
            RequestModel(model, false)
            nextRequestAt = now + 250
        end
        Wait(0)
    end

    return JRSNativeTrue(HasModelLoaded(model))
end

function PerformRequest(hash)
    RequestModel(hash, 0)
    local attempts = 0
    while not HasModelLoaded(hash) do
        RequestModel(hash, 0)
        attempts = attempts + 1
        Citizen.Wait(100)
        if attempts >= 50 then break end
    end
end

function SetModel(name)
	local model = GetHashKey(name)
	local player = PlayerId()

	if not IsModelValid(model) then
        return
    end
	PerformRequest(model)

	if not HasModelLoaded(model) then
		CreatorDebug('^3[jrs_character] SetModel: model ' .. tostring(name) .. ' failed to load within timeout^7')
		return
	end

	Citizen.InvokeNative(0xED40380076A31506, player, model, true)
	local np = PlayerPedId()
	if DoesEntityExist(np) then
		SetEntityAlpha(np, 255)
		SetEntityVisible(np, true, false)
		ResetEntityAlpha(np)
	end
	SetModelAsNoLongerNeeded(model)
end

function SetClotheModel(name)
	local model = GetHashKey(name)
	local player = PlayerId()

	if not IsModelValid(model) then
        return
    end
	PerformRequest(model)

	if not HasModelLoaded(model) then
		CreatorDebug('^3[jrs_character] SetClotheModel: model ' .. tostring(name) .. ' failed to load within timeout^7')
		return
	end

	Citizen.InvokeNative(0xED40380076A31506, player, model, true)
	local np = PlayerPedId()
	if DoesEntityExist(np) then
		SetEntityAlpha(np, 255)
		SetEntityVisible(np, true, false)
		ResetEntityAlpha(np)
	end
	SetModelAsNoLongerNeeded(model)
end

function SetModelPed(pped, name)
	local model = GetHashKey(name)

	if not IsModelValid(model) then
        return
    end
	PerformRequest(model)

	if HasModelLoaded(model) then
		Citizen.InvokeNative(0x283978A15512B2FE, pped, true)
		SetModelAsNoLongerNeeded(model)
	end
end

function loadDataToPed(ped, hash)
    local readyLoad = false
    -- Bounded like HasBodyComponentsLoaded: a component that never streams
    -- used to spin here forever and freeze whatever called it.
    local deadline = GetGameTimer() + 5000
    while readyLoad == false and GetGameTimer() < deadline do
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, tonumber(hash), false, true, true)
        Wait(100)
        Citizen.InvokeNative(0x704C908E9C405136, ped)
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, 0)
        Wait(0)
        readyLoad = Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
    end
end

function HasBodyComponentsLoaded(ped, hash_for_load, text)
    local readyLoad = false
    local deadline = GetGameTimer() + 5000
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), hash_for_load, true, true, true)
    while readyLoad == false and GetGameTimer() < deadline do
        readyLoad = Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, PlayerPedId())
        Wait(0)
    end
    if readyLoad == false then
        CreatorDebug(("^3[jrs_character] HasBodyComponentsLoaded: component '%s' did not report ready within 5s, continuing.^7"):format(tostring(text)))
    end
    Citizen.InvokeNative(0x704C908E9C405136, PlayerPedId())
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, 0)
    return true
end

local reloadClothingCategories = {
    0x9925C067, -- Hat
    0x05E47CA6, -- EyeWear
    0x7505EF42, -- Mask
    0x5FC29285, -- NeckWear
    0x7A96FACA, -- NeckTies
    0x2026C46D, -- Shirt
    0x877A2CF7, -- Suspender
    0x485EE834, -- Vest
    0xE06D30CE, -- Coat
    0x0662AC34, -- CoatClosed
    0xAF14310B, -- Poncho
    0x3C1A74CD, -- Cloak
    0xEABE0032, -- Glove
    0x7A6BBD0B, -- RingRh
    0xF16A1D23, -- RingLh
    0x7BC10759, -- Bracelet
    0x9B2C8B89, -- Gunbelt
    0xA6D134C6, -- Belt
    0xFAE9107F, -- Buckle
    0xB6B6122D, -- Holster
    0x1D4C528A, -- Pant
    0xA0E3AB7F, -- Skirt
    0x3107499B, -- Chap
    0x777EC6EF, -- Boots
    0x18729F39, -- Spurs
    0xF1542D11, -- GunbeltAccs
    0x514ADCEA, -- Spats
    0x91CE9B20, -- Gauntlets
    0x83887E88, -- Loadouts
    0x79D7DF96, -- Accessories
    0x94504D26, -- Satchels
}

local function ClearReloadClothing(ped)
    for _, categoryHash in ipairs(reloadClothingCategories) do
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, categoryHash, 0)
    end
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
end

local DEFAULT_BODY_TYPE = 61606861
local DEFAULT_WAIST_TYPE = -2045421226

-- Older/new characters can contain zeroes when the creator's default controls
-- never fired a change callback. Zero is not a valid metaped component hash and
-- produces invisible gaps after SetPlayerModel (notably on /re).
local function EnsureValidBodyComponents()
    local nation = tonumber(Skin_Table["Nation"])
    if not nation or nation < 1 or nation > 6 then
        nation = 1
        Skin_Table["Nation"] = nation
    end

    local gender = Skin_Table["sex"] == Config.ModelNames.female and "Female" or "Male"
    local genderDefaults = Config.DefaultChar and (Config.DefaultChar[gender] or Config.DefaultChar["Male"])
    local defaults = genderDefaults and (genderDefaults[nation] or genderDefaults[1])
    local function componentHash(category)
        if defaults and defaults[category] and defaults[category][1] then
            return tonumber("0x" .. defaults[category][1])
        end
        return 0
    end

    if not Skin_Table["HeadType"] or Skin_Table["HeadType"] == 0 then
        Skin_Table["HeadType"] = componentHash("Heads")
    end
    if not Skin_Table["Body"] or Skin_Table["Body"] == 0 then
        Skin_Table["Body"] = componentHash("Body")
    end
    if not Skin_Table["LegsType"] or Skin_Table["LegsType"] == 0 then
        Skin_Table["LegsType"] = componentHash("Legs")
    end
    if not Skin_Table["BodyType"] or Skin_Table["BodyType"] == 0 then
        Skin_Table["BodyType"] = DEFAULT_BODY_TYPE
    end
    if not Skin_Table["Waist"] or Skin_Table["Waist"] == 0 then
        Skin_Table["Waist"] = DEFAULT_WAIST_TYPE
    end
end

function Data_Character_Load(state)
    EnsureValidBodyComponents()
    local model = GetHashKey(Skin_Table["sex"])
    RequestModel(model)
    local modelDeadline = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < modelDeadline do
        RequestModel(model)
        Citizen.Wait(0)
    end
    if not HasModelLoaded(model) then
        CreatorDebug("^3[jrs_character] Data_Character_Load: player model failed to stream within 8s, continuing with best-effort ped.^7")
    end
    JRSSafeSetPlayerModel(model)

    Citizen.Wait(0)
    HasBodyComponentsLoaded(0xB3966C9, Skin_Table["Body"], "Body")
    HasBodyComponentsLoaded(0x378AD10C, Skin_Table["HeadType"], "Head")
    HasBodyComponentsLoaded(0x823687F5, Skin_Table["LegsType"], "Legs")
    Citizen.Wait(0)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.Wait(0)
    for i=1,6 do
        if Skin_Table["Nation"] == i then
            local defaultGender = Skin_Table["sex"] == Config.ModelNames.female and "Female" or "Male"
            for k,v in pairs(Config.DefaultChar[defaultGender][i]) do
                if k == "Heads" then
                    for x,y in pairs(v) do
                        if x == 1 then
                            local hash = ("0x"..y)
                            HeadCategory = i
                            Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), tonumber(hash), true, true, true)
                        end
                    end
                end
            end
        end
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["Body"], false, true, true)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["HeadType"], false, true, true)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["BodyType"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    ClearReloadClothing(PlayerPedId())
    Citizen.Wait(50)
    if Skin_Table["Eyes"] ~= -1 then
        HasBodyComponentsLoaded(0xEA24B45E, Skin_Table["Eyes"], "EYES")
    end
    if Skin_Table["Hair"] ~= -1 then
        HasBodyComponentsLoaded(0x864B03AE, Skin_Table["Hair"], "HAIR")
    end
    if Skin_Table["Beard"] ~= -1 then
        HasBodyComponentsLoaded(0xF8016BCA, Skin_Table["Beard"], "BEARD")
    end
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["BodyType"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    if Clothe_Table["Hat"] ~= -1 then
        HasBodyComponentsLoaded(0x9925C067, Clothe_Table["Hat"], "HAT")
    end
    if Clothe_Table["EyeWear"] ~= -1 then
        HasBodyComponentsLoaded(0x5E47CA6, Clothe_Table["EyeWear"], "EyeWear")
    end
    if Clothe_Table["Mask"] ~= -1 then
        HasBodyComponentsLoaded(0x7505EF42, Clothe_Table["Mask"], "Mask")
    end
    if Clothe_Table["NeckWear"] ~= -1 then
        HasBodyComponentsLoaded(0x5FC29285, Clothe_Table["NeckWear"], "NeckWear")
    end
    if Clothe_Table["Suspender"] ~= -1 then
        HasBodyComponentsLoaded(0x877A2CF7, Clothe_Table["Suspender"], "Suspender")
    end
    if Clothe_Table["NeckTies"] ~= -1 then
        HasBodyComponentsLoaded(0x7A96FACA, Clothe_Table["NeckTies"], "NeckTies")
    end
    if Clothe_Table["Shirt"] ~= -1 then
        HasBodyComponentsLoaded(0x2026C46D, Clothe_Table["Shirt"], "Shirt")
    end
    if Clothe_Table["Vest"] ~= -1 then
        HasBodyComponentsLoaded(0x485EE834, Clothe_Table["Vest"], "Vest")
    end
    if Clothe_Table["Coat"] ~= -1 then
        HasBodyComponentsLoaded(0xE06D30CE, Clothe_Table["Coat"], "Coat")
    end
    if Clothe_Table["CoatClosed"] ~= -1 then
        HasBodyComponentsLoaded(0x662AC34, Clothe_Table["CoatClosed"], "CoatClosed")
    end
    if Clothe_Table["Poncho"] ~= -1 then
        HasBodyComponentsLoaded(0xAF14310B, Clothe_Table["Poncho"], "Poncho")
    end
    if Clothe_Table["Cloak"] ~= -1 then
        HasBodyComponentsLoaded(0x3C1A74CD, Clothe_Table["Cloak"], "Cloak")
    end
    if Clothe_Table["Glove"] ~= -1 then
        HasBodyComponentsLoaded(0xEABE0032, Clothe_Table["Glove"], "Glove")
    end
    if Clothe_Table["RingRh"] ~= -1 then
        HasBodyComponentsLoaded(0x7A6BBD0B, Clothe_Table["RingRh"], "RingRh")
    end
    if Clothe_Table["RingLh"] ~= -1 then
        HasBodyComponentsLoaded(0xF16A1D23, Clothe_Table["RingLh"], "RingLh")
    end
    if Clothe_Table["Bracelet"] ~= -1 then
        HasBodyComponentsLoaded(0x7BC10759, Clothe_Table["Bracelet"], "Bracelet")
    end
    if Clothe_Table["Buckle"] ~= -1 then
        HasBodyComponentsLoaded(0xFAE9107F, Clothe_Table["Buckle"], "Buckle")
    end
    if Clothe_Table["Chap"] ~= -1 then
        HasBodyComponentsLoaded(0x3107499B, Clothe_Table["Chap"], "Chap")
    end
    if Clothe_Table["Skirt"] ~= -1 then
        HasBodyComponentsLoaded(0xA0E3AB7F, Clothe_Table["Skirt"], "Skirt")
    end
    if Clothe_Table["Pant"] == -1 then
        HasBodyComponentsLoaded(0x823687F5, Skin_Table["LegsType"], "Legs")
    else
        HasBodyComponentsLoaded(0x1D4C528A, Clothe_Table["Pant"], "Pant")
    end
    if Clothe_Table["Boots"] ~= -1 then
        HasBodyComponentsLoaded(0x777EC6EF, Clothe_Table["Boots"], "Boots")
    end
    if Clothe_Table["Spurs"] ~= -1 then
        HasBodyComponentsLoaded(0x18729F39, Clothe_Table["Spurs"], "Spurs")
    end
    if Clothe_Table["Spats"] ~= -1 then
        HasBodyComponentsLoaded(0x514ADCEA, Clothe_Table["Spats"], "Spats")
    end
    if Clothe_Table["Gauntlets"] ~= -1 then
        HasBodyComponentsLoaded(0x91CE9B20, Clothe_Table["Gauntlets"], "Gauntlets")
    end
    if Clothe_Table["Loadouts"] ~= -1 then
        HasBodyComponentsLoaded(0x83887E88, Clothe_Table["Loadouts"], "Loadouts")
    end
    if Clothe_Table["Accessories"] ~= -1 then
        HasBodyComponentsLoaded(0x79D7DF96, Clothe_Table["Accessories"], "Accessories")
    end
    if Clothe_Table["Belt"] ~= -1 then
        HasBodyComponentsLoaded(0xA6D134C6, Clothe_Table["Belt"], "Belt")
    end
    if Clothe_Table["Gunbelt"] ~= -1 then
        HasBodyComponentsLoaded(0x9B2C8B89, Clothe_Table["Gunbelt"], "Gunbelt")
    end
    if Clothe_Table["GunbeltAccs"] ~= -1 then
        HasBodyComponentsLoaded(0xF1542D11, Clothe_Table["GunbeltAccs"], "GunbeltAccs")
    end
    if Clothe_Table["Satchels"] ~= -1 then
        HasBodyComponentsLoaded(0x94504D26, Clothe_Table["Satchels"], "Satchels")
    end
    if Clothe_Table["Holster"] ~= -1 then
        HasBodyComponentsLoaded(0xB6B6122D, Clothe_Table["Holster"], "Holster")
    end
    if Skin_Table["Teeth"] ~= -1 and Skin_Table["Teeth"] ~= nil then
        HasBodyComponentsLoaded(0x96EDAE5C, Skin_Table["Teeth"], "Teeth")
    end
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0x3F1F01E5, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0xDA0E2C55, 0)
    Citizen.InvokeNative(0x704C908E9C405136, PlayerPedId())
    Citizen.Wait(0)
    Citizen.InvokeNative(0x25ACFC650B65C538, PlayerPedId(), Skin_Table["Scale"])
    Citizen.Wait(0)
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x84D6, Skin_Table["HeadSize"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x3303, Skin_Table["EyeBrowH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x2FF9, Skin_Table["EyeBrowW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x4AD1, Skin_Table["EyeBrowD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xC04F, Skin_Table["EarsH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xB6CE, Skin_Table["EarsW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x2844, Skin_Table["EarsD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xED30, Skin_Table["EarsL"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x8B2B, Skin_Table["EyeLidH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x1B6B, Skin_Table["EyeLidW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xEE44, Skin_Table["EyeD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xD266, Skin_Table["EyeAng"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xA54E, Skin_Table["EyeDis"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xDDFB, Skin_Table["EyeH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x6E7F, Skin_Table["NoseW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x3471, Skin_Table["NoseS"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x03F5, Skin_Table["NoseH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x34B1, Skin_Table["NoseAng"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xF156, Skin_Table["NoseC"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x561E, Skin_Table["NoseDis"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x6A0B, Skin_Table["CheekBonesH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xABCF, Skin_Table["CheekBonesW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x358D, Skin_Table["CheekBonesD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xF065, Skin_Table["MouthW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xAA69, Skin_Table["MouthD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x7AC3, Skin_Table["MouthX"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x410D, Skin_Table["MouthY"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x1A00, Skin_Table["ULiphH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x91C1, Skin_Table["ULiphW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xC375, Skin_Table["ULiphD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xBB4D, Skin_Table["LLiphH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xB0B0, Skin_Table["LLiphW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x5D16, Skin_Table["LLiphD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x8D0A, Skin_Table["JawH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xEBAE, Skin_Table["JawW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x1DF6, Skin_Table["JawD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x3C0F, Skin_Table["ChinH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xC3B2, Skin_Table["ChinW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xE323, Skin_Table["ChinD"]);
    Citizen.Wait(0)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["HeadType"], false, true, true)
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["BodyType"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.Wait(0)
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0xEA24B45E, 0);
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0x864B03AE, 0);
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0xF8016BCA, 0);
    ClearReloadClothing(PlayerPedId())
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0x96EDAE5C, 0);

    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0xB3966C9, 0);
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0x378AD10C, 0);
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0x823687F5, 0);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, 0);
    Citizen.Wait(0)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Body"],       true, true, false);
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["HeadType"],       true, true, false);
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["LegsType"],       true, true, false);
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Eyes"],       true, true, false);
    if Skin_Table["Teeth"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Teeth"],       true, true, false);
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, 0);
    Citizen.Wait(500)
    if Skin_Table["Beard"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Beard"],       true, true, false);
    end
    if Skin_Table["Hair"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Hair"],       true, true, false);
    end
    if Clothe_Table["Hat"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Hat"],       true, true, false);
    end
    if Clothe_Table["EyeWear"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["EyeWear"],   true, true, false);
    end
    if Clothe_Table["Mask"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Mask"],      true, true, false);
    end
    if Clothe_Table["NeckWear"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["NeckWear"],  true, true, false);
    end
    if Clothe_Table["Suspender"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Suspender"], true, true, false);
    end
    if Clothe_Table["NeckTies"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["NeckTies"],  true, true, false);
    end
    if Clothe_Table["Shirt"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Shirt"],     true, true, false);
    end
    if Clothe_Table["Vest"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Vest"],      true, true, false);
    end
    if Clothe_Table["Coat"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Coat"],      true, true, false);
    end
    if Clothe_Table["CoatClosed"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["CoatClosed"],true, true, false);
    end
    if Clothe_Table["Poncho"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Poncho"],    true, true, false);
    end
    if Clothe_Table["Cloak"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Cloak"],     true, true, false);
    end
    if Clothe_Table["Glove"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Glove"],    true, true, false);
    end
    if Clothe_Table["RingRh"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["RingRh"],   true, true, false);
    end
    if Clothe_Table["RingLh"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["RingLh"],   true, true, false);
    end
    if Clothe_Table["Bracelet"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Bracelet"], true, true, false);
    end
    if Clothe_Table["Buckle"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Buckle"],   true, true, false);
    end
    if Clothe_Table["Chap"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Chap"],     true, true, false);
    end
    if Clothe_Table["Skirt"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Skirt"],    true, true, false);
    end
    if Clothe_Table["Pant"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Pant"],     true, true, false);
    end
    if Clothe_Table["Boots"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Boots"],    true, true, false);
    end
    if Clothe_Table["Spurs"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Spurs"],    true, true, false);
    end
    if Clothe_Table["Spats"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Spats"],   true, true, false);
    end
    if Clothe_Table["Gauntlets"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Gauntlets"],true, true, false);
    end
    if Clothe_Table["Loadouts"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Loadouts"], true, true, false);
    end
    if Clothe_Table["Accessories"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Accessories"],true, true, false);
    end
    if Clothe_Table["Belt"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Belt"], true, true, false);
    end
    if Clothe_Table["Gunbelt"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Gunbelt"], true, true, false);
    end
    if Clothe_Table["GunbeltAccs"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["GunbeltAccs"], true, true, false);
    end
    if Clothe_Table["Satchels"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Satchels"], true, true, false);
    end
    if Clothe_Table["Holster"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Clothe_Table["Holster"], true, true, false);
    end
    if Skin_Table["Teeth"] ~= -1 and Skin_Table["Teeth"] ~= nil then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Teeth"], true, true, false);
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);

    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"])
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    reload_scars()
    if Skin_Table["HairAccesorie"] ~= -1 and Skin_Table["HairAccesorie"] ~= nil then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["HairAccesorie"], true, true, false);
    end
    Citizen.InvokeNative(0x25ACFC650B65C538, PlayerPedId(), Skin_Table["Scale"])
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.Wait(0)
     if state == true then
         TriggerEvent("jrs_inventory:reload_weap")
     end

end

function ReloadCloth()
    EnsureValidBodyComponents()
    local model = GetHashKey(Skin_Table["sex"])
    RequestModel(model)
    local modelDeadline = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < modelDeadline do
        Citizen.Wait(0)
    end
    if not HasModelLoaded(model) then
        CreatorDebug("^3[jrs_character] ReloadCloth: player model failed to stream within 8s, continuing with best-effort ped.^7")
    end
    JRSSafeSetPlayerModel(model)

    Citizen.Wait(50)
    HasBodyComponentsLoaded(0xB3966C9, Skin_Table["Body"], "Body")
    HasBodyComponentsLoaded(0x378AD10C, Skin_Table["HeadType"], "Head")
    HasBodyComponentsLoaded(0x823687F5, Skin_Table["LegsType"], "Legs")
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    for i=1,6 do
        if Skin_Table["Nation"] == i then
            local defaultGender = Skin_Table["sex"] == Config.ModelNames.female and "Female" or "Male"
            for k,v in pairs(Config.DefaultChar[defaultGender][i]) do
                if k == "Heads" then
                    for x,y in pairs(v) do
                        if x == 1 then
                            local hash = ("0x"..y)
                            HeadCategory = i
                            Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), tonumber(hash), true, true, true)
                        end
                    end
                end
            end
        end
    end

    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["Body"], false, true, true)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["HeadType"], false, true, true)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["BodyType"], false, true, true);
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0x3F1F01E5, 0)
    Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), 0xDA0E2C55, 0)
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x84D6, Skin_Table["HeadSize"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x3303, Skin_Table["EyeBrowH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x2FF9, Skin_Table["EyeBrowW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x4AD1, Skin_Table["EyeBrowD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xC04F, Skin_Table["EarsH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xB6CE, Skin_Table["EarsW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x2844, Skin_Table["EarsD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xED30, Skin_Table["EarsL"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x8B2B, Skin_Table["EyeLidH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x1B6B, Skin_Table["EyeLidW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xEE44, Skin_Table["EyeD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xD266, Skin_Table["EyeAng"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xA54E, Skin_Table["EyeDis"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xDDFB, Skin_Table["EyeH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x6E7F, Skin_Table["NoseW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x3471, Skin_Table["NoseS"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x03F5, Skin_Table["NoseH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x34B1, Skin_Table["NoseAng"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xF156, Skin_Table["NoseC"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x561E, Skin_Table["NoseDis"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x6A0B, Skin_Table["CheekBonesH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xABCF, Skin_Table["CheekBonesW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x358D, Skin_Table["CheekBonesD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xF065, Skin_Table["MouthW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xAA69, Skin_Table["MouthD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x7AC3, Skin_Table["MouthX"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x410D, Skin_Table["MouthY"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x1A00, Skin_Table["ULiphH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x91C1, Skin_Table["ULiphW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xC375, Skin_Table["ULiphD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xBB4D, Skin_Table["LLiphH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xB0B0, Skin_Table["LLiphW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x5D16, Skin_Table["LLiphD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x8D0A, Skin_Table["JawH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xEBAE, Skin_Table["JawW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x1DF6, Skin_Table["JawD"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0x3C0F, Skin_Table["ChinH"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xC3B2, Skin_Table["ChinW"]);
    Citizen.InvokeNative(0x5653AB26C82938CF, PlayerPedId(), 0xE323, Skin_Table["ChinD"]);
    Citizen.Wait(0)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    local readyLoad = false
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["HeadType"], false, true, true)
    local readyDeadline = GetGameTimer() + 5000
    while readyLoad == false and GetGameTimer() < readyDeadline do
        readyLoad = Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, PlayerPedId())
        Wait(0)
    end

    local readyLoad = false
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["BodyType"], false, true, true)
    local readyDeadline = GetGameTimer() + 5000
    while readyLoad == false and GetGameTimer() < readyDeadline do
        readyLoad = Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, PlayerPedId())
        Wait(0)
    end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(), Skin_Table["HeadType"], false, true, true)
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["BodyType"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.Wait(0)

    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Body"],       true, true, false);
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["HeadType"],       true, true, false);
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["LegsType"],       true, true, false);
    Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Eyes"],       true, true, false);
    if Skin_Table["Teeth"] ~= -1 then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["Teeth"],       true, true, false);
    end

    if Skin_Table["Eyes"] ~= -1 then
        HasBodyComponentsLoaded(0xEA24B45E, Skin_Table["Eyes"], "EYES")
    end
    if Skin_Table["Hair"] ~= -1 then
        HasBodyComponentsLoaded(0x864B03AE, Skin_Table["Hair"], "HAIR")
    end
    if Skin_Table["Beard"] ~= -1 then
        HasBodyComponentsLoaded(0xF8016BCA, Skin_Table["Beard"], "BEARD")
    end

    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);

    ClearReloadClothing(PlayerPedId())
    Citizen.Wait(100)
    if Clothe_Table["Hat"] ~= -1 then
        HasBodyComponentsLoaded(0x9925C067, Clothe_Table["Hat"], "HAT")
    end
    if Clothe_Table["EyeWear"] ~= -1 then
        HasBodyComponentsLoaded(0x5E47CA6, Clothe_Table["EyeWear"], "EyeWear")
    end
    if Clothe_Table["Mask"] ~= -1 then
        HasBodyComponentsLoaded(0x7505EF42, Clothe_Table["Mask"], "Mask")
    end
    if Clothe_Table["Shirt"] ~= -1 then
        HasBodyComponentsLoaded(0x2026C46D, Clothe_Table["Shirt"], "Shirt")
    end
    Citizen.Wait(0)
    if Clothe_Table["Vest"] ~= -1 then
        HasBodyComponentsLoaded(0x485EE834, Clothe_Table["Vest"], "Vest")
    end
    if Clothe_Table["NeckWear"] ~= -1 then
        HasBodyComponentsLoaded(0x5FC29285, Clothe_Table["NeckWear"], "NeckWear")
    end
    if Clothe_Table["Suspender"] ~= -1 then
        HasBodyComponentsLoaded(0x877A2CF7, Clothe_Table["Suspender"], "Suspender")
    end
    if Clothe_Table["NeckTies"] ~= -1 then
        HasBodyComponentsLoaded(0x7A96FACA, Clothe_Table["NeckTies"], "NeckTies")
    end
    if Clothe_Table["Coat"] ~= -1 then
        HasBodyComponentsLoaded(0xE06D30CE, Clothe_Table["Coat"], "Coat")
    end
    if Clothe_Table["CoatClosed"] ~= -1 then
        HasBodyComponentsLoaded(0x662AC34, Clothe_Table["CoatClosed"], "CoatClosed")
    end
    if Clothe_Table["Poncho"] ~= -1 then
        HasBodyComponentsLoaded(0xAF14310B, Clothe_Table["Poncho"], "Poncho")
    end
    if Clothe_Table["Cloak"] ~= -1 then
        HasBodyComponentsLoaded(0x3C1A74CD, Clothe_Table["Cloak"], "Cloak")
    end
    if Clothe_Table["Glove"] ~= -1 then
        HasBodyComponentsLoaded(0xEABE0032, Clothe_Table["Glove"], "Glove")
    end
    if Clothe_Table["RingRh"] ~= -1 then
        HasBodyComponentsLoaded(0x7A6BBD0B, Clothe_Table["RingRh"], "RingRh")
    end
    if Clothe_Table["RingLh"] ~= -1 then
        HasBodyComponentsLoaded(0xF16A1D23, Clothe_Table["RingLh"], "RingLh")
    end
    if Clothe_Table["Bracelet"] ~= -1 then
        HasBodyComponentsLoaded(0x7BC10759, Clothe_Table["Bracelet"], "Bracelet")
    end
    if Clothe_Table["Buckle"] ~= -1 then
        HasBodyComponentsLoaded(0xFAE9107F, Clothe_Table["Buckle"], "Buckle")
    end
    if Clothe_Table["Chap"] ~= -1 then
        HasBodyComponentsLoaded(0x3107499B, Clothe_Table["Chap"], "Chap")
    end
    if Clothe_Table["Skirt"] ~= -1 then
        HasBodyComponentsLoaded(0xA0E3AB7F, Clothe_Table["Skirt"], "Skirt")
    end
    if Clothe_Table["Pant"] == -1 then
        HasBodyComponentsLoaded(0x823687F5, Skin_Table["LegsType"], "Legs")
    else
        HasBodyComponentsLoaded(0x1D4C528A, Clothe_Table["Pant"], "Pant")
    end
    if Clothe_Table["Boots"] ~= -1 then
        HasBodyComponentsLoaded(0x777EC6EF, Clothe_Table["Boots"], "Boots")
    end
    if Clothe_Table["Spurs"] ~= -1 then
        HasBodyComponentsLoaded(0x18729F39, Clothe_Table["Spurs"], "Spurs")
    end
    if Clothe_Table["Spats"] ~= -1 then
        HasBodyComponentsLoaded(0x514ADCEA, Clothe_Table["Spats"], "Spats")
    end
    if Clothe_Table["Gauntlets"] ~= -1 then
        HasBodyComponentsLoaded(0x91CE9B20, Clothe_Table["Gauntlets"], "Gauntlets")
    end
    if Clothe_Table["Loadouts"] ~= -1 then
        HasBodyComponentsLoaded(0x83887E88, Clothe_Table["Loadouts"], "Loadouts")
    end
    if Clothe_Table["Accessories"] ~= -1 then
        HasBodyComponentsLoaded(0x79D7DF96, Clothe_Table["Accessories"], "Accessories")
    end
    if Clothe_Table["Belt"] ~= -1 then
        HasBodyComponentsLoaded(0xA6D134C6, Clothe_Table["Belt"], "Belt")
    end
    if Clothe_Table["Gunbelt"] ~= -1 then
        HasBodyComponentsLoaded(0x9B2C8B89, Clothe_Table["Gunbelt"], "Gunbelt")
    end
    if Clothe_Table["GunbeltAccs"] ~= -1 then
        HasBodyComponentsLoaded(0xF1542D11, Clothe_Table["GunbeltAccs"], "GunbeltAccs")
    end
    if Clothe_Table["Satchels"] ~= -1 then
        HasBodyComponentsLoaded(0x94504D26, Clothe_Table["Satchels"], "Satchels")
    end
    if Clothe_Table["Holster"] ~= -1 then
        HasBodyComponentsLoaded(0xB6B6122D, Clothe_Table["Holster"], "Holster")
    end
    if Skin_Table["Teeth"] ~= -1 and Skin_Table["Teeth"] ~= nil then
        HasBodyComponentsLoaded(0x96EDAE5C, Skin_Table["Teeth"], "Teeth")
    end
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"])

    Citizen.InvokeNative(0x1902C4CFCC5BE57C, PlayerPedId(), Skin_Table["Waist"], false, true, true);

    reload_scars()
    Citizen.InvokeNative(0x25ACFC650B65C538, PlayerPedId(), Skin_Table["Scale"])
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, false);
    Citizen.Wait(0)
    if Skin_Table["HairAccesorie"] ~= -1 and Skin_Table["HairAccesorie"] ~= nil then
        Citizen.InvokeNative(0xD3A7B003ED343FD9, PlayerPedId(),  Skin_Table["HairAccesorie"], true, true, false);
    end
end

function reload_scars()
    if Skin_Table["scars_tx_id"] ~= nil  and Skin_Table["scars_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "scars", Skin_Table["scars_visibility"], Skin_Table["scars_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["scars_opacity"])
    end
    if Skin_Table["spots_tx_id"] ~= nil  and Skin_Table["spots_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "spots", Skin_Table["spots_visibility"], Skin_Table["spots_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["spots_opacity"])
    end
    if Skin_Table["disc_tx_id"] ~= nil  and Skin_Table["disc_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "disc", Skin_Table["disc_visibility"], Skin_Table["disc_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["disc_opacity"])
    end
    if Skin_Table["complex_tx_id"] ~= nil  and Skin_Table["complex_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "complex", Skin_Table["complex_visibility"], Skin_Table["complex_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["complex_opacity"])
    end
    if Skin_Table["acne_tx_id"] ~= nil  and Skin_Table["acne_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "acne", Skin_Table["acne_visibility"], Skin_Table["acne_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["acne_opacity"])
    end
    if Skin_Table["ageing_tx_id"] ~= nil  and Skin_Table["ageing_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "ageing", Skin_Table["ageing_visibility"], Skin_Table["ageing_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["ageing_opacity"])
    end
    if Skin_Table["freckles_tx_id"] ~= nil  and Skin_Table["freckles_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "freckles", Skin_Table["freckles_visibility"], Skin_Table["freckles_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["freckles_opacity"])
    end
    if Skin_Table["moles_tx_id"] ~= nil  and Skin_Table["moles_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "moles", Skin_Table["moles_visibility"], Skin_Table["moles_tx_id"], 0, 0, 1, 1.0, 0, 1, 0,0,0,1,Skin_Table["moles_opacity"])
    end
    if Skin_Table["eyebrows_tx_id"] ~= nil  and Skin_Table["eyebrows_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "eyebrows", Skin_Table["eyebrows_visibility"], Skin_Table["eyebrows_tx_id"], 1, 0, 0, 1.0, 0, 1, Skin_Table["eyebrows_color"],0,0,1,Skin_Table["eyebrows_opacity"])
    end
    if Skin_Table["blush_tx_id"] ~= nil  and Skin_Table["blush_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "blush", Skin_Table["blush_visibility"], Skin_Table["blush_tx_id"], 1, 0, 0, 1.0, 0, 1, Skin_Table["blush_color_1"],0,0,1,Skin_Table["blush_opacity"])
    end
    if Skin_Table["eyeliners_tx_id"] ~= nil  and Skin_Table["eyeliners_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "eyeliners", Skin_Table["eyeliners_visibility"], 1, 1, 0, 0, 1.0, 0, 1, Skin_Table["eyeliners_color_1"],0,0,Skin_Table["eyeliners_tx_id"],Skin_Table["eyeliners_opacity"])
    end
    if Skin_Table["lipsticks_tx_id"] ~= nil  and Skin_Table["lipsticks_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "lipsticks", Skin_Table["lipsticks_visibility"], 1, 1, 0, 0, 1.0, 0, 1, Skin_Table["lipsticks_color_1"],Skin_Table["lipsticks_color_2"],Skin_Table["lipsticks_color_3"], Skin_Table["lipsticks_tx_id"], Skin_Table["lipsticks_opacity"])
    end
    if Skin_Table["shadows_tx_id"] ~= nil  and Skin_Table["shadows_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "shadows", Skin_Table["shadows_visibility"], 1, 1, 0, 0, 1.0, 0, 1, Skin_Table["shadows_color_1"],Skin_Table["shadows_color_2"],Skin_Table["shadows_color_3"],Skin_Table["shadows_tx_id"],Skin_Table["shadows_opacity"])
    end
    if Skin_Table["beardstabble_tx_id"] ~= nil  and Skin_Table["beardstabble_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "beardstabble", Skin_Table["beardstabble_visibility"], 1, 1, 0, 0, 1.0, 0, 1, Skin_Table["beardstabble_color_1"],Skin_Table["beardstabble_color_2"],Skin_Table["beardstabble_color_3"],Skin_Table["beardstabble_tx_id"],Skin_Table["beardstabble_opacity"])
    end
    if Skin_Table["hairstable_opacity"] ~= nil then
        TriggerEvent("jrs_characters:colors", "hair",1, 1,1,0,0,1.0,0,1,Skin_Table["hairstable_color"],0,0,1,Skin_Table["hairstable_opacity"])
    end
end

function Mount_States()
    local pped = PlayerPedId()
    local playerHash = GetHashKey("PLAYER")

    if (IsControlPressed(0, 0xCEFD9220)) then
        Citizen.InvokeNative(0xBF25EB89375A37AD, 1, playerHash, playerHash);
        active_block = true
        Citizen.Wait(4000)
    end
    if (IsPedOnMount(pped) and IsPedInAnyVehicle(pped, false) and active_block == true) then
        Citizen.InvokeNative(0xBF25EB89375A37AD, 5, playerHash, playerHash)
        active_block = false
    elseif (active_block == true and (IsPedOnMount(pped) or IsPedInAnyVehicle(pped, false))) then
        if (IsPedInAnyVehicle(pped, false)) then
            Citizen.InvokeNative(0xBF25EB89375A37AD, 5, playerHash, playerHash)
            active_block = false
        elseif (GetPedInVehicleSeat(GetMount(pped), -1) == pped) then
            Citizen.InvokeNative(0xBF25EB89375A37AD, 5, playerHash, playerHash);
            active_block = false
        end
    else
        if active_block == true and not IsPedOnMount(pped) then
            Citizen.InvokeNative(0xBF25EB89375A37AD, 5, playerHash, playerHash)
            active_block = false
        end
    end
end

-- ===== Death Camera Functions =====

function StartDeathCam()
    Citizen.CreateThread(function()
        ClearFocus()
        local playerPed = PlayerPedId()
        cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", GetEntityCoords(playerPed), 0, 0, 0, GetGameplayCamFov())
        SetCamActive(cam, true)
        RenderScriptCams(true, true, 1000, true, false)
    end)
end

function EndDeathCam()
    Citizen.CreateThread(function()
        NetworkSetInSpectatorMode(false, PlayerPedId())
        ClearFocus()
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)
        cam = nil
    end)
end

function ProcessCamControls()
    Citizen.CreateThread(function()
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local newPos = ProcessNewPosition()
        SetCamCoord(cam, newPos.x, newPos.y, newPos.z)
        PointCamAtCoord(cam, playerCoords.x, playerCoords.y, playerCoords.z + 0.5)
    end)
end

function ProcessNewPosition()
    local mouseX = 0.0
    local mouseY = 0.0
    if (IsInputDisabled(0)) then
        mouseX = GetDisabledControlNormal(1, 0x4D8FB4C1) * 1.5
        mouseY = GetDisabledControlNormal(1, 0xFDA83190) * 1.5
    else
        mouseX = GetDisabledControlNormal(1, 0x4D8FB4C1) * 0.5
        mouseY = GetDisabledControlNormal(1, 0xFDA83190) * 0.5
    end
    angleZ = angleZ - mouseX
    angleY = angleY + mouseY

    if (angleY > 89.0) then angleY = 89.0 elseif (angleY < -89.0) then angleY = -89.0 end
    local pCoords = GetEntityCoords(PlayerPedId())
    local behindCam = {
        x = pCoords.x + ((Cos(angleZ) * Cos(angleY)) + (Cos(angleY) * Cos(angleZ))) / 2 * (3.0 + 0.5),
        y = pCoords.y + ((Sin(angleZ) * Cos(angleY)) + (Cos(angleY) * Sin(angleZ))) / 2 * (3.0 + 0.5),
        z = pCoords.z + ((Sin(angleY))) * (3.0 + 0.5)
    }
    local rayHandle = StartShapeTestRay(pCoords.x, pCoords.y, pCoords.z + 0.5, behindCam.x, behindCam.y, behindCam.z, -1, PlayerPedId(), 0)
    local a, hitBool, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)

    local maxRadius = 3.0
    if (hitBool and Vdist(pCoords.x, pCoords.y, pCoords.z + 0.5, hitCoords) < 3.0 + 0.5) then
        maxRadius = Vdist(pCoords.x, pCoords.y, pCoords.z + 0.5, hitCoords)
    end

    local offset = {
        x = ((Cos(angleZ) * Cos(angleY)) + (Cos(angleY) * Cos(angleZ))) / 2 * maxRadius,
        y = ((Sin(angleZ) * Cos(angleY)) + (Cos(angleY) * Sin(angleZ))) / 2 * maxRadius,
        z = ((Sin(angleY))) * maxRadius
    }

    local pos = {
        x = pCoords.x + offset.x,
        y = pCoords.y + offset.y,
        z = pCoords.z + offset.z
    }

    return pos
end

local isReloadingCharacter = false

local SavedHealth = nil
local SavedStamina = nil
local SavedStaminaCore = nil

local function GetPedStaminaValue(ped)
    return Citizen.InvokeNative(
        0x775A1CA7893AA8B5,
        ped,
        Citizen.ResultAsFloat()
    )
end

local function SaveHealthAndStamina()
    local ped = PlayerPedId()

    if not DoesEntityExist(ped) then
        return
    end

    SavedHealth = GetEntityHealth(ped)
    SavedStamina = GetPedStaminaValue(ped)
    SavedStaminaCore = Citizen.InvokeNative(0x36731AC041289BB1, ped, 1)
end

local function RestoreHealthAndStamina()
    local healthToRestore = SavedHealth
    local staminaToRestore = SavedStamina
    local staminaCoreToRestore = SavedStaminaCore

    if healthToRestore == nil and staminaToRestore == nil and staminaCoreToRestore == nil then
        return
    end

    -- Character/model loading may overwrite stamina for several frames,
    -- so restore the values a few times after the reload completes.
    for attempt = 1, 3 do
        local ped = PlayerPedId()

        if DoesEntityExist(ped) then
            if healthToRestore ~= nil then
                SetEntityHealth(ped, healthToRestore)
            end

            -- Restore the inner stamina core (0-100).
            if staminaCoreToRestore ~= nil then
                local staminaCore = math.max(0, math.min(100, math.floor(tonumber(staminaCoreToRestore) or 0)))
                Citizen.InvokeNative(0xC6258F41D86676E0, ped, 1, staminaCore)
            end

            -- Restore the current outer stamina by applying the exact difference.
            if staminaToRestore ~= nil then
                local currentStamina = GetPedStaminaValue(ped)
                local targetStamina = tonumber(staminaToRestore) or 0.0

                if currentStamina then
                    Citizen.InvokeNative(
                        0xC3D4B754C0E86B9E,
                        ped,
                        targetStamina - currentStamina
                    )
                end
            end
        end

        if attempt < 3 then
            Citizen.Wait(150)
        end
    end
    SavedHealth = nil
    SavedStamina = nil
    SavedStaminaCore = nil
end

local reloadAppearanceFinished = false
local reloadAppearanceSucceeded = false

RegisterNetEvent('jrs_character_creator:appearanceReloadFinished')
AddEventHandler('jrs_character_creator:appearanceReloadFinished', function(success)
    if not isReloadingCharacter then
        return
    end

    reloadAppearanceSucceeded = success == true
    reloadAppearanceFinished = true
end)

local function ReloadCurrentCharacter()
    if isReloadingCharacter then
        return
    end

    local oldPed = PlayerPedId()
    if not DoesEntityExist(oldPed) then
        return
    end

    -- Raw InvokeNative BOOLs can come back as 0/1; a bare 0 is truthy in Lua and
    -- made every reload (/rc, bath dress-up) bail out here without doing anything.
    local hogtiedRaw = Citizen.InvokeNative(0x3AA24CCC0D451379, oldPed)
    local cuffedRaw = Citizen.InvokeNative(0x74E559B3BC910685, oldPed)
    local hogtied = hogtiedRaw == true or hogtiedRaw == 1
    local cuffed = cuffedRaw == true or cuffedRaw == 1
    local dead = IsEntityDead(oldPed)

    if hogtied or cuffed or dead then
        return
    end

    isReloadingCharacter = true
    reloadAppearanceFinished = false
    reloadAppearanceSucceeded = false
    TriggerEvent('jrs_character:client:appearanceReloadState', true)

    local coords = GetEntityCoords(oldPed)
    local heading = GetEntityHeading(oldPed)
    SaveHealthAndStamina()

    -- Always reload through the new JRS creator pipeline. The legacy
    -- Data_Character_Load path does not restore the creator's bodies_upper
    -- component and can leave the hands/forearms invisible after /rc.
    TriggerEvent('jrs_character_creator:loadskinjrs')

    local timeoutAt = GetGameTimer() + 12000
    while not reloadAppearanceFinished and GetGameTimer() < timeoutAt do
        Citizen.Wait(50)
    end

    local newPed = PlayerPedId()
    if DoesEntityExist(newPed) then
        SetEntityCoordsNoOffset(newPed, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(newPed, heading)
        DetachEntity(newPed, true, true)
        ClearPedTasksImmediately(newPed)

        -- The creator reload already requests the saved outfit. Request it
        -- once more after the base body is ready so clothing layering cannot
        -- remove the upper-body/hand component.
        if reloadAppearanceSucceeded then
            Citizen.Wait(150)
            TriggerEvent('jrs_clothes:reloadCurrentClothes')
        end
    end

    Citizen.Wait(250)
    RestoreHealthAndStamina()

    reloadAppearanceFinished = false
    reloadAppearanceSucceeded = false
    isReloadingCharacter = false
    TriggerEvent('jrs_character:client:appearanceReloadState', false)
end

-- Safe appearance-only reload API used by jrs_pedmenu and jrs_admin.
-- It never clears the active core character and never opens the selector.
RegisterNetEvent('jrs_character:client:reloadCurrentCharacter', function()
    CreateThread(ReloadCurrentCharacter)
end)

exports('ReloadCurrentCharacter', function()
    if isReloadingCharacter then return true end
    CreateThread(ReloadCurrentCharacter)
    return true
end)

exports('IsReloadingCurrentCharacter', function()
    return isReloadingCharacter == true
end)

-- /rc remains an appearance repair command; it does not re-select characters.
RegisterCommand('rc', ReloadCurrentCharacter)


-- ===== Resource Cleanup =====

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if cam then EndDeathCam() end
end)

-- ===== jrs:SelectedCharacter Handler #1 (Death/Respawn) =====

-- jrs_core fires jrs:SelectedCharacter again on every character switch
-- (admin selector, second chance, etc). Without this guard each additional
-- fire spawned another permanent while-true thread, stacking duplicate
-- death timers/StartDeathCam calls (see the deathMonitorStarted guard
-- already used further down for the same event).
local deathRespawnMonitorStarted = false

RegisterNetEvent("jrs:SelectedCharacter")
AddEventHandler("jrs:SelectedCharacter", function(charid)
    if deathRespawnMonitorStarted then return end
    deathRespawnMonitorStarted = true
    Citizen.CreateThread(function()
        local lastScaledPed = 0
        while true do
            Citizen.Wait(1000)
            if IsEntityDead(PlayerPedId()) then
                if not set_dead then
                    set_dead = true
                    TimeToRespawn = Config.TimeToRespawn
                    Citizen.InvokeNative(0xD63FE3AF9FB3D53F, true)
                    Citizen.InvokeNative(0x1B3DA717B9AFF828, true)
                    ExecuteCommand("hud")
                    StartDeathCam()
                end
                if set_dead then
                    exports["spawnmanager"].setAutoSpawn(false)
                    TimeToRespawn = TimeToRespawn-1
                end
            else
               -- Re-asserting scale/variation EVERY second reset the ped's
               -- locomotion stride (robotic, stuttering walk) and spammed the
               -- server. Apply once per ped instance; carried/attached/revive
               -- paths already re-apply scale through JRSQueuePlayerScaleRefresh.
               local scaledPed = PlayerPedId()
               if scaledPed ~= lastScaledPed then
                  lastScaledPed = scaledPed
                  if Config.startScale then
                     TriggerServerEvent("jrs_character:AdminCheck")
                  else
                     Citizen.InvokeNative(0x25ACFC650B65C538, scaledPed, Skin_Table["Scale"])
                     Citizen.InvokeNative(0xCC8CA3E88256E58F, scaledPed, 0, 1, 1, 1, false)
                  end
               end
            end
        end
    end)
end)

-- ===== jrs:SelectedCharacter Handler #4 (Mount States + Disable Controls) =====

-- Same stacking-thread risk as Handler #1 above: guard so a repeated
-- jrs:SelectedCharacter fire cannot pile up another permanent 5ms loop.
local mountControlsMonitorStarted = false

RegisterNetEvent("jrs:SelectedCharacter")
AddEventHandler("jrs:SelectedCharacter", function(charid)
    if mountControlsMonitorStarted then return end
    mountControlsMonitorStarted = true
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(5)
            DisableControlAction(0, 0x580C4473, true)
            DisableControlAction(0, 0xCF8A4ECA, true)
            Citizen.InvokeNative(0x8BC7C1F929D07BF3, 474191950)
            Citizen.InvokeNative(0xFEDFA97638D61D4A, 0.2)
            Citizen.InvokeNative(0x1F91D44490E1EA0C, 0.0)
            Citizen.InvokeNative(0x606374EBFC27B133, 0.0)
            Mount_States()
        end
    end)
end)
end

-- ============================================================================
-- Module: legacy/overlays.lua
-- ============================================================================
do
-- ===== Overlay Processing Thread =====

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(50)
        if is_overlay_change_active then  
            local ped = PlayerPedId()
            if Skin_Table["sex"] == Config.ModelNames.male then
                current_texture_settings = Config.texture_types["male"]
            else
                current_texture_settings = Config.texture_types["female"]
            end          
            if textureId ~= -1 then
                Citizen.InvokeNative(0xB63B9178D0F58D82,textureId)  -- reset texture
                Citizen.InvokeNative(0x6BEFAA907B076859,textureId)  -- remove texture
            end
            if Skin_Table["sex"] == Config.ModelNames.male then
                if HeadCategory == 1 then
                    CharTypeWhat = GetHashKey("mp_head_mr1_sc08_c0_000_ab")
                elseif HeadCategory == 2 then
                    CharTypeWhat = GetHashKey("mp_head_mr1_sc02_c0_000_ab")
                elseif HeadCategory == 3 then
                    CharTypeWhat = GetHashKey("mp_head_mr1_sc03_c0_000_ab")
                elseif HeadCategory == 4 then
                    CharTypeWhat = GetHashKey("mp_head_mr1_sc01_c0_000_ab")
                elseif HeadCategory == 5 then
                    CharTypeWhat = GetHashKey("mp_head_mr1_sc04_c0_000_ab")
                elseif HeadCategory == 6 then
                    CharTypeWhat = GetHashKey("mp_head_mr1_sc05_c0_000_ab")
                end
            else
                if HeadCategory == 1 then
                    CharTypeWhat = GetHashKey("mp_head_fr1_sc08_c0_000_ab")
                elseif HeadCategory == 2 then
                    CharTypeWhat = GetHashKey("mp_head_fr1_sc02_c0_000_ab")
                elseif HeadCategory == 3 then
                    CharTypeWhat = GetHashKey("mp_head_fr1_sc03_c0_000_ab")
                elseif HeadCategory == 4 then
                    CharTypeWhat = GetHashKey("mp_head_fr1_sc05_c0_000_ab")
                elseif HeadCategory == 5 then
                    CharTypeWhat = GetHashKey("mp_head_fr1_sc01_c0_000_ab")
                elseif HeadCategory == 6 then
                    CharTypeWhat = GetHashKey("mp_head_fr1_sc04_c0_000_ab")
                end
            end
            textureId = Citizen.InvokeNative(0xC5E7204F322E49EB, CharTypeWhat, current_texture_settings.normal, current_texture_settings.material)
            for k,v in pairs(Config.overlay_all_layers) do
                if v.visibility ~= 0 then
                    local overlay_id = Citizen.InvokeNative(0x86BB5FF45F193A02,textureId, v.tx_id , v.tx_normal, v.tx_material, v.tx_color_type, v.tx_opacity,v.tx_unk)
                    if v.tx_color_type == 0 then
                        Citizen.InvokeNative(0x1ED8588524AC9BE1,textureId,overlay_id,v.palette);    -- apply palette
                        Citizen.InvokeNative(0x2DF59FFE6FFD6044,textureId,overlay_id,v.palette_color_primary,v.palette_color_secondary,v.palette_color_tertiary)  -- apply palette colours
                    end
                    Citizen.InvokeNative(0x3329AAE2882FC8E4,textureId,overlay_id, v.var);  -- apply overlay variant
                    Citizen.InvokeNative(0x6C76BC24F8BB709A,textureId,overlay_id, v.opacity); -- apply overlay opacity
                end
            end
            local textureDeadline = GetGameTimer() + 3000
            while not Citizen.InvokeNative(0x31DC8D3F216D8509,textureId) and GetGameTimer() < textureDeadline do  -- wait till texture fully loaded
                Citizen.Wait(0)
            end
            Citizen.InvokeNative(0x0B46E25761519058,ped,`heads`,textureId)  -- apply texture to current component in category "heads"
            Citizen.InvokeNative(0x92DAABA2C1C10B0E,textureId)      -- update texture
            Citizen.InvokeNative(0xCC8CA3E88256E58F,ped, 0, 1, 1, 1, false);  -- refresh ped components
            is_overlay_change_active = false
        end
    end
end)

-- ===== Set Colors Event =====

RegisterNetEvent('jrs_characters:setcolors')
AddEventHandler('jrs_characters:setcolors', function(name,visibility,tx_id,tx_normal,tx_material,tx_color_type,tx_opacity,tx_unk,palette_id,palette_color_primary,palette_color_secondary,palette_color_tertiary,var,opacity)
    for k,v in pairs(Config.overlay_all_layers) do
        if v.name==name then
            v.visibility = visibility
            if visibility ~= 0 then
                v.tx_normal = tx_normal
                v.tx_material = tx_material
                v.tx_color_type = tx_color_type
                v.tx_opacity =  tx_opacity
                v.tx_unk =  tx_unk
                if tx_color_type == 0 then
                    v.palette = Config.color_palettes[palette_id][1]
                    v.palette_color_primary = palette_color_primary
                    v.palette_color_secondary = palette_color_secondary
                    v.palette_color_tertiary = palette_color_tertiary
                end
                if name == "shadows" or name == "eyeliners" or name == "lipsticks" then
                    v.var = var
                    v.tx_id = Config.overlays_info[name][1].id
                else
                    v.var = 0 
                    v.tx_id = Config.overlays_info[name][tx_id].id
                end
                v.opacity = opacity
            end
        end
    end
    is_overlay_change_active = true
end)
end

-- ============================================================================
-- Module: legacy/events.lua
-- ============================================================================
do
-- JRS character runtime events.
-- The legacy selector/creator NUI callbacks were removed; only gameplay compatibility remains.

RegisterNetEvent('jrs_character:hairPomade')
AddEventHandler('jrs_character:hairPomade', function()
    if Citizen.InvokeNative(0xFB4891BD7578CDC1, PlayerPedId(), tonumber(0x9925C067)) then
        TaskItemInteraction(PlayerPedId(), 0, GetHashKey("APPLY_POMADE_WITH_HAT"), 1, 0, -1082130432)
    else
        TaskItemInteraction(PlayerPedId(), 0, GetHashKey("APPLY_POMADE_WITH_NO_HAT"), 1, 0, -1082130432)
    end
    Wait(1500)
    Citizen.InvokeNative(0x66B957AAC2EAAEAB, PlayerPedId(), Skin_Table["Hair"], GetHashKey("POMADE"), 0, true, 1)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, PlayerPedId(), 0, 1, 1, 1, 0)
end)

RegisterNetEvent('jrs_character:selected_char')
AddEventHandler('jrs_character:selected_char', function()
    is_loaded_character = true
end)

RegisterNetEvent('jrs_character:saveBarberAction')
AddEventHandler('jrs_character:saveBarberAction', function(skin_table_receive)
    Skin_Table = skin_table_receive
    have_character = true
end)

RegisterNetEvent('jrs_character:send_data_back')
AddEventHandler('jrs_character:send_data_back', function(skin_table_receive, outfit_table_receive, coord_table_receive, isdeaded, update, new_char)
    -- Compatibility route for resources that still use the old JRS event.
    -- The integrated creator owns the complete spawn/fade/NUI lifecycle.
    TriggerEvent('jrs_character_creator:FinalizeCharacter', {
        skin = type(skin_table_receive) == 'table' and skin_table_receive or {},
        components = type(outfit_table_receive) == 'table' and outfit_table_receive or {},
        coords = type(coord_table_receive) == 'table' and coord_table_receive or {},
        isDead = tonumber(isdeaded) or 0,
        peddata = {},
        newCharacter = new_char == true,
    })
end)

RegisterNetEvent('jrs_character:send_character')
AddEventHandler('jrs_character:send_character', function()
    TriggerServerEvent('jrs_character_creator:getCharacters')
end)

-- Keep the selected character height stable across death, carry/attach and revive.
-- RedM can reset ped scale after NetworkResurrectLocalPlayer or ped attachment, so
-- we cache the last authoritative scale received from jrs_admin for this character.
JRSLastSavedPlayerScale = nil
JRSScaleRefreshToken = 0

-- These bounds must stay identical to jrs_admin/server/player_scale.lua's
-- MIN_SCALE / MAX_SCALE, which is where admin-set and store-bought heights are
-- validated and stored. They were 0.7 here, so a height of 0.60 granted by an
-- admin or bought in the store was silently raised to 0.70 on arrival and the
-- character stood taller than the height that was actually paid for.
JRSPlayerScaleMin = 0.60
JRSPlayerScaleMax = 1.30

function JRSNormalizePlayerScale(value)
    local scale = tonumber(value)
    if not scale or scale <= 0.0 then return nil end
    if scale < JRSPlayerScaleMin then scale = JRSPlayerScaleMin end
    if scale > JRSPlayerScaleMax then scale = JRSPlayerScaleMax end
    return scale
end

function JRSApplyCachedPlayerScale()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    local scale = JRSNormalizePlayerScale(JRSLastSavedPlayerScale)
    if not scale and type(Skin_Table) == 'table' then
        scale = JRSNormalizePlayerScale(Skin_Table["Scale"])
    end
    if not scale then return false end

    Citizen.InvokeNative(0x25ACFC650B65C538, ped, scale)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
    return true
end

function JRSQueuePlayerScaleRefresh(requestAuthoritativeScale)
    JRSScaleRefreshToken = JRSScaleRefreshToken + 1
    local token = JRSScaleRefreshToken

    if requestAuthoritativeScale == true then
        TriggerServerEvent("jrs_character:RequestSavedScale")
    end

    CreateThread(function()
        -- Reapply after the common resurrection/model stabilization windows.
        local schedule = { 0, 125, 300, 650, 1200, 2200, 3500 }
        local startedAt = GetGameTimer()

        for _, atMs in ipairs(schedule) do
            while token == JRSScaleRefreshToken and (GetGameTimer() - startedAt) < atMs do
                Wait(25)
            end
            if token ~= JRSScaleRefreshToken then return end
            JRSApplyCachedPlayerScale()
        end
    end)
end

RegisterNetEvent("jrs_character:reapplySavedScale")
AddEventHandler("jrs_character:reapplySavedScale", function(requestAuthoritativeScale)
    JRSQueuePlayerScaleRefresh(requestAuthoritativeScale == true)
end)

-- Carry & Attachment Scale Guard:
-- When a player is carried, hogtied, or attached, RedM frequently resets ped scale.
-- When the player is dropped, thrown, or detached, the ragdoll / detach animation also resets scale.
-- We actively monitor both states so the character's height stays locked while carried,
-- and is immediately re-asserted in staggered ticks the moment they are thrown or dropped.
local wasAttachedOrCarried = false
CreateThread(function()
    while true do
        Wait(400)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) and have_character and is_loaded_character then
            local isAttached = false
            if type(IsEntityAttached) == 'function' then
                local ok, att = pcall(IsEntityAttached, ped)
                if ok and att == true then isAttached = true end
            end

            local carrierPed = 0
            pcall(function()
                carrierPed = Citizen.InvokeNative(0x09B83E68DE004CD4, ped) or 0
            end)

            local isCarried = (carrierPed ~= 0 and carrierPed ~= nil)
            local currentlyCarriedOrAttached = isAttached or isCarried

            if currentlyCarriedOrAttached then
                wasAttachedOrCarried = true
                JRSApplyCachedPlayerScale()
            elseif wasAttachedOrCarried then
                -- The player was JUST dropped, thrown, or released!
                wasAttachedOrCarried = false
                JRSApplyCachedPlayerScale()
                JRSQueuePlayerScaleRefresh(true)
            end
        end
    end
end)

RegisterNetEvent("jrs_character:open_manage")
AddEventHandler("jrs_character:open_manage", function(height)
    local norm = JRSNormalizePlayerScale(height)
    if norm then
        JRSLastSavedPlayerScale = norm
        if type(Skin_Table) == 'table' then
            Skin_Table["Scale"] = norm
        end
        JRSApplyCachedPlayerScale()
    end
end)

RegisterNetEvent("jrs_admin:playerScale:apply")
AddEventHandler("jrs_admin:playerScale:apply", function(height)
    local norm = JRSNormalizePlayerScale(height)
    if norm then
        JRSLastSavedPlayerScale = norm
        if type(Skin_Table) == 'table' then
            Skin_Table["Scale"] = norm
        end
        JRSApplyCachedPlayerScale()
    end
end)

RegisterNetEvent("jrs_character:open_managestop")
AddEventHandler("jrs_character:open_managestop", function()
    JRSLastSavedPlayerScale = 1.0
    if type(Skin_Table) == 'table' then
        Skin_Table["Scale"] = 1.0
    end
    JRSApplyCachedPlayerScale()
end)

-- Background Watchdog loop: checks every 1200ms and restores scale if displaced by any script/ragdoll
CreateThread(function()
    while true do
        Wait(1200)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) and have_character and is_loaded_character then
            if JRSLastSavedPlayerScale and math.abs(JRSLastSavedPlayerScale - 1.0) > 0.001 then
                JRSApplyCachedPlayerScale()
            end
        end
    end
end)

-- Instant Client Command to immediately restore character height at 0ms latency
RegisterCommand('fixscale', function()
    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) then
        JRSApplyCachedPlayerScale()
        TriggerEvent('jrs_character:reapplySavedScale', true)
        TriggerServerEvent('jrs_admin:playerScale:request')
    end
end, false)

RegisterCommand('fixheight', function()
    ExecuteCommand('fixscale')
end, false)

RegisterCommand('scale', function()
    ExecuteCommand('fixscale')
end, false)

exports('GetCachedPlayerScale', function()
    return JRSLastSavedPlayerScale or 1.0
end)

exports('ApplyCachedPlayerScale', function()
    return JRSApplyCachedPlayerScale()
end)

-- Cached appearance payload across death/respawn/sleep transitions
JRSLastLoadedBarber = nil
JRSLastLoadedComponents = nil
JRSLastLoadedAge = nil
JRSLastLoadedPedData = nil

function ApplyCharacterExpressions(ped, expressions)
    ped = ped or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    expressions = expressions
        or (JRSLastLoadedPedData and JRSLastLoadedPedData.expressions)
        or (CachePedData and CachePedData.expressions)

    if type(expressions) ~= "table" or not ExpressionsHashes then return false end

    for k, v in pairs(expressions) do
        local hash = ExpressionsHashes[k]
        if hash then
            local val = tonumber(v)
            if val ~= nil then
                Citizen.InvokeNative(0x5653AB26C82938CF, ped, hash, val + 0.0)
            end
        end
    end
    return true
end

RegisterNetEvent('jrs_character:reapplyExpressions', function(targetPed)
    ApplyCharacterExpressions(targetPed or PlayerPedId())
end)

RegisterNetEvent('jrs_clothes:outfitchanged', function()
    Wait(500)
    ApplyCharacterExpressions(PlayerPedId())
end)

exports('ApplyCharacterExpressions', ApplyCharacterExpressions)

function JRSRestoreCharacterAppearanceOnRespawn(ped)
    ped = ped or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    local pedData = JRSLastLoadedPedData or CachePedData
    local components = JRSLastLoadedComponents or Clothe_Table
    local barber = JRSLastLoadedBarber

    -- 1. Ensure ped model and essential body components are set
    if type(pedData) == 'table' and pedData.pedmodel and pedData.pedmodel.model then
        local gender = pedData.gender == "Female" and "Female" or "Male"
        local skinTone = tonumber(pedData.skintone) or 1
        local skinSet = DefaultChar and DefaultChar[gender] and DefaultChar[gender][skinTone]
        if skinSet then
            local headIndex = tonumber(pedData.head) or 1
            local headHex = (skinSet.Heads and skinSet.Heads[headIndex] and skinSet.Heads[headIndex] ~= "") and skinSet.Heads[headIndex] or (skinSet.Heads and skinSet.Heads[1])
            local heads = headHex and tonumber("0x" .. headHex) or nil
            local upperIndex = tonumber(pedData.upperbody)
            local bodyHex = (upperIndex and upperIndex > 0 and skinSet.Body and skinSet.Body[upperIndex] and skinSet.Body[upperIndex] ~= "") and skinSet.Body[upperIndex] or (upperIndex ~= 0 and skinSet.Body and skinSet.Body[1])
            local bodyType = bodyHex and tonumber("0x" .. bodyHex) or nil
            local lowerIndex = tonumber(pedData.lowerbody)
            local legsHex = (lowerIndex and lowerIndex > 0 and skinSet.Legs and skinSet.Legs[lowerIndex] and skinSet.Legs[lowerIndex] ~= "") and skinSet.Legs[lowerIndex] or (lowerIndex ~= 0 and skinSet.Legs and skinSet.Legs[1])
            local legs = legsHex and tonumber("0x" .. legsHex) or nil
            local headtexture = skinSet.HeadTexture and skinSet.HeadTexture[1] and joaat(skinSet.HeadTexture[1]) or nil
            local albedo = texture_types and texture_types[gender] and texture_types[gender].albedo

            if type(ApplyShopItemToPed) == 'function' then
                if heads then ApplyShopItemToPed(heads, ped) end
                if upperIndex == 0 then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0B3966C9, 0)
                elseif bodyType then
                    ApplyShopItemToPed(bodyType, ped)
                end
                if lowerIndex == 0 then
                    Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x823687F5, 0)
                elseif legs then
                    ApplyShopItemToPed(legs, ped)
                end
            end
            if albedo and headtexture then
                Citizen.InvokeNative(0xC5E7204F322E49EB, albedo, headtexture, 0x7FC5B1E1)
            end
            if (pedData.body or 0) > 0 and Body and Body[pedData.body] and type(EquipMetaPedOutfit) == 'function' then
                EquipMetaPedOutfit(tonumber(Body[pedData.body]), ped)
            end
            if (pedData.waist or 0) > 0 and Waist and Waist[pedData.waist] and type(EquipMetaPedOutfit) == 'function' then
                EquipMetaPedOutfit(tonumber(Waist[pedData.waist]), ped)
            end
            if (pedData.teeth or 0) > 0 and Teeth and Teeth[gender] and Teeth[gender][pedData.teeth] and type(ApplyShopItemToPed) == 'function' then
                ApplyShopItemToPed(Teeth[gender][pedData.teeth].hash, ped)
            end
            if (pedData.eyes or 0) > 0 and Eyes and Eyes[gender] and Eyes[gender][pedData.eyes] and type(ApplyShopItemToPed) == 'function' then
                ApplyShopItemToPed(Eyes[gender][pedData.eyes], ped)
            end
            if type(pedData.expressions) == 'table' and type(SetCharExpression) == 'function' and ExpressionsHashes then
                for k, v in pairs(pedData.expressions) do
                    if ExpressionsHashes[k] then
                        SetCharExpression(ped, ExpressionsHashes[k], v)
                    end
                end
            end
        end
    elseif type(EnsureValidBodyComponents) == 'function' then
        EnsureValidBodyComponents()
    end

    -- 2. Apply clothing
    local clothingApplied = false
    if type(components) == 'table' and next(components) ~= nil and type(ApplySavedClothingToPreviewPed) == 'function' then
        clothingApplied = ApplySavedClothingToPreviewPed(ped, components) == true
    end
    if not clothingApplied then
        TriggerEvent('jrs_clothing:loadclothes')
    end

    -- 3. Apply barber (hair, beard, overlays, age)
    if type(barber) == 'table' and next(barber) ~= nil and type(ApplySavedBarberToPreviewPed) == 'function' then
        ApplySavedBarberToPreviewPed(ped, barber, pedData, JRSLastLoadedAge)
    else
        TriggerEvent('jrs_character_creator:loadbarberoverlay')
    end

    if GetResourceState("jrs_clothing") == "started" then
        pcall(function()
            exports.jrs_clothing:SmartBodyFitPed(ped, components or JRSLastLoadedComponents)
        end)
    end

    if type(NativeUpdatePedVariation) == 'function' then
        NativeUpdatePedVariation(ped)
    else
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
    end
    if type(IsPedReadyToRender) == 'function' then
        IsPedReadyToRender(ped)
    end
    -- Reapply expressions after component variation updates have completed
    ApplyCharacterExpressions(ped, pedData and pedData.expressions)
    JRSQueuePlayerScaleRefresh(true)
    return true
end

exports('RestoreCharacterAppearance', function(ped)
    return JRSRestoreCharacterAppearanceOnRespawn(ped or PlayerPedId())
end)

local deathMonitorStarted = false

RegisterNetEvent("jrs:SelectedCharacter")
AddEventHandler("jrs:SelectedCharacter", function(charid)
    if deathMonitorStarted then return end
    deathMonitorStarted = true

    Citizen.CreateThread(function()
        local nextCarryScaleRefreshAt = 0
        while true do 
            local optimization = 1000
            -- jrs_fightarena owns deaths inside the arena (it resurrects the
            -- player itself). Marking them dead here re-killed them every second
            -- after an arena respawn and saved a dead state to the DB.
            local inArena = LocalPlayer and LocalPlayer.state and LocalPlayer.state.jrsArena == true
            if inArena and isDead then
                isDead = false
                set_dead = false
                PublishJRSDeathState(false)
                TriggerServerEvent("jrs_character:dead_state", false)
            end
            if isDead then
                SetEntityHealth(PlayerPedId(), 0.0)
                isDead = true
            end
            if inArena then
                -- nothing: the arena handles this death
            elseif IsEntityDead(PlayerPedId()) then
                carrier = Citizen.InvokeNative(0x09B83E68DE004CD4, PlayerPedId());

                -- Attaching/carrying a dead ped can reset its scale to 1.0. Keep the
                -- cached character height authoritative while another player carries it.
                if carrier and carrier ~= 0 then
                    local now = GetGameTimer()
                    if now >= nextCarryScaleRefreshAt then
                        JRSApplyCachedPlayerScale()
                        nextCarryScaleRefreshAt = now + 750
                    end
                else
                    if nextCarryScaleRefreshAt ~= 0 then
                        JRSQueuePlayerScaleRefresh(true)
                    end
                    nextCarryScaleRefreshAt = 0
                end

                optimization = 5 
                if (cam and IsEntityDead(PlayerPedId())) then
                    ProcessCamControls()
                end
                if isDead == false then
                    TriggerServerEvent("jrs_character:dead_state", true)
                    isDead = true
                    PublishJRSDeathState(true)
                    TriggerEvent('jrs_isDead:start')
                end
                local GetCoords = GetEntityCoords(PlayerPedId())
                if carrier then
                else
                    if TimeToRespawn <= 0 then
                             Citizen.Wait(2000)
                    end
                end
            else
                optimization = 2000 
                spawned = false
            end
            Citizen.Wait(optimization)
        end
    end)
end)

local function JRSPerformDeathRespawn(targetCoords)
    targetCoords = type(targetCoords) == 'table' and targetCoords or {}
    local ped = PlayerPedId()
    local x = tonumber(targetCoords.x or targetCoords[1]) or 0.0
    local y = tonumber(targetCoords.y or targetCoords[2]) or 0.0
    local z = tonumber(targetCoords.z or targetCoords[3]) or 0.0
    local heading = tonumber(targetCoords.heading or targetCoords.h or targetCoords.w or targetCoords[4]) or 0.0

    if type(SetJRSCharacterGate) == 'function' then SetJRSCharacterGate(true, 'death_respawn') end
    DisplayHud(false)
    DisplayRadar(false)
    if not IsScreenFadedOut() and not IsScreenFadingOut() then
        DoScreenFadeOut(250)
        local fadeTimeout = GetGameTimer() + 2500
        while not IsScreenFadedOut() and GetGameTimer() < fadeTimeout do Wait(0) end
    end

    isDead = false
    PublishJRSDeathState(false)
    set_dead = false
    spawned = true
    TimeToRespawn = Config.TimeToRespawn

    EndDeathCam()
    NetworkSetInSpectatorMode(false, ped)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    if type(SetEntityAlpha) == 'function' then SetEntityAlpha(ped, 0, false) end
    SetPlayerInvincible(PlayerId(), true)

    Citizen.InvokeNative(0x71BC8E838B9C6035, ped)
    Citizen.InvokeNative(0x0E3F4AF2D63491FB)
    SetEntityHealth(ped, 600, 0)
    TriggerServerEvent("jrs_character:dead_state", false)
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, heading)

    local collisionTimeout = GetGameTimer() + 8000
    while GetGameTimer() < collisionTimeout and not HasCollisionLoadedAroundEntity(ped) do
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
    end

    ped = PlayerPedId()
    local foundRespawnGround, respawnGroundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if foundRespawnGround and math.abs(respawnGroundZ - z) < 3.0 then
        SetEntityCoords(ped, x, y, respawnGroundZ, false, false, false, false)
    else
        SetEntityCoords(ped, x, y, z, false, false, false, false)
        pcall(PlaceEntityOnGroundProperly, ped, true)
    end

    -- Fully restore character skin, face, hair, and clothing on respawn
    ped = PlayerPedId()
    if type(JRSRestoreCharacterAppearanceOnRespawn) == 'function' then
        JRSRestoreCharacterAppearanceOnRespawn(ped)
    else
        TriggerEvent('jrs_clothing:loadclothes')
        TriggerEvent('jrs_character_creator:loadbarberoverlay')
    end

    -- Ensure clothing and smart body fit are finished before reveal
    if GetResourceState('jrs_clothing') == 'started' then
        if exports.jrs_clothing.IsClothingBusy then
            local busyDeadline = GetGameTimer() + 3500
            while exports.jrs_clothing:IsClothingBusy() and GetGameTimer() < busyDeadline do
                Wait(50)
            end
        end
        pcall(function()
            exports.jrs_clothing:SmartBodyFitPed(ped, JRSLastLoadedComponents or Clothe_Table)
        end)
        NativeUpdatePedVariation(ped)
    end

    -- Ensure components and clothing are confirmed loaded before reveal
    local componentTimeout = GetGameTimer() + 8000
    while not NativeHasPedComponentLoaded(ped) and GetGameTimer() < componentTimeout do
        Wait(50)
    end
    Wait(400) -- Extra buffer for low-end PC texture decoding

    Citizen.InvokeNative(0xF808475FA571D823, true)
    Citizen.InvokeNative(0xBF25EB89375A37AD, 5, GetHashKey("PLAYER"), GetHashKey("PLAYER"))
    JRSSafeNetworkConceal(false)
    if type(SetEntityAlpha) == 'function' then ResetEntityAlpha(ped) end
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    JRSQueuePlayerScaleRefresh(true)

    local spawnAnimCfg = type(Config.SpawnAnimation) == 'table' and Config.SpawnAnimation or {}
    local playAnim = spawnAnimCfg.Enabled ~= false and spawnAnimCfg.ApplyAfterDeathRespawn ~= false
    local wakeUpTime = playAnim and (tonumber(spawnAnimCfg.WakeUpTimeMs) or 7000) or 1500
    local fadeInDelay = playAnim and math.max(500, tonumber(spawnAnimCfg.FadeInDelayMs) or 1500) or 250

    FreezeEntityPosition(ped, false)
    if playAnim then
        JRSPlaySpawnAnimation('deathRespawn')
    end

    -- Keep controls locked and player invincible during the sleep/wake-up animation
    SetPlayerInvincible(PlayerId(), true)
    JRSApplyPlayerControl(false)

    Wait(fadeInDelay)
    if IsScreenFadedOut() or IsScreenFadingOut() then
        DoScreenFadeIn(800)
    end

    local remainingWakeUp = math.max(0, wakeUpTime - fadeInDelay)
    local elapsed = 0
    while elapsed < remainingWakeUp do
        Wait(500)
        elapsed = elapsed + 500
        ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            if not NativeHasPedComponentLoaded(ped) then
                NativeUpdatePedVariation(ped)
            end
        end
    end

    ped = PlayerPedId()
    SetPlayerInvincible(PlayerId(), false)
    JRSApplyPlayerControl(true)
    DisplayHud(true)
    DisplayRadar(true)
    if type(SetJRSCharacterGate) == 'function' then SetJRSCharacterGate(false, 'death_respawn_ready') end
end

RegisterNetEvent('jrs_character:revive_player')
AddEventHandler('jrs_character:revive_player', function(id, where)
    local target = nil
    if tonumber(where) == 0 then
        for _, v in pairs(Config.RespawnCoords) do
            local current = GetEntityCoords(PlayerPedId())
            if GetDistanceBetweenCoords(current.x, current.y, current.z, v.x, v.y, v.z, false) < 1000.0 and set_dead == true then
                target = v
                break
            end
        end
        if not target then
            for _, v in pairs(Config.RespawnCoords) do
                local current = GetEntityCoords(PlayerPedId())
                if GetDistanceBetweenCoords(current.x, current.y, current.z, v.x, v.y, v.z, false) < 3000.0 and set_dead == true then
                    target = v
                    break
                end
            end
        end
        target = target or Config.RespawnCoords[1]
    else
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        target = { x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped) }
    end

    if target then
        JRSPerformDeathRespawn(target)
    end
end)

RegisterNetEvent('jrs_characters:colors')
AddEventHandler('jrs_characters:colors', function(name,visibility,tx_id,tx_normal,tx_material,tx_color_type,tx_opacity,tx_unk,palette_id,palette_color_primary,palette_color_secondary,palette_color_tertiary,var,opacity)
    for k,v in pairs(Config.overlay_all_layers) do
        if v.name==name then
            v.visibility = visibility
            if visibility ~= 0 then
                v.tx_normal = tx_normal
                v.tx_material = tx_material
                v.tx_color_type = tx_color_type
                v.tx_opacity =  tx_opacity
                v.tx_unk =  tx_unk
                if tx_color_type == 0 then
                    v.palette = Config.color_palettes[palette_id][1]
                    v.palette_color_primary = palette_color_primary
                    v.palette_color_secondary = palette_color_secondary
                    v.palette_color_tertiary = palette_color_tertiary
                end
                if name == "shadows" or name == "eyeliners" or name == "lipsticks" then
                    v.var = var
                    v.tx_id = Config.overlays_info[name][1].id
                else
                    v.var = 0 
                    v.tx_id = Config.overlays_info[name][tx_id].id
                end
                v.opacity = opacity
            end
        end
    end
    is_overlay_change_active = true
end)

-- ===== NUI Callbacks =====
end

-- ============================================================================
-- Module: selector_bridge.lua
-- ============================================================================
do
-- JRS selector bridge.
-- This file contains only lifecycle and in-game switching logic for the new creator.

local selectorOpen = false
local selectorOpening = false
local selectorCooldown = 0
local pendingAdminSelectorToken = nil

local function notify(message, duration)
    if type(IsJRSCharacterUiSuppressed) == 'function' and IsJRSCharacterUiSuppressed() then return end
    TriggerEvent('jrs_core:sendRightTipNotification', tostring(message), tonumber(duration) or 3500)
end

-- Character re-selection can only be initiated by a short-lived server token
-- created by the jrs_character AdminOpenCharacterSelector export.
local function openSelectorFromAdmin(adminToken)
    if type(adminToken) ~= 'string' or #adminToken < 24 then return end

    local now = GetGameTimer()
    if selectorOpen or selectorOpening or now < selectorCooldown then return end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        notify(_U('chc_you_cannot_switch_character_while_dead'), 3000)
        return
    end

    selectorOpening = true
    selectorCooldown = now + 5000
    pendingAdminSelectorToken = adminToken

    if GetResourceState('jrs_pedmenu') == 'started' then
        pcall(function() exports['jrs_pedmenu']:PrepareCharacterTransition() end)
    end

    SetJRSCharacterGate(true, 'admin_character_switch')
    JRSApplyNuiFocus(false, false, false)

    -- Immediately black out screen and set loading state so player does not see character unload in world
    DoScreenFadeOut(500)
    loadingcharacter(true)

    local coords = GetEntityCoords(ped)
    TriggerServerEvent('jrs_character:unload_character', 'admin_character_switch', {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = GetEntityHeading(ped)
    }, adminToken)

    SetTimeout(20000, function()
        if selectorOpening and not selectorOpen and pendingAdminSelectorToken == adminToken then
            selectorOpening = false
            pendingAdminSelectorToken = nil
            SetJRSCharacterGate(false, 'admin_character_switch_timeout')
            notify(_U('chc_character_selection_request_expired'), 4000)
            if IsScreenFadedOut() or IsScreenFadingOut() then
                DoScreenFadeIn(500)
            end
        end
    end)
end

RegisterNetEvent('jrs_character:adminOpenSelector', function(adminToken)
    openSelectorFromAdmin(adminToken)
end)

RegisterNetEvent('jrs_character:adminSelectorAuthorized', function()
    if not selectorOpening or not pendingAdminSelectorToken then return end
    TriggerServerEvent('jrs_character_creator:getCharacters')
end)

RegisterNetEvent('jrs_character:creatorSelectorState', function(open)
    selectorOpen = open == true
    selectorOpening = false
    if selectorOpen then
        pendingAdminSelectorToken = nil
        have_character = false
        is_loaded_character = false
    end
end)

-- Character Selection uses the same dim moonshine-shack interior (78337) as
-- the creator, but none of the creator's own two-lamp Light() rig ever runs
-- here since it hangs off CachePed, and the selector shows several
-- pedslot peds at once rather than one active creator ped. Simple, separate
-- fixture: one static hanging lamp near the selector camera's look-at point,
-- on for as long as the selector is open, independent of Light()/CreatorLight.
local selectorLampObj = nil
local function SelectorLight(state)
    if state then
        if selectorLampObj ~= nil then return end
        CreateThread(function()
            local anchor = CreatorConfig.CharSelect.camera and CreatorConfig.CharSelect.camera.target
            if not anchor then return end
            local model = GetHashKey("p_lamphanging06x")
            RequestModel(model)
            local deadline = GetGameTimer() + 8000
            while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
            if not HasModelLoaded(model) or selectorOpen ~= true then return end
            selectorLampObj = CreateObject(model, anchor.x, anchor.y, anchor.z + 1.6, false, true, true)
            if not selectorLampObj or selectorLampObj == 0 then
                selectorLampObj = nil
                return
            end
            local lightingCfg = CreatorConfig and CreatorConfig.Lighting or {}
            local lightColor = lightingCfg.color or { r = 255, g = 200, b = 170 }
            local selIntensity = tonumber(lightingCfg.selectorIntensity) or 15.0
            SetEntityLightsEnabled(selectorLampObj, true)
            SetLightsTypeForEntity(selectorLampObj, 20)
            SetLightsColorForEntity(selectorLampObj, lightColor.r or 255, lightColor.g or 200, lightColor.b or 170)
            SetLightsIntensityForEntity(selectorLampObj, selIntensity)
            FreezeEntityPosition(selectorLampObj, true)
            SetEntityAlpha(selectorLampObj, 0, false)
            -- Apply once — no per-frame loop needed; the object holds its light state.
            SetLightsIntensityForEntity(selectorLampObj, selIntensity)
            UpdateLightsOnEntity(selectorLampObj)
        end)
    else
        if selectorLampObj ~= nil then
            DeleteObject(selectorLampObj)
            selectorLampObj = nil
        end
    end
end

RegisterNetEvent('jrs_character:creatorSelectorState', function(open)
    SelectorLight(open == true)
end)

-- Some selector scenes are outdoors (mountain slot groups). Ambient wildlife
-- and NPCs kept spawning there - a bear walked in and mauled/ragdolled the
-- preview peds. While the selector is open: zero ambient/scenario density,
-- remove any non-player ped near the selector slots, and stop the preview
-- peds from ragdolling or reacting.
local selectorWildlifeGuardRunning = false
local densityNatives = {
    0xC0258742B034DFAF, -- SET_AMBIENT_ANIMAL_DENSITY_MULTIPLIER_THIS_FRAME
    0xBA0980B5C0A11924, -- SET_AMBIENT_HUMAN_DENSITY_MULTIPLIER_THIS_FRAME
    0xDB48E99F8E064E56, -- SET_SCENARIO_ANIMAL_DENSITY_MULTIPLIER_THIS_FRAME
    0x28CB6391ACEDD9DB, -- SET_SCENARIO_HUMAN_DENSITY_MULTIPLIER_THIS_FRAME
}
local function selectorGuardCenter()
    if type(charselectpeds) == 'table' then
        for _, ped in pairs(charselectpeds) do
            if ped and DoesEntityExist(ped) then return GetEntityCoords(ped) end
        end
    end
    local anchor = CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.camera
        and CreatorConfig.CharSelect.camera.target
    if anchor then return vector3(anchor.x, anchor.y, anchor.z) end
    return nil
end
local function isSelectorPed(ped)
    if type(charselectpeds) ~= 'table' then return false end
    for _, p in pairs(charselectpeds) do
        if p == ped then return true end
    end
    return false
end
local function StartSelectorWildlifeGuard()
    if selectorWildlifeGuardRunning then return end
    selectorWildlifeGuardRunning = true
    local okNatives = {}
    for _, h in ipairs(densityNatives) do
        if pcall(Citizen.InvokeNative, h, 0.0) then okNatives[#okNatives + 1] = h end
    end
    CreateThread(function()
        local nextSweep = 0
        while selectorOpen do
            for i = 1, #okNatives do Citizen.InvokeNative(okNatives[i], 0.0) end
            local now = GetGameTimer()
            if now >= nextSweep then
                nextSweep = now + 250
                local center = selectorGuardCenter()
                if center then
                    for _, ped in ipairs(GetGamePool('CPed')) do
                        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                            if isSelectorPed(ped) then
                                SetPedCanRagdoll(ped, false)
                                SetBlockingOfNonTemporaryEvents(ped, true)
                            elseif #(GetEntityCoords(ped) - center) < 90.0 then
                                if not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped) then
                                    SetEntityAsMissionEntity(ped, true, true)
                                    DeletePed(ped)
                                else
                                    NetworkRequestControlOfEntity(ped)
                                    SetEntityVisible(ped, false)
                                    SetEntityCollision(ped, false, false)
                                end
                            end
                        end
                    end
                end
            end
            Wait(0)
        end
        selectorWildlifeGuardRunning = false
    end)
end

RegisterNetEvent('jrs_character:creatorSelectorState', function(open)
    if open == true then StartSelectorWildlifeGuard() end
end)

-- Sent by the server's loadCharacters() when this session's character is
-- already ready (jrs_core was never restarted, only this resource was) - the
-- normal selector/creator flow that ends with SetJRSCharacterGate(false, ...)
-- never runs again for an already-playing character, but this resource's own
-- restart wipes the client script and characterGateActive defaults back to
-- true, which freezes controls and hides the HUD/radar with nothing left to
-- release them. Only act if the gate actually looks stuck active - a normal
-- mid-session duplicate getCharacters call (other resources trigger it too)
-- must not touch an already-fine gate.
RegisterNetEvent('jrs_character_creator:AlreadyReady', function()
    -- characterGateActive itself is local to a different module scope in this
    -- file; IsJRSCharacterUiSuppressed()/SetJRSCharacterGate are the exported
    -- globals meant for cross-module reads/writes of that same state.
    if not IsJRSCharacterUiSuppressed() then return end
    have_character = true
    is_loaded_character = true
    SetJRSCharacterGate(false, 'already_ready_resync')
end)

RegisterNetEvent('jrs:SelectedCharacter', function()
    selectorOpen = false
    selectorOpening = false
    pendingAdminSelectorToken = nil
    have_character = true
end)

-- No public in-game selector event/command is registered here.
-- Initial character selection below remains unchanged for login.

CreateThread(function()
    Wait(1000)
    loadingcharacter(true)
    TriggerServerEvent('jrs_character_creator:getCharacters')
end)
end

-- ============================================================================
-- Module: appearance/settings/overlays.lua
-- ============================================================================
do
overlays_info = {

    ["eyebrows"] = {
                    {id=0x07844317,albedo=0xF81B2E66,normal=0x7BC4288B,ma=0x202674A1,},    --   {albedo="mp_u_faov_eyebrow_m_012_ab",normal="mp_u_faov_eyebrow_m_012_nm",ma="mp_u_faov_eyebrow_m_012_ma",},
                    {id=0x0A83CA6E,albedo=0x8FA4286B,normal=0xBD811948,ma=0xB82C8FBB,},    --   {albedo="mp_u_faov_eyebrow_m_006_ab",normal="mp_u_faov_eyebrow_m_006_nm",ma="mp_u_faov_eyebrow_m_006_ma",},
                    {id=0x139A5CA3,albedo=0x487ABE5A,normal=0x22A9DDF9,ma=0x78AA9401,},    --   {albedo="mp_u_faov_eyebrow_m_003_ab",normal="mp_u_faov_eyebrow_m_003_nm",ma="mp_u_faov_eyebrow_m_003_ma",},
                    {id=0x1832E474,albedo=0x96FBB931,normal=0x32FA2683,ma=0xA1775B18,},    --   {albedo="mp_u_faov_eyebrow_m_011_ab",normal="mp_u_faov_eyebrow_m_011_nm",ma="mp_u_faov_eyebrow_m_011_ma",},
                    {id=0x216EF84C,albedo=0x269CD8F8,normal=0x2F54C727,ma=0xCCBD1939,},    --   {albedo="mp_u_faov_eyebrow_m_002_ab",normal="mp_u_faov_eyebrow_m_002_nm",ma="mp_u_faov_eyebrow_m_002_ma",},
                    {id=0x2594304D,albedo=0xA5A23CD1,normal=0x8611B42C,ma=0x0238302B,},    --   {albedo="mp_u_faov_eyebrow_f_004_ab",normal="mp_u_faov_eyebrow_f_004_nm",ma="mp_u_faov_eyebrow_f_004_ma",},
                    {id=0x33C39BC5,albedo=0xF928E29B,normal=0x46C268BD,ma=0x4B92F13E,},    --   {albedo="mp_u_faov_eyebrow_m_013_ab",normal="mp_u_faov_eyebrow_m_013_nm",ma="mp_u_faov_eyebrow_m_013_ma",},
                    {id=0x443E3CBA,albedo=0x6C83B571,normal=0x2B191070,ma=0xD551E623,},    --   {albedo="mp_u_faov_eyebrow_m_014_ab",normal="mp_u_faov_eyebrow_m_014_nm",ma="mp_u_faov_eyebrow_m_014_ma",},
                    {id=0x4F5052DE,albedo=0x827EEF46,normal=0x70E8C702,ma=0xD97518F9,},    --   {albedo="mp_u_faov_eyebrow_m_015_ab",normal="mp_u_faov_eyebrow_m_015_nm",ma="mp_u_faov_eyebrow_m_015_ma",},
                    {id=0x5C049D35,albedo=0x41E90506,normal=0x7E47D163,ma=0x54100288,},    --   {albedo="mp_u_faov_eyebrow_f_001_ab",normal="mp_u_faov_eyebrow_f_001_nm",ma="mp_u_faov_eyebrow_f_001_ma",},
                    {id=0x77A1546E,albedo=0x43C4AE44,normal=0x290FC7F7,ma=0xD8FC26A9,},    --   {albedo="mp_u_faov_eyebrow_f_003_ab",normal="mp_u_faov_eyebrow_f_003_nm",ma="mp_u_faov_eyebrow_f_003_ma",},
                    {id=0x8A4B79C2,albedo=0xAE6ED4E6,normal=0x89B29E5A,ma=0xFA0476E4,},    --   {albedo="mp_u_faov_eyebrow_f_002_ab",normal="mp_u_faov_eyebrow_f_002_nm",ma="mp_u_faov_eyebrow_f_002_ma",},
                    {id=0x9728137B,albedo=0x23E65D35,normal=0xEE39073F,ma=0x218DD4C8,},    --   {albedo="mp_u_faov_eyebrow_f_006_ab",normal="mp_u_faov_eyebrow_f_006_nm",ma="mp_u_faov_eyebrow_f_006_ma",},
                    {id=0xA6DE8325,albedo=0x7A93F649,normal=0x22B33B65,ma=0xEE6CCF11,},    --   {albedo="mp_u_faov_eyebrow_m_008_ab",normal="mp_u_faov_eyebrow_m_008_nm",ma="mp_u_faov_eyebrow_m_008_ma",},
                    {id=0xA8CCB6C4,albedo=0x29AD8BF9,normal=0x34ABB09D,ma=0xCF206860,},    --   {albedo="mp_u_faov_eyebrow_f_005_ab",normal="mp_u_faov_eyebrow_f_005_nm",ma="mp_u_faov_eyebrow_f_005_ma",},
                    {id=0xB3F74D19,albedo=0x3E2F71B1,normal=0xD4809D11,ma=0x9ABFA640,},    --   {albedo="mp_u_faov_eyebrow_f_007_ab",normal="mp_u_faov_eyebrow_f_007_nm",ma="mp_u_faov_eyebrow_f_007_ma",},
                    {id=0xBD38AFD9,albedo=0x058A698E,normal=0x9A732F86,ma=0x2EF1D769,},    --   {albedo="mp_u_faov_eyebrow_m_007_ab",normal="mp_u_faov_eyebrow_m_007_nm",ma="mp_u_faov_eyebrow_m_007_ma",},
                    {id=0xCD0A4F7C,albedo=0xED46998E,normal=0xB5B73A38,ma=0x15C5FB78,},    --   {albedo="mp_u_faov_eyebrow_m_009_ab",normal="mp_u_faov_eyebrow_m_009_nm",ma="mp_u_faov_eyebrow_m_009_ma",},
                    {id=0xD0EC86FF,albedo=0x81B462A2,normal=0x894F8744,ma=0x51551810,},    --   {albedo="mp_u_faov_eyebrow_f_000_ab",normal="mp_u_faov_eyebrow_f_000_nm",ma="mp_u_faov_eyebrow_f_000_ma",},
                    {id=0xEB088A20,albedo=0x0C6CDBDC,normal=0x91A2496E,ma=0xE639F138,},    --   {albedo="mp_u_faov_eyebrow_m_010_ab",normal="mp_u_faov_eyebrow_m_010_nm",ma="mp_u_faov_eyebrow_m_010_ma",},
                    {id=0xF0CA96FC,albedo=0xAC3BCA3F,normal=0x667FEFF8,ma=0xDD8E5EFF,},    --   {albedo="mp_u_faov_eyebrow_m_005_ab",normal="mp_u_faov_eyebrow_m_005_nm",ma="mp_u_faov_eyebrow_m_005_ma",},
                    {id=0xF3351BD9,albedo=0xC3286EA4,normal=0x8BB9158A,ma=0xFBBAE4D8,},    --   {albedo="mp_u_faov_eyebrow_m_001_ab",normal="mp_u_faov_eyebrow_m_001_nm",ma="mp_u_faov_eyebrow_m_001_ma",},
                    {id=0xF9052779,albedo=0x8AEADE78,normal=0x21BB2D97,ma=0x75A0B928,},    --   {albedo="mp_u_faov_eyebrow_m_000_ab",normal="mp_u_faov_eyebrow_m_000_nm",ma="mp_u_faov_eyebrow_m_000_ma",},
                    {id=0xFE183197,albedo=0x92B508CD,normal=0x6AA92A3E,ma=0xB4A436DB,},    --   {albedo="mp_u_faov_eyebrow_m_004_ab",normal="mp_u_faov_eyebrow_m_004_nm",ma="mp_u_faov_eyebrow_m_004_ma",},
                },

    ["scars"] =     {
                    {id=0xC8E45B5B,albedo=0x6245579F,normal=0xD53A336F,},       -- {albedo="mp_u_faov_scar_000_ab",normal="mp_u_faov_scar_000_nm",},
                    {id=0x90D86B44,albedo=0xA1538E6F,normal=0xDFCB1159,},       -- {albedo="mp_u_faov_scar_001_ab",normal="mp_u_faov_scar_001_nm",},
                    {id=0x23190FC3,albedo=0x39683ECE,normal=0x249C1A0A,},       -- {albedo="mp_u_faov_scar_002_ab",normal="mp_u_faov_scar_002_nm",},
                    {id=0x7574B47D,albedo=0x3AB2A0BB,normal=0x7A70886A,},       -- {albedo="mp_u_faov_scar_003_ab",normal="mp_u_faov_scar_003_nm",},
                    {id=0x7FE8C965,albedo=0xB81C8D16,normal=0x7210971B,},       -- {albedo="mp_u_faov_scar_004_ab",normal="mp_u_faov_scar_004_nm",},
                    {id=0x083059FE,albedo=0xC332710C,normal=0x860EE45E,},       -- {albedo="mp_u_faov_scar_005_ab",normal="mp_u_faov_scar_005_nm",},
                    {id=0x19E9FD71,albedo=0x40895310,normal=0xB753C5C7,},       -- {albedo="mp_u_faov_scar_006_ab",normal="mp_u_faov_scar_006_nm",},
                    {id=0x4CAF62FB,albedo=0xD80F2F64,normal=0x00BBF225,},       -- {albedo="mp_u_faov_scar_007_ab",normal="mp_u_faov_scar_007_nm",},
                    {id=0xDE650668,albedo=0x85F6BF71,normal=0x3DD0B0AE,},       -- {albedo="mp_u_faov_scar_008_ab",normal="mp_u_faov_scar_008_nm",},
                    {id=0xC648562B,albedo=0x6397E4D9,normal=0x2B59CDA1,},       -- {albedo="mp_u_faov_scar_009_ab",normal="mp_u_faov_scar_009_nm",},
                    {id=0x484BAEF8,albedo=0xBF2946DE,normal=0xD3F2F2F6,},       -- {albedo="mp_u_faov_scar_010_ab",normal="mp_u_faov_scar_010_nm",},
                    {id=0x190F5080,albedo=0xCBBDB741,normal=0x9518FA34,},       -- {albedo="mp_u_faov_scar_011_ab",normal="mp_u_faov_scar_011_nm",},
                    {id=0x2B5DF51D,albedo=0x0E05C415,normal=0x8B8C57AC,},       -- {albedo="mp_u_faov_scar_012_ab",normal="mp_u_faov_scar_012_nm",},
                    {id=0xE490E784,albedo=0x50853115,normal=0xDA7F2A1E,},       -- {albedo="mp_u_faov_scar_013_ab",normal="mp_u_faov_scar_013_nm",},
                    {id=0x0ED23C06,albedo=0xAEA45D76,normal=0x364DAAA6,},       -- {albedo="mp_u_faov_scar_014_ab",normal="mp_u_faov_scar_014_nm",},
                    {id=0x5712CCB6,albedo=0x9318AF61,normal=0x98104C8C,},       -- {albedo="mp_u_faov_scar_015_ab",normal="mp_u_faov_scar_015_nm",},

                },
    ["scars2"] =     {
        {id=0xC8E45B5B,albedo=0x6245579F,normal=0xD53A336F,},       -- {albedo="mp_u_faov_scar_000_ab",normal="mp_u_faov_scar_000_nm",},
        {id=0x90D86B44,albedo=0xA1538E6F,normal=0xDFCB1159,},       -- {albedo="mp_u_faov_scar_001_ab",normal="mp_u_faov_scar_001_nm",},
        {id=0x23190FC3,albedo=0x39683ECE,normal=0x249C1A0A,},       -- {albedo="mp_u_faov_scar_002_ab",normal="mp_u_faov_scar_002_nm",},
        {id=0x7574B47D,albedo=0x3AB2A0BB,normal=0x7A70886A,},       -- {albedo="mp_u_faov_scar_003_ab",normal="mp_u_faov_scar_003_nm",},
        {id=0x7FE8C965,albedo=0xB81C8D16,normal=0x7210971B,},       -- {albedo="mp_u_faov_scar_004_ab",normal="mp_u_faov_scar_004_nm",},
        {id=0x083059FE,albedo=0xC332710C,normal=0x860EE45E,},       -- {albedo="mp_u_faov_scar_005_ab",normal="mp_u_faov_scar_005_nm",},
        {id=0x19E9FD71,albedo=0x40895310,normal=0xB753C5C7,},       -- {albedo="mp_u_faov_scar_006_ab",normal="mp_u_faov_scar_006_nm",},
        {id=0x4CAF62FB,albedo=0xD80F2F64,normal=0x00BBF225,},       -- {albedo="mp_u_faov_scar_007_ab",normal="mp_u_faov_scar_007_nm",},
        {id=0xDE650668,albedo=0x85F6BF71,normal=0x3DD0B0AE,},       -- {albedo="mp_u_faov_scar_008_ab",normal="mp_u_faov_scar_008_nm",},
        {id=0xC648562B,albedo=0x6397E4D9,normal=0x2B59CDA1,},       -- {albedo="mp_u_faov_scar_009_ab",normal="mp_u_faov_scar_009_nm",},
        {id=0x484BAEF8,albedo=0xBF2946DE,normal=0xD3F2F2F6,},       -- {albedo="mp_u_faov_scar_010_ab",normal="mp_u_faov_scar_010_nm",},
        {id=0x190F5080,albedo=0xCBBDB741,normal=0x9518FA34,},       -- {albedo="mp_u_faov_scar_011_ab",normal="mp_u_faov_scar_011_nm",},
        {id=0x2B5DF51D,albedo=0x0E05C415,normal=0x8B8C57AC,},       -- {albedo="mp_u_faov_scar_012_ab",normal="mp_u_faov_scar_012_nm",},
        {id=0xE490E784,albedo=0x50853115,normal=0xDA7F2A1E,},       -- {albedo="mp_u_faov_scar_013_ab",normal="mp_u_faov_scar_013_nm",},
        {id=0x0ED23C06,albedo=0xAEA45D76,normal=0x364DAAA6,},       -- {albedo="mp_u_faov_scar_014_ab",normal="mp_u_faov_scar_014_nm",},
        {id=0x5712CCB6,albedo=0x9318AF61,normal=0x98104C8C,},       -- {albedo="mp_u_faov_scar_015_ab",normal="mp_u_faov_scar_015_nm",},

    },
    ["scars3"] =     {
        {id=0xC8E45B5B,albedo=0x6245579F,normal=0xD53A336F,},       -- {albedo="mp_u_faov_scar_000_ab",normal="mp_u_faov_scar_000_nm",},
        {id=0x90D86B44,albedo=0xA1538E6F,normal=0xDFCB1159,},       -- {albedo="mp_u_faov_scar_001_ab",normal="mp_u_faov_scar_001_nm",},
        {id=0x23190FC3,albedo=0x39683ECE,normal=0x249C1A0A,},       -- {albedo="mp_u_faov_scar_002_ab",normal="mp_u_faov_scar_002_nm",},
        {id=0x7574B47D,albedo=0x3AB2A0BB,normal=0x7A70886A,},       -- {albedo="mp_u_faov_scar_003_ab",normal="mp_u_faov_scar_003_nm",},
        {id=0x7FE8C965,albedo=0xB81C8D16,normal=0x7210971B,},       -- {albedo="mp_u_faov_scar_004_ab",normal="mp_u_faov_scar_004_nm",},
        {id=0x083059FE,albedo=0xC332710C,normal=0x860EE45E,},       -- {albedo="mp_u_faov_scar_005_ab",normal="mp_u_faov_scar_005_nm",},
        {id=0x19E9FD71,albedo=0x40895310,normal=0xB753C5C7,},       -- {albedo="mp_u_faov_scar_006_ab",normal="mp_u_faov_scar_006_nm",},
        {id=0x4CAF62FB,albedo=0xD80F2F64,normal=0x00BBF225,},       -- {albedo="mp_u_faov_scar_007_ab",normal="mp_u_faov_scar_007_nm",},
        {id=0xDE650668,albedo=0x85F6BF71,normal=0x3DD0B0AE,},       -- {albedo="mp_u_faov_scar_008_ab",normal="mp_u_faov_scar_008_nm",},
        {id=0xC648562B,albedo=0x6397E4D9,normal=0x2B59CDA1,},       -- {albedo="mp_u_faov_scar_009_ab",normal="mp_u_faov_scar_009_nm",},
        {id=0x484BAEF8,albedo=0xBF2946DE,normal=0xD3F2F2F6,},       -- {albedo="mp_u_faov_scar_010_ab",normal="mp_u_faov_scar_010_nm",},
        {id=0x190F5080,albedo=0xCBBDB741,normal=0x9518FA34,},       -- {albedo="mp_u_faov_scar_011_ab",normal="mp_u_faov_scar_011_nm",},
        {id=0x2B5DF51D,albedo=0x0E05C415,normal=0x8B8C57AC,},       -- {albedo="mp_u_faov_scar_012_ab",normal="mp_u_faov_scar_012_nm",},
        {id=0xE490E784,albedo=0x50853115,normal=0xDA7F2A1E,},       -- {albedo="mp_u_faov_scar_013_ab",normal="mp_u_faov_scar_013_nm",},
        {id=0x0ED23C06,albedo=0xAEA45D76,normal=0x364DAAA6,},       -- {albedo="mp_u_faov_scar_014_ab",normal="mp_u_faov_scar_014_nm",},
        {id=0x5712CCB6,albedo=0x9318AF61,normal=0x98104C8C,},       -- {albedo="mp_u_faov_scar_015_ab",normal="mp_u_faov_scar_015_nm",},

    },

    ["eyeliners"] = {
                    {id=0x29A2E58F,albedo=0xA952BF75,ma=0xDD55AF2A,},                                                -- {albedo="mp_u_faov_eyeliner_000_ab",ma="mp_u_faov_eyeliner_000_ma",},
                },

    ["lipsticks"] = {
                    {id=0x887E11E0,albedo=0x96A5E4FB,normal=0x1C77591C,ma=0x4255A5F4,},                              -- {albedo="mp_u_faov_lipstick_000_ab",normal="mp_u_faov_lipstick_000_nm",ma="mp_u_faov_lipstick_000_ma",},  -- 7variantov
                },

    ["acne"] =  {
                    {id=0x96DD8F42,albedo=0x1BA4244B,normal=0xBA46CE92,},                                           -- {albedo="mp_u_faov_acne_000_ab",normal="mp_u_faov_acne_000_nm",},
                },

    ["shadows"] = {
                    {id=0x47BD7289,albedo=0x5C5C98FC,ma=0xE20345CC,},                                               -- {albedo="mp_u_faov_eyeshadow_000_ab",ma="mp_u_faov_eyeshadow_000_ma",},  -- 6 variantov
                },

    ["beardstabble"] = {
                    {id=0x375D4807,albedo=0xB5827817,normal=0x5041B648,ma=0x83F42340,},                              -- {albedo="mp_u_faov_beard_000_ab",normal="mp_u_faov_beard_000_nm",ma="mp_u_faov_beard_000_ma",},
                },

    ["paintedmasks"] = {
                    {id=0x5995AA6F,albedo=0x99BCB03F,},                                                              -- {albedo="mp_u_faov_masks_000_ab",},
                },

    ["ageing"]  = {
                    {id=0x96DD8F42,albedo=0x1BA4244B,normal=0xBA46CE92,},                                            -- {albedo="mp_u_faov_acne_000_ab",normal="mp_u_faov_acne_000_nm",},
                    {id=0x6D9DC405,albedo=0xAFE82F0C,normal=0x5CF8808E,},                                            -- {albedo="mp_u_faov_ageing_000_ab",normal="mp_u_faov_ageing_000_nm",},
                    {id=0x2761B792,albedo=0x4105C6B3,normal=0x8607CC56,},                                            -- {albedo="mp_u_faov_ageing_001_ab",normal="mp_u_faov_ageing_001_nm",},
                    {id=0x19009AD0,albedo=0xEBC18618,normal=0x9087AF96,},                                            -- {albedo="mp_u_faov_ageing_002_ab",normal="mp_u_faov_ageing_002_nm",},
                    {id=0xC29F6E07,albedo=0xF9887FA7,normal=0x1331C3C9,},                                            -- {albedo="mp_u_faov_ageing_003_ab",normal="mp_u_faov_ageing_003_nm",},
                    {id=0xA45F3187,albedo=0x1C30961A,normal=0x3CA2F3AE,},                                            -- {albedo="mp_u_faov_ageing_004_ab",normal="mp_u_faov_ageing_004_nm",},
                    {id=0x5E21250C,albedo=0x01E35044,normal=0x5A965FF0,},                                            -- {albedo="mp_u_faov_ageing_005_ab",normal="mp_u_faov_ageing_005_nm",},
                    {id=0x4FFE08C6,albedo=0xA65757F2,normal=0xC46CC005,},                                            -- {albedo="mp_u_faov_ageing_006_ab",normal="mp_u_faov_ageing_006_nm",},
                    {id=0x2DAD4485,albedo=0x358DEFDA,normal=0x55D317B4,},                                            -- {albedo="mp_u_faov_ageing_007_ab",normal="mp_u_faov_ageing_007_nm",},
                    {id=0x3F70680B,albedo=0x7073A58F,normal=0x33E73C5F,},                                            -- {albedo="mp_u_faov_ageing_008_ab",normal="mp_u_faov_ageing_008_nm",},
                    {id=0xD3310F8E,albedo=0xD9E8A605,normal=0x22297EA5,},                                            -- {albedo="mp_u_faov_ageing_009_ab",normal="mp_u_faov_ageing_009_nm",},
                    {id=0xF27A4C84,albedo=0xE0F0971B,normal=0x9F0E6718,},                                            -- {albedo="mp_u_faov_ageing_010_ab",normal="mp_u_faov_ageing_010_nm",},
                    {id=0x0044E819,albedo=0xFD844ADF,normal=0x315A6D56,},                                            -- {albedo="mp_u_faov_ageing_011_ab",normal="mp_u_faov_ageing_011_nm",},
                    {id=0xA648348D,albedo=0xC329F765,normal=0xE8CD7F20,},                                            -- {albedo="mp_u_faov_ageing_012_ab",normal="mp_u_faov_ageing_012_nm",},
                    {id=0x94F991F0,albedo=0x8586D19B,normal=0xCA334396,},                                            -- {albedo="mp_u_faov_ageing_013_ab",normal="mp_u_faov_ageing_013_nm",},
                    {id=0xCAACFD56,albedo=0xD2D0BF4F,normal=0xE0203BDA,},                                            -- {albedo="mp_u_faov_ageing_014_ab",normal="mp_u_faov_ageing_014_nm",},
                    {id=0xB9675ACB,albedo=0x2387AF71,normal=0x90A80AE1,},                                            -- {albedo="mp_u_faov_ageing_015_ab",normal="mp_u_faov_ageing_015_nm",},
                    {id=0x3C2CE03C,albedo=0xC6DCBCCA,normal=0x609B7EBD,},                                            -- {albedo="mp_u_faov_ageing_016_ab",normal="mp_u_faov_ageing_016_nm",},
                    {id=0xF2D64D90,albedo=0xC6DCBCCA,normal=0x609B7EBD,},                                            -- {albedo="mp_u_faov_ageing_016_ab",normal="mp_u_faov_ageing_016_nm",},
                    {id=0xE389AEF7,albedo=0xDF591FF2,normal=0x11D92A14,},                                            -- {albedo="mp_u_faov_ageing_018_ab",normal="mp_u_faov_ageing_018_nm",},
                    {id=0x89317A44,albedo=0xB4640D19,normal=0x2F56FDA5,},                                            -- {albedo="mp_u_faov_ageing_019_ab",normal="mp_u_faov_ageing_019_nm",},
                    {id=0x64B3347C,albedo=0xFF2E8F96,normal=0x45EE7B10,},                                            -- {albedo="mp_u_faov_ageing_020_ab",normal="mp_u_faov_ageing_020_nm",},
                    {id=0x9FFDAB10,albedo=0x8F2950D9,normal=0x85BDD7E8,},                                            -- {albedo="mp_u_faov_ageing_021_ab",normal="mp_u_faov_ageing_021_nm",},
                    {id=0x91D40EBD,albedo=0x5DCD1D4E,normal=0xA1B5F71F,},                                            -- {albedo="mp_u_faov_ageing_022_ab",normal="mp_u_faov_ageing_022_nm",},
                    {id=0x6B94C23F,albedo=0xF17FE41C,normal=0x0C480977,},                                            -- {albedo="mp_u_faov_ageing_023_ab",normal="mp_u_faov_ageing_023_nm",},
                },
    ["blush"] = {
                    {id=0x6DB440FA,albedo=0x43B1AACA,},                                                              -- {albedo="mp_u_faov_blush_000_ab",},
                    {id=0x47617455,albedo=0x9CAD2EF0,},                                                              -- {albedo="mp_u_faov_blush_001_ab",},
                    {id=0x114D082D,albedo=0xA52E3B98,},                                                              -- {albedo="mp_u_faov_blush_002_ab",},
                    {id=0xEC6F3E72,albedo=0xB5CED4CB,},                                                              -- {albedo="mp_u_faov_blush_003_ab",},
                },
    ["blush2"] = {
        {id=0x6DB440FA,albedo=0x43B1AACA,},                                                              -- {albedo="mp_u_faov_blush_000_ab",},
        {id=0x47617455,albedo=0x9CAD2EF0,},                                                              -- {albedo="mp_u_faov_blush_001_ab",},
        {id=0x114D082D,albedo=0xA52E3B98,},                                                              -- {albedo="mp_u_faov_blush_002_ab",},
        {id=0xEC6F3E72,albedo=0xB5CED4CB,},                                                              -- {albedo="mp_u_faov_blush_003_ab",},
    },
    ["complex"] = {
                    {id=0xF679EDE7,albedo=0xFAAE9FF0,},                                                              -- {albedo="mp_u_faov_complex_000_ab",},
                    {id=0x3FFB80ED,albedo=0x1FDFD4A1,},                                                              -- {albedo="mp_u_faov_complex_001_ab",},
                    {id=0x31C0E478,albedo=0xC72D0698,},                                                              -- {albedo="mp_u_faov_complex_002_ab",},
                    {id=0x2457C9A6,albedo=0x98F1C76F,},                                                              -- {albedo="mp_u_faov_complex_003_ab",},
                    {id=0x16262D43,albedo=0xE0D03293,},                                                              -- {albedo="mp_u_faov_complex_004_ab",},
                    {id=0x88F312DB,albedo=0x2ECCC670,},                                                              -- {albedo="mp_u_faov_complex_005_ab",},
                    {id=0x785C71AE,albedo=0xAE1C329F,},                                                              -- {albedo="mp_u_faov_complex_006_ab",},
                    {id=0x6D7D5BF0,albedo=0x23201E55,},                                                              -- {albedo="mp_u_faov_complex_007_ab",},
                    {id=0x5F2FBF55,albedo=0x94503F97,},                                                              -- {albedo="mp_u_faov_complex_008_ab",},
                    {id=0xBF38FF6A,albedo=0x5F62F986,},                                                              -- {albedo="mp_u_faov_complex_009_ab",},
                    {id=0xF5656C26,albedo=0x83417009,},                                                              -- {albedo="mp_u_faov_complex_010_ab",},
                    {id=0x03A408A3,albedo=0x1BCC4185,},                                                              -- {albedo="mp_u_faov_complex_011_ab",},
                    {id=0x293453C3,albedo=0x6C556574,},                                                              -- {albedo="mp_u_faov_complex_012_ab",},
                    {id=0x43150800,albedo=0x1E486F85,},                                                              -- {albedo="mp_u_faov_complex_013_ab",},
                },
    ["disc"]  = {
                    {id=0xD44A5ABA,albedo=0x2D3AEB2F,},                                                              -- {albedo="mp_u_faov_disc_000_ab",},
                    {id=0xE2CF77C4,albedo=0xB8945AC0,},                                                              -- {albedo="mp_u_faov_disc_001_ab",},
                    {id=0xCF57D0E9,albedo=0xB15E4E47,},                                                              -- {albedo="mp_u_faov_disc_002_ab",},
                    {id=0xE0A8738A,albedo=0x25A711DD,},                                                              -- {albedo="mp_u_faov_disc_003_ab",},
                    {id=0xABD109DC,albedo=0xCEBED6D9,},                                                              -- {albedo="mp_u_faov_disc_004_ab",},
                    {id=0xB91C2472,albedo=0xFDD6C9AB,},                                                              -- {albedo="mp_u_faov_disc_005_ab",},
                    {id=0x894844B7,albedo=0x7E89B165,},                                                              -- {albedo="mp_u_faov_disc_006_ab",},
                    {id=0x96FAE01C,albedo=0x458799CD,},                                                              -- {albedo="mp_u_faov_disc_007_ab",},
                    {id=0x86D3BFCE,albedo=0x8F2F2826,},                                                              -- {albedo="mp_u_faov_disc_008_ab",},
                    {id=0x5488DB39,albedo=0xB49A0275,},                                                              -- {albedo="mp_u_faov_disc_009_ab",},
                    {id=0x7DA5A5AE,albedo=0x8200F51D,},                                                              -- {albedo="mp_u_faov_disc_010_ab",},
                    {id=0xE73778DC,albedo=0x8D35AC90,},                                                              -- {albedo="mp_u_faov_disc_011_ab",},
                    {id=0xD83EDADF,albedo=0x96B619CD,},                                                              -- {albedo="mp_u_faov_disc_012_ab",},
                    {id=0xE380F163,albedo=0xAB7309F7,},                                                              -- {albedo="mp_u_faov_disc_013_ab",},
                    {id=0xB4611324,albedo=0x26FEBDD4,},                                                              -- {albedo="mp_u_faov_disc_014_ab",},
                    {id=0xC6ABB7B9,albedo=0xC162C835,},                                                              -- {albedo="mp_u_faov_disc_015_ab",},
                },
    ["foundation"] = {
                    {id=0xEF5AB280,albedo=0xD9264247,ma=0x1535C7C9,},                                                -- {albedo="mp_u_faov_foundation_000_ab",ma="mp_u_faov_foundation_000_ma",},
                },
    ["freckles"] =  {
                    {id=0x1B794C51,albedo=0x59B8159A,},                                                              -- {albedo="mp_u_faov_freckles_000_ab",},
                    {id=0x29BFE8DE,albedo=0x03FCF67B,},                                                              -- {albedo="mp_u_faov_freckles_001_ab",},
                    {id=0x0EF6B34C,albedo=0x21E2FD82,},                                                              -- {albedo="mp_u_faov_freckles_002_ab",},
                    {id=0x64925E7E,albedo=0x3FD45844,},                                                              -- {albedo="mp_u_faov_freckles_003_ab",},
                    {id=0xF5F280FC,albedo=0xE372E00E,},                                                              -- {albedo="mp_u_faov_freckles_004_ab",},
                    {id=0x33B0FC78,albedo=0x288810E0,},                                                              -- {albedo="mp_u_faov_freckles_005_ab",},
                    {id=0x25675FE5,albedo=0xEB8C0B1D,},                                                              -- {albedo="mp_u_faov_freckles_006_ab",},
                    {id=0xD10F3736,albedo=0x3885AC2A,},                                                              -- {albedo="mp_u_faov_freckles_007_ab",},
                    {id=0x5126B75F,albedo=0xB061C984,},                                                              -- {albedo="mp_u_faov_freckles_008_ab",},
                    {id=0x6B8EEC2F,albedo=0xE1D1113E,},                                                              -- {albedo="mp_u_faov_freckles_009_ab",},
                    {id=0x0A9A26F7,albedo=0xA1EC1AEA,},                                                              -- {albedo="mp_u_faov_freckles_010_ab",},
                    {id=0xFDE40D8B,albedo=0x6DBC9203,},                                                              -- {albedo="mp_u_faov_freckles_011_ab",},
                    {id=0x7E338E44,albedo=0x097D1D0A,},                                                              -- {albedo="mp_u_faov_freckles_012_ab",},
                    {id=0x70F273C2,albedo=0x81A25BCE,},                                                              -- {albedo="mp_u_faov_freckles_013_ab",},
                    {id=0x61C7D56D,albedo=0x197A1335,},                                                              -- {albedo="mp_u_faov_freckles_014_ab",},
    },
    ["grime"] =     {
                    {id=0xA2F30923,albedo=0x16CDD724,normal=0x136165B3,ma=0xF3DFA7AC,},                              -- {albedo="mp_u_faov_grime_000_ab",normal="mp_u_faov_grime_000_nm",ma="mp_u_faov_grime_000_ma",},
                    {id=0xD5B1EEA0,albedo=0x0E599D69,normal=0x5C67FB68,ma=0x40FEC59E,},                              -- {albedo="mp_u_faov_grime_001_ab",normal="mp_u_faov_grime_001_nm",ma="mp_u_faov_grime_001_ma",},
                    {id=0x7EC740CC,albedo=0x0FAE8DC6,normal=0x9E7A4B63,ma=0xB48BF65A,},                              -- {albedo="mp_u_faov_grime_002_ab",normal="mp_u_faov_grime_002_nm",ma="mp_u_faov_grime_002_ma",},
                    {id=0xB08F245B,albedo=0x98358521,normal=0x1FAA4A84,ma=0x81428E8F,},                              -- {albedo="mp_u_faov_grime_003_ab",normal="mp_u_faov_grime_003_nm",ma="mp_u_faov_grime_003_ma",},
                    {id=0x1A5E77F8,albedo=0x8D3D2563,normal=0x1FAA4A84,ma=0x81428E8F,},                              -- {albedo="mp_u_faov_grime_004_ab",normal="mp_u_faov_grime_003_nm",ma="mp_u_faov_grime_003_ma",},
                    {id=0xE81B9373,albedo=0xAE43378D,normal=0x0CBEEF9B,ma=0x92097B22,},                              -- {albedo="mp_u_faov_grime_005_ab",normal="mp_u_faov_grime_005_nm",ma="mp_u_faov_grime_005_ma",},
                    {id=0x3CFA3D2F,albedo=0x7499570E,normal=0xA27FF667,ma=0x24B49749,},                              -- {albedo="mp_u_faov_grime_006_ab",normal="mp_u_faov_grime_006_nm",ma="mp_u_faov_grime_006_ma",},
                    {id=0x0B865A48,albedo=0xB80F6B12,normal=0x377319E3,ma=0x3CDC25A9,},                              -- {albedo="mp_u_faov_grime_007_ab",normal="mp_u_faov_grime_007_nm",ma="mp_u_faov_grime_007_ma",},
                    {id=0x506DE416,albedo=0x537BA522,normal=0x006AF092,ma=0x5CCEA9F8,},                              -- {albedo="mp_u_faov_grime_008_ab",normal="mp_u_faov_grime_008_nm",ma="mp_u_faov_grime_008_ma",},
                    {id=0x1F250185,albedo=0x51BE975D,normal=0x3F718027,ma=0x5527ACCF,},                              -- {albedo="mp_u_faov_grime_009_ab",normal="mp_u_faov_grime_009_nm",ma="mp_u_faov_grime_009_ma",},
                    {id=0xE71930B0,albedo=0x595D09A3,normal=0xF4E08D43,ma=0x60B91CE7,},                              -- {albedo="mp_u_faov_grime_010_ab",normal="mp_u_faov_grime_010_nm",ma="mp_u_faov_grime_010_ma",},
                    {id=0xDE571F2C,albedo=0xE7FAFDFA,normal=0xE6A18BBF,ma=0xCB315A57,},                              -- {albedo="mp_u_faov_grime_011_ab",normal="mp_u_faov_grime_011_nm",ma="mp_u_faov_grime_011_ma",},
                    {id=0x0CA6FBCB,albedo=0x0E27372E,normal=0xD4894921,ma=0xBF339D56,},                              -- {albedo="mp_u_faov_grime_012_ab",normal="mp_u_faov_grime_012_nm",ma="mp_u_faov_grime_012_ma",},
                    {id=0x21F62669,albedo=0x693623F0,normal=0xDB95176C,ma=0xEA27B375,},                              -- {albedo="mp_u_faov_grime_013_ab",normal="mp_u_faov_grime_013_nm",ma="mp_u_faov_grime_013_ma",},
                    {id=0xFB09D881,albedo=0xC4A40DA0,normal=0xADD1DC3D,ma=0xFD797A87,},                              -- {albedo="mp_u_faov_grime_014_ab",normal="mp_u_faov_grime_014_nm",ma="mp_u_faov_grime_014_ma",},
                    {id=0x11530513,albedo=0x67C6D30F,normal=0x26AA38C3,ma=0x89C2FFE3,},                              -- {albedo="mp_u_faov_grime_015_ab",normal="mp_u_faov_grime_015_nm",ma="mp_u_faov_grime_015_ma",},
                },
    ["hairstabble"] =  {
                    {id=0x39051515,albedo=0x60A4A360,normal=0x8D65EFF2,ma=0x62759D82,},                              -- {albedo="mp_u_faov_m_hair_000_ab",normal="mp_u_faov_m_hair_000_nm",ma="mp_u_faov_m_hair_000_ma",},
                    {id=0x5E71DFEE,albedo=0x71147B90,ma=0xD8EB57BC,},                                                -- {albedo="mp_u_faov_m_hair_002_ab",ma="mp_u_faov_m_hair_002_ma",},
                    {id=0xDD735DEF,albedo=0x493214E4,ma=0x6613D121,},                                                -- {albedo="mp_u_faov_m_hair_009_ab",ma="mp_u_faov_m_hair_009_ma",},
                    {id=0x69622EAD,albedo=0xA6E819C4,ma=0xE581D851,},                                                -- {albedo="mp_u_faov_m_hair_shared_000_ab",ma="mp_u_faov_m_hair_shared_000_ma",},
                },
    ["moles"] = {
                    {id=0x821FD077,albedo=0xDFDA0798,normal=0xE4E90C92,},                                            -- {albedo="mp_u_faov_moles_000_ab",normal="mp_u_faov_moles_000_nm",},
                    {id=0xCD38E6A8,albedo=0xE9CF623E,normal=0x43FAEA4B,},                                            -- {albedo="mp_u_faov_moles_001_ab",normal="mp_u_faov_moles_001_nm",},
                    {id=0x9F9D8B72,albedo=0x27450B2F,normal=0x0808DBFB,},                                            -- {albedo="mp_u_faov_moles_002_ab",normal="mp_u_faov_moles_002_nm",},
                    {id=0xE7179A39,albedo=0x38638E0B,normal=0x99346057,},                                            -- {albedo="mp_u_faov_moles_003_ab",normal="mp_u_faov_moles_003_nm",},
                    {id=0xBB094249,albedo=0x763F8624,normal=0x6975D6F9,},                                            -- {albedo="mp_u_faov_moles_004_ab",normal="mp_u_faov_moles_004_nm",},
                    {id=0x03AC5362,albedo=0xEF158115,normal=0xBA297751,},                                            -- {albedo="mp_u_faov_moles_005_ab",normal="mp_u_faov_moles_005_nm",},
                    {id=0x154FF6A9,albedo=0xEE28E6F7,normal=0xB7548307,},                                            -- {albedo="mp_u_faov_moles_006_ab",normal="mp_u_faov_moles_006_nm",},
                    {id=0x1E23084F,albedo=0x566ACE2F,normal=0x361237C6,},                                            -- {albedo="mp_u_faov_moles_007_ab",normal="mp_u_faov_moles_007_nm",},
                    {id=0x31DBAFC0,albedo=0x0AB0CC2B,normal=0xDBF55701,},                                            -- {albedo="mp_u_faov_moles_008_ab",normal="mp_u_faov_moles_008_nm",},
                    {id=0x3AC5C194,albedo=0xC940CC25,normal=0x41CB48FC,},                                            -- {albedo="mp_u_faov_moles_009_ab",normal="mp_u_faov_moles_009_nm",},
                    {id=0x4500D516,albedo=0x3A1EEDB1,normal=0x17BC19B0,},                                            -- {albedo="mp_u_faov_moles_010_ab",normal="mp_u_faov_moles_010_nm",},
                    {id=0x3695B840,albedo=0x1D30222E,normal=0xDA5FDF7E,},                                            -- {albedo="mp_u_faov_moles_011_ab",normal="mp_u_faov_moles_011_nm",},
                    {id=0x286C1BED,albedo=0x4F0B4FA8,normal=0x40333534,},                                            -- {albedo="mp_u_faov_moles_012_ab",normal="mp_u_faov_moles_012_nm",},
                    {id=0x934BF1AF,albedo=0x4540A8D7,normal=0x933ACF76,},                                            -- {albedo="mp_u_faov_moles_013_ab",normal="mp_u_faov_moles_013_nm",},
                    {id=0x84F55502,albedo=0x47BE6D32,normal=0xDCF7108E,},                                            -- {albedo="mp_u_faov_moles_014_ab",normal="mp_u_faov_moles_014_nm",},
                    {id=0xBD9A464B,albedo=0x9DABB1B9,normal=0x4A3B1739,},                                            -- {albedo="mp_u_faov_moles_015_ab",normal="mp_u_faov_moles_015_nm",},
                },
    ["spots"] = {
                    {id=0x5BBFF5F7,albedo=0x24968425,normal=0xA5D532AD,},                                            -- {albedo="mp_u_faov_spots_000_ab",normal="mp_u_faov_spots_000_nm",},
                    {id=0x65EC0A4F,albedo=0x326A7845,normal=0xC09B2354,},                                            -- {albedo="mp_u_faov_spots_001_ab",normal="mp_u_faov_spots_001_nm",},
                    {id=0x3F143CA0,albedo=0x91D7E39E,normal=0xD607DF75,},                                            -- {albedo="mp_u_faov_spots_002_ab",normal="mp_u_faov_spots_002_nm",},
                    {id=0x49675146,albedo=0x2E6C3769,normal=0xE6A21CD5,},                                            -- {albedo="mp_u_faov_spots_003_ab",normal="mp_u_faov_spots_003_nm",},
                    {id=0x07504D2D,albedo=0x39F16CE6,normal=0x5CB32D5C,},                                            -- {albedo="mp_u_faov_spots_004_ab",normal="mp_u_faov_spots_004_nm",},
                    {id=0xF161214F,albedo=0x47C60FBA,normal=0x19424C77,},                                            -- {albedo="mp_u_faov_spots_005_ab",normal="mp_u_faov_spots_005_nm",},
                    {id=0xE43286F2,albedo=0xA7E86379,normal=0x7C07E0B0,},                                            -- {albedo="mp_u_faov_spots_006_ab",normal="mp_u_faov_spots_006_nm",},
                    {id=0xDDDC7A46,albedo=0x26D3DA64,normal=0x5A69A9BB,},                                            -- {albedo="mp_u_faov_spots_007_ab",normal="mp_u_faov_spots_007_nm",},
                    {id=0xD086DF9B,albedo=0x7D6FF58C,normal=0x5A0D99C8,},                                            -- {albedo="mp_u_faov_spots_008_ab",normal="mp_u_faov_spots_008_nm",},
                    {id=0xBA51B331,albedo=0xCB23CA55,normal=0xA7720C6A,},                                            -- {albedo="mp_u_faov_spots_009_ab",normal="mp_u_faov_spots_009_nm",},
                    {id=0xE4CF097B,albedo=0x51D0FBDA,normal=0xB01F5202,},                                            -- {albedo="mp_u_faov_spots_010_ab",normal="mp_u_faov_spots_010_nm",},
                    {id=0xF70CADF6,albedo=0xD0858DFC,normal=0x7E067837,},                                            -- {albedo="mp_u_faov_spots_011_ab",normal="mp_u_faov_spots_011_nm",},
                    {id=0xC07F40DC,albedo=0x3BAF1008,normal=0x75030E1B,},                                            -- {albedo="mp_u_faov_spots_012_ab",normal="mp_u_faov_spots_012_nm",},
                    {id=0xD3B1E741,albedo=0x97091388,normal=0xA191AA56,},                                            -- {albedo="mp_u_faov_spots_013_ab",normal="mp_u_faov_spots_013_nm",},
                    {id=0xB494A903,albedo=0x18025AE1,normal=0x86F51AD1,},                                            -- {albedo="mp_u_faov_spots_014_ab",normal="mp_u_faov_spots_014_nm",},
                    {id=0xC6EE4DB6,albedo=0xC9F3EBA4,normal=0xE819AD33,},                                            -- {albedo="mp_u_faov_spots_015_ab",normal="mp_u_faov_spots_015_nm",},
                },
}

color_palettes = {
    {0x3F6E70FF,},
    {0x0105607B,},
    {0x17CBCC83,},
    {0x29F81B2A,},
    {0x3385C5DB,},
    {0x37CD36D4,},
    {0x4101ED87,},
    {0x63838A81,},
    {0x6765BC15,},
    {0x8BA18876,},
    {0x9AC34F34,},
    {0x9E4803A0,},
    {0xA4041CEF,},
    {0xA4CFABD0,},
    {0xAA65D8A3,},
    {0xB562025C,},
    {0xB9E7F722,},
    {0xBBF43EF8,},
    {0xD1476963,},
    {0xD799E1C2,},
    {0xDC6BC93B,},
    {0xDFB1F64C,},
    {0xF509C745,},
    {0xF93DB0C8,},
    {0xFB71527B,},
}

texture_types = {
    Male = {
        albedo = joaat("mp_head_mr1_sc08_c0_000_ab"),
        normal = joaat("mp_head_mr1_000_nm"),
        material = 0x50A4BBA9,
        color_type = 1,
        texture_opacity = 1.0,
        unk_arg = 0,
    },
    Female = {
        albedo = joaat("mp_head_fr1_sc08_c0_000_ab"),
        normal = joaat("head_fr1_mp_002_nm"),
        material = 0x7FC5B1E1,
        color_type = 1,
        texture_opacity = 1.0,
        unk_arg = 0,
    }
}
current_texture_settings = texture_types["Male"]


overlay_all_layers = {
    {name="eyebrows",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,    },
    {name="scars",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },
    {name="scars2",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },
    {name="scars3",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },

    
    {name="eyeliners",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,   },
    {name="lipsticks",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,   },
    {name="acne",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,        },
    {name="shadows",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,     },
    {name="beardstabble",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,},
    {name="paintedmasks",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,},
    {name="ageing",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,      },
    {name="blush",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },
    {name="blush2",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },

    {name="complex",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,     },
    {name="disc",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,        },
    {name="foundation",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,  },
    {name="freckles",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,    },
    {name="grime",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },
    {name="hairstabble",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,        },
    {name="moles",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },
    {name="spots",visibility=0,tx_id=1,tx_normal=0,tx_material=0,tx_color_type=0,tx_opacity=1.0,tx_unk=0,palette=0,palette_color_primary=0,palette_color_secondary=0,palette_color_tertiary=0,var=0,opacity=1.0,       },
}

Citizen.CreateThread(function()
    baseoverlay = deepcopy(overlay_all_layers)
end)
end

-- ============================================================================
-- Module: appearance/dataview.lua
-- ============================================================================
do
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
----------------- 			DATAVIEW FUNCTIONS					-------------
-----------------										-------------
----------------- 		BIG THNKS to gottfriedleibniz for this DataView in LUA.		-------------
----------------- https://gist.github.com/gottfriedleibniz/8ff6e4f38f97dd43354a60f8494eedff	-------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------

local _strblob = string.blob or function(length)
    return string.rep("\0", math.max(40 + 1, length))
end

DataView = {
    EndBig = ">",
    EndLittle = "<",
    Types = {
        Int8 = { code = "i1", size = 1 },
        Uint8 = { code = "I1", size = 1 },
        Int16 = { code = "i2", size = 2 },
        Uint16 = { code = "I2", size = 2 },
        Int32 = { code = "i4", size = 4 },
        Uint32 = { code = "I4", size = 4 },
        Int64 = { code = "i8", size = 8 },
        Uint64 = { code = "I8", size = 8 },

        LuaInt = { code = "j", size = 8 }, 
        UluaInt = { code = "J", size = 8 }, 
        LuaNum = { code = "n", size = 8}, 
        Float32 = { code = "f", size = 4 },
        Float64 = { code = "d", size = 8 }, 
        String = { code = "z", size = -1, }, 
    },

    FixedTypes = {
        String = { code = "c", size = -1, },
        Int = { code = "i", size = -1, },
        Uint = { code = "I", size = -1, },
    },
}
DataView.__index = DataView
local function _ib(o, l, t) return ((t.size < 0 and true) or (o + (t.size - 1) <= l)) end
local function _ef(big) return (big and DataView.EndBig) or DataView.EndLittle end
local SetFixed = nil
function DataView.ArrayBuffer(length)
    return setmetatable({
        offset = 1, length = length, blob = _strblob(length)
    }, DataView)
end
function DataView.Wrap(blob)
    return setmetatable({
        offset = 1, blob = blob, length = blob:len(),
    }, DataView)
end
function DataView:Buffer() return self.blob end
function DataView:ByteLength() return self.length end
function DataView:ByteOffset() return self.offset end
function DataView:SubView(offset)
    return setmetatable({
        offset = offset, blob = self.blob, length = self.length,
    }, DataView)
end
for label,datatype in pairs(DataView.Types) do
    DataView["Get" .. label] = function(self, offset, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            local v,_ = string.unpack(_ef(endian) .. datatype.code, self.blob, o)
            return v
        end
        return nil
    end

    DataView["Set" .. label] = function(self, offset, value, endian)
        local o = self.offset + offset
        if _ib(o, self.length, datatype) then
            return SetFixed(self, o, value, _ef(endian) .. datatype.code)
        end
        return self
    end
    if datatype.size >= 0 and string.packsize(datatype.code) ~= datatype.size then
        local msg = "Pack size of %s (%d) does not match cached length: (%d)"
        error(msg:format(label, string.packsize(fmt[#fmt]), datatype.size))
        return nil
    end
end
for label,datatype in pairs(DataView.FixedTypes) do
    DataView["GetFixed" .. label] = function(self, offset, typelen, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            local v,_ = string.unpack(code, self.blob, o)
            return v
        end
        return nil
    end
    DataView["SetFixed" .. label] = function(self, offset, typelen, value, endian)
        local o = self.offset + offset
        if o + (typelen - 1) <= self.length then
            local code = _ef(endian) .. "c" .. tostring(typelen)
            return SetFixed(self, o, value, code)
        end
        return self
    end
end

SetFixed = function(self, offset, value, code)
    local fmt = { }
    local values = { }
    if self.offset < offset then
        local size = offset - self.offset
        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(self.offset, size)
    end
    fmt[#fmt + 1] = code
    values[#values + 1] = value
    local ps = string.packsize(fmt[#fmt])
    if (offset + ps) <= self.length then
        local newoff = offset + ps
        local size = self.length - newoff + 1

        fmt[#fmt + 1] = "c" .. tostring(size)
        values[#values + 1] = self.blob:sub(newoff, self.length)
    end
    self.blob = string.pack(table.concat(fmt, ""), table.unpack(values))
    self.length = self.blob:len()
    return self
end

DataStream = { }
DataStream.__index = DataStream

function DataStream.New(view)
    return setmetatable({ view = view, offset = 0, }, DataStream)
end

for label,datatype in pairs(DataView.Types) do
    DataStream[label] = function(self, endian, align)
        local o = self.offset + self.view.offset
        if not _ib(o, self.view.length, datatype) then
            return nil
        end
        local v,no = string.unpack(_ef(endian) .. datatype.code, self.view:Buffer(), o)
        if align then
            self.offset = self.offset + math.max(no - o, align)
        else
            self.offset = no - self.view.offset
        end
        return v
    end
end

------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------
----------------- 										------------
-----------------		END OF DATAVIEW FUNCTIONS					------------
----------------- 										------------
------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------
end

-- ============================================================================
-- Module: selector/decor.lua
-- ============================================================================
do
-- Build DecorSettings from CreatorConfig (for compatibility with existing code)
DecorSettings = {
    interior = CreatorConfig.CharSelect.interior,
    interior_sets = CreatorConfig.CharSelect.interior_sets,
    charselectcam = CreatorConfig.CharSelect.camera,
    pedslots = {}
}

-- Convert scenario strings to hashes
for k, v in pairs(CreatorConfig.CharSelect.pedslots) do
    DecorSettings.pedslots[k] = {
        coords = v.coords,
        heading = v.heading,
        scenario = v.scenario and GetHashKey(v.scenario) or nil,
        scenariopoint = v.scenariopoint and GetHashKey(v.scenariopoint) or nil
    }
end

Citizen.CreateThread(function()
    -- Load IMAPs
    if CreatorConfig.CharSelect.imaps then
        for _, imap in pairs(CreatorConfig.CharSelect.imaps) do
            RequestImap(GetHashKey(imap))
        end
    end
    
    -- Activate interior sets
    for k, v in pairs(DecorSettings.interior_sets) do
        if not IsInteriorEntitySetActive(DecorSettings.interior, v) then
            ActivateInteriorEntitySet(DecorSettings.interior, v)
        end
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        for k, v in pairs(DecorSettings.interior_sets) do
            if IsInteriorEntitySetActive(DecorSettings.interior, v) then
                DeactivateInteriorEntitySet(DecorSettings.interior, v, true)
            end
        end
    end
end)
end

-- ============================================================================
-- Module: appearance/utils.lua
-- ============================================================================
do
CachePed = PlayerPedId()
CachePedData = {}
CachePedData.expressions = {}

-- Exposes the cached facial expressions so jrs_clothing can restore them after an outfit change.
exports('GetCachedExpressions', function()
    return CachePedData.expressions
end)
CachePedData.gender = "Male"
CachePedData.pedmodel = { model = "mp_male", outfit = 0 }
CachePedData.skintone = 1
CachePedData.head = 1
CachePedData.teeth = 1
CachePedData.eyes = 1
CachePedData.body = 1
CachePedData.waist = 1
CachePedData.upperbody = 1
CachePedData.lowerbody = 1
CachePedData.height = 1.0
Citizen.CreateThread(function()
    DefaultCachePedData = deepcopy(CachePedData)
end)

hairstyleCache = {}

function scale(value, oldMin, oldMax, newMin, newMax)
    return (((value - oldMin) * (newMax - newMin)) / (oldMax - oldMin)) + newMin
end

function CreatePed_2(modelHash, x, y, z, heading, isNetwork, thisScriptCheck, p7, p8)
    return Citizen.InvokeNative(0xD49F9B0955C367DE, modelHash, x, y, z, heading, isNetwork, thisScriptCheck, p7, p8)
end

function PlaySound(action, soundset)
    PlaySoundFrontend(action, soundset, true, 0)
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function NPCAssetsToPed(model, outfit, target)
    local ped = target or CachePed
    local data = {}
    local gender
    local attempt = 0
    if model then
        repeat
            RequestModel(GetHashKey(model))
            local npcModelDeadline = GetGameTimer() + 8000
            while not HasModelLoaded(GetHashKey(model)) and GetGameTimer() < npcModelDeadline do
                Wait(1)
            end
            if not HasModelLoaded(GetHashKey(model)) then
                CreatorDebug("^3[jrs_character] NPCAssetsToPed: NPC model failed to stream within 8s, continuing.^7")
            end
            local pos = GetEntityCoords(ped)
            local entity = CreatePed_2(GetHashKey(model), pos.x, pos.y, pos.z - 10.0, 0.0, false, true)
            local npcPedDeadline = GetGameTimer() + 5000
            repeat
                Wait(1)
            until DoesEntityExist(entity) or GetGameTimer() >= npcPedDeadline
            if not DoesEntityExist(entity) then
                CreatorDebug("^3[jrs_character] NPCAssetsToPed: template ped never spawned within 5s, aborting this attempt.^7")
                attempt = attempt + 1
                goto npc_attempt_continue
            end
            if IsPedMale(entity) then gender = "male" else gender = "female" end
            Wait(10)
            EquipMetaPedOutfitPreset(entity, tonumber(outfit), false)
            Wait(10)
            for index = 0, 100 do
                local drawable, albedo, normal, material = GetMetaPedAssetGuids(entity, index)

                local assetDeadline = GetGameTimer() + 1000
                repeat
                    drawable, albedo, normal, material = GetMetaPedAssetGuids(entity, index)
                until (drawable ~= nil and albedo ~= nil and normal ~= nil and material ~= nil) or GetGameTimer() >= assetDeadline
                if drawable and drawable ~= 0 then
                    local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(entity, index)
                    local tintDeadline = GetGameTimer() + 1000
                    repeat
                        palette, tint0, tint1, tint2 = GetMetaPedAssetTint(entity, index)
                    until (palette ~= nil and tint0 ~= nil and tint1 ~= nil and tint2 ~= nil) or GetGameTimer() >= tintDeadline
                    data[index] = {
                        drawable = drawable,
                        albedo = albedo,
                        normal = normal,
                        material = material,
                        palette =
                            palette,
                        tint0 = tint0,
                        tint1 = tint1,
                        tint2 = tint2
                    }
                end
            end
            DeletePed(entity)
            attempt = attempt + 1
            ::npc_attempt_continue::
        until
            #data > 0 or attempt > 15
        local playermodel = GetHashKey("mp_" .. gender)
        RequestModel(playermodel)
        local playerModelDeadline = GetGameTimer() + 8000
        while not HasModelLoaded(playermodel) and GetGameTimer() < playerModelDeadline do Wait(100) end
        if not HasModelLoaded(playermodel) then
            CreatorDebug("^3[jrs_character] NPCAssetsToPed: mp_" .. tostring(gender) .. " model failed to stream within 8s, continuing.^7")
        end
        JRSSafeSetPlayerModel(playermodel)
        ped = PlayerPedId()
        CachePed = ped
        Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
        NativeUpdatePedVariation(ped)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, joaat("ammo_pistols"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, joaat("pants"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, joaat("bodies_upper"), 0)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, joaat("bodies_lower"), 0)
        NativeUpdatePedVariation(ped)
        SetModelAsNoLongerNeeded(playermodel)
        for k, v in pairs(data) do
            UpdateCustomClothes(ped, v.drawable, v.albedo, v.normal, v.material, v.palette, v.tint0, v.tint1, v.tint2)
        end
        local toremove = { "hats", "eyewear" }
        local catgender = "Female"
        if gender == "male" then catgender = "Male" end
        for _, tagName in pairs(catlist[catgender]) do
            local hash = joaat(tagName)
            if IsMetaPedUsingComponentCategory(ped, hash) then
                for _, essential in ipairs(toremove) do
                    if hash == GetHashFromString(essential) then
                        Citizen.InvokeNative(0xD710A5007C2AC539, ped, hash, 0)
                        break
                    end
                end
            end
        end
        UpdatePedVariation(ped)
        RemoveHairsAndBeards(ped)
    end
    return true
end

function GetHead(ped)
    local numComponents = GetNumComponentsInPed(ped)
    for i = 0, numComponents - 1, 1 do
        local componentCategory = GetCategoryOfComponentAtIndex(ped, i)
        if componentCategory == `heads` then
            local shopitem = GetShopItemComponentAtIndex(ped, i, true)
            return shopitem
        end
    end
end

function GetMetaPedData(category, ped)
    local playerPed = ped or PlayerPedId()
    local componentIndex = GetComponentIndexByCategory(playerPed, category)
    if not componentIndex then
        return nil
    end
    local drawable, albedo, normal, material = GetMetaPedAssetGuids(playerPed, componentIndex)
    local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(playerPed, componentIndex)

    return {
        drawable = drawable,
        albedo = albedo,
        normal = normal,
        material = material,
        palette = palette,
        tint0 = tint0,
        tint1 =
            tint1,
        tint2 = tint2
    }
end

function GetHashFromString(value)
    if type(value) == "string" then
        local number = tonumber(value)
        if number then return number end
        return joaat(value)
    end
    return value
end

function GetCategoriesEquiped(ped)
    local equiped = {}
    local numComponent = GetNumComponentsInPed(ped) or 0
    for index = 0, numComponent - 1 do
        --Get current component
        local category = GetCategoryOfComponentAtIndex(ped, index)
        equiped[category] = {
            index = index,
        }
        if category == `neckwear` then
            equiped[`neckerchiefs`] = equiped[category]
            equiped[`neckerchiefs`].category = "neckerchiefs"
        elseif category == `neckerchiefs` then
            equiped[`neckwear`] = equiped[category]
            equiped[`neckwear`].category = "neckwear"
        end
    end
    --clear cached value
    local component = equiped
    return component
end

function ApplyCachePedDataToPedPlayer()
    -- Prevent crash when clicking too fast before data is loaded
    if not CachePedData or not CachePedData.pedmodel or not CachePedData.pedmodel.model then
        CreatorDebug("[jrs_character_creator] Warning: CachePedData not loaded yet, retrying...")
        Wait(500)
        if not CachePedData or not CachePedData.pedmodel or not CachePedData.pedmodel.model then
            CreatorDebug("[jrs_character_creator] Error: CachePedData still not loaded, aborting")
            return
        end
    end
    
    local model = CachePedData.pedmodel.model
    local outfit = CachePedData.pedmodel.outfit
    local ped = CachePed
    if model == "mp_male" or model == "mp_female" then
        local currentPed = PlayerPedId()
        local currentModel = GetEntityModel(currentPed)
        local modelHash = joaat and joaat(model) or GetHashKey(model)
        local fallbackHash = GetHashKey(model)

        -- Only change model if player ped is not already this model
        if currentModel ~= modelHash and currentModel ~= fallbackHash then
            local loaded = RequestPlayerModelSafely(modelHash, 30000, 'creator')
            if not loaded then
                return false
            else
                if not JRSSafeSetPlayerModel(modelHash) then
                    CreatorDebug("^1[jrs_character] SetPlayerModel skipped (crash guard)^7")
                    return false
                else
                    Wait(100)
                    local appliedModel = GetEntityModel(PlayerPedId())
                    if appliedModel ~= modelHash and appliedModel ~= fallbackHash then return false end
                end
            end
        else
            CreatorDebug(("^2[jrs_character] Ped model already matches %s - skipping model recreation^7"):format(tostring(model)))
        end
        CachePed = PlayerPedId()

        if not have_character and CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.playerSpawn then
            local sp = CreatorConfig.CharSelect.playerSpawn
            local spCoords = sp.coords
            local cx = tonumber(spCoords and (spCoords.x or spCoords[1])) or -2785.515
            local cy = tonumber(spCoords and (spCoords.y or spCoords[2])) or -3058.224
            local cz = tonumber(spCoords and (spCoords.z or spCoords[3])) or -12.34043
            local ch = tonumber(sp.heading) or 349.0
            SetEntityCoordsNoOffset(CachePed, cx, cy, cz, false, false, false)
            SetEntityHeading(CachePed, ch)
            FreezeEntityPosition(CachePed, true)
            SetEntityCollision(CachePed, true, true)
            SetEntityVisible(CachePed, true, false)
            if type(ResetEntityAlpha) == 'function' then ResetEntityAlpha(CachePed) end
            SetPlayerInvincible(PlayerId(), true)
            JRSSafeNetworkConceal(false)
        end

        if model == "mp_female" then
            Citizen.InvokeNative(0x77FF8D35EEC6BBC4, CachePed, 2, false)    -- EquipMetaPedOutfitPreset avec preset 2
            local femaleReadyDeadline = GetGameTimer() + 5000
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, CachePed) and GetGameTimer() < femaleReadyDeadline do
                Wait(0)
            end
            Citizen.InvokeNative(0x0BFA1BD465CDFEFD, CachePed)                                 -- ResetPedComponents
            Citizen.InvokeNative(0xAAB86462966168CE, CachePed, true)                           -- Fixes outfit
            Citizen.InvokeNative(0xCC8CA3E88256E58F, CachePed, false, true, true, true, false) -- UpdatePedVariation
        else
            Citizen.InvokeNative(0x77FF8D35EEC6BBC4, CachePed, 0, false)                       -- EquipMetaPedOutfitPreset avec preset 0
            local maleReadyDeadline = GetGameTimer() + 5000
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, CachePed) and GetGameTimer() < maleReadyDeadline do
                Wait(0)
            end
        end

        local genderNorm  = (CachePedData.gender == "Female" or CachePedData.gender == "female") and "Female" or "Male"
        local genderSets  = DefaultChar and DefaultChar[genderNorm]
        local SkinColor   = genderSets and (genderSets[CachePedData.skintone] or genderSets[1]) or nil
        if not SkinColor then return end

        local headIndex   = tonumber(CachePedData.head) or 1
        local headHex     = (SkinColor.Heads and SkinColor.Heads[headIndex] and SkinColor.Heads[headIndex] ~= "") and SkinColor.Heads[headIndex] or (SkinColor.Heads and SkinColor.Heads[1])
        local heads       = headHex and tonumber("0x" .. headHex) or nil

        local bodyIndex   = tonumber(CachePedData.upperbody)
        local bodyHex     = (bodyIndex and bodyIndex > 0 and SkinColor.Body and SkinColor.Body[bodyIndex] and SkinColor.Body[bodyIndex] ~= "") and SkinColor.Body[bodyIndex] or (bodyIndex ~= 0 and SkinColor.Body and SkinColor.Body[1])
        local bodyType    = bodyHex and tonumber("0x" .. bodyHex) or nil

        local legsIndex   = tonumber(CachePedData.lowerbody)
        local legsHex     = (legsIndex and legsIndex > 0 and SkinColor.Legs and SkinColor.Legs[legsIndex] and SkinColor.Legs[legsIndex] ~= "") and SkinColor.Legs[legsIndex] or (legsIndex ~= 0 and SkinColor.Legs and SkinColor.Legs[1])
        local legs        = legsHex and tonumber("0x" .. legsHex) or nil

        local headtexture = SkinColor.HeadTexture and SkinColor.HeadTexture[1] and joaat(SkinColor.HeadTexture[1]) or nil
        local albedo      = texture_types and texture_types[genderNorm] and texture_types[genderNorm].albedo
        IsPedReadyToRender(CachePed)
        RemoveAllClothesExceptEssentials(CachePed)
        if heads then
            ApplyShopItemToPed(heads, CachePed)
            NativeSetPedComponentEnabled(CachePed, heads, false, true)
        end
        if bodyIndex == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x0B3966C9, 0)
        elseif bodyType then
            ApplyShopItemToPed(bodyType, CachePed)
        end
        if legsIndex == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x823687F5, 0)
        elseif legs then
            ApplyShopItemToPed(legs, CachePed)
        end
        if albedo and headtexture then
            Citizen.InvokeNative(0xC5E7204F322E49EB, albedo, headtexture, 0x7FC5B1E1)
        end
        UpdatePedVariation(CachePed)
        if heads then
            ApplyShopItemToPed(heads, CachePed)
            NativeSetPedComponentEnabled(CachePed, heads, false, true)
        end
        if CachePedData.lowerbody and CachePedData.lowerbody > 0 then
            local comp = DefaultChar[genderNorm][CachePedData.skintone].Legs[CachePedData.lowerbody]
            if comp then
                ApplyShopItemToPed(tonumber("0x" .. comp), CachePed)
                TriggerEvent("jrs_clothes:Loadlowerbody", tonumber("0x" .. comp))
            end
        elseif CachePedData.lowerbody == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x823687F5, 0)
            TriggerEvent("jrs_clothes:Loadlowerbody", 0)
        end
        if CachePedData.upperbody and CachePedData.upperbody > 0 then
            local comp = DefaultChar[genderNorm][CachePedData.skintone].Body[CachePedData.upperbody]
            if comp then
                ApplyShopItemToPed(tonumber("0x" .. comp), CachePed)
                TriggerEvent("jrs_clothes:Loadupperbody", tonumber("0x" .. comp))
            end
        elseif CachePedData.upperbody == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x0B3966C9, 0)
            TriggerEvent("jrs_clothes:Loadupperbody", 0)
        end
        if CachePedData.body > 0 then
            local comp = tonumber(Body[CachePedData.body])
            EquipMetaPedOutfit(comp, CachePed)
        end
        if CachePedData.waist > 0 then
            local comp = tonumber(Waist[CachePedData.waist])
            EquipMetaPedOutfit(comp, CachePed)
        end
        if CachePedData.body > 0 or CachePedData.waist > 0 then
            if heads then
                ApplyShopItemToPed(heads, CachePed)
                NativeSetPedComponentEnabled(CachePed, heads, false, true)
            end
            ApplyShopItemToPed(bodyType, CachePed)
            ApplyShopItemToPed(legs, CachePed)
            Citizen.InvokeNative(0x59BD177A1A48600A, CachePed, 1)
            UpdatePedVariation(CachePed)
        end
        TriggerEvent("jrs_clothes:LoadBasSkin")
        -- Deprioritizing the base model before its own component variations
        -- finish streaming can leave some parts unresolved under streamer
        -- pressure, so this must wait until every variation call above is done.
        SetModelAsNoLongerNeeded(modelHash)
    else
        NPCAssetsToPed(model, outfit)
        IsPedReadyToRender(CachePed)
    end


    if CachePedData.teeth > 0 then
        ApplyShopItemToPed(Teeth[CachePedData.gender][CachePedData.teeth].hash, CachePed)
    end

    if CachePedData.eyes > 0 then
        ApplyShopItemToPed(Eyes[CachePedData.gender][CachePedData.eyes], CachePed)
    end

    if type(ApplyCharacterExpressions) == "function" then
        ApplyCharacterExpressions(CachePed, CachePedData.expressions)
    elseif type(CachePedData.expressions) == "table" and ExpressionsHashes then
        for k, v in pairs(CachePedData.expressions) do
            if ExpressionsHashes[k] then
                SetCharExpression(CachePed, ExpressionsHashes[k], v)
            end
        end
    end
    return true
end

EssentialsCategories = { -- Categories that will not be removed when changing clothes, and not be saved when creating an outfit
    "bodies_upper",
    "bodies_lower",
    "heads",
    "hair",
    "hair_bonnet",
    "beard",
    "teeth",
    "eyes",
    "beards_chin",
    "beards_chops",
    "beards_mustache",
    "beards_complete",
}


function RemoveHairsAndBeards(ped)
    local toremove = {
        "hair",
        "hair_bonnet",
        "beard",
        "beards_chin",
        "beards_chops",
        "beards_mustache",
        "beards_complete",
    }


    IsPedReadyToRender(ped)
    for _, value in ipairs(toremove) do
        local hash = GetHashFromString(value)
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, hash, 0)
    end

    UpdatePedVariation(ped)
end

function RemoveAllClothesExceptEssentials(ped, npc)
    local targetPed = ped or CachePed or PlayerPedId()
    if not targetPed or not DoesEntityExist(targetPed) then return end

    local essentials = EssentialsCategories or {}

    local genderNorm = "Male"
    if CachePedData and (CachePedData.gender == "Female" or CachePedData.gender == "female") then
        genderNorm = "Female"
    elseif CachePedData and (CachePedData.gender == "Male" or CachePedData.gender == "male") then
        genderNorm = "Male"
    elseif GetEntityModel(targetPed) == GetHashKey("mp_female") then
        genderNorm = "Female"
    end

    local categories = (catlist and (catlist[genderNorm] or catlist[genderNorm:lower()])) or (catlist and catlist.Male) or {}
    for _, tagName in pairs(categories) do
        local isEssential = false
        local hash = joaat(tagName)
        if IsMetaPedUsingComponentCategory(targetPed, hash) then
            for _, essential in ipairs(essentials) do
                if hash == GetHashFromString(essential) then
                    isEssential = true
                    break
                end
            end

            if not isEssential then
                Citizen.InvokeNative(0xD710A5007C2AC539, targetPed, hash, 0)
            end
        end
    end
    if not npc then
        local skintone = CachePedData and tonumber(CachePedData.skintone) or 1
        local skinSet = DefaultChar and (DefaultChar[genderNorm] or DefaultChar[genderNorm:lower()])
        skinSet = skinSet and skinSet[skintone]
        if skinSet then
            IsPedReadyToRender(targetPed)
            local lowerIndex = CachePedData and tonumber(CachePedData.lowerbody)
            if lowerIndex == 0 then
                Citizen.InvokeNative(0xD710A5007C2AC539, targetPed, 0x823687F5, 0)
            elseif lowerIndex and skinSet.Legs and skinSet.Legs[lowerIndex] then
                ApplyShopItemToPed(tonumber("0x" .. skinSet.Legs[lowerIndex]), targetPed)
            end

            local upperIndex = CachePedData and tonumber(CachePedData.upperbody)
            if upperIndex == 0 then
                Citizen.InvokeNative(0xD710A5007C2AC539, targetPed, 0x0B3966C9, 0)
            elseif upperIndex and skinSet.Body and skinSet.Body[upperIndex] then
                ApplyShopItemToPed(tonumber("0x" .. skinSet.Body[upperIndex]), targetPed)
            end
            UpdatePedVariation(targetPed)
        end
    end

    NativeUpdatePedVariation(targetPed)
end

function RemoveTagFromMetaPed(hash, ped)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped or PlayerPedId(), hash, 0)
end

function ApplyCachePedDataToPed(ped, data, charid)
    local model = data.pedmodel.model
    local outfit = data.pedmodel.outfit
    if model == "mp_male" or model == "mp_female" then
        if model == "mp_female" then
            Citizen.InvokeNative(0x77FF8D35EEC6BBC4, ped, 2, false)    -- EquipMetaPedOutfitPreset avec preset 2
            local femaleReadyDeadline = GetGameTimer() + 5000
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and GetGameTimer() < femaleReadyDeadline do
                Wait(0)
            end
            Citizen.InvokeNative(0x0BFA1BD465CDFEFD, ped)                                 -- ResetPedComponents
            Citizen.InvokeNative(0xAAB86462966168CE, ped, true)                           -- Fixes outfit
            Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false) -- UpdatePedVariation
        else
            Citizen.InvokeNative(0x77FF8D35EEC6BBC4, ped, 0, false)                       -- EquipMetaPedOutfitPreset avec preset 0
            local maleReadyDeadline = GetGameTimer() + 5000
            while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and GetGameTimer() < maleReadyDeadline do
                Wait(0)
            end
        end

        local genderNorm  = (data.gender == "Female" or data.gender == "female") and "Female" or "Male"
        local genderSets  = DefaultChar and DefaultChar[genderNorm]
        local SkinColor   = genderSets and (genderSets[data.skintone] or genderSets[1]) or nil
        if not SkinColor then return end

        local headIndex   = tonumber(data.head) or 1
        local headHex     = (SkinColor.Heads and SkinColor.Heads[headIndex] and SkinColor.Heads[headIndex] ~= "") and SkinColor.Heads[headIndex] or (SkinColor.Heads and SkinColor.Heads[1])
        local heads       = headHex and tonumber("0x" .. headHex) or nil

        local bodyIndex   = tonumber(data.upperbody)
        local bodyHex     = (bodyIndex and bodyIndex > 0 and SkinColor.Body and SkinColor.Body[bodyIndex] and SkinColor.Body[bodyIndex] ~= "") and SkinColor.Body[bodyIndex] or (bodyIndex ~= 0 and SkinColor.Body and SkinColor.Body[1])
        local bodyType    = bodyHex and tonumber("0x" .. bodyHex) or nil

        local legsIndex   = tonumber(data.lowerbody)
        local legsHex     = (legsIndex and legsIndex > 0 and SkinColor.Legs and SkinColor.Legs[legsIndex] and SkinColor.Legs[legsIndex] ~= "") and SkinColor.Legs[legsIndex] or (legsIndex ~= 0 and SkinColor.Legs and SkinColor.Legs[1])
        local legs        = legsHex and tonumber("0x" .. legsHex) or nil

        local headtexture = SkinColor.HeadTexture and SkinColor.HeadTexture[1] and joaat(SkinColor.HeadTexture[1]) or nil
        local albedo      = texture_types and texture_types[genderNorm] and texture_types[genderNorm].albedo
        IsPedReadyToRender(ped)
        RemoveAllClothesExceptEssentials(ped)
        if heads then
            ApplyShopItemToPed(heads, ped)
            NativeSetPedComponentEnabled(ped, heads, false, true)
        end
        if bodyIndex == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0B3966C9, 0)
        elseif bodyType then
            ApplyShopItemToPed(bodyType, ped)
        end
        if legsIndex == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x823687F5, 0)
        elseif legs then
            ApplyShopItemToPed(legs, ped)
        end
        if albedo and headtexture then
            Citizen.InvokeNative(0xC5E7204F322E49EB, albedo, headtexture, 0x7FC5B1E1)
        end
        UpdatePedVariation(ped)
        if heads then
            ApplyShopItemToPed(heads, ped)
            NativeSetPedComponentEnabled(ped, heads, false, true)
        end
        if data.lowerbody and data.lowerbody > 0 then
            local comp = DefaultChar[genderNorm][data.skintone].Legs
                [data.lowerbody]
            ApplyShopItemToPed(tonumber("0x" .. comp), ped)
        elseif data.lowerbody == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x823687F5, 0)
        end
        if data.upperbody and data.upperbody > 0 then
            local comp = DefaultChar[genderNorm][data.skintone].Body
                [data.upperbody]
            ApplyShopItemToPed(tonumber("0x" .. comp), ped)
        elseif data.upperbody == 0 then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0B3966C9, 0)
        end
        if data.body > 0 then
            local comp = tonumber(Body[data.body])
            EquipMetaPedOutfit(comp, ped)
        end
        if data.waist > 0 then
            local comp = tonumber(Waist[data.waist])
            EquipMetaPedOutfit(comp, ped)
        end
        if data.body > 0 or data.waist > 0 then
            if heads then
                ApplyShopItemToPed(heads, ped)
                NativeSetPedComponentEnabled(ped, heads, false, true)
            end
            ApplyShopItemToPed(bodyType, ped)
            ApplyShopItemToPed(legs, ped)
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, 1)
            UpdatePedVariation(ped)
        end
    end


    if data.teeth > 0 then
        ApplyShopItemToPed(Teeth[data.gender][data.teeth].hash, ped)
    end

    if data.eyes > 0 then
        ApplyShopItemToPed(Eyes[data.gender][data.eyes], ped)
    end
    IsPedReadyToRender(ped)
    for k, v in pairs(data.expressions) do
        SetCharExpression(ped, ExpressionsHashes[k], v)
    end
    -- Selector clothing and barber data are applied synchronously by the
    -- selector after this base body has been cloned. Do not start asynchronous
    -- resource callbacks here; they race against ClonePed and produce bald or
    -- partially dressed preview characters.
    UpdatePedVariation(ped)
end

function OpenClothesMenu()
    if not baseHeading then
        baseHeading = GetEntityHeading(PlayerPedId())
        angleOffset = 180 - baseHeading
    end
    OpenCreatorClothingMenu()
end

-- fixing scale network issue
CreateThread(function()
    repeat Wait(2000) until LocalPlayer.state
    while false do
        local dead = IsEntityDead(PlayerPedId())
        if CachePedData.height ~= 1.0 then
            if not dead then
                SetPedScale(PlayerPedId(), CachePedData.height)
            end
        end
        Wait(1000)
    end
end)

function bigInt(text)
    local string1 = DataView.ArrayBuffer(16)
    string1:SetInt64(0, text)
    return string1:GetInt64(0)
end

ShowAdvancedRightNotification = function(_text, _dict, icon, text_color, duration, quality)
    -- jrs_core is the only renderer on this server. Route through its own
    -- client-side event instead of the raw RDR2 native feed (a second renderer).
    if GetResourceState('jrs_core') == 'started' then
        local ok, rendered = pcall(function()
            return exports.jrs_core:Toast(tostring(_text or ''), 'reward', duration, 'CHARACTER')
        end)
        if ok and rendered == true then return end
    end

    TriggerEvent('jrs_core:sendRightTipNotification', tostring(_text or ''), tonumber(duration) or 3500)
end
end

-- ============================================================================
-- Module: appearance/camera.lua
-- ============================================================================
do
ActiveCam = 0
currentCamDestionation = ""
camCoords = {}
baseHeading = false
rotatePedIndex = 0
ActualCamera = nil

function getCreatorActiveCamera()
    if ActiveCam == 1 and Cam1 and DoesCamExist(Cam1) then return Cam1 end
    if ActiveCam == 2 and Cam2 and DoesCamExist(Cam2) then return Cam2 end
    if ActualCamera and DoesCamExist(ActualCamera) then return ActualCamera end
    return nil
end

local DEFAULT_CREATOR_LATERAL_RATIO = 0.065
-- Global on purpose: creatorViewControl (pan buttons) lives in another
-- module's do-block and can't see a local declared here.
creatorViewPanRatio = 0.0
local creatorCurrentRawCamCoords = nil
local creatorCurrentRawCamTarget = nil

function ApplyCreatorCameraLateralOffset(rawCoords, rawTarget)
    if not rawCoords or not rawTarget then return rawCoords, rawTarget end
    if currentCamDestionation == "charselect" or currentCamDestionation == "selected" or currentCamDestionation == "base" then
        return rawCoords, rawTarget
    end
    local fwd = rawTarget - rawCoords
    local fwdLen = math.sqrt(fwd.x * fwd.x + fwd.y * fwd.y)
    if fwdLen < 0.001 then return rawCoords, rawTarget end
    local dist = #(rawCoords - rawTarget)
    local totalRatio = DEFAULT_CREATOR_LATERAL_RATIO + creatorViewPanRatio
    local lateralDist = dist * totalRatio
    local ux = fwd.x / fwdLen
    local uy = fwd.y / fwdLen
    -- Camera's left vector in horizontal plane is (-uy, ux, 0).
    -- Shifting camera and target along the left vector moves the character to screen RIGHT.
    local shiftX = -uy * lateralDist
    local shiftY = ux * lateralDist
    local newCoords = vector3(rawCoords.x + shiftX, rawCoords.y + shiftY, rawCoords.z)
    local newTarget = vector3(rawTarget.x + shiftX, rawTarget.y + shiftY, rawTarget.z)
    return newCoords, newTarget
end

function UpdateCreatorActiveCameraPosition()
    local cam = getCreatorActiveCamera()
    if not cam or not creatorCurrentRawCamCoords or not creatorCurrentRawCamTarget then return end
    local coords, target = ApplyCreatorCameraLateralOffset(creatorCurrentRawCamCoords, creatorCurrentRawCamTarget)
    SetCamCoord(cam, coords)
    PointCamAtCoord(cam, target)
end

function MoveCam(destination, data, tpcam, target)
	local ped = tonumber(target) or CachePed or PlayerPedId()
	if ped == nil or ped == 0 or not DoesEntityExist(ped) then
		ped = PlayerPedId()
	end
	if destination == currentCamDestionation then return end
	currentCamDestionation = destination
	if not camCoords[ped] then
		camCoords[ped] = {}
		camCoords[ped].default = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.0, 0.3),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0),
			fov = 30.0,
		}
		camCoords[ped].edit = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.0, 0.3),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0),
			fov = 30.0,
		}
		camCoords[ped].Body = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.0, 0.5),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.3),
			fov = 30.0
		}
		camCoords[ped].head = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.55, 0.70),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.68),
			fov = 32.0
		}
		camCoords[ped].selected = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.7, 0.65),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.65),
			fov = 40.0
		}
		camCoords[ped].eyesandbrows = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.65),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.65),
			fov = 30.0
		}
		camCoords[ped].facial = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.65),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.65),
			fov = 30.0
		}
		camCoords[ped].mouth = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.65),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.65),
			fov = 30.0
		}
		camCoords[ped].upperbody = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.2),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.2),
			fov = 30.0
		}
		camCoords[ped].lowerbody = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, -0.4),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.4),
			fov = 30.0
		}
		camCoords[ped].waist = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.75, -0.05),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.05),
			fov = 28.0
		}
		camCoords[ped].feet = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, -0.82),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, -0.82),
			fov = 27.0
		}
		camCoords[ped].hands = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.8, 0.0),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0),
			fov = 31.0
		}
	end
	local coords, target, fov
	if destination == "head" or destination == "hair" or destination == "beard"
		or destination == "eyesandbrows" or destination == "facial" or destination == "mouth" then
		local headBone = 21030
		local pedCoords = GetEntityCoords(ped)
		local headCoords = GetPedBoneCoords(ped, headBone, 0.0, 0.0, 0.0)
		local headOffsetZ = headCoords.z - pedCoords.z
		local targetOffset = 0.0
		local cameraDistance = 0.95
		local fovValue = 29.0

		if destination == "hair" then
			targetOffset = 0.02
			cameraDistance = 0.95
			fovValue = 29.0
		elseif destination == "beard" then
			targetOffset = -0.02
			cameraDistance = 0.95
			fovValue = 29.0
		elseif destination == "eyesandbrows" then
			targetOffset = 0.055
			cameraDistance = 0.82
			fovValue = 24.0
		elseif destination == "mouth" then
			targetOffset = -0.065
			cameraDistance = 0.82
			fovValue = 24.0
		elseif destination == "facial" then
			targetOffset = 0.0
			cameraDistance = 0.90
			fovValue = 26.0
		end

		camCoords[ped][destination] = {
			coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, cameraDistance, headOffsetZ + targetOffset),
			target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, headOffsetZ + targetOffset),
			fov = fovValue
		}
	end
	if not camCoords[ped][destination] then
		if not data then
			coords = camCoords[ped].default.coords
			target = camCoords[ped].default.target
			fov = camCoords[ped].default.fov
		else
			coords = data.coords
			target = data.target
			fov = data.fov
		end
	else
		coords = camCoords[ped][destination].coords
		target = camCoords[ped][destination].target
		fov = camCoords[ped][destination].fov
	end
	creatorCurrentRawCamCoords = coords
	creatorCurrentRawCamTarget = target
	coords, target = ApplyCreatorCameraLateralOffset(coords, target)
	CamFov = fov
	BaseCamFov = fov
	creatorViewFov = fov
	if ActiveCam == 0 then
		Cam1 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true);
		SetCamCoord(Cam1, coords)
		PointCamAtCoord(Cam1, target)
		SetCamActive(Cam1, true);
		if not tpcam then
			RenderScriptCams(true, true, 1000, true, true)
		else
			RenderScriptCams(true, false, 0, true, true)
		end
		SetCamFov(Cam1, fov)
		SetCamFocusDistance(Cam1, #(GetCamCoord(Cam1) - GetEntityCoords(ped)))
		ActualCamera = Cam1
		ActiveCam = 1
	else
		if not DoesCamExist(Cam2) then
			Cam2 = CreateCam("DEFAULT_SCRIPTED_CAMERA", true);
		end
		local from, to = 0, 0
		if ActiveCam == 1 then
			from = Cam1
			to = Cam2
			ActiveCam = 2
		else
			from = Cam2
			to = Cam1
			ActiveCam = 1
		end
		SetCamCoord(to, coords)
		PointCamAtCoord(to, target)
		SetCamFov(to, fov)
		if not tpcam then
			SetCamActiveWithInterp(to, from, 1000, true, true)
		else
			SetCamActive(to, true);
		end
		-- Wait(1000)
		SetCamFocusDistance(to, #(GetCamCoord(to) - GetEntityCoords(ped)))
		ActualCamera = to
	end
end

function SwitchOffCam(ease)
	if ease then
		RenderScriptCams(false, true, 2000, true, true)
	else
		RenderScriptCams(false, false, 0, true, true)
	end
	if DoesCamExist(Cam1) then DestroyCam(Cam1) end
	if DoesCamExist(Cam2) then DestroyCam(Cam2) end
	ActiveCam = 0
	ActualCamera = nil
	currentCamDestionation = ""
	camCoords = {}
	baseHeading = false
	rotatePedIndex = 0
	creatorCurrentRawCamCoords = nil
	creatorCurrentRawCamTarget = nil
	creatorViewPanRatio = 0.0
end

function CameraZoom(sens)
	if sens then
		CamFov = CamFov - 0.5
	else
		CamFov = CamFov + 0.5
	end
	if ActiveCam == 1 then
		SetCamFov(Cam1, CamFov)
	else
		SetCamFov(Cam2, CamFov)
	end
end

lamp = nil
lamp2 = nil
CreatorLight = false

-- Direct dynamic studio lighting on the player ped every tick.
-- Illuminates the entire character clearly: upper body/face, lower body/legs/boots, and ambient fill.
local function drawPlayerPetsStyleLight(ped)
	if not ped or ped == 0 or not DoesEntityExist(ped) then return end
	local cfg = (CreatorConfig and CreatorConfig.Lighting) or {}
	if cfg.enabled == false then return end

	local color = cfg.color or { r = 255, g = 248, b = 240 }
	local r = tonumber(color.r) or 255
	local g = tonumber(color.g) or 248
	local b = tonumber(color.b) or 240
	local intensity = tonumber(cfg.intensity) or 7.5
	local frontIntensity = tonumber(cfg.frontIntensity) or 6.5
	local lowerIntensity = tonumber(cfg.lowerIntensity) or 5.5
	local range = tonumber(cfg.range) or 6.5
	local heightOffset = tonumber(cfg.heightOffset) or 0.85
	local frontOffset = tonumber(cfg.frontOffset) or 0.9

	local coords = GetEntityCoords(ped)

	-- 1. Main ambient studio fill light on player
	if intensity and intensity > 0.0 then
		if type(DrawLightWithRange) == "function" then
			DrawLightWithRange(coords.x, coords.y, coords.z + heightOffset, r, g, b, range, intensity)
		elseif type(DrawSpotLight) == "function" then
			DrawSpotLight(coords.x, coords.y, coords.z + heightOffset + 1.2, 0.0, 0.0, -1.0, r, g, b, range + 1.0, intensity, 8.0, range, 1.0)
		else
			Citizen.InvokeNative(0xD2D9E04C0DF927F4, coords.x, coords.y, coords.z + heightOffset, r, g, b, range, intensity)
		end
	end

	-- 2. Direct front key light: illuminates face, hat, chest, coat, and hands
	if frontIntensity and frontIntensity > 0.0 and frontOffset and frontOffset > 0.0 then
		local frontCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, frontOffset, heightOffset + 0.15)
		if type(DrawLightWithRange) == "function" then
			DrawLightWithRange(frontCoords.x, frontCoords.y, frontCoords.z, r, g, b, range, frontIntensity)
		elseif type(DrawSpotLight) == "function" then
			DrawSpotLight(frontCoords.x, frontCoords.y, frontCoords.z + 0.5, 0.0, 0.0, -1.0, r, g, b, range + 1.0, frontIntensity, 8.0, range, 1.0)
		else
			Citizen.InvokeNative(0xD2D9E04C0DF927F4, frontCoords.x, frontCoords.y, frontCoords.z, r, g, b, range, frontIntensity)
		end
	end

	-- 3. Lower body fill light: illuminates waist, chaps, pants, skirts, holsters, and boots
	if lowerIntensity and lowerIntensity > 0.0 and frontOffset and frontOffset > 0.0 then
		local lowerCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, frontOffset, -0.25)
		if type(DrawLightWithRange) == "function" then
			DrawLightWithRange(lowerCoords.x, lowerCoords.y, lowerCoords.z, r, g, b, range, lowerIntensity)
		elseif type(DrawSpotLight) == "function" then
			DrawSpotLight(lowerCoords.x, lowerCoords.y, lowerCoords.z + 0.5, 0.0, 0.0, -1.0, r, g, b, range + 1.0, lowerIntensity, 8.0, range, 1.0)
		else
			Citizen.InvokeNative(0xD2D9E04C0DF927F4, lowerCoords.x, lowerCoords.y, lowerCoords.z, r, g, b, range, lowerIntensity)
		end
	end
end

function Light()
	Citizen.CreateThread(function()
		if CreatorLight == true then return end
		CreatorLight = true

		-- احسب إحداثيات النور مرة واحدة عند البداية وثبّتها
		local ped = CachePed or PlayerPedId()
		local cfg = (CreatorConfig and CreatorConfig.Lighting) or {}
		local color = cfg.color or { r = 255, g = 248, b = 240 }
		local r = tonumber(color.r) or 255
		local g = tonumber(color.g) or 248
		local b = tonumber(color.b) or 240
		local intensity      = tonumber(cfg.intensity)      or 7.5
		local frontIntensity = tonumber(cfg.frontIntensity) or 6.5
		local lowerIntensity = tonumber(cfg.lowerIntensity) or 5.5
		local range          = tonumber(cfg.range)          or 6.5
		local heightOffset   = tonumber(cfg.heightOffset)   or 0.85
		local frontOffset    = tonumber(cfg.frontOffset)    or 0.9

		-- مواقع ثابتة محسوبة مرة واحدة
		local baseCoords  = GetEntityCoords(ped)
		local frontCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, frontOffset, heightOffset + 0.15)
		local lowerCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, frontOffset, -0.25)

		-- DrawLightWithRange/DrawSpotLight يجب استدعاؤها كل فريم (مثل DrawText)
		-- لكن الإحداثيات ثابتة الآن فلا يومض ولا يتحرك النور
		while CreatorLight == true do
			if cfg.enabled ~= false then
				-- 1. نور رئيسي فوق الشخصية
				if intensity > 0.0 then
					if type(DrawLightWithRange) == "function" then
						DrawLightWithRange(baseCoords.x, baseCoords.y, baseCoords.z + heightOffset, r, g, b, range, intensity)
					else
						Citizen.InvokeNative(0xD2D9E04C0DF927F4, baseCoords.x, baseCoords.y, baseCoords.z + heightOffset, r, g, b, range, intensity)
					end
				end
				-- 2. نور أمامي للوجه والصدر
				if frontIntensity > 0.0 then
					if type(DrawLightWithRange) == "function" then
						DrawLightWithRange(frontCoords.x, frontCoords.y, frontCoords.z, r, g, b, range, frontIntensity)
					else
						Citizen.InvokeNative(0xD2D9E04C0DF927F4, frontCoords.x, frontCoords.y, frontCoords.z, r, g, b, range, frontIntensity)
					end
				end
				-- 3. نور سفلي للأرجل
				if lowerIntensity > 0.0 then
					if type(DrawLightWithRange) == "function" then
						DrawLightWithRange(lowerCoords.x, lowerCoords.y, lowerCoords.z, r, g, b, range, lowerIntensity)
					else
						Citizen.InvokeNative(0xD2D9E04C0DF927F4, lowerCoords.x, lowerCoords.y, lowerCoords.z, r, g, b, range, lowerIntensity)
					end
				end
			end
			Wait(0)
		end
	end)
end

AddEventHandler("onResourceStop", function(resourceName)
	if resourceName == GetCurrentResourceName() then
		-- CachePed is normally the player's own ped; only a preview ped may go.
		if CachePed and CachePed ~= 0 and DoesEntityExist(CachePed)
			and CachePed ~= PlayerPedId() and not IsPedAPlayer(CachePed) then
			DeletePed(CachePed)
		end
		if (ActiveCam or 0) ~= 0 then SwitchOffCam() end
		if lamp ~= nil then
			DeleteObject(lamp)
		end
		if lamp2 ~= nil then
			DeleteObject(lamp2)
		end
		DisplayRadar(true)
	end
end)
end

-- ============================================================================
-- Module: appearance/overlays.lua
-- ============================================================================
do
-------- OVERLAYS --------
local textureId = -1
local overlayUpdateRunning = false
local overlayUpdateQueued = false
local overlayUpdatePed = nil

function RemoveOverlays(ped)
    Callback.triggerServer("jrs_barber:GetCurrentOverlays", function(makeup, permanent)
        permanent = type(permanent) == "table" and permanent or {}
        overlay_all_layers = deepcopy(type(baseoverlay) == "table" and baseoverlay or {})
        if type(overlay_all_layers) == "table" then
            for k, v in pairs(overlay_all_layers) do
                for key, value in pairs(permanent) do
                    if type(value) == "table" and v.name == value.name then
                        -- Replace direct assignment with field updates
                        for field, val in pairs(value) do
                            overlay_all_layers[k][field] = val
                        end
                    end
                end
            end
        end
        Wait(200)
        UpdateOverlay(ped)
    end)
end

local function ApplyOverlayTexture(ped)
    ped = ped or CachePed or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    local isMale = IsPedMale(ped)
    local gender = isMale and "Male" or "Female"

    local currentSettings = texture_types and texture_types[gender] and deepcopy(texture_types[gender]) or {
        albedo = joaat(isMale and "mp_head_mr1_sc08_c0_000_ab" or "mp_head_fr1_sc08_c0_000_ab"),
        normal = joaat(isMale and "mp_head_mr1_000_nm" or "head_fr1_mp_002_nm"),
        material = isMale and 0x50A4BBA9 or 0x7FC5B1E1,
        color_type = 1,
        texture_opacity = 1.0,
        unk_arg = 0
    }

    local skintone = CachePedData and tonumber(CachePedData.skintone) or 1
    if skintone < 1 then skintone = 1 end
    local genderSets = DefaultChar and DefaultChar[gender] or (DefaultChar and DefaultChar["Male"])
    local skinSet = genderSets and (genderSets[skintone] or genderSets[1])
    local headTextureStr = skinSet and skinSet.HeadTexture and skinSet.HeadTexture[1]
    if not headTextureStr or headTextureStr == "" then
        headTextureStr = isMale and "mp_head_mr1_sc08_c0_000_ab" or "mp_head_fr1_sc08_c0_000_ab"
    end
    currentSettings.albedo = joaat(headTextureStr)

    if textureId ~= -1 then
        Citizen.InvokeNative(0xB63B9178D0F58D82, textureId) -- reset texture
        Citizen.InvokeNative(0x6BEFAA907B076859, textureId) -- remove texture
        textureId = -1
    end

    textureId = Citizen.InvokeNative(0xC5E7204F322E49EB, currentSettings.albedo, currentSettings.normal, currentSettings.material)
    local attempts = 0
    while textureId == -1 and attempts < 20 do
        attempts = attempts + 1
        Citizen.Wait(10)
        textureId = Citizen.InvokeNative(0xC5E7204F322E49EB, currentSettings.albedo, currentSettings.normal, currentSettings.material)
    end

    if textureId == -1 then return false end

    for _, v in pairs(overlay_all_layers or {}) do
        if v.visibility and tonumber(v.visibility) ~= 0 then
            local tx_id = v.tx_id
            local tx_normal = v.tx_normal or 0
            local tx_material = v.tx_material or 0

            if overlays_info and overlays_info[v.name] then
                local info = nil
                if v.tx_id_index and overlays_info[v.name][v.tx_id_index] then
                    info = overlays_info[v.name][v.tx_id_index]
                elseif type(tx_id) == "number" and tx_id > 0 and tx_id <= #overlays_info[v.name] then
                    info = overlays_info[v.name][tx_id]
                else
                    for _, entry in ipairs(overlays_info[v.name]) do
                        if entry.id == tx_id then
                            info = entry
                            break
                        end
                    end
                end

                if info then
                    if info.id and (not tx_id or tx_id == 0 or (type(tx_id) == "number" and tx_id <= #overlays_info[v.name] and tx_id > 0)) then
                        tx_id = info.id
                    end
                    if (tx_normal == 0 or not tx_normal) and info.normal then
                        tx_normal = info.normal
                    end
                    if (tx_material == 0 or not tx_material) and (info.ma or info.material) then
                        tx_material = info.ma or info.material
                    end
                end
            end

            local overlay_id = Citizen.InvokeNative(0x86BB5FF45F193A02, textureId, tx_id, tx_normal, tx_material,
                v.tx_color_type or 0, v.tx_opacity or 1.0, v.tx_unk or 0)
            if (v.tx_color_type or 0) == 0 then
                local palette = v.palette
                if not palette or palette == 0 then
                    local pId = tonumber(v.palette_id) or 1
                    palette = color_palettes and color_palettes[pId] and color_palettes[pId][1] or 0x3F6E70FF
                end
                Citizen.InvokeNative(0x1ED8588524AC9BE1, textureId, overlay_id, palette)
                Citizen.InvokeNative(0x2DF59FFE6FFD6044, textureId, overlay_id, v.palette_color_primary or 0,
                    v.palette_color_secondary or 0, v.palette_color_tertiary or 0)
            end
            Citizen.InvokeNative(0x3329AAE2882FC8E4, textureId, overlay_id, v.var or 0)
            Citizen.InvokeNative(0x6C76BC24F8BB709A, textureId, overlay_id, v.opacity or 1.0)
        end
    end

    local textureDeadline = GetGameTimer() + 2500
    while not Citizen.InvokeNative(0x31DC8D3F216D8509, textureId) and GetGameTimer() < textureDeadline do
        Citizen.Wait(0)
    end
    if not Citizen.InvokeNative(0x31DC8D3F216D8509, textureId) then
        Citizen.InvokeNative(0x6BEFAA907B076859, textureId)
        textureId = -1
        return false
    end

    Citizen.InvokeNative(0x0B46E25761519058, ped, `heads`, textureId)
    Citizen.InvokeNative(0x92DAABA2C1C10B0E, textureId)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
    if type(ApplyCharacterExpressions) == "function" then
        ApplyCharacterExpressions(ped)
    end
    return true
end

function UpdateOverlay(ped, table, targetalbedo)
    if table then
        overlay_all_layers = deepcopy(table)
    end
    overlayUpdatePed = ped or CachePed or PlayerPedId()
    if overlayUpdateRunning then
        overlayUpdateQueued = true
        return true
    end

    overlayUpdateRunning = true
    Citizen.CreateThread(function()
        local result = true
        repeat
            overlayUpdateQueued = false
            local ok, applied = pcall(ApplyOverlayTexture, overlayUpdatePed)
            if not ok then
                CreatorDebug(('[jrs_character] overlay update failed: %s'):format(tostring(applied)))
                result = false
                break
            end
            if applied == false then result = false end
            Citizen.Wait(0)
        until not overlayUpdateQueued
        overlayUpdateRunning = false
    end)
    return true
end

function OverlayChange(name, visibility, tx_id, tx_normal, tx_material, tx_color_type, tx_opacity, tx_unk, palette_id,
                       palette_color_primary, palette_color_secondary, palette_color_tertiary, var, opacity)
    for k, v in pairs(overlay_all_layers) do
        if v.name == name then
            v.visibility = visibility
            if visibility ~= 0 then
                v.tx_id_index = tx_id
                v.palette_id = palette_id

                v.tx_normal = tx_normal
                v.tx_material = tx_material
                v.tx_color_type = tx_color_type
                v.tx_opacity = tx_opacity
                v.tx_unk = tx_unk
                if tx_color_type == 0 then
                    if color_palettes[palette_id] then
                        v.palette = color_palettes[palette_id][1]
                    end
                    v.palette_color_primary = palette_color_primary
                    v.palette_color_secondary = palette_color_secondary
                    v.palette_color_tertiary = palette_color_tertiary
                end
                if name == "shadows" or name == "eyeliners" or name == "lipsticks" then
                    v.var = var
                    v.tx_id = overlays_info[name][1].id
                else
                    v.var = 0
                    v.tx_id = overlays_info[name][tx_id].id
                end
                if overlays_info and overlays_info[name] and overlays_info[name][tx_id] then
                    local info = overlays_info[name][tx_id]
                    if (not v.tx_normal or v.tx_normal == 0) and info.normal then
                        v.tx_normal = info.normal
                    end
                    if (not v.tx_material or v.tx_material == 0) and (info.ma or info.material) then
                        v.tx_material = info.ma or info.material
                    end
                end
                v.opacity = opacity
            end
        end
    end
    UpdateOverlay(CachePed)
end
end

-- ============================================================================
-- Module: appearance/barber.lua
-- ============================================================================
do
RegisterNetEvent('jrs_character_creator:loadbarberoverlay', function()
    -- Wait for player ped to be ready
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        CreatorDebug("[jrs_barber_creator] Error: Player ped does not exist")
        return
    end
    IsPedReadyToRender(ped)
    
    Callback.triggerServer('jrs_character_creator:GetCurrentHairs', function(datatable, outfitid, makeup, permanent)
        if datatable and next(datatable) ~= nil then
            makeup = type(makeup) == "table" and makeup or {}
            permanent = type(permanent) == "table" and permanent or {}
            barber_overlay_all_layers = deepcopy(type(baseoverlay) == "table" and baseoverlay or {})
            if type(barber_overlay_all_layers) == "table" then
                for k, v in pairs(barber_overlay_all_layers) do
                    for key, value in pairs(makeup) do
                        if type(value) == "table" and v.name == value.name then
                            -- Replace direct assignment with field updates
                            for field, val in pairs(value) do
                                barber_overlay_all_layers[k][field] = val
                            end
                        end
                    end
                    for key, value in pairs(permanent) do
                        if type(value) == "table" and v.name == value.name then
                            -- Replace direct assignment with field updates
                            for field, val in pairs(value) do
                                barber_overlay_all_layers[k][field] = val
                            end
                        end
                    end
                end
            end
            -- Small wait to ensure ped is ready for component changes
            Wait(100)
            TriggerEvent("jrs_character_creator:clotheitem", datatable, outfitid, true)
        else
            CreatorDebug("[jrs_barber_creator] No hairstyle data found for current character (empty datatable)")
        end
    end)
end)

RegisterNetEvent('jrs_character_creator:loadbarberoverlayOnCharacter', function(charid, ped)
    -- Wait for ped to be valid and fully loaded
    local attempts = 0
    while not DoesEntityExist(ped) do
        Wait(100)
        attempts = attempts + 1
        if attempts > 50 then
            CreatorDebug("[jrs_barber_creator] Error: Ped not loaded after 5 seconds for character " .. tostring(charid))
            return
        end
    end
    
    -- Wait for ped to be ready to render
    IsPedReadyToRender(ped)
    
    Callback.triggerServer('jrs_character_creator:GetCurrentHairsOnCharacter',
        function(datatable, outfitid, makeup, permanent)
            if datatable and next(datatable) ~= nil then
                makeup = type(makeup) == "table" and makeup or {}
                permanent = type(permanent) == "table" and permanent or {}
                barber_overlay_all_layers = deepcopy(type(baseoverlay) == "table" and baseoverlay or {})
                if type(barber_overlay_all_layers) == "table" then
                    for k, v in pairs(barber_overlay_all_layers) do
                        for key, value in pairs(makeup) do
                            if type(value) == "table" and v.name == value.name then
                                -- Replace direct assignment with field updates
                                for field, val in pairs(value) do
                                    barber_overlay_all_layers[k][field] = val
                                end
                            end
                        end
                        for key, value in pairs(permanent) do
                            if type(value) == "table" and v.name == value.name then
                                -- Replace direct assignment with field updates
                                for field, val in pairs(value) do
                                    barber_overlay_all_layers[k][field] = val
                                end
                            end
                        end
                    end
                end
                -- Small wait to ensure ped is ready for component changes
                Wait(100)
                TriggerEvent("jrs_character_creator:clotheitem", datatable, outfitid, true, ped, charid)
            else
                CreatorDebug("[jrs_barber_creator] No hairstyle data found for character " .. tostring(charid) .. " (empty datatable)")
            end
        end, charid)
end)

RegisterNetEvent('jrs_character_creator:clotheitem')
AddEventHandler('jrs_character_creator:clotheitem', function(hairstyleComponents, outfitid, overlay, target, charid)
    Citizen.CreateThread(function()
        local _Target = target or PlayerPedId()
        local gender
        if IsPedMale(_Target) then gender = "male" else gender = "female" end
        IsPedReadyToRender(_Target)
        barberCache = type(hairstyleComponents) == "table" and deepcopy(hairstyleComponents) or {}
        if JRS_ASSETS and JRS_ASSETS[gender] then
            for k, v in pairs(JRS_ASSETS[gender]) do
                if barberCache[k] == nil then
                    barberCache[k] = {}
                    barberCache[k].model = 0
                    barberCache[k].texture = 0
                end
            end
        end
        OldbarberCache = deepcopy(barberCache)
        Callback.triggerServer("jrs_character_creator:GetCurrentOverlays", function(makeup, permanent)
            makeup = type(makeup) == "table" and makeup or {}
            permanent = type(permanent) == "table" and permanent or {}
            Actualalbedo = nil
            Callback.triggerServer("jrs_character_creator:GetCharSkinTone", function(result)
                Actualalbedo = result
            end, IsPedMale(_Target), charid)
            -- Bounded: a lost/rejected reply left this loop spinning forever
            -- and every later barber/overlay reload queued behind it.
            local albedoDeadline = GetGameTimer() + 10000
            repeat
                Wait(100)
            until Actualalbedo ~= nil or GetGameTimer() > albedoDeadline
            local albedo = tonumber(Actualalbedo) or 0
            if GetHead(_Target) ~= 0 then
                if overlay == false then
                    RemoveOverlays(_Target)
                    barber_overlay_all_layers = deepcopy(type(baseoverlay) == "table" and baseoverlay or {})
                    if type(barber_overlay_all_layers) == "table" then
                        for k, v in pairs(barber_overlay_all_layers) do
                            for key, value in pairs(makeup) do
                                if type(value) == "table" and v.name == value.name then
                                    -- Replace direct assignment with field updates
                                    for field, val in pairs(value) do
                                        barber_overlay_all_layers[k][field] = val
                                    end
                                end
                            end
                            for key, value in pairs(permanent) do
                                if type(value) == "table" and v.name == value.name then
                                    -- Replace direct assignment with field updates
                                    for field, val in pairs(value) do
                                        barber_overlay_all_layers[k][field] = val
                                    end
                                end
                            end
                        end
                    end
                elseif type(barber_overlay_all_layers) ~= "table" then
                    barber_overlay_all_layers = deepcopy(type(baseoverlay) == "table" and baseoverlay or {})
                    if type(barber_overlay_all_layers) == "table" then
                        for k, v in pairs(barber_overlay_all_layers) do
                            for key, value in pairs(makeup) do
                                if type(value) == "table" and v.name == value.name then
                                    for field, val in pairs(value) do
                                        barber_overlay_all_layers[k][field] = val
                                    end
                                end
                            end
                            for key, value in pairs(permanent) do
                                if type(value) == "table" and v.name == value.name then
                                    for field, val in pairs(value) do
                                        barber_overlay_all_layers[k][field] = val
                                    end
                                end
                            end
                        end
                    end
                end
                if type(barber_overlay_all_layers) == "table" then
                    for k, v in pairs(barber_overlay_all_layers) do
                        if type(v) == "table" and (v.visibility or 0) > 0 then
                            UpdateOverlay(_Target, barber_overlay_all_layers, albedo)
                            break
                        end
                    end
                end
            end
            local canloadhair = false
            if type(barberCache) == "table" then
                for k, v in pairs(barberCache) do
                    if type(v) == "table" and (tonumber(v.model) or 0) > 0 then
                        canloadhair = true
                        break
                    end
                end
            end
            CreatorDebug("[jrs_barber_creator] Hairstyle data - canloadhair:", canloadhair, "charid:", charid, "target:", _Target)
            if canloadhair then
                -- Wait a bit to ensure ped is fully ready for component changes
                Wait(100)
                RemoveAllBarber(_Target)
                Wait(100)
                ReequipAllhairstyle(_Target)
                if charid == nil then
                    -- Aging effects must run after the saved hairstyle and overlays are fully loaded.
                    -- Passing clean copies prevents the runtime grey-hair layer from modifying saved data.
                    TriggerEvent('jrs_character:agingAppearanceReady',
                        deepcopy(barberCache),
                        deepcopy(type(barber_overlay_all_layers) == "table" and barber_overlay_all_layers or {}),
                        albedo
                    )
                end
            else
                CreatorDebug("[jrs_barber_creator] No hairstyle data to load for character")
            end
        end, charid)
    end)
end)

function RemoveAllBarber(ped)
    local equipped = GetCategoriesEquiped(ped)
    if type(equipped) ~= "table" then
        equipped = {}
    end

    local toremove = {
        "hair",
        "beard",
        "beards_chin",
        "beards_chops",
        "beards_mustache",
        "beards_complete",
        "hair_bonnet",
        "hats",
        "hat_accessories",
    }

    for category, data in pairs(equipped) do
        local isEssential = true
        for _, essential in ipairs(toremove) do
            if category == GetHashFromString(essential) then
                isEssential = false
                break
            end
        end

        if not isEssential then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, category, 0)
        end
    end


    NativeUpdatePedVariation(ped)
end

function BarberUsesHairTintPalette(category)
    category = tostring(category or "")
    return category == "hair" or category == "hairstabble" or category == "hair_bonnet"
        or category == "beard" or category == "beardstabble" or category == "beards_complete"
        or category == "beards_chin" or category == "beards_chops" or category == "beards_mustache"
end

function ReequipAllhairstyle(ped)
    local gender
    if IsPedMale(ped) then gender = "male" else gender = "female" end
    
    CreatorDebug("[jrs_barber_creator] ReequipAllhairstyle - gender:", gender, "ped:", ped)

    if type(barberCache) ~= "table" then
        CreatorDebug("[jrs_barber_creator] ReequipAllhairstyle - barberCache is not a table")
        return
    end

    for category, data in pairs(barberCache) do
        if type(data) == "table" and data.model and tonumber(data.model) > 0 then
            local modelIndex = tonumber(data.model)
            CreatorDebug("[jrs_barber_creator] Processing category:", category, "model:", modelIndex)
            
            if not JRS_ASSETS[gender] then
                CreatorDebug("[jrs_barber_creator] ERROR: No JRS_ASSETS for gender:", gender)
                goto continue
            end
            
            if not JRS_ASSETS[gender][category] then
                CreatorDebug("[jrs_barber_creator] ERROR: No JRS_ASSETS for category:", category)
                goto continue
            end
            
            local asset = JRS_ASSETS[gender][category] and JRS_ASSETS[gender][category][modelIndex]
            if asset == nil then
                CreatorDebug("Invalid hairstyle data for category:", category, "model:", modelIndex)
            else
                local drawable = asset.drawable
                if drawable then
                    local varIdx = 1
                    if type(data.texture) == "table" then
                        varIdx = tonumber(data.texture.palette or data.texture.model) or 1
                    else
                        varIdx = tonumber(data.texture) or 1
                    end
                    if varIdx < 1 then varIdx = 1 end

                    local variants = type(asset.variants) == "table" and asset.variants or {}
                    local selectedVariant = variants[varIdx] or variants[1]
                    if selectedVariant then
                        local albedo = selectedVariant.albedo
                        local normal = selectedVariant.normal
                        local material = selectedVariant.material
                        local palette = selectedVariant.palette
                        local vt = type(selectedVariant.tint) == "table" and selectedVariant.tint or {}
                        local tint0 = 0
                        local tint1 = 0
                        local tint2 = 0

                        if BarberUsesHairTintPalette(category) then
                            palette = `metaped_tint_hair`
                            if type(data.texture) == "table" then
                                local baseTint = tonumber(data.texture.tint0) or tonumber(vt[1]) or 0
                                tint0 = baseTint
                                tint1 = tonumber(data.texture.tint1) or baseTint
                                tint2 = tonumber(data.texture.tint2) or baseTint
                            else
                                local baseTint = tonumber(vt[1]) or 0
                                tint0 = baseTint
                                tint1 = baseTint
                                tint2 = baseTint
                            end
                        else
                            tint0 = tonumber(type(data.texture) == "table" and (data.texture.tint0 or vt[1]) or vt[1]) or 0
                            tint1 = tonumber(type(data.texture) == "table" and (data.texture.tint1 or vt[2]) or vt[2]) or 0
                            tint2 = tonumber(type(data.texture) == "table" and (data.texture.tint2 or vt[3]) or vt[3]) or 0
                        end

                        UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                        UpdatePedVariation(ped)
                    end
                else
                    local variantHash = nil
                    if type(data.texture) == "table" then
                        local texIdx = tonumber(data.texture.model or data.texture.palette or 1) or 1
                        if texIdx < 1 then texIdx = 1 end
                        variantHash = asset[texIdx] and asset[texIdx].hash or (asset[1] and asset[1].hash)
                        if variantHash then
                            NativeSetPedComponentEnabled(ped, variantHash, false, true)
                            local catHash = (category == "beard") and -134124598 or (type(category) == "number" and category or joaat(category))
                            local deadline = GetGameTimer() + 1500
                            local componentIndex = GetComponentIndexByCategory(ped, catHash)
                            while componentIndex == -1 and GetGameTimer() < deadline do
                                Wait(0)
                                componentIndex = GetComponentIndexByCategory(ped, catHash)
                            end
                            if componentIndex ~= -1 then
                                local d, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                                local baseTint = tonumber(data.texture.tint0) or 0
                                local tint0 = baseTint
                                local tint1 = tonumber(data.texture.tint1) or baseTint
                                local tint2 = tonumber(data.texture.tint2) or baseTint
                                local palette = `metaped_tint_hair`
                                UpdateCustomhairstyle(ped, d, albedo, normal, material, palette, tint0, tint1, tint2)
                            end
                            UpdatePedVariation(ped)
                        end
                    else
                        local texIdx = tonumber(data.texture or 1) or 1
                        if texIdx < 1 then texIdx = 1 end
                        variantHash = asset[texIdx] and asset[texIdx].hash or (asset[1] and asset[1].hash)
                        if variantHash then
                            NativeSetPedComponentEnabled(ped, tonumber(variantHash), false, true)
                            UpdatePedVariation(ped)
                        end
                    end
                end
            end
            ::continue::
        end
    end
    CreatorDebug("[jrs_barber_creator] ReequipAllhairstyle completed")
end


local function mergeSavedPreviewOverlays(savedMakeup, savedPermanent)
    local layers = deepcopy(type(baseoverlay) == "table" and baseoverlay or {})
    local function merge(source)
        for _, saved in pairs(type(source) == "table" and source or {}) do
            if type(saved) == "table" and saved.name then
                for _, layer in pairs(layers) do
                    if layer.name == saved.name then
                        for field, value in pairs(saved) do layer[field] = value end
                        break
                    end
                end
            end
        end
    end
    merge(savedMakeup)
    merge(savedPermanent)
    return layers
end

-- Apply saved hair, beard and face overlays to a selector ped synchronously.
-- The normal barber event shares barberCache between callbacks; with multiple
-- selector peds that caused later characters to overwrite earlier previews.
function ApplySavedBarberToPreviewPed(ped, barberData, pedData, age)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    barberData = type(barberData) == "table" and barberData or {}
    local hairstyle = type(barberData.hairstyle) == "table" and barberData.hairstyle or {}
    local hasAnyHair = false
    for _, v in pairs(hairstyle) do
        if type(v) == "table" and (tonumber(v.model) or 0) > 0 then
            hasAnyHair = true
            break
        end
    end
    if not hasAnyHair then
        local seed = tonumber(pedData and (pedData.charIdentifier or pedData.charid) or 0) or 1
        local gender = (pedData and pedData.gender == "Female") and "female" or (IsPedMale(ped) and "male" or "female")
        hairstyle = GetDiverseStarterBarber(gender, seed)
    end

    if next(hairstyle) ~= nil then
        local previousCache = barberCache
        barberCache = deepcopy(hairstyle)
        RemoveHairsAndBeards(ped)
        Wait(25)
        ReequipAllhairstyle(ped)
        barberCache = previousCache
    end

    local layers = mergeSavedPreviewOverlays(barberData.overlays, barberData.permanentoverlay)
    local albedo = nil
    local hasVisibleOverlay = false
    for _, layer in pairs(layers) do
        if tonumber(layer.visibility) and tonumber(layer.visibility) > 0 then
            hasVisibleOverlay = true
            break
        end
    end

    if hasVisibleOverlay and type(UpdateOverlay) == "function" then
        pedData = type(pedData) == "table" and pedData or {}
        local gender = pedData.gender == "Female" and "Female" or "Male"
        local skinTone = tonumber(pedData.skintone) or 1
        local skinSet = DefaultChar and DefaultChar[gender] and DefaultChar[gender][skinTone]
        if skinSet and skinSet.HeadTexture and skinSet.HeadTexture[1] then
            albedo = joaat(skinSet.HeadTexture[1])
        end
        UpdateOverlay(ped, layers, albedo)
    end

    NativeUpdatePedVariation(ped)
    IsPedReadyToRender(ped)

    if ped == PlayerPedId() then
        -- The selected player must receive the age effect immediately after the
        -- saved barber data is present. This is independent from the periodic
        -- playtime save thread and runs before the player is revealed.
        TriggerEvent('jrs_character:agingPlayerAppearanceReady',
            age,
            deepcopy(hairstyle),
            deepcopy(layers),
            albedo
        )
    elseif type(JRSApplyAgingToPreviewPed) == 'function' then
        JRSApplyAgingToPreviewPed(ped, barberData, pedData, age)
    end
    return true
end
end

-- ============================================================================
-- Module: appearance/clothing.lua
-- ============================================================================
do
-- Clothing editor embedded in jrs_character.
-- This does not open the jrs_clothing NUI. It only reuses the same asset format
-- and saves the final selection to the same jrs_clothing database tables.

CreatorOutfitMode = CreatorOutfitMode or nil
CreatorClothesCache = CreatorClothesCache or {}
CreatorClothesGender = CreatorClothesGender or nil
CreatorClothesInitialized = CreatorClothesInitialized or false
CreatorClothesResetSnapshot = CreatorClothesResetSnapshot or {}

-- The shared JRS asset database mixes two schemas per category: flat
-- catalog entries (first list entry has is_multiplayer=true/false) and
-- recolourable drawable+variants groups (see isMultiplayerAssetGroup below).
local CreatorMPAssetIndices = {}

local function isMultiplayerAssetGroup(asset, gender)
    if type(asset) ~= "table" then return false end

    -- Recolourable garments (drawable + variants) are a distinct schema from the
    -- flat is_multiplayer catalog entries: the drawable mesh id is only ever
    -- generated for real mp_male/mp_female components, and any NPC-only texture
    -- source (police/army/etc.) is stripped at the variant level in data/client.lua.
    -- A drawable group is therefore MP-safe whenever it still has a variant left.
    if asset.drawable ~= nil and type(asset.variants) == "table" then
        return next(asset.variants) ~= nil
    end

    local first = asset
    if asset.is_multiplayer == nil then first = asset[1] end
    if type(first) ~= "table" then return false end

    local isMP = first.is_multiplayer == true or tonumber(first.is_multiplayer) == 1
    local pedType = tostring(first.ped_type or gender or "")
    return isMP and (pedType == "" or pedType == tostring(gender or ""))
end

local function ensureCreatorMPAssetIndices(gender)
    local currentGender = IsPedMale(CachePed or PlayerPedId()) and "male" or "female"
    gender = tostring(gender or currentGender)
    if CreatorMPAssetIndices[gender] then return end

    CreatorMPAssetIndices[gender] = {}
    local genderAssets = JRS_CLOTHING_ASSETS and JRS_CLOTHING_ASSETS[gender] or {}
    for category, assets in pairs(genderAssets) do
        local indices = {}
        for realIndex, asset in ipairs(assets or {}) do
            if isMultiplayerAssetGroup(asset, gender) then
                indices[#indices + 1] = realIndex
            end
        end
        CreatorMPAssetIndices[gender][tostring(category)] = indices
    end
end

local function getCreatorMPIndices(category)
    local gender = IsPedMale(CachePed or PlayerPedId()) and "male" or "female"
    ensureCreatorMPAssetIndices(gender)
    return CreatorMPAssetIndices[gender] and CreatorMPAssetIndices[gender][tostring(category or "")] or {}
end

-- 4.2.45: MP | NPC switch, same as the jrs_clothing shop. In the shared
-- asset file a drawable+variants group is an NPC garment and a flat catalog
-- entry is an MP shop item. The creator list is split by that; the slider
-- walks only the list of the active mode (CreatorClothingModes[category]).
CreatorClothingModes = CreatorClothingModes or {}

local function creatorAssetMode(category, realIndex)
    local gender = IsPedMale(CachePed or PlayerPedId()) and "male" or "female"
    local assets = JRS_CLOTHING_ASSETS and JRS_CLOTHING_ASSETS[gender] and JRS_CLOTHING_ASSETS[gender][tostring(category or "")]
    local asset = assets and assets[tonumber(realIndex) or 0]
    return (type(asset) == "table" and asset.drawable ~= nil) and "npc" or "mp"
end

local CreatorModeIndexCache = {}
local function getCreatorModeIndices(category, mode)
    if mode ~= "mp" and mode ~= "npc" then return getCreatorMPIndices(category) end
    local gender = IsPedMale(CachePed or PlayerPedId()) and "male" or "female"
    local key = gender .. "|" .. tostring(category or "")
    local cached = CreatorModeIndexCache[key]
    if not cached then
        cached = { mp = {}, npc = {} }
        for _, realIndex in ipairs(getCreatorMPIndices(category)) do
            local list = cached[creatorAssetMode(category, realIndex)]
            list[#list + 1] = realIndex
        end
        CreatorModeIndexCache[key] = cached
    end
    return cached[mode]
end

-- mode: "mp" / "npc" for that list, "all" for the full list, nil for the
-- category's active mode.
local function resolveCreatorMPAssetIndex(category, uiIndex, mode)
    local indices = getCreatorModeIndices(category, mode or CreatorClothingModes[tostring(category or "")])
    return indices[tonumber(uiIndex) or 0]
end

local function getCreatorMPUiIndex(category, realIndex, mode)
    realIndex = tonumber(realIndex) or 0
    if realIndex < 1 then return 0 end
    for uiIndex, mappedIndex in ipairs(getCreatorModeIndices(category, mode or CreatorClothingModes[tostring(category or "")])) do
        if mappedIndex == realIndex then return uiIndex end
    end
    return 0
end

local clothingLabels = {
    head = "Head", upper = "Upper Body", lower = "Lower Body", feets = "Footwear", accs = "Accessories",
    bodies_upper = "Body Upper", bodies_lower = "Body Lower",
    hats = "Hats", masks = "Masks", eyewear = "Eyewear", headwear = "Headwear", face_props = "Face Props",
    hat_accessories = "Hat Accessories", masks_large = "Large Masks", coats = "Coats", shirts_full = "Shirts",
    vests = "Vests", suspenders = "Suspenders", unionsuits_full = "Full Unionsuits", overalls_full = "Overalls",
    shirts_full_overpants = "Overshirts", cloaks = "Cloaks", overalls_modular_uppers = "Overalls Upper",
    coats_closed = "Closed Coats", outfits = "Full Outfits", coats_heavy = "Heavy Coats", ponchos = "Ponchos",
    shawls = "Shawls", corsets = "Corsets", chemises = "Chemises", capes = "Capes", pants = "Pants",
    overalls_modular_lowers = "Overalls Lower", dresses = "Dresses", skirts = "Skirts",
    unionsuit_legs = "Unionsuit Legs", knickers = "Knickers", stockings = "Stockings", boots = "Boots",
    boot_accessories = "Boot Accessories", spats = "Spats", neckerchiefs = "Neckerchiefs", neckties = "Neckties",
    gloves = "Gloves", belts = "Belts", accessories = "General Accessories", badges = "Badges", satchels = "Satchels",
    neckwear = "Neckwear", jewelry_necklaces = "Necklaces", jewelry_rings = "Rings",
    vest_accessories = "Vest Accessories", hair_accessories = "Hair Accessories", aprons = "Aprons",
    coat_accessories = "Coat Accessories", chaps = "Chaps", pants_accessories = "Pants Accessories",
    armor = "Armor", jewelry_bracelets = "Bracelets", wrist_bindings = "Wrist Bindings", gauntlets = "Gauntlets",
    ankle_bindings = "Ankle Bindings", belt_buckles = "Belt Buckles", jewelry_rings_right = "Right Rings",
    jewelry_rings_left = "Left Rings", satchel_straps = "Satchel Straps", jewelry_earrings = "Earrings",
    gunbelts = "Gun Belts", loadouts = "Loadouts", holsters_right = "Right Holster", holsters_left = "Left Holster",
    holsters_center = "Center Holster", holsters_knife = "Knife Sheath", holsters_crossdraw = "Crossdraw Holster",
    holsters_quivers = "Quivers", ammo_pistols = "Pistol Ammo",
    gunbelt_accs = "Gun Belt Accessories", lduvmjua_0x2b388a05 = "Under Shirt",
    nbtudvja_0x53b67599 = "Sleeveless Shirt", cnvfyaba_0xd7ae0d03 = "Shoulder Dress",
    gjrbmoma_0xcb39a6f4 = "Dress Accessory 1", pnyvpusa_0x44f4c713 = "Dress Accessory 2",
    ogoolgaa_0xecd61654 = "Dress Accessory 3", gnuusvra_0x7024af8b = "Dress Accessory 4",
    oacpqvda_0x41292b6f = "Dress Accessory 5", ywkywwvb_0xe93b9f1b = "Dress Accessory 6",
    mbbwboia_0x42e8f927 = "Flowers"
}

CreatorClothingPinsVisible = CreatorClothingPinsVisible or false
local CreatorClothingPinsGeneration = 0

local clothingCameraGroups = {
    head = "head",
    upper = "upperbody",
    lower = "lowerbody",
    feets = "feet",
    accs = "Body"
}

local clothingHeadCategories = {
    hats = true, masks = true, eyewear = true, headwear = true, face_props = true,
    hat_accessories = true, masks_large = true, hair_accessories = true, jewelry_earrings = true
}
local clothingUpperCategories = {
    bodies_upper = true,
    coats = true, shirts_full = true, lduvmjua_0x2b388a05 = true, nbtudvja_0x53b67599 = true,
    vests = true, suspenders = true, unionsuits_full = true, overalls_full = true,
    shirts_full_overpants = true, cloaks = true, overalls_modular_uppers = true,
    coats_closed = true, coats_heavy = true, ponchos = true, capes = true, shawls = true,
    corsets = true, chemises = true, armor = true, cnvfyaba_0xd7ae0d03 = true,
    gjrbmoma_0xcb39a6f4 = true, pnyvpusa_0x44f4c713 = true, ogoolgaa_0xecd61654 = true,
    gnuusvra_0x7024af8b = true, oacpqvda_0x41292b6f = true, ywkywwvb_0xe93b9f1b = true
}
local clothingLowerCategories = {
    bodies_lower = true,
    pants = true, overalls_modular_lowers = true, dresses = true, skirts = true,
    unionsuit_legs = true, knickers = true, stockings = true, chaps = true,
    pants_accessories = true, aprons = true
}
local clothingFeetCategories = {
    boots = true, boot_accessories = true, spats = true, ankle_bindings = true
}
local clothingWaistCategories = {
    belts = true, belt_buckles = true, gunbelts = true, loadouts = true,
    holsters_right = true, holsters_left = true, holsters_center = true,
    holsters_knife = true, holsters_crossdraw = true, holsters_quivers = true,
    ammo_pistols = true, gunbelt_accs = true, coat_accessories = true, vest_accessories = true
}
local clothingHandCategories = {
    gloves = true, jewelry_rings = true, jewelry_rings_right = true, jewelry_rings_left = true,
    jewelry_bracelets = true, wrist_bindings = true, gauntlets = true
}
local clothingAccsCategories = {
    accessories = true, badges = true, satchels = true, satchel_straps = true,
    neckwear = true, neckerchiefs = true, neckties = true,
    jewelry_necklaces = true, jewelry_earrings = true,
    aprons = true, chaps = true, pants_accessories = true, armor = true,
    hair_accessories = true, ankle_bindings = true, mbbwboia_0x42e8f927 = true
}

local CreatorClothingGroupOrder = { "head", "upper", "lower", "feets", "accs" }

-- These three freemode categories are mandatory in the creator and must never
-- be lost when new categories are added to the shared clothing asset file.
-- Every MP record from each category is exposed through the selector.
local CreatorPrimaryPlayerCategories = {
    shirts_full = "upper",
    pants = "lower",
    boots = "feets"
}

local CreatorCategoryPriority = {
    -- Upper Body
    bodies_upper = 0,
    shirts_full = 1,
    vests = 2,
    coats = 3,
    coats_closed = 4,
    coats_heavy = 5,
    ponchos = 6,
    cloaks = 7,
    suspenders = 8,
    outfits = 9,
    corsets = 10,
    chemises = 11,
    shawls = 12,
    capes = 13,
    armor = 14,
    
    -- Lower Body
    bodies_lower = 0,
    pants = 1,
    skirts = 2,
    dresses = 3,
    chaps = 4,
    knickers = 5,
    stockings = 6,
    
    -- Head
    hats = 1,
    eyewear = 2,
    masks = 3,
    headwear = 4,
    face_props = 5,
    hat_accessories = 6,
    
    -- Footwear
    boots = 1,
    boot_accessories = 2,
    spats = 3,
    ankle_bindings = 4,
    
    -- Accessories
    gloves = 1,
    belts = 2,
    belt_buckles = 3,
    neckties = 4,
    neckerchiefs = 5,
    neckwear = 6,
    jewelry_necklaces = 7,
    jewelry_rings_right = 8,
    jewelry_rings_left = 9,
    jewelry_bracelets = 10,
    jewelry_earrings = 11,
    badges = 12,
    satchels = 13,
    satchel_straps = 14,
    gunbelts = 15,
    holsters_right = 16,
    holsters_left = 17,
    holsters_center = 18,
    holsters_knife = 19,
    gunbelt_accs = 20,
    loadouts = 21,
    gauntlets = 22,
    wrist_bindings = 23,
    aprons = 24,
    coat_accessories = 25,
    vest_accessories = 26,
    pants_accessories = 27,
    hair_accessories = 28,
    accessories = 29,
}

-- These are character-body or barber components, not wearable clothing.
local CreatorNonClothingCategories = {
    hair = true, hair_bonnet = true, hairstabble = true, beard = true, beardstabble = true,
    beards_complete = true, beards_chin = true, beards_chops = true, beards_mustache = true,
    heads = true, eyes = true, teeth = true,
    eyebrows = true, eyeliners = true, lipsticks = true, shadows = true, paintedmasks = true,
    blush = true, blush2 = true, foundation = true, scars = true, scars2 = true, scars3 = true,
    acne = true, ageing = true, complex = true, disc = true, freckles = true, grime = true,
    moles = true, spots = true
}

local function classifyCreatorClothingCategory(category)
    category = tostring(category or "")
    if CreatorNonClothingCategories[category] then return nil end
    if category:match("^%-?%d+$") or category:find("^gore_") then return nil end
    if clothingHeadCategories[category] then return "head" end
    if clothingFeetCategories[category] then return "feets" end
    if clothingLowerCategories[category] then return "lower" end
    if clothingUpperCategories[category] or category == "outfits" then return "upper" end
    if clothingAccsCategories[category] or clothingWaistCategories[category] or clothingHandCategories[category] then
        return "accs"
    end
    -- Do not leak unknown dev/admin/ped hash categories into the creator menu
    return nil
end

local function creatorCategoryLabel(category)
    category = tostring(category or "")
    local key = 'creator_cat_' .. category
    local lang = (type(currentLanguage) == "function" and currentLanguage()) or JrsLang.Current() or "ar"

    local translated = _UL(lang, key)
    if translated and translated ~= key and translated ~= "" then
        return translated
    end
    translated = _UL("ar", key)
    if translated and translated ~= key and translated ~= "" then
        return translated
    end
    translated = _UL("en", key)
    if translated and translated ~= key and translated ~= "" then
        return translated
    end

    local known = clothingLabels[category]
    if known then return known end

    local value = category:gsub("_0x[%da-fA-F]+$", ""):gsub("_", " ")
    value = value:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end)
    if value == "" or value:match("^%-?%d+$") then
        return _UL(lang, "creator_cat_accessories") or "إكسسوارات عامة"
    end
    return value
end

function GetCreatorOutfitCameraDestination(category, group, mode)
    category = tostring(category or "")
    group = tostring(group or "")

    if tostring(mode or CreatorOutfitMode) == "barber" then
        return "head"
    end

    if clothingHeadCategories[category] then return "head" end
    if clothingFeetCategories[category] then return "feet" end
    if clothingWaistCategories[category] then return "waist" end
    if clothingHandCategories[category] then return "hands" end
    if clothingLowerCategories[category] then return "lowerbody" end
    if clothingUpperCategories[category] then return "upperbody" end
    if category == "outfits" or category == "satchels" or category == "satchel_straps" or category == "accessories" then
        return "Body"
    end
    return clothingCameraGroups[group] or clothingCameraGroups[category] or "Body"
end

function FocusCreatorOutfitCategory(category, group, mode)
    MoveCam(GetCreatorOutfitCameraDestination(category, group, mode))
end

function StopCreatorClothingPins()
    CreatorClothingPinsVisible = false
    CreatorClothingPinsGeneration = CreatorClothingPinsGeneration + 1
    SendNUIMessage({ type = "hideClothingPins" })
end

local function clothingScreenPoint(coords)
    local visible, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    -- Depending on the RedM artifact/native bridge, the visibility result can
    -- be returned as boolean true or numeric 1. Normalize both forms so the
    -- body-attached clothing and barber pins are not hidden incorrectly.
    local isVisible = visible == true or tonumber(visible) == 1
    return {
        x = tonumber(x) or 0.5,
        y = tonumber(y) or 0.5,
        visible = isVisible
    }
end

function StartCreatorClothingPins()
    CreatorClothingPinsVisible = false
    CreatorClothingPinsGeneration = CreatorClothingPinsGeneration + 1
    CreatorClothingPinsVisible = true
    CreatorClothingPinsGeneration = CreatorClothingPinsGeneration + 1
    local generation = CreatorClothingPinsGeneration

    CreateThread(function()
        while CreatorClothingPinsVisible and generation == CreatorClothingPinsGeneration and CreatorOutfitMode == "clothing" do
            local ped = CachePed or PlayerPedId()
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                -- Use the actual freemode skeleton anchors. The previous
                -- version accidentally used left upper-arm/left-hand/right-thigh
                -- IDs for multiple areas, which stacked Accessories and Footwear
                -- around the waist. These anchors match head, chest, pelvis,
                -- thighs and feet respectively for mp_male/mp_female peds.
                local head = GetPedBoneCoords(ped, 21030, 0.00, 0.00, 0.10)   -- SKEL_Head
                local upper = GetPedBoneCoords(ped, 53684, 0.00, 0.00, 0.00)  -- CP_Chest
                local accs = GetPedBoneCoords(ped, 56200, 0.00, 0.00, 0.02)   -- SKEL_Pelvis

                local leftThigh = GetPedBoneCoords(ped, 65478, 0.00, 0.00, -0.08)
                local rightThigh = GetPedBoneCoords(ped, 6884, 0.00, 0.00, -0.08)
                local lower = vector3(
                    (leftThigh.x + rightThigh.x) * 0.5,
                    (leftThigh.y + rightThigh.y) * 0.5,
                    (leftThigh.z + rightThigh.z) * 0.5
                )

                local leftFoot = GetPedBoneCoords(ped, 45454, 0.00, 0.00, 0.02)
                local rightFoot = GetPedBoneCoords(ped, 33646, 0.00, 0.00, 0.02)
                local feet = vector3(
                    (leftFoot.x + rightFoot.x) * 0.5,
                    (leftFoot.y + rightFoot.y) * 0.5,
                    (leftFoot.z + rightFoot.z) * 0.5
                )

                local headPoint = clothingScreenPoint(head)
                local upperPoint = clothingScreenPoint(upper)
                local accsPoint = clothingScreenPoint(accs)
                local lowerPoint = clothingScreenPoint(lower)
                local feetPoint = clothingScreenPoint(feet)

                SendNUIMessage({
                    type = "updateClothingPins",
                    pins = {
                        { id = "head", x = headPoint.x, y = headPoint.y, visible = headPoint.visible, direction = "right", offsetX = 0.010, offsetY = -0.010 },
                        { id = "upper", x = upperPoint.x, y = upperPoint.y, visible = upperPoint.visible, direction = "left", offsetX = -0.010, offsetY = -0.004 },
                        { id = "accs", x = accsPoint.x, y = accsPoint.y, visible = accsPoint.visible, direction = "right", offsetX = 0.012, offsetY = 0.000 },
                        { id = "lower", x = lowerPoint.x, y = lowerPoint.y, visible = lowerPoint.visible, direction = "left", offsetX = -0.012, offsetY = 0.012 },
                        { id = "feets", x = feetPoint.x, y = feetPoint.y, visible = feetPoint.visible, direction = "right", offsetX = 0.012, offsetY = 0.008 }
                    }
                })
            end
            Wait(60)
        end
    end)
end


CreatorBarberPinsVisible = CreatorBarberPinsVisible or false
local CreatorBarberPinsGeneration = 0

function StopCreatorBarberPins()
    CreatorBarberPinsVisible = false
    CreatorBarberPinsGeneration = CreatorBarberPinsGeneration + 1
    SendNUIMessage({ type = "hideBarberPins" })
end

function StartCreatorBarberPins()
    CreatorBarberPinsVisible = false
    CreatorBarberPinsGeneration = CreatorBarberPinsGeneration + 1
    CreatorBarberPinsVisible = true
    CreatorBarberPinsGeneration = CreatorBarberPinsGeneration + 1
    local generation = CreatorBarberPinsGeneration

    CreateThread(function()
        while CreatorBarberPinsVisible and generation == CreatorBarberPinsGeneration and CreatorOutfitMode == "barber" do
            local ped = CachePed or PlayerPedId()
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local hair = GetPedBoneCoords(ped, 21030, 0.00, 0.00, 0.20)
                local beard = GetPedBoneCoords(ped, 21030, 0.00, 0.02, -0.13)
                local lifestyle = GetPedBoneCoords(ped, 21030, -0.16, 0.01, 0.02)
                local makeup = GetPedBoneCoords(ped, 21030, 0.16, 0.01, 0.05)

                local hairPoint = clothingScreenPoint(hair)
                local beardPoint = clothingScreenPoint(beard)
                local lifestylePoint = clothingScreenPoint(lifestyle)
                local makeupPoint = clothingScreenPoint(makeup)

                SendNUIMessage({
                    type = "updateBarberPins",
                    pins = {
                        { id = "hair", x = hairPoint.x, y = hairPoint.y, visible = hairPoint.visible, direction = "right" },
                        { id = "beard", x = beardPoint.x, y = beardPoint.y, visible = beardPoint.visible, direction = "left" },
                        { id = "lifestyle", x = lifestylePoint.x, y = lifestylePoint.y, visible = lifestylePoint.visible, direction = "left" },
                        { id = "makeup", x = makeupPoint.x, y = makeupPoint.y, visible = makeupPoint.visible, direction = "right" }
                    }
                })
            end
            Wait(60)
        end
    end)
end

local function getCreatorClothingGender()
    return IsPedMale(CachePed or PlayerPedId()) and "male" or "female"
end

local function getAsset(category, model)
    local gender = getCreatorClothingGender()
    return JRS_CLOTHING_ASSETS and JRS_CLOTHING_ASSETS[gender]
        and JRS_CLOTHING_ASSETS[gender][category]
        and JRS_CLOTHING_ASSETS[gender][category][tonumber(model)] or nil
end

local function getVariantTint(variant)
    local tint = type(variant) == "table" and variant.tint or nil
    return tonumber(variant and variant.tint0) or tonumber(tint and tint[1]) or 0,
        tonumber(variant and variant.tint1) or tonumber(tint and tint[2]) or 0,
        tonumber(variant and variant.tint2) or tonumber(tint and tint[3]) or 0
end

local function getCreatorSkinSet()
    local gender = CachePedData and CachePedData.gender or (IsPedMale(CachePed or PlayerPedId()) and "Male" or "Female")
    if gender == "male" then gender = "Male" end
    if gender == "female" then gender = "Female" end
    local skintone = CachePedData and tonumber(CachePedData.skintone) or 1
    return DefaultChar and DefaultChar[gender] and DefaultChar[gender][skintone]
end

local function removeCreatorClothingCategory(ped, category)
    if category == "bodies_upper" then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0B3966C9, 0)
        NativeUpdatePedVariation(ped)
        return
    elseif category == "bodies_lower" then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x823687F5, 0)
        NativeUpdatePedVariation(ped)
        return
    end
    if category == "cloaks" or category == "ponchos" or category == "capes" then
        for _, linked in ipairs({ "cloaks", "ponchos", "capes" }) do
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(linked), 0)
        end
    else
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(tostring(category)), 0)
        local numeric = tonumber(category)
        if numeric then Citizen.InvokeNative(0xD710A5007C2AC539, ped, numeric, 0) end
    end
    NativeUpdatePedVariation(ped)
end

function ResetCreatorClothingCache(removeCurrent)
    CreatorClothesCache = {}
    CreatorClothesGender = getCreatorClothingGender()
    CreatorClothesInitialized = true

    local genderAssets = JRS_CLOTHING_ASSETS and JRS_CLOTHING_ASSETS[CreatorClothesGender] or {}
    for category in pairs(genderAssets or {}) do
        CreatorClothesCache[category] = { model = 0, texture = 0 }
    end

    if removeCurrent ~= false then
        RemoveAllClothesExceptEssentials(CachePed or PlayerPedId())
    end
end

function GetCreatorClothesCache()
    return deepcopy(CreatorClothesCache or {})
end

-- Starter outfit: simple clothes for a new man / woman. The player can change or remove them in the creator.
CreatorStarterOutfit = {
    male   = { "pants", "shirts_full", "boots" },
    female = { "skirts", "shirts_full", "boots" },
}

function ApplyCreatorStarterOutfit()
    local gender = IsPedMale(CachePed or PlayerPedId()) and "male" or "female"
    for _, category in ipairs(CreatorStarterOutfit[gender] or {}) do
        local current = CreatorClothesCache and CreatorClothesCache[category]
        if not current or (tonumber(current.model) or 0) < 1 then
            if not CreatorClothingChange(1, category, "model") and category == "skirts" then
                CreatorClothingChange(1, "pants", "model")
            end
        end
    end
    -- the creator re-skins the body right after it opens: put the clothes back on once that is done
    CreateThread(function()
        Wait(1500)
        if CreatorClothesInitialized then ReseatCreatorClothes(CachePed or PlayerPedId()) end
    end)
end

function CreatorClothingChange(id, category, changeType, value)
    local ped = CachePed or PlayerPedId()
    local model = tonumber(id) or 0
    category = tostring(category or "")
    if category == "" then return false end

    -- Direct support for Upper Body and Lower Body meshes (DefaultChar skin-matched)
    -- Allow 0 for "Hidden / Erased" body mesh to eliminate clothing clipping (wrists, waist, thighs)
    if (category == "bodies_upper" or category == "bodies_lower") and model < 0 then model = 0 end
    if category == "bodies_upper" then
        if model == 0 then
            CachePedData.upperbody = 0
            CreatorClothesCache["bodies_upper"] = { model = 0, texture = 0 }
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0B3966C9, 0)
            TriggerEvent("jrs_clothes:Loadupperbody", 0)
            NativeUpdatePedVariation(ped)
            return true
        end
        local skinSet = getCreatorSkinSet()
        local bodyList = skinSet and skinSet.Body or {}
        local count = #bodyList
        if count > 0 then
            local modelVal = math.max(1, math.min(count, model))
            CachePedData.upperbody = modelVal
            CreatorClothesCache["bodies_upper"] = { model = modelVal, texture = 0 }
            local comp = bodyList[modelVal]
            if comp then
                ApplyShopItemToPed(tonumber("0x" .. comp), ped)
                TriggerEvent("jrs_clothes:Loadupperbody", tonumber("0x" .. comp))
                NativeUpdatePedVariation(ped)
            end
            return true
        end
        return false
    end

    if category == "bodies_lower" then
        if model == 0 then
            CachePedData.lowerbody = 0
            CreatorClothesCache["bodies_lower"] = { model = 0, texture = 0 }
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x823687F5, 0)
            TriggerEvent("jrs_clothes:Loadlowerbody", 0)
            NativeUpdatePedVariation(ped)
            return true
        end
        local skinSet = getCreatorSkinSet()
        local legList = skinSet and skinSet.Legs or {}
        local count = #legList
        if count > 0 then
            local modelVal = math.max(1, math.min(count, model))
            CachePedData.lowerbody = modelVal
            CreatorClothesCache["bodies_lower"] = { model = modelVal, texture = 0 }
            local comp = legList[modelVal]
            if comp then
                ApplyShopItemToPed(tonumber("0x" .. comp), ped)
                TriggerEvent("jrs_clothes:Loadlowerbody", tonumber("0x" .. comp))
                NativeUpdatePedVariation(ped)
            end
            return true
        end
        return false
    end

    -- Model values coming from the creator UI are MP-only list positions.
    -- Convert them back to the original shared asset index before applying or
    -- saving so the regular jrs_clothing resource reads the same garment.
    if changeType == "model" and model > 0 then
        model = resolveCreatorMPAssetIndex(category, model) or 0
        if model < 1 then return false end
    end

    CreatorClothesCache[category] = CreatorClothesCache[category] or { model = 0, texture = 0 }
    if model < 1 then
        removeCreatorClothingCategory(ped, category)
        CreatorClothesCache[category] = { model = 0, texture = 0 }
        return true
    end

    local asset = getAsset(category, changeType == "model" and model or CreatorClothesCache[category].model)
    if not asset then return false end

    if changeType == "model" then
        CreatorClothesCache[category].model = model
        if asset.drawable and asset.variants and asset.variants[1] then
            local variant = asset.variants[1]
            local tint0, tint1, tint2 = getVariantTint(variant)
            CreatorClothesCache[category].texture = {
                palette = 1,
                tint0 = tint0,
                tint1 = tint1,
                tint2 = tint2
            }
            UpdateCustomClothes(ped, asset.drawable, variant.albedo, variant.normal, variant.material, variant.palette,
                tint0, tint1, tint2)
        elseif asset[1] and asset[1].hash then
            CreatorClothesCache[category].texture = 1
            NativeSetPedComponentEnabled(ped, asset[1].hash, false, true)
        else
            CreatorClothesCache[category] = { model = 0, texture = 0 }
            return false
        end
        NativeUpdatePedVariation(ped)
        return true
    end

    local texture = CreatorClothesCache[category].texture
    if asset.drawable and asset.variants then
        if type(texture) ~= "table" then texture = { palette = 1, tint0 = 0, tint1 = 0, tint2 = 0 } end
        local paletteIndex = tonumber(texture.palette) or 1

        if changeType == "variants" then paletteIndex = math.max(1, math.min(#asset.variants, tonumber(value) or 1)) end
        local variant = asset.variants[paletteIndex]
        if not variant then return false end

        local default0, default1, default2 = getVariantTint(variant)
        texture.palette = paletteIndex
        texture.tint0 = tonumber(texture.tint0) or default0
        texture.tint1 = tonumber(texture.tint1) or default1
        texture.tint2 = tonumber(texture.tint2) or default2
        if changeType == 1 then texture.tint0 = tonumber(value) or texture.tint0 end
        if changeType == 2 then texture.tint1 = tonumber(value) or texture.tint1 end
        if changeType == 3 then texture.tint2 = tonumber(value) or texture.tint2 end
        CreatorClothesCache[category].texture = texture

        UpdateCustomClothes(ped, asset.drawable, variant.albedo, variant.normal, variant.material, variant.palette,
            texture.tint0, texture.tint1, texture.tint2)
    else
        local variation = tonumber(changeType == "variants" and value or texture) or 1
        variation = math.max(1, math.min(#asset, variation))
        local variant = asset[variation]
        if not variant or not variant.hash then return false end
        CreatorClothesCache[category].texture = variation
        NativeSetPedComponentEnabled(ped, variant.hash, false, true)

        if changeType == 1 or changeType == 2 or changeType == 3 then
            local catHash = GetHashKey(category)
            local componentIndex = GetComponentIndexByCategory(ped, catHash)
            if componentIndex and componentIndex >= 0 then
                local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                if changeType == 1 then tint0 = tonumber(value) or tint0 end
                if changeType == 2 then tint1 = tonumber(value) or tint1 end
                if changeType == 3 then tint2 = tonumber(value) or tint2 end
                CreatorClothesCache[category].texture = {
                    palette = variation,
                    tint0 = tint0 or 0,
                    tint1 = tint1 or 0,
                    tint2 = tint2 or 0
                }
                UpdateCustomClothes(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
            end
        end
    end

    NativeUpdatePedVariation(ped)
    return true
end

function ResetCreatorClothingItem(category)
    category = tostring(category or "")
    if category == "" then return 0 end

    local ped = CachePed or PlayerPedId()
    local original = deepcopy((CreatorClothesResetSnapshot or {})[category] or { model = 0, texture = 0 })

    if category == "bodies_upper" or category == "bodies_lower" then
        local originalModel = tonumber(original.model) or 0
        CreatorClothingChange(originalModel, category, "model")
        return originalModel
    end

    removeCreatorClothingCategory(ped, category)
    CreatorClothesCache[category] = { model = 0, texture = 0 }

    local originalModel = tonumber(original.model) or 0
    if originalModel > 0 then CreatorClothingModes[category] = creatorAssetMode(category, originalModel) end
    local uiIndex = getCreatorMPUiIndex(category, originalModel)
    if originalModel > 0 and uiIndex > 0 then
        if CreatorClothingChange(uiIndex, category, "model") then
            local texture = original.texture
            if type(texture) == "table" then
                local palette = tonumber(texture.palette) or tonumber(texture.model) or 1
                CreatorClothingChange(originalModel, category, "variants", palette)
                CreatorClothingChange(originalModel, category, 1, tonumber(texture.tint0) or 0)
                CreatorClothingChange(originalModel, category, 2, tonumber(texture.tint1) or 0)
                CreatorClothingChange(originalModel, category, 3, tonumber(texture.tint2) or 0)
            else
                CreatorClothingChange(originalModel, category, "variants", tonumber(texture) or 1)
            end
        end
    else
        uiIndex = 0
    end

    local selectedModel = CreatorClothesCache[category] and tonumber(CreatorClothesCache[category].model) or 0
    UpdateCreatorClothingContextualDatas(selectedModel, category)
    NativeUpdatePedVariation(ped)
    return uiIndex
end

function UpdateCreatorClothingContextualDatas(value, category)
    category = tostring(category or "")
    if category == "bodies_upper" or category == "bodies_lower" then
        ContextualDataOn = false
        SendNUIMessage({ type = "hidecontextualDatas" })
        return
    end

    local current = CreatorClothesCache[category]
    local model = tonumber(value) or tonumber(current and current.model) or 0
    if model < 1 then
        ContextualDataOn = false
        SendNUIMessage({ type = "hidecontextualDatas" })
        return
    end

    local asset = getAsset(category, model)
    if not asset then
        ContextualDataOn = false
        SendNUIMessage({ type = "hidecontextualDatas" })
        return
    end

    local texture = current and current.texture or 1
    local variationValue = type(texture) == "table" and tonumber(texture.palette) or tonumber(texture) or 1
    local variationAmount = asset.drawable and #(asset.variants or {}) or #asset
    if variationAmount < 1 then variationAmount = 1 end
    variationValue = math.max(1, math.min(variationAmount, variationValue))

    if variationAmount <= 1 then
        ContextualDataOn = false
        SendNUIMessage({ type = "hidecontextualDatas" })
        return
    end

    -- Same native-colour chip picker as jrs_clothing's real store (and the
    -- barber "Style" control above): dedupe this drawable's variants by
    -- their real signature so visually-identical ones collapse into a
    -- single numbered chip. Only the discrete chip picker is added here -
    -- clothing still has no continuous RGB tint sliders, matching
    -- jrs_clothing's own live behaviour (it doesn't have those either).
    local colorOptions = {}
    if asset.drawable and type(asset.variants) == "table" then
        local seen = {}
        for uiIndex, variant in ipairs(asset.variants) do
            local vtint = variant.tint or { variant.tint0 or 0, variant.tint1 or 0, variant.tint2 or 0 }
            local signature = table.concat({
                tostring(variant.albedo or 0),
                tostring(variant.normal or 0),
                tostring(variant.material or 0),
                tostring(variant.palette or 0),
                tostring(vtint[1] or 0),
                tostring(vtint[2] or 0),
                tostring(vtint[3] or 0)
            }, ":")
            if not seen[signature] then
                seen[signature] = true
                table.insert(colorOptions, {
                    value = uiIndex,
                    realVariant = uiIndex,
                    selected = uiIndex == variationValue,
                })
            end
        end
    end

    SendNUIMessage({
        type = "contextualDatas",
        data = {
            contextual = "variation",
            category = category,
            variationAmount = variationAmount,
            variationValue = variationValue,
            actualColorOptions = colorOptions,
            nativeColor = #colorOptions > 1,
        }
    })
    ContextualDataOn = true
end

function OpenCreatorClothingMenu()
    StopCreatorBarberPins()
    local gender = getCreatorClothingGender()
    if not CreatorClothesInitialized or CreatorClothesGender ~= gender then
        ResetCreatorClothingCache(true)
    end

    CreatorOutfitMode = "clothing"
    ensureCreatorMPAssetIndices(gender)

    local categories = {}
    local items = {}
    local ped = CachePed or PlayerPedId()
    local genderAssets = JRS_CLOTHING_ASSETS and JRS_CLOTHING_ASSETS[gender] or {}
    local grouped = { head = {}, upper = {}, lower = {}, feets = {}, accs = {} }

    -- Remove old NPC-only or invalid selections from the preview/cache.
    for category, current in pairs(CreatorClothesCache or {}) do
        if category ~= "bodies_upper" and category ~= "bodies_lower" then
            local model = type(current) == "table" and tonumber(current.model) or 0
            if model and model > 0 and getCreatorMPUiIndex(category, model, "all") == 0 then
                removeCreatorClothingCategory(ped, category)
                CreatorClothesCache[category] = { model = 0, texture = 0 }
            end
        end
    end

    -- Reset Item restores only the selected garment to the state it had when
    -- the integrated clothing page was opened.
    CreatorClothesResetSnapshot = deepcopy(CreatorClothesCache or {})

    -- Discover every wearable MP category directly from the asset database.
    -- Unknown categories are kept under Accessories instead of being omitted.
    local discoveredCategories = {}
    for category in pairs(genderAssets) do
        local mpIndices = getCreatorMPIndices(category)
        local group = classifyCreatorClothingCategory(category)
        if group and type(mpIndices) == "table" and #mpIndices > 0 then
            local key = tostring(category)
            grouped[group][#grouped[group] + 1] = key
            discoveredCategories[key] = true
        end
    end

    -- Explicitly guarantee the complete player shirt, pants and boots lists.
    -- This is intentionally independent of the generic classifier so future
    -- category-map edits cannot remove these core wearable categories.
    for category, group in pairs(CreatorPrimaryPlayerCategories) do
        local mpIndices = getCreatorMPIndices(category)
        if #mpIndices > 0 and not discoveredCategories[category] then
            grouped[group][#grouped[group] + 1] = category
            discoveredCategories[category] = true
        end
    end

    -- Add Upper Body and Lower Body body mesh selectors to allow players to adjust their body for clothes
    local skinSet = getCreatorSkinSet()
    local bodyList = skinSet and skinSet.Body or {}
    local legList = skinSet and skinSet.Legs or {}

    if #bodyList > 0 and not discoveredCategories["bodies_upper"] then
        grouped["upper"][#grouped["upper"] + 1] = "bodies_upper"
        discoveredCategories["bodies_upper"] = true
    end

    if #legList > 0 and not discoveredCategories["bodies_lower"] then
        grouped["lower"][#grouped["lower"] + 1] = "bodies_lower"
        discoveredCategories["bodies_lower"] = true
    end

    for _, group in ipairs(CreatorClothingGroupOrder) do
        table.sort(grouped[group], function(a, b)
            local priorityA = CreatorCategoryPriority[a] or 100
            local priorityB = CreatorCategoryPriority[b] or 100
            if priorityA ~= priorityB then return priorityA < priorityB end
            return creatorCategoryLabel(a) < creatorCategoryLabel(b)
        end)

        if #grouped[group] > 0 then
            categories[#categories + 1] = {
                id = group,
                name = creatorCategoryLabel(group),
                image = ("./img/categories/%s_%s.png"):format(group, gender)
            }

            for _, category in ipairs(grouped[group]) do
                if category == "bodies_upper" then
                    local currentVal = tonumber(CachePedData.upperbody) or 1
                    CreatorClothesCache["bodies_upper"] = { model = currentVal, texture = 0 }
                    items[#items + 1] = {
                        id = "bodies_upper",
                        name = creatorCategoryLabel("bodies_upper"),
                        category = group,
                        min = 0,
                        totalAmount = #bodyList,
                        selectorType = "slider",
                        contextual = "none",
                        value = currentVal
                    }
                elseif category == "bodies_lower" then
                    local currentVal = tonumber(CachePedData.lowerbody) or 1
                    CreatorClothesCache["bodies_lower"] = { model = currentVal, texture = 0 }
                    items[#items + 1] = {
                        id = "bodies_lower",
                        name = creatorCategoryLabel("bodies_lower"),
                        category = group,
                        min = 0,
                        totalAmount = #legList,
                        selectorType = "slider",
                        contextual = "none",
                        value = currentVal
                    }
                else
                    CreatorClothesCache[category] = CreatorClothesCache[category] or { model = 0, texture = 0 }
                    local mpList = getCreatorModeIndices(category, "mp")
                    local npcList = getCreatorModeIndices(category, "npc")
                    local currentModel = tonumber(CreatorClothesCache[category].model) or 0
                    local mode = currentModel > 0 and creatorAssetMode(category, currentModel)
                        or CreatorClothingModes[category]
                    if mode ~= "mp" and mode ~= "npc" then mode = #mpList > 0 and "mp" or "npc" end
                    if mode == "mp" and #mpList == 0 then mode = "npc" end
                    if mode == "npc" and #npcList == 0 then mode = "mp" end
                    CreatorClothingModes[category] = mode
                    items[#items + 1] = {
                        id = category,
                        name = creatorCategoryLabel(category),
                        category = group,
                        totalAmount = mode == "npc" and #npcList or #mpList,
                        selectorType = "slider",
                        contextual = "variation",
                        clothingMode = mode,
                        mpCount = #mpList,
                        npcCount = #npcList,
                        value = getCreatorMPUiIndex(category, currentModel, mode)
                    }
                end
            end
        end
    end

    SendNUIMessage({
        type = "openOutfitMenu",
        title = _U('character_outfit_title_clothing'),
        mode = "clothing",
        categories = categories,
        items = items
    })
    FocusCreatorOutfitCategory(nil, nil, "clothing")
    StartCreatorClothingPins()
    JRSApplyNuiFocus(true, true, false)
end


-- Apply saved clothing to a character-selector ped synchronously.
-- The regular jrs_clothing event uses shared ClothesCache state and asynchronous
-- callbacks, which races when several preview peds are built at once. This
-- loader reads the same model/texture format but keeps all state local per ped.
local function applyPreviewCreatorClothingCategory(ped, gender, category, data)
    if not ped or ped == 0 or not DoesEntityExist(ped) or type(data) ~= "table" then return end

    local model = tonumber(data.model) or 0
    if model < 1 then return end

    local genderAssets = JRS_CLOTHING_ASSETS and JRS_CLOTHING_ASSETS[gender]
    local categoryAssets = genderAssets and genderAssets[tostring(category)]
    local asset = categoryAssets and categoryAssets[model]
    if type(asset) ~= "table" then return end

    local texture = data.texture
    if asset.drawable and type(asset.variants) == "table" then
        local paletteIndex = type(texture) == "table"
            and tonumber(texture.palette or texture.model)
            or tonumber(texture)
        paletteIndex = math.max(1, math.min(#asset.variants, paletteIndex or 1))
        local variant = asset.variants[paletteIndex]
        if not variant then return end

        local default0, default1, default2 = getVariantTint(variant)
        local tint0 = type(texture) == "table" and tonumber(texture.tint0) or default0
        local tint1 = type(texture) == "table" and tonumber(texture.tint1) or default1
        local tint2 = type(texture) == "table" and tonumber(texture.tint2) or default2
        UpdateCustomClothes(ped, asset.drawable, variant.albedo, variant.normal,
            variant.material, variant.palette, tint0 or default0, tint1 or default1, tint2 or default2)
        return
    end

    local variation = type(texture) == "table"
        and tonumber(texture.palette or texture.model)
        or tonumber(texture)
    variation = math.max(1, math.min(#asset, variation or 1))
    local variant = asset[variation]
    if not variant or not variant.hash then return end

    NativeSetPedComponentEnabled(ped, variant.hash, false, true, true)

    if type(texture) == "table" then
        local hasTint = texture.tint0 ~= nil or texture.tint1 ~= nil or texture.tint2 ~= nil
        if hasTint then
            local catHash = tonumber(category) or joaat(tostring(category))
            local timeout = 80
            while GetComponentIndexByCategory(ped, catHash) == -1 and timeout > 0 do
                Wait(0)
                timeout = timeout - 1
            end
            local componentIndex = GetComponentIndexByCategory(ped, catHash)
            if componentIndex and componentIndex >= 0 then
                local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                local palette, current0, current1, current2 = GetMetaPedAssetTint(ped, componentIndex)
                UpdateCustomClothes(ped, drawable, albedo, normal, material, palette,
                    tonumber(texture.tint0) or current0 or 0,
                    tonumber(texture.tint1) or current1 or 0,
                    tonumber(texture.tint2) or current2 or 0)
            end
        end
    end
end

-- 4.2.44: re-dress the creator ped after its body changes. MP garments
-- conform to the body mesh/shape only when they are (re)applied, so changing
-- body type, waist, upper/lower body or skin tone left the clothes still
-- shaped for the old body (clipping at the waist, wrists and thighs). Clothes
-- go back on inner -> outer, the same order jrs_clothing uses; the body is
-- never touched here, so skin tone stays exactly as chosen.
local CreatorReseatOrder = {
    "unionsuits_full", "unionsuit_legs", "shirts_full", "chemises", "corsets", "pants", "skirts", "dresses",
    "stockings", "knickers", "boots", "spats", "boot_accessories", "overalls_full", "overalls_modular_lowers",
    "overalls_modular_uppers", "vests", "suspenders", "coats", "coats_closed", "coats_heavy", "chaps",
    "neckwear", "neckties", "neckerchiefs", "gloves", "belts", "belt_buckles", "gunbelts", "holsters_right",
    "holsters_left", "satchels", "shawls", "cloaks", "ponchos", "capes",
}

function ReseatCreatorClothes(ped)
    ped = ped or CachePed or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) or type(CreatorClothesCache) ~= "table" then return end
    local worn = {}
    for category, data in pairs(CreatorClothesCache) do
        if category ~= "bodies_upper" and category ~= "bodies_lower" and type(data) == "table"
            and (tonumber(data.model) or 0) > 0 then
            worn[category] = data
        end
    end
    if next(worn) == nil then return end
    local gender = IsPedMale(ped) and "male" or "female"
    local done = {}
    for _, category in ipairs(CreatorReseatOrder) do
        if worn[category] then
            applyPreviewCreatorClothingCategory(ped, gender, category, worn[category])
            done[category] = true
        end
    end
    for category, data in pairs(worn) do
        if not done[category] then applyPreviewCreatorClothingCategory(ped, gender, category, data) end
    end
    NativeUpdatePedVariation(ped)
end

-- NPC garments were modelled on an NPC body: let jrs_clothing's smart fit pick
-- that body (skin tone kept), then put the clothes back on over it.
CreatorSmartBodyDrivers = {
    shirts_full = true, dresses = true, unionsuits_full = true, unionsuit_legs = true, overalls_full = true,
    overalls_modular_uppers = true, overalls_modular_lowers = true, coats_closed = true, coats = true,
    vests = true, pants = true, skirts = true,
}

function CreatorFitAndReseat(ped)
    ped = ped or CachePed or PlayerPedId()
    if GetResourceState("jrs_clothing") == "started" and type(CreatorClothesCache) == "table" then
        -- The body-shape / legs / skin-tone handlers put a new MP body on without
        -- telling jrs_clothing. Hand it the current base bodies first, or the fit
        -- would restore the previous body (and read the previous skin tone).
        local skinSet = getCreatorSkinSet()
        local upper = skinSet and skinSet.Body and skinSet.Body[tonumber(CachePedData and CachePedData.upperbody) or 1]
        local lower = skinSet and skinSet.Legs and skinSet.Legs[tonumber(CachePedData and CachePedData.lowerbody) or 1]
        if upper then TriggerEvent("jrs_clothes:Loadupperbody", tonumber("0x" .. upper)) end
        if lower then TriggerEvent("jrs_clothes:Loadlowerbody", tonumber("0x" .. lower)) end
        TriggerEvent("jrs_clothes:LoadBasSkin")
        -- Garments only: the creator keeps its MP body-shape slider values
        -- under bodies_upper/bodies_lower, which are not clothing.
        local garments = {}
        for category, data in pairs(CreatorClothesCache) do
            if category ~= "bodies_upper" and category ~= "bodies_lower" then garments[category] = data end
        end
        garments.shirts_full = garments.shirts_full or { model = 0, texture = 0 }
        pcall(function() exports.jrs_clothing:SmartBodyFitPed(ped, garments) end)
    end
    ReseatCreatorClothes(ped)
end

function ApplySavedClothingToPreviewPed(ped, clothesData, pedDataOverride)
    if not ped or ped == 0 or not DoesEntityExist(ped) or type(clothesData) ~= "table" then return false end

    -- Legacy characters can still carry component hashes instead of the
    -- jrs_clothing model/texture format. Preserve support for those rows.
    local hasCreatorFormat = false
    for _, value in pairs(clothesData) do
        if type(value) == "table" and value.model ~= nil then
            hasCreatorFormat = true
            break
        end
    end
    if not hasCreatorFormat then
        if type(LoadComps) == "function" then
            LoadComps(ped, clothesData, false)
            NativeUpdatePedVariation(ped)
            return true
        end
        return false
    end

    local hasAnyActiveItem = false
    for _, value in pairs(clothesData) do
        if type(value) == "table" and (tonumber(value.model) or 0) > 0 then
            hasAnyActiveItem = true
            break
        end
    end
    local gender = IsPedMale(ped) and "male" or "female"
    if not hasAnyActiveItem then
        local seed = tonumber(pedDataOverride and (pedDataOverride.charIdentifier or pedDataOverride.charid) or 0) or 1
        clothesData = GetDiverseStarterClothing(gender, seed)
    end
    local applied = {}
    local orderedCategories = {
        "cloaks", "ponchos", "capes", "coats", "shirts_full", "vests",
        "pants", "boots", "gunbelts", "belt_buckles", "gloves"
    }

    for _, category in ipairs(orderedCategories) do
        local value = clothesData[category]
        if value then
            applyPreviewCreatorClothingCategory(ped, gender, category, value)
            applied[category] = true
        end
    end

    for category, value in pairs(clothesData) do
        if not applied[category] and category ~= "bodies_upper" and category ~= "bodies_lower" then
            applyPreviewCreatorClothingCategory(ped, gender, category, value)
        end
    end

    -- Ensure base body meshes (upper & lower) are equipped if outer clothing does not cover them.
    -- Use pedDataOverride (per-character selector data) when provided so each preview ped
    -- resolves its own skintone/upperbody/lowerbody/head instead of the global CachePedData
    -- which only holds the currently active player's appearance.
    local pedData = (type(pedDataOverride) == "table" and pedDataOverride) or CachePedData
    local pdGender = nil
    if pedData then
        pdGender = (pedData.gender == "Female") and "Female" or "Male"
    end
    local equipped = GetCategoriesEquiped(ped)
    if tonumber(pedData and pedData.upperbody) == 0 then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x0B3966C9, 0)
    elseif not equipped[`bodies_upper`] then
        local upperHash = (gender == "male") and 0x206061DB or 0x206061DB
        if pedData and pdGender and pedData.upperbody and pedData.skintone and DefaultChar and DefaultChar[pdGender] then
            local sc = DefaultChar[pdGender][pedData.skintone]
            if sc and sc.Body and sc.Body[pedData.upperbody] then
                upperHash = tonumber("0x" .. sc.Body[pedData.upperbody])
            end
        end
        NativeSetPedComponentEnabled(ped, upperHash, false, true)
    end
    if tonumber(pedData and pedData.lowerbody) == 0 then
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x823687F5, 0)
    elseif not equipped[`bodies_lower`] then
        local lowerHash = (gender == "male") and 0x84BB6309 or 0x84BB6309
        if pedData and pdGender and pedData.lowerbody and pedData.skintone and DefaultChar and DefaultChar[pdGender] then
            local sc = DefaultChar[pdGender][pedData.skintone]
            if sc and sc.Legs and sc.Legs[pedData.lowerbody] then
                lowerHash = tonumber("0x" .. sc.Legs[pedData.lowerbody])
            end
        end
        NativeSetPedComponentEnabled(ped, lowerHash, false, true)
    end
    local headHash = nil
    if pedData and pdGender and pedData.skintone and DefaultChar and DefaultChar[pdGender] then
        local sc = DefaultChar[pdGender][pedData.skintone]
        if sc and sc.Heads then
            local headIndex = tonumber(pedData.head) or 1
            local hex = (sc.Heads[headIndex] and sc.Heads[headIndex] ~= "") and sc.Heads[headIndex]
                     or (sc.Heads[1] ~= "" and sc.Heads[1])
            if hex and hex ~= "" then
                headHash = tonumber("0x" .. hex)
            end
        end
    end
    if not headHash then
        headHash = (gender == "male") and 0xA0BE4A7B or 0x76ACA91E
    end
    NativeSetPedComponentEnabled(ped, headHash, false, true)

    -- jrs_clothing smart body fit: NPC garments get the body they were made
    -- for, same as the player gets after spawning. Skipped when the player
    -- chose a hidden body (0) or jrs_clothing isn't running.
    if tonumber(pedData and pedData.upperbody) ~= 0 and tonumber(pedData and pedData.lowerbody) ~= 0
        and GetResourceState("jrs_clothing") == "started" then
        NativeUpdatePedVariation(ped)
        pcall(function() exports.jrs_clothing:SmartBodyFitPed(ped, clothesData) end)
    end

    NativeUpdatePedVariation(ped)
    IsPedReadyToRender(ped)
    return true
end
end

-- ============================================================================
-- Module: appearance/editor.lua
-- ============================================================================
do
function Change(id, category, change_type, value)
    id = tonumber(id)
    -- These were globals, shared by every overlapping NUI callback coroutine:
    -- a fast second edit overwrote the first one's asset/tint mid-apply.
    local ped = MannequinPed or PlayerPedId()
    local drawable, albedo, normal, material, palette, tint0, tint1, tint2
    local gender
    if IsPedMale(ped) then gender = "male" else gender = "female" end
    if id < 1 then
        if category == "cloaks" or category == "ponchos" or category == "capes" then
            local categories = { "cloaks", "ponchos", "capes" }
            for k, v in pairs(categories) do
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, v, 0)
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(v), 0)
                local hexHash = v:match("0x[%x]+")
                local decimalHash = tonumber(hexHash)
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, decimalHash, 0)
                Citizen.InvokeNative(0xD710A5007C2AC539, ped, hexHash, true)
                NativeUpdatePedVariation(ped)
            end
        elseif category == "beard" then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0xF8016BCA, 0)
            NativeUpdatePedVariation(ped)
        elseif category == "hair" then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, 0x864B03AE, 0)
            NativeUpdatePedVariation(ped)
        else
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, category, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, GetHashKey(category), 0)
            local hexHash = category:match("0x[%x]+")
            local decimalHash = tonumber(hexHash)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, decimalHash, 0)
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, hexHash, true)
            NativeUpdatePedVariation(ped)
        end
        hairstyleCache[category].model = id
    else
        if change_type == "model" then
            hairstyleCache[category].model = id
            if JRS_ASSETS[gender][category][id].drawable then
                hairstyleCache[category].texture = {}
                local drawable = JRS_ASSETS[gender][category][id].drawable
                local firstVariant = JRS_ASSETS[gender][category][id].variants and JRS_ASSETS[gender][category][id].variants[1] or {}
                local albedo = firstVariant.albedo
                local normal = firstVariant.normal
                local material = firstVariant.material
                local palette = firstVariant.palette
                local vt = type(firstVariant.tint) == "table" and firstVariant.tint or {}
                local tint0 = tonumber(firstVariant.tint0 or vt[1]) or 0
                local tint1 = tonumber(firstVariant.tint1 or vt[2]) or 0
                local tint2 = tonumber(firstVariant.tint2 or vt[3]) or 0
                if BarberUsesHairTintPalette(category) then
                    palette = `metaped_tint_hair`
                    tint1 = tint0
                    tint2 = tint0
                end
                hairstyleCache[category].texture.palette = 1
                hairstyleCache[category].texture.tint0 = tint0
                hairstyleCache[category].texture.tint1 = tint1
                hairstyleCache[category].texture.tint2 = tint2
                UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                if CreatorConfig.DevMode then
                    SendNUIMessage({
                        type = 'clipboard',
                        data = "moveAsset " ..
                            gender .. " " .. category .. " " .. JRS_ASSETS[gender][category][id].drawable
                    })
                    CreatorDebug("Clipboard",
                        "moveAsset " .. gender .. " " .. category .. " " .. JRS_ASSETS[gender][category][id].drawable)
                end
            else
                hairstyleCache[category].texture = 1
                NativeSetPedComponentEnabled(ped, JRS_ASSETS[gender][category][id][1].hash, false, true,
                    true)
            end
        else
            if JRS_ASSETS[gender][category][hairstyleCache[category].model].drawable then
                drawable = JRS_ASSETS[gender][category][hairstyleCache[category].model].drawable
                local assetVariants = JRS_ASSETS[gender][category][hairstyleCache[category].model].variants or {}
                if change_type ~= "variants" then
                    local curPalette = 1
                    if type(hairstyleCache[category].texture) == "table" then
                        curPalette = tonumber(hairstyleCache[category].texture.palette or hairstyleCache[category].texture.model) or 1
                    else
                        curPalette = tonumber(hairstyleCache[category].texture) or 1
                    end
                    local currentVariant = assetVariants[curPalette] or assetVariants[1] or {}
                    albedo = currentVariant.albedo
                    normal = currentVariant.normal
                    material = currentVariant.material
                    palette = currentVariant.palette
                end
                if change_type == "variants" then
                    local varIdx = math.max(1, math.floor(tonumber(value) or 1))
                    local selectedVariant = assetVariants[varIdx] or assetVariants[1] or {}
                    albedo = selectedVariant.albedo
                    normal = selectedVariant.normal
                    material = selectedVariant.material
                    palette = selectedVariant.palette
                    local vt = type(selectedVariant.tint) == "table" and selectedVariant.tint or {}
                    tint0 = tonumber(selectedVariant.tint0 or vt[1]) or 0
                    tint1 = tonumber(selectedVariant.tint1 or vt[2]) or 0
                    tint2 = tonumber(selectedVariant.tint2 or vt[3]) or 0
                    if BarberUsesHairTintPalette(category) then
                        palette = `metaped_tint_hair`
                        tint1 = tint0
                        tint2 = tint0
                    end

                    if type(hairstyleCache[category].texture) ~= "table" then
                        hairstyleCache[category].texture = {}
                    end
                    hairstyleCache[category].texture.palette = varIdx
                    hairstyleCache[category].texture.tint0 = tint0
                    hairstyleCache[category].texture.tint1 = tint1
                    hairstyleCache[category].texture.tint2 = tint2
                elseif change_type == 1 then
                    if type(hairstyleCache[category].texture) ~= "table" then hairstyleCache[category].texture = {} end
                    hairstyleCache[category].texture.tint0 = value
                    tint0 = value
                    if BarberUsesHairTintPalette(category) and not hairstyleCache[category].texture.custom_tint1 then
                        hairstyleCache[category].texture.tint1 = value
                    end
                    if BarberUsesHairTintPalette(category) and not hairstyleCache[category].texture.custom_tint2 then
                        hairstyleCache[category].texture.tint2 = value
                    end
                    tint1 = tonumber(hairstyleCache[category].texture.tint1) or value
                    tint2 = tonumber(hairstyleCache[category].texture.tint2) or value
                elseif change_type == 2 then
                    if type(hairstyleCache[category].texture) ~= "table" then hairstyleCache[category].texture = {} end
                    hairstyleCache[category].texture.tint1 = value
                    hairstyleCache[category].texture.custom_tint1 = true
                    tint0 = tonumber(hairstyleCache[category].texture.tint0) or 0
                    tint1 = value
                    tint2 = tonumber(hairstyleCache[category].texture.tint2) or tint0
                elseif change_type == 3 then
                    if type(hairstyleCache[category].texture) ~= "table" then hairstyleCache[category].texture = {} end
                    hairstyleCache[category].texture.tint2 = value
                    hairstyleCache[category].texture.custom_tint2 = true
                    tint0 = tonumber(hairstyleCache[category].texture.tint0) or 0
                    tint1 = tonumber(hairstyleCache[category].texture.tint1) or tint0
                    tint2 = value
                end
                if BarberUsesHairTintPalette(category) then
                    palette = `metaped_tint_hair`
                end
                UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
            else
                local catHash


                if category == "beard" then
                    catHash = -134124598
                else
                    if type(category) ~= "number" then
                        catHash = joaat(category)
                    else
                        catHash = category
                    end
                end
                if change_type == "variants" then
                    hairstyleCache[category].texture = value
                    NativeSetPedComponentEnabled(ped,
                        JRS_ASSETS[gender][category][hairstyleCache[category].model][value].hash, false, true, true)
                elseif change_type == 1 then
                    if type(hairstyleCache[category].texture) == "table" then
                        do local waitUntil = GetGameTimer() + 2000 while GetComponentIndexByCategory(ped, catHash) == -1 and GetGameTimer() < waitUntil do Wait(0) end end if GetComponentIndexByCategory(ped, catHash) == -1 then return end
                        local componentIndex = GetComponentIndexByCategory(ped, catHash)
                        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                        local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                        hairstyleCache[category].texture.tint0 = value
                        tint0 = value
                        if BarberUsesHairTintPalette(category) and not hairstyleCache[category].texture.custom_tint1 then
                            hairstyleCache[category].texture.tint1 = value
                        end
                        if BarberUsesHairTintPalette(category) and not hairstyleCache[category].texture.custom_tint2 then
                            hairstyleCache[category].texture.tint2 = value
                        end
                        tint1 = tonumber(hairstyleCache[category].texture.tint1) or value
                        tint2 = tonumber(hairstyleCache[category].texture.tint2) or value
                        palette = `metaped_tint_hair`
                        UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                    else
                        local model = hairstyleCache[category].texture
                        hairstyleCache[category].texture = {}
                        hairstyleCache[category].texture.model = model
                        do local waitUntil = GetGameTimer() + 2000 while GetComponentIndexByCategory(ped, catHash) == -1 and GetGameTimer() < waitUntil do Wait(0) end end if GetComponentIndexByCategory(ped, catHash) == -1 then return end
                        local componentIndex = GetComponentIndexByCategory(ped, catHash)
                        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                        local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                        tint0 = value
                        tint1 = value
                        tint2 = value
                        hairstyleCache[category].texture.tint0 = tint0
                        hairstyleCache[category].texture.tint1 = tint1
                        hairstyleCache[category].texture.tint2 = tint2
                        palette = `metaped_tint_hair`
                        UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                    end
                elseif change_type == 2 then
                    if type(hairstyleCache[category].texture) == "table" then
                        do local waitUntil = GetGameTimer() + 2000 while GetComponentIndexByCategory(ped, catHash) == -1 and GetGameTimer() < waitUntil do Wait(0) end end if GetComponentIndexByCategory(ped, catHash) == -1 then return end
                        local componentIndex = GetComponentIndexByCategory(ped, catHash)
                        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                        local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                        hairstyleCache[category].texture.tint1 = value
                        tint0 = hairstyleCache[category].texture.tint0
                        tint1 = value
                        tint2 = hairstyleCache[category].texture.tint2
                        palette = `metaped_tint_hair`
                        UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                    else
                        local model = hairstyleCache[category].texture
                        hairstyleCache[category].texture = {}
                        hairstyleCache[category].texture.model = model
                        do local waitUntil = GetGameTimer() + 2000 while GetComponentIndexByCategory(ped, catHash) == -1 and GetGameTimer() < waitUntil do Wait(0) end end if GetComponentIndexByCategory(ped, catHash) == -1 then return end
                        local componentIndex = GetComponentIndexByCategory(ped, catHash)
                        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                        local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                        tint1 = value
                        hairstyleCache[category].texture.tint0 = tint0
                        hairstyleCache[category].texture.tint1 = tint1
                        hairstyleCache[category].texture.tint2 = tint2
                        palette = `metaped_tint_hair`
                        UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                    end
                elseif change_type == 3 then
                    if type(hairstyleCache[category].texture) == "table" then
                        do local waitUntil = GetGameTimer() + 2000 while GetComponentIndexByCategory(ped, catHash) == -1 and GetGameTimer() < waitUntil do Wait(0) end end if GetComponentIndexByCategory(ped, catHash) == -1 then return end
                        local componentIndex = GetComponentIndexByCategory(ped, catHash)
                        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                        local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                        hairstyleCache[category].texture.tint2 = value
                        tint0 = hairstyleCache[category].texture.tint0
                        tint1 = hairstyleCache[category].texture.tint1
                        tint2 = value
                        palette = `metaped_tint_hair`
                        UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                    else
                        local model = hairstyleCache[category].texture
                        hairstyleCache[category].texture = {}
                        hairstyleCache[category].texture.model = model
                        do local waitUntil = GetGameTimer() + 2000 while GetComponentIndexByCategory(ped, catHash) == -1 and GetGameTimer() < waitUntil do Wait(0) end end if GetComponentIndexByCategory(ped, catHash) == -1 then return end
                        local componentIndex = GetComponentIndexByCategory(ped, catHash)
                        local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, componentIndex)
                        local palette, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, componentIndex)
                        tint2 = value
                        hairstyleCache[category].texture.tint0 = tint0
                        hairstyleCache[category].texture.tint1 = tint1
                        hairstyleCache[category].texture.tint2 = tint2
                        palette = `metaped_tint_hair`
                        UpdateCustomhairstyle(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
                    end
                end
            end
        end
    end
end


function UpdateCustomhairstyle(playerPed, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    local componentDeadline = GetGameTimer() + 5000
    while not NativeHasPedComponentLoaded(playerPed) and GetGameTimer() < componentDeadline do
        CreatorDebug("Waiting for ped component to load...")
        Wait(0)
    end
    if not NativeHasPedComponentLoaded(playerPed) then
        CreatorDebug("^3[jrs_character] UpdateCustomhairstyle: ped component never reported loaded within 5s, continuing.^7")
    end
    local _drawable = tonumber(drawable)
    local _albedo = tonumber(albedo)
    local _normal = tonumber(normal)
    local _material = tonumber(material)
    local _palette = tonumber(palette)
    local _tint0 = tonumber(tint0)
    local _tint1 = tonumber(tint1)
    local _tint2 = tonumber(tint2)
    SetMetaPedTag(playerPed, _drawable, _albedo, _normal, _material, _palette, _tint0, _tint1, _tint2)
    UpdatePedVariation(playerPed)
end


function GetComponentIndexByCategory(ped, category)
    local numComponents = GetNumComponentsInPed(ped)
    for i = 0, numComponents - 1, 1 do
        local componentCategory = GetCategoryOfComponentAtIndex(ped, i)
        if componentCategory == category then
            return i
        end
    end
end

function GetNumComponentsInPed(ped)
    return Citizen.InvokeNative(0x90403E8107B60E81, ped, Citizen.ResultAsInteger())
end

function NativeGetPedComponentCategory(isFemale, componentHash)
    return Citizen.InvokeNative(0x5FF9A878C3D115B8, componentHash, isFemale, true)
end

function NativeSetPedComponentEnabled(ped, componentHash, immediately, isMp)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not componentHash then return false end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, immediately == true, isMp ~= false, true)
    NativeFixMeshIssues(ped)
    NativeUpdatePedVariation(ped)
    return true
end

function NativeFixMeshIssues(ped, categoryHash)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, 1)
end


function IsPedReadyToRender(ped)
    local renderDeadline = GetGameTimer() + 5000
    repeat Wait(0) until Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped or PlayerPedId()) or GetGameTimer() >= renderDeadline
    if not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped or PlayerPedId()) then
        CreatorDebug("^3[jrs_character] IsPedReadyToRender: ped never reported ready within 5s, continuing.^7")
    end
end


function SetCharExpression(ped, value, expression)
    Citizen.InvokeNative(0x5653AB26C82938CF, ped, value, expression)
end


function GetCategoryOfComponentAtIndex(ped, componentIndex)
    return Citizen.InvokeNative(0x9b90842304c938a7, ped, componentIndex, 0, Citizen.ResultAsInteger())
end

function GetMetaPedAssetGuids(ped, index)
    return Citizen.InvokeNative(0xA9C28516A6DC9D56, ped, index, Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

function GetMetaPedAssetTint(ped, index)
    return Citizen.InvokeNative(0xE7998FEC53A33BBE, ped, index, Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt())
end

function UpdateCustomClothes(playerPed, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    local componentDeadline = GetGameTimer() + 5000
    while not NativeHasPedComponentLoaded(playerPed) and GetGameTimer() < componentDeadline do
        Wait(0)
    end
    if not NativeHasPedComponentLoaded(playerPed) then
        CreatorDebug("^3[jrs_character] UpdateCustomClothes: ped component never reported loaded within 5s, continuing.^7")
    end
    local _drawable = drawable
    local _albedo = albedo
    local _normal = normal
    local _material = material
    local _palette = palette
    local _tint0 = tonumber(tint0)
    local _tint1 = tonumber(tint1)
    local _tint2 = tonumber(tint2)

    SetMetaPedTag(playerPed, _drawable, _albedo, _normal, _material, _palette, _tint0, _tint1, _tint2)
    UpdatePedVariation(playerPed)
end

function SetMetaPedTag(ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
    Citizen.InvokeNative(0xBC6DF00D7A4A6819, ped, drawable, albedo, normal, material, palette, tint0, tint1, tint2)
end
function UpdatePedVariation(ped)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true) -- UNKNOWN "Fixes outfit"- always paired with _UPDATE_PED_VARIATION
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false) -- _UPDATE_PED_VARIATION
end


function IsMetaPedUsingComponentCategory(ped, componentCategory)
    return Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, componentCategory)
end


function UpdateShopItemWearableState(ped, shopItemHash, wearableStateHash, isMultiplayer)
    Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, shopItemHash, wearableStateHash, 0, isMultiplayer, 1)
end

function NativeUpdatePedVariation(ped)
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true) -- UNKNOWN "Fixes outfit"- always paired with _UPDATE_PED_VARIATION
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    local componentDeadline = GetGameTimer() + 5000
    while not NativeHasPedComponentLoaded(ped) and GetGameTimer() < componentDeadline do
        Wait(1)
    end
    if not NativeHasPedComponentLoaded(ped) then
        CreatorDebug("^3[jrs_character] NativeUpdatePedVariation: ped component never reported loaded within 5s, continuing.^7")
    end
end

function NativeHasPedComponentLoaded(ped)
    return Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
end

function ApplyShopItemToPed(comp, ped)
    if not comp or comp == 0 then return end
    ped = ped or PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, comp, false, true, true)
    Citizen.InvokeNative(0x59BD177A1A48600A, ped, 1)
end

function EquipMetaPedOutfit(hash, ped)
    Citizen.InvokeNative(0x1902C4CFCC5BE57C, ped or PlayerPedId(), hash)
end
end

-- ============================================================================
-- Module: aging/effects.lua
-- ============================================================================
do
-- Optional playtime-age appearance and movement effects.
-- Effects are applied at runtime and never overwrite the saved barber data.

local currentAge = nil
local currentStage = nil
local lastAppliedPed = 0
local visualEffectApplied = false
local movementRate = 1.0
local applyToken = 0
local agingSourceHair = {}
local agingSourceLayers = {}
local agingSourceAlbedo = nil
local agingHairEnforcementUntil = 0
local lastAgingRuntimeRepair = 0

local function cloneTable(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[cloneTable(key, seen)] = cloneTable(item, seen)
    end
    return copy
end

-- Character height is owned by jrs_admin: the admin menu and the gold store
-- are the only two places that may set it, and the value lives in
-- jrs_admin_character_scale. The age pass below re-equips metaped components
-- (RemoveAllBarber / ReequipAllhairstyle / SetMetaPedTag / UpdatePedVariation),
-- and RedM drops the ped back to the engine's default scale of 1.0 whenever it
-- does. Without this, a character aging one year silently snapped to the
-- default height - taller for anyone whose bought/granted height was below 1.0.
-- Re-assert the authoritative height after every age pass on the PLAYER ped.
-- Selector preview peds never come through here.
local function restoreAuthoritativeScale()
    if type(JRSApplyCachedPlayerScale) ~= 'function' then return false end
    local ok, applied = pcall(JRSApplyCachedPlayerScale)
    return ok and applied == true
end

local function effectsConfig()
    return type(Config) == 'table' and type(Config.AgingEffects) == 'table' and Config.AgingEffects or nil
end

local function effectsEnabled()
    local cfg = effectsConfig()
    return cfg ~= nil and cfg.Enabled == true and tostring(Config.AgingMode or ''):lower() == 'playtime'
end

local function getStageForAge(age)
    if not effectsEnabled() then return nil end
    age = tonumber(age)
    if not age then return nil end

    local stages = effectsConfig().Stages
    if type(stages) ~= 'table' then return nil end

    for index, stage in ipairs(stages) do
        local minimum = tonumber(stage.MinAge) or 0
        local maximum = tonumber(stage.MaxAge)
        if age >= minimum and (maximum == nil or age <= maximum) then
            local result = cloneTable(stage)
            result._index = index
            return result
        end
    end
    return nil
end

local function stageKey(stage)
    if type(stage) ~= 'table' then return 'none' end
    return table.concat({
        tostring(stage._index or ''),
        tostring(stage.HairTint or ''),
        tostring(stage.BeardTint or ''),
        tostring(stage.WrinkleTexture or ''),
        tostring(stage.WrinkleOpacity or ''),
        tostring(stage.MovementRate or ''),
    }, ':')
end

local function categoryTint(category, stage)
    local cfg = effectsConfig()
    if not cfg or not stage then return nil end

    local hair = type(cfg.Hair) == 'table' and cfg.Hair or {}
    if hair.Enabled == true and type(hair.Categories) == 'table' and hair.Categories[category] == true then
        return tonumber(stage.HairTint)
    end

    local beard = type(cfg.Beard) == 'table' and cfg.Beard or {}
    if beard.Enabled == true and type(beard.Categories) == 'table' and beard.Categories[category] == true then
        return tonumber(stage.BeardTint)
    end

    return nil
end

local function buildAgedHairstyle(source, stage)
    local result = cloneTable(type(source) == 'table' and source or {})
    for category, data in pairs(result) do
        local tint = categoryTint(category, stage)
        if tint ~= nil and type(data) == 'table' then
            if type(data.texture) ~= 'table' then
                data.texture = { model = tonumber(data.texture) or 1 }
            end
            tint = math.max(0, math.min(255, math.floor(tint)))
            data.texture.tint0 = tint
            data.texture.tint1 = tint
            data.texture.tint2 = tint
        end
    end
    return result
end

local function componentCategoryHash(category)
    if category == 'beard' then
        return -134124598
    end
    if type(category) == 'number' then
        return category
    end
    return joaat(category)
end

local function forceCategoryTint(ped, category, tint)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    tint = tonumber(tint)
    if not tint then return false end
    tint = math.max(0, math.min(255, math.floor(tint)))

    local index = GetComponentIndexByCategory(ped, componentCategoryHash(category))
    if index == nil or index == -1 then return false end

    local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, index)
    if not drawable or tonumber(drawable) == 0 then return false end

    -- Always use the dedicated hair tint palette here.
    SetMetaPedTag(
        ped,
        tonumber(drawable),
        tonumber(albedo),
        tonumber(normal),
        tonumber(material),
        `metaped_tint_hair`,
        tint,
        tint,
        tint
    )
    return true
end

local function forceAgedTintsOnPed(ped, source, stage)
    if type(source) ~= 'table' or type(stage) ~= 'table' then return false end
    local changed = false

    for category, data in pairs(source) do
        local tint = categoryTint(category, stage)
        if tint ~= nil and type(data) == 'table' and tonumber(data.model or 0) > 0 then
            if forceCategoryTint(ped, category, tint) then
                changed = true
            end
        end
    end

    if changed then
        NativeUpdatePedVariation(ped)
    end
    return changed
end

local function restoreNaturalTintsOnPed(ped, source)
    if not ped or ped == 0 or not DoesEntityExist(ped) or type(source) ~= 'table' then return false end
    local changed = false

    for category, data in pairs(source) do
        local isHair = false
        if type(BarberUsesHairTintPalette) == 'function' then
            isHair = BarberUsesHairTintPalette(category)
        else
            local catStr = tostring(category or '')
            isHair = catStr == 'hair' or catStr == 'hairstabble' or catStr == 'hair_bonnet'
                or catStr == 'beard' or catStr == 'beardstabble' or catStr == 'beards_complete'
                or catStr == 'beards_chin' or catStr == 'beards_chops' or catStr == 'beards_mustache'
        end
        if isHair and type(data) == 'table' and tonumber(data.model or 0) > 0 then
            local index = GetComponentIndexByCategory(ped, componentCategoryHash(category))
            if index ~= nil and index ~= -1 then
                local drawable, albedo, normal, material = GetMetaPedAssetGuids(ped, index)
                if drawable and tonumber(drawable) ~= 0 then
                    local tint0 = 0
                    local tint1 = 0
                    local tint2 = 0
                    if type(data.texture) == 'table' then
                        tint0 = tonumber(data.texture.tint0) or 0
                        tint1 = tonumber(data.texture.tint1) or 0
                        tint2 = tonumber(data.texture.tint2) or 0
                    end
                    SetMetaPedTag(
                        ped,
                        tonumber(drawable),
                        tonumber(albedo),
                        tonumber(normal),
                        tonumber(material),
                        `metaped_tint_hair`,
                        tint0,
                        tint1,
                        tint2
                    )
                    changed = true
                end
            end
        end
    end

    if changed then
        NativeUpdatePedVariation(ped)
    end
    return changed
end

local function runtimeEnforcementConfig()
    local cfg = effectsConfig()
    return cfg and type(cfg.RuntimeEnforcement) == 'table' and cfg.RuntimeEnforcement or {}
end

local function beginAgingHairEnforcement(durationMs)
    local runtime = runtimeEnforcementConfig()
    if runtime.Enabled ~= true then return end

    local duration = tonumber(durationMs) or tonumber(runtime.SpawnDurationMs) or 20000
    duration = math.max(1000, math.floor(duration))
    agingHairEnforcementUntil = math.max(agingHairEnforcementUntil, GetGameTimer() + duration)
end

local function categoryHasExpectedTint(ped, category, expectedTint)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    local index = GetComponentIndexByCategory(ped, componentCategoryHash(category))
    if index == nil or index == -1 then return false end

    local _, tint0, tint1, tint2 = GetMetaPedAssetTint(ped, index)
    local expected = math.max(0, math.min(255, math.floor(tonumber(expectedTint) or 0)))

    return tonumber(tint0) == expected
        and tonumber(tint1) == expected
        and tonumber(tint2) == expected
end

local function agedHairNeedsRepair(ped, source, stage)
    if type(source) ~= 'table' or type(stage) ~= 'table' then return false end

    for category, data in pairs(source) do
        local tint = categoryTint(category, stage)
        if tint ~= nil and type(data) == 'table' and tonumber(data.model or 0) > 0 then
            if not categoryHasExpectedTint(ped, category, tint) then
                return true
            end
        end
    end

    return false
end

local function applyHairstyleToPed(ped, source, stage)
    if type(source) ~= 'table' or next(source) == nil then return false end
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    -- Smoothly apply tints directly without removing hair components to eliminate flickering/hair loss
    if stage ~= nil then
        if forceAgedTintsOnPed(ped, source, stage) then
            return true
        end
    else
        if restoreNaturalTintsOnPed(ped, source) then
            return true
        end
    end

    -- Fallback: if components are not yet present on the ped, equip them
    if type(ReequipAllhairstyle) ~= 'function' then return false end

    local previousCache = barberCache
    barberCache = buildAgedHairstyle(source, stage)

    local ok, err = pcall(function()
        ReequipAllhairstyle(ped)
        if stage then
            forceAgedTintsOnPed(ped, source, stage)
        end
    end)

    barberCache = previousCache
    if not ok and Config.Debug then
        print(('[jrs_character] Aging hairstyle error: %s'):format(tostring(err)))
    end
    return ok
end

local function mergeSavedLayers(savedMakeup, savedPermanent)
    local layers = cloneTable(type(baseoverlay) == 'table' and baseoverlay or {})
    local function merge(source)
        for _, saved in pairs(type(source) == 'table' and source or {}) do
            if type(saved) == 'table' and saved.name then
                for _, layer in pairs(layers) do
                    if layer.name == saved.name then
                        for field, value in pairs(saved) do layer[field] = value end
                        break
                    end
                end
            end
        end
    end
    merge(savedMakeup)
    merge(savedPermanent)
    return layers
end

local function buildAgedOverlayLayers(source, stage)
    local layers = cloneTable(type(source) == 'table' and source or {})
    local cfg = effectsConfig()
    local wrinkles = cfg and type(cfg.Wrinkles) == 'table' and cfg.Wrinkles or {}
    local opacity = stage and tonumber(stage.WrinkleOpacity) or 0.0

    if wrinkles.Enabled ~= true or opacity <= 0.0 then
        return layers
    end

    local ageingInfo = type(overlays_info) == 'table' and overlays_info.ageing or nil
    local textureIndex = math.floor(tonumber(stage.WrinkleTexture) or 2)
    if type(ageingInfo) ~= 'table' or #ageingInfo == 0 then return layers end
    textureIndex = math.max(1, math.min(#ageingInfo, textureIndex))
    local texture = ageingInfo[textureIndex]
    if type(texture) ~= 'table' then return layers end

    for _, layer in pairs(layers) do
        if layer.name == 'ageing' then
            layer.visibility = 1
            layer.tx_id = texture.id or layer.tx_id

            -- Ageing overlays are non-palette overlays. Using color type 0 here
            -- applies a palette to the whole head and causes the face/body skin
            -- mismatch. Type 1 preserves the original skin albedo and adds only
            -- the ageing texture details.
            layer.tx_normal = 0
            layer.tx_material = 0
            layer.tx_color_type = 1
            layer.tx_opacity = 1.0
            layer.tx_unk = 0
            layer.palette = 0
            layer.palette_color_primary = 0
            layer.palette_color_secondary = 0
            layer.palette_color_tertiary = 0
            layer.var = 0
            layer.opacity = math.max(0.0, math.min(1.0, opacity))
            break
        end
    end
    return layers
end

local function applyOverlayToPed(ped, source, stage, albedo)
    if type(UpdateOverlay) ~= 'function' or type(source) ~= 'table' then return false end
    local layers = buildAgedOverlayLayers(source, stage)
    local ok, err = pcall(function()
        UpdateOverlay(ped, layers, albedo)
    end)
    if not ok and Config.Debug then
        print(('[jrs_character] Aging overlay error: %s'):format(tostring(err)))
    end
    return ok
end

local function savedPlayerOverlayLayers()
    if type(barber_overlay_all_layers) == 'table' and next(barber_overlay_all_layers) ~= nil then
        return barber_overlay_all_layers
    end
    if type(overlay_all_layers) == 'table' and next(overlay_all_layers) ~= nil then
        return overlay_all_layers
    end
    return type(baseoverlay) == 'table' and baseoverlay or {}
end

local function applyCurrentVisualEffects(force)
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return false end

    local stage = getStageForAge(currentAge)
    local samePed = lastAppliedPed == ped
    local sameStage = currentStage and stage and stageKey(currentStage) == stageKey(stage)
        or (currentStage == nil and stage == nil)

    if not force and samePed and sameStage then return true end

    currentStage = stage
    lastAppliedPed = ped

    local sourceHair = type(agingSourceHair) == 'table' and agingSourceHair or {}
    if next(sourceHair) == nil and type(barberCache) == 'table' then
        sourceHair = cloneTable(barberCache)
    end

    local sourceLayers = type(agingSourceLayers) == 'table' and agingSourceLayers or {}
    if next(sourceLayers) == nil then
        sourceLayers = cloneTable(savedPlayerOverlayLayers())
    end

    local sourceAlbedo = agingSourceAlbedo or Actualalbedo

    -- Reapplying the clean saved source with a nil stage restores the original
    -- hairstyle. Wrinkles are only rebuilt when a stage actually requests them.
    local cfg = effectsConfig()
    local hasHairAging = cfg and ((cfg.Hair and cfg.Hair.Enabled == true) or (cfg.Beard and cfg.Beard.Enabled == true))
    if hasHairAging and next(sourceHair) ~= nil then
        applyHairstyleToPed(ped, sourceHair, stage)
    end
    if stage and next(sourceLayers) ~= nil then
        applyOverlayToPed(ped, sourceLayers, stage, sourceAlbedo)
    end

    restoreAuthoritativeScale()

    visualEffectApplied = stage ~= nil
    movementRate = stage and tonumber(stage.MovementRate) or 1.0
    movementRate = math.max(0.1, math.min(1.0, movementRate))
    return true
end

function JRSForceCurrentAgingAppearance(startEnforcement)
    if startEnforcement == true then
        beginAgingHairEnforcement()
    end
    return applyCurrentVisualEffects(true)
end

local function scheduleApply(delay, force)
    applyToken = applyToken + 1
    local token = applyToken
    SetTimeout(math.max(0, tonumber(delay) or 0), function()
        if token ~= applyToken then return end
        applyCurrentVisualEffects(force == true)
    end)
end

-- Used by selector preview peds after their saved barber data is loaded.
function JRSApplyAgingToPreviewPed(ped, barberData, pedData, age)
    local cfg = effectsConfig()
    if not cfg or cfg.Enabled ~= true or cfg.PreviewInCharacterSelector ~= true then return false end
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end

    local stage = getStageForAge(age)
    if not stage then return false end

    barberData = type(barberData) == 'table' and barberData or {}
    local hairstyle = type(barberData.hairstyle) == 'table' and barberData.hairstyle or {}
    local hasHairAging = (cfg.Hair and cfg.Hair.Enabled == true) or (cfg.Beard and cfg.Beard.Enabled == true)
    if hasHairAging and next(hairstyle) ~= nil then
        applyHairstyleToPed(ped, hairstyle, stage)
    end

    local layers = mergeSavedLayers(barberData.overlays, barberData.permanentoverlay)
    local albedo = nil
    pedData = type(pedData) == 'table' and pedData or {}
    local gender = pedData.gender == 'Female' and 'Female' or 'Male'
    local skinTone = tonumber(pedData.skintone) or 1
    local skinSet = type(DefaultChar) == 'table' and DefaultChar[gender] and DefaultChar[gender][skinTone]
    if skinSet and skinSet.HeadTexture and skinSet.HeadTexture[1] then
        albedo = joaat(skinSet.HeadTexture[1])
    end
    applyOverlayToPed(ped, layers, stage, albedo)
    return true
end

local function applyNowWithFastRetries()
    -- First pass is synchronous. Runtime enforcement then watches the final
    -- barber/clothing callbacks and immediately repairs any restored natural tint.
    beginAgingHairEnforcement()
    applyToken = applyToken + 1
    applyCurrentVisualEffects(true)
    local token = applyToken
    CreateThread(function()
        Wait(200)
        if token ~= applyToken then return end
        applyCurrentVisualEffects(true)
        Wait(650)
        if token ~= applyToken then return end
        applyCurrentVisualEffects(true)
    end)
end

RegisterNetEvent('jrs_character:agingPlayerAppearanceReady', function(age, hair, layers, albedo)
    currentAge = tonumber(age) or currentAge
    agingSourceHair = cloneTable(type(hair) == 'table' and hair or {})
    agingSourceLayers = cloneTable(type(layers) == 'table' and layers or {})
    agingSourceAlbedo = tonumber(albedo) or albedo
    applyNowWithFastRetries()
end)

RegisterNetEvent('jrs_character:agingAppearanceReady', function(hair, layers, albedo)
    agingSourceHair = cloneTable(type(hair) == 'table' and hair or {})
    agingSourceLayers = cloneTable(type(layers) == 'table' and layers or {})
    agingSourceAlbedo = tonumber(albedo) or albedo
    applyNowWithFastRetries()
end)

RegisterNetEvent('jrs_character:ageUpdated', function(data)
    data = type(data) == 'table' and data or {}
    local newAge = tonumber(data.age) or currentAge
    currentAge = newAge

    -- Do not rebuild or reload character skin/appearance live during gameplay.
    -- Appearance is updated on player exit & enter (spawn/reconnect) or when the player manually runs /rc.
end)

RegisterNetEvent('jrs_character_creator:FinalizeCharacter', function(payload)
    payload = type(payload) == 'table' and payload or {}
    currentAge = tonumber(payload.age) or currentAge
    beginAgingHairEnforcement()
    scheduleApply(0, true)
end)

AddEventHandler('jrs_character:isPlayerReady', function()
    TriggerServerEvent('jrs_character:requestAgeSnapshot')
    beginAgingHairEnforcement()
    applyNowWithFastRetries()
end)

AddEventHandler('jrs_character_creator:loadbarberoverlay', function()
    -- This event starts before the asynchronous barber callback completes.
    -- Keep the enforcement window open so the final saved hair load cannot
    -- permanently overwrite the age tint.
    beginAgingHairEnforcement()
    scheduleApply(0, true)
end)

AddEventHandler('jrs_character_creator:appearanceReloadFinished', function(success)
    if success ~= false then
        beginAgingHairEnforcement()
        applyNowWithFastRetries()
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetTimeout(3500, function()
        TriggerServerEvent('jrs_character:requestAgeSnapshot')
    end)
end)

-- A separate barber resource can reload the saved natural hair after the
-- selected-character event. During the short spawn window, detect that reset
-- and repair the complete age appearance without waiting for the five-minute age save.
CreateThread(function()
    while true do
        local runtime = runtimeEnforcementConfig()
        local interval = math.max(50, math.floor(tonumber(runtime.CheckIntervalMs) or 100))

        if runtime.Enabled == true and GetGameTimer() < agingHairEnforcementUntil then
            Wait(interval)

            local ped = PlayerPedId()
            local stage = getStageForAge(currentAge)
            local sourceHair = type(agingSourceHair) == 'table' and agingSourceHair or {}

            if ped ~= 0 and DoesEntityExist(ped)
                and stage ~= nil and next(sourceHair) ~= nil
                and agedHairNeedsRepair(ped, sourceHair, stage) then
                local now = GetGameTimer()
                if now - lastAgingRuntimeRepair >= 250 then
                    lastAgingRuntimeRepair = now
                    -- Rebuild the complete runtime age pass so a late barber
                    -- load cannot remove either the grey tint or the wrinkles.
                    applyCurrentVisualEffects(true)
                end
            end
        else
            Wait(500)
        end
    end
end)

-- SET_PED_MOVE_RATE_OVERRIDE must be refreshed while the slowdown is active.
CreateThread(function()
    local resetApplied = false
    while true do
        local cfg = effectsConfig()
        local movement = cfg and type(cfg.Movement) == 'table' and cfg.Movement or {}
        local rate = effectsEnabled() and movement.Enabled == true and movementRate or 1.0
        local ped = PlayerPedId()

        local suspended = false
        if rate < 1.0 and movement.ApplyWhileMounted ~= true and ped ~= 0 and DoesEntityExist(ped) then
            suspended = IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false)
        end

        if rate < 1.0 and not suspended and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            Citizen.InvokeNative(0x085BF80FA50A39D1, ped, rate)
            resetApplied = false
            Wait(0)
        else
            if not resetApplied and ped ~= 0 and DoesEntityExist(ped) then
                Citizen.InvokeNative(0x085BF80FA50A39D1, ped, 1.0)
                resetApplied = true
            end
            Wait(500)
        end
    end
end)

exports('GetCurrentCharacterAge', function()
    return currentAge, currentStage
end)
end

-- ============================================================================
-- Module: ui/messages.lua
-- ============================================================================
do
local init = false
DisplayPins = true

-- GetScreenCoordFromWorldCoord's first return is a visibility flag: false
-- means the bone is currently off-screen (e.g. legs/chest while the editor
-- camera is zoomed into the head for a close-up category) and the x/y it
-- still returns in that case are unreliable, landing anywhere up to the
-- screen edges. OpenApperanceMenu used to ignore that flag and send those
-- coordinates straight to the NUI every ~45ms, which snapped a pin's dot to
-- a far corner while its label (positioned once, on open) stayed put -
-- exactly the crossing/scattered connector lines reported as "التضارب".
-- Falling back to the last known good screen position for that pin keeps
-- the dot (and its line) stable instead of flinging it off-screen, and it
-- self-corrects the next frame the bone is back in view.
local function getPinScreenCoords(ped, boneId, rightOffset, forwardOffset, upOffset)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false, 0.5, 0.5
    end
    local boneCoords = GetPedBoneCoords(ped, boneId, 0.0, 0.0, 0.0)
    if not boneCoords or (boneCoords.x == 0.0 and boneCoords.y == 0.0 and boneCoords.z == 0.0) then
        boneCoords = GetEntityCoords(ped)
    end
    local fwd = GetEntityForwardVector(ped)
    -- Local right vector perpendicular to forward vector in XY plane:
    local rX, rY = fwd.y, -fwd.x

    local worldX = boneCoords.x + (rightOffset or 0.0) * rX + (forwardOffset or 0.0) * fwd.x
    local worldY = boneCoords.y + (rightOffset or 0.0) * rY + (forwardOffset or 0.0) * fwd.y
    local worldZ = boneCoords.z + (upOffset or 0.0)

    local visible, screenX, screenY = GetScreenCoordFromWorldCoord(worldX, worldY, worldZ)
    local isVisible = (visible == true or visible == 1)
        and (screenX >= 0.01 and screenX <= 0.99 and screenY >= 0.01 and screenY <= 0.99)
    return isVisible, tonumber(screenX) or 0.5, tonumber(screenY) or 0.5
end

-- Category and item translation table for later use in the loop
local CategoryLabels = {
    -- Main categories
    ["barber"] = "@@category_barber",
    ["lifestyle"] = "@@category_lifestyle",
    ["makeup"] = "@@category_makeup",
    
    -- Hair and Beard
    ["hairstabble"] = "@@category_hairstabble",
    ["hair"] = "@@category_hair",
    ["hair_bonnet"] = "@@category_hair_bonnet",
    ["beardstabble"] = "@@category_beardstabble",
    ["beard"] = "@@category_beard",
    ["beards_complete"] = "@@category_beards_complete",
    ["beards_chin"] = "@@category_beards_chin",
    ["beards_chops"] = "@@category_beards_chops",
    ["beards_mustache"] = "@@category_beards_mustache",
    
    -- Makeup
    ["eyeliners"] = "@@category_eyeliners",
    ["lipsticks"] = "@@category_lipsticks",
    ["shadows"] = "@@category_shadows",
    ["paintedmasks"] = "@@category_paintedmasks",
    ["blush"] = "@@category_blush",
    ["blush2"] = "@@category_blush2",
    ["foundation"] = "@@category_foundation",
    
    -- Lifestyle and Skin
    ["eyebrows"] = "@@category_eyebrows",
    ["scars"] = "@@category_scars",
    ["scars2"] = "@@category_scars2",
    ["scars3"] = "@@category_scars3",
    ["acne"] = "@@category_acne",
    ["ageing"] = "@@category_ageing",
    ["complex"] = "@@category_complex",
    ["disc"] = "@@category_disc",
    ["freckles"] = "@@category_freckles",
    ["grime"] = "@@category_grime",
    ["moles"] = "@@category_moles",
    ["spots"] = "@@category_spots"}

local function getBoneScreenCoords(boneCoords, rX, rY, fwd, rightOffset, forwardOffset, upOffset)
    local worldX = boneCoords.x + (rightOffset or 0.0) * rX + (forwardOffset or 0.0) * fwd.x
    local worldY = boneCoords.y + (rightOffset or 0.0) * rY + (forwardOffset or 0.0) * fwd.y
    local worldZ = boneCoords.z + (upOffset or 0.0)

    local visible, screenX, screenY = GetScreenCoordFromWorldCoord(worldX, worldY, worldZ)
    local isVisible = (visible == true or visible == 1)
        and (screenX >= 0.01 and screenX <= 0.99 and screenY >= 0.01 and screenY <= 0.99)
    return isVisible, tonumber(screenX) or 0.5, tonumber(screenY) or 0.5
end

local isAppearanceLoopRunning = false
-- Stores the last screen coordinates sent to NUI so we can skip identical frames.
local prevPinCoords = nil

function OpenApperanceMenu()
    DisplayPins = true
    if isAppearanceLoopRunning then
        return
    end
    isAppearanceLoopRunning = true

    Citizen.CreateThread(function()
        local init = false
        local lastHeading = nil
        while DisplayPins do
            local player = CachePed or PlayerPedId()
            if player and player ~= 0 and DoesEntityExist(player) then
                local fwd = GetEntityForwardVector(player)
                local rX, rY = fwd.y, -fwd.x

                local headCoords = GetPedBoneCoords(player, 21030, 0.0, 0.0, 0.0)
                if not headCoords or (headCoords.x == 0.0 and headCoords.y == 0.0 and headCoords.z == 0.0) then
                    headCoords = GetEntityCoords(player)
                end

                local chestCoords = GetPedBoneCoords(player, 53684, 0.0, 0.0, 0.0)
                if not chestCoords or (chestCoords.x == 0.0 and chestCoords.y == 0.0 and chestCoords.z == 0.0) then
                    chestCoords = GetEntityCoords(player)
                end

                local thighCoords = GetPedBoneCoords(player, 6884, 0.0, 0.0, 0.0)
                if not thighCoords or (thighCoords.x == 0.0 and thighCoords.y == 0.0 and thighCoords.z == 0.0) then
                    thighCoords = GetEntityCoords(player)
                end

                local headVisible, headx, heady = getBoneScreenCoords(headCoords, rX, rY, fwd, 0.0, 0.02, 0.12)
                local eyesVisible, eyesx, eyesy = getBoneScreenCoords(headCoords, rX, rY, fwd, 0.0, 0.07, 0.04)
                local facialVisible, facialx, facialy = getBoneScreenCoords(headCoords, rX, rY, fwd, -0.02, 0.06, -0.03)
                local mouthVisible, mouthx, mouthy = getBoneScreenCoords(headCoords, rX, rY, fwd, 0.0, 0.07, -0.08)

                local chestVisible, chestx, chesty = getBoneScreenCoords(chestCoords, rX, rY, fwd, 0.0, 0.04, 0.02)
                local footVisible, footx, footy = getBoneScreenCoords(thighCoords, rX, rY, fwd, 0.0, 0.0, -0.28)

                if not init then
                    local pins = {
                        {
                            id = "head",
                            name = "@@character_head",
                            visible = headVisible,
                            startPosition = {
                                x = headx,
                                y = heady
                            },
                            direction = "left",
                            subElem = {
                                {
                                    id = "headshape",
                                    name = "@@creator_head_shape"
                                },
                                {
                                    id = "neck",
                                    name = "@@creator_neck"
                                },
                                {
                                    id = "barber",
                                    name = "@@character_hairdresser"
                                },
                            }
                        },
                        {
                            id = "eyesandbrows",
                            name = "@@creator_eyes",
                            direction = "right",
                            visible = eyesVisible,
                            startPosition = {
                                x = eyesx,
                                y = eyesy
                            },
                            subElem = {
                                {
                                    id = "brows",
                                    name = "@@creator_brows"
                                },
                                {
                                    id = "eyes",
                                    name = "@@creator_eyes"
                                },
                                {
                                    id = "eyelid",
                                    name = "@@creator_eyelid"
                                }
                            }
                        },
                        {
                            id = "facial",
                            name = "@@character_face",
                            direction = "right",
                            visible = facialVisible,
                            startPosition = {
                                x = facialx,
                                y = facialy
                            },
                            subElem = {
                                {
                                    id = "ears",
                                    name = "@@creator_ears"
                                },
                                {
                                    id = "cheekbone",
                                    name = "@@creator_cheekbone"
                                },
                                {
                                    id = "jaw",
                                    name = "@@creator_jaw"
                                },
                                {
                                    id = "chin",
                                    name = "@@creator_chin"
                                },
                                {
                                    id = "nose",
                                    name = "@@creator_nose"
                                },
                            }
                        },
                        {
                            id = "mouth",
                            name = "@@creator_mouth",
                            direction = "left",
                            visible = mouthVisible,
                            startPosition = {
                                x = mouthx,
                                y = mouthy
                            },
                            subElem = {
                                {
                                    id = "mouth",
                                    name = "@@creator_mouth"
                                },
                                {
                                    id = "lipupper",
                                    name = "@@creator_lip_upper"
                                },
                                {
                                    id = "liplower",
                                    name = "@@creator_lip_lower"
                                },
                                {
                                    id = "mouthcornerleft",
                                    name = "@@creator_mouth_corner_left"
                                },
                                {
                                    id = "mouthcornerright",
                                    name = "@@creator_mouth_corner_right"
                                },
                            }
                        },
                        {
                            id = "upperbody",
                            name = "@@creator_upper",
                            direction = "right",
                            visible = chestVisible,
                            startPosition = {
                                x = chestx,
                                y = chesty
                            },
                            subElem = {
                                {
                                    id = "arms",
                                    name = "@@creator_arms"
                                },
                                {
                                    id = "shoulders",
                                    name = "@@creator_shoulders"
                                },
                                {
                                    id = "chest",
                                    name = "@@creator_chest"
                                },
                            }
                        },
                        {
                            id = "lowerbody",
                            name = "@@character_legs",
                            direction = "left",
                            visible = footVisible,
                            startPosition = {
                                x = footx,
                                y = footy
                            },
                            subElem = {
                                {
                                    id = "legs",
                                    name = "@@creator_legs"
                                },
                                {
                                    id = "waist",
                                    name = "@@creator_waist"
                                },
                            }
                        },
                    }
                    if CreatorConfig.jrs_clothing == true then
                        local pelvisCoords = GetPedBoneCoords(player, 56200, 0.0, 0.0, 0.0)
                        if not pelvisCoords or (pelvisCoords.x == 0.0 and pelvisCoords.y == 0.0 and pelvisCoords.z == 0.0) then
                            pelvisCoords = GetEntityCoords(player)
                        end
                        local clothesVisible, clothesx, clothesy = getBoneScreenCoords(pelvisCoords, rX, rY, fwd, 0.0, 0.05, 0.03)
                        table.insert(pins, {
                            id = "clothes",
                            name = "@@character_clothes",
                            visible = clothesVisible,
                            startPosition = {
                                x = clothesx,
                                y = clothesy
                            },
                            direction = "left",
                            subElem = {
                                {
                                    id = "clothes",
                                    name = "@@character_clothes_shop"
                                }
                            }
                        })
                    end
                    JRSApplyNuiFocus(true, true, false)
                    init = true
                    -- Seed prevPinCoords so the first update cycle has a baseline to diff against.
                    prevPinCoords = {
                        head         = { x = headx,   y = heady,   v = headVisible   },
                        eyesandbrows = { x = eyesx,   y = eyesy,   v = eyesVisible   },
                        facial       = { x = facialx, y = facialy, v = facialVisible },
                        mouth        = { x = mouthx,  y = mouthy,  v = mouthVisible  },
                        upperbody    = { x = chestx,  y = chesty,  v = chestVisible  },
                        lowerbody    = { x = footx,   y = footy,   v = footVisible   },
                    }
                    lastHeading = GetEntityHeading(player)
                    PlaceElem(true, pins, false)
                else
                    -- Track camera and bone motion with a subpixel noise threshold.
                    local currentHeading = GetEntityHeading(player)
                    local headingDiff = lastHeading and math.abs(currentHeading - lastHeading) or 0.0
                    if headingDiff > 180.0 then headingDiff = 360.0 - headingDiff end

                    local currentCoords = {
                        head         = { x = headx,   y = heady,   v = headVisible   },
                        eyesandbrows = { x = eyesx,   y = eyesy,   v = eyesVisible   },
                        facial       = { x = facialx, y = facialy, v = facialVisible },
                        mouth        = { x = mouthx,  y = mouthy,  v = mouthVisible  },
                        upperbody    = { x = chestx,  y = chesty,  v = chestVisible  },
                        lowerbody    = { x = footx,   y = footy,   v = footVisible   },
                    }

                    local clothesVisible, clothesx, clothesy = false, 0.5, 0.5
                    if CreatorConfig.jrs_clothing == true then
                        local pelvisCoords = GetPedBoneCoords(player, 56200, 0.0, 0.0, 0.0)
                        if not pelvisCoords or (pelvisCoords.x == 0.0 and pelvisCoords.y == 0.0 and pelvisCoords.z == 0.0) then
                            pelvisCoords = GetEntityCoords(player)
                        end
                        clothesVisible, clothesx, clothesy = getBoneScreenCoords(pelvisCoords, rX, rY, fwd, 0.0, 0.05, 0.03)
                        currentCoords["clothes"] = { x = clothesx, y = clothesy, v = clothesVisible }
                    end

                    local dirty = false
                    -- إذا دار اللاعب (تغير اتجاه الجسم بأكثر من 0.25 درجة)
                    if headingDiff > 0.25 then
                        dirty = true
                        lastHeading = currentHeading
                    elseif prevPinCoords then
                        -- Suppress subpixel jitter without quantizing slow camera motion.
                        local DEADZONE = 0.00015
                        for id, cur in pairs(currentCoords) do
                            local p = prevPinCoords[id]
                            if not p
                                or math.abs(cur.x - p.x) > DEADZONE
                                or math.abs(cur.y - p.y) > DEADZONE
                                or cur.v ~= p.v then
                                dirty = true
                                break
                            end
                        end
                    else
                        dirty = true
                    end

                    if dirty then
                        prevPinCoords = currentCoords
                        lastHeading = currentHeading
                        local pinUpdates = {
                            { id = "head",         visible = headVisible,   startPosition = { x = headx,   y = heady   }, direction = "left"  },
                            { id = "eyesandbrows", visible = eyesVisible,   startPosition = { x = eyesx,   y = eyesy   }, direction = "right" },
                            { id = "facial",       visible = facialVisible, startPosition = { x = facialx, y = facialy }, direction = "right" },
                            { id = "mouth",        visible = mouthVisible,  startPosition = { x = mouthx,  y = mouthy  }, direction = "left"  },
                            { id = "upperbody",    visible = chestVisible,  startPosition = { x = chestx,  y = chesty  }, direction = "right" },
                            { id = "lowerbody",    visible = footVisible,   startPosition = { x = footx,   y = footy   }, direction = "left"  },
                        }
                        if CreatorConfig.jrs_clothing == true then
                            table.insert(pinUpdates, {
                                id = "clothes",
                                visible = clothesVisible,
                                startPosition = { x = clothesx, y = clothesy },
                                direction = "left"
                            })
                        end
                        PlaceElem(true, pinUpdates, true)
                    end
                end
            end
            -- Sample bone projections on the render tick; 33ms visibly steps
            -- during camera motion and can become 20Hz on a 60Hz client.
            Wait(0)
        end



        if init then
            PlaceElem(false)
            init = false
        end
        prevPinCoords = nil
        isAppearanceLoopRunning = false
    end)
end

function PlaceElem(state, pins, update)
    if state then
        if not update then
            SendNUIMessage(
                {
                    type = "placeElem",
                    pins = pins
                }
            )
        elseif update then
            SendNUIMessage(
                {
                    type = "updateElem",
                    pins = pins
                }
            )
        end
    else
        SendNUIMessage(
            {
                type = "hideBodyPartsMenu",
            }
        )
    end
end

function EditionMenu(state, edition)
    if state then
        SendNUIMessage(
            {
                type = "showEditionMenu",
                edition = edition
            }
        )
    elseif not state then
        SendNUIMessage(
            {
                type = "hideEditionMenu",
            }
        )
        SendNUIMessage(
            {
                type = "hideEyesPersoMenu",
            }
        )
    end
end

local function buildCurrentAppearanceMenu()
    local menu = {}
    local pedData = type(CachePedData) == "table" and CachePedData or {}
    local gender = pedData.gender == "Female" and "Female" or "Male"
    local genderSet = type(DefaultChar) == "table" and DefaultChar[gender] or nil
    local skinTone = math.floor(tonumber(pedData.skintone) or 1)

    if type(genderSet) == "table" and #genderSet > 0 then
        if skinTone < 1 then skinTone = 1 end
        if skinTone > #genderSet then skinTone = #genderSet end
    end

    local skinSet = type(genderSet) == "table" and genderSet[skinTone] or nil

    for index, entry in ipairs(ApparenceMenu or {}) do
        local copy = {}
        for key, value in pairs(entry) do copy[key] = value end

        if copy.id == "body" then
            copy.totalAmount = math.max(1, type(Body) == "table" and #Body or 1)
            copy.value = math.max(1, math.min(copy.totalAmount, tonumber(pedData.body) or tonumber(copy.value) or 1))
        elseif copy.id == "waist" then
            copy.totalAmount = math.max(1, type(Waist) == "table" and #Waist or 1)
            copy.value = math.max(1, math.min(copy.totalAmount, tonumber(pedData.waist) or tonumber(copy.value) or 1))
        elseif copy.id == "legs" then
            copy.totalAmount = math.max(1, skinSet and type(skinSet.Legs) == "table" and #skinSet.Legs or 1)
            copy.min = 1
            copy.value = math.max(1, math.min(copy.totalAmount, tonumber(pedData.lowerbody) ~= nil and tonumber(pedData.lowerbody) or (tonumber(copy.value) or 1)))
        elseif copy.id == "upper" then
            copy.totalAmount = math.max(1, skinSet and type(skinSet.Body) == "table" and #skinSet.Body or 1)
            copy.min = 1
            copy.value = math.max(1, math.min(copy.totalAmount, tonumber(pedData.upperbody) ~= nil and tonumber(pedData.upperbody) or (tonumber(copy.value) or 1)))
        elseif copy.id == "height" then
            local height = tonumber(pedData.height)
            if height and height <= 2.0 and HeightMax ~= HeightMin then
                local ratio = (height - HeightMin) / (HeightMax - HeightMin)
                copy.value = math.max(0, math.min(100, math.floor((ratio * 100) + 0.5)))
            end
            -- Inputs for the slider's live cm label (same JRSHeightToCm formula).
            copy.heightMin = HeightMin
            copy.heightMax = HeightMax
            copy.heightBaseCm = JRSHeightBaseCm(gender)
        end

        menu[index] = copy
    end

    return menu
end

local function buildCurrentSkinColours()
    local pedData = type(CachePedData) == "table" and CachePedData or {}
    local gender = pedData.gender == "Female" and "Female" or "Male"
    local genderSet = type(DefaultChar) == "table" and DefaultChar[gender] or nil
    local amount = type(genderSet) == "table" and #genderSet or 0
    local current = math.floor(tonumber(pedData.skintone) or 1)

    if amount < 1 then return {} end
    if current < 1 then current = 1 end
    if current > amount then current = amount end

    local result = {}
    for index, entry in ipairs(SkinColours or {}) do
        local copy = {}
        for key, value in pairs(entry) do copy[key] = value end
        copy.tintAmount = amount
        copy.tintValue = current
        result[index] = copy
    end
    return result
end

-- Eye colours for the Edit Appearance page. The static EyeColours table always
-- reports colour 1, so the live CachePedData value and the real per-gender hash
-- count are applied here before the list reaches the UI.
-- Declared globally: the eyes contextual panel lives in a later chunk block.
function JRSBuildCurrentEyeColours()
    local pedData = type(CachePedData) == "table" and CachePedData or {}
    local gender = pedData.gender == "Female" and "Female" or "Male"
    local genderEyes = type(Eyes) == "table" and Eyes[gender] or nil
    local amount = type(genderEyes) == "table" and #genderEyes or 0

    if amount < 1 then return {} end

    local current = math.floor(tonumber(pedData.eyes) or 1)
    if current < 1 then current = 1 end
    if current > amount then current = amount end

    local result = {}
    for index, entry in ipairs(EyeColours or {}) do
        local copy = {}
        for key, value in pairs(entry) do copy[key] = value end

        -- Never advertise more swatches than there are eye hashes or images.
        local colours = {}
        for colourIndex, colour in ipairs(entry.colours or {}) do
            if colourIndex <= amount then colours[#colours + 1] = colour end
        end
        copy.colours = colours
        copy.tintAmount = #colours
        copy.tintValue = math.min(current, math.max(1, #colours))
        result[index] = copy
    end
    return result
end

function LoadApparenceMenu()
    local pedModel = CachePedData and CachePedData.pedmodel and CachePedData.pedmodel.model or nil
    if pedModel ~= "mp_male" and pedModel ~= "mp_female" then
        SendNUIMessage({
            type = "openEditApparenceMenu",
            skinColours = {},
            apparenceMenu = {},
            eyeColours = {},
        })
    else
        SendNUIMessage({
            type = "openEditApparenceMenu",
            skinColours = buildCurrentSkinColours(),
            apparenceMenu = buildCurrentAppearanceMenu(),
            eyeColours = JRSBuildCurrentEyeColours(),
        })
    end
end

local menucategories = {
    male = {
        categories = { "hair", "beard", "lifestyle", "makeup" },
        hair = { "hairstabble", "hair", "hair_bonnet" },
        beard = {
            "beardstabble", "beard", "beards_complete", "beards_chin", "beards_chops", "beards_mustache"
        },
        makeup = {
            "eyeliners", "lipsticks", "shadows", "paintedmasks", "blush", "blush2", "foundation",
        },
        lifestyle = {
            "eyebrows", "scars", "scars2", "scars3", "acne", "ageing", "complex", "disc", "freckles", "grime", "moles",
            "spots"
        },
    },
    female = {
        categories = { "hair", "beard", "lifestyle", "makeup" },
        hair = { "hair", "hair_bonnet" },
        beard = { "beard", "beards_complete", "beards_chin", "beards_chops", "beards_mustache" },
        makeup = {
            "eyeliners", "lipsticks", "shadows", "paintedmasks", "blush", "blush2", "foundation",
        },
        lifestyle = {
            "eyebrows", "scars", "scars2", "scars3", "acne", "ageing", "complex", "disc", "freckles", "grime", "moles",
            "spots"
        },
    }
}

local barberGroupLabels = {
    hair = "Hair",
    beard = "Beard & Mustache",
    lifestyle = "Face Details",
    makeup = "Makeup"
}

-- Same idea for the barber sections. (Key avoids the word "group": _U forces
-- any key containing it to English, which is meant for native prompts only.)
local function barberSectionLabel(group)
    local key = 'creator_barber_section_' .. tostring(group)
    local translated = _U(key)
    if translated ~= key then return translated end
    return barberGroupLabels[group] or group
end

local function barberGroupImage(group, gender)
    if group == "hair" then
        return ("./img/categories/head_%s.png"):format(gender)
    end
    if group == "beard" then
        return "./img/categories/barber.png"
    end
    return ("./img/categories/%s.png"):format(group)
end

local function barberCategoryAvailable(selectedgender, category, showoverlay)
    local assetGroup = JRS_ASSETS and JRS_ASSETS[selectedgender] and JRS_ASSETS[selectedgender][category]
    if type(assetGroup) == "table" and next(assetGroup) ~= nil then
        return true
    end
    return showoverlay and overlays_info and overlays_info[category] ~= nil
end

CreatorBarberResetSnapshot = CreatorBarberResetSnapshot or {}
CreatorOverlayResetSnapshot = CreatorOverlayResetSnapshot or {}

function OpenBarberMenu()
    StopCreatorClothingPins()
    StopCreatorBarberPins()
    CreatorOutfitMode = "barber"
    FocusCreatorOutfitCategory(nil, nil, "barber")
    CreatorBarberResetSnapshot = deepcopy(hairstyleCache or {})
    CreatorOverlayResetSnapshot = deepcopy(overlay_all_layers or {})

    local ped = CachePed
    if eyesanim or teethanim then
        eyesanim = false
        teethanim = false
        ClearPedTasks(ped)
    end
    local selectedgender = "female"
    if CachePedData.gender == "Male" then selectedgender = "male" end

    local showoverlay = GetHead(ped) ~= 0
    local menu = menucategories[selectedgender]
    local categories = {}
    local items = {}

    for _, group in ipairs(menu.categories) do
        local groupHasItems = false

        if (group ~= "makeup" and group ~= "lifestyle") or showoverlay then
            for _, category in ipairs(menu[group] or {}) do
                if barberCategoryAvailable(selectedgender, category, showoverlay) then
                    groupHasItems = true

                    local assetGroup = JRS_ASSETS and JRS_ASSETS[selectedgender] and JRS_ASSETS[selectedgender][category]
                    if type(assetGroup) == "table" and next(assetGroup) ~= nil then
                        local cached = hairstyleCache[category] or {}
                        table.insert(items, {
                            id = category,
                            name = CategoryLabels[category] or (Lang and Lang.Categories and Lang.Categories[category]) or category,
                            category = group,
                            totalAmount = #assetGroup,
                            selectorType = "slider",
                            contextual = "variation",
                            value = tonumber(cached.model) or 0,
                        })
                    elseif showoverlay and overlays_info and overlays_info[category] then
                        local currentVal = 0
                        for _, l in pairs(overlay_all_layers or {}) do
                            if l.name == category and l.visibility and tonumber(l.visibility) > 0 then
                                currentVal = tonumber(l.tx_id_index) or 1
                                break
                            end
                        end
                        table.insert(items, {
                            id = category,
                            name = CategoryLabels[category] or (Lang and Lang.Categories and Lang.Categories[category]) or category,
                            category = group,
                            totalAmount = #overlays_info[category],
                            selectorType = "slider",
                            contextual = "variation",
                            value = currentVal,
                        })
                    end
                end
            end
        end

        if groupHasItems then
            table.insert(categories, {
                id = group,
                name = barberSectionLabel(group),
                image = barberGroupImage(group, selectedgender)
            })
        end
    end

    SendNUIMessage({
        type = "openOutfitMenu",
        title = _U('character_outfit_title_barber'),
        mode = "barber",
        categories = categories,
        items = items
    })

    StartCreatorBarberPins()
end

ContextualDataOn = false
function UpdateContextualDatas(value, category)
    local selectedgender = "female"
    if CachePedData.gender == "Male" then selectedgender = "male" end
    if value then
        if value > 0 then
            if overlays_info[category] then
                local overlayState = nil
                for _, layer in pairs(overlay_all_layers or {}) do
                    if layer.name == category then
                        overlayState = layer
                        break
                    end
                end

                local function clampInt(value, minValue, maxValue, defaultValue)
                    value = tonumber(value)
                    if value == nil then value = defaultValue end
                    if value == nil then value = minValue end
                    if value < minValue then value = minValue end
                    if value > maxValue then value = maxValue end
                    return math.floor(value)
                end

                local function resolvePaletteIndex(state)
                    local fallback = 1
                    local palettes = Config and Config.color_palettes or nil
                    if type(palettes) ~= 'table' then return fallback end
                    local statePalette = state and state.palette or nil
                    if statePalette == nil then return fallback end
                    for paletteId, paletteData in pairs(palettes) do
                        if type(paletteData) == 'table' and paletteData[1] == statePalette then
                            return tonumber(paletteId) or fallback
                        end
                    end
                    return fallback
                end

                local variationAmount = 1
                if category == "eyeliners" then variationAmount = 15 end
                if category == "shadows" then variationAmount = 5 end
                if category == "lipsticks" then variationAmount = 7 end

                local variationValue = clampInt(overlayState and overlayState.var or 1, 1, variationAmount, 1)
                local opacityValue = clampInt((overlayState and overlayState.opacity or 1.0) * 100, 0, 100, 100)
                local paletteValue = resolvePaletteIndex(overlayState)
                local maxPalette = 25
                if type(Config) == 'table' and type(Config.color_palettes) == 'table' then
                    local paletteCount = 0
                    for _ in pairs(Config.color_palettes) do paletteCount = paletteCount + 1 end
                    if paletteCount > 0 then maxPalette = paletteCount end
                end

                local tints = {
                    { tintId = 1, value = clampInt(overlayState and overlayState.palette_color_primary or 0, 0, 255, 0) },
                    { tintId = 2, value = clampInt(overlayState and overlayState.palette_color_secondary or 0, 0, 255, 0) },
                    { tintId = 3, value = clampInt(overlayState and overlayState.palette_color_tertiary or 0, 0, 255, 0) }
                }

                local data = {
                    variationAmount = variationAmount,
                    variationValue = variationValue,
                    tints = tints,
                    contextual = "variation",
                    advanced = true,
                    advancedValues = {
                        {
                            valueName = "Opacity",
                            valueId = 1,
                            valueValue = opacityValue,
                            maxValue = 100,
                            minValue = 0
                        },
                        {
                            valueName = "Palette",
                            valueId = 2,
                            valueValue = clampInt(paletteValue, 1, maxPalette, 1),
                            maxValue = maxPalette,
                            minValue = 1
                        }
                    },
                    category = category,
                }

                SendNUIMessage(
                    {
                        type = "contextualDatas",
                        data = data

                    }
                )
            else
                local variationValue = 1
                if type(hairstyleCache[category].texture) == "table" then
                    variationValue = hairstyleCache[category].texture.palette or hairstyleCache[category].texture.model
                else
                    variationValue = hairstyleCache[category].texture
                end
                local variationAmount = 1
                local tints = {}
                local colorOptions = {}
                if JRS_ASSETS[selectedgender][category][value].variants then
                    local variants = JRS_ASSETS[selectedgender][category][value].variants
                    variationAmount = #variants
                    tint0value = hairstyleCache[category].texture.tint0 or
                        variants[1].tint[1] or 1
                    tint1value = hairstyleCache[category].texture.tint1 or
                        variants[1].tint[2] or 1
                    tint2value = hairstyleCache[category].texture.tint2 or
                        variants[1].tint[3] or 1
                    tints = {
                        { tintId = 1, value = tint0value },
                        { tintId = 2, value = tint1value },
                        { tintId = 3, value = tint2value }
                    }

                    -- Native colour picker: dedupe by the variant's real
                    -- signature (same fields jrs_clothing's own colour
                    -- picker keys on), so visually-identical variants
                    -- collapse into one numbered chip instead of listing
                    -- every raw drawable variant.
                    local seen = {}
                    for uiIndex, variant in ipairs(variants) do
                        local vtint = variant.tint or { variant.tint0 or 0, variant.tint1 or 0, variant.tint2 or 0 }
                        local signature = table.concat({
                            tostring(variant.albedo or 0),
                            tostring(variant.normal or 0),
                            tostring(variant.material or 0),
                            tostring(variant.palette or 0),
                            tostring(vtint[1] or 0),
                            tostring(vtint[2] or 0),
                            tostring(vtint[3] or 0)
                        }, ":")
                        if not seen[signature] then
                            seen[signature] = true
                            table.insert(colorOptions, {
                                value = uiIndex,
                                realVariant = uiIndex,
                                selected = uiIndex == variationValue,
                            })
                        end
                    end
                else
                    variationAmount = #JRS_ASSETS[selectedgender][category][value]
                    if type(hairstyleCache[category].texture) == "table" then
                        tint0value = hairstyleCache[category].texture.tint0 or 1
                        tint1value = hairstyleCache[category].texture.tint1 or 1
                        tint2value = hairstyleCache[category].texture.tint2 or 1
                    else
                        tint0value = 1
                        tint1value = 1
                        tint2value = 1
                    end
                    tints = {
                        { tintId = 1, value = tint0value },
                        { tintId = 2, value = tint1value },
                        { tintId = 3, value = tint2value }
                    }
                end
                local data = {
                    variationAmount = variationAmount,
                    variationValue = variationValue or 1,
                    tints = tints,
                    contextual = "variation",
                    category = category,
                    actualColorOptions = colorOptions,
                    nativeColor = #colorOptions > 1,
                }

                SendNUIMessage(
                    {
                        type = "contextualDatas",
                        data = data

                    }
                )
            end
            if ContextualDataOn == false then
                ContextualDataOn = true
                PlaySound("SELECT", "HUD_PLAYER_MENU")
            end
        else
            PlaySound("BACK", "HUD_PLAYER_MENU")
            ContextualDataOn = false
            SendNUIMessage(
                {
                    type = "hidecontextualDatas",

                }
            )
        end
    end
end
end

-- ============================================================================
-- Module: ui/callbacks.lua
-- ============================================================================
do
local camOnHead = false
local processingcam = false
local teethanim = false
local eyesanim = false
local changingGender = false
local function clampAppearanceIndex(value, entries)
    if type(entries) ~= "table" or #entries == 0 then return nil, nil end

    local index = math.floor(tonumber(value) or 1)
    if index < 1 then index = 1 end
    if index > #entries then index = #entries end

    return entries[index], index
end

local function getCurrentDefaultSkinSet()
    if type(CachePedData) ~= "table" then return nil end

    local gender = CachePedData.gender == "Female" and "Female" or "Male"
    local genderSet = type(DefaultChar) == "table" and DefaultChar[gender] or nil
    if type(genderSet) ~= "table" or #genderSet == 0 then return nil end

    local skinTone = math.floor(tonumber(CachePedData.skintone) or 1)
    if skinTone < 1 then skinTone = 1 end
    if skinTone > #genderSet then skinTone = #genderSet end
    CachePedData.gender = gender
    CachePedData.skintone = skinTone

    return genderSet[skinTone]
end

local function hexComponentToNumber(value)
    if value == nil then return nil end
    if type(value) == "number" then return value end

    local text = tostring(value):gsub("^0[xX]", "")
    if text == "" then return nil end
    return tonumber("0x" .. text)
end

-- Callback for showing the edition menu
RegisterNUICallback("showEditionMenu", function(data, cb)
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    local pinId = data.pinId
    local pinName = data.pinName
    local elemId = data.elemId
    local subElemName = data.subElemName
    DisplayPins = false

    if elemId == "barber" then
        OpenBarberMenu()
    elseif elemId == "clothes" then
        OpenClothesMenu()
    else
        local arrayData = {}
        if EditionElem[elemId] then
            -- Convertir la table en tableau indexé numériquement
            for _, i in pairs(EditionElem[elemId].division) do
                for j, elem in pairs(i.elements) do
                    if elem.type == "slider" then
                        if CachePedData.expressions[elem.id] == nil then
                            elem.startValue = 50
                        else
                            elem.startValue = scale(CachePedData.expressions[elem.id], ExpressionsMaxValues[elem.id].min,
                                ExpressionsMaxValues[elem.id].max, 0, 100)
                        end
                    end
                    if elem.type == "matrice" then
                        if CachePedData.expressions[elem.XHashes] == nil then
                            elem.startPositionX = 0.5
                        else
                            elem.startPositionX = scale(CachePedData.expressions[elem.XHashes],
                                ExpressionsMaxValues[elem.XHashes].min,
                                ExpressionsMaxValues[elem.XHashes].max, 0, 1)
                        end
                        if CachePedData.expressions[elem.YHashes] == nil then
                            elem.startPositionY = 0.5
                        else
                            elem.startPositionY = scale(CachePedData.expressions[elem.YHashes],
                                ExpressionsMaxValues[elem.YHashes].min,
                                ExpressionsMaxValues[elem.YHashes].max, 0, 1)
                        end
                    end
                    -- Mise à jour des valeurs pour les slider_legacy depuis CachePedData
                    if elem.type == "slider_legacy" then
                        if elem.id == "head" and CachePedData.head then
                            elem.value = CachePedData.head
                        elseif elem.id == "tooth" and CachePedData.teeth then
                            elem.value = CachePedData.teeth
                        end
                    end
                end
            end
            local elem = deepcopy(EditionElem[elemId])
            if elemId == "headshape" then
                if CachePedData.pedmodel.model ~= "mp_male" and CachePedData.pedmodel.model ~= "mp_female" then
                    table.remove(elem.division, 1)
                end
            end
            table.insert(arrayData, elem)
            ------------------
            --- Renvoyer les startpositions
        end
        EditionMenu(true, arrayData)

        -- Add your logic here
    end
    SendNUIMessage(
        {
            type = "hideEditApparenceMenu",

        }
    )
    if elemId == "eyes" then
        SendNUIMessage(
            {
                type = "openEyesPersoMenu",
                eyesColours = JRSBuildCurrentEyeColours()
            }
        )
    end
    MoveCam(pinId)
    Wait(1001)
    if cb then cb({ ok = true }) end
end)

-- Callback for canceling character edition
RegisterNUICallback("cancelCharEdition", function(data, cb)
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    MoveCam("edit")
    EditionMenu(false)
    local ped = CachePed
    local x, y, z = table.unpack(GetEntityCoords(ped))
    if not baseHeading then
        baseHeading = GetEntityHeading(ped)
        -- Stocker l'offset initial pour que 180 corresponde à baseHeading
        angleOffset = 180 - baseHeading
    end
    local targetHeading = (180 - angleOffset) % 360
    local rad = math.rad(targetHeading)
    local distance = 1.0
    local targetX = x + (math.sin(-rad) * distance)
    local targetY = y + (math.cos(-rad) * distance)
    TaskTurnPedToFaceCoord(ped, targetX, targetY, z, 0)
    DisplayPins = true

    Wait(1000)

    LoadApparenceMenu()

    OpenApperanceMenu()

    -- Add your logic here

    cb("ok")
end)

RegisterNetEvent("jrs_character_creator:BackFromClothing", function()
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    ActiveCam = 0
    MoveCam("edit")

    EditionMenu(false)
    local ped = CachePed
    local x, y, z = table.unpack(GetEntityCoords(ped))
    if not baseHeading then
        baseHeading = GetEntityHeading(ped)
        -- Stocker l'offset initial pour que 180 corresponde à baseHeading
        angleOffset = 180 - baseHeading
    end
    local targetHeading = (180 - angleOffset) % 360
    local rad = math.rad(targetHeading)
    local distance = 1.0
    local targetX = x + (math.sin(-rad) * distance)
    local targetY = y + (math.cos(-rad) * distance)
    TaskTurnPedToFaceCoord(ped, targetX, targetY, z, 0)
    DisplayPins = true
    Light()
    Wait(1000)
    LoadApparenceMenu()
    OpenApperanceMenu()
end)

local creatorViewBaseHeading = nil
local creatorViewFov = nil
local creatorViewPedHandle = nil

local function getCreatorActiveCamera()
    if ActiveCam == 1 and Cam1 and DoesCamExist(Cam1) then return Cam1 end
    if ActiveCam == 2 and Cam2 and DoesCamExist(Cam2) then return Cam2 end
    if ActualCamera and DoesCamExist(ActualCamera) then return ActualCamera end
    return nil
end

local function creatorViewControlHandler(data, cb)
    data = type(data) == 'table' and data or {}
    local action = tostring(data.action or '')
    local focusTarget = tostring(data.target or '')
    local ped = CachePed
    if not ped or ped == 0 or not DoesEntityExist(ped) then ped = PlayerPedId() end
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        if cb then cb({ ok = false, reason = 'invalid_ped' }) end
        return
    end

    if creatorViewPedHandle ~= ped then
        creatorViewPedHandle = ped
        creatorViewBaseHeading = GetEntityHeading(ped)
        creatorViewFov = nil
    elseif creatorViewBaseHeading == nil then
        creatorViewBaseHeading = GetEntityHeading(ped)
    end

    local function applyFocus(destination)
        if not destination or destination == '' then return false end
        currentCamDestionation = ''
        MoveCam(destination)
        local cam = getCreatorActiveCamera()
        if cam then
            creatorViewFov = tonumber(GetCamFov(cam)) or creatorViewFov
            CamFov = creatorViewFov or CamFov
        end
        return true
    end

    local focusMap = {
        fullbody = 'Body',
        body = 'Body',
        head = 'head',
        face = 'facial',
        torso = 'upperbody',
        upperbody = 'upperbody',
        hands = 'hands',
        waist = 'waist',
        legs = 'lowerbody',
        lowerbody = 'lowerbody',
        boots = 'feet',
        feet = 'feet'
    }

    local downSequence = {
        head = 'facial',
        facial = 'upperbody',
        eyesandbrows = 'facial',
        mouth = 'facial',
        upperbody = 'hands',
        hands = 'waist',
        waist = 'lowerbody',
        lowerbody = 'feet',
        feet = 'Body',
        Body = 'lowerbody',
        [''] = 'lowerbody'
    }

    -- Mirror of downSequence so "Up" retraces the same chain instead of
    -- leaving the player stuck at the bottom with no way back except the
    -- Quick Focus shortcuts.
    local upSequence = {
        facial = 'head',
        eyesandbrows = 'head',
        mouth = 'head',
        upperbody = 'facial',
        hands = 'upperbody',
        waist = 'hands',
        lowerbody = 'waist',
        feet = 'lowerbody',
        Body = 'feet',
        head = 'head',
        [''] = 'upperbody'
    }

    if action == 'rotateDrag' then
        local delta = tonumber(data.delta)
        if not delta or delta ~= delta or math.abs(delta) == math.huge then
            if cb then cb({ ok = false, reason = 'invalid_delta' }) end
            return
        end
        SetEntityHeading(ped, (GetEntityHeading(ped) - (delta % 360.0)) % 360.0)
        baseHeading = false
    elseif action == 'rotateLeft' or action == 'rotateRight' then
        local step = 7.5
        local heading = GetEntityHeading(ped)
        heading = heading + (action == 'rotateLeft' and step or -step)
        heading = heading % 360.0
        SetEntityHeading(ped, heading)
        baseHeading = false
    elseif action == 'zoomIn' or action == 'zoomOut' then
        local cam = getCreatorActiveCamera()
        if cam then
            local current = tonumber(GetCamFov(cam)) or tonumber(creatorViewFov) or tonumber(BaseCamFov) or 30.0
            local nextFov = current + (action == 'zoomIn' and -1.5 or 1.5)
            nextFov = math.max(12.0, math.min(75.0, nextFov))
            creatorViewFov = nextFov
            CamFov = nextFov
            SetCamFov(cam, nextFov)
            if Cam1 and DoesCamExist(Cam1) and cam ~= Cam1 then SetCamFov(Cam1, nextFov) end
            if Cam2 and DoesCamExist(Cam2) and cam ~= Cam2 then SetCamFov(Cam2, nextFov) end
        end
    elseif action == 'moveDown' then
        local nextDestination = downSequence[currentCamDestionation or ''] or 'lowerbody'
        applyFocus(nextDestination)
    elseif action == 'moveUp' then
        local nextDestination = upSequence[currentCamDestionation or ''] or 'upperbody'
        applyFocus(nextDestination)
    elseif action == 'focus' then
        local mapped = focusMap[string.lower(focusTarget)]
        if not mapped or not applyFocus(mapped) then
            if cb then cb({ ok = false, reason = 'invalid_focus_target' }) end
            return
        end
    elseif action == 'panRight' then
        -- 0.007 of the cam distance was ~3cm per press on the body cam, so
        -- the buttons looked dead. 0.035 is a visible step; ±0.35 keeps the
        -- ped on screen at the creator FOVs.
        creatorViewPanRatio = math.min(0.35, creatorViewPanRatio + 0.035)
        UpdateCreatorActiveCameraPosition()
    elseif action == 'panLeft' then
        creatorViewPanRatio = math.max(-0.35, creatorViewPanRatio - 0.035)
        UpdateCreatorActiveCameraPosition()
    elseif action == 'centerView' then
        creatorViewPanRatio = 0.0
        UpdateCreatorActiveCameraPosition()
    elseif action == 'reset' then
        creatorViewPanRatio = 0.0
        if creatorViewBaseHeading ~= nil then
            SetEntityHeading(ped, creatorViewBaseHeading)
        end
        baseHeading = false
        applyFocus('Body')
        local cam = getCreatorActiveCamera()
        if cam then
            local resetFov = tonumber(BaseCamFov) or 30.0
            creatorViewFov = resetFov
            SetCamFov(cam, resetFov)
            CamFov = resetFov
        end
    else
        if cb then cb({ ok = false, reason = 'invalid_action' }) end
        return
    end

    if cb then cb({ ok = true, heading = GetEntityHeading(ped), fov = creatorViewFov, current = currentCamDestionation }) end
end

-- Always answer the NUI: an error inside the handler used to leave the
-- request hanging, which froze that view button until the ajax timeout.
RegisterNUICallback("creatorViewControl", function(data, cb)
    local answered = false
    local function reply(result)
        if answered then return end
        answered = true
        if cb then cb(result) end
    end
    local ok, err = pcall(creatorViewControlHandler, data, reply)
    if not ok then
        print(("^3[jrs_character] creatorViewControl failed: %s^7"):format(tostring(err)))
        reply({ ok = false, reason = "error" })
    end
end)

-- Callback for handling camera changes
RegisterNUICallback("cameraChange", function(data, cb)
    local cameraName = data.cameraName
    local value = data.value


    if cameraName == "Z" then
        local outputvalue = scale(value, 1, 360, 15.0, 50.0)
        if ActiveCam == 1 then
            SetCamFov(Cam1, outputvalue)
        else
            SetCamFov(Cam2, outputvalue)
        end
        PlaySound("Amount_Increase", "HUD_Donate_Sounds")
    end

    if cameraName == "R" then
        local ped = CachePed
        local x, y, z = table.unpack(GetEntityCoords(ped))

        -- Initialiser le heading de base si pas encore fait
        if not baseHeading then
            baseHeading = GetEntityHeading(ped)
            -- Stocker l'offset initial pour que 180 corresponde à baseHeading
            angleOffset = 180 - baseHeading
        end

        -- Calculer le heading cible directement
        local targetHeading = (value - angleOffset) % 360
        local rad = math.rad(targetHeading)

        -- Calculer un point à 1 unité devant le ped selon le heading voulu
        local distance = 1.0
        local targetX = x + (math.sin(-rad) * distance)
        local targetY = y + (math.cos(-rad) * distance)

        TaskTurnPedToFaceCoord(ped, targetX, targetY, z, 0)
        PlaySound("Amount_Decrease",
            "HUD_Donate_Sounds")
    end
    if cb then cb({ ok = true }) end
end)

-- Callback for handling matrix element updates
RegisterNUICallback("matriceElem", function(data, cb)
    local item = data.item
    local matriceId = data.matriceId
    local x = data.X
    local y = data.Y

    local XHashes = data.XHashes
    local YHashes = data.YHashes
    local Xoutputvalue = scale(x, 0, 1, ExpressionsMaxValues[XHashes].min, ExpressionsMaxValues[XHashes].max)
    local Youtputvalue = scale(y, 0, 1, ExpressionsMaxValues[YHashes].min, ExpressionsMaxValues[YHashes].max)

    local ped = CachePed

    PlaySound("Amount_Decrease", "HUD_Donate_Sounds")
    IsPedReadyToRender(ped)
    SetCharExpression(ped, ExpressionsHashes[XHashes], Xoutputvalue)
    SetCharExpression(ped, ExpressionsHashes[YHashes], Youtputvalue)
    CachePedData.expressions[XHashes] = Xoutputvalue
    CachePedData.expressions[YHashes] = Youtputvalue
    UpdatePedVariation(ped)
    if cb then cb({ ok = true }) end
end)

-- Callback for handling matrix element updates
RegisterNUICallback("sliderCharChange", function(data, cb)
    local value = data.value
    local ElementID = data.ElementID
    local ped = CachePed
    local range = ExpressionsMaxValues[ElementID]
    if not range or not ExpressionsHashes[ElementID] or not ped or not DoesEntityExist(ped) then
        if cb then cb({ ok = false, reason = "invalid" }) end
        return
    end
    local outputvalue = scale(tonumber(value) or 50, 0, 100, range.min, range.max)
    PlaySound("Amount_Increase", "HUD_Donate_Sounds")

    IsPedReadyToRender(ped)
    SetCharExpression(ped, ExpressionsHashes[ElementID], outputvalue)
    CachePedData.expressions[ElementID] = outputvalue
    UpdatePedVariation(ped)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("cancelCharCreation", function(data, cb)
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    
    -- Normal cancel behavior for character creation
    CachePedData = deepcopy(DefaultCachePedData)
    ResetCreatorClothingCache(true)
    hairstyleCache = {}
    ApplyCachePedDataToPedPlayer()
    SendNUIMessage({ type = "hideCharGlobalMenu" })
    if type(JRSHandleCreatorCancel) == 'function' then
        JRSHandleCreatorCancel()
    else
        TriggerServerEvent('jrs_character_creator:getCharacters')
    end
    if cb then cb({ ok = true }) end
end)

local function truncateIdentityText(value, limit)
    local text = tostring(value or '')
    -- Byte slicing can split Arabic letters before JSON reaches the server.
    local length = utf8.len(text)
    if not length then return '' end
    if length > limit then return text:sub(1, utf8.offset(text, limit + 1) - 1) end
    return text
end

local function applyCharacterIdentity(data)
    data = type(data) == "table" and data or {}
    CharacterName = truncateIdentityText(data.CharacterName or CharacterName, 50)
    CharacterSurname = truncateIdentityText(data.CharacterSurname or CharacterSurname, 50)
    CharacterTitle = truncateIdentityText(data.CharacterTitle or CharacterTitle, 50)
    CharacterOccupation = truncateIdentityText(data.CharacterOccupation or CharacterOccupation, 80)
    CharacterLore = truncateIdentityText(data.CharacterLore or CharacterLore, 2000)
    CharacterBirthDate = tostring(data.CharacterBirthDate or CharacterBirthDate or ""):sub(1, 10)
    CharacterBirthDay = tostring(data.CharacterBirthDay or CharacterBirthDay or "")
    CharacterBirthMonth = tostring(data.CharacterBirthMonth or CharacterBirthMonth or "")
    CharacterBirthYear = tostring(data.CharacterBirthYear or CharacterBirthYear or "")
    if data.CharacterIsAPed ~= nil then CharacterIsAPed = data.CharacterIsAPed == true end
    CharacterSexe = data.CharacterSexe or CharacterSexe
end

local function validateCharacterIdentity()
    if tostring(CharacterName or "") == "" then return false, "characterName" end
    if tostring(CharacterSurname or "") == "" then return false, "characterSurname" end
    if tostring(CharacterBirthDate or "") == "" then return false, "characterBirthDate" end
    if not tostring(CharacterBirthDate):match("^%d%d%d%d%-%d%d%-%d%d$") then
        return false, "characterBirthDate"
    end
    if tostring(CharacterLore or "") == "" then return false, "characterLore" end
    return true
end

RegisterNUICallback("NextChar", function(data, cb)
    applyCharacterIdentity(data)

    local valid, field = validateCharacterIdentity()
    if not valid then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        if cb then cb({ ok = false, field = field }) end
        return
    end

    if changingGender == true then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        if cb then cb({ ok = false, reason = "gender_busy" }) end
        return
    end

    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    SendNUIMessage({ type = "hideCharGlobalMenu" })
    MoveCam("edit")
    Wait(1200)
    LoadApparenceMenu()
    DisplayPins = true
    OpenApperanceMenu()
    if cb then cb({ ok = true }) end
end)

local function BuildEnabledSpawnLocations()
    local book = type(Config.SpawnBook) == 'table' and Config.SpawnBook or {}
    local configuredCities = type(book.Cities) == 'table' and book.Cities or {}
    local locations = {}

    -- A city's Arabic copy (city.Ar) travels with the English so the book can
    -- repaint on a language switch without the client resending the pages.
    local function cityTranslations(city)
        if type(city.Ar) ~= 'table' then return nil end
        local ar = {}
        for field, key in pairs({ Name = 'name', Tagline = 'tagline', Description = 'description',
            Region = 'region', Climate = 'climate', Economy = 'economy', Danger = 'danger' }) do
            if type(city.Ar[field]) == 'string' and city.Ar[field] ~= '' then
                ar[key] = city.Ar[field]
            end
        end
        return next(ar) and { ar = ar } or nil
    end

    for _, city in ipairs(configuredCities) do
        if type(city) == 'table' and city.Enabled ~= false then
            local spawnCoords = city.SpawnCoords or city.pedspawn
            local cameraCoords = city.CameraCoords or city.coords or spawnCoords
            local cameraTarget = city.CameraTarget or city.target or spawnCoords

            if spawnCoords and cameraCoords and cameraTarget then
                locations[#locations + 1] = {
                    id = #locations + 1,
                    key = tostring(city.Key or city.key or ('city_' .. tostring(#locations + 1))),
                    name = tostring(city.Name or city.name or 'Unknown'),
                    tagline = tostring(city.Tagline or city.tagline or ''),
                    description = tostring(city.Description or city.description or ''),
                    region = tostring(city.Region or city.region or 'Unknown'),
                    climate = tostring(city.Climate or city.climate or 'Unknown'),
                    economy = tostring(city.Economy or city.economy or 'Unknown'),
                    danger = tostring(city.Danger or city.danger or 'Unknown'),
                    image = tostring(city.Image or city.image or ''),
                i18n = cityTranslations(city),
                    coords = cameraCoords,
                    target = cameraTarget,
                    fov = tonumber(city.CameraFov or city.fov) or 45.0,
                    pedspawn = spawnCoords,
                    pedspawnheading = tonumber(city.SpawnHeading or city.pedspawnheading) or 0.0,
                }
            end
        end
    end

    -- Never leave a new character trapped if every toggle was disabled by mistake.
    if #locations == 0 and type(configuredCities[1]) == 'table' then
        local city = configuredCities[1]
        local spawnCoords = city.SpawnCoords or city.pedspawn
        if spawnCoords then
            locations[1] = {
                id = 1,
                key = tostring(city.Key or city.key or 'fallback'),
                name = tostring(city.Name or city.name or 'Fallback'),
                tagline = tostring(city.Tagline or city.tagline or ''),
                description = tostring(city.Description or city.description or ''),
                region = tostring(city.Region or city.region or 'Unknown'),
                climate = tostring(city.Climate or city.climate or 'Unknown'),
                economy = tostring(city.Economy or city.economy or 'Unknown'),
                danger = tostring(city.Danger or city.danger or 'Unknown'),
                image = tostring(city.Image or city.image or ''),
                i18n = cityTranslations(city),
                coords = city.CameraCoords or city.coords or spawnCoords,
                target = city.CameraTarget or city.target or spawnCoords,
                fov = tonumber(city.CameraFov or city.fov) or 45.0,
                pedspawn = spawnCoords,
                pedspawnheading = tonumber(city.SpawnHeading or city.pedspawnheading) or 0.0,
            }
-- REMOVED-PRINT:             print('^3[jrs_character] All SpawnBook cities are disabled. The first configured city was used as a safety fallback.^7')
        end
    end

    return locations
end

local function RefreshSpawnLocations()
    SpawnLocation = BuildEnabledSpawnLocations()
    return SpawnLocation
end

local function GetSpawnBookUiConfig()
    local book = type(Config.SpawnBook) == 'table' and Config.SpawnBook or {}
    local ar = {}
    if type(book.Ar) == 'table' then
        for field, key in pairs({ Title = 'title', Subtitle = 'subtitle', SelectLabel = 'selectLabel', PageLabel = 'pageLabel' }) do
            if type(book.Ar[field]) == 'string' and book.Ar[field] ~= '' then
                ar[key] = book.Ar[field]
            end
        end
    end
    return {
        title = tostring(book.Title or 'Choose Your Beginning'),
        subtitle = tostring(book.Subtitle or ''),
        selectLabel = tostring(book.SelectLabel or 'Begin in %s'),
        pageLabel = tostring(book.PageLabel or 'Page %s of %s'),
        previewWorld = book.PreviewWorld == true,
        i18n = next(ar) and { ar = ar } or nil,
    }
end

local function ResolveSpawnLocation(data)
    data = type(data) == 'table' and data or {}
    local requestedKey = tostring(data.SpawnLocationKey or data.spawnLocationKey or '')

    if requestedKey ~= '' then
        for _, location in ipairs(SpawnLocation or {}) do
            if tostring(location.key) == requestedKey then
                return location
            end
        end
    end

    local requestedId = math.floor(tonumber(data.SpawnLocationId) or 1)
    return SpawnLocation[requestedId] or SpawnLocation[1]
end

RefreshSpawnLocations()

local PendingIdCardData = nil

-- Identity Registry auto-fill: describe the ped the player just built so the
-- registry's height / complexion / hair / eyes fields arrive pre-filled
-- (still editable there). Names follow the creator's own swatches: skin_tone_N
-- / eye_color_N images and ui/rdo_colors.js RDO_HAIR_COLORS (same tint lookup
-- tintPreviewColour uses for the tint meter).
local IdSkinToneNames = {
    { en = "Fair",        ar = "فاتح جداً" },
    { en = "Light",       ar = "فاتح" },
    { en = "Tan",         ar = "حنطي" },
    { en = "Olive",       ar = "قمحي" },
    { en = "Brown",       ar = "أسمر" },
    { en = "Dark",        ar = "داكن" },
}
local IdEyeColourNames = {
    { en = "Light Blue",  ar = "أزرق فاتح" },
    { en = "Blue",        ar = "أزرق" },
    { en = "Grey Blue",   ar = "أزرق رمادي" },
    { en = "Light Teal",  ar = "فيروزي فاتح" },
    { en = "Grey Green",  ar = "أخضر رمادي" },
    { en = "Teal",        ar = "فيروزي" },
    { en = "Hazel Green", ar = "أخضر عسلي" },
    { en = "Pale Blue",   ar = "أزرق شاحب" },
    { en = "Grey",        ar = "رمادي" },
    { en = "Amber",       ar = "عسلي" },
    { en = "Hazel",       ar = "بندقي" },
    { en = "Green",       ar = "أخضر" },
    { en = "Brown",       ar = "بني" },
    { en = "Dark Brown",  ar = "بني داكن" },
}
-- Mirrors RDO_HAIR_COLORS in ui/rdo_colors.js (index = list position).
local IdHairColourNames = {
    { t = 0,   en = "Jet Black",        ar = "أسود فاحم" },
    { t = 1,   en = "Black",            ar = "أسود" },
    { t = 2,   en = "Dark Espresso",    ar = "بني قهوة داكن" },
    { t = 3,   en = "Dark Brown",       ar = "بني داكن" },
    { t = 4,   en = "Chestnut",         ar = "كستنائي" },
    { t = 5,   en = "Medium Brown",     ar = "بني متوسط" },
    { t = 6,   en = "Cinnamon Brown",   ar = "بني قرفي" },
    { t = 7,   en = "Light Ash Brown",  ar = "بني رمادي فاتح" },
    { t = 8,   en = "Sandy Brown",      ar = "بني رملي" },
    { t = 9,   en = "Dirty Blonde",     ar = "أشقر داكن" },
    { t = 10,  en = "Honey Blonde",     ar = "أشقر عسلي" },
    { t = 11,  en = "Golden Blonde",    ar = "أشقر ذهبي" },
    { t = 12,  en = "Sandy Blonde",     ar = "أشقر رملي" },
    { t = 13,  en = "Light Blonde",     ar = "أشقر فاتح" },
    { t = 14,  en = "Platinum Blonde",  ar = "أشقر بلاتيني" },
    { t = 15,  en = "Deep Auburn",      ar = "أحمر كستنائي داكن" },
    { t = 16,  en = "Chestnut Red",     ar = "كستنائي أحمر" },
    { t = 17,  en = "Ginger",           ar = "أحمر زنجبيلي" },
    { t = 18,  en = "Copper",           ar = "نحاسي" },
    { t = 19,  en = "Strawberry Blonde", ar = "أشقر محمر" },
    { t = 145, en = "Salt & Pepper",    ar = "أشيب خفيف" },
    { t = 148, en = "Charcoal Grey",    ar = "رمادي فحمي" },
    { t = 152, en = "Steel Grey",       ar = "رمادي فولاذي" },
    { t = 156, en = "Silver",           ar = "فضي" },
    { t = 160, en = "Grey",             ar = "رمادي" },
    { t = 161, en = "White",            ar = "أبيض" },
}

local function idNameFor(entry, isArabic)
    if not entry then return nil end
    return isArabic and entry.ar or entry.en
end

local function idHairColourEntry(hair)
    if type(hair) ~= "table" or (tonumber(hair.model) or 0) <= 0 then
        return false -- no hair model = bald
    end
    local tex = hair.texture
    if type(tex) == "table" and tonumber(tex.tint0) then
        local tint = math.floor(tonumber(tex.tint0))
        for _, entry in ipairs(IdHairColourNames) do
            if entry.t == tint then return entry end
        end
        return IdHairColourNames[(tint % #IdHairColourNames) + 1]
    end
    local variant = math.floor(tonumber(type(tex) == "table" and (tex.palette or tex.model) or tex) or 1)
    return IdHairColourNames[((math.max(1, variant) - 1) % #IdHairColourNames) + 1]
end

-- Height formula (the creator slider label in ui/script.js uses the same one):
--   scale = HeightMin + (slider / 100) * (HeightMax - HeightMin)
--   cm    = round(HeightBaseCm[gender] * scale)
-- Male 180 base: slider 0 -> 171 cm, 50 -> 180 cm, 100 -> 189 cm.
function JRSHeightBaseCm(gender)
    local bases = type(HeightBaseCm) == "table" and HeightBaseCm or {}
    return tonumber(gender == "Female" and bases.Female or bases.Male) or (gender == "Female" and 168 or 180)
end

function JRSHeightToCm(scaleValue, gender)
    scaleValue = tonumber(scaleValue) or 1.0
    return math.floor(JRSHeightBaseCm(gender) * scaleValue + 0.5)
end

function JRSBuildIdCardAppearance()
    local lang = (JrsLang and JrsLang.Current and JrsLang.Current()) or "ar"
    local isArabic = tostring(lang):lower():sub(1, 2) == "ar"
    local out = {}

    local scaleValue = tonumber(CachePedData and CachePedData.height) or 1.0
    if scaleValue > 0.5 and scaleValue < 2.0 then
        out.height = ("%d cm"):format(JRSHeightToCm(scaleValue, CachePedData and CachePedData.gender))
    end

    out.complexion = idNameFor(IdSkinToneNames[math.floor(tonumber(CachePedData and CachePedData.skintone) or 0)], isArabic)
    out.eyes = idNameFor(IdEyeColourNames[math.floor(tonumber(CachePedData and CachePedData.eyes) or 0)], isArabic)

    local hairEntry = idHairColourEntry(hairstyleCache and hairstyleCache["hair"])
    if hairEntry == false then
        out.hair = isArabic and "أصلع" or "Bald"
    else
        out.hair = idNameFor(hairEntry, isArabic)
    end

    return out
end

RegisterNetEvent('jrs_idcard:client:onStudioReturn', function()
    pcall(JRSSetSpawnBookCharacterHidden, false)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, true)
    end
    MoveCam("edit", nil, true)
    Light()
end)

RegisterNUICallback("ContinueCreator", function(data, cb)
    local valid, field = validateCharacterIdentity()
    if not valid then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        SendNUIMessage({ type = "hideEditApparenceMenu" })
        MoveCam("base")
        Wait(800)
        SendNUIMessage({ type = "showCharGlobalMenu" })
        if cb then cb({ ok = false, field = field }) end
        return
    end

    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    DisplayPins = false
    PlaceElem(false)
    EditionMenu(false)
    SendNUIMessage({ type = "closeOutfitMenu" })
    SendNUIMessage({ type = "hideEditApparenceMenu" })
    SendNUIMessage({ type = "hideCharGlobalMenu" })
    Wait(250)

    pcall(JRSSetSpawnBookCharacterHidden, false)
    local myPed = PlayerPedId()
    FreezeEntityPosition(myPed, true)
    MoveCam("edit", nil, true)
    Light()

    local charData = {
        name = ((CharacterName or "") .. " " .. (CharacterSurname or "")):gsub("^%s+", ""):gsub("%s+$", ""),
        firstname = CharacterName or "",
        lastname = CharacterSurname or "",
        birthday = CharacterBirthDate or "",
        gender = CharacterSexe,
    }
    local bYear, bMonth, bDay = tostring(CharacterBirthDate or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if bYear and bMonth and bDay then
        charData.birthday1 = bDay .. " / " .. bMonth
        charData.birthday2 = bYear
        charData.age = 1899 - tonumber(bYear)
    else
        charData.birthday1 = (CharacterBirthDay or "01") .. " / " .. (CharacterBirthMonth or "06")
        charData.birthday2 = CharacterBirthYear or "1875"
        charData.age = 1899 - (tonumber(CharacterBirthYear) or 1875)
    end
    if tonumber(charData.age) and tonumber(charData.age) < 18 then
        charData.age = 25
    end
    do
        local ok, looks = pcall(JRSBuildIdCardAppearance)
        if ok and type(looks) == "table" then
            charData.height = looks.height
            charData.complexion = looks.complexion
            charData.hair = looks.hair
            charData.eyes = looks.eyes
        end
    end

    if GetResourceState('jrs_idcard') == 'started' and exports['jrs_idcard'].StartNewCharacterCreationSession then
        jrsExternalUiFocusActive = true
        -- RedM can silently no-op a SetNuiFocus(true, true) call when it
        -- already believes that is the current value (the same quirk
        -- JRSRecoverNuiCursor above works around) - jrs_character's own
        -- creator page already holds focus at this point, so jrs_idcard's
        -- own setMenu(true)/SetNuiFocus(true, true) call on the registry
        -- form would be exactly that no-op: the page paints (ui_page swap
        -- is separate from focus) but click/keyboard routing never actually
        -- transitions to it, which is why the form could render but not
        -- respond. Release focus for real first so jrs_idcard's own
        -- acquisition is a genuine off->on edge.
        JRSApplyNuiFocus(false, false, false)
        exports['jrs_idcard']:StartNewCharacterCreationSession(charData, function(idCardData)
            jrsExternalUiFocusActive = false
            -- jrs_idcard's own 'create' NUI callback is expected to run
            -- setMenu(false) (a real SetNuiFocus(false, false)) before
            -- calling us, but do not depend on that: force the same real
            -- drop ourselves first so our own reclaim below is always a
            -- genuine off->on edge no matter what jrs_idcard's callback did.
            pcall(SetNuiFocus, false, false)
            JRSApplyNuiFocus(true, true, false)
            PendingIdCardData = idCardData
            RefreshSpawnLocations()
            pcall(JRSSetSpawnBookCharacterHidden, true)
            SendNUIMessage({
                type = "openSpawnMenu",
                spawnLocation = SpawnLocation,
                spawnBook = GetSpawnBookUiConfig(),
            })
        end, function()
            jrsExternalUiFocusActive = false
            -- Cancel ("BACK TO APPEARANCE") reported live as freezing input
            -- even after the create path above worked - jrs_idcard's cancel
            -- callback apparently does not always release focus the same
            -- way its create path does, so JRSApplyNuiFocus(true, true, ...)
            -- here could repeat the same already-true value and no-op. Force
            -- the real drop ourselves first, same as the create path.
            pcall(SetNuiFocus, false, false)
            JRSApplyNuiFocus(true, true, false)
            PlaySound("BACK", "HUD_SHOP_SOUNDSET")
            pcall(JRSSetSpawnBookCharacterHidden, false)
            MoveCam("edit")
            Wait(250)
            LoadApparenceMenu()
            DisplayPins = true
            OpenApperanceMenu()
        end)
    else
        RefreshSpawnLocations()
        pcall(JRSSetSpawnBookCharacterHidden, true)
        SendNUIMessage({
            type = "openSpawnMenu",
            spawnLocation = SpawnLocation,
            spawnBook = GetSpawnBookUiConfig(),
        })
    end

    if cb then cb({ ok = true }) end
end)

-- Lets the player return from the spawn-city book to the identity registration
-- or appearance/clothing editor without losing anything.
RegisterNUICallback("BackToApparenceFromSpawn", function(data, cb)
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    SendNUIMessage({ type = "hideSpawnMenu" })
    pcall(JRSSetSpawnBookCharacterHidden, false)
    local myPed = PlayerPedId()
    FreezeEntityPosition(myPed, true)
    MoveCam("edit", nil, true)
    Light()
    Wait(250)

    local charData = {
        name = PendingIdCardData and PendingIdCardData.name or (((CharacterName or "") .. " " .. (CharacterSurname or "")):gsub("^%s+", ""):gsub("%s+$", "")),
        firstname = CharacterName or "",
        lastname = CharacterSurname or "",
        birthday1 = PendingIdCardData and PendingIdCardData.birthday1 or "01 / 06",
        birthday2 = PendingIdCardData and PendingIdCardData.birthday2 or "1875",
        age = PendingIdCardData and PendingIdCardData.age or 24,
        picture = PendingIdCardData and PendingIdCardData.picture or nil,
        height = PendingIdCardData and PendingIdCardData.height or nil,
        complexion = PendingIdCardData and PendingIdCardData.complexion or nil,
        hair = PendingIdCardData and PendingIdCardData.hair or nil,
        eyes = PendingIdCardData and PendingIdCardData.eyes or nil,
        marks = PendingIdCardData and PendingIdCardData.marks or nil,
    }
    -- Anything the player left blank on the registry falls back to the
    -- auto-filled appearance description.
    do
        local ok, looks = pcall(JRSBuildIdCardAppearance)
        if ok and type(looks) == "table" then
            for _, key in ipairs({ "height", "complexion", "hair", "eyes" }) do
                if charData[key] == nil or charData[key] == "" then
                    charData[key] = looks[key]
                end
            end
        end
    end

    if GetResourceState('jrs_idcard') == 'started' and exports['jrs_idcard'].StartNewCharacterCreationSession then
        jrsExternalUiFocusActive = true
        -- Same genuine-edge fix as ContinueCreator above - release focus
        -- for real before handing off, or jrs_idcard's own focus acquisition
        -- can be a silent no-op against jrs_character's still-held focus.
        JRSApplyNuiFocus(false, false, false)
        exports['jrs_idcard']:StartNewCharacterCreationSession(charData, function(idCardData)
            jrsExternalUiFocusActive = false
            -- Force a genuine off->on edge ourselves - see ContinueCreator
            -- above for why this cannot depend on jrs_idcard's own release.
            pcall(SetNuiFocus, false, false)
            JRSApplyNuiFocus(true, true, false)
            PendingIdCardData = idCardData
            RefreshSpawnLocations()
            pcall(JRSSetSpawnBookCharacterHidden, true)
            SendNUIMessage({
                type = "openSpawnMenu",
                spawnLocation = SpawnLocation,
                spawnBook = GetSpawnBookUiConfig(),
            })
        end, function()
            jrsExternalUiFocusActive = false
            pcall(SetNuiFocus, false, false)
            JRSApplyNuiFocus(true, true, false)
            pcall(JRSSetSpawnBookCharacterHidden, false)
            MoveCam("edit")
            Wait(250)
            LoadApparenceMenu()
            DisplayPins = true
            OpenApperanceMenu()
        end)
    else
        LoadApparenceMenu()
        DisplayPins = true
        OpenApperanceMenu()
    end

    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("CreateChar", function(data, cb)
    -- Normal character creation flow
    CharacterName = nil
    SendNUIMessage({ type = "getAllCharDatas", })
    local identityDeadline = GetGameTimer() + 5000
    repeat
        Wait(100)
    until CharacterName ~= nil or GetGameTimer() >= identityDeadline
    if CharacterName == nil then
        if cb then cb({ ok = false, reason = 'identity_timeout' }) end
        return
    end
    if tostring(CharacterName) == "" or tostring(CharacterSurname) == "" or tostring(CharacterBirthDay) == "" or tostring(CharacterBirthMonth) == "" or tostring(CharacterBirthYear) == "" or tostring(CharacterLore) == "" then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        CreatorDebug("Missing informations, please fill all fields")
    else
        PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
        SendNUIMessage(
            {
                type = "hideCharGlobalMenu",
            }
        )
        Wait(1000)
        pcall(JRSSetSpawnBookCharacterHidden, true)
        SendNUIMessage(
            {
                type = "openSpawnMenu",
                spawnLocation = RefreshSpawnLocations(),
                spawnBook = GetSpawnBookUiConfig(),
            }
        )
    end
    if cb then cb({ ok = true }) end
end)

local canspawn = true

RegisterNUICallback("spawnPreview", function(data, cb)
    local location = ResolveSpawnLocation(data)
    if not location then
        if cb then cb({ ok = false, reason = 'no_location' }) end
        return
    end

    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    canspawn = false
    SetEntityCoords(PlayerPedId(), location.pedspawn)
    SetEntityHeading(PlayerPedId(), location.pedspawnheading)
    FreezeEntityPosition(PlayerPedId(), true)
    pcall(JRSSetSpawnBookCharacterHidden, true)
    DoScreenFadeOut(600)

    for _, ped in pairs(charselectpeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end

    Wait(650)
    Citizen.InvokeNative("0x387AD749E3B69B70", location.coords, 0.0, 0.0, 0.0, 5.0, 0)
    local timeout = GetGameTimer() + 8000
    while not IsLoadSceneLoaded() and GetGameTimer() < timeout do Wait(100) end
    Citizen.InvokeNative("0x5A8B01199C3E79C3")

    MoveCam(location.name, {
        coords = location.coords,
        target = location.target,
        fov = location.fov,
    }, true)

    Wait(350)
    DoScreenFadeIn(650)
    canspawn = true
    if cb then cb({ ok = true }) end
end)


RegisterNUICallback("spawnCharacter", function(data, cb)
    if canspawn then
        canspawn = false -- Prevent multiple clicks
        local selectedLocation = ResolveSpawnLocation(data)
        if not selectedLocation then
            canspawn = true
            PlaySound("UNAFFORDABLE", "Ledger_Sounds")
            if cb then cb("no_location") end
            return
        end
        local spawnLocationId = selectedLocation.id
        local spawnLocationName = selectedLocation.name
        PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
        JRSApplyNuiFocus(false, false, false)
        DoScreenFadeOut(500)
        data.firstname = CharacterName
        data.lastname = CharacterSurname
        data.nickname = CharacterTitle
        data.occupation = CharacterOccupation
        data.coords = selectedLocation.pedspawn
        data.lore = CharacterLore
        data.birthdate = CharacterBirthDate
        data.birthday = CharacterBirthDay
        data.birthmonth = CharacterBirthMonth
        data.birthyear = CharacterBirthYear
        data.gender = CachePedData.gender
        data.pedspawn = selectedLocation.pedspawn
        data.pedspawnheading = selectedLocation.pedspawnheading
        data.spawnLocationKey = selectedLocation.key
        data.skintone = CachePedData.skintone
        local skinSet = getCurrentDefaultSkinSet()
        local headComponent, headIndex = clampAppearanceIndex(CachePedData.head, skinSet and skinSet.Heads)
        local upperComponent, upperIndex
        if tonumber(CachePedData.upperbody) == 0 then
            upperIndex = 0
            upperComponent = nil
        else
            upperComponent, upperIndex = clampAppearanceIndex(CachePedData.upperbody, skinSet and skinSet.Body)
        end
        local lowerComponent, lowerIndex
        if tonumber(CachePedData.lowerbody) == 0 then
            lowerIndex = 0
            lowerComponent = nil
        else
            lowerComponent, lowerIndex = clampAppearanceIndex(CachePedData.lowerbody, skinSet and skinSet.Legs)
        end
        data.head = hexComponentToNumber(headComponent)
        data.body = upperComponent and hexComponentToNumber(upperComponent) or 0
        data.legs = lowerComponent and hexComponentToNumber(lowerComponent) or 0
        CachePedData.head = headIndex or 1
        CachePedData.upperbody = upperIndex or 0
        CachePedData.lowerbody = lowerIndex or 0
        DeleteObject(lamp)
        DeleteObject(lamp2)
        SwitchOffCam(true)
        CreatorLight = false
        SendNUIMessage(
            {
                type = "hideSpawnMenu",
            }
        )
        SetEntityCoords(PlayerPedId(), selectedLocation.pedspawn)
        SetEntityHeading(PlayerPedId(), selectedLocation.pedspawnheading)
        FreezeEntityPosition(PlayerPedId(), true)
        pcall(JRSSetSpawnBookCharacterHidden, true)
        local creationResponseReceived = false
        SetTimeout(30000, function()
            if creationResponseReceived or JRSCharacterSpawnComplete == true then return end
            canspawn = true
            TriggerEvent('jrs_character_creator:SelectionFailed',
                _U('ch_character_creation_timed_out'))
        end)

        -- Send the complete creator state in one transaction. The creator has
        -- its own clothing and barber editors, but uses the normal JRS tables.
        data._clothes = GetCreatorClothesCache()
        data._barber = {
            hairstyle = deepcopy(hairstyleCache or {}),
            overlays = deepcopy(overlay_all_layers or {}),
            permanentoverlay = {},
            isMale = IsPedMale(PlayerPedId())
        }

        Callback.triggerServer('jrs_character_creator:CreateNewCharacter', function(createdCharacter)
            creationResponseReceived = true
            canspawn = true
            if createdCharacter then
                CreatorDebug("Character, clothing and barber data saved successfully")
                if PendingIdCardData then
                    TriggerServerEvent('jrs_idcard:server:finalizeNewCharacterId', {
                        charData = {
                            charIdentifier = createdCharacter.charIdentifier or createdCharacter.charid,
                            name = PendingIdCardData.name or ((CharacterName or '') .. ' ' .. (CharacterSurname or '')),
                            age = PendingIdCardData.age,
                            birthday1 = PendingIdCardData.birthday1,
                            birthday2 = PendingIdCardData.birthday2,
                        },
                        city = spawnLocationName or (selectedLocation and selectedLocation.name) or 'Valentine',
                        picture = PendingIdCardData.picture,
                        name = PendingIdCardData.name,
                        age = PendingIdCardData.age,
                        birthday1 = PendingIdCardData.birthday1,
                        birthday2 = PendingIdCardData.birthday2,
                        height = PendingIdCardData.height,
                        complexion = PendingIdCardData.complexion,
                        hair = PendingIdCardData.hair,
                        eyes = PendingIdCardData.eyes,
                        marks = PendingIdCardData.marks,
                    })
                    PendingIdCardData = nil
                end
                -- The server also sends FinalizeCharacter directly. This local
                -- call is a safe fallback and is ignored by the spawn guard.
                TriggerEvent('jrs_character_creator:FinalizeCharacter', createdCharacter)
            else
                TriggerEvent('jrs_character_creator:SelectionFailed',
                    _U('ch_character_creation_failed_try_again'))
            end
        end, data, CachePedData)
        cb("ok")
    else
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        CreatorDebug("You cannot spawn yet, please wait")
        cb("busy")
    end
end)


RegisterNUICallback("EditChart", function(data, cb)
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    if changingGender == true then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        if cb then cb({ ok = false, reason = 'busy' }) end
        return
    end

    SendNUIMessage(
        {
            type = "hideCharGlobalMenu",
        }
    )
    MoveCam("edit")
    Wait(1200)
    LoadApparenceMenu()
    DisplayPins = true
    OpenApperanceMenu()
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("CharValues", function(data, cb)
    applyCharacterIdentity(data)
    if cb then cb({ ok = true }) end
end)

-- The creator's date picker used to bound itself with the real-world clock, so
-- it demanded a modern birth year. It now asks for the world's own date instead
-- and bounds itself against that, which keeps the picker, the client-side
-- check and the server's authoritative check all measuring from the same year.
RegisterNUICallback("getCreatorEra", function(_, cb)
    local world = type(Config) == 'table' and type(Config.WorldDate) == 'table' and Config.WorldDate or {}
    if cb then
        cb({
            year  = math.floor(tonumber(world.year) or 1899),
            month = math.max(1, math.min(12, math.floor(tonumber(world.month) or 1))),
            day   = math.max(1, math.min(31, math.floor(tonumber(world.day) or 1))),
            minimumAge = math.max(1, math.floor(tonumber(Config and Config.MinimumAge) or 18)),
            earliestBirthYear = math.floor(tonumber(Config and Config.EarliestBirthYear) or 1790),
        })
    end
end)


RegisterNUICallback("sexeStatusChanged", function(data, cb)
    if changingGender == false then
        changingGender = true
        CachePedData = deepcopy(DefaultCachePedData)
        SendNUIMessage(
            {
                type = "changeuserSexe",
                userSexe = data.currentSexe,
            }
        )
        local currentSexe = data.currentSexe
        PlaySound("Amount_Increase", "HUD_Donate_Sounds")
        CreatorLight = false
        Wait(1000)

        local model = "mp_male"
        if currentSexe == "Female" then model = "mp_female" end
        CachePedData.gender = currentSexe
        CachePedData.pedmodel = { model = model, outfit = 0 }
        local coords = CreatorConfig.CharSelect.playerSpawn.coords
        local heading = CreatorConfig.CharSelect.playerSpawn.heading
        RequestModel(GetHashKey(model))
        local sexeModelDeadline = GetGameTimer() + 8000
        while not HasModelLoaded(GetHashKey(model)) and GetGameTimer() < sexeModelDeadline do
            Wait(1)
        end
        if not HasModelLoaded(GetHashKey(model)) then
            CreatorDebug("^3[jrs_character] sexeStatusChanged: " .. model .. " failed to stream within 8s, continuing with best-effort ped.^7")
        end
        if CachePed ~= PlayerPedId() then
            DeleteEntity(CachePed)
        end
        JRSSafeSetPlayerModel(GetHashKey(model))
        CachePed = PlayerPedId()
        Wait(10)
        EquipMetaPedOutfitPreset(CachePed, 0, false)

        ApplyCachePedDataToPedPlayer()
        RemoveAllClothesExceptEssentials(CachePed)
        ResetCreatorClothingCache(true)
        ApplyCreatorStarterOutfit()
        Light()
        SetEntityCoordsNoOffset(CachePed, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(CachePed, heading)
        hairstyleCache = {}
        local selectedgender = "female"
        if CachePedData.gender == "Male" then selectedgender = "male" end
        for k, v in pairs(JRS_ASSETS[selectedgender]) do
            if hairstyleCache[k] == nil then
                hairstyleCache[k] = {}
                hairstyleCache[k].model = 0
                hairstyleCache[k].texture = 0
            end
        end
        Wait(1500)
        changingGender = false
    else
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
    end
    if cb then cb({ ok = true }) end
end)

local cachePedSelection, cachePedVariation = 0, 0
local pedwarning = false
RegisterNUICallback("pedValue", function(data, cb)
    local model = data.id
    local outfit = tonumber(data.item)
    if outfit == nil then outfit = 0 end
    outfit = outfit - 1
    if outfit < 0 then outfit = 0 end
    if cachePedSelection == model and cachePedVariation == outfit then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        if cb then cb({ ok = true, unchanged = true }) end
        return
    end
    local cachegender = CachePedData.gender
    CachePedData = deepcopy(DefaultCachePedData)
    CachePedData.gender = cachegender
    if model ~= cachePedSelection then
        PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
        cachePedSelection = model
        cachePedVariation = outfit
    else
        if cachePedVariation > outfit then
            PlaySound("Amount_Decrease", "HUD_Donate_Sounds")
        else
            PlaySound("Amount_Increase", "HUD_Donate_Sounds")
        end
        cachePedVariation = outfit
    end
    CachePedData.pedmodel = { model = model, outfit = outfit }

    NPCAssetsToPed(model, outfit)
    RemoveAllClothesExceptEssentials(PlayerPedId(), true)
    DisplayHud(true)
    if pedwarning == false then
        pedwarning = true
        local notifyDuration = 10 * 1000
        CharacterNotify(_U('ch_warning_title'), _U('creator_ped_warning'), notifyDuration)
        Citizen.SetTimeout(notifyDuration, function()
            DisplayHud(false)
        end)
        Citizen.SetTimeout(60 * 5 * 1000, function()
            pedwarning = false
        end)
    end
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("PedSelection", function(data, cb)
    if PedAccess == false then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        if cb then cb({ ok = false, reason = "ped_access_denied" }) end
        return
    end
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    SendNUIMessage({ type = "getAllCharDatas", })
    Wait(100)
    SendNUIMessage({ type = "hideCharGlobalMenu", })
    local count = 0
    local modelcount = 0
    local pedtoshow = {}
    for k, v in pairs(PedList[CharacterSexe]) do
        if not string.find(v.name, "cs_") then
            count = count + v.totalAmount
            table.insert(pedtoshow, v)
            modelcount = modelcount + 1
        end
    end
    SendNUIMessage(
        {
            type = "showPedsList",
            pedsList = pedtoshow,
        }
    )
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("PedTrueFalse", function(data, cb)
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    local userPed = data.userPed
    if userPed == "false" and CachePedData.pedmodel.model ~= "mp_male" and CachePedData.pedmodel.model ~= "mp_female" then
        CreatorLight = false
        Wait(1000)
        local model = "mp_male"
        local gender = CachePedData.gender
        CachePedData = deepcopy(DefaultCachePedData)
        CachePedData.gender = gender
        if CachePedData.gender == "Female" then model = "mp_female" end

        CachePedData.pedmodel = { model = model, outfit = 0 }
        local coords = CreatorConfig.CharSelect.playerSpawn.coords
        local heading = CreatorConfig.CharSelect.playerSpawn.heading
        RequestModel(GetHashKey(model))
        local pedToggleModelDeadline = GetGameTimer() + 8000
        while not HasModelLoaded(GetHashKey(model)) and GetGameTimer() < pedToggleModelDeadline do
            Wait(1)
        end
        if not HasModelLoaded(GetHashKey(model)) then
            CreatorDebug("^3[jrs_character] PedTrueFalse: " .. model .. " failed to stream within 8s, continuing with best-effort ped.^7")
        end
        if CachePed ~= PlayerPedId() then
            DeleteEntity(CachePed)
        end
        JRSSafeSetPlayerModel(GetHashKey(model))
        CachePed = PlayerPedId()
        Wait(10)
        EquipMetaPedOutfitPreset(CachePed, 0, false)
        ApplyCachePedDataToPedPlayer()
        RemoveAllClothesExceptEssentials(CachePed)
        Light()
        SetEntityCoordsNoOffset(CachePed, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(CachePed, heading)
    end
    if cb then cb({ ok = true }) end
end)


RegisterNUICallback("cancelPedSelection", function(data, cb)
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    SendNUIMessage(
        {
            type = "showCharGlobalMenu",
        }
    )
    -- DisplayHud(false)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("globalApparence", function(data, cb)
    data = type(data) == "table" and data or {}
    local item = tonumber(data.item)
    local elem = tostring(data.elem or "")
    local applied = false

    if eyesanim then
        eyesanim = false
        ClearPedTasks(CachePed)
    end

    if processingcam == true then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        if cb then cb({ ok = false, reason = "camera_busy" }) end
        return
    end

    local skinSet = getCurrentDefaultSkinSet()

    if elem == "tooth" then
        local teethList = type(Teeth) == "table" and Teeth[CachePedData.gender] or nil
        local tooth, safeIndex = clampAppearanceIndex(item, teethList)
        local toothHash = tooth and (tonumber(tooth.hash) or tonumber(tooth.hash_dec_signed)) or nil
        if toothHash then
            teethanim = true
            if not HasAnimDictLoaded("FACE_HUMAN@GEN_MALE@BASE") then
                RequestAnimDict("FACE_HUMAN@GEN_MALE@BASE")
                local animDeadline = GetGameTimer() + 8000
                repeat Wait(0) until HasAnimDictLoaded("FACE_HUMAN@GEN_MALE@BASE") or GetGameTimer() >= animDeadline
                if not HasAnimDictLoaded("FACE_HUMAN@GEN_MALE@BASE") then
                    CreatorDebug("^3[jrs_character] globalApparence(tooth): anim dict failed to load within 8s, skipping preview animation.^7")
                end
            end

            if not IsEntityPlayingAnim(CachePed, "FACE_HUMAN@GEN_MALE@BASE", "Face_Dentistry_Loop", 1) then
                TaskPlayAnim(CachePed, "FACE_HUMAN@GEN_MALE@BASE", "Face_Dentistry_Loop", 1.0, -1.0, -1, 16,
                    0.0, false, 0, false, "", false)
            end

            IsPedReadyToRender(CachePed)
            ApplyShopItemToPed(toothHash, CachePed)
            UpdatePedVariation(CachePed)
            CachePedData.teeth = safeIndex
            applied = true
        end
    elseif elem == "head" then
        local component, safeIndex = clampAppearanceIndex(item, skinSet and skinSet.Heads)
        local hash = hexComponentToNumber(component)
        if not hash and skinSet and skinSet.Heads and skinSet.Heads[1] then
            component = skinSet.Heads[1]
            safeIndex = 1
            hash = hexComponentToNumber(component)
        end
        if hash then
            IsPedReadyToRender(CachePed)
            ApplyShopItemToPed(hash, CachePed)
            UpdatePedVariation(CachePed)
            CachePedData.head = safeIndex
            UpdateOverlay(CachePed)
            applied = true
        end
    elseif elem == "body" then
        local component, safeIndex = clampAppearanceIndex(item, Body)
        if component then
            IsPedReadyToRender(CachePed)
            EquipMetaPedOutfit(tonumber(component), CachePed)
            UpdatePedVariation(CachePed)
            CachePedData.body = safeIndex
            applied = true
        end
    elseif elem == "waist" then
        local component, safeIndex = clampAppearanceIndex(item, Waist)
        if component then
            IsPedReadyToRender(CachePed)
            EquipMetaPedOutfit(tonumber(component), CachePed)
            UpdatePedVariation(CachePed)
            CachePedData.waist = safeIndex
            applied = true
        end
    elseif elem == "legs" then
        if false then -- "Hidden" (0) removed: 0 now falls through and clamps to the first mesh
            IsPedReadyToRender(CachePed)
            Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x823687F5, 0)
            NativeUpdatePedVariation(CachePed)
            CachePedData.lowerbody = 0
            applied = true
        else
            local component, safeIndex = clampAppearanceIndex(item, skinSet and skinSet.Legs)
            local hash = hexComponentToNumber(component)
            if hash then
                IsPedReadyToRender(CachePed)
                ApplyShopItemToPed(hash, CachePed)
                UpdatePedVariation(CachePed)
                CachePedData.lowerbody = safeIndex
                applied = true
            end
        end
    elseif elem == "upper" then
        if false then -- "Hidden" (0) removed: 0 now falls through and clamps to the first mesh
            IsPedReadyToRender(CachePed)
            Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x0B3966C9, 0)
            NativeUpdatePedVariation(CachePed)
            CachePedData.upperbody = 0
            applied = true
        else
            local component, safeIndex = clampAppearanceIndex(item, skinSet and skinSet.Body)
            local hash = hexComponentToNumber(component)
            if hash then
                IsPedReadyToRender(CachePed)
                ApplyShopItemToPed(hash, CachePed)
                UpdatePedVariation(CachePed)
                CachePedData.upperbody = safeIndex
                applied = true
            end
        end
    elseif elem == "height" then
        local safeValue = math.max(0, math.min(100, tonumber(item) or 50))
        local outputvalue = scale(safeValue, 0, 100, HeightMin, HeightMax)
        IsPedReadyToRender(CachePed)
        SetPedScale(CachePed, outputvalue)
        UpdatePedVariation(CachePed)
        CachePedData.height = outputvalue
        applied = true
    end

    if applied then UpdatePedVariation(CachePed) end
    if applied and (elem == "body" or elem == "waist" or elem == "upper" or elem == "legs") then
        CreatorFitAndReseat(CachePed)
    end

    if type(ApplyCharacterExpressions) == "function" then
        ApplyCharacterExpressions(CachePed, CachePedData.expressions)
    elseif type(CachePedData.expressions) == "table" and ExpressionsHashes then
        for key, value in pairs(CachePedData.expressions) do
            local expressionHash = ExpressionsHashes[key]
            if expressionHash then
                SetCharExpression(CachePed, expressionHash, tonumber(value) or 0.0)
            end
        end
    end

    if cb then cb({ ok = applied }) end
end)

RegisterNUICallback("SkinColourValue", function(data, cb)
    data = type(data) == "table" and data or {}
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")

    local gender = CachePedData.gender == "Female" and "Female" or "Male"
    local genderSet = type(DefaultChar) == "table" and DefaultChar[gender] or nil
    if type(genderSet) ~= "table" or #genderSet == 0 then
        if cb then cb({ ok = false }) end
        return
    end

    local item = math.floor(tonumber(data.item) or 1)
    if item < 1 then item = 1 end
    if item > #genderSet then item = #genderSet end

    CachePedData.gender    = gender
    CachePedData.skintone  = item
    CachePedData.lowerbody = 1
    CachePedData.upperbody = 1
    CachePedData.head      = 1

    local skinColor        = genderSet[item]
    local legs             = hexComponentToNumber(skinColor and skinColor.Legs and skinColor.Legs[1])
    local bodyType         = hexComponentToNumber(skinColor and skinColor.Body and skinColor.Body[1])
    local heads            = hexComponentToNumber(skinColor and skinColor.Heads and skinColor.Heads[1])
    local headtextureName  = skinColor and skinColor.HeadTexture and skinColor.HeadTexture[1]
    local headtexture      = headtextureName and joaat(headtextureName) or nil
    local textureType      = type(texture_types) == "table" and texture_types[gender] or nil
    local albedo           = textureType and textureType.albedo or nil

    IsPedReadyToRender(CachePed)
    if heads then ApplyShopItemToPed(heads, CachePed) end
    if bodyType then ApplyShopItemToPed(bodyType, CachePed) end
    if legs then ApplyShopItemToPed(legs, CachePed) end
    if albedo and headtexture then
        Citizen.InvokeNative(0xC5E7204F322E49EB, albedo, headtexture, 0x7FC5B1E1)
    end

    UpdateOverlay(CachePed)
    UpdatePedVariation(CachePed)
    CreatorFitAndReseat(CachePed)

    -- Every skin-tone set has a different amount of upper/lower body hashes.
    -- Refresh the UI slider limits after changing the skin tone.
    LoadApparenceMenu()
    if cb then cb({ ok = true, item = item }) end
end)


RegisterNUICallback("EyeColourValue", function(data, cb)
    data = type(data) == "table" and data or {}
    local gender = CachePedData.gender == "Female" and "Female" or "Male"
    local eyeHash, item = clampAppearanceIndex(data.item, type(Eyes) == "table" and Eyes[gender] or nil)

    if not eyeHash then
        if cb then cb({ ok = false }) end
        return
    end

    if processingcam == true then
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
        if cb then cb({ ok = false, reason = "camera_busy" }) end
        return
    end

    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    if camOnHead == false and data.skipCameraFocus ~= true then
        camOnHead = true
        processingcam = true
        MoveCam("head")
        DisplayPins = false
        Wait(1000)
        processingcam = false
    end

    eyesanim = true
    if not HasAnimDictLoaded("FACE_HUMAN@GEN_MALE@BASE") then
        RequestAnimDict("FACE_HUMAN@GEN_MALE@BASE")
        local animDeadline = GetGameTimer() + 8000
        repeat Wait(0) until HasAnimDictLoaded("FACE_HUMAN@GEN_MALE@BASE") or GetGameTimer() >= animDeadline
        if not HasAnimDictLoaded("FACE_HUMAN@GEN_MALE@BASE") then
            CreatorDebug("^3[jrs_character] EyeColourValue: anim dict failed to load within 8s, skipping preview animation.^7")
        end
    end

    if not IsEntityPlayingAnim(CachePed, "FACE_HUMAN@GEN_MALE@BASE", "mood_normal_eyes_wide", 1) then
        TaskPlayAnim(CachePed, "FACE_HUMAN@GEN_MALE@BASE", "mood_normal_eyes_wide", 1.0, -1.0, -1, 16, 0.0,
            false, 0, false, "", false)
    end

    IsPedReadyToRender(CachePed)
    ApplyShopItemToPed(tonumber(eyeHash), CachePed)
    UpdatePedVariation(CachePed)
    CachePedData.eyes = item
    if cb then cb({ ok = true, item = item }) end
end)

local savingSecondChance = false
RegisterNUICallback("CancelApparenceEdition", function(data, cb)
    if savingSecondChance then
        if cb then cb({ ok = false, reason = 'busy' }) end
        return
    end
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    processingcam = false
    camOnHead = false
    teethanim = false
    eyesanim = false
    ClearPedTasks(CachePed)
    DisplayPins = false
    
    -- Check if we're in Second Chance mode (cancel without saving)
    if SecondChanceMode or (data and data.secondChanceMode) then
        SendNUIMessage({ type = "hideGlobalCharacterMenu" })
        JRSApplyNuiFocus(false, false, false)
        DisplayRadar(true)
        
        -- Clean up lights and camera
        SwitchOffCam(true)
        CreatorLight = false
        DeleteObject(lamp)
        DeleteObject(lamp2)
        
        -- Reset second chance mode
        SecondChanceMode = false
        
        -- Reload the original creator face/body data from the database.
        Wait(500)
        TriggerEvent("jrs_character_creator:loadskinjrs")
        if cb then cb({ ok = true }) end
        return
    end
    
    -- Normal mode: go back to character menu
    SendNUIMessage(
        {
            type = "hideEditApparenceMenu",
        }
    )
    MoveCam("base")
    Wait(1200)
    SendNUIMessage(
        {
            type = "showCharGlobalMenu",
        }
    )
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("resetApparenceEdition", function(data, cb)
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    local gender = CachePedData.gender
    CachePedData = deepcopy(DefaultCachePedData)
    CachePedData.gender = gender
    CachePedData.pedmodel = { model = gender == 'Female' and 'mp_female' or 'mp_male', outfit = 0 }
    ApplyCachePedDataToPedPlayer()
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("UndressApparenceEdition", function(data, cb)
    if CachePedData.pedmodel.model == "mp_male" or CachePedData.pedmodel.model == "mp_female" then
        RemoveAllClothesExceptEssentials(CachePed)
        PlaySound("Select", "HUD_SHOP_SOUNDSET")
    else
        PlaySound("UNAFFORDABLE", "Ledger_Sounds")
    end
    if cb then cb({ ok = true }) end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Second Chance - Save skin and close
-- ═══════════════════════════════════════════════════════════════════════════
RegisterNUICallback("SaveSecondChance", function(data, cb)
    if savingSecondChance or not SecondChanceMode then
        if cb then cb({ ok = false, reason = savingSecondChance and 'busy' or 'not_editing' }) end
        return
    end
    savingSecondChance = true
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")

    local function finishSecondChance()
        DisplayPins = false
        SendNUIMessage({ type = "hideGlobalCharacterMenu" })
        JRSApplyNuiFocus(false, false, false)
        DisplayRadar(true)
        SwitchOffCam(true)
        CreatorLight = false
        DeleteObject(lamp)
        DeleteObject(lamp2)
        SecondChanceMode = false
        Wait(500)
        TriggerEvent("jrs_character_creator:loadskin")
    end

    Callback.triggerServer('jrs_character_creator:SaveAppearance', function(success, reason)
        savingSecondChance = false
        if not success then
            CreatorDebug("[jrs_character_creator] SecondChance: Failed to save skin data")
            PlaySound("UNAFFORDABLE", "Ledger_Sounds")
            if cb then cb({ ok = false, reason = reason or 'save_failed' }) end
            return
        end
        finishSecondChance()
        if cb then cb({ ok = true }) end
    end, CachePedData, overlay_all_layers or {}, hairstyleCache or {}, GetCreatorClothesCache())
end)


--- Callback for char selection
local SelectedChar = nil
local isSelectingChar = false
RegisterNUICallback("selectedChar", function(data, cb)
    -- Prevent rapid clicking
    if isSelectingChar then
        CreatorDebug("[jrs_character_creator] Character selection in progress, please wait...")
        cb("busy")
        return
    end
    isSelectingChar = true
    
    SendNUIMessage(
        {
            type = "hideSelectCharMenu",
        }
    )
    PlaySound("Select", "HUD_SHOP_SOUNDSET")
    local pinId = tonumber(data.pinId)
    if not pinId or not PlayerInfo[pinId] or not charselectpeds[pinId] or not DoesEntityExist(charselectpeds[pinId]) then
        isSelectingChar = false
        SendNUIMessage({ type = "openSelectCharMenu", pinsSelectChar = buildSelectorPinsSnapshot(), canCreate = selectorCanCreate, currentCharacters = selectorCharacterCount, maxCharacters = selectorSlotLimit })
        if cb then cb("invalid") end
        return
    end

    local pinName = data.pinName
    SelectedChar = pinId
    MoveCam("selected", nil, nil, charselectpeds[pinId])
    -- MoveCam("selectedped",  {
    --         coords = GetCamCoord(ActualCamera),
    --         target = GetOffsetFromEntityInWorldCoords(charselectpeds[pinId], 0.2, 0.0, 0.2),
    --         fov = 10.0
    --     }, false, charselectpeds[pinId])
    local charinfo = PlayerInfo[SelectedChar]
    local currentCharacters, maxCharacters = 0, 0
    if type(JRSGetCharacterSelectionCounts) == 'function' then
        currentCharacters, maxCharacters = JRSGetCharacterSelectionCounts()
    end

    local charadata = {
        name = charinfo.firstname .. " " .. charinfo.lastname,
        money = tonumber(charinfo.money) or 0,
        gold = tonumber(charinfo.gold) or 0,
        dirtymoney = tonumber(charinfo.dirtymoney) or 0,
        currentCharacters = tonumber(currentCharacters) or 0,
        maxCharacters = tonumber(maxCharacters) or 0,
        job = charinfo.job or "unemployed",
        grade = tonumber(charinfo.grade) or 0,
        lastLocation = charinfo.lastLocation or "Unknown",
        age = tonumber(charinfo.age),
        height = tonumber(charinfo.height) or 1.0,
        playtimeHours = tonumber(charinfo.playtimeHours) or 0,
        hoursPerYear = tonumber(charinfo.hoursPerYear) or tonumber(Config and Config.HoursPerYear) or 100,
        DayBirth = charinfo.informations.birthday or nil,
        MonthBirth = charinfo.informations.birthmonth or nil,
        YearBirth = charinfo.informations.birthyear or nil,
    }
    SendNUIMessage(
        {
            type = "openSelectedCharMenu",
            selectedDataChar = charadata,

        }
    )
    
    -- Reset flag after a delay
    SetTimeout(800, function()
        isSelectingChar = false
    end)
    
    cb("ok")
end)

RegisterNUICallback("PlaySelectedChar", function(data, cb)
    -- Prevent double-clicking  
    if isSelectingChar then
        CreatorDebug("[jrs_character_creator] Action in progress, please wait...")
        cb("busy")
        return
    end
    isSelectingChar = true
    
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    TriggerEvent("jrs_character_creator:PlaySelectedChar", SelectedChar)

    -- The adapter keeps selector peds alive until the server confirms that
    -- the character was selected. This allows the menu to recover cleanly
    -- when selection fails instead of leaving the player on a black screen.
    SendNUIMessage(
        {
            type = "hideSelectedCharMenu",
        }
    )
    SendNUIMessage(
        {
            type = "hideSelectCharMenu",
        }
    )
    JRSApplyNuiFocus(false, false, false)

    -- Do not permanently lock the Play button if the server rejects or times
    -- out the request. The adapter still blocks duplicate in-flight requests.
    SetTimeout(1500, function()
        isSelectingChar = false
    end)

    cb("ok")
end)

RegisterNUICallback("DeleteSelectedChar", function(data, cb)
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    DoScreenFadeOut(500)
    Wait(500)
    for k, v in pairs(charselectpeds) do
        if DoesEntityExist(v) then
            DeleteEntity(v)
        end
    end
    SendNUIMessage(
        {
            type = "hideSelectedCharMenu",
        }
    )
    local charIdentifier = PlayerInfo[SelectedChar] and PlayerInfo[SelectedChar].characterid or SelectedChar
    TriggerServerEvent("jrs_character_creator:deleteCharacter", charIdentifier)
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("CancelSelectedChar", function(data, cb)
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    local selectionCamera = type(JRSGetCharacterSelectionCameraData) == 'function'
        and JRSGetCharacterSelectionCameraData() or DecorSettings.charselectcam
    MoveCam("charselect", selectionCamera, false)
    SendNUIMessage(
        {
            type = "hideSelectedCharMenu",
        }
    )
    Wait(1000)
    local canCreate = type(JRSCanCreateCharacterFromSelector) == 'function'
        and JRSCanCreateCharacterFromSelector() or false
    local currentCharacters, maxCharacters = 0, 0
    if type(JRSGetCharacterSelectionCounts) == 'function' then
        currentCharacters, maxCharacters = JRSGetCharacterSelectionCounts()
    end
    SendNUIMessage(
        {
            type = "openSelectCharMenu",
            pinsSelectChar = headsonscreen,
            canCreate = canCreate,
            currentCharacters = tonumber(currentCharacters) or 0,
            maxCharacters = tonumber(maxCharacters) or 0,
        }
    )
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("createNewChar", function(data, cb)
    local canCreate = type(JRSCanCreateCharacterFromSelector) == 'function'
        and JRSCanCreateCharacterFromSelector() or false

    if not canCreate then
        local currentCharacters, maxCharacters = 0, 0
        if type(JRSGetCharacterSelectionCounts) == 'function' then
            currentCharacters, maxCharacters = JRSGetCharacterSelectionCounts()
        end
        if not (type(IsJRSCharacterUiSuppressed) == 'function' and IsJRSCharacterUiSuppressed()) then
            TriggerEvent('jrs_core:sendRightTipNotification',
                _U('ch_you_have_reached_the_character_limit',
                    tonumber(currentCharacters) or 0, tonumber(maxCharacters) or 0),
                4500)
        end
        SendNUIMessage({
            type = "openSelectCharMenu",
            pinsSelectChar = headsonscreen,
            canCreate = false,
            currentCharacters = tonumber(currentCharacters) or 0,
            maxCharacters = tonumber(maxCharacters) or 0,
        })
        if cb then cb({ ok = false, reason = 'character_limit_reached' }) end
        return
    end

    SendNUIMessage({ type = "hideSelectCharMenu" })
    PlaySound("Select", "HUD_SHOP_SOUNDSET")
    if type(JRSStartCharacterCreator) == 'function' then
        JRSStartCharacterCreator(false)
    else
        TriggerEvent("jrs_character_creator:LaunchCreator")
    end
    if cb then cb({ ok = true }) end
end)
end

-- ============================================================================
-- Module: ui/item_callbacks.lua
-- ============================================================================
do

RegisterNUICallback("backToOutfitList", function(data, cb)
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    StopCreatorClothingPins()
    StopCreatorBarberPins()
    SendNUIMessage(
        {
            type = "closeOutfitMenu",
        }
    )
    MoveCam("edit")
    EditionMenu(false)
    local ped = CachePed
    local x, y, z = table.unpack(GetEntityCoords(ped))
    if not baseHeading then
        baseHeading = GetEntityHeading(ped)
        -- Stocker l'offset initial pour que 180 corresponde à baseHeading
        angleOffset = 180 - baseHeading
    end
    local targetHeading = (180 - angleOffset) % 360
    local rad = math.rad(targetHeading)
    local distance = 1.0
    local targetX = x + (math.sin(-rad) * distance)
    local targetY = y + (math.cos(-rad) * distance)
    TaskTurnPedToFaceCoord(ped, targetX, targetY, z, 0)

    Wait(1000)
    CreatorOutfitMode = nil
    LoadApparenceMenu()
    DisplayPins = true
    OpenApperanceMenu()
    if cb then cb({ ok = true }) end
end)

RegisterNUICallback("focusOutfitCategory", function(body, resultCallback)
    body = type(body) == "table" and body or {}
    FocusCreatorOutfitCategory(body.category, body.group, body.mode)
    PlaySound("SELECT", "HUD_SHOP_SOUNDSET")
    if resultCallback then resultCallback({ ok = true }) end
end)


RegisterNUICallback("itemValue", function(body, resultCallback)
    body = type(body) == "table" and body or {}
    local value = tonumber(body.item)
    local category = tostring(body.category or "")
    local menu = body.menu

    if category == "" then
        if resultCallback then resultCallback({ ok = false, reason = "invalid_item_category" }) end
        return
    end

    if CreatorOutfitMode == "clothing" then
        if body.clothingMode == "mp" or body.clothingMode == "npc" then
            CreatorClothingModes[category] = body.clothingMode
        end
        if value ~= nil then
            local previous = CreatorClothesCache[category] and tonumber(CreatorClothesCache[category].model) or 0
            CreatorClothingChange(value, category, "model")
            if CreatorSmartBodyDrivers[category] then
                CreatorFitAndReseat(CachePed or PlayerPedId())
            elseif category == "bodies_upper" or category == "bodies_lower" then
                -- Manual body pick stays; only re-seat the clothes on it.
                ReseatCreatorClothes(CachePed or PlayerPedId())
            end
            local selectedModel = CreatorClothesCache[category] and tonumber(CreatorClothesCache[category].model) or 0
            PlaySound(previous > selectedModel and "Amount_Decrease" or "Amount_Increase", "HUD_Donate_Sounds")
            UpdateCreatorClothingContextualDatas(selectedModel, category)
        else
            local current = CreatorClothesCache[category] and tonumber(CreatorClothesCache[category].model) or 0
            UpdateCreatorClothingContextualDatas(current, category)
        end
        currentcategory = category
        if resultCallback then resultCallback({ ok = true }) end
        return
    end
    if value then
        if overlays_info[category] then
            PlaySound("Amount_Increase", "HUD_Donate_Sounds")
            local name = category
            local visibility = 1
            if value == 0 then
                visibility = 0
            end
            local tx_id = value
            if value == 0 then
                tx_id = 1
            end
            local currentLayer = nil
            for _, l in pairs(overlay_all_layers or {}) do
                if l.name == name then currentLayer = l; break end
            end
            local var = currentLayer and tonumber(currentLayer.var) or 0
            local tx_color_type = currentLayer and tonumber(currentLayer.tx_color_type) or 0
            if name == "scars" or name == "scars2" or name == "scars3" or name == "spots" or name == "disc" or name == "complex" or name == "acne" or name == "ageing" or name == "moles" or name == "freckles" then
                tx_color_type = 1
            end
            local opacity = (currentLayer and tonumber(currentLayer.opacity)) or 1.0
            if opacity <= 0.0 then opacity = 1.0 end
            local palette_id = currentLayer and (tonumber(currentLayer.palette_id) or tonumber(currentLayer.palette)) or 1
            if palette_id <= 0 then palette_id = 1 end
            local palette_color_primary = currentLayer and tonumber(currentLayer.palette_color_primary) or 0
            local palette_color_secondary = currentLayer and tonumber(currentLayer.palette_color_secondary) or 0
            local palette_color_tertiary = currentLayer and tonumber(currentLayer.palette_color_tertiary) or 0
            OverlayChange(name,visibility,tx_id,0,0,tx_color_type,1.0,0,palette_id,palette_color_primary,palette_color_secondary,palette_color_tertiary,var,opacity)
        else
            Change(value, category, "model")
            if hairstyleCache[category].model > value then
                PlaySound("Amount_Decrease", "HUD_Donate_Sounds")
            else
                PlaySound("Amount_Increase", "HUD_Donate_Sounds")
            end
        end
        UpdateContextualDatas(value, category)
    else
        if overlays_info[category] then
            local currentLayer = nil
            for _, l in pairs(overlay_all_layers or {}) do
                if l.name == category then currentLayer = l; break end
            end
            local currentVal = currentLayer and currentLayer.visibility and currentLayer.visibility > 0 and (tonumber(currentLayer.tx_id_index) or 1) or 0
            if currentVal > 0 then
                UpdateContextualDatas(currentVal, category)
            elseif ContextualDataOn then
                ContextualDataOn = false
                PlaySound("SELECT", "HUD_PLAYER_MENU")
                SendNUIMessage({ type = "hidecontextualDatas" })
            end
        else
            if hairstyleCache[category].model == 0 then
                if ContextualDataOn then
                    ContextualDataOn = false
                    PlaySound("SELECT", "HUD_PLAYER_MENU")
                    SendNUIMessage(
                        {
                            type = "hidecontextualDatas",

                        }
                    )
                end
            elseif hairstyleCache[category].model > 0 then
                UpdateContextualDatas(hairstyleCache[category].model, category)
            end
            if currentcategory ~= category then
                PlaySound("Amount_Increase", "HUD_Donate_Sounds")
            end
        end
    end
    currentcategory = category
    if resultCallback then resultCallback({ ok = true }) end
end)


RegisterNUICallback("resetOutfitItem", function(body, resultCallback)
    body = type(body) == "table" and body or {}
    local category = tostring(body.category or "")
    local mode = tostring(body.mode or CreatorOutfitMode or "")

    if category == "" then
        if resultCallback then resultCallback({ ok = false, value = 0 }) end
        return
    end

    if mode == "clothing" or CreatorOutfitMode == "clothing" then
        local value = ResetCreatorClothingItem(category)
        PlaySound("BACK", "HUD_SHOP_SOUNDSET")
        if resultCallback then resultCallback({ ok = true, value = value }) end
        return
    end

    local value = 0
    if overlays_info and overlays_info[category] then
        local originalLayer = nil
        for _, layer in pairs(CreatorOverlayResetSnapshot or {}) do
            if layer.name == category then
                originalLayer = deepcopy(layer)
                break
            end
        end

        for index, layer in pairs(overlay_all_layers or {}) do
            if layer.name == category then
                if originalLayer then
                    overlay_all_layers[index] = deepcopy(originalLayer)
                    value = originalLayer.visibility and originalLayer.visibility > 0 and (tonumber(originalLayer.tx_id_index) or 1) or 0
                else
                    layer.visibility = 0
                    value = 0
                end
                break
            end
        end
        UpdateOverlay(CachePed)
    else
        local original = deepcopy((CreatorBarberResetSnapshot or {})[category] or { model = 0, texture = 0 })
        hairstyleCache[category] = hairstyleCache[category] or { model = 0, texture = 0 }
        Change(0, category, "model")
        value = tonumber(original.model) or 0
        if value > 0 then
            Change(value, category, "model")
            local texture = original.texture
            if type(texture) == "table" then
                local variation = tonumber(texture.palette) or tonumber(texture.model) or 1
                Change(value, category, "variants", variation)
                Change(value, category, 1, tonumber(texture.tint0) or 0)
                Change(value, category, 2, tonumber(texture.tint1) or 0)
                Change(value, category, 3, tonumber(texture.tint2) or 0)
            else
                Change(value, category, "variants", tonumber(texture) or 1)
            end
        else
            hairstyleCache[category] = { model = 0, texture = 0 }
        end
    end

    if value > 0 then
        UpdateContextualDatas(value, category)
    else
        ContextualDataOn = false
        SendNUIMessage({ type = "hidecontextualDatas" })
    end
    PlaySound("BACK", "HUD_SHOP_SOUNDSET")
    if resultCallback then resultCallback({ ok = true, value = value }) end
end)

RegisterNUICallback("varValue", function(body, resultCallback)
    body = type(body) == "table" and body or {}
    local value = tonumber(body.item)
    local category = tostring(body.category or "")
    local reference

    if category == "" then
        if resultCallback then resultCallback({ ok = false, reason = "invalid_variation_category" }) end
        return
    end

    if CreatorOutfitMode == "clothing" then
        local current = CreatorClothesCache[category]
        local model = current and tonumber(current.model) or 0
        if model > 0 and value then
            CreatorClothingChange(model, category, "variants", value)
            UpdateCreatorClothingContextualDatas(model, category)
        end
        if resultCallback then resultCallback({ ok = true }) end
        return
    end
    if overlays_info[category] then
        local name = category
        local advancedValue = body.advancedValue
        local itemValue = body.itemValue
        for k,v in pairs(overlay_all_layers) do
            if v.name==name then
                if advancedValue == "Opacity" then
                    itemValue = scale(itemValue, 0, 100, 0.0, 1.0)
                    if v.opacity > itemValue then
                        PlaySound("Amount_Decrease", "HUD_Donate_Sounds")
                    else
                        PlaySound("Amount_Increase", "HUD_Donate_Sounds")
                    end
                    v.opacity = itemValue
                end
                if advancedValue == "Palette" then
                    if v.palette_id > tonumber(itemValue) then
                        PlaySound("Amount_Decrease", "HUD_Donate_Sounds")
                    else
                        PlaySound("Amount_Increase", "HUD_Donate_Sounds")
                    end
                    v.palette_id = tonumber(itemValue)
                end
                local visibility = v.visibility
                local tx_id = v.tx_id_index
                local var = v.var
                if value then
                    if var > value then
                        PlaySound("Amount_Decrease", "HUD_Donate_Sounds")
                    else
                        PlaySound("Amount_Increase", "HUD_Donate_Sounds")
                    end
                    var = value
                end
                local tx_color_type = v.tx_color_type
                local opacity = v.opacity
                local palette_id = v.palette_id
                local palette_color_primary = v.palette_color_primary
                local palette_color_secondary = v.palette_color_secondary
                local palette_color_tertiary = v.palette_color_tertiary
                OverlayChange(name,visibility,tx_id,0,0,tx_color_type,1.0,0,palette_id,palette_color_primary,palette_color_secondary,palette_color_tertiary,var,opacity)
            end 
        end
    else
        hairstyleCache[category] = hairstyleCache[category] or { model = 0, texture = 0 }
        if type(hairstyleCache[category].texture) == "table" then
            reference = tonumber(hairstyleCache[category].texture.palette or hairstyleCache[category].texture.model) or 0
        else
            reference = tonumber(hairstyleCache[category].texture) or 0
        end
        if value and reference > value then
            PlaySound("Amount_Decrease", "HUD_Donate_Sounds")
        elseif value then
            PlaySound("Amount_Increase", "HUD_Donate_Sounds")
        end
        if category == "bodies_upper" or category == "bodies_lower" then
            if value then
                ChangeSkin(category, hairstyleCache[category].model, "variants", value)
            end
        else
            if value then
                Change(hairstyleCache[category].model, category, "variants", value)
            end
        end
    end
    if resultCallback then resultCallback({ ok = true }) end
end)

RegisterNUICallback("tintValue", function(body, resultCallback)
    body = type(body) == "table" and body or {}
    local value = tonumber(body.value)
    local tintId = tonumber(body.tintId)
    local category = tostring(body.category or "")
    local reference

    if category == "" or value == nil or tintId == nil then
        if resultCallback then resultCallback({ ok = false, reason = "invalid_tint_payload" }) end
        return
    end

    if CreatorOutfitMode == "clothing" then
        -- Clothing tint controls were removed from the creator. Ignore any stale UI call.
        if resultCallback then resultCallback({ ok = false, reason = "clothing_tints_disabled" }) end
        return
    end
    if overlays_info[category] then
        local name = category
        for k,v in pairs(overlay_all_layers) do
            if v.name==name then
                local visibility = v.visibility
                local tx_id = v.tx_id_index
                local var = v.var
                local tx_color_type = v.tx_color_type
                local opacity = v.opacity
                local palette_id = v.palette_id
                if tintId == 1 then
                    v.palette_color_primary = value
                end
                local palette_color_primary = v.palette_color_primary
                if tintId == 2 then
                    v.palette_color_secondary = value
                end
                local palette_color_secondary = v.palette_color_secondary
                if tintId == 3 then
                    v.palette_color_tertiary = value
                end
                local palette_color_tertiary = v.palette_color_tertiary
                OverlayChange(name,visibility,tx_id,0,0,tx_color_type,1.0,0,palette_id,palette_color_primary,palette_color_secondary,palette_color_tertiary,var,opacity)
            end 
        end
    else
        hairstyleCache[category] = hairstyleCache[category] or { model = 0, texture = 0 }
        if type(hairstyleCache[category].texture) == "table" then
            reference = hairstyleCache[category].texture["tint" .. tostring(tintId - 1)]
        else
            reference = 0
        end
        if reference > value then
            PlaySound("Amount_Decrease",
                "HUD_Donate_Sounds")
        else
            PlaySound("Amount_Increase", "HUD_Donate_Sounds")
        end
        Change(hairstyleCache[category].model, category, tintId, value)
    end
    if resultCallback then resultCallback({ ok = true }) end
end)
end

-- ============================================================================
-- Module: integration/jrs_client.lua
-- ============================================================================
do
if CreatorConfig.framework == 'jrs_core' then
    local myChars = {}
    charselectpeds = {}
    headsonscreen = {}
    PedAccess = false
    PlayerInfo = {}
    PlayerSex = {}
    local lastRcCommand = 0
    local selectionPending = false
    local selectionRequestId = 0
    local characterFinalizing = false
    local lastFinalizedCharacter = nil
    local lastFinalizedRequestId = -1
    JRSCharacterSpawnComplete = false

    -- Character selection uses the original JRS outdoor scenes. Only saved
    -- characters are spawned there; creation never uses a placeholder ped.
    local activeSelectionGroup = nil
    local activeSelectionCamera = nil
    local selectorCanCreate = false
    local selectorCharacterCount = 0
    local selectorSlotLimit = 0
    JRSCharacterCreatorDirectEntry = false
    JRSCharacterCreatorReturnToSelector = false

    local clearSelectorPeds
    local hideAllCharacterMenus
    local stopAllLoadingScreens
    local armLoadingPresentation
    local releaseLoadingPresentation
    local hidePlayerForSelector
    local preparePlayerForCreator
    local getSelectorSceneFocusCoords
    local waitForSelectorSceneReady
    local loadingPresentationToken = 0
    local pendingLoadingPresentation = nil
    local characterNuiReady = false
    local pendingPresentationDispatch = nil
    local presentationDispatchGeneration = 0
    local selectorWaitingForLoadingDismiss = false
    local selectorPedScenarios = {}
    local getSelectionSlot
    local buildSelectionCamera

    getSelectionSlot = function(group, index, totalCharacters)
        index = tonumber(index) or 1
        totalCharacters = math.max(1, tonumber(totalCharacters) or index)

        local layout = {
            [1] = { 2 },
            [2] = { 2, 3 },
            [3] = { 1, 2, 3 },
            [4] = { 1, 2, 3, 4 },
        }
        local mappedIndex = index
        local mappedLayout = layout[math.min(totalCharacters, 4)]
        if type(mappedLayout) == 'table' and mappedLayout[index] then
            mappedIndex = mappedLayout[index]
        end

        local pos = group and group['char' .. tostring(mappedIndex)] or nil

        -- The original JRS scenes contain four authored positions. Additional
        -- slots are extended beside the fourth position instead of using the
        -- creator interior or spawning a fake create-character ped.
        if type(pos) ~= 'table' and group then
            local anchor = group.char4 or group.char3 or group.char2 or group.char1
            if type(anchor) == 'table' then
                local extra = math.max(index - 4, 1)
                pos = {
                    x = (tonumber(anchor.x) or 0.0) + (extra * 1.15),
                    y = (tonumber(anchor.y) or 0.0) + (extra * 0.35),
                    z = tonumber(anchor.z) or 0.0,
                    h = tonumber(anchor.h) or 0.0,
                }
            end
        end

        if type(pos) ~= 'table' then return nil end

        local scenarios = {
            'WORLD_HUMAN_STAND_WAITING',
            'WORLD_HUMAN_BADASS',
            'WORLD_HUMAN_STAND_WAITING',
            'WORLD_HUMAN_BADASS',
        }

        return {
            coords = vector3(
                tonumber(pos.x) or 0.0,
                tonumber(pos.y) or 0.0,
                tonumber(pos.z) or 0.0
            ),
            heading = tonumber(pos.h or pos.heading) or 0.0,
            scenario = GetHashKey(scenarios[((index - 1) % #scenarios) + 1]),
        }
    end

    -- The selector camera FOV is vertical, so a 4:3 / 16:10 / cropped window
    -- sees far less sideways than 16:9 and the outer characters fall off-screen
    -- (no name pin, cannot be entered). Keep the 16:9 horizontal coverage.
    local function widenFovForNarrowScreen(fov)
        local okRes, rw, rh = pcall(GetActiveScreenResolution)
        rw, rh = tonumber(rw), tonumber(rh)
        if not okRes or not rw or not rh or rw <= 0 or rh <= 0 then return fov end
        local aspect = rw / rh
        local baseline = 16.0 / 9.0
        if aspect >= baseline - 0.02 then return fov end
        local widened = math.deg(2.0 * math.atan(math.tan(math.rad(fov) * 0.5) * baseline / aspect))
        return math.min(75.0, widened)
    end

    buildSelectionCamera = function(group, totalCharacters)
        local cam = group and group.camStart or nil
        if type(cam) ~= 'table' then
            return DecorSettings.charselectcam
        end

        local count = math.max(1, tonumber(totalCharacters) or (#myChars > 0 and #myChars) or 1)
        local minX, maxX = 1e9, -1e9
        local minY, maxY = 1e9, -1e9
        local minZ, maxZ = 1e9, -1e9
        local validSlots = 0

        if type(getSelectionSlot) == 'function' then
            for i = 1, count do
                local slot = getSelectionSlot(group, i, count)
                if slot and slot.coords then
                    validSlots = validSlots + 1
                    local sx = tonumber(slot.coords.x) or 0.0
                    local sy = tonumber(slot.coords.y) or 0.0
                    local sz = tonumber(slot.coords.z) or 0.0
                    if sx < minX then minX = sx end
                    if sx > maxX then maxX = sx end
                    if sy < minY then minY = sy end
                    if sy > maxY then maxY = sy end
                    if sz < minZ then minZ = sz end
                    if sz > maxZ then maxZ = sz end
                end
            end
        end

        if validSlots > 0 then
            local midX = (minX + maxX) * 0.5
            local midY = (minY + maxY) * 0.5
            local midZ = (minZ + maxZ) * 0.5
            local target = vector3(midX, midY, midZ + 0.85)

            local baseCamX = tonumber(cam.x) or (midX + 7.2)
            local baseCamY = tonumber(cam.y) or midY

            local camVecX = baseCamX - midX
            local camVecY = baseCamY - midY
            local horizDist = math.sqrt(camVecX * camVecX + camVecY * camVecY)

            local uX = 1.0
            local uY = 0.0
            if horizDist > 0.1 then
                uX = camVecX / horizDist
                uY = camVecY / horizDist
            end

            local desiredDist = 7.2
            local fov = 38.0

            if count == 1 then
                desiredDist = 7.0
                fov = 36.0
            elseif count == 2 then
                desiredDist = 7.6
                fov = 39.0
            elseif count == 3 then
                desiredDist = 8.5
                fov = 44.0
            else
                desiredDist = 9.4 + math.min(count - 4, 3) * 0.8
                fov = math.min(52.0, 47.0 + (count - 4) * 2.0)
            end

            local camZ = (midZ + 0.85) + 0.95
            if cam.z then
                local configuredZDelta = tonumber(cam.z) - midZ
                if configuredZDelta > 0.5 and configuredZDelta < 4.0 then
                    camZ = midZ + configuredZDelta
                end
            end

            local camCoords = vector3(
                midX + uX * desiredDist,
                midY + uY * desiredDist,
                camZ
            )

            return {
                coords = camCoords,
                target = target,
                fov = widenFovForNarrowScreen(fov),
            }
        end

        local x = tonumber(cam.x) or 0.0
        local y = tonumber(cam.y) or 0.0
        local z = tonumber(cam.z) or 0.0
        local heading = math.rad(tonumber(cam.h or cam.heading) or 85.0)
        local pitch = math.rad(-7.5)
        local distance = 9.0
        local horizontal = math.cos(pitch) * distance

        return {
            coords = vector3(x, y, z),
            target = vector3(
                x - math.sin(heading) * horizontal,
                y + math.cos(heading) * horizontal,
                z + math.sin(pitch) * distance
            ),
            fov = tonumber(cam.f or cam.fov) or 44.0,
        }
    end

    -- GetScreenCoordFromWorldCoord returns junk (0/-1) for points outside the
    -- viewport, so every off-screen head was clamped into the same corner and
    -- the names stacked on top of each other (only one visible). Project from
    -- the rendered camera instead so the pin lands on the correct edge.
    local function projectSelectorPoint(px, py, pz)
        local okC, cam = pcall(GetFinalRenderedCamCoord)
        local okR, rot = pcall(GetFinalRenderedCamRot, 2)
        local okF, fov = pcall(GetFinalRenderedCamFov)
        if not (okC and okR and okF and cam and rot and tonumber(fov)) then return nil end
        local okRes, rw, rh = pcall(GetActiveScreenResolution)
        rw, rh = tonumber(rw), tonumber(rh)
        local aspect = (okRes and rw and rh and rh > 0) and (rw / rh) or (16.0 / 9.0)
        local rx, rz = math.rad(rot.x), math.rad(rot.z)
        local fx, fy, fz = -math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx)
        local sx, sy = math.cos(rz), math.sin(rz)
        -- up = right x forward
        local ux, uy, uz = sy * fz, -sx * fz, sx * fy - sy * fx
        local dx, dy, dz = px - cam.x, py - cam.y, pz - cam.z
        local depth = math.max(0.05, dx * fx + dy * fy + dz * fz)
        local tanV = math.tan(math.rad(tonumber(fov)) * 0.5)
        if tanV <= 0 then return nil end
        local x = 0.5 + ((dx * sx + dy * sy) / (depth * tanV * aspect)) * 0.5
        local y = 0.5 - ((dx * ux + dy * uy + dz * uz) / (depth * tanV)) * 0.5
        return x, y
    end

    -- Pins are ~190px wide; keep them from covering each other after clamping.
    local function spreadSelectorPins(pins)
        if #pins < 2 then return end
        local okRes, rw = pcall(GetActiveScreenResolution)
        rw = tonumber(rw)
        local gap = (okRes and rw and rw > 0) and math.min(0.2, 200.0 / rw) or 0.11
        local order = {}
        for i = 1, #pins do order[i] = pins[i] end
        table.sort(order, function(a, b) return a.startPosition.x < b.startPosition.x end)
        for i = 2, #order do
            local prev, cur = order[i - 1].startPosition, order[i].startPosition
            if math.abs(cur.y - prev.y) < 0.06 and cur.x - prev.x < gap then
                cur.x = prev.x + gap
            end
        end
        -- If pushing ran off the right edge, slide the whole row back.
        local overflow = order[#order].startPosition.x - 0.88
        if overflow > 0 then
            for i = 1, #order do
                order[i].startPosition.x = math.max(0.06, order[i].startPosition.x - overflow)
            end
        end
    end

    function buildSelectorPinsSnapshot()
        local pins = {}
        local allChars = myChars or {}
        for key, value in ipairs(allChars) do
            local ped = charselectpeds[key]
            if ped and DoesEntityExist(ped) then
                local headCoords = GetPedBoneCoords(ped, 21030, 0.0, 0.0, 0.0)
                if not headCoords or (headCoords.x == 0.0 and headCoords.y == 0.0 and headCoords.z == 0.0) then
                    headCoords = GetEntityCoords(ped)
                    headCoords = vector3(headCoords.x, headCoords.y, headCoords.z + 0.8)
                end
                local visible, headx, heady = GetScreenCoordFromWorldCoord(headCoords.x, headCoords.y, headCoords.z + 0.2)
                if not (visible == true or visible == 1) then
                    -- Off-screen (narrow aspect ratio / cropped window): keep the
                    -- pin reachable on the nearest edge instead of dropping it.
                    local px, py = projectSelectorPoint(headCoords.x, headCoords.y, headCoords.z + 0.2)
                    if px then
                        headx, heady = px, py
                    else
                        local total = #allChars
                        headx = total > 1 and (0.2 + ((key - 1) / (total - 1)) * 0.6) or 0.5
                        heady = 0.3
                    end
                end
                headx = math.max(0.12, math.min(0.88, tonumber(headx) or 0.5))
                heady = math.max(0.14, math.min(0.90, tonumber(heady) or 0.5))
                pins[#pins + 1] = {
                    id = key,
                    name = (tostring(value.firstname or '') .. ' ' .. tostring(value.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
                    ExistingChar = true,
                    startPosition = { x = headx, y = heady },
                }
            end
        end

        if #pins == 0 and #allChars > 0 then
            local total = #allChars
            for key, value in ipairs(allChars) do
                local posX = 0.5
                if total > 1 then
                    posX = 0.35 + ((key - 1) / (total - 1)) * 0.3
                end
                pins[#pins + 1] = {
                    id = key,
                    name = (tostring(value.firstname or '') .. ' ' .. tostring(value.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
                    ExistingChar = true,
                    startPosition = { x = posX, y = 0.45 },
                }
            end
        end
        spreadSelectorPins(pins)
        return pins
    end

    function JRSGetCharacterSelectionCameraData()
        return activeSelectionCamera or DecorSettings.charselectcam
    end

    function JRSCanCreateCharacterFromSelector()
        return selectorCanCreate == true
            and selectorSlotLimit > 0
            and selectorCharacterCount < selectorSlotLimit
    end

    function JRSGetCharacterSelectionCounts()
        return selectorCharacterCount, selectorSlotLimit
    end

    local function getSelectorNuiLimitData()
        local canCreate = JRSCanCreateCharacterFromSelector()
        return canCreate, selectorCharacterCount, selectorSlotLimit
    end

    function JRSStartCharacterCreator(directEntry)
        SetJRSCharacterGate(true, directEntry == true and 'new_character_creator' or 'character_creator')
        JRSCharacterCreatorDirectEntry = directEntry == true
        JRSCharacterCreatorReturnToSelector = directEntry ~= true
        selectionPending = false
        characterFinalizing = false
        JRSCharacterSpawnComplete = false

        -- Keep the initial RedM loading screen (or the transition fade when
        -- creating an additional character) until the creator ped and NUI have
        -- both finished rendering. The NUI acknowledges readiness below.
        if not IsScreenFadedOut() and not IsScreenFadingOut() then
            DoScreenFadeOut(250)
            local creatorFadeTimeout = GetGameTimer() + 2000
            while not IsScreenFadedOut() and GetGameTimer() < creatorFadeTimeout do Wait(0) end
        end
        if type(armLoadingPresentation) == 'function' then
            local ct = armLoadingPresentation('creator')
        end


        TriggerEvent('jrs_character:creatorSelectorState', false)
        JRSApplyNuiFocus(false, false, false)
        hideAllCharacterMenus()
        DisplayPins = false

        if type(SwitchOffCam) == 'function' then SwitchOffCam(false) end
        clearSelectorPeds()

        CachePed = PlayerPedId()
        if type(DefaultCachePedData) == 'table' then
            CachePedData = deepcopy(DefaultCachePedData)
        end
        if type(ResetCreatorClothingCache) == 'function' then
            ResetCreatorClothingCache(true)
        end
        hairstyleCache = {}
        overlay_all_layers = deepcopy(type(baseoverlay) == 'table' and baseoverlay or {})

        local coords = CreatorConfig.CharSelect.playerSpawn.coords
        local heading = CreatorConfig.CharSelect.playerSpawn.heading
        if type(preparePlayerForCreator) == 'function' then
            preparePlayerForCreator(coords, heading)
        else
            -- Defensive fallback: creator startup must never abort because a
            -- helper was not initialized. The normal path uses the helper above.
            local ped = PlayerPedId()
            local cx = tonumber(coords.x or coords[1]) or -2785.515
            local cy = tonumber(coords.y or coords[2]) or -3058.224
            local cz = tonumber(coords.z or coords[3]) or -12.34043
            local ch = tonumber(heading) or 349.0
            RequestCollisionAtCoord(cx, cy, cz)
            SetEntityCoordsNoOffset(ped, cx, cy, cz, false, false, false)
            SetEntityHeading(ped, ch)
            if type(SetEntityAlpha) == 'function' then ResetEntityAlpha(ped) end
            SetEntityVisible(ped, true, false)
            SetEntityCollision(ped, true, true)
            FreezeEntityPosition(ped, true)
            SetPlayerInvincible(PlayerId(), true)
            JRSSafeNetworkConceal(false)
        end
        JRSApplyPlayerControl(true)

        TriggerEvent('jrs_character_creator:LaunchCreator')
    end

    function JRSHandleCreatorCancel()
        if JRSCharacterCreatorDirectEntry == true then
            -- A new account has no selector to return to. Reset and immediately
            -- reopen the creator with one default player ped.
            JRSStartCharacterCreator(true)
            return
        end

        JRSCharacterCreatorReturnToSelector = false
        if type(SwitchOffCam) == 'function' then SwitchOffCam(false) end
        clearSelectorPeds()
        JRSApplyNuiFocus(false, false, false)
        TriggerServerEvent('jrs_character_creator:getCharacters')
    end

    local function safeScale(ped, scale)
        if type(SetPedScale) == 'function' and ped and ped ~= 0 and DoesEntityExist(ped) then
            SetPedScale(ped, tonumber(scale) or 1.0)
        end
    end

    clearSelectorPeds = function()
        for _, ped in pairs(charselectpeds or {}) do
            if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
        end
        charselectpeds = {}
        selectorPedScenarios = {}
    end

    local function loadCreatorAppearance(delay)
        CreateThread(function()
            Wait(delay or 1800)
            TriggerEvent('jrs_character_creator:loadskinjrs')
        end)
    end

    hideAllCharacterMenus = function()
        SendNUIMessage({ type = 'closeSelectCharMenu' })
        SendNUIMessage({ type = 'hideSelectCharMenu' })
        SendNUIMessage({ type = 'hideSelectedCharMenu' })
        SendNUIMessage({ type = 'hideSpawnMenu' })
        SendNUIMessage({ type = 'hideGlobalCharacterMenu' })
        SendNUIMessage({ type = 'hideCharGlobalMenu' })
        -- The language switcher stays reachable for the whole pre-spawn flow -
        -- selection, creation, appearance, spawn point - and only leaves when
        -- the character UI closes and the player enters the world.
        SendNUIMessage({ type = 'hideLanguageSwitch' })
    end

    stopAllLoadingScreens = function(reason)
        -- jrs_character owns the handoff from the external loading screen to the
        -- character UI.  Fire this only after Chromium confirms that either the
        -- selector or creator presentation has actually been painted.
        local closeReason = tostring(reason or 'character_ui_ready')
        if GetResourceState('jrs_loadingscreen') == 'started' then
            TriggerEvent('jrs_loadingscreen:client:close', closeReason)
        end

        -- Keep native shutdown as a defensive fallback. This also makes the
        -- character resource safe if a different manual loadscreen is installed.
        -- Do not ClearFocus while in character selection or waiting for selector scene,
        -- as that resets focus to the underground player ped and causes blurry unstreamed LOD terrain.
        if not selectorOpen and not selectorSceneWaitActive then
            if type(ClearFocus) == 'function' then pcall(ClearFocus) end
        end

        if GetResourceState('jrs_core') == 'started' then
            TriggerEvent('jrs_core:closeLoadingScreen')
        end

        if type(ShutdownLoadingScreenNui) == 'function' then
            pcall(ShutdownLoadingScreenNui)
        end
        if type(ShutdownLoadingScreen) == 'function' then
            pcall(ShutdownLoadingScreen)
        end
    end

    -- The creator's saloon room (CreatorConfig.CharSelect) streams its IMAPs
    -- and interior entity sets asynchronously (selector/decor.lua). Chromium
    -- can paint the CHARACTER INFO form and this resource used to fade the
    -- screen back in after a flat 80ms, with no relation to that stream.
    -- On a cold join the room isn't loaded yet, so the reveal exposed the
    -- raw unstreamed exterior terrain under the player instead of the bar -
    -- reported as the character spawning "in the wrong place". This waits
    -- (bounded, like every other collision/appearance guard in this file)
    -- for the room to actually be there before the fade-in. It only delays
    -- the reveal; if streaming genuinely never finishes, it still continues
    -- after the timeout instead of leaving the player stuck.
    -- True while waitForCreatorSceneReady is running, so the 45s emergency
    -- handoff in armLoadingPresentation does not cut the wait short.
    local creatorSceneWaitActive = false

    local function waitForCreatorSceneReady()
        creatorSceneWaitActive = true
        local coords = CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.playerSpawn and CreatorConfig.CharSelect.playerSpawn.coords
        local px = tonumber(coords and (coords.x or coords[1])) or -2785.515
        local py = tonumber(coords and (coords.y or coords[2])) or -3058.224
        local pz = tonumber(coords and (coords.z or coords[3])) or -12.34043
        local ph = tonumber(CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.playerSpawn and CreatorConfig.CharSelect.playerSpawn.heading) or 349.0

        local imaps = (CreatorConfig and CreatorConfig.CharSelect and type(CreatorConfig.CharSelect.imaps) == 'table')
            and CreatorConfig.CharSelect.imaps or {}

        -- Streaming has to be pointed at the room, not only at the ped: the
        -- terrain/texture streamer follows the focus position, and a collision
        -- request only lives for the frame it was made in. Without both, the
        -- ground around the room stays at its distant low-detail LOD (the
        -- blurry, flat terrain seen when the reveal beat the stream).
        if type(SetFocusPosAndVel) == 'function' then pcall(SetFocusPosAndVel, px, py, pz, 0.0, 0.0, 0.0) end
        local loadSceneStarted = false
        if type(NewLoadSceneStartSphere) == 'function' then
            loadSceneStarted = pcall(NewLoadSceneStartSphere, px, py, pz, 60.0, 0)
        end

        local sets = (CreatorConfig and CreatorConfig.CharSelect and type(CreatorConfig.CharSelect.interior_sets) == 'table')
            and CreatorConfig.CharSelect.interior_sets or {}

        -- The screen stays covered until the room, the collision and the
        -- player ped are ALL ready. The deadline is only a last-resort net
        -- against a permanently stuck black screen (3 minutes), not a target.
        -- 4.2.42: was 180000. A stalled streamer (models/interior never
        -- ready) held the loading screen for minutes; cap it like JRS/JRS do.
        -- 4.2.42: same approach as jrs_character's creator Setup(): request
        -- the imaps by IPL hash and use StartPlayerTeleport (streams the
        -- destination) instead of a bare SetEntityCoords into unloaded map.
        for _, imap in pairs(imaps) do
            local h = GetHashKey(imap)
            if type(IsIplActiveByHash) == 'function' and type(RequestIplByHash) == 'function'
                and not IsIplActiveByHash(h) then
                pcall(RequestIplByHash, h)
            end
        end
        -- Preparation already placed the player. Starting another teleport here
        -- hides the newly rendered creator ped while the NUI is being revealed.

        local deadline = GetGameTimer() + 180000
        while GetGameTimer() < deadline do
            RequestCollisionAtCoord(px, py, pz)
            for _, imap in pairs(imaps) do
                RequestImap(GetHashKey(imap))
            end
            local ped = CachePed or PlayerPedId()
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                SetEntityCoordsNoOffset(ped, px, py, pz, false, false, false)
                SetEntityHeading(ped, ph)
                FreezeEntityPosition(ped, true)
                SetEntityCollision(ped, true, true)
                SetEntityVisible(ped, true, false)
            end

            local intId = GetInteriorAtCoords(px, py, pz)
            if not intId or intId == 0 then intId = GetInteriorFromEntity(ped) end
            if not intId or intId == 0 then intId = CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.interior end

            local interiorReady = true
            -- 4.2.42: the config interior id is only a fallback and is "valid"
            -- even when the room never streamed (ped floated over white void).
            -- Require the real interior at the spawn coords to exist and be
            -- ready; after 60s accept the fallback so a missing room can't
            -- hold the screen for the whole deadline.
            local realInt = GetInteriorAtCoords(px, py, pz)
            if JRSCreatorSceneShifted then
                interiorReady = true
            elseif (not realInt or realInt == 0) and GetGameTimer() < (deadline - 120000) then
                interiorReady = false
            elseif realInt and realInt ~= 0 and type(IsInteriorReady) == 'function'
                and not IsInteriorReady(realInt) then
                PinInteriorInMemory(realInt)
                interiorReady = false
            end
            if intId and intId ~= 0 then
                for _, setName in pairs(sets) do
                    if not IsInteriorEntitySetActive(intId, setName) then
                        ActivateInteriorEntitySet(intId, setName)
                        if type(RefreshInterior) == 'function' then RefreshInterior(intId) end
                        interiorReady = false
                    end
                end
            else
                interiorReady = false
            end

            -- Player ped: exists, has its (creator) model/appearance drawn.
            local pedReady = ped and ped ~= 0 and DoesEntityExist(ped)
                and Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) -- IsPedReadyToRender

            if JRSCreatorSceneShifted then interiorReady = true end
            local colReady = ped and ped ~= 0 and HasCollisionLoadedAroundEntity(ped)
            if interiorReady and pedReady and colReady then
                break
            end
            Wait(50)
        end

        if loadSceneStarted and type(NewLoadSceneStop) == 'function' then pcall(NewLoadSceneStop) end

        -- Collision being loaded does not mean the surrounding LOD has been
        -- swapped for the detailed terrain yet; give the streamer a short,
        -- fixed settle window (still re-requesting) before the screen fades in.
        local settleUntil = GetGameTimer() + 1500
        while GetGameTimer() < settleUntil do
            RequestCollisionAtCoord(px, py, pz)
            Wait(50)
        end
        creatorSceneWaitActive = false

        local ped = CachePed or PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            SetEntityCoordsNoOffset(ped, px, py, pz, false, false, false)
            SetEntityHeading(ped, ph)
            FreezeEntityPosition(ped, true)
            SetEntityCollision(ped, true, true)
            SetEntityVisible(ped, true, false)
            if type(ResetEntityAlpha) == 'function' then ResetEntityAlpha(ped) end
        end
    end

    local selectorSceneWaitActive = false

    getSelectorSceneFocusCoords = function()
        local group = activeSelectionGroup
        if group then
            if group.char1 then
                return tonumber(group.char1.x) or 0.0, tonumber(group.char1.y) or 0.0, tonumber(group.char1.z) or 0.0
            elseif group.playerPos then
                return tonumber(group.playerPos.x) or 0.0, tonumber(group.playerPos.y) or 0.0, tonumber(group.playerPos.z) or 0.0
            end
        end
        if activeSelectionCamera and activeSelectionCamera.target then
            local target = activeSelectionCamera.target
            return tonumber(target.x) or 0.0, tonumber(target.y) or 0.0, tonumber(target.z) or 0.0
        end
        local fallbackCoords = CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.playerSpawn and CreatorConfig.CharSelect.playerSpawn.coords
        if fallbackCoords then
            return tonumber(fallbackCoords.x or fallbackCoords[1]) or -2785.515,
                   tonumber(fallbackCoords.y or fallbackCoords[2]) or -3058.224,
                   tonumber(fallbackCoords.z or fallbackCoords[3]) or -12.34043
        end
        return 1072.09, 1719.825, 380.288
    end

    waitForSelectorSceneReady = function()
        selectorSceneWaitActive = true
        local fx, fy, fz = getSelectorSceneFocusCoords()

        if type(SetFocusPosAndVel) == 'function' then
            pcall(SetFocusPosAndVel, fx, fy, fz, 0.0, 0.0, 0.0)
        end

        local loadSceneStarted = false
        if type(NewLoadSceneStartSphere) == 'function' then
            loadSceneStarted = pcall(NewLoadSceneStartSphere, fx, fy, fz, 80.0, 0)
        end

        local deadline = GetGameTimer() + 25000
        while GetGameTimer() < deadline do
            RequestCollisionAtCoord(fx, fy, fz)

            local allCollisionLoaded = true
            local pedCount = 0

            for _, ped in pairs(charselectpeds or {}) do
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    pedCount = pedCount + 1
                    local pc = GetEntityCoords(ped)
                    RequestCollisionAtCoord(pc.x, pc.y, pc.z)
                    if not HasCollisionLoadedAroundEntity(ped) or not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) then
                        allCollisionLoaded = false
                    end
                end
            end

            if (pedCount == 0) or (pedCount > 0 and allCollisionLoaded) then
                break
            end
            Wait(50)
        end

        if loadSceneStarted and type(NewLoadSceneStop) == 'function' then
            pcall(NewLoadSceneStop)
        end

        -- Allow streamer to swap distant low-detail LOD terrain mesh/textures
        -- for full-detail terrain before screen fades in.
        local settleUntil = GetGameTimer() + 1500
        while GetGameTimer() < settleUntil do
            RequestCollisionAtCoord(fx, fy, fz)
            for _, ped in pairs(charselectpeds or {}) do
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    local pc = GetEntityCoords(ped)
                    RequestCollisionAtCoord(pc.x, pc.y, pc.z)
                end
            end
            Wait(50)
        end

        -- Snap each ped precisely onto the loaded terrain surface so they stand cleanly on the ground
        for _, ped in pairs(charselectpeds or {}) do
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                pcall(FreezeEntityPosition, ped, false)
                local pc = GetEntityCoords(ped)
                local foundGround, groundZ = GetGroundZFor_3dCoord(pc.x, pc.y, pc.z + 2.0, false)
                if foundGround and math.abs(groundZ - pc.z) < 3.0 then
                    SetEntityCoords(ped, pc.x, pc.y, groundZ, false, false, false, false)
                end
                pcall(PlaceEntityOnGroundProperly, ped, true)
                pcall(FreezeEntityPosition, ped, true)
                local sc = selectorPedScenarios[ped]
                if sc then
                    pcall(TaskStartScenarioInPlace, ped, sc, -1, false)
                end
            end
        end

        selectorSceneWaitActive = false
    end

    releaseLoadingPresentation = function(mode, token, forced)
        local pending = pendingLoadingPresentation
        if type(pending) ~= 'table' then return false end
        if tostring(mode or '') ~= tostring(pending.mode or '') then return false end
        if tonumber(token) ~= tonumber(pending.token) then return false end

        pendingLoadingPresentation = nil
        local queued = pendingPresentationDispatch
        if type(queued) == 'table'
            and tostring(queued.mode or '') == tostring(mode or '')
            and tonumber(queued.token) == tonumber(token) then
            pendingPresentationDispatch = nil
            presentationDispatchGeneration = presentationDispatchGeneration + 1
        end

        local normalizedMode = tostring(mode or '')

        CreateThread(function()
            -- Wait for scene readiness before handing off or fading in!
            if forced then
                Wait(0)
            elseif normalizedMode == 'creator' then
                waitForCreatorSceneReady()
            elseif normalizedMode == 'selector' then
                waitForSelectorSceneReady()
            else
                Wait(80)
            end

            -- Character Selection now intentionally remains covered by the external
            -- loading screen until the selector scene is fully loaded.
            if normalizedMode == 'selector'
                and forced ~= true
                and JRSIsExternalLoadingScreenActive() then
                selectorWaitingForLoadingDismiss = true
                jrsLoadingScreenCursorHandoffActive = true

                -- The manual loadscreen owns the cursor until it is actually gone.
                -- Release Character CEF focus first so RedM never has two cursor
                -- owners fighting each other. loadingDismissed claims it back.
                JRSApplyNuiFocus(false, false, false, true)
                TriggerEvent('jrs_loadingscreen:client:characterSelectionReady', 'jrs_character_selector_ui_ready')

                -- Cover the tiny race where another fallback closes the loading
                -- frontend between the active-state check and the event above.
                if selectorWaitingForLoadingDismiss == true and not JRSIsExternalLoadingScreenActive() then
                    TriggerEvent('jrs_character:client:loadingDismissed', 'character_selector_handoff_race_recovery')
                else
                    CreateThread(function()
                        Wait(2000)
                        if selectorWaitingForLoadingDismiss == true then
                            TriggerEvent('jrs_character:client:loadingDismissed', 'selector_watchdog_timeout')
                        end
                    end)
                end
                return
            end

            stopAllLoadingScreens(('jrs_character_%s_ui_ready'):format(normalizedMode ~= '' and normalizedMode or 'character'))
            loadingcharacter(false)

            -- The loadscreen owns a separate NUI/frontend surface. Closing it can
            -- clear the character cursor even though our earlier SetNuiFocus call
            -- succeeded. Reacquire only after that surface has been shut down.
            if (normalizedMode == 'selector' or normalizedMode == 'creator')
                and jrsNuiFocusWanted == true
                and jrsNuiCursorWanted == true then
                Wait(60)
                -- Selector preserves the loadscreen's own cursor position (see the
                -- claimSelectorCursor comment below), but a brand-new player's
                -- creator entry never had a visible loadscreen cursor to preserve.
                -- SetNuiFocus alone can leave RedM's native pointer un-rendered
                -- after ShutdownLoadingScreenNui(); centring it here forces a
                -- redraw the same way the initial LaunchCreator commit does.
                JRSRecoverNuiCursor(normalizedMode == 'creator')
            end

            if IsScreenFadedOut() or IsScreenFadingOut() then
                DoScreenFadeIn(500)
            end
        end)
        return true
    end

    armLoadingPresentation = function(mode)
        loadingPresentationToken = loadingPresentationToken + 1
        local token = loadingPresentationToken
        local normalizedMode = tostring(mode or '')
        pendingLoadingPresentation = {
            mode = normalizedMode,
            token = token,
        }
        pendingPresentationDispatch = nil
        presentationDispatchGeneration = presentationDispatchGeneration + 1
        loadingcharacter(true)

        local loadingText = normalizedMode == 'creator'
            and _U('ch_preparing_character_creator')
            or _U('ch_preparing_your_characters')

        -- Update the active jrs_core loadscreen using the loadscreen message
        -- format its JavaScript actually consumes. This does nothing after the
        -- initial loadscreen has already closed, which is intentional.
        if type(SendLoadingScreenMessage) == 'function' then
            local ok, encoded = pcall(json.encode, {
                type = 'update',
                progress = 82,
                text = loadingText,
            })
            if ok and encoded then
                SendLoadingScreenMessage(encoded)
            end
        end

        -- Last-resort recovery only. Presentation messages are retried below
        -- once the NUI document reports that it is actually alive, so the old
        -- startup race should no longer reach this path.
        local function emergencyRelease()
            local pending = pendingLoadingPresentation
            if type(pending) == 'table'
                and pending.token == token
                and pending.mode == normalizedMode then
                -- The creator and selector are deliberately allowed to wait for their room/scene,
                -- collision and ped; keep re-checking instead of forcing the
                -- reveal while that wait is still running.
                if (normalizedMode == 'creator' and creatorSceneWaitActive)
                    or (normalizedMode == 'selector' and selectorSceneWaitActive) then
                    SetTimeout(5000, emergencyRelease)
                    return
                end
                releaseLoadingPresentation(normalizedMode, token, true)
            end
        end
        SetTimeout(45000, emergencyRelease)
        return token
    end

    function JRSGetLoadingPresentationToken(mode)
        local pending = pendingLoadingPresentation
        if type(pending) ~= 'table' then return nil end
        if mode ~= nil and tostring(mode) ~= tostring(pending.mode) then return nil end
        return pending.token
    end

    -- Presentation messages are critical: SendNUIMessage can be lost when the
    -- Chromium page is still booting during resource/player startup. Queue the
    -- newest selector/creator presentation and replay it until Chromium both
    -- receives it and acknowledges the matching token.
    function JRSSendCharacterPresentation(mode, payload)
        local normalizedMode = tostring(mode or '')
        local token = JRSGetLoadingPresentationToken(normalizedMode)
        if not token then
            -- Loading handshake already released (45s emergency release on slow
            -- PCs, forced reveal). Dropping the message left the selector scene
            -- with no names and no Play button; Murphy sends it unconditionally.
            -- Send directly and replay until the NUI document is alive.
            if normalizedMode == 'selector' and type(payload) == 'table' then
                payload.loadingToken = nil
                payload.loadingHold = false
                CreateThread(function()
                    for _, delay in ipairs({ 0, 400, 1000, 2000, 4000 }) do
                        if delay > 0 then Wait(delay) end
                        if not selectorOpen then return end
                        if characterNuiReady == true or delay >= 2000 then
                            SendNUIMessage(payload)
                        end
                    end
                end)
            end
            return false
        end

        payload = type(payload) == 'table' and payload or {}
        payload.loadingToken = token

        presentationDispatchGeneration = presentationDispatchGeneration + 1
        local generation = presentationDispatchGeneration
        pendingPresentationDispatch = {
            mode = normalizedMode,
            token = token,
            payload = payload,
            generation = generation,
        }

        local function dispatch()
            local queued = pendingPresentationDispatch
            local pending = pendingLoadingPresentation
            if type(queued) ~= 'table' or type(pending) ~= 'table' then return false end
            if queued.generation ~= generation then return false end
            if pending.token ~= token or pending.mode ~= normalizedMode then return false end
            if characterNuiReady ~= true then return true end
            SendNUIMessage(payload)
            return true
        end

        dispatch()
        CreateThread(function()
            -- Fast retries cover the first Chromium paint; slower retries cover
            -- heavily loaded clients without spamming NUI every frame.
            local attempt = 0
            while dispatch() do
                attempt = attempt + 1
                Wait(attempt <= 5 and 350 or 850)
            end
        end)
        return true
    end

    RegisterNUICallback('characterNuiReady', function(data, cb)
        characterNuiReady = true
        if cb then cb({ ok = true }) end

        local queued = pendingPresentationDispatch
        local pending = pendingLoadingPresentation
        if type(queued) == 'table' and type(pending) == 'table'
            and queued.token == pending.token
            and queued.mode == pending.mode
            and type(queued.payload) == 'table' then
            SendNUIMessage(queued.payload)
        end
    end)

    RegisterNUICallback('characterPresentationReady', function(data, cb)
        data = type(data) == 'table' and data or {}
        local released = releaseLoadingPresentation(data.mode, data.token, false)
        if cb then cb({ ok = released == true }) end
    end)

    RegisterNetEvent('jrs_character:client:loadingSkipAvailable', function(data)
        if selectorWaitingForLoadingDismiss ~= true then return end
        data = type(data) == 'table' and data or {}

        SendNUIMessage({
            type = 'showLoadingScreenSkip',
            label = tostring(data.label or 'SKIP'),
            seconds = math.max(1, tonumber(data.seconds) or 60),
        })

        -- Legacy hold/skip mode keeps the loading surface as the only cursor
        -- owner. Character claims focus only after loadingDismissed.
        if jrsLoadingScreenCursorHandoffActive ~= true then
            JRSSetSelectorCursorOwnership(true, false)
        end
    end)

    RegisterNUICallback('characterSkipLoading', function(_, cb)
        if selectorWaitingForLoadingDismiss ~= true then
            if cb then cb({ ok = false, reason = 'selector_not_waiting' }) end
            return
        end

        if cb then cb({ ok = true }) end
        TriggerEvent('jrs_loadingscreen:client:skip', 'character_selector_skip_button')
    end)

    RegisterNUICallback('loadingScreenProxyPointer', function(data, cb)
        if selectorWaitingForLoadingDismiss ~= true
            or GetResourceState('jrs_loadingscreen') ~= 'started' then
            if cb then cb({ ok = false, reason = 'loading_screen_not_waiting' }) end
            return
        end

        data = type(data) == 'table' and data or {}
        local x = math.max(0.0, math.min(1.0, tonumber(data.x) or 0.0))
        local y = math.max(0.0, math.min(1.0, tonumber(data.y) or 0.0))
        local action = tostring(data.action or 'click')

        if type(SendLoadingScreenMessage) == 'function' then
            local ok, encoded = pcall(json.encode, {
                type = 'jrs:proxyPointer',
                action = action,
                x = x,
                y = y,
                button = tonumber(data.button) or 0,
            })
            if ok and encoded then
                pcall(SendLoadingScreenMessage, encoded)
                if cb then cb({ ok = true }) end
                return
            end
        end

        if cb then cb({ ok = false, reason = 'loading_message_unavailable' }) end
    end)

    RegisterNetEvent('jrs_character:client:loadingDismissed', function(reason)
        if selectorWaitingForLoadingDismiss ~= true then return end
        selectorWaitingForLoadingDismiss = false
        jrsLoadingScreenCursorHandoffActive = false

        SendNUIMessage({ type = 'hideLoadingScreenSkip', releaseSelector = true })

        CreateThread(function()
            loadingcharacter(false)

            -- Do NOT release the mouse when the external loadscreen disappears.
            -- Cursor ownership is latched to Character Selection and is released
            -- only by creatorSelectorState(false) when the player chooses a character.
            JRSSetSelectorCursorOwnership(true, false)

            -- ShutdownLoadingScreenNui() may clear Chromium/native focus a few
            -- frames after returning. Always perform one bounded post-shutdown
            -- acquisition and preserve the player's current cursor position.
            Wait(100)
            if jrsSelectorCursorOwned == true then
                JRSRecoverNuiCursor(false)
            end

            if IsScreenFadedOut() or IsScreenFadingOut() then
                DoScreenFadeIn(500)
            end

        end)
    end)

    -- Called when Chromium regains OS/window focus after alt-tab or a frontend
    -- transition. This is deliberately local-only and does not touch the server.
    RegisterNUICallback('characterFocusRecovery', function(data, cb)
        local recovered = false
        if jrsNuiFocusWanted == true and jrsNuiCursorWanted == true then
            recovered = JRSRecoverNuiCursor(false) == true
        end
        if cb then cb({ ok = recovered }) end
    end)

    hidePlayerForSelector = function(position)
        local ped = PlayerPedId()
        if not ped or ped == 0 or not DoesEntityExist(ped) then return end
        local coords = type(position) == 'table' and position or {}
        local x = tonumber(coords.x or coords[1]) or 0.0
        local y = tonumber(coords.y or coords[2]) or 0.0
        local z = tonumber(coords.z or coords[3]) or 0.0
        SetEntityCoordsNoOffset(ped, x, y, z - 25.0, false, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        if type(SetEntityAlpha) == 'function' then SetEntityAlpha(ped, 0, false) end
        SetPlayerInvincible(PlayerId(), true)
        JRSSafeNetworkConceal(true)
    end

    preparePlayerForCreator = function(position, heading)
        local ped = PlayerPedId()
        if not ped or ped == 0 or not DoesEntityExist(ped) then return end
        local coords = type(position) == 'table' and position or {}
        local x = tonumber(coords.x or coords[1]) or -2785.515
        local y = tonumber(coords.y or coords[2]) or -3058.224
        local z = tonumber(coords.z or coords[3]) or -12.34043
        local h = tonumber(heading) or 349.0

        if CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.imaps then
            for _, imap in pairs(CreatorConfig.CharSelect.imaps) do
                RequestImap(GetHashKey(imap))
            end
        end

        -- Place the frozen ped directly, then bound collision streaming at the
        -- destination. The fallback must not inherit an active teleport task.
        local function tryStreamAt(tx, ty, tz, th, label, tpMs, colMs)
            local sphere = false
            if type(NewLoadSceneStartSphere) == 'function' then
                sphere = pcall(NewLoadSceneStartSphere, tx, ty, tz, 50.0, 0)
            end
            if type(SetFocusPosAndVel) == 'function' then pcall(SetFocusPosAndVel, tx, ty, tz, 0.0, 0.0, 0.0) end
            RequestCollisionAtCoord(tx, ty, tz)
            local placed = JRSTeleportToScene(tx, ty, tz, th, tpMs)
            if not placed then
                if sphere and type(NewLoadSceneStop) == 'function' then pcall(NewLoadSceneStop) end
                return false
            end
            local pedNow = PlayerPedId()
            local colDeadline = GetGameTimer() + colMs
            while not JRSNativeTrue(HasCollisionLoadedAroundEntity(pedNow)) and GetGameTimer() < colDeadline do
                RequestCollisionAtCoord(tx, ty, tz)
                Wait(0)
            end
            local colOk = JRSNativeTrue(HasCollisionLoadedAroundEntity(pedNow))
            if sphere and type(NewLoadSceneStop) == 'function' then pcall(NewLoadSceneStop) end
            return colOk
        end

        if CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.imaps
            and type(IsIplActiveByHash) == 'function' and type(RequestIplByHash) == 'function' then
            for _, imap in pairs(CreatorConfig.CharSelect.imaps) do
                local hh = GetHashKey(imap)
                if not IsIplActiveByHash(hh) then pcall(RequestIplByHash, hh) end
            end
        end

        local streamed = tryStreamAt(x, y, z, h, 'room', 10000, 8000)
        if not streamed and not JRSCreatorSceneShifted then
            local fx, fy, fz = 1072.09, 1719.825, 380.288
            local cs = CreatorConfig and CreatorConfig.CharSelect
            if cs and cs.playerSpawn and cs.playerSpawn.coords then
                local dx, dy, dz = fx - x, fy - y, fz - z
                local function sh(v) return vector3(v.x + dx, v.y + dy, v.z + dz) end
                cs.playerSpawn.coords = sh(cs.playerSpawn.coords)
                if cs.camera then
                    if cs.camera.coords then cs.camera.coords = sh(cs.camera.coords) end
                    if cs.camera.target then cs.camera.target = sh(cs.camera.target) end
                end
                if type(cs.pedslots) == 'table' then
                    for _, slot in pairs(cs.pedslots) do
                        if slot.coords then slot.coords = sh(slot.coords) end
                    end
                end
                JRSCreatorSceneShifted = true
                x, y, z = fx, fy, fz
                tryStreamAt(x, y, z, h, 'fallback', 10000, 10000)
            end
        end
        ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        SetEntityHeading(ped, h)
        if type(SetEntityAlpha) == 'function' then ResetEntityAlpha(ped) end
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        FreezeEntityPosition(ped, true)
        SetPlayerInvincible(PlayerId(), true)
        JRSSafeNetworkConceal(false)

        local intId = GetInteriorAtCoords(x, y, z)
        if not intId or intId == 0 then intId = GetInteriorFromEntity(ped) end
        if not intId or intId == 0 then intId = CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.interior end
        if intId and intId ~= 0 then
            local sets = (CreatorConfig and CreatorConfig.CharSelect and type(CreatorConfig.CharSelect.interior_sets) == 'table')
                and CreatorConfig.CharSelect.interior_sets or {}
            for _, setName in pairs(sets) do
                ActivateInteriorEntitySet(intId, setName)
            end
            if type(RefreshInterior) == 'function' then RefreshInterior(intId) end
        end
    end

    local function revealPlayerAfterSelection(wakeUpDuration)
        local ped = PlayerPedId()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            FreezeEntityPosition(ped, false)
            if type(SetEntityAlpha) == 'function' then ResetEntityAlpha(ped) end
            SetEntityVisible(ped, true, false)
            SetEntityCollision(ped, true, true)
            if type(SetEntityCanBeDamaged) == 'function' then
                SetEntityCanBeDamaged(ped, true)
            end
        end
        JRSSafeNetworkConceal(false)
        loadingcharacter(false)
        if type(ClearFocus) == 'function' then pcall(ClearFocus) end
        stopAllLoadingScreens()

        wakeUpDuration = tonumber(wakeUpDuration) or 0
        if wakeUpDuration > 0 then
            -- Keep controls locked and player invincible during the wake-up / sleep animation
            SetPlayerInvincible(PlayerId(), true)
            JRSApplyPlayerControl(false)
            DisplayRadar(false)
            DisplayHud(false)

            local spawnAnimCfg = type(Config.SpawnAnimation) == 'table' and Config.SpawnAnimation or {}
            local fadeInDelay = math.max(500, tonumber(spawnAnimCfg.FadeInDelayMs) or 1500)
            Wait(fadeInDelay)

            if not IsScreenFadedIn() then DoScreenFadeIn(800) end

            local remainingWakeUp = math.max(0, wakeUpDuration - fadeInDelay)
            local checkInterval = 500
            local elapsed = 0
            while elapsed < remainingWakeUp do
                Wait(checkInterval)
                elapsed = elapsed + checkInterval
                ped = PlayerPedId()
                if ped and ped ~= 0 and DoesEntityExist(ped) then
                    if not NativeHasPedComponentLoaded(ped) then
                        NativeUpdatePedVariation(ped)
                    end
                end
            end

            SetPlayerInvincible(PlayerId(), false)
            JRSApplyPlayerControl(true)
            DisplayRadar(true)
            DisplayHud(true)
        else
            SetPlayerInvincible(PlayerId(), false)
            JRSApplyPlayerControl(true)
            DisplayRadar(true)
            DisplayHud(true)
            if not IsScreenFadedIn() then DoScreenFadeIn(500) end
        end
    end

    local function normalizeSpawnCoords(value)
        if type(value) ~= 'table' then value = {} end

        local fallback = SpawnLocation
            and SpawnLocation[1]
            and (SpawnLocation[1].pedspawn or SpawnLocation[1].coords)
            or CreatorConfig.CharSelect.playerSpawn.coords

        return {
            x = tonumber(value.x or value[1]) or tonumber(fallback.x) or 0.0,
            y = tonumber(value.y or value[2]) or tonumber(fallback.y) or 0.0,
            z = tonumber(value.z or value[3]) or tonumber(fallback.z) or 0.0,
            heading = tonumber(value.heading or value.h or value.w or value[4])
                or tonumber(SpawnLocation and SpawnLocation[1] and SpawnLocation[1].pedspawnheading)
                or tonumber(CreatorConfig.CharSelect.playerSpawn.heading)
                or 0.0,
        }
    end

    local function clampCreatorIndex(value, list)
        local count = type(list) == 'table' and #list or 0
        if count <= 0 then return 1 end
        local index = math.floor(tonumber(value) or 1)
        if index < 1 then index = 1 end
        if index > count then index = count end
        return index
    end

    local function normalizeCreatorPedData(data)
        data = type(data) == 'table' and data or {}
        data.gender = data.gender == 'Female' and 'Female' or 'Male'
        data.pedmodel = type(data.pedmodel) == 'table' and data.pedmodel or {}
        data.pedmodel.model = tostring(data.pedmodel.model or
            (data.gender == 'Female' and 'mp_female' or 'mp_male'))
        data.pedmodel.outfit = tonumber(data.pedmodel.outfit) or 0
        data.expressions = type(data.expressions) == 'table' and data.expressions or {}

        local genderSets = type(DefaultChar) == 'table' and DefaultChar[data.gender] or {}
        data.skintone = clampCreatorIndex(data.skintone, genderSets)
        local skinSet = genderSets[data.skintone] or genderSets[1] or {}

        data.head = clampCreatorIndex(data.head, skinSet.Heads)
        if skinSet.Heads and (not skinSet.Heads[data.head] or skinSet.Heads[data.head] == "") then
            data.head = 1
        end
        if tonumber(data.upperbody) == 0 then
            data.upperbody = 0
        else
            data.upperbody = clampCreatorIndex(data.upperbody, skinSet.Body)
        end
        if tonumber(data.lowerbody) == 0 then
            data.lowerbody = 0
        else
            data.lowerbody = clampCreatorIndex(data.lowerbody, skinSet.Legs)
        end
        data.body = clampCreatorIndex(data.body, Body)
        data.waist = clampCreatorIndex(data.waist, Waist)
        data.eyes = clampCreatorIndex(data.eyes, Eyes and Eyes[data.gender])
        data.teeth = clampCreatorIndex(data.teeth, Teeth and Teeth[data.gender])
        data.height = tonumber(data.height) or 1.0
        return data
    end

    RegisterNetEvent('jrs:SelectedCharacter', function()
        -- jrs_core accepted the character. Keep selectionPending true until the
        -- server sends FinalizeCharacter, otherwise a missing finalize packet
        -- would leave the player on a permanent black screen without timeout.
    end)

    RegisterNetEvent('jrs_character:revive_player', function()
        loadCreatorAppearance(1500)
    end)

    RegisterNetEvent('jrs_character_creator:SelectionFailed', function(message)
        -- Ignore stale failure/time-out events after a successful spawn.
        if JRSCharacterSpawnComplete == true then return end

        selectionPending = false
        characterFinalizing = false

        if type(message) == 'string' and message ~= '' then
            if not (type(IsJRSCharacterUiSuppressed) == 'function' and IsJRSCharacterUiSuppressed()) then
                TriggerEvent('jrs_core:sendRightTipNotification', message, 4500)
            end
        end

        local hasSelectorPed = false
        for _, ped in pairs(charselectpeds or {}) do
            if ped and DoesEntityExist(ped) then
                hasSelectorPed = true
                break
            end
        end

        if not hasSelectorPed then
            TriggerServerEvent('jrs_character_creator:getCharacters')
            return
        end

        TriggerEvent('jrs_character:creatorSelectorState', true)
        local fallbackPos = activeSelectionGroup and activeSelectionGroup.playerPos
            or CreatorConfig.CharSelect.playerSpawn.coords
        hidePlayerForSelector(fallbackPos)
        MoveCam("charselect", JRSGetCharacterSelectionCameraData(), false)

        if IsScreenFadedOut() or IsScreenFadingOut() then
            DoScreenFadeIn(400)
        end

        local canCreate, currentCharacters, maxCharacters = getSelectorNuiLimitData()
        if JRSIsExternalLoadingScreenActive() then
            jrsLoadingScreenCursorHandoffActive = true
            JRSApplyNuiFocus(false, false, false, true)
        else
            -- Admin reselect / later selector opens have no active manual
            -- loadscreen, so Character can own the cursor immediately.
            jrsLoadingScreenCursorHandoffActive = false
            JRSApplyNuiFocus(true, true, false)
            JRSSetSelectorCursorOwnership(true, false)
        end
        SendNUIMessage({
            type = "openSelectCharMenu",
            pinsSelectChar = headsonscreen,
            canCreate = canCreate,
            currentCharacters = currentCharacters,
            maxCharacters = maxCharacters,
        })
    end)

    local jrsSpawnVitalsToken = 0

    local function JRSIsPedAliveForVitals(ped)
        return ped
            and ped ~= 0
            and DoesEntityExist(ped)
            and not IsEntityDead(ped)
            and GetEntityHealth(ped) > 0
    end

    function JRSApplyConfiguredSpawnVitals(ped)
        local settings = type(Config.SpawnVitals) == 'table' and Config.SpawnVitals or {}
        if settings.Enabled == false then return false end

        ped = ped or PlayerPedId()
        if not JRSIsPedAliveForVitals(ped) then
            return false
        end

        if settings.FillHealthCore ~= false then
            local healthCore = math.max(0, math.min(100, math.floor(tonumber(settings.HealthCore) or 100)))
            Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, healthCore)
        end

        if settings.FillHealth ~= false then
            local health = math.max(1, math.floor(tonumber(settings.Health) or 600))
            SetEntityHealth(ped, health, 0)
        end

        if settings.FillStaminaCore ~= false then
            local staminaCore = math.max(0, math.min(100, math.floor(tonumber(settings.StaminaCore) or 100)))
            Citizen.InvokeNative(0xC6258F41D86676E0, ped, 1, staminaCore)
        end

        if settings.FillStamina ~= false then
            local stamina = math.max(0.0, math.min(100.0, tonumber(settings.Stamina) or 100.0))
            Citizen.InvokeNative(0x675680D089BFA21F, ped, stamina)
        end

        return true
    end

    function JRSApplySpawnVitalsSequence()
        local settings = type(Config.SpawnVitals) == 'table' and Config.SpawnVitals or {}
        if settings.Enabled == false then return end

        jrsSpawnVitalsToken = jrsSpawnVitalsToken + 1
        local token = jrsSpawnVitalsToken
        local delays = type(settings.ReapplyDelaysMs) == 'table' and settings.ReapplyDelaysMs or { 0, 200, 700 }

        for _, delay in ipairs(delays) do
            SetTimeout(math.max(0, math.floor(tonumber(delay) or 0)), function()
                if token ~= jrsSpawnVitalsToken then return end
                JRSApplyConfiguredSpawnVitals(PlayerPedId())
            end)
        end
    end

    local function JRSRestoreCoreMapAfterSpawn()
        -- The character gate hides the radar every frame. Re-enable it only
        -- after the gate is released, then let jrs_core re-apply its configured
        -- minimap mode (small / medium / hidden).
        DisplayHud(true)
        DisplayRadar(true)

        if GetResourceState('jrs_core') == 'started' then
            TriggerEvent('jrs:isPlayerReady')
            SetTimeout(1750, function()
                if characterGateActive == true then return end
                local okMode, mode = pcall(function()
                    return exports['jrs_core']:GetMiniMapMode()
                end)
                if okMode and mode then
                    pcall(function()
                        exports['jrs_core']:SetMiniMapMode(mode)
                    end)
                else
                    DisplayRadar(true)
                end
            end)
        end
    end

    RegisterNetEvent('jrs_character_creator:FinalizeCharacter', function(payload)
        payload = type(payload) == 'table' and payload or {}
        local payloadCharId = tonumber(payload.charIdentifier)
        -- Creation is confirmed both by a direct server event and by the custom
        -- callback response. Ignore the duplicate finalization packet.
        if payloadCharId and lastFinalizedCharacter == payloadCharId
            and lastFinalizedRequestId == selectionRequestId then
            return
        end
        if characterFinalizing then return end

        characterFinalizing = true
        JRSCharacterSpawnComplete = false
        selectionPending = false
        selectionRequestId = selectionRequestId + 1
        local finalizeRequestId = selectionRequestId
        local finalizationSignalsSent = false

        -- Absolute safety net: a bad appearance component must never leave the
        -- player behind a permanent black loading screen. Normal finalization
        -- can now take up to ~32s on its own (model streaming gets a long
        -- window under heavy join-time ymap contention), so this must stay
        -- above that or it fires while the real flow is still finishing and
        -- races it. This runs only when that flow aborted unexpectedly.
        SetTimeout(45000, function()
            if not characterFinalizing or finalizeRequestId ~= selectionRequestId then return end

-- REMOVED-PRINT:             print('^3[jrs_character] Spawn finalizer watchdog recovered a stalled character load.^7')
            TriggerEvent('jrs_character:creatorSelectorState', false)
            JRSApplyNuiFocus(false, false, false)
            hideAllCharacterMenus()
            clearSelectorPeds()
            if type(SwitchOffCam) == 'function' then SwitchOffCam(false) end
            if payload.isDead ~= true and tonumber(payload.isDead) ~= 1 then
                JRSApplyConfiguredSpawnVitals(PlayerPedId())
                JRSPlaySpawnAnimation('characterSelect')
            end
            pcall(JRSSetSpawnBookCharacterHidden, false)
            local wakeDuration = (payload.isDead ~= true and tonumber(payload.isDead) ~= 1 and Config.SpawnAnimation and Config.SpawnAnimation.Enabled ~= false)
                and (tonumber(Config.SpawnAnimation.WakeUpTimeMs) or 7000) or 0
            revealPlayerAfterSelection(wakeDuration)
            if payload.isDead ~= true and tonumber(payload.isDead) ~= 1 then
                JRSApplySpawnVitalsSequence()
            end
            have_character = true
            is_loaded_character = true

            Wait(350)

            if not finalizationSignalsSent then
                finalizationSignalsSent = true
                TriggerEvent('jrs_character:selected_char')
                TriggerEvent('jrs_character:isPlayerReady')
                TriggerEvent('jrs_inventory:can_save')
                TriggerServerEvent('jrs_character_creator:spawnFinalized', payloadCharId)
                JRSQueuePlayerScaleRefresh(true)
            end

            if payloadCharId then
                lastFinalizedCharacter = payloadCharId
                lastFinalizedRequestId = finalizeRequestId
            end
            JRSCharacterSpawnComplete = true
            SetJRSCharacterGate(false, 'character_ready')
            JRSRestoreCoreMapAfterSpawn()
            characterFinalizing = false
        end)

        CreateThread(function()
            local coords = normalizeSpawnCoords(payload.coords)
            local rawPedData = type(payload.peddata) == 'table' and payload.peddata or {}
            local pedData = next(rawPedData) ~= nil and normalizeCreatorPedData(rawPedData) or {}

            TriggerEvent('jrs_character:creatorSelectorState', false)
            JRSApplyNuiFocus(false, false, false)
            hideAllCharacterMenus()
            DisplayPins = false

            if not IsScreenFadedOut() then
                DoScreenFadeOut(350)
                local fadeTimeout = GetGameTimer() + 2500
                while not IsScreenFadedOut() and GetGameTimer() < fadeTimeout do Wait(0) end
            end

            if type(SwitchOffCam) == 'function' then SwitchOffCam(false) end
            clearSelectorPeds()
            NetworkClearClockTimeOverride()

            Skin_Table = type(payload.skin) == 'table' and payload.skin or {}
            -- Never carry an admin height from the previously selected character.
            -- Start with this character's creator scale until jrs_admin returns its saved override.
            JRSLastSavedPlayerScale = JRSNormalizePlayerScale(Skin_Table["Scale"]) or 1.0
            Clothe_Table = type(payload.components) == 'table' and payload.components or {}
            Coord_Table = coords
            isDead = payload.isDead == true or tonumber(payload.isDead) == 1
            PublishJRSDeathState(isDead)
            have_character = true
            is_loaded_character = false

            local ped = PlayerPedId()
            FreezeEntityPosition(ped, true)
            SetEntityVisible(ped, false, false)
            SetPlayerInvincible(PlayerId(), true)

            CachePedData = pedData

            local appearanceDone = false
            CreateThread(function()
                if next(CachePedData) ~= nil
                    and CachePedData.pedmodel
                    and CachePedData.pedmodel.model then
                    CachePed = PlayerPedId()
                    ApplyCachePedDataToPedPlayer()
                elseif next(Skin_Table) ~= nil and type(ReloadCloth) == 'function' then
                    -- Compatibility fallback only. New creator characters use peddata.
                    ReloadCloth()
                end
                appearanceDone = true
            end)

            -- Must stay above ApplyCachePedDataToPedPlayer's own model-stream
            -- timeout (30s) plus headroom, or this gives up and lets the main
            -- flow keep mutating the ped while the appearance thread is still running.
            local appearanceTimeout = GetGameTimer() + 32000
            while not appearanceDone and GetGameTimer() < appearanceTimeout do
                Wait(50)
            end
            if not appearanceDone then
                print('^1[jrs_character] Appearance load timed out; continuing spawn to avoid a black screen. The character may look wrong.^7')
            end

            ped = PlayerPedId()
            SetEntityCoords(ped, coords.x, coords.y, coords.z - 1.0, false, false, false, false)
            SetEntityHeading(ped, coords.heading)
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            local collisionTimeout = GetGameTimer() + 5000
            while GetGameTimer() < collisionTimeout and not HasCollisionLoadedAroundEntity(ped) do
                RequestCollisionAtCoord(coords.x, coords.y, coords.z)
                Wait(50)
            end

            -- Snap the player ped to the real ground surface so it does not
            -- stay buried or drop from the air if coords were saved at height.
            ped = PlayerPedId()
            local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
            if not foundGround then
                for testZ = coords.z, -100.0, -5.0 do
                    local ok, gz = GetGroundZFor_3dCoord(coords.x, coords.y, testZ, false)
                    if ok and gz and gz > -100.0 then
                        foundGround = true
                        groundZ = gz
                        break
                    end
                end
            end
            if foundGround and groundZ then
                SetEntityCoords(ped, coords.x, coords.y, groundZ + 0.1, false, false, false, false)
                pcall(PlaceEntityOnGroundProperly, ped, true)
            else
                SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
                pcall(PlaceEntityOnGroundProperly, ped, true)
            end

            -- Safety fall protection on spawn (prevents dying even if spawned at height)
            SetEntityInvincible(ped, true)
            SetEntityCanBeDamaged(ped, false)
            if type(SetRagdollBlockingFlags) == 'function' then pcall(SetRagdollBlockingFlags, ped, (1 << 9)) end
            CreateThread(function()
                Wait(6000)
                local p = PlayerPedId()
                if DoesEntityExist(p) then
                    if type(ClearRagdollBlockingFlags) == 'function' then pcall(ClearRagdollBlockingFlags, p, (1 << 9)) end
                    local isGod = (god == true) or (tostring(JRSAdminCurrentPlayerMode or '') == 'godmode')
                    SetEntityInvincible(p, isGod)
                    SetEntityCanBeDamaged(p, not isGod)
                end
            end)

            ped = PlayerPedId()
            local clothingApplied = false
            if type(ApplySavedClothingToPreviewPed) == 'function' then
                clothingApplied = ApplySavedClothingToPreviewPed(ped, payload.components or {}) == true
            end
            if not clothingApplied then
                -- Compatibility fallback for an unsupported legacy clothing row.
                TriggerEvent('jrs_clothing:loadclothes')
                Wait(150)
                ped = PlayerPedId()
            end

            local payloadBarber = type(payload.barber) == 'table' and payload.barber or {}
            if next(payloadBarber) ~= nil and type(ApplySavedBarberToPreviewPed) == 'function' then
                -- Apply saved hair, beard, overlays and age synchronously before
                -- the player becomes visible. No database callback or five-minute
                -- age-save tick is required for the initial render.
                ApplySavedBarberToPreviewPed(ped, payloadBarber, pedData, payload.age)
            else
                -- Compatibility fallback for characters without embedded barber data.
                TriggerEvent('jrs_character_creator:loadbarberoverlay')
            end

            -- Cache last loaded appearance data for reliable respawn/revive restoration
            JRSLastLoadedBarber = payloadBarber
            JRSLastLoadedComponents = payload.components
            JRSLastLoadedAge = payload.age
            JRSLastLoadedPedData = pedData
            Wait(250)

            -- Let jrs_clothing run its canonical outfit pass NOW, under the black
            -- screen, so the strip/re-dress never happens after the reveal or on
            -- top of the wake-up animation. Bounded: a stuck pass cannot hold the spawn.
            TriggerEvent('jrs_character:appearanceStageReady')
            Wait(150)
            local dressDeadline = GetGameTimer() + 5000
            while GetGameTimer() < dressDeadline do
                local okBusy, busy = pcall(function() return exports.jrs_clothing:IsClothingBusy() end)
                if not okBusy or not busy then break end
                Wait(50)
            end
            Wait(100)

            ped = PlayerPedId()
            local foundFinalGround, finalGroundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
            if foundFinalGround and math.abs(finalGroundZ - coords.z) < 3.0 then
                SetEntityCoords(ped, coords.x, coords.y, finalGroundZ, false, false, false, false)
            else
                SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
                pcall(PlaceEntityOnGroundProperly, ped, true)
            end
            SetEntityHeading(ped, coords.heading)

            if isDead then
                SetEntityHealth(ped, 0.0)
            else
                set_dead = false
                if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then
                    Citizen.InvokeNative(0x71BC8E838B9C6035, ped)
                    Citizen.InvokeNative(0x0E3F4AF2D63491FB)
                    SetEntityHealth(ped, 600, 0)
                end
            end

            Citizen.InvokeNative(0xF808475FA571D823, true)
            Citizen.InvokeNative(0xBF25EB89375A37AD, 5, GetHashKey("PLAYER"), GetHashKey("PLAYER"))

            ped = PlayerPedId()
            if pedData and DefaultChar then
                local pdGender = (pedData.gender == "Female" or pedData.gender == "female") and "Female" or "Male"
                local sc = DefaultChar[pdGender] and DefaultChar[pdGender][tonumber(pedData.skintone) or 1]
                if sc and sc.Heads then
                    local hIdx = tonumber(pedData.head) or 1
                    local hHex = (sc.Heads[hIdx] and sc.Heads[hIdx] ~= "") and sc.Heads[hIdx] or sc.Heads[1]
                    if hHex and hHex ~= "" then
                        NativeSetPedComponentEnabled(ped, tonumber("0x" .. hHex), false, true)
                    end
                end
            end
            NativeUpdatePedVariation(ped)

            -- Final synchronous pass on the actual spawned player ped. This is
            -- intentionally placed immediately before reveal, after all body,
            -- clothing and embedded barber data have finished loading.
            if type(JRSForceCurrentAgingAppearance) == 'function' then
                JRSForceCurrentAgingAppearance(true)
                Wait(50)
            end

            if type(ApplyCharacterExpressions) == 'function' then
                ApplyCharacterExpressions(ped, pedData and pedData.expressions)
            end

            local spawnVitals = type(Config.SpawnVitals) == 'table' and Config.SpawnVitals or {}
            if not isDead and spawnVitals.ApplyOnCharacterSelect ~= false then
                JRSApplyConfiguredSpawnVitals(ped)
            end

            -- Ensure clothing and smart body fit are fully committed before reveal
            ped = PlayerPedId()
            if GetResourceState("jrs_clothing") == "started" then
                pcall(function()
                    exports.jrs_clothing:SmartBodyFitPed(ped, payload.components or JRSLastLoadedComponents)
                end)
                NativeUpdatePedVariation(ped)
                if exports.jrs_clothing.IsClothingBusy then
                    local busyDeadline = GetGameTimer() + 3500
                    while exports.jrs_clothing:IsClothingBusy() and GetGameTimer() < busyDeadline do
                        Wait(50)
                    end
                end
            end

            if not isDead then
                -- Start the wake-up task while the screen is still faded out,
                -- then reveal the player already inside the animation.
                JRSPlaySpawnAnimation('characterSelect')
            end

            -- Final gate: don't reveal the ped while its components are still
            -- mid-stream, or it renders incomplete (dark/half-loaded) for a
            -- moment. Bounded so a genuinely stuck streamer still reveals.
            ped = PlayerPedId()
            local spawnAnimSettings = type(Config.SpawnAnimation) == 'table' and Config.SpawnAnimation or {}
            local ensureTimeout = math.max(8000, tonumber(spawnAnimSettings.EnsureComponentsTimeoutMs) or 12000)
            local revealDeadline = GetGameTimer() + ensureTimeout
            while not NativeHasPedComponentLoaded(ped) and GetGameTimer() < revealDeadline do
                Wait(50)
            end
            if not NativeHasPedComponentLoaded(ped) then
                print('^3[jrs_character] Ped components not confirmed loaded before reveal after timeout; revealing anyway to avoid a black screen.^7')

                -- Revealing anyway trades a permanent black screen for a
                -- possible visible glitch (a placeholder/incomplete mesh,
                -- e.g. a box-shaped head) on the heaviest cold joins where
                -- streaming genuinely did not finish in time. That is an
                -- acceptable one-time tradeoff, but leaving it broken for
                -- the rest of the session is not - keep nudging the already-
                -- requested components in the background for a further
                -- bounded window and force one variation refresh once they
                -- do finish, so the visual self-corrects without requiring
                -- a relog. NativeUpdatePedVariation only refreshes rendering
                -- of components already requested above; it does not
                -- re-request or change any of them, so this is safe to run
                -- unconditionally in the background.
                local healPed = ped
                CreateThread(function()
                    local healDeadline = GetGameTimer() + 15000
                    while GetGameTimer() < healDeadline do
                        if not DoesEntityExist(healPed) or PlayerPedId() ~= healPed then return end
                        if NativeHasPedComponentLoaded(healPed) then
                            NativeUpdatePedVariation(healPed)
                            if type(ApplyCharacterExpressions) == 'function' then
                                ApplyCharacterExpressions(healPed, pedData and pedData.expressions)
                            end
                            return
                        end
                        Wait(250)
                    end
                end)
            end

            ped = PlayerPedId()
            if type(ApplyCharacterExpressions) == 'function' then
                ApplyCharacterExpressions(ped, pedData and pedData.expressions)
            end

            pcall(JRSSetSpawnBookCharacterHidden, false)
            local wakeDuration = (not isDead and spawnAnimSettings.Enabled ~= false and spawnAnimSettings.ApplyOnCharacterSelect ~= false)
                and (tonumber(spawnAnimSettings.WakeUpTimeMs) or 7000) or 0
            revealPlayerAfterSelection(wakeDuration)

            if not isDead and spawnVitals.ApplyOnCharacterSelect ~= false then
                JRSApplySpawnVitalsSequence()
            end
            is_loaded_character = true

            Wait(350)

            if not finalizationSignalsSent then
                finalizationSignalsSent = true
                TriggerEvent('jrs_character:selected_char')
                TriggerEvent('jrs_character:isPlayerReady')
                TriggerEvent('jrs_inventory:can_save')
                TriggerServerEvent('jrs_character_creator:spawnFinalized', payloadCharId)
                JRSQueuePlayerScaleRefresh(true)

                -- Multi-stage expression retention thread after all ready events fire
                CreateThread(function()
                    local charExpressions = pedData and pedData.expressions
                    for _, delay in ipairs({ 500, 1200, 2500, 4500 }) do
                        Wait(delay)
                        if have_character and not characterFinalizing and type(ApplyCharacterExpressions) == 'function' then
                            ApplyCharacterExpressions(PlayerPedId(), charExpressions)
                        end
                    end
                end)
            end

            if payloadCharId then
                lastFinalizedCharacter = payloadCharId
                lastFinalizedRequestId = finalizeRequestId
            end
            JRSCharacterSpawnComplete = true
            SetJRSCharacterGate(false, 'character_ready')
            JRSRestoreCoreMapAfterSpawn()
            characterFinalizing = false
        end)
    end)

    RegisterNetEvent('jrs_character_creator:PlaySelectedChar', function(id)
        id = tonumber(id)
        local selected = id and myChars[id] or nil
        if selectionPending or not selected or tonumber(selected.charIdentifier) == 0 then return end

        SetJRSCharacterGate(true, 'character_loading')
        selectionPending = true
        JRSCharacterSpawnComplete = false
        selectionRequestId = selectionRequestId + 1
        local requestId = selectionRequestId
        TriggerEvent('jrs_character:creatorSelectorState', false)

        JRSApplyNuiFocus(false, false, false)
        SendNUIMessage({ type = 'closeSelectCharMenu' })
        SendNUIMessage({ type = 'hideSelectedCharMenu' })
        SendNUIMessage({ type = 'hideSelectCharMenu' })

        DoScreenFadeOut(400)
        local timeout = GetGameTimer() + 3000
        while not IsScreenFadedOut() and GetGameTimer() < timeout do Wait(0) end

        TriggerServerEvent('jrs_character_creator:selectCharacter', tonumber(selected.charIdentifier))

        SetTimeout(15000, function()
            if selectionPending and requestId == selectionRequestId then
                TriggerEvent('jrs_character_creator:SelectionFailed',
                    _U('ch_character_loading_timed_out'))
            end
        end)
    end)

    RegisterNetEvent('jrs_character_creator:LaunchCharSelect', function(characters, pedperm, slots, serverCharacterCount)
        SetJRSCharacterGate(true, 'character_selector')
        selectionPending = false
        characterFinalizing = false
        JRSCharacterSpawnComplete = false
        selectionRequestId = selectionRequestId + 1
        is_loaded_character = false
        have_character = false

        -- Do not stop the RedM loading screen here. It is released only
        -- after every selector ped and the NUI pins are fully rendered.
        JRSApplyNuiFocus(false, false, false)
        clearSelectorPeds()
        headsonscreen          = {}
        charselectpeds         = {}
        myChars                = {}
        PlayerInfo             = {}
        PlayerSex              = {}
        ActiveCam              = 0
        currentCamDestionation = ""
        camCoords              = {}
        baseHeading            = false
        rotatePedIndex         = 0
        PedAccess              = pedperm

        for _, value in pairs(characters or {}) do
            if tonumber(value.charIdentifier) and tonumber(value.charIdentifier) ~= 0 then
                myChars[#myChars + 1] = value
            end
        end
        table.sort(myChars, function(a, b)
            return (tonumber(a.charIdentifier) or 0) < (tonumber(b.charIdentifier) or 0)
        end)

        selectorCharacterCount = math.max(0, tonumber(serverCharacterCount) or #myChars)
        selectorSlotLimit = math.max(1, tonumber(slots) or selectorCharacterCount)
        selectorCanCreate = selectorCharacterCount < selectorSlotLimit

        TriggerEvent('jrs_character:check_char', true)

        -- Brand-new players skip the selector completely. The only ped shown is
        -- the editable player ped in the creator room.
        if #myChars == 0 then
            DoScreenFadeOut(350)
            local fadeTimeout = GetGameTimer() + 2000
            while not IsScreenFadedOut() and GetGameTimer() < fadeTimeout do Wait(0) end
            JRSStartCharacterCreator(true)
            return
        end

        JRSCharacterCreatorDirectEntry = false
        JRSCharacterCreatorReturnToSelector = false
        local selectorLoadingToken = type(armLoadingPresentation) == 'function'
            and armLoadingPresentation('selector') or nil
        TriggerEvent('jrs_character:creatorSelectorState', true)

        local groups = type(Config.spawnGroups) == 'table' and Config.spawnGroups or {}
        activeSelectionGroup = #groups > 0 and groups[math.random(1, #groups)] or nil
        activeSelectionCamera = buildSelectionCamera(activeSelectionGroup, #myChars)

        DoScreenFadeOut(500)
        Wait(500)
        DisplayRadar(false)
        DisplayHud(false)


        local playerPed = PlayerPedId()
        CachePed = playerPed
        local playerPos = activeSelectionGroup and activeSelectionGroup.playerPos
            or CreatorConfig.CharSelect.playerSpawn.coords
        hidePlayerForSelector(playerPos)

        local sfx, sfy, sfz = getSelectorSceneFocusCoords()
        if type(SetFocusPosAndVel) == 'function' then
            pcall(SetFocusPosAndVel, sfx, sfy, sfz, 0.0, 0.0, 0.0)
        end
        if type(NewLoadSceneStartSphere) == 'function' then
            pcall(NewLoadSceneStartSphere, sfx, sfy, sfz, 80.0, 0)
        end
        RequestCollisionAtCoord(sfx, sfy, sfz)

        CreateThread(function()
            while selectorOpen do
                local cfx, cfy, cfz = getSelectorSceneFocusCoords()
                if type(SetFocusPosAndVel) == 'function' then
                    pcall(SetFocusPosAndVel, cfx, cfy, cfz, 0.0, 0.0, 0.0)
                end
                local p = PlayerPedId()
                if DoesEntityExist(p) and (IsEntityVisible(p) or (type(IsEntityPositionFrozen) == 'function' and not IsEntityPositionFrozen(p))) then
                    hidePlayerForSelector(playerPos)
                end
                Wait(500)
            end
        end)

        MoveCam('charselect', activeSelectionCamera, true, playerPed)

        for slotIdx, _ in ipairs(myChars) do
            local slotInfo = getSelectionSlot(activeSelectionGroup, slotIdx, #myChars)
            if slotInfo and slotInfo.coords then
                RequestCollisionAtCoord(slotInfo.coords.x, slotInfo.coords.y, slotInfo.coords.z)
            end
        end

        for key, value in ipairs(myChars) do
            local data = getSelectionSlot(activeSelectionGroup, key, #myChars)
            if not data then
                CreatorDebug(('[jrs_character] Missing legacy selector slot for character %s'):format(tostring(key)))
                break
            end

            local charScale = tonumber(value.height) or (type(value.peddata) == 'table' and tonumber(value.peddata.height)) or 1.0
            if charScale <= 0 then charScale = 1.0 end

            PlayerInfo[key] = {
                firstname = value.firstname,
                lastname = value.lastname,
                characterid = value.charIdentifier,
                informations = type(value.informations) == 'table' and value.informations or {},
                money = tonumber(value.money) or 0,
                gold = tonumber(value.gold) or 0,
                dirtymoney = tonumber(value.dirtymoney) or 0,
                job = value.job or 'unemployed',
                grade = tonumber(value.grade) or 0,
                occupation = value.occupation or '',
                nickname = value.nickname or '',
                lastLocation = value.lastLocation or 'Unknown',
                age = tonumber(value.age or value.ageYears),
                baseAge = tonumber(value.baseAge),
                playtimeSeconds = tonumber(value.playtimeSeconds) or 0,
                playtimeHours = tonumber(value.playtimeHours) or 0,
                hoursPerYear = tonumber(value.hoursPerYear) or tonumber(Config and Config.HoursPerYear) or 100,
                charid = value.charIdentifier,
                height = charScale,
            }
            PlayerSex[key] = value.skin and value.skin.sex == 'mp_male' and 1 or 0

            if value.peddata and next(value.peddata) ~= nil
                and value.peddata.pedmodel and value.peddata.pedmodel.model then
                local peddata = value.peddata
                local model = GetHashKey(peddata.pedmodel.model)
                RequestModel(model)
                -- Bounded: a character saved with a ped model that no longer
                -- exists (removed custom ped, typo) hung the selector forever.
                local selectorModelDeadline = GetGameTimer() + (IsModelValid(model) and 15000 or 0)
                while not HasModelLoaded(model) and GetGameTimer() < selectorModelDeadline do Wait(50) end
                if not HasModelLoaded(model) then
                    CreatorDebug("^3[jrs_character] selector: ped model " .. tostring(peddata.pedmodel.model) .. " not loadable, using mp default.^7")
                    model = GetHashKey(value.peddata.gender == 'Female' and 'mp_female' or 'mp_male')
                    RequestModel(model)
                    local fallbackDeadline = GetGameTimer() + 15000
                    while not HasModelLoaded(model) and GetGameTimer() < fallbackDeadline do Wait(50) end
                end

                PlayerSex[key] = value.peddata.gender == 'Male' and 1 or 0
                JRSSafeSetPlayerModel(model)
                local templatePed = PlayerPedId()
                IsPedReadyToRender(templatePed)

                if peddata.pedmodel.model ~= 'mp_female' and peddata.pedmodel.model ~= 'mp_male' then
                    EquipMetaPedOutfitPreset(templatePed, peddata.pedmodel.outfit, false)
                end

                RemoveHairsAndBeards(templatePed)
                ApplyCachePedDataToPed(templatePed, peddata, value.charIdentifier)
                Wait(100)

                data.PedHandler = ClonePed(templatePed, false, true, true)
                charselectpeds[key] = data.PedHandler
                SetEntityCoords(data.PedHandler, data.coords.x, data.coords.y, data.coords.z,
                    false, false, false, false)
                -- Give ClonePed a moment to finish before applying clothing.
                -- Without this small pause the MetaPed commit can be silently discarded.
                Wait(80)
                -- Apply the saved appearance to the actual clone, not to the
                -- temporary player template. This guarantees ClonePed timing
                -- cannot drop hair, beard, tint or late clothing categories.
                -- Pass peddata so each ped resolves its own body/skin hashes.
                if type(ApplySavedClothingToPreviewPed) == 'function' then
                    ApplySavedClothingToPreviewPed(data.PedHandler, value.components or {}, peddata)
                end
                NativeUpdatePedVariation(data.PedHandler)
                if type(ApplySavedBarberToPreviewPed) == 'function' then
                    -- Barber and age are the final appearance pass. No ped
                    -- variation refresh runs afterward, so grey tint remains.
                    ApplySavedBarberToPreviewPed(data.PedHandler, value.barber, peddata, value.age)
                end
                IsPedReadyToRender(data.PedHandler)
                -- Apply saved character height to the selector ped so the user
                -- can see their character's true scale in the selection screen.
                if charScale then
                    if type(SetPedScale) == 'function' then
                        pcall(SetPedScale, data.PedHandler, charScale)
                    end
                    Citizen.InvokeNative(0x25ACFC650B65C538, data.PedHandler, charScale)
                    Citizen.InvokeNative(0xCC8CA3E88256E58F, data.PedHandler, 0, 1, 1, 1, false)
                end
                SetEntityHeading(data.PedHandler, data.heading)
                NetworkSetEntityInvisibleToNetwork(data.PedHandler, true)
                SetEntityAsMissionEntity(data.PedHandler, true, true)
                SetEntityInvincible(data.PedHandler, true)
                SetEntityCanBeDamagedByRelationshipGroup(data.PedHandler, false, GetHashKey('PLAYER'))
            else
                local sex = value.skin and value.skin.sex or 'mp_male'
                LoadPlayer(sex)
                data.PedHandler = CreatePed(joaat(sex), data.coords.x, data.coords.y, data.coords.z,
                    data.heading, false, false, false, false)
                local pedDeadline = GetGameTimer() + 5000
                while not DoesEntityExist(data.PedHandler) and GetGameTimer() < pedDeadline do Wait(0) end
                if not DoesEntityExist(data.PedHandler) then goto continue_selector_slot end
                -- Load only the legacy body here. Saved clothing and barber
                -- data are then applied locally to this ped without shared
                -- resource caches or asynchronous database callbacks.
                LoadCharacterSelect(data.PedHandler, value.skin or {}, {})
                if type(ApplySavedClothingToPreviewPed) == 'function' then
                    ApplySavedClothingToPreviewPed(data.PedHandler, value.components or {}, value.peddata or {})
                end
                NativeUpdatePedVariation(data.PedHandler)
                if type(ApplySavedBarberToPreviewPed) == 'function' then
                    ApplySavedBarberToPreviewPed(data.PedHandler, value.barber, value.peddata or {}, value.age)
                end
                IsPedReadyToRender(data.PedHandler)
                -- Apply saved character height to the selector ped.
                if charScale then
                    if type(SetPedScale) == 'function' then
                        pcall(SetPedScale, data.PedHandler, charScale)
                    end
                    Citizen.InvokeNative(0x25ACFC650B65C538, data.PedHandler, charScale)
                    Citizen.InvokeNative(0xCC8CA3E88256E58F, data.PedHandler, 0, 1, 1, 1, false)
                end
                SetEntityInvincible(data.PedHandler, true)
                charselectpeds[key] = data.PedHandler
                SetPedCanBeTargetted(data.PedHandler, false)
            end

            if data.PedHandler and DoesEntityExist(data.PedHandler) then
                local foundInitialGround, initialGroundZ = GetGroundZFor_3dCoord(data.coords.x, data.coords.y, data.coords.z + 2.0, false)
                if foundInitialGround and math.abs(initialGroundZ - data.coords.z) < 3.0 then
                    SetEntityCoords(data.PedHandler, data.coords.x, data.coords.y, initialGroundZ, false, false, false, false)
                end
                pcall(PlaceEntityOnGroundProperly, data.PedHandler, true)
                FreezeEntityPosition(data.PedHandler, true)
                if data.scenario then
                    selectorPedScenarios[data.PedHandler] = data.scenario
                    TaskStartScenarioInPlace(data.PedHandler, data.scenario, -1, false)
                end
                if charScale then
                    if type(SetPedScale) == 'function' then
                        pcall(SetPedScale, data.PedHandler, charScale)
                    end
                    Citizen.InvokeNative(0x25ACFC650B65C538, data.PedHandler, charScale)
                    Citizen.InvokeNative(0xCC8CA3E88256E58F, data.PedHandler, 0, 1, 1, 1, false)
                end

                Wait(250)
                local headCoords = GetPedBoneCoords(data.PedHandler, 21030, 0.0, 0.0, 0.0)
                if not headCoords or (headCoords.x == 0.0 and headCoords.y == 0.0 and headCoords.z == 0.0) then
                    headCoords = GetEntityCoords(data.PedHandler)
                    headCoords = vector3(headCoords.x, headCoords.y, headCoords.z + 0.8)
                end
                local visible, headx, heady = GetScreenCoordFromWorldCoord(
                    headCoords.x, headCoords.y, headCoords.z + 0.2)
                local inBounds = headx and heady and headx > 0.01 and headx < 0.99 and heady > 0.01 and heady < 0.99
                if visible == true or visible == 1 or inBounds then
                    table.insert(headsonscreen, {
                        id = key,
                        name = tostring(value.firstname or '') .. ' ' .. tostring(value.lastname or ''),
                        ExistingChar = true,
                        startPosition = { x = headx or 0.5, y = heady or 0.5 }
                    })
                end
            end
            ::continue_selector_slot::
        end

        -- SetPlayerModel is used as a local appearance template above. Keep that
        -- player ped hidden outside the camera until a saved character is chosen.
        playerPed = PlayerPedId()
        CachePed = playerPed
        hidePlayerForSelector(playerPos)

        -- Re-assert selector camera and RenderScriptCams since SetPlayerModel recreates player ped
        currentCamDestionation = ""
        MoveCam('charselect', activeSelectionCamera, true, playerPed)
        RenderScriptCams(true, false, 0, true, true)

        headsonscreen = buildSelectorPinsSnapshot()

        SendNUIMessage({
            type = 'updateElemSelectCharMenu',
            pinsSelectChar = headsonscreen,
        })

        -- All character peds have now received body, barber and clothing
        -- data. Keep the screen covered until Chromium confirms that the pins
        -- and selector menu were painted as well.
        Wait(100)
        local canCreate, currentCharacters, maxCharacters = getSelectorNuiLimitData()
        -- The loading screen already has a visible cursor. Acquire Character NUI
        -- focus once without moving the pointer and without the retry burst.
        JRSApplyNuiFocus(true, true, false, true)
        JRSSendCharacterPresentation('selector', {
            type = 'openSelectCharMenu',
            pinsSelectChar = headsonscreen,
            canCreate = canCreate,
            currentCharacters = currentCharacters,
            maxCharacters = maxCharacters,
            loadingHold = JRSIsExternalLoadingScreenActive(),
        })

        local selectorSessionId = selectionRequestId
        CreateThread(function()
            local lastSignature = nil
            while selectorOpen and selectorSessionId == selectionRequestId do
                local updatedPins = buildSelectorPinsSnapshot()
                local signatureParts = {}
                for _, pin in ipairs(updatedPins) do
                    local pos = pin.startPosition or {}
                    signatureParts[#signatureParts + 1] = string.format('%s:%.4f:%.4f',
                        tostring(pin.id or ''), tonumber(pos.x) or 0.0, tonumber(pos.y) or 0.0)
                end
                local signature = table.concat(signatureParts, '|')
                if signature ~= lastSignature then
                    SendNUIMessage({
                        type = 'updateElemSelectCharMenu',
                        pinsSelectChar = updatedPins,
                    })
                    lastSignature = signature
                end
                Wait(500)
            end
        end)
    end)

    RegisterNetEvent("jrs_character_creator:deleteCharacterClient", function(charid)
        -- Remove character from local list by matching charIdentifier
        for i, v in ipairs(myChars) do
            if v.charIdentifier == charid then
                table.remove(myChars, i)
                selectorCharacterCount = math.max(0, selectorCharacterCount - 1)
                selectorCanCreate = selectorCharacterCount < selectorSlotLimit
                break
            end
        end
    end)

    RegisterNetEvent("jrs_character_creator:loadskin", function()
        -- Add cooldown to prevent /rc spam abuse
        local currentTime = GetGameTimer()
        if currentTime - lastRcCommand > 2000 then -- 2 second cooldown
            lastRcCommand = currentTime
            
            -- First, check if model change is needed by getting the target model from server
            Callback.triggerServer("jrs_character_creator:GetPedData", function(peddata)
                if not peddata or next(peddata) == nil then
                    CreatorDebug("[JRS CHARACTER CREATOR] No ped data found, skipping loadskin")
                    return
                end
                
                local targetModel = peddata.pedmodel and peddata.pedmodel.model or nil
                if not targetModel then
                    CreatorDebug("[JRS CHARACTER CREATOR] No target model in ped data, skipping loadskin")
                    return
                end
                
                local currentModel = GetEntityModel(PlayerPedId())
                local targetModelHash = GetHashKey(targetModel)
                local needsModelChange = (currentModel ~= targetModelHash)
                
                if needsModelChange then
                    CreatorDebug("[JRS CHARACTER CREATOR] Model change needed (" .. tostring(targetModel) .. ") - reloading character appearance")
                    CreateThread(ReloadCurrentCharacter)
                    return
                end

                CreatorDebug("[JRS CHARACTER CREATOR] Model already correct (" .. targetModel .. "), no model change needed - reloading clothes and overlays")
                TriggerEvent("jrs_clothing:loadclothes")
                TriggerEvent("jrs_character_creator:loadbarberoverlay")
            end)
        else
            CreatorDebug("^3[JRS CHARACTER CREATOR]^7 Please wait before reloading character again (cooldown: 2s)")
        end
    end)

    local processingLoadSkin = false
    RegisterNetEvent("jrs_character_creator:loadskinjrs", function()
        if processingLoadSkin then
            CreatorDebug("Multiple skin loads avoided")
            TriggerEvent("jrs_character_creator:appearanceReloadFinished", false, "busy")
            return
        end
        processingLoadSkin = true
        
        Callback.triggerServer("jrs_character_creator:GetPedData", function(peddata)
            Wait(1000)
            -- A failed/rejected server callback answers false/nil. Assigning
            -- that to CachePedData and calling next() on it threw here and left
            -- processingLoadSkin stuck true (every later reload skipped), and
            -- wiped the cached appearance for the rest of the session.
            if type(peddata) ~= "table" or next(peddata) == nil
                or type(peddata.pedmodel) ~= "table" or not peddata.pedmodel.model then
                processingLoadSkin = false
                TriggerEvent("jrs_character_creator:appearanceReloadFinished", false, "missing_ped_data")
                return
            end
            CachePedData = peddata

            if next(CachePedData) == nil then
                --- If no data in jrs_character_creator, load default skin for framework
                processingLoadSkin = false
                TriggerEvent("jrs_character_creator:appearanceReloadFinished", false, "missing_ped_data")
                return
            end
            
            local model = CachePedData.pedmodel.model
            local outfit = CachePedData.pedmodel.outfit
            local currentModel = GetEntityModel(PlayerPedId())
            local targetModel = GetHashKey(model)
            
            -- Check if model change is needed
            local needsModelChange = (currentModel ~= targetModel)
            
            -- Variables for health/stamina restoration
            local savedHealthOuter, savedHealthInner, savedStaminaOuter, savedStaminaInner
            local innerHealth, innerStamina
            
            if needsModelChange then
                -- STEP 1: Save current health/stamina BEFORE model change
                local playerBefore = PlayerPedId()
                savedHealthOuter = GetEntityHealth(playerBefore)
                savedHealthInner = Citizen.InvokeNative(0x36731AC041289BB1, playerBefore, 0, Citizen.ResultAsInteger())
                savedStaminaOuter = Citizen.InvokeNative(0x22F2A386D43048A9, playerBefore, Citizen.ResultAsFloat())
                savedStaminaInner = Citizen.InvokeNative(0x36731AC041289BB1, playerBefore, 1, Citizen.ResultAsInteger())
                
                innerHealth = tonumber(savedHealthInner)
                innerStamina = tonumber(savedStaminaInner)
                
                CreatorDebug("[JRS CHARACTER CREATOR] Model change needed - Saving health/stamina BEFORE: HealthOuter: " .. tostring(savedHealthOuter) .. ", HealthInner: " .. tostring(innerHealth) .. ", StaminaOuter: " .. tostring(savedStaminaOuter) .. ", StaminaInner: " .. tostring(innerStamina))
            else
                CreatorDebug("[JRS CHARACTER CREATOR] Model already correct (" .. model .. "), no model change needed - skipping health/stamina save/restore")
            end
            
            if model == "mp_male" or model == "mp_female" then
                if needsModelChange then
                    local modelLoaded = RequestPlayerModelSafely(targetModel, 30000, 'loadskinjrs')
                    if not modelLoaded then
                        -- A focus handoff can finish shortly after the initial
                        -- timeout on slow clients. Give it one clean retry
                        -- before reporting a real streaming failure.
                        Wait(500)
                        modelLoaded = RequestPlayerModelSafely(targetModel, 15000, 'loadskinjrs-retry')
                    end
                    if not modelLoaded then
                        CreatorDebug("^1[jrs_character] model " .. tostring(model) .. " could not be streamed after focus recovery. Keeping the current ped and retrying on the next appearance load.^7")
                        processingLoadSkin = false
                        TriggerEvent("jrs_character_creator:appearanceReloadFinished", false, "model_load_timeout")
                        return
                    end
                    if not JRSSafeSetPlayerModel(targetModel) then
                        CreatorDebug("^1[jrs_character] SetPlayerModel skipped (crash guard)^7")
                        processingLoadSkin = false
                        TriggerEvent("jrs_character_creator:appearanceReloadFinished", false, "model_set_failed")
                        return
                    end
                    Wait(500)
                    SetModelAsNoLongerNeeded(targetModel)
                end
                
                CachePed = PlayerPedId()


                    if model == "mp_female" then
                        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, CachePed, 2, false)    -- EquipMetaPedOutfitPreset avec preset 2

                        local femaleReadyDeadline = GetGameTimer() + 5000
                        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, CachePed) and GetGameTimer() < femaleReadyDeadline do -- IsPedReadyToRender
                            Wait(0)
                        end
                        if not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, CachePed) then
                            CreatorDebug("^3[JRS CHARACTER CREATOR] loadskinjrs: female preset never reported ready within 5s, continuing.^7")
                        end

                        Citizen.InvokeNative(0x0BFA1BD465CDFEFD, CachePed)                                 -- ResetPedComponents

                        Citizen.InvokeNative(0xAAB86462966168CE, CachePed, true)                           -- Fixes outfit
                        Citizen.InvokeNative(0xCC8CA3E88256E58F, CachePed, false, true, true, true, false) -- UpdatePedVariation
                    else
                        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, CachePed, 0, false)                       -- EquipMetaPedOutfitPreset avec preset 0

                        local maleReadyDeadline = GetGameTimer() + 5000
                        while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, CachePed) and GetGameTimer() < maleReadyDeadline do -- IsPedReadyToRender
                            Wait(0)
                        end
                        if not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, CachePed) then
                            CreatorDebug("^3[JRS CHARACTER CREATOR] loadskinjrs: male preset never reported ready within 5s, continuing.^7")
                        end
                    end


                    local genderNorm  = (CachePedData and (CachePedData.gender == "Female" or CachePedData.gender == "female" or model == "mp_female")) and "Female" or "Male"
                    local genderSets  = DefaultChar and (DefaultChar[genderNorm] or (CachePedData and DefaultChar[CachePedData.gender]))
                    local SkinColor   = genderSets and (genderSets[CachePedData.skintone] or genderSets[1]) or nil
                    if not SkinColor then
                        processingLoadSkin = false
                        TriggerEvent("jrs_character_creator:appearanceReloadFinished", false, "invalid_skin_color")
                        return
                    end

                    local headIndex   = tonumber(CachePedData.head) or 1
                    local headHex     = (SkinColor.Heads and SkinColor.Heads[headIndex] and SkinColor.Heads[headIndex] ~= "") and SkinColor.Heads[headIndex] or (SkinColor.Heads and SkinColor.Heads[1])
                    local heads       = headHex and tonumber("0x" .. headHex) or nil

                    local bodyIndex   = tonumber(CachePedData.upperbody)
                    local bodyHex     = (bodyIndex and bodyIndex > 0 and SkinColor.Body and SkinColor.Body[bodyIndex] and SkinColor.Body[bodyIndex] ~= "") and SkinColor.Body[bodyIndex] or (bodyIndex ~= 0 and SkinColor.Body and SkinColor.Body[1])
                    local bodyType    = bodyHex and tonumber("0x" .. bodyHex) or nil

                    local legsIndex   = tonumber(CachePedData.lowerbody)
                    local legsHex     = (legsIndex and legsIndex > 0 and SkinColor.Legs and SkinColor.Legs[legsIndex] and SkinColor.Legs[legsIndex] ~= "") and SkinColor.Legs[legsIndex] or (legsIndex ~= 0 and SkinColor.Legs and SkinColor.Legs[1])
                    local legs        = legsHex and tonumber("0x" .. legsHex) or nil

                    local headtexture = SkinColor.HeadTexture and SkinColor.HeadTexture[1] and joaat(SkinColor.HeadTexture[1]) or nil
                    local albedo      = texture_types and (texture_types[genderNorm] or (CachePedData and texture_types[CachePedData.gender])) and (texture_types[genderNorm] or texture_types[CachePedData.gender]).albedo

                    IsPedReadyToRender(CachePed)
                    RemoveAllClothesExceptEssentials(CachePed)
                    if heads then ApplyShopItemToPed(heads, CachePed) end
                    if bodyIndex == 0 then
                        Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x0B3966C9, 0)
                    elseif bodyType then
                        ApplyShopItemToPed(bodyType, CachePed)
                    end
                    if legsIndex == 0 then
                        Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x823687F5, 0)
                    elseif legs then
                        ApplyShopItemToPed(legs, CachePed)
                    end
                    if albedo and headtexture then
                        Citizen.InvokeNative(0xC5E7204F322E49EB, albedo, headtexture, 0x7FC5B1E1)
                    end
                    UpdatePedVariation(CachePed)
                    if heads then
                        ApplyShopItemToPed(heads, CachePed)
                    end
                    if CachePedData.lowerbody and CachePedData.lowerbody > 0 then
                        local charData = DefaultChar and (DefaultChar[genderNorm] or (CachePedData and DefaultChar[CachePedData.gender]))
                        local comp = charData and charData[CachePedData.skintone] and charData[CachePedData.skintone].Legs and charData[CachePedData.skintone].Legs[CachePedData.lowerbody]
                        if comp then
                            ApplyShopItemToPed(tonumber("0x" .. comp), CachePed)
                            TriggerEvent("jrs_clothes:Loadlowerbody", tonumber("0x" .. comp))
                        end
                    elseif CachePedData.lowerbody == 0 then
                        Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x823687F5, 0)
                        TriggerEvent("jrs_clothes:Loadlowerbody", 0)
                    end
                    if CachePedData.upperbody and CachePedData.upperbody > 0 then
                        local charData = DefaultChar and (DefaultChar[genderNorm] or (CachePedData and DefaultChar[CachePedData.gender]))
                        local comp = charData and charData[CachePedData.skintone] and charData[CachePedData.skintone].Body and charData[CachePedData.skintone].Body[CachePedData.upperbody]
                        if comp then
                            ApplyShopItemToPed(tonumber("0x" .. comp), CachePed)
                            TriggerEvent("jrs_clothes:Loadupperbody", tonumber("0x" .. comp))
                        end
                    elseif CachePedData.upperbody == 0 then
                        Citizen.InvokeNative(0xD710A5007C2AC539, CachePed, 0x0B3966C9, 0)
                        TriggerEvent("jrs_clothes:Loadupperbody", 0)
                    end
                    if CachePedData.body > 0 then
                        local comp = tonumber(Body[CachePedData.body])
                        EquipMetaPedOutfit(comp, CachePed)
                    end
                    if CachePedData.waist > 0 then
                        local comp = tonumber(Waist[CachePedData.waist])
                        EquipMetaPedOutfit(comp, CachePed)
                    end
                else
                    -- NPC model - check if model change is needed
                    if needsModelChange then
                        NPCAssetsToPed(model, outfit, PlayerPedId())
                    end
                    CachePed = PlayerPedId()
                end


                if CachePedData.teeth > 0 then
                    ApplyShopItemToPed(Teeth[CachePedData.gender][CachePedData.teeth].hash, CachePed)
                end

                if CachePedData.eyes > 0 then
                    ApplyShopItemToPed(Eyes[CachePedData.gender][CachePedData.eyes], CachePed)
                end
                IsPedReadyToRender(CachePed)
                for k, v in pairs(CachePedData.expressions) do
                    SetCharExpression(CachePed, ExpressionsHashes[k], v)
                end
                UpdatePedVariation(CachePed)
            

            -- Only restore health/stamina if model was changed
            if needsModelChange then
                -- Wait for ped to be fully ready after model change
                local ped = PlayerPedId()
                local pedReady = false
                local timeout = 0
                local maxTimeout = 5000 -- 5 seconds max wait
                
                repeat
                    Wait(100)
                    timeout = timeout + 100
                    ped = PlayerPedId()
                    pedReady = Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) -- IsPedReadyToRender
                until (pedReady or timeout >= maxTimeout)
                
                Wait(500) -- Small buffer for stability
                ped = PlayerPedId() -- Refresh ped reference
                
                if ped == 0 or not DoesEntityExist(ped) then
                    CreatorDebug("[JRS CHARACTER CREATOR] ERROR: Player ped not valid after model change, cannot restore health")
                    processingLoadSkin = false
                    TriggerEvent("jrs_character_creator:appearanceReloadFinished", false, "invalid_player_ped")
                    return
                end
                
                -- Restore health/stamina after model change
                -- Health Inner Core
                Citizen.InvokeNative(0xC6258F41D86676E0, ped, 0, innerHealth or 100)
                -- Restore the outer health value after a player-model change.
                SetEntityHealth(ped, (savedHealthOuter or 600) + (innerHealth or 100), 0)
                -- Stamina Inner Core  
                Citizen.InvokeNative(0xC6258F41D86676E0, ped, 1, innerStamina or 100)
                -- Stamina Outer - savedStaminaOuter is already 0-100 float from ResultAsFloat()
                Citizen.InvokeNative(0x675680D089BFA21F, ped, savedStaminaOuter or 100.0)
                
                CreatorDebug("[JRS CHARACTER CREATOR] Appearance reload restored - HealthOuter: " .. tostring(savedHealthOuter) .. ", HealthInner: " .. tostring(innerHealth) .. ", StaminaOuter: " .. tostring(savedStaminaOuter) .. ", StaminaInner: " .. tostring(innerStamina))
            end

            TriggerEvent("jrs_clothing:loadclothes")
            TriggerEvent("jrs_character_creator:loadbarberoverlay")
            processingLoadSkin = false
            TriggerEvent("jrs_character_creator:appearanceReloadFinished", true)
        end)
    end)

    RegisterNetEvent("jrs_character_creator:HealthFromCore")
    AddEventHandler("jrs_character_creator:HealthFromCore", function(healthData)
        HealthData = healthData
    end)

    function LoadFaceFeatures(ped, skin)
        for key, value in pairs(FaceFeatures) do
            for label, v in pairs(value) do
                if skin[v.comp] and skin[v.comp] ~= 0 then
                    SetCharExpression(ped, v.hash, skin[v.comp])
                end
            end
        end
    end

    local function NormalizeComponentValue(value)
        if type(value) == "number" or type(value) == "string" then
            return {
                comp = tonumber(value) or -1,
                palette = 0,
                tint0 = 0,
                tint1 = 0,
                tint2 = 0
            }
        end

        if type(value) ~= "table" then
            return { comp = -1, palette = 0, tint0 = 0, tint1 = 0, tint2 = 0 }
        end

        return {
            comp = tonumber(value.comp) or -1,
            palette = tonumber(value.palette) or 0,
            tint0 = tonumber(value.tint0) or 0,
            tint1 = tonumber(value.tint1) or 0,
            tint2 = tonumber(value.tint2) or 0,
            drawable = tonumber(value.drawable) or 0,
            albedo = tonumber(value.albedo) or 0,
            normal = tonumber(value.normal) or 0,
            material = tonumber(value.material) or 0
        }
    end

    function ApplyAllComponents(category, value, ped, set)
        value = NormalizeComponentValue(value)
        if value.comp == -1 then
            return
        end

        local status = not set and "false" or GetResourceKvpString(tostring(value.comp))
        if status == "true" then
            local tag = HashList[category]
            if tag then
                return RemoveTagFromMetaPed(tag, ped)
            end
            return
        end

        ApplyShopItemToPed(value.comp, ped)

        if category ~= "Boots" then
            UpdateShopItemWearableState(ped, `base`)
        end

        Citizen.InvokeNative(0xAAB86462966168CE, ped, 1)
        UpdatePedVariation(ped)
        IsPedReadyToRender(ped)

        if value.palette ~= 0 then
            local TagData = GetMetaPedData(category == "Boots" and "boots" or category, ped)
            if TagData then
                local palette = value.palette ~= 0 and value.palette or TagData.palette
                SetMetaPedTag(ped, TagData.drawable, TagData.albedo, TagData.normal, TagData.material, palette,
                    value.tint0, value.tint1, value.tint2)
                if IsPedAPlayer(ped) and CachedComponents and CachedComponents[category] then
                    CachedComponents[category].drawable = TagData.drawable
                    CachedComponents[category].albedo = TagData.albedo
                    CachedComponents[category].normal = TagData.normal
                    CachedComponents[category].material = TagData.material
                    CachedComponents[category].palette = palette
                end
            end
        end
    end

    function LoadCharacterSelect(ped, skin, components)
        local gender = skin.sex == "mp_male" and "Male" or "Female"
        LoadAll(gender, ped, skin, components, false)
        SetAttributeCoreValue(ped, 1, 100)
        SetAttributeCoreValue(ped, 0, 100)
    end

    function LoadComps(ped, components, set)
        components = type(components) == "table" and components or {}

        -- Shirt and Vest are applied last to keep the intended wearable layering.
        for category, value in pairs(components) do
            if category ~= "Shirt" and category ~= "Vest" then
                ApplyAllComponents(category, value, ped, set)
            end
        end

        ApplyAllComponents("Shirt", components.Shirt, ped, set)
        ApplyAllComponents("Vest", components.Vest, ped, set)
    end

    function RemoveMetaTags(ped)
        for _, tag in pairs(HashList) do
            RemoveTagFromMetaPed(tag, ped)
            UpdatePedVariation(ped)
        end
    end


function SetDefaultSkin(gender, skin)
    local __data = {}
    for skinColor, value in pairs(DefaultChar[gender]) do
        for key, info in pairs(value) do
            if key == "HeadTexture" then
                local headtext = joaat(value.HeadTexture[1])
                if headtext == skin.albedo then
                    __data = value
                    -- work arround to fix Torso
                    for k, v in pairs(value.Body) do
                        if skin.Torso ~= 0 then
                            -- if Torso is not part of this color set due to old character, then set it to the first value in order to fix it
                            if tonumber("0x" .. v) ~= skin.Torso then
                                skin.Torso = tonumber("0x" .. v)
                                break
                            end
                        end
                    end
                    break
                end
            end
        end
    end

    if not next(__data) then
        return skin
    end

    if skin.HeadType and skin.HeadType == 0 then
        skin.HeadType = tonumber("0x" .. __data.Heads[1])
    end

    if skin.BodyType and skin.BodyType == 0 then
        skin.BodyType = tonumber("0x" .. __data.Body[1])
    end

    if skin.LegsType and skin.LegsType == 0 then
        skin.LegsType = tonumber("0x" .. __data.Legs[1])
    end

    if skin.Torso and skin.Torso == 0 then
        skin.Torso = tonumber("0x" .. __data.Body[1])
    end

    return skin
end


local function ApplyJRSHeight(ped, scale)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    if not scale then scale = 1.0 end

    scale = tonumber(scale) or 1.0
    if scale < 0.7 then scale = 0.7 end
    if scale > 1.3 then scale = 1.3 end

    safeScale(ped, scale)
end

function removeMetaTags(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    for _, tag in pairs(HashList) do
        RemoveTagFromMetaPed(tag, ped)
    end
    UpdatePedVariation(ped)
end


RegisterNetEvent("jrs_character_creator:reloadAfterDeath")
AddEventHandler("jrs_character_creator:reloadAfterDeath", function()
    local spawnVitals = type(Config.SpawnVitals) == 'table' and Config.SpawnVitals or {}

    -- Disabling death-respawn vitals must be authoritative. Do not run a
    -- fallback that refills health or stamina when the option is off.
    if spawnVitals.Enabled == false or spawnVitals.ApplyAfterDeathRespawn == false then
        return
    end

    CreateThread(function()
        local waitTimeout = math.max(0, math.floor(tonumber(spawnVitals.DeathRespawnAliveWaitMs) or 15000))
        local pollInterval = math.max(25, math.floor(tonumber(spawnVitals.DeathRespawnPollMs) or 100))
        local deadline = GetGameTimer() + waitTimeout
        local player = PlayerPedId()

        -- Some death resources emit the reload event slightly before the new
        -- living ped is ready. Wait briefly, but never heal or revive a dead ped.
        while not JRSIsPedAliveForVitals(player) and GetGameTimer() < deadline do
            Wait(pollInterval)
            player = PlayerPedId()
        end

        if not JRSIsPedAliveForVitals(player) then
            return
        end

        local getPedModel = GetEntityModel(player)
        local reload = getPedModel ~= joaat("mp_female") and getPedModel ~= joaat("mp_male")

        if type(JRSRestoreCharacterAppearanceOnRespawn) == 'function' then
            JRSRestoreCharacterAppearanceOnRespawn(player)
        else
            TriggerEvent('jrs_clothing:loadclothes')
            TriggerEvent('jrs_character_creator:loadbarberoverlay')
        end

        player = PlayerPedId()
        if not JRSIsPedAliveForVitals(player) then
            return
        end

        JRSApplyConfiguredSpawnVitals(player)
        JRSApplySpawnVitalsSequence()
    end)
end)
function LoadAll(gender, ped, pedskin, components, set)
    removeMetaTags(ped)
    IsPedReadyToRender(ped)
    ResetPedComponents(ped)

    local skin = SetDefaultSkin(gender, pedskin)

    ApplyShopItemToPed(skin.HeadType, ped)
    ApplyShopItemToPed(skin.BodyType, ped)
    ApplyShopItemToPed(skin.LegsType, ped)
    ApplyShopItemToPed(skin.Eyes, ped)
    ApplyShopItemToPed(skin.Legs, ped)
    ApplyShopItemToPed(skin.Hair, ped)
    ApplyShopItemToPed(skin.Beard, ped)
    ApplyShopItemToPed(skin.Torso, ped)

    EquipMetaPedOutfit(skin.Waist, ped)
    EquipMetaPedOutfit(skin.Body, ped)

    Citizen.InvokeNative(0xAAB86462966168CE, ped, 1)
    LoadFaceFeatures(ped, skin)
    UpdatePedVariation(ped)
    IsPedReadyToRender(ped)

    LoadComps(ped, components, set)

    local scale = skin.Scale or 1.0 
    safeScale(ped, scale) 

    UpdatePedVariation(ped)

    return skin
end


RegisterNetEvent("jrs_PlayerHeight:SetPedScale")
AddEventHandler("jrs_PlayerHeight:SetPedScale", function(ped, scals)
    JRSLastSavedPlayerScale = JRSNormalizePlayerScale(scals) or JRSLastSavedPlayerScale
    ped = (ped and ped ~= 0 and DoesEntityExist(ped)) and ped or PlayerPedId()
    safeScale(ped, JRSLastSavedPlayerScale or scals)
end)

RegisterNetEvent("jrs_PlayerHeight:SetPedScale_2")
AddEventHandler("jrs_PlayerHeight:SetPedScale_2", function(ped, scals)
    JRSLastSavedPlayerScale = JRSNormalizePlayerScale(scals) or JRSLastSavedPlayerScale
    ped = (ped and ped ~= 0 and DoesEntityExist(ped)) and ped or PlayerPedId()
    safeScale(ped, JRSLastSavedPlayerScale or scals)
end)

    function SetDefaultSkin(gender, skin)
        local __data = {}
        for skinColor, value in pairs(DefaultChar[gender]) do
            for key, info in pairs(value) do
                if key == "HeadTexture" then
                    local headtext = joaat(value.HeadTexture[1])
                    if headtext == skin.albedo then
                        __data = value
                        -- work arround to fix Torso
                        for k, v in pairs(value.Body) do
                            if skin.Torso ~= 0 then
                                -- if Torso is not part of this color set due to old character, then set it to the first value in order to fix it
                                if tonumber("0x" .. v) ~= skin.Torso then
                                    skin.Torso = tonumber("0x" .. v)
                                    break
                                end
                            end
                        end

                        break
                    end
                end
            end
        end

        if not next(__data) then
            return skin
        end

        if skin.HeadType and skin.HeadType == 0 then
            skin.HeadType = tonumber("0x" .. __data.Heads[1])
        end

        if skin.BodyType and skin.BodyType == 0 then
            skin.BodyType = tonumber("0x" .. __data.Body[1])
        end

        if skin.LegsType and skin.LegsType == 0 then
            skin.LegsType = tonumber("0x" .. __data.Legs[1])
        end

        if skin.Torso and skin.Torso == 0 then
            skin.Torso = tonumber("0x" .. __data.Body[1])
        end

        return skin
    end

    function LoadPlayer(sex)
        -- 4.2.42: sex is a name string; hash it and bound the wait (the old
        -- unbounded repeat hung the selector forever when streaming stalled).
        local hash = type(sex) == 'string' and joaat(sex) or sex
        if not HasModelLoaded(hash) then
            RequestModel(hash, false)
            local deadline = GetGameTimer() + 15000
            while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
        end
        return HasModelLoaded(hash)
    end

    FaceFeatures = {
        head = {
            ["Head Width"] = { hash = 0x84D6, comp = "HeadSize" },
            ["Face Width"] = { hash = 41396, comp = "FaceW" },
            ["Face Depth"] = { hash = 12281, comp = "FaceD" },
            ["Forehead Size"] = { hash = 13059, comp = "FaceS" },
            ["Neck Width"] = { hash = 36277, comp = "NeckW" },
            ["Neck Depth"] = { hash = 60890, comp = "NeckD" },
        },

        eyesandbrows = {
            ["Brows Height"] = { hash = 0x3303, comp = "EyeBrowH" },
            ["Brows Width"] = { hash = 0x2FF9, comp = "EyeBrowW" },
            ["Brows Depth"] = { hash = 0x4AD1, comp = "EyeBrowD" },
            ["Eyes Depth"] = { hash = 0xEE44, comp = "EyeD" },
            ["Eyes Angle"] = { hash = 0xD266, comp = "EyeAng" },
            ["Eyes Distance"] = { hash = 0xA54E, comp = "EyeDis" },
            ["Eyes Height"] = { hash = 0xDDFB, comp = "EyeH" },
            ["Eyelid Height"] = { hash = 0x8B2B, comp = "EyeLidH" },
            ["Eyelid Width"] = { hash = 0x1B6B, comp = "EyeLidW" },
            ["Eyelid Left O/Close"] = { hash = 52902, comp = "EyeLidL" },
            ["Eyelid Right O/Close"] = { hash = 22421, comp = "EyeLidR" },
        },

        ears = {
            ["Ears Width"] = { hash = 0xC04F, comp = "EarsW" },
            ["Ears Angle"] = { hash = 0xB6CE, comp = "EarsA" },
            ["Ears Height"] = { hash = 0x2844, comp = "EarsH" },
            ["Ears Depth"] = { hash = 0xED30, comp = "EarsD" },
        },
        cheek = {
            ["CheekBone Height"] = { hash = 0x6A0B, comp = "CheekBonesH" },
            ["CheekBone Width"] = { hash = 0xABCF, comp = "CheekBonesW" },
            ["CheekBone Depth"] = { hash = 0x358D, comp = "CheekBonesD" },
        },
        jaw = {
            ["Jaw Height"] = { hash = 0x8D0A, comp = "JawH" },
            ["Jaw Width"] = { hash = 0xEBAE, comp = "JawW" },
            ["Jaw Depth"] = { hash = 0x1DF6, comp = "JawD" },
        },
        chin = {
            ["Chin Height"] = { hash = 0x3C0F, comp = "ChinH" },
            ["Chin Width"] = { hash = 0xC3B2, comp = "ChinW" },
            ["Chin Depth"] = { hash = 0xE323, comp = "ChinD" },
        },
        nose = {
            ["Nose Width"] = { hash = 0x6E7F, comp = "NoseW" },
            ["Nose Size"] = { hash = 0x3471, comp = "NoseS" },
            ["Nose Height"] = { hash = 0x03F5, comp = "NoseH" },
            ["Nose Angle"] = { hash = 0x34B1, comp = "NoseAng" },
            ["Nose Curvature"] = { hash = 0xF156, comp = "NoseC" },
            ["Nose Distance"] = { hash = 0x561E, comp = "NoseDis" },
        },
        mouthandlips = {
            ["Mouth Width"] = { hash = 0xF065, comp = "MouthW" },
            ["Mouth Depth"] = { hash = 0xAA69, comp = "MouthD" },
            ["Mouth DistanceX"] = { hash = 0x7AC3, comp = "MouthX" },
            ["Mouth DistanceY"] = { hash = 0x410D, comp = "MouthY" },
            ["Lip Upper Height"] = { hash = 0x1A00, comp = "ULiphH" },
            ["Lip Upper Width"] = { hash = 0x91C1, comp = "ULiphW" },
            ["Lip Upper Depth"] = { hash = 0xC375, comp = "ULiphD" },
            ["Lip Lower Height"] = { hash = 0xBB4D, comp = "LLiphH" },
            ["Lip Lower Width"] = { hash = 0xB0B0, comp = "LLiphW" },
            ["Lip Lower Depth"] = { hash = 0x5D16, comp = "LLiphD" },
            ["Mouth Corner Left Withd"] = { hash = 57350, comp = "MouthCLW" },
            ["Mouth Corner Right Withd"] = { hash = 60292, comp = "MouthCRW" },
            ["Mouth Corner Left Depth"] = { hash = 40950, comp = "MouthCLD" },
            ["Mouth Corner Right Depth"] = { hash = 49299, comp = "MouthCRD" },
            ["Mouth Corner Left Height"] = { hash = 46661, comp = "MouthCLH" },
            ["Mouth Corner Right Height"] = { hash = 55718, comp = "MouthCRH" },
            ["Mouth Corner Left Lips Distance"] = { hash = 22344, comp = "MouthCLLD" },
            ["Mouth Corner Right Lips Distance"] = { hash = 9423, comp = "MouthCRLD" },
        },
        upperbody = {
            ["Arms Size"] = { hash = 46032, comp = "ArmsS" },
            ["Upper Shoulders Size"] = { hash = 50039, comp = "ShouldersS" },
            ["Back Shoulders Thickness"] = { hash = 7010, comp = "ShouldersT" },
            ["Back Muscles"] = { hash = 18046, comp = "ShouldersM" }, -- shoulder blades / back muscles
            ["Chest Size"] = { hash = 27779, comp = "ChestS" },
            ["Waist Width"] = { hash = 50460, comp = "WaistW" },
            ["Hips Size"] = { hash = 49787, comp = "HipsS" }, -- hip width / stomach size
        },

        lowerbody = {
            ["Tights Size"] = { hash = 64834, comp = "LegsS" },
            ["Calves Size"] = { hash = 42067, comp = "CalvesS" },
        },

    }


    HashList = {
        Gunbelt     = 0x9B2C8B89,
        Mask        = 0x7505EF42,
        Holster     = 0xB6B6122D,
        Loadouts    = 0x83887E88,
        Coat        = 0xE06D30CE,
        Cloak       = 0x3C1A74CD,
        EyeWear     = 0x5E47CA6,
        Bracelet    = 0x7BC10759,
        Skirt       = 0xA0E3AB7F,
        Poncho      = 0xAF14310B,
        Spats       = 0x514ADCEA,
        NeckTies    = 0x7A96FACA,
        Spurs       = 0x18729F39,
        Pant        = 0x1D4C528A,
        Suspender   = 0x877A2CF7,
        Glove       = 0xEABE0032,
        Satchels    = 0x94504D26,
        GunbeltAccs = 0xF1542D11,
        CoatClosed  = 0x662AC34,
        Buckle      = 0xFAE9107F,
        RingRh      = 0x7A6BBD0B,
        Belt        = 0xA6D134C6,
        Accessories = 0x79D7DF96,
        Shirt       = 0x2026C46D,
        Gauntlets   = 0x91CE9B20,
        Chap        = 0x3107499B,
        NeckWear    = 0x5FC29285,
        Boots       = 0x777EC6EF,
        Vest        = 0x485EE834,
        RingLh      = 0xF16A1D23,
        Hat         = 0x9925C067,
        Dress       = 0xA2926F9B,
        Badge       = 0x3F7F3587,
        armor       = 0x72E6EF74,
        Hair        = 0x864B03AE,
        Beard       = 0xF8016BCA,
        bow         = 0x8E84A2AA,
    }
end
end

-- ============================================================================
-- Module: runtime/events.lua
-- ============================================================================
do

-- Developer character-selector shortcut removed; selection is admin-menu only.

RegisterNetEvent("jrs_character_creator:OpenCharSelect", function()
    TriggerServerEvent("jrs_character_creator:getCharacters")
end)

RegisterNetEvent("jrs_character_creator:LaunchCreator", function()
    local coords = CreatorConfig.CharSelect.playerSpawn.coords
    local heading = CreatorConfig.CharSelect.playerSpawn.heading
    local cx = tonumber(coords.x or coords[1]) or -2785.515
    local cy = tonumber(coords.y or coords[2]) or -3058.224
    local cz = tonumber(coords.z or coords[3]) or -12.34043
    local ch = tonumber(heading) or 349.0

    if CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.imaps then
        for _, imap in pairs(CreatorConfig.CharSelect.imaps) do
            RequestImap(GetHashKey(imap))
        end
    end
    RequestCollisionAtCoord(cx, cy, cz)

    CachePed = PlayerPedId()
    SetEntityCoordsNoOffset(CachePed, cx, cy, cz, false, false, false)
    SetEntityHeading(CachePed, ch)
    if type(SetEntityAlpha) == 'function' then ResetEntityAlpha(CachePed) end
    SetEntityVisible(CachePed, true, false)
    SetEntityCollision(CachePed, true, true)
    FreezeEntityPosition(CachePed, true)
    SetPlayerInvincible(PlayerId(), true)
    JRSSafeNetworkConceal(false)

    local selectedgender = "female"
    if CachePedData.gender == "Male" then selectedgender = "male" end
    for k, v in pairs(JRS_ASSETS[selectedgender]) do
        if hairstyleCache[k] == nil then
            hairstyleCache[k] = {}
            hairstyleCache[k].model = 0
            hairstyleCache[k].texture = 0
        end
    end

    overlay_all_layers = deepcopy(baseoverlay)

    if not CachePedData or not CachePedData.pedmodel then
        CreatorDebug("[jrs_character_creator] Error: CachePedData not initialized properly")
        return
    end

    DisplayRadar(false)
    -- 4.2.42: a failed model stream used to abort the creator (black/void
    -- screen, no UI). Retry a few times - re-asserting collision/streaming at
    -- the scene between attempts - and if the model still cannot be streamed,
    -- keep going with the current ped so the creator UI always opens.
    local applyOk = ApplyCachePedDataToPedPlayer() ~= false
    local applyTry = 1
    while not applyOk and applyTry < 4 do
        applyTry = applyTry + 1
        local sp = CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.playerSpawn
        if sp and sp.coords then
            RequestCollisionAtCoord(sp.coords.x, sp.coords.y, sp.coords.z)
        end
        Wait(1500)
        applyOk = ApplyCachePedDataToPedPlayer() ~= false
    end
    if not applyOk then
    end

    -- Ensure newly created player ped is anchored firmly at creator coordinates
    CachePed = PlayerPedId()
    SetEntityCoordsNoOffset(CachePed, cx, cy, cz, false, false, false)
    SetEntityHeading(CachePed, ch)
    FreezeEntityPosition(CachePed, true)
    SetEntityCollision(CachePed, true, true)
    SetEntityVisible(CachePed, true, false)
    if type(ResetEntityAlpha) == 'function' then ResetEntityAlpha(CachePed) end
    SetPlayerInvincible(PlayerId(), true)
    JRSSafeNetworkConceal(false)

    local intId = GetInteriorAtCoords(cx, cy, cz)
    if not intId or intId == 0 then intId = GetInteriorFromEntity(CachePed) end
    if not intId or intId == 0 then intId = CreatorConfig and CreatorConfig.CharSelect and CreatorConfig.CharSelect.interior end
    if intId and intId ~= 0 then
        local sets = (CreatorConfig and CreatorConfig.CharSelect and type(CreatorConfig.CharSelect.interior_sets) == 'table')
            and CreatorConfig.CharSelect.interior_sets or {}
        for _, setName in pairs(sets) do
            ActivateInteriorEntitySet(intId, setName)
        end
        if type(RefreshInterior) == 'function' then RefreshInterior(intId) end
    end

    RemoveAllClothesExceptEssentials(CachePed)
    ResetCreatorClothingCache(false)
    ApplyCreatorStarterOutfit()
    Light()
    currentCamDestionation = ""
    MoveCam("default")
    JRSApplyNuiFocus(true, true, true)
    if type(JRSSendCharacterPresentation) == 'function' then
        JRSSendCharacterPresentation('creator', {
            type = "showCharGlobalMenu",
        })
    else
        -- Defensive fallback for unusual hot-reload ordering.
        SendNUIMessage({
            type = "showCharGlobalMenu",
            loadingToken = type(JRSGetLoadingPresentationToken) == 'function'
                and JRSGetLoadingPresentationToken('creator') or nil,
        })
    end
end)

-- Second Chance
SecondChanceMode = false

RegisterNetEvent('jrs_character:adminPrepareCharacterEditor', function()
    CreateThread(function()
        if GetResourceState('jrs_pedmenu') == 'started' then
            pcall(function() exports['jrs_pedmenu']:PrepareCharacterTransition() end)
        end
        TriggerEvent('jrs_character:client:reloadCurrentCharacter')
        TriggerEvent('jrs_character_creator:SecondChance')
    end)
end)

RegisterNetEvent("jrs_character_creator:SecondChance", function()
    SecondChanceMode = true
    
    Callback.triggerServer("jrs_character_creator:GetPedData", function(peddata)
        if peddata and next(peddata) ~= nil then
            CachePedData = peddata
        else
            local ped = PlayerPedId()
            local model = GetEntityModel(ped)
            local gender = model == GetHashKey("mp_male") and "Male" or "Female"
            CachePedData = deepcopy(DefaultCachePedData or {})
            CachePedData.expressions = CachePedData.expressions or {}
            CachePedData.gender = gender
            CachePedData.skintone = tonumber(CachePedData.skintone) or 1
            CachePedData.pedmodel = {
                model = gender == "Male" and "mp_male" or "mp_female",
                outfit = 0
            }
            CachePedData.upperbody = tonumber(CachePedData.upperbody) or 1
            CachePedData.lowerbody = tonumber(CachePedData.lowerbody) or 1
            CachePedData.height = tonumber(CachePedData.height) or 1.0
        end
        
        local selectedgender = "female"
        if CachePedData.gender == "Male" then selectedgender = "male" end
        for k, v in pairs(JRS_ASSETS[selectedgender]) do
            if hairstyleCache[k] == nil then
                hairstyleCache[k] = { model = 0, texture = 0 }
            end
        end
        
        overlay_all_layers = deepcopy(baseoverlay)
        
        Callback.triggerServer("jrs_character_creator:GetCurrentHairs", function(hairData, outfitId, overlays, permanentoverlay)
            if hairData and next(hairData) ~= nil then
                hairstyleCache = hairData
            end
            
            local sourceOverlays = {}
            if overlays and next(overlays) ~= nil then
                for _, ov in pairs(overlays) do
                    if type(ov) == "table" and ov.name then
                        sourceOverlays[ov.name] = ov
                    end
                end
            end
            if permanentoverlay and next(permanentoverlay) ~= nil then
                for _, ov in pairs(permanentoverlay) do
                    if type(ov) == "table" and ov.name then
                        sourceOverlays[ov.name] = ov
                    end
                end
            end

            for k, v in pairs(overlay_all_layers) do
                local saved = sourceOverlays[v.name]
                if saved then
                    for field, val in pairs(saved) do
                        overlay_all_layers[k][field] = val
                    end
                end
            end
            
            Callback.triggerServer("jrs_character_creator:GetCurrentClothes", function(clothes)
                CreatorClothesGender = selectedgender
                CreatorClothesInitialized = true
                CreatorClothesCache = type(clothes) == "table" and clothes or {}
                local genderAssets = JRS_CLOTHING_ASSETS and JRS_CLOTHING_ASSETS[selectedgender] or {}
                for category in pairs(genderAssets) do
                    CreatorClothesCache[category] = CreatorClothesCache[category] or { model = 0, texture = 0 }
                end

                CachePed = PlayerPedId()
                Wait(10)
                DisplayRadar(false)
                Wait(200)
                Light()
                MoveCam("default")
                JRSApplyNuiFocus(true, true, false)
                SendNUIMessage({ type = "showSecondChanceMenu" })
                Wait(50)
                LoadApparenceMenu()
                Wait(1500)
                DisplayPins = true
                OpenApperanceMenu()
            end)
        end)
    end)
end)

RegisterCommand(CreatorConfig.LoadSkinCommand, function(source, args, raw)
    TriggerEvent("jrs_character_creator:loadskin")
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        for k, v in pairs(charselectpeds) do
            if DoesEntityExist(v) then
                DeleteEntity(v)
            end
        end
    end
end)
end
