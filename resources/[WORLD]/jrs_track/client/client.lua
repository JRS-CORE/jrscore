-- jrs_track | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_track | client
-- Horse races: build a route of checkpoints (J = start and in-between points, G = finish), save it, join a
-- race and ride through the checkpoints. The server keeps the race, the track list and the results; this file
-- draws the fire rings, the GPS and the start blip and sends what the rider did.

local race = {
    points = {},             -- the route in use: start, checkpoints, finish
    track = false,           -- a route is set
    name = nil,              -- its name
    laps = 1, lapsDone = 0, checkpoint = 1,
    joined = false, started = false,
    riders = {}, finishers = {}, results = {}, saved = {},
    maxPoints = 15,
    building = false, pending = nil,          -- route being built / waiting for its name
    winnerPopup = false,
}

local menuOpen = false
local gps = false
local startBlip
local rings, ringMeta = {}, {}                -- index -> handle, handle -> { coords, heading, idx }
local group = GetRandomIntInRange(0, 0xffffff)
local prompt

local J_KEY <const>, G_KEY <const> = 0xF3830D8E, 0x760A9C6F
local RING = { dict = 'scr_net_target_races', name = 'scr_net_target_fire_ring_mp' }

-- ------------------------------------------------------------------ messages

local function toast(data)
    if not data then return end
    local title = data.title or Locale('title')
    local text = data.description or data.desc or ''
    JRS.Notify(text ~= '' and (title .. ': ' .. text) or title, data.duration or 3800)
end

local function say(key, ...) toast({ description = Locale(key, ...) }) end

RegisterNetEvent('jrs_track:toast', toast)

-- ------------------------------------------------------------------ the fire rings

local function headingTo(at)
    if not at then return 0.0 end
    local me = GetEntityCoords(PlayerPedId())
    local h = math.deg(math.atan(me.x - at.x, me.y - at.y))
    return h < 0 and h + 360.0 or h
end

local function ringColour(handle, index, total)
    if index == 1 then SetParticleFxLoopedColour(handle, 1.0, 0.22, 0.15, false)           -- start: red
    elseif total and index == total then SetParticleFxLoopedColour(handle, 0.15, 0.85, 0.35, false)   -- finish: green
    else SetParticleFxLoopedColour(handle, 1.0, 0.88, 0.35, false) end                       -- between: gold
end

local function loadRing()
    if HasNamedPtfxAssetLoaded(RING.dict) then return end
    RequestNamedPtfxAsset(RING.dict)
    while not HasNamedPtfxAssetLoaded(RING.dict) do Wait(0) end
end

local function startRing(at, heading)
    loadRing()
    UseParticleFxAsset(RING.dict)
    return StartParticleFxLoopedAtCoord(RING.name, at.x, at.y, at.z + 0.35, 0.0, 0.0, heading, 1.8, false, false, false, false)
end

local function putRing(at, index, total)
    if not at then return end
    local heading = headingTo(at)
    local handle = startRing(at, heading)
    if handle and handle ~= 0 then
        ringColour(handle, index, total)
        ringMeta[handle] = { coords = { x = at.x, y = at.y, z = at.z }, heading = heading, idx = index }
        return handle
    end
end

local function clearRings()
    for _, handle in pairs(rings) do
        if handle and DoesParticleFxLoopedExist(handle) then StopParticleFxLooped(handle, false) end
    end
    rings, ringMeta = {}, {}
end

local function showRings()
    clearRings()
    for i, p in ipairs(race.points) do
        local handle = putRing(p, i, #race.points)
        if handle then rings[i] = handle end
    end
end

-- rings are flat discs: turn them towards the rider when the angle is off by more than 7 degrees
CreateThread(function()
    while true do
        Wait(150)
        for index, handle in pairs(rings) do
            local meta = handle and DoesParticleFxLoopedExist(handle) and ringMeta[handle]
            if meta then
                local heading = headingTo(meta.coords)
                local off = math.abs(heading - meta.heading)
                if off > 180 then off = 360 - off end
                if off > 7.0 then
                    StopParticleFxLooped(handle, false)
                    ringMeta[handle] = nil
                    Wait(10)
                    local fresh = startRing(meta.coords, heading)
                    if fresh and fresh ~= 0 then
                        ringColour(fresh, meta.idx, #race.points)
                        rings[index] = fresh
                        ringMeta[fresh] = { coords = meta.coords, heading = heading, idx = meta.idx }
                    else
                        rings[index] = nil
                    end
                end
            end
        end
    end
end)

-- ------------------------------------------------------------------ route on the map

local function dropGps()
    if gps then ClearGpsMultiRoute() gps = false end
end

local function showGps()
    if not race.points[1] then return end
    dropGps()
    StartGpsMultiRoute(0x3D9A8F9E, true, true)
    for _, p in ipairs(race.points) do AddPointToGpsMultiRoute(p.x, p.y, p.z) end
    SetGpsMultiRouteRender(true)
    gps = true
end

local function showStartBlip()
    if startBlip then RemoveBlip(startBlip) end
    local first = race.points[1]
    if not first then return end
    startBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, first.x, first.y, first.z)
    SetBlipSprite(startBlip, 1754506823, 1)
    SetBlipScale(startBlip, 1.0)
    Citizen.InvokeNative(0x9CB1A1623062F402, startBlip, Locale('blip_start'))
end

local function clearVisuals()
    clearRings()
    dropGps()
    if startBlip then RemoveBlip(startBlip) startBlip = nil end
    race.checkpoint = 1
end

-- ------------------------------------------------------------------ the open prompt at the start

CreateThread(function()
    prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, J_KEY)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', Locale('prompt_open_menu')))
    PromptSetEnabled(prompt, false)
    PromptSetVisible(prompt, false)
    PromptSetHoldMode(prompt, true)
    PromptSetGroup(prompt, group)
    PromptRegisterEnd(prompt)
end)

local function showPrompt(on)
    PromptSetEnabled(prompt, on)
    PromptSetVisible(prompt, on)
end

local OpenMenu            -- defined with the menus below

CreateThread(function()
    while true do
        Wait(0)
        local ready = race.track and race.points[1] and not race.started and not race.building
        if ready then
            if not rings[1] then showRings() end
            local here, first = GetEntityCoords(PlayerPedId()), race.points[1]
            if #(here - vector3(first.x, first.y, first.z)) < 10.0 then
                showPrompt(true)
                PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', Locale('title')))
                if PromptHasHoldModeCompleted(prompt) then OpenMenu() Wait(1000) end
            else
                showPrompt(false)
            end
        else
            if not race.track and next(rings) then clearRings() end
            if not race.track or race.building or race.started then showPrompt(false) end
        end
    end
end)

-- ------------------------------------------------------------------ results menu

local function showWinners(list)
    local data = list or race.finishers
    if not data or #data == 0 then
        local last = race.results[#race.results]
        data = last and last.finishers or {}
    end
    if #data == 0 then return JRS.Notify(Locale('notify_no_winners')) end

    local rows = {}
    for _, f in ipairs(data) do
        rows[#rows + 1] = {
            label = ('%s  %s'):format(f.position == 1 and Locale('ui_winner') or Locale('ui_place', f.position), tostring(f.name)),
            value = f.position, desc = Locale('ui_laps_suffix', f.laps or race.laps),
        }
    end
    JRS.OpenMenu('jrs_track_winners', Locale('ui_results_title'), Locale('ui_results_sub'), rows, function() end, function() OpenMenu() end)
end

-- ------------------------------------------------------------------ building a route

local function nameAndSave()
    CreateThread(function()
        local name = JRS.Input(Locale('ui_create'), Locale('notify_track_name_required'))
        if name then name = name:sub(1, 40) end

        local points = race.pending
        if points and name and name:len() > 0 then
            race.pending, race.building, race.track, race.points, race.name = nil, false, true, points, name
            TriggerServerEvent('horse_race:trackCreated', points, name)
            showStartBlip()
            showGps()
            showRings()
            Wait(100)
            OpenMenu()
        else
            if points then race.pending, race.points = nil, {} end
            race.building = false
            clearRings()
            JRS.Notify(Locale('notify_creation_cancelled'))
        end
    end)
end

local function drawPost(at, lift, size, r, g, b, a)
    DrawMarker(28, at.x, at.y, at.z - lift, 0, 0, 0, 0, 0, 0, size, size, size, r, g, b, a, false, true, 2, false, nil, nil, false)
end

local function buildRoute()
    if race.track or race.started or race.building then return end
    race.points, race.pending, race.building, race.checkpoint = {}, nil, true, 1
    clearRings()
    toast({ description = Locale('notify_track_setup_instructions'), duration = 10000 })

    CreateThread(function()
        local start
        local between = {}

        while race.building do
            Wait(0)
            local me = GetEntityCoords(PlayerPedId())
            local here = { x = me.x, y = me.y, z = me.z }

            -- the preview follows the rider, the placed posts stay
            DrawMarker(28, me.x, me.y, me.z, 0, 0, 0, 0.0, 0.0, headingTo(here), 1.5, 1.5, 1.5, 255, 200, 60, 150, false, true, 2, false, nil, nil, false)
            if start then drawPost(start, 0.9, 1.0, 255, 60, 60, 160) end
            for _, p in ipairs(between) do drawPost(p, 0.9, 0.9, 255, 220, 80, 130) end

            -- J: the first press is the start, later presses add points (two slots stay free for start and finish)
            if IsControlJustPressed(0, J_KEY) then
                if not start then
                    start = here
                    local handle = putRing(start, 1, 2)
                    if handle then rings[1] = handle end
                    toast({ description = Locale('notify_start_point_placed') })
                elseif #between >= race.maxPoints - 2 then
                    toast({ description = Locale('notify_max_points', race.maxPoints) })
                else
                    between[#between + 1] = here
                    local handle = putRing(here, #between + 1, math.max(#between + 2, 2))
                    if handle then rings[#between + 1] = handle end
                    toast({ description = Locale('notify_point_added', #between + 1) })
                end
            end

            -- G: the finish is where the rider stands; the route is start, the points in order, finish
            if IsControlJustPressed(0, G_KEY) then
                if not start then
                    toast({ description = Locale('notify_need_start_first') })
                else
                    local route = { start }
                    for _, p in ipairs(between) do route[#route + 1] = p end
                    route[#route + 1] = here

                    race.pending = route
                    local handle = putRing(here, #route, #route)
                    if handle then rings[#route] = handle end
                    nameAndSave()
                    return
                end
            end
        end
    end)
end

-- ------------------------------------------------------------------ the menu

local function pickTrack(id, title, sub, empty, onPick)
    local rows = {}
    for _, t in ipairs(race.saved) do
        rows[#rows + 1] = { label = tostring(t.name), value = t.track_id or t.id, desc = Locale('ui_load_count', t.points and #t.points or 0) }
    end
    if #rows == 0 then rows[1] = { label = empty, value = false, desc = '' } end

    JRS.OpenMenu(id, title, sub, rows, function(row, menu)
        if not row.value then return end
        menu.close()
        onPick(row.value, row.label)
    end, function() OpenMenu() end)
end

local function askNumber(titleKey, hint, event)
    local n = JRS.Input(Locale(titleKey), hint, true)
    if n then TriggerServerEvent(event, math.floor(n)) end
    OpenMenu()
end

OpenMenu = function()
    TriggerServerEvent('jrs_track:requestTracks')
    Wait(200)
    menuOpen = true

    local rows = {}
    local function row(value, label, desc) rows[#rows + 1] = { label = label, value = value, desc = desc or '' } end

    if not race.track and not race.building then row('create', Locale('ui_create'), Locale('ui_create_hint')) end
    row('load', Locale('ui_load'), #race.saved > 0 and Locale('ui_load_count', #race.saved) or Locale('ui_load_none'))
    if not race.joined and race.track and not race.started then row('join', Locale('ui_join'), Locale('ui_join_enter')) end
    if race.joined and not race.started then row('leave', Locale('ui_leave'), Locale('ui_leave_hint')) end
    if race.track and not race.started then row('start', Locale('ui_start'), Locale('ui_start_hint')) end
    row('laps', Locale('ui_set_laps'), Locale('ui_laps_current', race.laps))
    row('max', Locale('ui_set_max'), Locale('ui_max_current', race.maxPoints))
    row('winners', Locale('ui_view_winners'), Locale('ui_winners_card'))
    row('delete', Locale('ui_delete'), Locale('ui_delete_hint'))
    row('reset', Locale('ui_reset'), Locale('ui_reset_hint'))

    local simple = { join = 'jrs_track:joinRace', leave = 'jrs_track:leaveRace', start = 'jrs_track:startRace', reset = 'jrs_track:resetRace' }

    JRS.OpenMenu('jrs_track', Locale('title'), race.name or Locale('ui_subtitle'), rows, function(picked, menu)
        local v = picked.value
        if v == 'create' then
            menu.close()
            buildRoute()
        elseif v == 'load' then
            pickTrack('jrs_track_load', Locale('ui_saved_tracks'), Locale('ui_saved_tracks_sub'), Locale('ui_no_tracks'), function(id, name)
                JRS.Notify(Locale('notify_loading_track', name))
                TriggerServerEvent('jrs_track:loadTrack', id)
            end)
        elseif v == 'delete' then
            pickTrack('jrs_track_delete', Locale('ui_delete_track'), Locale('ui_delete_track_sub'), Locale('ui_nothing_delete'), function(id, name)
                JRS.Notify(Locale('notify_deletion_requested', name))
                TriggerServerEvent('jrs_track:deleteTrack', id)
            end)
        elseif simple[v] then
            menu.close()
            TriggerServerEvent(simple[v])
        elseif v == 'winners' then
            showWinners()
        elseif v == 'laps' then
            askNumber('ui_set_laps', '1-5', 'jrs_track:setLaps')
        elseif v == 'max' then
            askNumber('ui_set_max', '2-30', 'jrs_track:setMaxMarkers')
        end
    end, function() menuOpen = false end)
end

local function closeMenu()
    menuOpen = false
    JRS.CloseMenu()
end

function OpenRaceMenu() OpenMenu() end
function LoadTracksFromServer() TriggerServerEvent('jrs_track:requestTracks') end
RegisterCommand('racerace', function() OpenMenu() end, false)
RegisterCommand('race', function() OpenMenu() end, false)

-- ------------------------------------------------------------------ the countdown

local function countdown()
    CreateThread(function()
        local container = DatabindingAddDataContainerFromPath('', 'MPCountdown')
        local text = DatabindingAddDataString(container, 'Timer', '10')
        local shown = DatabindingAddDataBool(container, 'showTimer', true)
        for n = 10, 1, -1 do
            DatabindingWriteDataString(text, tostring(n))
            Wait(1000)
        end
        if UiStateMachineExists(190275865) then UiStateMachineDestroy(190275865) end
        if DatabindingIsEntryValid(text) then DatabindingRemoveDataEntry(text) end
        if DatabindingIsEntryValid(shown) then
            DatabindingWriteDataBool(shown, false)
            DatabindingRemoveDataEntry(shown)
        end
        if DatabindingIsEntryValid(container) then DatabindingRemoveDataEntry(container) end
        toast({ description = Locale('notify_go') })
        TriggerServerEvent('horse_race:countdownFinished')
    end)
end

-- ------------------------------------------------------------------ riding through the checkpoints

local function passedFinish(count)
    race.lapsDone = race.lapsDone + 1
    if race.lapsDone < race.laps then
        race.checkpoint = 1
        return
    end
    toast({ description = Locale('notify_race_finished_self', race.lapsDone, race.laps) })
    race.winnerPopup = true
    TriggerServerEvent('horse_race:finishRace', race.lapsDone)
    race.joined, race.lapsDone, race.checkpoint = false, 0, 1
    dropGps()
end

CreateThread(function()
    local lastHit, gap = 0, 1200
    while true do
        Wait(100)
        local count = #race.points
        if race.started and race.joined and race.points[1] and count >= 2 then
            for i = 1, count do
                if not rings[i] then
                    local handle = putRing(race.points[i], i, count)
                    if handle then rings[i] = handle end
                end
            end
            if not gps then showGps() end
            if race.checkpoint < 1 or race.checkpoint > count then race.checkpoint = 1 end

            local target, here, now = race.points[race.checkpoint], GetEntityCoords(PlayerPedId()), GetGameTimer()
            if #(here - vector3(target.x, target.y, target.z)) < 6.0 and now - lastHit > gap then
                lastHit = now
                if race.checkpoint == count then
                    passedFinish(count)
                else
                    local hit = race.checkpoint
                    race.checkpoint = race.checkpoint + 1
                    toast({ description = Locale('notify_checkpoint_progress', hit, count, race.checkpoint), duration = 2200 })
                end
            end
        else
            if not race.joined then race.checkpoint, race.lapsDone = 1, 0 end
            if not race.track then dropGps() end
        end
    end
end)

-- ------------------------------------------------------------------ what the server tells us

RegisterNetEvent('jrs_track:syncTracks', function(tracks)
    race.saved = type(tracks) == 'table' and tracks or {}
end)

RegisterNetEvent('jrs_track:syncMaxMarkers', function(count)
    race.maxPoints = math.max(2, math.min(30, tonumber(count) or 15))
end)

-- the name of a route we are given: look it up among the saved ones by comparing the points
local function nameOfRoute(points)
    for _, t in ipairs(race.saved) do
        local tp = t.points
        if tp and #tp == #points then
            local same = true
            for i = 1, #tp do
                if tp[i].x ~= points[i].x or tp[i].y ~= points[i].y then same = false break end
            end
            if same then return t.name end
        end
    end
end

RegisterNetEvent('jrs_track:syncTrack', function(points, created)
    race.points, race.track = points or {}, created
    if created and race.points[1] and race.points[2] then
        race.name = nameOfRoute(race.points) or race.name or Locale('active_track_pts', #race.points)
        showStartBlip()
        showGps()
        showRings()
    else
        if startBlip then RemoveBlip(startBlip) startBlip = nil end
        dropGps()
        race.name = nil
        clearRings()
    end
    race.checkpoint = 1
end)

RegisterNetEvent('jrs_track:syncLaps', function(laps) race.laps = laps end)

RegisterNetEvent('jrs_track:updatePlayers', function(list, started)
    race.riders = type(list) == 'table' and list or {}
    race.started = started == true
    if race.started and menuOpen then closeMenu() end
end)

RegisterNetEvent('jrs_track:joinedRace', function() race.joined, race.lapsDone, race.checkpoint = true, 0, 1 end)
RegisterNetEvent('jrs_track:leftRace', function() race.joined, race.lapsDone, race.checkpoint, race.winnerPopup = false, 0, 1, false end)

RegisterNetEvent('jrs_track:startRace', function()
    if menuOpen then closeMenu() end
    if race.joined then countdown() end
end)

RegisterNetEvent('jrs_track:raceStarted', function()
    race.started = true
    if menuOpen then closeMenu() end
end)

RegisterNetEvent('jrs_track:finishRace', function()
    race.started, race.joined, race.lapsDone = false, false, 0
    clearVisuals()
end)

RegisterNetEvent('jrs_track:rewardReceived', function(amount) toast({ description = Locale('notify_reward', amount) }) end)
RegisterNetEvent('jrs_track:showFinisherNotification', function(name, place) toast({ description = Locale('notify_finisher', name, place) }) end)

RegisterNetEvent('jrs_track:syncResults', function(finishers)
    race.finishers = finishers or {}
    if race.winnerPopup and #race.finishers > 0 then
        race.winnerPopup = false
        CreateThread(function()
            Wait(450)
            if #race.finishers > 0 then showWinners(race.finishers) end
        end)
    elseif race.joined and #race.finishers > 0 then
        -- somebody won while we skipped a checkpoint: clear everything
        clearVisuals()
        race.joined, race.lapsDone = false, 0
        toast({ description = Locale('notify_finished_missed_checkpoint'), duration = 5000 })
    end
end)

RegisterNetEvent('jrs_track:syncRaceResults', function(results) race.results = results or {} end)

RegisterNetEvent('jrs_track:resetRace', function(manual)
    race.points, race.joined, race.started, race.riders, race.track = {}, false, false, {}, false
    race.lapsDone, race.laps, race.name, race.pending, race.building, race.winnerPopup = 0, 1, nil, nil, false, false
    if manual then race.results, race.finishers = {}, {} end
    clearVisuals()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if prompt then PromptDelete(prompt) end
    clearVisuals()
    if menuOpen then SetNuiFocus(false, false) end
end)

-- ESC would skip the menu's own close handling and leave the focus stuck
CreateThread(function()
    while true do
        Wait(0)
        if menuOpen then DisableControlAction(0, 0x1B0000, true) end
    end
end)
