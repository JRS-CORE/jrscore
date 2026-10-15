local inRace = false
local raceStarted = false
local playersInRace = {}
local racePoints = {}
local trackCreated = false
local raceBlip = nil
local playerLaps = 0
local totalLaps = 1
local particleHandles = {}
local particleMeta = {}
local raceResults = {}
local currentRaceFinishers = {}
local savedTracks = {}
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local racePrompt = nil
local isGpsActive = false
local isNuiOpen = false
local currentTrackName = nil
local pendingRacePoints = nil
local isCreatingTrack = false
local pendingWinnerPopup = false
local MAX_POINTS = 15
local checkpointIdx = 1
local creationPoints = {}

Citizen.CreateThread(function()
    local str = Locale('prompt_open_menu')
    racePrompt = PromptRegisterBegin()
    PromptSetControlAction(racePrompt, 0xF3830D8E) -- J key
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(racePrompt, str)
    PromptSetEnabled(racePrompt, false)
    PromptSetVisible(racePrompt, false)
    PromptSetHoldMode(racePrompt, true)
    PromptSetGroup(racePrompt, promptGroup)
    PromptRegisterEnd(racePrompt)
end)

local function CreateRaceBlip()
    if raceBlip then RemoveBlip(raceBlip) end
    if racePoints[1] then
        raceBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, racePoints[1].x, racePoints[1].y, racePoints[1].z)
        SetBlipSprite(raceBlip, 1754506823, 1)
        SetBlipScale(raceBlip, 1.0)
        Citizen.InvokeNative(0x9CB1A1623062F402, raceBlip, Locale('blip_start'))
    end
end

local function ClearParticles()
    for _, handle in pairs(particleHandles) do
        if handle and DoesParticleFxLoopedExist(handle) then StopParticleFxLooped(handle, false) end
        particleMeta[handle] = nil
    end
    particleHandles = {}
    particleMeta = {}
end

local function ClearAllRaceVisuals()
    ClearParticles()
    if isGpsActive then ClearGpsMultiRoute() isGpsActive = false end
    if raceBlip then RemoveBlip(raceBlip) raceBlip = nil end
    checkpointIdx = 1
end

local function GetHeadingToFacePlayer(coords)
    if not coords then return 0.0 end
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local dx = pCoords.x - coords.x
    local dy = pCoords.y - coords.y
    local heading = math.deg(math.atan(dx, dy)) -- Lua 5.4 dropped math.atan2; two-arg math.atan replaces it
    if heading < 0 then heading = heading + 360.0 end
    return heading
end

local function ApplyParticleEffect(coords, idx, total)
    if not coords then return end
    local ptfxDict = "scr_net_target_races"
    local ptfxName = "scr_net_target_fire_ring_mp"
    if not HasNamedPtfxAssetLoaded(ptfxDict) then
        RequestNamedPtfxAsset(ptfxDict)
        while not HasNamedPtfxAssetLoaded(ptfxDict) do Wait(0) end
    end
    UseParticleFxAsset(ptfxDict)
    local heading = GetHeadingToFacePlayer(coords)
    local handle = StartParticleFxLoopedAtCoord(ptfxName, coords.x, coords.y, coords.z + 0.35, 0.0, 0.0, heading, 1.8, false, false, false, false)
    if handle and handle ~= 0 then
        -- Color per index: 1=start red, N=finish green, mids gold
        if idx == 1 then
            SetParticleFxLoopedColour(handle, 1.0, 0.22, 0.15, false)
        elseif total and idx == total then
            SetParticleFxLoopedColour(handle, 0.15, 0.85, 0.35, false)
        else
            SetParticleFxLoopedColour(handle, 1.0, 0.88, 0.35, false)
        end
        particleMeta[handle] = { coords = { x = coords.x, y = coords.y, z = coords.z }, heading = heading, idx = idx }
    end
    return handle
end

local function RefreshAllParticles()
    ClearParticles()
    for i, pt in ipairs(racePoints) do
        local h = ApplyParticleEffect(pt, i, #racePoints)
        if h then particleHandles[i] = h end
    end
end

-- Keep particles facing player
Citizen.CreateThread(function()
    while true do
        Wait(150)
        if #particleHandles > 0 then
            for idx, handle in pairs(particleHandles) do
                if handle and DoesParticleFxLoopedExist(handle) and particleMeta[handle] then
                    local meta = particleMeta[handle]
                    local newHeading = GetHeadingToFacePlayer(meta.coords)
                    local diff = math.abs(newHeading - meta.heading)
                    if diff > 180 then diff = 360 - diff end
                    if diff > 7.0 then
                        StopParticleFxLooped(handle, false)
                        particleMeta[handle] = nil
                        Wait(10)
                        local ptfxDict = "scr_net_target_races"
                        local ptfxName = "scr_net_target_fire_ring_mp"
                        if not HasNamedPtfxAssetLoaded(ptfxDict) then
                            RequestNamedPtfxAsset(ptfxDict)
                            while not HasNamedPtfxAssetLoaded(ptfxDict) do Wait(0) end
                        end
                        UseParticleFxAsset(ptfxDict)
                        local newHandle = StartParticleFxLoopedAtCoord(ptfxName, meta.coords.x, meta.coords.y, meta.coords.z + 0.35, 0.0, 0.0, newHeading, 1.8, false, false, false, false)
                        if newHandle and newHandle ~= 0 then
                            if meta.idx == 1 then SetParticleFxLoopedColour(newHandle, 1.0, 0.22, 0.15, false)
                            elseif meta.idx == #racePoints then SetParticleFxLoopedColour(newHandle, 0.15, 0.85, 0.35, false)
                            else SetParticleFxLoopedColour(newHandle, 1.0, 0.88, 0.35, false) end
                            particleHandles[idx] = newHandle
                            particleMeta[newHandle] = { coords = meta.coords, heading = newHeading, idx = meta.idx }
                        else
                            particleHandles[idx] = nil
                        end
                    end
                end
            end
        end
    end
end)

local function SetRaceGPS()
    if not racePoints[1] then return end
    if isGpsActive then ClearGpsMultiRoute() isGpsActive = false end
    StartGpsMultiRoute(0x3D9A8F9E, true, true)
    for _, p in ipairs(racePoints) do
        AddPointToGpsMultiRoute(p.x, p.y, p.z)
    end
    SetGpsMultiRouteRender(true)
    isGpsActive = true
end

local function GetStateForNUI()
    return {
        trackCreated = trackCreated,
        inRace = inRace,
        raceStarted = raceStarted,
        totalLaps = totalLaps,
        savedTracks = savedTracks,
        playersInRace = playersInRace,
        raceResults = raceResults,
        currentRaceFinishers = currentRaceFinishers,
        racePoints = racePoints,
        currentTrackName = currentTrackName,
        pointsCount = racePoints and #racePoints or 0,
        creationCount = creationPoints and #creationPoints or 0,
        isCreating = isCreatingTrack,
        maxPoints = MAX_POINTS,
        lang = (GetLocaleLang and GetLocaleLang() or 'en'),
        strings = (GetLocaleStrings and GetLocaleStrings() or {})
    }
end

local OpenRaceMenuNUI -- defined below (needs the menu actions)

local function CloseRaceMenuNUI()
    isNuiOpen = false
    JRS.CloseMenu()
end

local function UpdateRaceMenuNUI() end

local function ShowToast(data)
    if not data then return end
    local title = data.title or Locale('title')
    local text = data.description or data.desc or ''
    JRS.Notify(text ~= '' and (title .. ': ' .. text) or title, data.duration or 3800)
end

local TrackNotify = ShowToast

RegisterNetEvent('jrs_track:toast', function(data) ShowToast(data) end)

local function ShowWinnersNUI(finishers)
    local data = finishers or currentRaceFinishers
    if not data or #data == 0 then
        local last = raceResults[#raceResults]
        if last and last.finishers then data = last.finishers end
    end
    if not data or #data == 0 then return JRS.Notify(Locale('notify_no_winners')) end
    local elements = {}
    for _, f in ipairs(data) do
        elements[#elements + 1] = { label = ('%s  %s'):format(f.position == 1 and Locale('ui_winner') or Locale('ui_place', f.position), tostring(f.name)),
            value = f.position, desc = Locale('ui_laps_suffix', f.laps or totalLaps) }
    end
    JRS.OpenMenu('jrs_track_winners', Locale('ui_results_title'), Locale('ui_results_sub'), elements, function() end,
        function() if OpenRaceMenuNUI then OpenRaceMenuNUI() end end)
end

Citizen.CreateThread(function()
    while true do
        Wait(0)
        if trackCreated and racePoints[1] and not raceStarted and not isCreatingTrack then
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)
            local startPoint = racePoints[1]
            if not particleHandles[1] then RefreshAllParticles() end
            if Vdist(coords.x, coords.y, coords.z, startPoint.x, startPoint.y, startPoint.z) < 10.0 then
                PromptSetEnabled(racePrompt, true)
                PromptSetVisible(racePrompt, true)
                PromptSetActiveGroupThisFrame(promptGroup, CreateVarString(10, 'LITERAL_STRING', Locale('title')))
                if PromptHasHoldModeCompleted(racePrompt) then OpenRaceMenuNUI() Wait(1000) end
            else
                PromptSetEnabled(racePrompt, false)
                PromptSetVisible(racePrompt, false)
            end
        else
            if not trackCreated and #particleHandles > 0 then ClearParticles() end
            if not trackCreated or isCreatingTrack or raceStarted then
                PromptSetEnabled(racePrompt, false)
                PromptSetVisible(racePrompt, false)
            end
        end
    end
end)

RegisterNetEvent('jrs_track:syncTracks')
AddEventHandler('jrs_track:syncTracks', function(tracks)
    savedTracks = tracks or {}
    if type(savedTracks) ~= 'table' then savedTracks = {} end
    UpdateRaceMenuNUI()
end)

RegisterNetEvent('jrs_track:syncMaxMarkers')
AddEventHandler('jrs_track:syncMaxMarkers', function(count)
    MAX_POINTS = math.max(2, math.min(30, tonumber(count) or 15))
    UpdateRaceMenuNUI()
end)

function LoadTracksFromServer() TriggerServerEvent('jrs_track:requestTracks') end
function OpenRaceMenu() OpenRaceMenuNUI() end
RegisterCommand('racerace', function() OpenRaceMenuNUI() end, false)
RegisterCommand('race', function() OpenRaceMenuNUI() end, false)

-- track name for a freshly built route (was the NUI name dialog)
local function ConfirmCreate(name)
    if pendingRacePoints and name and name:len() > 0 then
        local pts = pendingRacePoints
        pendingRacePoints = nil
        isCreatingTrack = false
        creationPoints = {}
        trackCreated = true
        racePoints = pts
        currentTrackName = name
        TriggerServerEvent('horse_race:trackCreated', racePoints, name)
        CreateRaceBlip()
        SetRaceGPS()
        RefreshAllParticles()
        return true
    end
    if pendingRacePoints then pendingRacePoints = nil racePoints = {} end
    isCreatingTrack = false
    creationPoints = {}
    ClearParticles()
    JRS.Notify(Locale('notify_creation_cancelled'))
    return false
end

local function AskTrackName()
    CreateThread(function()
        local name = JRS.Input(Locale('ui_create'), Locale('notify_track_name_required'))
        if name then name = name:sub(1, 40) end
        if ConfirmCreate(name) then Wait(100) OpenRaceMenuNUI() end
    end)
end

local function TrackListMenu(id, title, sub, emptyLabel, onPick)
    local elements = {}
    for _, t in ipairs(savedTracks or {}) do
        elements[#elements + 1] = { label = tostring(t.name), value = t.track_id or t.id, desc = Locale('ui_load_count', t.points and #t.points or 0) }
    end
    if #elements == 0 then elements[1] = { label = emptyLabel, value = false, desc = '' } end
    JRS.OpenMenu(id, title, sub, elements, function(el, menu)
        if not el.value then return end
        menu.close()
        onPick(el.value, el.label)
    end, function() OpenRaceMenuNUI() end)
end

OpenRaceMenuNUI = function()
    LoadTracksFromServer()
    Wait(200)
    isNuiOpen = true
    local elements = {}
    local function add(value, label, desc) elements[#elements + 1] = { label = label, value = value, desc = desc or '' } end

    if not trackCreated and not isCreatingTrack then add('create', Locale('ui_create'), Locale('ui_create_hint')) end
    add('load', Locale('ui_load'), #savedTracks > 0 and Locale('ui_load_count', #savedTracks) or Locale('ui_load_none'))
    if not inRace and trackCreated and not raceStarted then add('join', Locale('ui_join'), Locale('ui_join_enter')) end
    if inRace and not raceStarted then add('leave', Locale('ui_leave'), Locale('ui_leave_hint')) end
    if trackCreated and not raceStarted then add('start', Locale('ui_start'), Locale('ui_start_hint')) end
    add('laps', Locale('ui_set_laps'), Locale('ui_laps_current', totalLaps))
    add('max', Locale('ui_set_max'), Locale('ui_max_current', MAX_POINTS))
    add('winners', Locale('ui_view_winners'), Locale('ui_winners_card'))
    add('delete', Locale('ui_delete'), Locale('ui_delete_hint'))
    add('reset', Locale('ui_reset'), Locale('ui_reset_hint'))

    JRS.OpenMenu('jrs_track', Locale('title'), currentTrackName or Locale('ui_subtitle'), elements, function(el, menu)
        local v = el.value
        if v == 'create' then menu.close() CreateRaceTrack()
        elseif v == 'load' then
            TrackListMenu('jrs_track_load', Locale('ui_saved_tracks'), Locale('ui_saved_tracks_sub'), Locale('ui_no_tracks'), function(id, name)
                JRS.Notify(Locale('notify_loading_track', name))
                TriggerServerEvent('jrs_track:loadTrack', id)
            end)
        elseif v == 'delete' then
            TrackListMenu('jrs_track_delete', Locale('ui_delete_track'), Locale('ui_delete_track_sub'), Locale('ui_nothing_delete'), function(id, name)
                JRS.Notify(Locale('notify_deletion_requested', name))
                TriggerServerEvent('jrs_track:deleteTrack', id)
            end)
        elseif v == 'join' then menu.close() TriggerServerEvent('jrs_track:joinRace')
        elseif v == 'leave' then menu.close() TriggerServerEvent('jrs_track:leaveRace')
        elseif v == 'start' then menu.close() TriggerServerEvent('jrs_track:startRace')
        elseif v == 'reset' then menu.close() TriggerServerEvent('jrs_track:resetRace')
        elseif v == 'winners' then ShowWinnersNUI()
        elseif v == 'laps' then
            local n = JRS.Input(Locale('ui_set_laps'), '1-5', true)
            if n then TriggerServerEvent('jrs_track:setLaps', math.floor(n)) end
            OpenRaceMenuNUI()
        elseif v == 'max' then
            local n = JRS.Input(Locale('ui_set_max'), '2-30', true)
            if n then TriggerServerEvent('jrs_track:setMaxMarkers', math.floor(n)) end
            OpenRaceMenuNUI()
        end
    end, function() isNuiOpen = false end)
end

function CreateRaceTrack()
    if trackCreated or raceStarted then return end
    if isCreatingTrack then return end

    -- Track creation deliberately keeps the START separate from the
    -- intermediate points.  G places the FINISH at the player's current
    -- position and then builds the final ordered route:
    --   start -> point 1 -> point 2 -> ... -> finish
    racePoints = {}
    pendingRacePoints = nil
    creationPoints = {}
    isCreatingTrack = true
    checkpointIdx = 1
    ClearParticles()

    TrackNotify({
        title = Locale('title'),
        description = Locale('notify_track_setup_instructions'),
        type = 'inform',
        duration = 10000
    })

    Citizen.CreateThread(function()
        local startPoint = nil
        local extraPoints = {}
        local KEY_ADD_POINT = 0xF3830D8E -- J
        local KEY_FINISH = 0x760A9C6F -- G

        while isCreatingTrack do
            Wait(0)

            local coords = GetEntityCoords(PlayerPedId())
            local preview = { x = coords.x, y = coords.y, z = coords.z }
            local heading = GetHeadingToFacePlayer(preview)

            -- Preview marker at the player's current position.
            DrawMarker(
                28,
                coords.x, coords.y, coords.z,
                0, 0, 0,
                0.0, 0.0, heading,
                1.5, 1.5, 1.5,
                255, 200, 60, 150,
                false, true, 2, false, nil, nil, false
            )

            -- Start marker.
            if startPoint then
                DrawMarker(
                    28,
                    startPoint.x, startPoint.y, startPoint.z - 0.9,
                    0, 0, 0,
                    0, 0, 0,
                    1.0, 1.0, 1.0,
                    255, 60, 60, 160,
                    false, true, 2, false, nil, nil, false
                )
            end

            -- Intermediate J points.
            for i, p in ipairs(extraPoints) do
                DrawMarker(
                    28,
                    p.x, p.y, p.z - 0.9,
                    0, 0, 0,
                    0, 0, 0,
                    0.9, 0.9, 0.9,
                    255, 220, 80, 130,
                    false, true, 2, false, nil, nil, false
                )
            end

            -- J:
            --   first press = START only
            --   later presses = intermediate points
            if IsControlJustPressed(0, KEY_ADD_POINT) then
                if not startPoint then
                    startPoint = preview
                    creationPoints = { startPoint }

                    local h = ApplyParticleEffect(startPoint, 1, 2)
                    if h then particleHandles[1] = h end

                    TrackNotify({
                        title = Locale('title'),
                        description = Locale('notify_start_point_placed'),
                        type = 'success'
                    })
                elseif #extraPoints >= (MAX_POINTS - 2) then
                    -- Reserve two slots in the final route for START + FINISH.
                    TrackNotify({
                        title = Locale('title'),
                        description = Locale('notify_max_points', MAX_POINTS),
                        type = 'error'
                    })
                else
                    local point = preview
                    table.insert(extraPoints, point)

                    -- creationPoints contains start + intermediate points.
                    creationPoints = { startPoint }
                    for _, p in ipairs(extraPoints) do
                        table.insert(creationPoints, p)
                    end

                    if isNuiOpen then
                        UpdateRaceMenuNUI()
                    end

                    local h = ApplyParticleEffect(
                        point,
                        #extraPoints + 1,
                        math.max(#extraPoints + 2, 2)
                    )
                    if h then particleHandles[#extraPoints + 1] = h end

                    TrackNotify({
                        title = Locale('title'),
                        description = Locale('notify_point_added', #extraPoints + 1),
                        type = 'inform'
                    })
                end
            end

            -- G:
            -- Capture the player's CURRENT position as the finish.
            if IsControlJustPressed(0, KEY_FINISH) then
                if not startPoint then
                    TrackNotify({
                        title = Locale('title'),
                        description = Locale('notify_need_start_first'),
                        type = 'error'
                    })
                else
                    -- Final route always contains:
                    -- START + any intermediate J points + FINISH.
                    local finalPoints = { startPoint }

                    for _, p in ipairs(extraPoints) do
                        table.insert(finalPoints, p)
                    end

                    local finishPoint = preview
                    table.insert(finalPoints, finishPoint)

                    if #finalPoints < 2 then
                        TrackNotify({
                            title = Locale('title'),
                            description = Locale('notify_need_start_and_finish'),
                            type = 'error'
                        })
                    else
                        pendingRacePoints = finalPoints
                        creationPoints = finalPoints

                        -- Finish marker is green.
                        local finishIndex = #finalPoints
                        local h = ApplyParticleEffect(
                            finishPoint,
                            finishIndex,
                            finishIndex
                        )
                        if h then particleHandles[finishIndex] = h end

                        AskTrackName()

                        return
                    end
                end
            end
        end
    end)
end

RegisterNetEvent('jrs_track:syncTrack')
AddEventHandler('jrs_track:syncTrack', function(points, created)
    racePoints = points or {}
    trackCreated = created
    if created and racePoints[1] and racePoints[2] then
        -- Find name by comparing encoded points (handles N)
        for _, t in ipairs(savedTracks) do
            if t.points and #t.points == #racePoints and t.points[1].x == racePoints[1].x and t.points[#t.points].x == racePoints[#racePoints].x then
                local match = true
                for i=1,#t.points do if t.points[i].x ~= racePoints[i].x or t.points[i].y ~= racePoints[i].y then match=false break end end
                if match then currentTrackName = t.name break end
            end
        end
        if not currentTrackName then currentTrackName = Locale('active_track_pts', #racePoints) end
        CreateRaceBlip()
        SetRaceGPS()
        RefreshAllParticles()
        checkpointIdx = 1
    else
        if raceBlip then RemoveBlip(raceBlip) raceBlip = nil end
        if isGpsActive then ClearGpsMultiRoute() isGpsActive = false end
        currentTrackName = nil
        ClearParticles()
        checkpointIdx = 1
    end
    UpdateRaceMenuNUI()
end)

local function StartRaceCountdown()
    Citizen.CreateThread(function()
        local timer = 10
        local container = DatabindingAddDataContainerFromPath("", "MPCountdown")
        local dataString = DatabindingAddDataString(container, "Timer", tostring(timer))
        local dataBoolean = DatabindingAddDataBool(container, "showTimer", true)
        for i = timer, 1, -1 do
            DatabindingWriteDataString(dataString, tostring(i))
            Citizen.Wait(1000)
        end
        if UiStateMachineExists(190275865) then UiStateMachineDestroy(190275865) end
        if DatabindingIsEntryValid(dataString) then DatabindingRemoveDataEntry(dataString) end
        if DatabindingIsEntryValid(dataBoolean) then DatabindingWriteDataBool(dataBoolean, false) DatabindingRemoveDataEntry(dataBoolean) end
        if DatabindingIsEntryValid(container) then DatabindingRemoveDataEntry(container) end
        TrackNotify({title = Locale('title'), description = Locale('notify_go'), type = 'success'})
        TriggerServerEvent('horse_race:countdownFinished')
    end)
end

Citizen.CreateThread(function()
    local lastCheckpointTime = 0
    local minCheckpointDelay = 1200
    while true do
        Wait(100)
        if raceStarted and inRace and racePoints[1] then
            local coords = GetEntityCoords(PlayerPedId())
            local currentTime = GetGameTimer()
            local n = #racePoints
            if n >= 2 then
                -- Ensure particles for all points during race
                for i=1,n do if not particleHandles[i] then local h=ApplyParticleEffect(racePoints[i], i, n) if h then particleHandles[i]=h end end end
                if not isGpsActive then SetRaceGPS() end
                -- Initialize checkpoint if needed
                if checkpointIdx <1 or checkpointIdx > n then checkpointIdx=1 end
                local target = racePoints[checkpointIdx]
                local dist = Vdist(coords.x, coords.y, coords.z, target.x, target.y, target.z)
                if dist < 6.0 and (currentTime - lastCheckpointTime) > minCheckpointDelay then
                    lastCheckpointTime = currentTime
                    local isFinish = checkpointIdx == n
                    local isStart = checkpointIdx == 1
                    if isFinish then
                        playerLaps = playerLaps + 1
                        if playerLaps >= totalLaps then
                            TrackNotify({title=Locale('title'), description=Locale('notify_race_finished_self', playerLaps, totalLaps), type='success'})
                            pendingWinnerPopup = true
                            TriggerServerEvent('horse_race:finishRace', playerLaps)
                            inRace=false playerLaps=0 checkpointIdx=1
                            if isGpsActive then ClearGpsMultiRoute() isGpsActive=false end
                        else
                            checkpointIdx = 1
                        end
                    else
                        -- Notify the rider whenever a checkpoint is successfully hit.
                        -- Checkpoint 1 is the start gate; subsequent points are the
                        -- intermediate checkpoints. Keep the notification lightweight
                        -- so it does not interfere with the race.
                        local hitPoint = checkpointIdx
                        checkpointIdx = checkpointIdx + 1
                        TrackNotify({
                            title = Locale('title'),
                            description = Locale('notify_checkpoint_progress', hitPoint, n, checkpointIdx),
                            type = 'success',
                            duration = 2200
                        })
                    end
                end
            end
        else
            -- Reset checkpoint when not racing
            if not inRace then checkpointIdx = 1 playerLaps=0 end
            if not trackCreated then
                if isGpsActive then ClearGpsMultiRoute() isGpsActive=false end
            end
        end
    end
end)

RegisterNetEvent('jrs_track:syncLaps')
AddEventHandler('jrs_track:syncLaps', function(laps) totalLaps=laps UpdateRaceMenuNUI() end)
RegisterNetEvent('jrs_track:updatePlayers')
AddEventHandler('jrs_track:updatePlayers', function(playerList, started)
    -- The server sends a clean array of real race participants. Keep the
    -- client state in that form so NUI never has to interpret Lua table keys.
    playersInRace = type(playerList) == 'table' and playerList or {}
    raceStarted = started == true
    if raceStarted and isNuiOpen then CloseRaceMenuNUI() end
    UpdateRaceMenuNUI()
end)
RegisterNetEvent('jrs_track:joinedRace')
AddEventHandler('jrs_track:joinedRace', function() inRace=true playerLaps=0 checkpointIdx=1 UpdateRaceMenuNUI() end)
RegisterNetEvent('jrs_track:leftRace')
AddEventHandler('jrs_track:leftRace', function() inRace=false playerLaps=0 checkpointIdx=1 pendingWinnerPopup=false UpdateRaceMenuNUI() end)
RegisterNetEvent('jrs_track:startRace')
AddEventHandler('jrs_track:startRace', function() if isNuiOpen then CloseRaceMenuNUI() end if inRace then StartRaceCountdown() end end)
RegisterNetEvent('jrs_track:raceStarted')
AddEventHandler('jrs_track:raceStarted', function() raceStarted=true if isNuiOpen then CloseRaceMenuNUI() end UpdateRaceMenuNUI() end)
RegisterNetEvent('jrs_track:finishRace')
AddEventHandler('jrs_track:finishRace', function() raceStarted=false inRace=false playerLaps=0 ClearAllRaceVisuals() UpdateRaceMenuNUI() end)
RegisterNetEvent('jrs_track:rewardReceived')
AddEventHandler('jrs_track:rewardReceived', function(amount) TrackNotify({title=Locale('title'), description=Locale('notify_reward', amount), type='success'}) end)
RegisterNetEvent('jrs_track:showFinisherNotification')
AddEventHandler('jrs_track:showFinisherNotification', function(name, pos) TrackNotify({title=Locale('title'), description=Locale('notify_finisher', name, pos), type='inform'}) end)
RegisterNetEvent('jrs_track:syncResults')
AddEventHandler('jrs_track:syncResults', function(finishers)
    currentRaceFinishers=finishers or {}
    UpdateRaceMenuNUI()
    if pendingWinnerPopup and #currentRaceFinishers>0 then
        pendingWinnerPopup=false
        Citizen.CreateThread(function() Wait(450) if #currentRaceFinishers>0 then ShowWinnersNUI(currentRaceFinishers) end end)
    elseif inRace and #currentRaceFinishers>0 and not pendingWinnerPopup then
        -- Winner finished but we missed a checkpoint - clear all markers anyway
        ClearAllRaceVisuals()
        inRace=false
        playerLaps=0
        checkpointIdx=1
        ShowToast({title=Locale('title'), description=Locale('notify_finished_missed_checkpoint'), type='inform', duration=5000})
    end
end)
RegisterNetEvent('jrs_track:syncRaceResults')
AddEventHandler('jrs_track:syncRaceResults', function(results) raceResults=results or {} UpdateRaceMenuNUI() end)
RegisterNetEvent('jrs_track:resetRace')
AddEventHandler('jrs_track:resetRace', function(manual)
    racePoints={} inRace=false raceStarted=false playersInRace={} trackCreated=false playerLaps=0 totalLaps=1 currentTrackName=nil pendingRacePoints=nil creationPoints={} isCreatingTrack=false pendingWinnerPopup=false checkpointIdx=1
    if manual then raceResults={} currentRaceFinishers={} end
    ClearAllRaceVisuals()
    UpdateRaceMenuNUI()
end)
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName()==resourceName then
        if racePrompt then PromptDelete(racePrompt) end
        ClearParticles()
        if isGpsActive then ClearGpsMultiRoute() isGpsActive=false end
        if raceBlip then RemoveBlip(raceBlip) end
        if isNuiOpen then SetNuiFocus(false,false) end
    end
end)
-- Block ESC while the NUI menu is open so it can't be used to bypass the
-- close/cancel NUI callbacks and leave focus stuck on the UI.
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if isNuiOpen then DisableControlAction(0, 0x1B0000, true) end
    end
end)
