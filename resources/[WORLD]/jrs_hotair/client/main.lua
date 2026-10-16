-- jrs_hotair | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_hotair | client
-- Hire a hot-air balloon at a dock, fly it with the keyboard (burner, drift, brake, altitude lock) and store it
-- again. Friends can ride in the basket as passengers. Prompts are used for every interaction, a small NUI
-- overlay shows the flight keys.

local hired, hiredDock = nil, nil           -- the balloon this player hired, and the dock it came from
local occupants = 0                         -- how many people sit in it

local riding, ridingSeat, ridingNet = nil, nil, nil     -- the balloon this player rides in as a passenger

local dockPeds = {}
local altitudeLock = false
local hintShown = false
local lastKeys

local PILOT_DICT <const> = 'script_story@gng2@ig@ig_2_balloon_control'

-- ------------------------------------------------------------------ small helpers

local function notify(title, message) JRS.Notify(('%s: %s'):format(title, message), 5000) end

local function groundBelow(x, y, z)
    local found, ground = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
    return found and ground or z
end

local function heightOf(entity)
    local at = GetEntityCoords(entity)
    local found, ground = GetGroundZFor_3dCoord(at.x, at.y, at.z, false)
    return found and at.z - ground or 999.0
end

local function speedOf(entity) return #(GetEntityVelocity(entity)) end

local function owns() return hired ~= nil and DoesEntityExist(hired) end

local function calm(entity)
    return speedOf(entity) < Config.StoreMaxSpeed and heightOf(entity) < Config.StoreMaxHeightAGL
end

local function landed(entity)
    return speedOf(entity) < Config.BoardMaxSpeed and heightOf(entity) < Config.BoardMaxHeightAGL
end

-- polls `ready()` up to `tries` times, `every` ms apart
local function waitFor(ready, tries, every)
    local n = 0
    while not ready() and n < tries do Wait(every) n = n + 1 end
    return ready()
end

local function loadModel(hash)
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    return waitFor(function() return HasModelLoaded(hash) end, 500, 10)
end

local function piloting()
    if not owns() then return false end
    local ped = PlayerPedId()
    return IsPedInVehicle(ped, hired, false) and GetPedInVehicleSeat(hired, -1) == ped
end

local function forgetBalloon()
    hired, hiredDock, occupants, altitudeLock = nil, nil, 0, false
end

-- ------------------------------------------------------------------ flight hint (NUI)

local KEY_STATE <const> = {
    SHIFT = 'INPUT_SPRINT', W = 'INPUT_VEH_MOVE_UP_ONLY', A = 'INPUT_VEH_MOVE_LEFT_ONLY', D = 'INPUT_VEH_MOVE_RIGHT_ONLY',
    S = 'INPUT_VEH_MOVE_DOWN_ONLY', SPACE = 'INPUT_JUMP', R = 'INPUT_RELOAD',
}

local function showHint()
    hintShown = true
    SendNUIMessage({ type = 'showFlightControls', altitudeLocked = altitudeLock })
end

local function refreshHint()
    if hintShown then SendNUIMessage({ type = 'updateFlightControls', altitudeLocked = altitudeLock }) end
end

local function hideHint()
    if not hintShown then return end
    hintShown, lastKeys = false, nil
    SendNUIMessage({ type = 'hideFlightControls' })
end

-- sends the held keys, but only when they changed
local function pushKeys(burner)
    if not hintShown then return end
    local held = {}
    for label, control in pairs(KEY_STATE) do held[label] = IsControlPressed(0, joaat(control)) end
    held.SHIFT = burner

    local same = lastKeys ~= nil
    if same then
        for label, value in pairs(held) do
            if lastKeys[label] ~= value then same = false break end
        end
    end
    if not same then
        lastKeys = held
        SendNUIMessage({ type = 'flightControlsPressed', pressed = held })
    end
end

-- the page gets every text from Lua's L(), so it never hardcodes a language
local UI_KEYS <const> = {
    'panel_title', 'panel_subtitle', 'back', 'close', 'service_status', 'available', 'in_use', 'your_balance', 'hire_a_balloon',
    'scout_balloon', 'scout_balloon_desc', 'controls_hint_1', 'controls_hint_2', 'controls_hint_3', 'order_summary', 'hire_fee_prefix',
    'total_cost', 'active_balloon', 'no_balloon_out', 'hire', 'store', 'out', 'no_funds', 'loading_title', 'preparing_balloon',
    'storing_balloon', 'affordable', 'too_costly', 'balloon_out', 'aboard_suffix', 'moored_out_of_prefix', 'moored_out_of_suffix',
    'controls_panel_title', 'locked', 'burner_ascend', 'drift_forward', 'drift_left', 'drift_right', 'drift_backward', 'altitude_lock',
    'brake', 'currency_symbol', 'toast_default_title', 'toast_default_message',
}
local UI_EXTRA <const> = {
    hireFailedTitle = 'title.hire_failed', unableToHire = 'error.unable_to_hire', noBalloonTitle = 'title.no_balloon',
    noBalloonOutMsg = 'error.no_balloon_out', cannotStoreTitle = 'title.cannot_store', unableToStore = 'error.unable_to_store',
    balloonHiredTitle = 'title.balloon_hired', balloonStoredTitle = 'title.balloon_stored', balloonStoredMsg = 'success.balloon_stored',
}

local function camel(snake)
    return (snake:gsub('_(%w)', function(c) return c:upper() end))
end

local function pushStrings()
    local strings = {}
    for _, key in ipairs(UI_KEYS) do strings[camel(key)] = L('ui.' .. key) end
    for name, key in pairs(UI_EXTRA) do strings[name] = L(key) end
    SendNUIMessage({ type = 'setLocale', strings = strings, rtl = Config.Language == 'ar' })
end
CreateThread(pushStrings)

-- ------------------------------------------------------------------ hiring and storing

function StoreHiredBalloon()
    if not owns() then
        SendNUIMessage({ type = 'storeFailed', reason = L('error.no_balloon_out') })
        return notify(L('title.no_balloon'), L('error.no_balloon_out'))
    end
    if not calm(hired) then
        SendNUIMessage({ type = 'storeFailed', reason = L('error.must_land_to_store') })
        return notify(L('title.too_unsteady'), L('error.must_land_to_store'))
    end

    TriggerServerEvent('jrs_hotair:server:disembarkAll', NetworkGetNetworkIdFromEntity(hired))
    DeleteEntity(hired)
    forgetBalloon()
    hideHint()
    TriggerServerEvent('jrs_hotair:server:storedBalloon')
    notify(L('title.balloon_stored'), L('success.balloon_stored'))
    SendNUIMessage({ type = 'storeSuccess' })
end

local function spawnBalloon(dockIndex)
    local dock = Config.Docks[dockIndex]
    if not dock then return end

    local function fail(reason)
        TriggerServerEvent('jrs_hotair:server:cancelHire')
        notify(L('title.hire_failed'), L(reason))
    end

    local model = joaat(Config.Model)
    if not loadModel(model) then return fail('error.model_load_failed') end

    local at = dock.spawnCoords
    local balloon = CreateVehicle(model, at.x, at.y, groundBelow(at.x, at.y, at.z) + 1.0, dock.spawnHeading, true, false, false, false)
    if not DoesEntityExist(balloon) then return fail('error.balloon_ready_failed') end
    SetModelAsNoLongerNeeded(model)
    SetEntityAsMissionEntity(balloon, true, true)
    SetVehicleOnGroundProperly(balloon)
    FreezeEntityPosition(balloon, false)
    NetworkRegisterEntityAsNetworked(balloon)

    hired, hiredDock, occupants = balloon, dockIndex, 0

    local netId = NetworkGetNetworkIdFromEntity(balloon)
    SetNetworkIdExistsOnAllMachines(netId, true)
    TriggerServerEvent('jrs_hotair:server:registerBalloon', netId)

    local ped = PlayerPedId()
    TaskEnterVehicle(ped, balloon, -1, -1, 2.0, 1, 0)
    if not waitFor(function() return IsPedInVehicle(ped, balloon, false) end, 500, 10) then
        TaskWarpPedIntoVehicle(ped, balloon, -1)
    end

    local message = L('success.balloon_hired_at', dock.label)
    notify(L('title.balloon_hired'), message)
    SendNUIMessage({ type = 'hireSuccess', dockLabel = dock.label, message = message })
end

local function dockMenu(dockIndex)
    local dock = Config.Docks[dockIndex]
    if not dock then return end

    local row
    if owns() then
        row = { label = L('target.store_balloon'), value = 'store', desc = L('ui.active_balloon') }
    else
        row = { label = L('target.hire_balloon'), value = 'hire', desc = ('$%s'):format(Config.HirePrice) }
    end

    JRS.OpenMenu('jrs_hotair', dock.label, L('ui.panel_title'), { row }, function(picked, menu)
        menu.close()
        if picked.value == 'store' then return StoreHiredBalloon() end
        if owns() then return notify(L('title.hire_failed'), L('error.already_have_balloon')) end

        local ok, reason = JRS.Await('jrs_hotair:server:hireBalloon', dockIndex)
        if not ok then return notify(L('title.hire_failed'), reason or L('error.unable_to_hire')) end
        spawnBalloon(dockIndex)
    end)
end

-- ------------------------------------------------------------------ passengers

local function sit(entity, netId, seat)
    local offset = Config.PassengerOffsets[seat]
    if not offset then return end

    local balloon = entity
    if not DoesEntityExist(balloon) then
        balloon = NetworkGetEntityFromNetworkId(netId)
        waitFor(function() return DoesEntityExist(balloon) end, 500, 10)
        if not DoesEntityExist(balloon) then
            TriggerServerEvent('jrs_hotair:server:vacateSeat', netId, seat)
            return notify(L('title.cannot_board'), L('error.lost_sight_of_balloon'))
        end
    end

    local ped = PlayerPedId()
    AttachEntityToEntity(ped, balloon, 0, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, false, false, false, false, 0, true)
    SetPedCanRagdoll(ped, false)
    SetPedConfigFlag(ped, 166, true)
    riding, ridingSeat, ridingNet = balloon, seat, netId
    notify(L('title.aboard'), L('success.aboard'))
end

local function board(entity)
    if not DoesEntityExist(entity) then return end
    if not landed(entity) then return notify(L('title.cannot_board'), L('error.balloon_must_be_landed_to_board')) end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId == 0 then return notify(L('title.cannot_board'), L('error.cannot_reach_balloon')) end

    JRS.TriggerCallback('jrs_hotair:server:requestSeat', function(granted, seat, reason)
        if not granted then return notify(L('title.cannot_board'), reason or L('error.no_seat_available')) end
        sit(entity, netId, seat)
    end, netId)
end

local function climbOut(forced)
    if not riding then return end
    if not forced and not landed(riding) then
        return notify(L('title.cannot_disembark'), L('error.must_wait_to_disembark'))
    end

    local ped = PlayerPedId()
    if ridingNet and ridingSeat then TriggerServerEvent('jrs_hotair:server:vacateSeat', ridingNet, ridingSeat) end
    DetachEntity(ped, true, true)
    SetPedCanRagdoll(ped, true)

    local beside = GetOffsetFromEntityInWorldCoords(riding, 1.5, 0.0, 0.0)
    SetEntityCoords(ped, beside.x, beside.y, groundBelow(beside.x, beside.y, GetEntityCoords(riding).z) + 0.5, false, false, false, false)
    riding, ridingSeat, ridingNet = nil, nil, nil
end

RegisterNetEvent('jrs_hotair:client:forceDisembark', function() climbOut(true) end)
RegisterNetEvent('jrs_hotair:client:seatUpdate', function(count) occupants = count or 0 end)

-- ------------------------------------------------------------------ flying

local function flyTick(balloon)
    DisableControlAction(0, `INPUT_VEH_HORN`, true)          -- the horn key stores the balloon instead

    -- Shift fakes the throttle-up control so the balloon's own physics climb
    local burner = IsControlPressed(0, `INPUT_SPRINT`)
    if burner then SetControlNormal(0, `INPUT_VEH_FLY_THROTTLE_UP`, 1.0) end

    local push = IsControlPressed(0, `INPUT_VEH_TRAVERSAL`) and Config.BoostSpeed or Config.CruiseSpeed
    local before = GetEntityVelocity(balloon)
    local velocity = before

    -- drift relative to the camera: velocity builds up, nothing is forced
    local heading = math.rad(GetGameplayCamRot(2).z)
    local forward = vector3(-math.sin(heading), math.cos(heading), 0.0)
    local right = vector3(math.cos(heading), math.sin(heading), 0.0)
    if IsControlPressed(0, `INPUT_VEH_MOVE_UP_ONLY`) then velocity = velocity + forward * push end
    if IsControlPressed(0, `INPUT_VEH_MOVE_DOWN_ONLY`) then velocity = velocity - forward * push end
    if IsControlPressed(0, `INPUT_VEH_MOVE_LEFT_ONLY`) then velocity = velocity - right * push end
    if IsControlPressed(0, `INPUT_VEH_MOVE_RIGHT_ONLY`) then velocity = velocity + right * push end

    -- brake (R): sideways speed bleeds towards zero
    if IsControlPressed(0, `INPUT_RELOAD`) then
        local function towardZero(v) return v > 0 and math.max(0, v - push) or math.min(0, v + push) end
        velocity = vector3(towardZero(velocity.x), towardZero(velocity.y), velocity.z)
    end

    if IsControlJustPressed(0, `INPUT_JUMP`) then
        altitudeLock = not altitudeLock
        refreshHint()
        if altitudeLock then notify(L('title.altitude_locked'), L('info.altitude_locked_desc'))
        else notify(L('title.altitude_unlocked'), L('info.altitude_unlocked_desc')) end
    end

    if altitudeLock and not burner then
        SetEntityVelocity(balloon, vector3(velocity.x, velocity.y, 0.0))
    elseif velocity ~= before then
        SetEntityVelocity(balloon, velocity)
    end

    -- ceiling above ground
    local at = GetEntityCoords(balloon)
    local _, ground = GetGroundZFor_3dCoord(at.x, at.y, at.z, false)
    if ground and at.z > ground + Config.MaxAltitudeAGL then
        SetEntityCoords(balloon, at.x, at.y, ground + Config.MaxAltitudeAGL, false, false, false, false)
    end

    if IsControlJustPressed(0, `INPUT_VEH_HORN`) then
        if GetEntityHeightAboveGround(balloon) <= 0.5 then StoreHiredBalloon()
        else notify(L('title.too_high'), L('error.must_land_before_storing')) end
    end

    pushKeys(burner)
end

CreateThread(function()
    local was = false
    while true do
        local now = piloting()
        if now ~= was then
            was = now
            if now then showHint() else altitudeLock = false hideHint() end
        end

        if now then
            flyTick(hired)
            Wait(0)
        elseif owns() then
            -- nobody at the burner: the balloon only settles, it is never pushed
            if speedOf(hired) > 0.3 then
                local v = GetEntityVelocity(hired)
                SetEntityVelocity(hired, v.x * 0.995, v.y * 0.995, v.z)
            end
            if IsEntityDead(hired, false) then
                DeleteEntity(hired)
                forgetBalloon()
                hideHint()
                TriggerServerEvent('jrs_hotair:server:storedBalloon')
                notify(L('title.balloon_lost'), L('error.balloon_destroyed'))
            end
            Wait(100)
        else
            Wait(1000)
        end
    end
end)

-- the pilot's hands: rope pull while the burner is on, idle otherwise
CreateThread(function()
    local playing
    while true do
        local ped = PlayerPedId()
        if piloting() then
            local name = IsControlPressed(0, `INPUT_SPRINT`) and 'base_burner_pull_arthur' or 'idle_burner_line_arthur'
            if DoesAnimDictExist(PILOT_DICT) and not (playing == name and IsEntityPlayingAnim(ped, PILOT_DICT, name, 3)) then
                RequestAnimDict(PILOT_DICT)
                if waitFor(function() return HasAnimDictLoaded(PILOT_DICT) end, 200, 10) then
                    TaskPlayAnim(ped, PILOT_DICT, name, 1.0, 1.0, -1, 17, 0.0, false, 0, false, '', false)
                    RemoveAnimDict(PILOT_DICT)
                    playing = name
                end
            end
            Wait(500)
        else
            if playing then StopAnimTask(ped, PILOT_DICT, playing, 1.0) playing = nil end
            Wait(2000)
        end
    end
end)

-- no leaving the basket in the air
CreateThread(function()
    while true do
        if owns() and IsPedInVehicle(PlayerPedId(), hired, false) then
            Wait(0)
            if GetEntityHeightAboveGround(hired) > 0.5 then DisableControlAction(0, `INPUT_VEH_EXIT`, true) end
        else
            Wait(500)
        end
    end
end)

-- whoever sits in the balloon cannot ragdoll out of it
CreateThread(function()
    while true do
        if owns() then
            for seat = -1, GetVehicleMaxNumberOfPassengers(hired) do
                local who = GetPedInVehicleSeat(hired, seat)
                if who ~= 0 and IsPedAPlayer(who) then
                    SetPedCanRagdoll(who, false)
                    SetPedConfigFlag(who, 166, true)
                end
            end
            Wait(2000)
        else
            Wait(5000)
        end
    end
end)

-- ------------------------------------------------------------------ docks

CreateThread(function()
    for i, dock in ipairs(Config.Docks) do
        local model = joaat(dock.npcModel)
        if loadModel(model) then
            local at = dock.npcCoords
            local z = groundBelow(at.x, at.y, at.z)
            local ped = CreatePed(model, at.x, at.y, z, at.w, false, false, false, false)
            Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            SetPedCanBeTargetted(ped, false)
            SetModelAsNoLongerNeeded(model)
            dockPeds[i] = ped

            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, at.x, at.y, z)
            SetBlipSprite(blip, dock.blip.sprite, 1)
            SetBlipScale(blip, dock.blip.scale)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, dock.blip.name)
        else
            print(('^1[jrs_hotair]^0 Dock NPC model failed to load: %s'):format(dock.npcModel))
        end
    end
end)

RegisterCommand('hotair', function()
    local here = GetEntityCoords(PlayerPedId())
    local best, bestAway
    for i, dock in ipairs(Config.Docks) do
        local away = #(here - dock.npcCoords.xyz)
        if not bestAway or away < bestAway then best, bestAway = i, away end
    end
    if best and bestAway < 50.0 then dockMenu(best) else notify(L('title.balloon_hire'), L('info.visit_dock')) end
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    hideHint()
    if owns() then DeleteEntity(hired) hired = nil end
    if riding then
        DetachEntity(PlayerPedId(), true, true)
        riding, ridingSeat, ridingNet = nil, nil, nil
    end
    for _, ped in pairs(dockPeds) do
        if DoesEntityExist(ped) then DeletePed(ped) end
    end
    dockPeds = {}
end)

-- ------------------------------------------------------------------ prompts

CreateThread(function()
    local model = joaat(Config.Model)
    local prompts = JRS.Prompts()
    local pHire = prompts:add(0x760A9C6F, LE('target.hire_balloon'))
    local pPilot = prompts:add(0x760A9C6F, LE('target.pilot_balloon'))
    local pStorage = prompts:add(0xCEFD9220, LE('target.open_storage'))
    local pStore = prompts:add(0xD9D0E1C0, LE('target.store_balloon'), 1500)
    local pBoard = prompts:add(0x760A9C6F, LE('target.board_balloon'))
    local pLeave = prompts:add(0x760A9C6F, LE('target.disembark'))
    local every = { pHire, pPilot, pStorage, pStore, pBoard, pLeave }

    local function pressed(prompt, shown, action)
        if shown[prompt] and prompts:done(prompt) then
            action(shown[prompt])
            Wait(500)
            return true
        end
    end

    while true do
        local wait = 500
        local ped = PlayerPedId()
        local here = GetEntityCoords(ped)
        local onFoot = not IsPedInAnyVehicle(ped, false)
        local shown, title = {}, nil

        if onFoot then
            for i, dock in ipairs(Config.Docks) do
                if #(here - dock.npcCoords.xyz) < 3.0 then shown[pHire], title = i, dock.label end
            end
        end

        if not title and onFoot and owns() and #(here - GetEntityCoords(hired)) < Config.TargetDistance then
            title = LE('title.balloon_hire')
            shown[pStorage] = true
            if calm(hired) then shown[pPilot], shown[pStore] = true, true end
        end

        if not title then
            if riding and DoesEntityExist(riding) then
                shown[pLeave], title = true, LE('title.aboard')
            elseif onFoot then
                local other = GetClosestVehicle(here.x, here.y, here.z, Config.TargetDistance, model, 70)
                if other ~= 0 and other ~= hired and landed(other) then shown[pBoard], title = other, LE('title.balloon_hire') end
            end
        end

        if title then
            wait = 0
            for _, p in ipairs(every) do prompts:visible(p, shown[p] ~= nil) end
            prompts:show(title)

            local _ = pressed(pHire, shown, dockMenu)
                or pressed(pPilot, shown, function() TaskEnterVehicle(ped, hired, -1, -1, 2.0, 1, 0) end)
                or pressed(pStorage, shown, function()
                    local ok, reason = JRS.Await('jrs_hotair:server:openStorage')
                    if not ok then notify(L('title.cannot_open_storage'), reason or L('error.unable_to_open_storage')) end
                end)
                or pressed(pStore, shown, StoreHiredBalloon)
                or pressed(pBoard, shown, board)
                or pressed(pLeave, shown, function() climbOut(false) end)
        end
        Wait(wait)
    end
end)
