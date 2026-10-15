

local hiredBalloon = nil      -- owner's balloon entity
local hiredDock = nil         -- dock index it was hired from
local isUIOpen = false
local activeDock = nil        -- dock index the open NUI was launched from
local occupantCount = 0

local passengerBalloon = nil  -- balloon entity this client is riding as passenger
local passengerSeat = nil
local passengerNetId = nil

local dockPeds = {}

local altitudeLocked = false
local lastControlsPressed = nil -- last key-down state pushed to the flight HUD

-- ============================================================================
-- FLIGHT CONTROLS HUD (left-of-screen NUI overlay, shown only while piloting)
-- ============================================================================

-- Replaces the old uiprompt on-screen button legend. This is a plain
-- SendNUIMessage to the resource's own ui_page, so it needs no NUI focus
-- and no extra dependency.
local flightHintShown = false

local function ShowFlightHint()
    flightHintShown = true
    SendNUIMessage({ type = 'showFlightControls', altitudeLocked = altitudeLocked })
end

local function RefreshFlightHint()
    if not flightHintShown then return end
    SendNUIMessage({ type = 'updateFlightControls', altitudeLocked = altitudeLocked })
end

local function HideFlightHint()
    if not flightHintShown then return end
    flightHintShown = false
    SendNUIMessage({ type = 'hideFlightControls' })
    lastControlsPressed = nil
end

-- Live key-down feedback for the HUD (turns a key badge green while held).
-- Only pushed to NUI when something actually changed, so this doesn't spam
-- a message every single tick.
local function TablesEqual(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    return true
end

local function PushControlsPressed(burnerHeld)
    if not flightHintShown then return end
    local pressed = {
        SHIFT = burnerHeld,
        W = IsControlPressed(0, `INPUT_VEH_MOVE_UP_ONLY`),
        A = IsControlPressed(0, `INPUT_VEH_MOVE_LEFT_ONLY`),
        D = IsControlPressed(0, `INPUT_VEH_MOVE_RIGHT_ONLY`),
        S = IsControlPressed(0, `INPUT_VEH_MOVE_DOWN_ONLY`),
        SPACE = IsControlPressed(0, `INPUT_JUMP`),
        R = IsControlPressed(0, `INPUT_RELOAD`),
    }
    if not lastControlsPressed or not TablesEqual(pressed, lastControlsPressed) then
        lastControlsPressed = pressed
        SendNUIMessage({ type = 'flightControlsPressed', pressed = pressed })
    end
end

local function GetCameraRelativeVectors()
    local camRot = GetGameplayCamRot(2)
    local camHeading = math.rad(camRot.z)
    local forwardVector = vector3(-math.sin(camHeading), math.cos(camHeading), 0.0)
    local rightVector = vector3(math.cos(camHeading), math.sin(camHeading), 0.0)
    return forwardVector, rightVector
end

-- ============================================================================
-- HELPERS
-- ============================================================================

local function Notify(title, message, ntype)
    JRS.Notify(('%s: %s'):format(title, message), 5000)
end

local function ResolveGroundZ(x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
    if found then
        return groundZ
    end
    return z
end

local function HeightAboveGround(entity)
    local coords = GetEntityCoords(entity)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false)
    if not found then
        return 999.0
    end
    return coords.z - groundZ
end

local function BalloonSpeed(entity)
    return #(GetEntityVelocity(entity))
end

local function HasActiveBalloon()
    return hiredBalloon ~= nil and DoesEntityExist(hiredBalloon)
end

local function IsBalloonCalm(entity)
    return BalloonSpeed(entity) < Config.StoreMaxSpeed
        and HeightAboveGround(entity) < Config.StoreMaxHeightAGL
end

-- Busy-waits on an arbitrary "is it ready yet" check. Shared by every
-- "request X, wait for it to load" spot in this file so the polling pattern
-- only lives in one place.
local function WaitUntil(checkFn, maxAttempts, intervalMs)
    local attempts = 0
    while not checkFn() and attempts < maxAttempts do
        Wait(intervalMs)
        attempts = attempts + 1
    end
    return checkFn()
end

local function EnsureModelLoaded(hash)
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    return WaitUntil(function() return HasModelLoaded(hash) end, 500, 10)
end

-- True while the local player is in the driver seat of their own balloon
local function IsPiloting()
    if not HasActiveBalloon() then return false end
    local ped = PlayerPedId()
    return IsPedInVehicle(ped, hiredBalloon, false)
        and GetPedInVehicleSeat(hiredBalloon, -1) == ped
end

-- ============================================================================
-- NUI
-- ============================================================================

-- All strings the NUI page needs, forwarded from Lua's L() so the HTML/JS
-- never has to hardcode English. Sent once at startup and again on every
-- OpenBalloonUI call in case the page missed the first message.
local function BuildUiStrings()
    return {
        panelTitle = L('ui.panel_title'),
        panelSubtitle = L('ui.panel_subtitle'),
        back = L('ui.back'),
        close = L('ui.close'),
        serviceStatus = L('ui.service_status'),
        available = L('ui.available'),
        inUse = L('ui.in_use'),
        yourBalance = L('ui.your_balance'),
        hireABalloon = L('ui.hire_a_balloon'),
        scoutBalloon = L('ui.scout_balloon'),
        scoutBalloonDesc = L('ui.scout_balloon_desc'),
        controlsHint1 = L('ui.controls_hint_1'),
        controlsHint2 = L('ui.controls_hint_2'),
        controlsHint3 = L('ui.controls_hint_3'),
        orderSummary = L('ui.order_summary'),
        hireFeePrefix = L('ui.hire_fee_prefix'),
        totalCost = L('ui.total_cost'),
        activeBalloon = L('ui.active_balloon'),
        noBalloonOut = L('ui.no_balloon_out'),
        hire = L('ui.hire'),
        store = L('ui.store'),
        out = L('ui.out'),
        noFunds = L('ui.no_funds'),
        loadingTitle = L('ui.loading_title'),
        preparingBalloon = L('ui.preparing_balloon'),
        storingBalloon = L('ui.storing_balloon'),
        affordable = L('ui.affordable'),
        tooCostly = L('ui.too_costly'),
        balloonOut = L('ui.balloon_out'),
        aboardSuffix = L('ui.aboard_suffix'),
        mooredOutOfPrefix = L('ui.moored_out_of_prefix'),
        mooredOutOfSuffix = L('ui.moored_out_of_suffix'),
        controlsPanelTitle = L('ui.controls_panel_title'),
        locked = L('ui.locked'),
        burnerAscend = L('ui.burner_ascend'),
        driftForward = L('ui.drift_forward'),
        driftLeft = L('ui.drift_left'),
        driftRight = L('ui.drift_right'),
        driftBackward = L('ui.drift_backward'),
        altitudeLock = L('ui.altitude_lock'),
        brake = L('ui.brake'),
        currencySymbol = L('ui.currency_symbol'),
        toastDefaultTitle = L('ui.toast_default_title'),
        toastDefaultMessage = L('ui.toast_default_message'),
        hireFailedTitle = L('title.hire_failed'),
        unableToHire = L('error.unable_to_hire'),
        noBalloonTitle = L('title.no_balloon'),
        noBalloonOutMsg = L('error.no_balloon_out'),
        cannotStoreTitle = L('title.cannot_store'),
        unableToStore = L('error.unable_to_store'),
        balloonHiredTitle = L('title.balloon_hired'),
        balloonStoredTitle = L('title.balloon_stored'),
        balloonStoredMsg = L('success.balloon_stored'),
    }
end

local function PushUiStrings()
    SendNUIMessage({ type = 'setLocale', strings = BuildUiStrings(), rtl = Config.Language == 'ar' })
end

CreateThread(function()
    PushUiStrings()
end)

local function OpenBalloonUI(dockIndex)
    local dock = Config.Docks[dockIndex]
    if not dock then return end
    local elements = {}
    if HasActiveBalloon() then
        elements[#elements + 1] = { label = L('target.store_balloon'), value = 'store', desc = L('ui.active_balloon') }
    else
        elements[#elements + 1] = { label = L('target.hire_balloon'), value = 'hire', desc = ('$%s'):format(Config.HirePrice) }
    end
    JRS.OpenMenu('jrs_hotair', dock.label, L('ui.panel_title'), elements, function(el, menu)
        menu.close()
        if el.value == 'store' then return StoreHiredBalloon() end
        if HasActiveBalloon() then return Notify(L('title.hire_failed'), L('error.already_have_balloon'), 'error') end
        local success, reason = JRS.Await('jrs_hotair:server:hireBalloon', dockIndex)
        if not success then
            return Notify(L('title.hire_failed'), reason or L('error.unable_to_hire'), 'error')
        end
        SpawnHiredBalloon(dockIndex)
    end)
end

local function PushActiveState() end

-- ============================================================================
-- HIRE / SPAWN / STORE
-- ============================================================================

function SpawnHiredBalloon(dockIndex)
    local dock = Config.Docks[dockIndex]
    if not dock then return end
    local model = GetHashKey(Config.Model)
    if not EnsureModelLoaded(model) then
        TriggerServerEvent('jrs_hotair:server:cancelHire')
        Notify(L('title.hire_failed'), L('error.model_load_failed'), 'error')
        return
    end
    local gz = ResolveGroundZ(dock.spawnCoords.x, dock.spawnCoords.y, dock.spawnCoords.z)
    local balloon = CreateVehicle(model, dock.spawnCoords.x, dock.spawnCoords.y, gz + 1.0, dock.spawnHeading, true, false, false, false)
    if not DoesEntityExist(balloon) then
        TriggerServerEvent('jrs_hotair:server:cancelHire')
        Notify(L('title.hire_failed'), L('error.balloon_ready_failed'), 'error')
        return
    end
    SetModelAsNoLongerNeeded(model)
    SetEntityAsMissionEntity(balloon, true, true)
    SetVehicleOnGroundProperly(balloon)
    FreezeEntityPosition(balloon, false)
    NetworkRegisterEntityAsNetworked(balloon)

    hiredBalloon = balloon
    hiredDock = dockIndex
    occupantCount = 0

    local netId = NetworkGetNetworkIdFromEntity(balloon)
    SetNetworkIdExistsOnAllMachines(netId, true)
    TriggerServerEvent('jrs_hotair:server:registerBalloon', netId)
    RegisterBalloonTarget(balloon)

    local ped = PlayerPedId()
    TaskEnterVehicle(ped, balloon, -1, -1, 2.0, 1, 0)
    local seated = WaitUntil(function() return IsPedInVehicle(ped, balloon, false) end, 500, 10)
    if not seated then
        TaskWarpPedIntoVehicle(ped, balloon, -1)
    end

    local hiredMessage = L('success.balloon_hired_at', dock.label)
    Notify(L('title.balloon_hired'), hiredMessage, 'success')
    SendNUIMessage({ type = 'hireSuccess', dockLabel = dock.label, message = hiredMessage })
    PushActiveState()
end

function StoreHiredBalloon()
    if not HasActiveBalloon() then
        SendNUIMessage({ type = 'storeFailed', reason = L('error.no_balloon_out') })
        Notify(L('title.no_balloon'), L('error.no_balloon_out'), 'error')
        return
    end
    if not IsBalloonCalm(hiredBalloon) then
        SendNUIMessage({ type = 'storeFailed', reason = L('error.must_land_to_store') })
        Notify(L('title.too_unsteady'), L('error.must_land_to_store'), 'error')
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(hiredBalloon)
    TriggerServerEvent('jrs_hotair:server:disembarkAll', netId)
    DeleteEntity(hiredBalloon)
    hiredBalloon = nil
    hiredDock = nil
    occupantCount = 0
    altitudeLocked = false
    HideFlightHint()
    TriggerServerEvent('jrs_hotair:server:storedBalloon')
    Notify(L('title.balloon_stored'), L('success.balloon_stored'), 'success')
    SendNUIMessage({ type = 'storeSuccess' })
    PushActiveState()
end

-- ============================================================================
-- the JRS interaction prompt
-- ============================================================================

function RegisterBalloonTarget(balloon) end -- interaction is done with prompts (see bottom)

-- ============================================================================
-- PASSENGERS
-- ============================================================================

function RequestPassengerSeat(entity)
    if not DoesEntityExist(entity) then return end
    if BalloonSpeed(entity) >= Config.BoardMaxSpeed
        or HeightAboveGround(entity) >= Config.BoardMaxHeightAGL then
        Notify(L('title.cannot_board'), L('error.balloon_must_be_landed_to_board'), 'error')
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId == 0 then
        Notify(L('title.cannot_board'), L('error.cannot_reach_balloon'), 'error')
        return
    end
    JRS.TriggerCallback('jrs_hotair:server:requestSeat', function(granted, seat, reason)
        if not granted then
            Notify(L('title.cannot_board'), reason or L('error.no_seat_available'), 'error')
            return
        end
        AttachPassenger(entity, netId, seat)
    end, netId)
end

function AttachPassenger(entity, netId, seat)
    local offset = Config.PassengerOffsets[seat]
    if not offset then return end
    local target = entity
    if not DoesEntityExist(target) then
        target = NetworkGetEntityFromNetworkId(netId)
        WaitUntil(function() return DoesEntityExist(target) end, 500, 10)
        if not DoesEntityExist(target) then
            TriggerServerEvent('jrs_hotair:server:vacateSeat', netId, seat)
            Notify(L('title.cannot_board'), L('error.lost_sight_of_balloon'), 'error')
            return
        end
    end
    local ped = PlayerPedId()
    AttachEntityToEntity(ped, target, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, false, false, false, false, 0, true)
    SetPedCanRagdoll(ped, false)
    SetPedConfigFlag(ped, 166, true)
    passengerBalloon = target
    passengerSeat = seat
    passengerNetId = netId
    Notify(L('title.aboard'), L('success.aboard'), 'success')
end

function LeavePassengerSeat(forced)
    if passengerBalloon == nil then return end
    local ped = PlayerPedId()
    if not forced then
        if BalloonSpeed(passengerBalloon) >= Config.BoardMaxSpeed
            or HeightAboveGround(passengerBalloon) >= Config.BoardMaxHeightAGL then
            Notify(L('title.cannot_disembark'), L('error.must_wait_to_disembark'), 'error')
            return
        end
    end
    if passengerNetId and passengerSeat then
        TriggerServerEvent('jrs_hotair:server:vacateSeat', passengerNetId, passengerSeat)
    end
    DetachEntity(ped, true, true)
    SetPedCanRagdoll(ped, true)
    -- place on the ground beside the basket
    local coords = GetEntityCoords(passengerBalloon)
    local drop = GetOffsetFromEntityInWorldCoords(passengerBalloon, 1.5, 0.0, 0.0)
    local gz = ResolveGroundZ(drop.x, drop.y, coords.z)
    SetEntityCoords(ped, drop.x, drop.y, gz + 0.5, false, false, false, false)
    passengerBalloon = nil
    passengerSeat = nil
    passengerNetId = nil
end

RegisterNetEvent('jrs_hotair:client:forceDisembark', function()
    LeavePassengerSeat(true)
end)

RegisterNetEvent('jrs_hotair:client:seatUpdate', function(count)
    occupantCount = count or 0
    PushActiveState()
end)

-- ============================================================================
-- FLIGHT
-- ============================================================================

local wasPiloting = false

Citizen.CreateThread(function()
    while true do
        local piloting = IsPiloting()
        if piloting ~= wasPiloting then
            wasPiloting = piloting
            if piloting then
                ShowFlightHint()
            else
                altitudeLocked = false
                HideFlightHint()
            end
        end
        if piloting then
            FlyBalloonTick(hiredBalloon)
            Wait(0)
        elseif HasActiveBalloon() then
            -- unmanned: barely settle horizontal drift, never force motion
            if BalloonSpeed(hiredBalloon) > 0.3 then
                local v = GetEntityVelocity(hiredBalloon)
                SetEntityVelocity(hiredBalloon, v.x * 0.995, v.y * 0.995, v.z)
            end
            -- wrecked: clean up + free the slot
            if IsEntityDead(hiredBalloon, false) then
                DeleteEntity(hiredBalloon)
                hiredBalloon = nil
                hiredDock = nil
                occupantCount = 0
                altitudeLocked = false
                HideFlightHint()
                TriggerServerEvent('jrs_hotair:server:storedBalloon')
                Notify(L('title.balloon_lost'), L('error.balloon_destroyed'), 'error')
                PushActiveState()
            end
            Wait(100)
        else
            Wait(1000)
        end
    end
end)

function FlyBalloonTick(balloon)
    -- no horn honk while piloting; horn key stores the balloon instead
    DisableControlAction(0, `INPUT_VEH_HORN`, true)

    -- burner (climb): Shift fakes the vehicle's native throttle-up control
    -- each tick it's held, so the balloon's own ascend physics still drive
    -- it up. Everything else in this tick reads `burnerHeld` rather than
    -- re-querying the underlying throttle control directly.
    local burnerHeld = IsControlPressed(0, `INPUT_SPRINT`)
    if burnerHeld then
        SetControlNormal(0, `INPUT_VEH_FLY_THROTTLE_UP`, 1.0)
    end

    local speed = IsControlPressed(0, `INPUT_VEH_TRAVERSAL`) and Config.BoostSpeed or Config.CruiseSpeed
    local v1 = GetEntityVelocity(balloon)
    local v2 = v1

    -- camera-relative momentum drift (nothing forced, velocity accumulates)
    local forwardVec, rightVec = GetCameraRelativeVectors()
    if IsControlPressed(0, `INPUT_VEH_MOVE_UP_ONLY`) then
        v2 = v2 + forwardVec * speed
    end
    if IsControlPressed(0, `INPUT_VEH_MOVE_DOWN_ONLY`) then
        v2 = v2 - forwardVec * speed
    end
    if IsControlPressed(0, `INPUT_VEH_MOVE_LEFT_ONLY`) then
        v2 = v2 - rightVec * speed
    end
    if IsControlPressed(0, `INPUT_VEH_MOVE_RIGHT_ONLY`) then
        v2 = v2 + rightVec * speed
    end

    -- brake (R): bleed off horizontal velocity toward zero
    if IsControlPressed(0, `INPUT_RELOAD`) then
        v2 = vector3(
            v2.x > 0 and math.max(0, v2.x - speed) or math.min(0, v2.x + speed),
            v2.y > 0 and math.max(0, v2.y - speed) or math.min(0, v2.y + speed),
            v2.z
        )
    end

    -- altitude lock toggle (Space)
    if IsControlJustPressed(0, `INPUT_JUMP`) then
        altitudeLocked = not altitudeLocked
        RefreshFlightHint()
        Notify(
            altitudeLocked and L('title.altitude_locked') or L('title.altitude_unlocked'),
            altitudeLocked and L('info.altitude_locked_desc') or L('info.altitude_unlocked_desc'),
            'info'
        )
    end

    if altitudeLocked and not burnerHeld then
        SetEntityVelocity(balloon, vector3(v2.x, v2.y, 0.0))
    elseif v2 ~= v1 then
        SetEntityVelocity(balloon, v2)
    end

    -- altitude ceiling safety (above ground)
    local coords = GetEntityCoords(balloon)
    local _, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false)
    if groundZ and coords.z > (groundZ + Config.MaxAltitudeAGL) then
        SetEntityCoords(balloon, coords.x, coords.y, groundZ + Config.MaxAltitudeAGL, false, false, false, false)
    end

    -- store via horn key once landed
    if IsControlJustPressed(0, `INPUT_VEH_HORN`) then
        if GetEntityHeightAboveGround(balloon) <= 0.5 then
            StoreHiredBalloon()
        else
            Notify(L('title.too_high'), L('error.must_land_before_storing'), 'error')
        end
    end

    PushControlsPressed(burnerHeld)
end

-- burner rope-pull animation while piloting
local pilotAnim = nil

local function PlayPilotAnim(ped, name)
    local dict = 'script_story@gng2@ig@ig_2_balloon_control'
    if not DoesAnimDictExist(dict) then return end
    if pilotAnim == name and IsEntityPlayingAnim(ped, dict, name, 3) then return end
    RequestAnimDict(dict)
    if not WaitUntil(function() return HasAnimDictLoaded(dict) end, 200, 10) then return end
    TaskPlayAnim(ped, dict, name, 1.0, 1.0, -1, 17, 0.0, false, 0, false, '', false)
    RemoveAnimDict(dict)
    pilotAnim = name
end

Citizen.CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local piloting = IsPiloting()
        if piloting then
            local burning = IsControlPressed(0, `INPUT_SPRINT`)
            PlayPilotAnim(ped, burning and 'base_burner_pull_arthur' or 'idle_burner_line_arthur')
            Wait(500)
        else
            if pilotAnim ~= nil then
                StopAnimTask(ped, 'script_story@gng2@ig@ig_2_balloon_control', pilotAnim, 1.0)
                pilotAnim = nil
            end
            Wait(2000)
        end
    end
end)

-- lock the exit key while airborne, free it near the ground
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if HasActiveBalloon() and IsPedInVehicle(PlayerPedId(), hiredBalloon, false) then
            if GetEntityHeightAboveGround(hiredBalloon) > 0.5 then
                DisableControlAction(0, `INPUT_VEH_EXIT`, true)
            end
        else
            Citizen.Wait(500)
        end
    end
end)

-- no ragdoll for occupants
Citizen.CreateThread(function()
    while true do
        if HasActiveBalloon() then
            local maxPax = GetVehicleMaxNumberOfPassengers(hiredBalloon)
            for seat = -1, maxPax do
                local occupant = GetPedInVehicleSeat(hiredBalloon, seat)
                if occupant ~= 0 and IsPedAPlayer(occupant) then
                    SetPedCanRagdoll(occupant, false)
                    SetPedConfigFlag(occupant, 166, true)
                end
            end
            Wait(2000)
        else
            Wait(5000)
        end
    end
end)

-- ============================================================================
-- DOCKS
-- ============================================================================

Citizen.CreateThread(function()
    for i, dock in ipairs(Config.Docks) do
        local hash = GetHashKey(dock.npcModel)
        if EnsureModelLoaded(hash) then
            local gz = ResolveGroundZ(dock.npcCoords.x, dock.npcCoords.y, dock.npcCoords.z)
            local ped = CreatePed(hash, dock.npcCoords.x, dock.npcCoords.y, gz, dock.npcCoords.w, false, false, false, false)
            Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            SetPedCanBeTargetted(ped, false)
            SetModelAsNoLongerNeeded(hash)
            dockPeds[i] = ped

            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, dock.npcCoords.x, dock.npcCoords.y, gz)
            SetBlipSprite(blip, dock.blip.sprite, 1)
            SetBlipScale(blip, dock.blip.scale)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, dock.blip.name)

        else
            print(string.format('^1[jrs_hotair]^0 Dock NPC model failed to load: %s', dock.npcModel))
        end
    end
end)

-- ============================================================================
-- COMMANDS / MISC
-- ============================================================================

RegisterCommand('hotair', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local nearest, nearestDist = nil, nil
    for i, dock in ipairs(Config.Docks) do
        local d = #(coords - vector3(dock.npcCoords.x, dock.npcCoords.y, dock.npcCoords.z))
        if not nearestDist or d < nearestDist then
            nearest, nearestDist = i, d
        end
    end
    if nearest and nearestDist < 50.0 then
        OpenBalloonUI(nearest)
    else
        Notify(L('title.balloon_hire'), L('info.visit_dock'), 'info')
    end
end, false)


local function CleanUp()
    HideFlightHint()
    if HasActiveBalloon() then
        DeleteEntity(hiredBalloon)
        hiredBalloon = nil
    end
    if passengerBalloon ~= nil then
        DetachEntity(PlayerPedId(), true, true)
        passengerBalloon = nil
        passengerSeat = nil
        passengerNetId = nil
    end
    for _, ped in pairs(dockPeds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end
    dockPeds = {}
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        CleanUp()
    end
end)

-- ============================================================================
-- PROMPTS (no third-eye targeting)
-- ============================================================================
CreateThread(function()
    local model = GetHashKey(Config.Model)
    local prompts = JRS.Prompts()
    local pHire = prompts:add(0x760A9C6F, LE('target.hire_balloon'))
    local pPilot = prompts:add(0x760A9C6F, LE('target.pilot_balloon'))
    local pStorage = prompts:add(0xCEFD9220, LE('target.open_storage'))
    local pStore = prompts:add(0xD9D0E1C0, LE('target.store_balloon'), 1500)
    local pBoard = prompts:add(0x760A9C6F, LE('target.board_balloon'))
    local pLeave = prompts:add(0x760A9C6F, LE('target.disembark'))
    local all = { pHire, pPilot, pStorage, pStore, pBoard, pLeave }

    while true do
        local wait = 500
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local show, title = {}, nil

        -- dock NPCs
        for i, dock in ipairs(Config.Docks) do
            if #(pos - dock.npcCoords.xyz) < 3.0 and not IsPedInAnyVehicle(ped, false) then
                show[pHire], title = i, dock.label
            end
        end

        -- own balloon
        if not title and HasActiveBalloon() and not IsPedInAnyVehicle(ped, false)
            and #(pos - GetEntityCoords(hiredBalloon)) < Config.TargetDistance then
            title = LE('title.balloon_hire')
            show[pStorage] = true
            if IsBalloonCalm(hiredBalloon) then show[pPilot], show[pStore] = true, true end
        end

        -- passenger / other balloons
        if not title then
            if passengerBalloon ~= nil and DoesEntityExist(passengerBalloon) then
                show[pLeave], title = true, LE('title.aboard')
            elseif not IsPedInAnyVehicle(ped, false) then
                local other = GetClosestVehicle(pos.x, pos.y, pos.z, Config.TargetDistance, model, 70)
                if other ~= 0 and other ~= hiredBalloon and BalloonSpeed(other) < Config.BoardMaxSpeed
                    and HeightAboveGround(other) < Config.BoardMaxHeightAGL then
                    show[pBoard], title = other, LE('title.balloon_hire')
                end
            end
        end

        if title then
            wait = 0
            for _, p in ipairs(all) do prompts:visible(p, show[p] ~= nil) end
            prompts:show(title)
            if show[pHire] and prompts:done(pHire) then
                OpenBalloonUI(show[pHire]); Wait(500)
            elseif show[pPilot] and prompts:done(pPilot) then
                TaskEnterVehicle(ped, hiredBalloon, -1, -1, 2.0, 1, 0); Wait(500)
            elseif show[pStorage] and prompts:done(pStorage) then
                local ok, reason = JRS.Await('jrs_hotair:server:openStorage')
                if not ok then Notify(L('title.cannot_open_storage'), reason or L('error.unable_to_open_storage'), 'error') end
                Wait(500)
            elseif show[pStore] and prompts:done(pStore) then
                StoreHiredBalloon(); Wait(500)
            elseif show[pBoard] and prompts:done(pBoard) then
                RequestPassengerSeat(show[pBoard]); Wait(500)
            elseif show[pLeave] and prompts:done(pLeave) then
                LeavePassengerSeat(false); Wait(500)
            end
        end
        Wait(wait)
    end
end)
