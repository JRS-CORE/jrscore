local Mission = {
    active = false,
    stage = 'idle',
    hub = nil,
    catchZone = nil,
    delivery = nil,
    wagon = nil,
    wagonTrap = nil,
    wagonTraps = {},
    chickens = {},
    chickenBlips = {},
    wagonChickens = {},
    carriedChicken = nil,
    carriedChickenDead = false,
    tableChicken = nil,
    groundDeadChicken = nil,
    tableDead = false,
    caught = 0,
    processed = 0,
    chestProp = nil,
    chestOnWagon = false,
    carryingChest = false,
    objectiveBlip = nil,
    wagonBlip = nil,
    testMode = false,
}

local HubNPCs = {}
local HubBlips = {}
local CutStationObjects = {}
local StartPrompt = nil
local InteractPrompt = nil
local CurrentJob = nil
local lastJobWarn = 0

local function normalizeJob(job)
    if not job then return 'unemployed' end
    if type(job) == 'table' then
        job = job.job or job.name or 'unemployed'
    end
    local s = tostring(job or 'unemployed'):match('^%s*(.-)%s*$')
    return string.lower(s or 'unemployed')
end

local function getPlayerJob()
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.Job then
        local st = normalizeJob(LocalPlayer.state.Job)
        if st ~= '' and st ~= 'unemployed' then
            return st
        end
    end
    if CurrentJob and CurrentJob ~= '' then
        return normalizeJob(CurrentJob)
    end
    return 'unemployed'
end

local function hasRequiredJob()
    if not Config.JobCheck or not Config.JobCheck.enabled then return true end
    local req = normalizeJob(Config.JobCheck.job or 'chicken')
    return getPlayerJob() == req
end

local function dbg(msg)
    if Config.Debug then print('[jrs_chicken_job] ' .. tostring(msg)) end
end

local function hash(v)
    if type(v) == 'number' then return v end
    return GetHashKey(v)
end

local function requestModel(model)
    local h = hash(model)
    RequestModel(h)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(h) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(h), h
end

local function notify(msg, duration)
    -- jrs_core notification API: text + duration.
    -- The old jrs_core:client:notify call used by v1.1 is not part of the current core API
    -- and can throw a native exception in the core notification handler.
    duration = tonumber(duration) or 5000
    local core = (Config.Integration and Config.Integration.coreResource) or 'jrs_core'
    if GetResourceState(core) == 'started' then
        TriggerEvent('jrs_core:sendRightTipNotification', tostring(msg), duration)
    elseif Config.Debug then
        print('[jrs_chicken_job] NOTIFY: ' .. tostring(msg))
    end
end

local function sanitizePromptText(text)
    if not text then return 'Interact' end
    text = tostring(text)
    for i = 1, #text do
        if text:byte(i) > 127 then
            if Config.Prompts then
                for k, v in pairs(Config.Text or {}) do
                    if v == text and Config.Prompts[k] then
                        return Config.Prompts[k]
                    end
                end
                for k, v in pairs(Config.Texts and Config.Texts['ar'] or {}) do
                    if v == text and Config.Prompts[k] then
                        return Config.Prompts[k]
                    end
                end
            end
            return 'Interact'
        end
    end
    return text
end

local function promptCreate(label)
    local p = PromptRegisterBegin()
    PromptSetControlAction(p, Config.Keys.interact)
    PromptSetText(p, CreateVarString(10, 'LITERAL_STRING', sanitizePromptText(label)))
    PromptSetEnabled(p, true)
    PromptSetVisible(p, true)
    PromptSetStandardMode(p, true)
    PromptRegisterEnd(p)
    return p
end

local function promptShow(prompt, label, enabled)
    if not prompt then return end
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', sanitizePromptText(label)))
    PromptSetEnabled(prompt, enabled)
    PromptSetVisible(prompt, enabled)
end

local function promptDeleteSafe(prompt)
    if not prompt then return nil end
    pcall(function() PromptSetEnabled(prompt, false) end)
    pcall(function() PromptSetVisible(prompt, false) end)
    pcall(function() PromptDelete(prompt) end)
    return nil
end

local function hideAllPrompts()
    if StartPrompt then
        pcall(function() PromptSetEnabled(StartPrompt, false) end)
        pcall(function() PromptSetVisible(StartPrompt, false) end)
    end
    if InteractPrompt then
        pcall(function() PromptSetEnabled(InteractPrompt, false) end)
        pcall(function() PromptSetVisible(InteractPrompt, false) end)
    end
end

local function pressed(prompt)
    -- Some RedM builds do not reliably report PromptHasStandardModeCompleted
    -- for dynamically shown prompts. Accept the real G control directly too.
    if prompt and PromptHasStandardModeCompleted(prompt) then return true end
    return IsControlJustReleased(0, Config.Keys.interact) or IsDisabledControlJustReleased(0, Config.Keys.interact)
end

local function dist(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end


local function offsetFromHeading(base, heading, x, y, z)
    local r = math.rad(heading or 0.0)
    local c, sn = math.cos(r), math.sin(r)
    return vector3(
        base.x + (x or 0.0) * c - (y or 0.0) * sn,
        base.y + (x or 0.0) * sn + (y or 0.0) * c,
        base.z + (z or 0.0)
    )
end

local function deleteEntitySafe(ent)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        if JRSChickenAnim and JRSChickenAnim.carrying == ent then
            JRSChickenAnim.ReleaseCarry(ent)
        end
        NetworkRequestControlOfEntity(ent)
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function removeEntityFromList(list, ent)
    for i = #list, 1, -1 do
        if list[i] == ent then
            table.remove(list, i)
            return
        end
    end
end

local function clearGpsObjective()
    if not Config.Features.gps then return end

    -- Remove the optional JRS 3D destination indicator if it was enabled.
    local core = (Config.Integration and Config.Integration.coreResource) or 'jrs_core'
    if Config.Gps.useCoreDestination == true and GetResourceState(core) == 'started' then
        pcall(function() exports[core]:RemoveCustomDestination() end)
    end

    -- Clear the REAL map waypoint. This is the same waypoint system the
    -- player gets when clicking a point manually on the map.
    pcall(function()
        if IsWaypointActive() then
            SetWaypointOff()
        end
    end)

    -- Clear any old multi-route fallback as well.
    pcall(function()
        SetGpsMultiRouteRender(false)
        ClearGpsMultiRoute()
    end)
end

local function clearObjectiveBlip()
    if Mission.objectiveBlip and DoesBlipExist(Mission.objectiveBlip) then
        RemoveBlip(Mission.objectiveBlip)
    end
    Mission.objectiveBlip = nil
    clearGpsObjective()
end

local function createBlip(sprite, coords, name, scale)
    if not Config.Features.blips then return nil end
    local ok, blip = pcall(function()
        -- RDR2/RedM expects a BLIP TYPE in BlipAddForCoord, then the icon is
        -- assigned separately with SetBlipSprite. v1.1 incorrectly used the
        -- sprite hash as the blip type, which can make the objective invisible.
        local b = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
        if not b or b == 0 then return nil end
        SetBlipSprite(b, hash(sprite), true)
        SetBlipDisplay(b, 2)
        SetBlipScale(b, scale or 0.7)
        if name then
            Citizen.InvokeNative(0x9CB1A1623062F402, b, CreateVarString(10, 'LITERAL_STRING', name))
        end
        return b
    end)
    return ok and blip or nil
end

local function updateHubBlips()
    if not Config.Features.blips then return end
    local shouldShow = true
    if Config.JobCheck and Config.JobCheck.enabled and Config.JobCheck.showBlipOnlyIfJob then
        shouldShow = hasRequiredJob()
    end

    for _, hub in ipairs(Config.JobHubs or {}) do
        if shouldShow and hub.npc and hub.npc.blip and hub.npc.blip.enabled then
            if not HubBlips[hub.id] or not DoesBlipExist(HubBlips[hub.id]) then
                HubBlips[hub.id] = createBlip(hub.npc.blip.sprite, hub.npc.coords, hub.npc.blip.name, hub.npc.blip.scale)
            end
        else
            if HubBlips[hub.id] and DoesBlipExist(HubBlips[hub.id]) then
                RemoveBlip(HubBlips[hub.id])
            end
            HubBlips[hub.id] = nil
        end
    end
end

local function createEntityBlip(sprite, entity, name, scale)
    if not Config.Features.blips or not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local ok, blip = pcall(function()
        local b = Citizen.InvokeNative(0x23F74C2FDA6E7C61, 1664425300, entity) -- BLIP_ADD_FOR_ENTITY
        if not b or b == 0 then return nil end
        SetBlipSprite(b, hash(sprite), true)
        SetBlipDisplay(b, 2)
        SetBlipScale(b, scale or ((Config.Chicken and Config.Chicken.blipScale) or 0.55))
        if name then
            Citizen.InvokeNative(0x9CB1A1623062F402, b, CreateVarString(10, 'LITERAL_STRING', name))
        end
        return b
    end)
    return ok and blip or nil
end

local function clearWagonBlip()
    if Mission.wagonBlip and DoesBlipExist(Mission.wagonBlip) then
        RemoveBlip(Mission.wagonBlip)
    end
    Mission.wagonBlip = nil
end

local function setWagonBlip()
    clearWagonBlip()
    if not Config.Features.blips or not Mission.wagon or not DoesEntityExist(Mission.wagon) then return end
    Mission.wagonBlip = createEntityBlip(Config.ObjectiveBlips.wagon or 'blip_ambient_wagon', Mission.wagon, 'عربة الدجاج', 0.75)
end

local function removeChickenBlip(entity)
    local blip = Mission.chickenBlips and Mission.chickenBlips[entity]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    if Mission.chickenBlips then Mission.chickenBlips[entity] = nil end
end

local function clearChickenBlips()
    if not Mission.chickenBlips then return end
    for entity, blip in pairs(Mission.chickenBlips) do
        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
        Mission.chickenBlips[entity] = nil
    end
end

local function setGpsObjective(coords, name)
    if not Config.Features.gps then return false end
    clearGpsObjective()

    -- PRIMARY MODE: create a real RDR2/RedM map waypoint.
    -- This behaves exactly like the player manually selecting a point on the map
    -- and lets the game calculate/draw the normal road-following GPS route.
    local waypointOk = pcall(function()
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
    end)

    -- Optional JRS 3D indicator. Disabled by default because it is only a world
    -- marker and should never replace the real map waypoint/GPS route.
    local core = (Config.Integration and Config.Integration.coreResource) or 'jrs_core'
    if Config.Gps.useCoreDestination == true and GetResourceState(core) == 'started' then
        pcall(function()
            exports[core]:SetCustomDestination(vector3(coords.x, coords.y, coords.z), name or 'Destination')
        end)
    end

    if waypointOk then
        return true
    end

    -- Fallback only if SetNewWaypoint is unavailable on the current build.
    local routeOk = pcall(function()
        ClearGpsMultiRoute()
        StartGpsMultiRoute(Config.Gps.hudColor or 6, true, true)
        AddPointToGpsMultiRoute(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
        SetGpsMultiRouteRender(true)
    end)
    return routeOk
end

local function setObjective(sprite, coords, name)
    clearObjectiveBlip()
    Mission.objectiveBlip = createBlip(sprite, coords, name)
    setGpsObjective(coords, name)
    if Mission.objectiveBlip and Config.Features.gps and Config.Gps.enableBlipRouteFallback then
        pcall(function() SetBlipRoute(Mission.objectiveBlip, true) end)
    end
end

local function drawMarker(coords)
    if not Config.Features.markers then return end
    local m = Config.Marker
    Citizen.InvokeNative(0x2A32FAA57B937173, m.type,
        coords.x, coords.y, coords.z - 0.8,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        m.size[1], m.size[2], m.size[3],
        m.rgba[1], m.rgba[2], m.rgba[3], m.rgba[4],
        false, false, 2, false, 0, 0, false)
end

local function getButcherSite(id)
    for _, site in ipairs(Config.ButcherSites or {}) do
        if site.id == id then return site end
    end
end


local function getCutSite(id)
    if Config.GetCutStation then return Config.GetCutStation(id) end
    for _, site in ipairs(Config.CutStations or {}) do
        if site.id == id then return site end
    end
end

local function getCutTableCoords(site)
    local t = site and site.table
    local c = t and t.coords
    if not c then return nil end
    local object = CutStationObjects[site.id] and CutStationObjects[site.id].table or nil
    if object and DoesEntityExist(object) then return GetEntityCoords(object) end
    return vector3(c.x, c.y, c.z)
end

local function getCutScenarioCoords(site)
    local t = site and site.table
    if not t or not t.coords then return nil end
    local c = t.coords
    local sc = site.scenario or {}
    local o = sc.offset or { x = -0.15, y = -1.22, z = 0.0 }
    local object = CutStationObjects[site.id] and CutStationObjects[site.id].table or nil
    if object and DoesEntityExist(object) then
        return GetOffsetFromEntityInWorldCoords(object, o.x or -0.15, o.y or -1.22, o.z or 0.0)
    end
    local heading = c.w or 0.0
    return offsetFromHeading(vector3(c.x, c.y, c.z), heading, o.x or -0.15, o.y or -1.22, o.z or 0.0)
end

-- Creates a real RDR2 scenario point for a spawned chicken cutting table.
-- v2.1 only called TaskStartScenarioInPlace on custom tables. The butcher/rabbit
-- flow is scenario-point driven, so a spawned table had no usable point and the
-- animation could silently fail. v2.2 creates/attaches the point itself.
local function scenarioPointExists(pointId)
    if not pointId or pointId == 0 then return false end
    local ok, exists = pcall(function()
        return Citizen.InvokeNative(0x841475AC96E794D1, pointId, Citizen.ResultAsInteger()) -- DOES_SCENARIO_POINT_EXIST
    end)
    return ok and exists ~= 0 and exists ~= false
end

local function createCutScenarioPoint(site, tableEntity)
    if not site or not site.table or not tableEntity or tableEntity == 0 or not DoesEntityExist(tableEntity) then return nil end
    local sc = site.scenario or {}
    if sc.createPoint == false then return nil end

    CutStationObjects[site.id] = CutStationObjects[site.id] or {}
    local old = CutStationObjects[site.id].scenarioPoint
    if scenarioPointExists(old) then return old end

    local scenarioName = sc.type or ((Config.ButcherScenario or {}).FallbackScenario) or 'WORLD_HUMAN_BUTCHER_RABBIT'
    local o = sc.offset or { x = 0.0, y = -1.25, z = 0.0 }
    local pointId = nil

    -- Preferred: attach the scenario point to the spawned butcher table so it
    -- follows its heading/position and can be moved only from Config.CutStations.
    if sc.attachToTable ~= false then
        local ok, result = pcall(function()
            return Citizen.InvokeNative(
                0x794AB1379A74064D, -- CREATE_SCENARIO_POINT_HASH_ATTACHED_TO_ENTITY
                tableEntity,
                hash(scenarioName),
                o.x or 0.0, o.y or -1.05, o.z or 0.0,
                sc.headingOffset or 0.0,
                0, 0, true,
                Citizen.ResultAsInteger()
            )
        end)
        if ok and result and result ~= 0 then pointId = result end
    end

    -- Safe fallback: create the scenario point in world space at the configured
    -- player cutting position if the attached form is unavailable on a build.
    if not scenarioPointExists(pointId) then
        local p = getCutScenarioCoords(site)
        local heading = GetEntityHeading(tableEntity) + (sc.headingOffset or 0.0)
        if p then
            local ok, result = pcall(function()
                return Citizen.InvokeNative(
                    0x94B745CE41DB58A1, -- CREATE_SCENARIO_POINT_HASH
                    hash(scenarioName),
                    p.x, p.y, p.z,
                    heading,
                    0, 0, true,
                    Citizen.ResultAsInteger()
                )
            end)
            if ok and result and result ~= 0 then pointId = result end
        end
    end

    if scenarioPointExists(pointId) then
        pcall(function()
            Citizen.InvokeNative(0xC47D9080A9A8856A, pointId, sc.radius or 1.25) -- SET_SCENARIO_POINT_RADIUS
        end)
        CutStationObjects[site.id].scenarioPoint = pointId
        dbg(('created cut scenario point %s for %s (%s)'):format(tostring(pointId), tostring(site.id), tostring(scenarioName)))
        return pointId
    end

    dbg(('failed to create cut scenario point for %s'):format(tostring(site.id)))
    return nil
end

local function spawnCutStationObject(site)
    if not site or not site.table or site.table.spawn == false then return true end
    if CutStationObjects[site.id] and CutStationObjects[site.id].table and DoesEntityExist(CutStationObjects[site.id].table) then
        return true
    end

    local t = site.table
    local ok, model = requestModel(t.model or 'mp005_s_posse_butcher01x')
    if not ok then
        dbg(('cut table model failed: %s'):format(tostring(t.model)))
        return false
    end

    local c = t.coords
    local spawnZ = c.z
    local foundGround, groundZ = GetGroundZFor_3dCoord(c.x, c.y, c.z + 10.0, false)
    if not foundGround or not groundZ or groundZ <= 0.0 then
        foundGround, groundZ = GetGroundZFor_3dCoord(c.x, c.y, c.z + 2.0, false)
    end

    if foundGround and groundZ and groundZ > 0.0 then
        spawnZ = groundZ - 0.05
    else
        spawnZ = c.z - 0.05
    end

    local obj = CreateObject(model, c.x, c.y, spawnZ, false, false, false)
    if not obj or obj == 0 then return false end
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityCoordsNoOffset(obj, c.x, c.y, spawnZ, false, false, false)
    SetEntityHeading(obj, c.w or 0.0)
    SetEntityCollision(obj, true, true)
    FreezeEntityPosition(obj, true)
    SetEntityVisible(obj, true)

    CutStationObjects[site.id] = CutStationObjects[site.id] or {}
    CutStationObjects[site.id].table = obj

    -- A custom spawned object does not automatically get the map-authored
    -- butcher scenario point. Create one now so TaskUseScenarioPoint can run.
    createCutScenarioPoint(site, obj)

    local board = t.cuttingBoard
    if board and board.enabled ~= false then
        local bok, bmodel = requestModel(board.model or 'p_cuttingboard01x')
        if bok then
            local tablePos = GetEntityCoords(obj)
            local heading = GetEntityHeading(obj)
            local o = board.offset or { x = 0.0, y = 0.0, z = 0.82, headingOffset = 0.0 }
            local bp = offsetFromHeading(tablePos, heading, o.x, o.y, o.z)
            local b = CreateObject(bmodel, bp.x, bp.y, bp.z, false, false, false)
            if b and b ~= 0 then
                SetEntityAsMissionEntity(b, true, true)
                SetEntityHeading(b, heading + (o.headingOffset or 0.0))
                SetEntityCollision(b, false, false)
                FreezeEntityPosition(b, true)
                SetEntityVisible(b, true)
                CutStationObjects[site.id].board = b
            end
            SetModelAsNoLongerNeeded(bmodel)
        end
    end

    SetModelAsNoLongerNeeded(model)
    return true
end

local function spawnAllCutStations()
    for _, site in ipairs(Config.CutStations or {}) do
        spawnCutStationObject(site)
    end
end

-- Cut-table workspot (v3.2.0).
-- The old fixed stand offset (y = -1.22) landed inside the posse butcher
-- table's footprint, so the player was put on the table's short end/on top of
-- it. The table is now measured with downward rays once per site, and the
-- player is stood on the ground just outside the table's LONG edge, facing it,
-- with the chicken laid near that same edge.

-- Highest collision hit straight down at (x, y). Returns hitZ, hitEntity.
local function probeSurfaceZ(x, y, topZ, bottomZ)
    local start = StartExpensiveSynchronousShapeTestLosProbe or StartShapeTestRay
    if type(start) ~= 'function' or type(GetShapeTestResult) ~= 'function' then return nil end
    local okH, handle = pcall(start, x, y, topZ, x, y, bottomZ, -1, PlayerPedId(), 7)
    if not okH or not handle or handle == 0 then return nil end
    local deadline = GetGameTimer() + 150
    while true do
        local okR, status, hit, endCoords, _, entityHit = pcall(GetShapeTestResult, handle)
        if not okR then return nil end
        if status ~= 1 then
            if (hit == 1 or hit == true) and endCoords and endCoords.z then
                return endCoords.z + 0.0, entityHit
            end
            return nil
        end
        if GetGameTimer() > deadline then return nil end
        Wait(0)
    end
end

-- Table base (ground) position + heading, and a local->world helper.
local function getCutTableFrame(site)
    local t = site and site.table
    if not t or not t.coords then return nil end
    local ent = CutStationObjects[site.id] and CutStationObjects[site.id].table or nil
    if ent and DoesEntityExist(ent) then
        local pos = GetEntityCoords(ent)
        return {
            ent = ent, base = pos, heading = GetEntityHeading(ent),
            toWorld = function(lx, ly, lz) return GetOffsetFromEntityInWorldCoords(ent, lx, ly, lz or 0.0) end,
        }
    end
    local c = t.coords
    local base = vector3(c.x, c.y, c.z)
    return {
        ent = nil, base = base, heading = c.w or 0.0,
        toWorld = function(lx, ly, lz) return offsetFromHeading(base, c.w or 0.0, lx, ly, lz or 0.0) end,
    }
end

-- Rays start just above table-top height so a hanging rack over the table
-- (posse butcher model) is never hit first.
local TABLE_PROBE_TOP = 1.25

local function isTableHit(frame, z, ent)
    if not z then return false end
    -- Only the work-surface band counts; a rack or pole above it must not.
    if z > frame.base.z + TABLE_PROBE_TOP then return false end
    if frame.ent and ent and ent ~= 0 and ent == frame.ent then return true end
    return z > frame.base.z + 0.45
end

-- Measures how far the table top reaches along +x, -x, +y, -y (table-local).
local function measureCutTable(site, frame)
    local cache = CutStationObjects[site.id]
    if cache and cache.footprint and cache.footprintEnt == frame.ent then return cache.footprint end

    local step, maxReach = 0.06, 2.6
    local dirs = { px = { 1, 0 }, nx = { -1, 0 }, py = { 0, 1 }, ny = { 0, -1 } }
    local fp = { topZ = nil }
    local okAll = true
    for key, d in pairs(dirs) do
        local last = nil
        local dist = 0.0
        while dist <= maxReach do
            local p = frame.toWorld(d[1] * dist, d[2] * dist, 0.0)
            local z, ent = probeSurfaceZ(p.x, p.y, frame.base.z + TABLE_PROBE_TOP, frame.base.z - 1.0)
            if isTableHit(frame, z, ent) then
                last = dist
                if z > frame.base.z + 0.45 and (not fp.topZ or z > fp.topZ) then fp.topZ = z end
            elseif last then
                break
            elseif dist > 0.7 then
                break
            end
            dist = dist + step
        end
        if not last then okAll = false end
        fp[key] = last or 0.0
    end

    local measured = okAll and fp.topZ ~= nil
    if not measured then
        -- Collision not streamed / rays unavailable: use the model bounds
        -- for now and re-measure next time (not cached).
        local model = frame.ent and GetEntityModel(frame.ent) or nil
        if model then
            local okD, mn, mx = pcall(GetModelDimensions, model)
            if okD and mn and mx then
                fp.px, fp.nx, fp.py, fp.ny = mx.x, -mn.x, mx.y, -mn.y
                fp.topZ = fp.topZ or (frame.base.z + math.min(mx.z, 1.0))
                okAll = true
            end
        end
    end
    if not okAll then return nil end

    dbg(('cut table %s footprint +x %.2f -x %.2f +y %.2f -y %.2f top %.2f (base %.2f)'):format(
        tostring(site.id), fp.px, fp.nx, fp.py, fp.ny, fp.topZ or -1, frame.base.z))
    if measured then
        CutStationObjects[site.id] = CutStationObjects[site.id] or {}
        CutStationObjects[site.id].footprint = fp
        CutStationObjects[site.id].footprintEnt = frame.ent
    end
    return fp
end

-- Returns { stand = vector3 (ped root), heading, chicken = vector3, chickenHeading }.
-- nearPos picks which long side to use (the player at put-down time, the
-- chicken at cut time so both steps always use the same side).
local function getCutWorkspot(site, nearPos)
    local frame = getCutTableFrame(site)
    if not frame then return nil end
    local fp = measureCutTable(site, frame)
    if not fp then return nil end

    local sc = site.scenario or {}
    local t = site.table or {}
    local clearance = sc.standClearance or 0.48
    local inset = t.chickenEdgeInset or 0.26
    local lift = t.chickenSurfaceLift or 0.10

    -- Stand facing the long edge: the side axis is the table's short axis.
    local longIsX = (fp.px + fp.nx) >= (fp.py + fp.ny)
    local candidates
    if longIsX then
        local midX = (fp.px - fp.nx) * 0.5
        candidates = {
            { sx = midX, sy = fp.py + clearance, cx = midX, cy = math.max(0.0, fp.py - inset) },
            { sx = midX, sy = -(fp.ny + clearance), cx = midX, cy = -math.max(0.0, fp.ny - inset) },
        }
    else
        local midY = (fp.py - fp.ny) * 0.5
        candidates = {
            { sx = fp.px + clearance, sy = midY, cx = math.max(0.0, fp.px - inset), cy = midY },
            { sx = -(fp.nx + clearance), sy = midY, cx = -math.max(0.0, fp.nx - inset), cy = midY },
        }
    end

    local best, bestScore = nil, nil
    for _, c in ipairs(candidates) do
        local s = frame.toWorld(c.sx, c.sy, 0.0)
        local gz, gent = probeSurfaceZ(s.x, s.y, frame.base.z + TABLE_PROBE_TOP, frame.base.z - 2.0)
        local blocked = isTableHit(frame, gz, gent)
        local score = nearPos and #(vector2(s.x, s.y) - vector2(nearPos.x, nearPos.y)) or 0.0
        if blocked then score = score + 100.0 end
        if not bestScore or score < bestScore then
            best, bestScore = { c = c, s = s, gz = (not blocked) and gz or nil }, score
        end
    end
    if not best then return nil end

    local groundZ = best.gz
    if not groundZ or math.abs(groundZ - frame.base.z) > 1.2 then groundZ = frame.base.z end
    local standZ = groundZ + 0.98 + (sc.standZOffset or 0.0)
    local stand = vector3(best.s.x, best.s.y, standZ)

    local cw = frame.toWorld(best.c.cx, best.c.cy, 0.0)
    local chicken = vector3(cw.x, cw.y, (fp.topZ or (frame.base.z + 0.9)) + lift)
    local heading = GetHeadingFromVector_2d(chicken.x - stand.x, chicken.y - stand.y)

    return {
        stand = stand,
        heading = heading,
        chicken = chicken,
        -- Lay the bird along the edge, in front of the player.
        chickenHeading = heading + 90.0 + (t.chickenHeadingOffset or 0.0),
    }
end

-- Put the player on the ground at the workspot, facing the table.
local function moveToCutWorkspot(ped, spot, keepTasks)
    -- keepTasks: while carrying, clearing tasks would drop the native carry.
    if not keepTasks then ClearPedTasksImmediately(ped) end
    FreezeEntityPosition(ped, false)
    SetEntityCoordsNoOffset(ped, spot.stand.x, spot.stand.y, spot.stand.z, false, false, false)
    SetEntityHeading(ped, spot.heading)
    -- Never PlaceEntityOnGroundProperly here: it snaps up onto table collision.
    Wait(50)
end

local function despawnHubNPC(hubId)
    local ped = HubNPCs[hubId]
    if ped and DoesEntityExist(ped) then
        deleteEntitySafe(ped)
    end
    HubNPCs[hubId] = nil
end

local function spawnHubNPC(hub)
    if not Config.Features.npc then return nil end
    if not hub or not hub.npc then return nil end

    local currentPed = HubNPCs[hub.id]
    if currentPed and DoesEntityExist(currentPed) and not IsEntityDead(currentPed) then
        return currentPed
    end

    local c = hub.npc.coords
    if not c then return nil end

    local ok, model = requestModel(hub.npc.model)
    if not ok then return nil end

    local ped = CreatePed(model, c.x, c.y, c.z, c.w or 0.0, false, true, true, true)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(model)
        return nil
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)

    -- Wait briefly for collision so ground placement works cleanly without sinking or floating
    local deadline = GetGameTimer() + 1000
    while GetGameTimer() < deadline and not HasCollisionLoadedAroundEntity(ped) do
        Wait(0)
    end
    pcall(PlaceEntityOnGroundProperly, ped, false)

    -- Essential in RedM: ambient peds need outfit variation to be visible
    pcall(Citizen.InvokeNative, 0x283978A15512B2FE, ped, true)
    pcall(SetEntityVisible, ped, true)
    pcall(SetEntityAlpha, ped, 255, false)
    pcall(SetEntityInvincible, ped, true)
    pcall(SetEntityCanBeDamaged, ped, false)
    pcall(SetPedCanRagdoll, ped, false)
    pcall(SetBlockingOfNonTemporaryEvents, ped, true)
    pcall(FreezeEntityPosition, ped, true)
    pcall(SetPedCanBeTargetted, ped, false)

    local scenario = hub.npc.scenario or 'WORLD_HUMAN_STAND_WAITING'
    if scenario and scenario ~= '' then
        pcall(TaskStartScenarioInPlace, ped, GetHashKey(scenario), -1, true, false, false, false)
    end

    HubNPCs[hub.id] = ped
    SetModelAsNoLongerNeeded(model)
    return ped
end

local function setupAttachedPropSafe(obj, wagon, bone, x, y, z, rx, ry, rz)
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityInvincible(obj, true)
    pcall(SetEntityCanBeDamaged, obj, false)
    pcall(SetEntityProofs, obj, true, true, true, true, true, true, true, true)
    SetEntityCollision(obj, false, false)
    pcall(SetEntityCompletelyDisableCollision, obj, false, false)
    pcall(SetEntityDynamic, obj, false)
    SetEntityHasGravity(obj, false)
    FreezeEntityPosition(obj, false)
    AttachEntityToEntity(obj, wagon, bone or 0,
        x, y, z, rx, ry, rz,
        false, false, false, false, 2, true, false, false)
end

local function spawnWagonChickenTrap()
    local trap = Config.Wagon and Config.Wagon.chickenTrap or nil
    if not trap or trap.enabled == false then
        Mission.wagonTrap = nil
        Mission.wagonTraps = {}
        return true
    end
    if not Mission.wagon or not DoesEntityExist(Mission.wagon) then return false end

    local ok, model = requestModel(trap.model or 'p_trap01x')
    if not ok then
        notify(Config.Text.cageModelError or 'تعذر تحميل نموذج قفص الدجاج.')
        return false
    end

    Mission.wagonTraps = {}
    local cagesList = trap.cages
    local groupOffset = trap.groupOffset or { x = 0.0, y = 0.0, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0 }
    local wpos = GetEntityCoords(Mission.wagon)

    if type(cagesList) == 'table' and #cagesList > 0 then
        for i, cDef in ipairs(cagesList) do
            local obj = CreateObject(model, wpos.x, wpos.y, wpos.z + 1.0 + (i * 0.2), false, false, false)
            if not obj or obj == 0 or not DoesEntityExist(obj) then
                SetModelAsNoLongerNeeded(model)
                notify(Config.Text.cageSpawnError or 'تعذر إنشاء قفص الدجاج.')
                return false
            end

            local ax = (groupOffset.x or 0.0) + (cDef.x or 0.0)
            local ay = (groupOffset.y or 0.0) + (cDef.y or 0.0)
            local az = (groupOffset.z or 0.0) + (cDef.z or 0.0)
            local arx = (groupOffset.rx or 0.0) + (cDef.rx or 0.0)
            local ary = (groupOffset.ry or 0.0) + (cDef.ry or 0.0)
            local arz = (groupOffset.rz or 0.0) + (cDef.rz or 0.0)

            setupAttachedPropSafe(obj, Mission.wagon, 0, ax, ay, az, arx, ary, arz)

            Mission.wagonTraps[#Mission.wagonTraps + 1] = {
                entity = obj,
                offset = { x = ax, y = ay, z = az, rx = arx, ry = ary, rz = arz }
            }
        end
        Mission.wagonTrap = Mission.wagonTraps[1] and Mission.wagonTraps[1].entity or nil
    else
        local obj = CreateObject(model, wpos.x, wpos.y, wpos.z + 1.0, false, false, false)
        if not obj or obj == 0 or not DoesEntityExist(obj) then
            SetModelAsNoLongerNeeded(model)
            notify(Config.Text.cageSpawnError or 'تعذر إنشاء قفص الدجاج.')
            return false
        end

        local a = trap.attach or { x = 0.0, y = -1.48, z = 0.15, rx = 0.0, ry = 0.0, rz = 0.0 }
        local az = a.z or 0.15
        if az < 0.0 and groupOffset.z then
            az = az + groupOffset.z
        end

        setupAttachedPropSafe(obj, Mission.wagon, 0, a.x or 0.0, a.y or -1.48, az, a.rx or 0.0, a.ry or 0.0, a.rz or 0.0)

        Mission.wagonTraps[1] = {
            entity = obj,
            offset = { x = a.x or 0.0, y = a.y or -1.48, z = az, rx = a.rx or 0.0, ry = a.ry or 0.0, rz = a.rz or 0.0 }
        }
        Mission.wagonTrap = obj
    end

    SetModelAsNoLongerNeeded(model)
    return true
end

local function getWagonChickenParent(slot)
    slot = tonumber(slot) or 1
    if Mission.wagonTraps and #Mission.wagonTraps > 0 then
        local trapObj = (Config.Wagon and Config.Wagon.chickenTrap) or {}
        local slotsPerCage = (trapObj.chickenSlots and #trapObj.chickenSlots) or 2
        local cageIdx = math.floor((slot - 1) / slotsPerCage) + 1
        if cageIdx > #Mission.wagonTraps then cageIdx = #Mission.wagonTraps end
        local cageEntry = Mission.wagonTraps[cageIdx]
        local entity = type(cageEntry) == 'table' and cageEntry.entity or cageEntry
        if entity and DoesEntityExist(entity) then
            return entity
        end
        local first = type(Mission.wagonTraps[1]) == 'table' and Mission.wagonTraps[1].entity or Mission.wagonTraps[1]
        if first and DoesEntityExist(first) then
            return first
        end
    end
    if Mission.wagonTrap and DoesEntityExist(Mission.wagonTrap) then
        return Mission.wagonTrap
    end
    return Mission.wagon
end

local function getWagonChickenOffset(slot)
    slot = tonumber(slot) or 1
    local trapObj = (Config.Wagon and Config.Wagon.chickenTrap) or {}
    local positions = trapObj.chickenSlots or {}
    local pos

    if #positions > 0 then
        local slotInCage = ((slot - 1) % #positions) + 1
        pos = positions[slotInCage]
    else
        pos = { x = -0.16, y = 0.0, z = 0.16, rz = 20.0 }
    end

    -- Offsets here are relative to the specific p_trap01x cage
    return {
        x = pos.x or 0.0,
        y = pos.y or 0.0,
        z = pos.z or 0.16,
        rx = pos.rx or 0.0,
        ry = pos.ry or 0.0,
        rz = pos.rz or 0.0,
    }
end

local function ensureWagonTrapsAttached()
    if not Mission.wagon or not DoesEntityExist(Mission.wagon) then return end
    if not Mission.wagonTraps or #Mission.wagonTraps == 0 then return end

    for _, trapData in ipairs(Mission.wagonTraps) do
        local obj = type(trapData) == 'table' and trapData.entity or trapData
        local off = type(trapData) == 'table' and trapData.offset or nil
        if obj and DoesEntityExist(obj) then
            SetEntityCollision(obj, false, false)
            pcall(SetEntityDynamic, obj, false)
            if not IsEntityAttachedToEntity(obj, Mission.wagon) and off then
                AttachEntityToEntity(obj, Mission.wagon, 0,
                    off.x, off.y, off.z,
                    off.rx, off.ry, off.rz,
                    false, false, false, false, 2, true, false, false)
            end
        end
    end
end

local function ensureWagonChickensAttached()
    if not Mission.wagon or not DoesEntityExist(Mission.wagon) then return end
    if not Mission.wagonChickens or #Mission.wagonChickens == 0 then return end

    for slot, chicken in ipairs(Mission.wagonChickens) do
        if DoesEntityExist(chicken) then
            local parent = getWagonChickenParent(slot)
            SetEntityCollision(chicken, false, false)
            pcall(SetEntityDynamic, chicken, false)
            if parent and DoesEntityExist(parent) and not IsEntityAttachedToEntity(chicken, parent) then
                local o = getWagonChickenOffset(slot)
                AttachEntityToEntity(chicken, parent, 0,
                    o.x, o.y, o.z,
                    o.rx, o.ry, o.rz,
                    false, false, false, false, 2, true, false, false)
            end
        end
    end

    if Mission.chestOnWagon and Mission.chestProp and DoesEntityExist(Mission.chestProp) then
        SetEntityCollision(Mission.chestProp, false, false)
        pcall(SetEntityDynamic, Mission.chestProp, false)
        if not IsEntityAttachedToEntity(Mission.chestProp, Mission.wagon) then
            local o = (Config.Basin and Config.Basin.wagonAttach) or { x = 0.0, y = -1.35, z = 1.05, rx = 0.0, ry = 0.0, rz = 0.0 }
            AttachEntityToEntity(Mission.chestProp, Mission.wagon, 0,
                o.x or 0.0, o.y or -1.35, o.z or 1.05,
                o.rx or 0.0, o.ry or 0.0, o.rz or 0.0,
                false, false, false, false, 2, true, false, false)
        end
    end
end

local function spawnWagon(spawnOverride)
    local hub = Mission.hub
    local ok, model = requestModel(Config.Wagon.model)
    if not ok then
        notify(Config.Text.wagonModelError or 'تعذر تحميل نموذج العربة.')
        return false
    end
    local c = spawnOverride or hub.wagonSpawn
    if Config.Wagon.useDraftVehicle ~= false and CreateDraftVehicle then
        Mission.wagon = CreateDraftVehicle(
            model, c.x, c.y, c.z, c.w,
            true, true, false,
            hash(Config.Wagon.draftHorseGroup or 'DRAFT_HORSES_MID'),
            0
        )
    else
        Mission.wagon = CreateVehicle(model, c.x, c.y, c.z, c.w, true, true, false, false)
    end
    SetEntityAsMissionEntity(Mission.wagon, true, true)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(Mission.wagon) then return false end

    if not spawnWagonChickenTrap() then
        deleteEntitySafe(Mission.wagon)
        Mission.wagon = nil
        return false
    end
    setWagonBlip()
    return true
end

local function randomPoint(center, radius)
    local angle = math.random() * math.pi * 2.0
    -- Avoid putting every chicken on the exact center while also keeping them
    -- close enough for the player to immediately see what to do.
    local minR = math.min(2.0, radius * 0.25)
    local r = minR + (math.sqrt(math.random()) * math.max(0.0, radius - minR))
    return vector3(center.x + math.cos(angle) * r, center.y + math.sin(angle) * r, center.z + 1.5)
end

local function findGroundZ(x, y, fallbackZ)
    -- Cfx exposes GetGroundZFor_3dCoord on RedM builds. Keep a safe fallback
    -- for builds where it is unavailable or the collision has not streamed yet.
    local ok, found, groundZ = pcall(function()
        return GetGroundZFor_3dCoord(x + 0.0, y + 0.0, (fallbackZ or 0.0) + 20.0, false)
    end)
    if ok and found and groundZ then return groundZ + 0.15 end
    return (fallbackZ or 0.0) + 0.35
end

local function drawWorldText(coords, text, scale, rgba)
    local ok, onScreen, screenX, screenY = pcall(function()
        return GetScreenCoordFromWorldCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    end)
    if not ok or not onScreen then return end

    rgba = rgba or {255, 220, 90, 230}
    scale = scale or 0.28

    SetTextScale(scale, scale)
    SetTextColor(rgba[1], rgba[2], rgba[3], rgba[4])
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 180)
    local label = CreateVarString(10, 'LITERAL_STRING', text)
    DisplayText(label, screenX, screenY)
end

local function drawChickenMarker(entity, playerPos)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    local c = GetEntityCoords(entity)
    local d = playerPos and dist(playerPos, c) or 0.0
    local drawDistance = (Config.Chicken and Config.Chicken.drawText and Config.Chicken.drawText.distance) or 18.0
    if playerPos and d > drawDistance then return end

    -- Floating draw-text so every chicken is immediately identifiable.
    local dt = Config.Chicken and Config.Chicken.drawText or {}
    if dt.enabled ~= false then
        local text = dt.text or 'G  •  CATCH'
        local zOffset = dt.zOffset or 0.62
        drawWorldText(vector3(c.x, c.y, c.z + zOffset), text, dt.scale or 0.27, dt.rgba or {255, 220, 90, 235})
    end
end

local function spawnChickens()
    if #Mission.chickens > 0 then return true end

    local ok, model = requestModel(Config.Chicken.model)
    if not ok then
        notify(Config.Text.chickenSpawnFailed or 'تعذر استدعاء الدجاج، ابقَ قريباً من المنطقة وستتم إعادة المحاولة.')
        return false
    end

    local spawned = 0
    for i = 1, Config.ChickensRequired do
        local p = randomPoint(Mission.catchZone, Config.Chicken.spawnRadius)
        local groundZ = findGroundZ(p.x, p.y, Mission.catchZone.z)
        local ped = CreatePed(model, p.x, p.y, groundZ, math.random(0, 359) + 0.0, true, true, false, false)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)

            -- RedM can create animal/ped entities that exist and even have a blip,
            -- but stay visually invisible until an outfit/variation is applied.
            -- This native is the RedM SetRandomOutfitVariation / SetPedDefaultOutfit fix.
            pcall(function() Citizen.InvokeNative(0x283978A15512B2FE, ped, true) end)
            SetEntityVisible(ped, true)
            SetEntityAlpha(ped, 255, false)
            SetEntityCollision(ped, true, true)
            FreezeEntityPosition(ped, false)
            SetBlockingOfNonTemporaryEvents(ped, true)
            Entity(ped).state:set('isChickenJob', true, true)
            Entity(ped).state:set('chickenMission', true, true)
            pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, ped, 21, true) end)

            -- Keep the chicken on the streamed ground. Avoid relying only on
            -- PlaceEntityOnGroundProperly because that native is inconsistent for peds.
            SetEntityCoordsNoOffset(ped, p.x, p.y, groundZ, false, false, false)
            Wait(0)
            pcall(function() PlaceEntityOnGroundProperly(ped) end)
            SetEntityVisible(ped, true)
            SetEntityAlpha(ped, 255, false)

            local wandered = pcall(function()
                TaskWanderInArea(ped, Mission.catchZone.x, Mission.catchZone.y, Mission.catchZone.z,
                    math.max(3.0, Config.Chicken.spawnRadius * 0.85), 2.0, 5.0)
            end)
            if not wandered then TaskWanderStandard(ped, 2.0, 10) end

            Mission.chickens[#Mission.chickens + 1] = ped
            if Config.Chicken.showBlips ~= false then
                local b = createEntityBlip(Config.Chicken.blipSprite or Config.ObjectiveBlips.catch, ped, 'Chicken')
                if b then Mission.chickenBlips[ped] = b end
            end
            spawned = spawned + 1
        end
    end
    SetModelAsNoLongerNeeded(model)

    if spawned < Config.ChickensRequired then
        -- Do not silently advance into an empty catch stage.
        for _, ent in ipairs(Mission.chickens) do deleteEntitySafe(ent) end
        Mission.chickens = {}
        clearChickenBlips()
        notify(Config.Text.chickenSpawnFailed or 'تعذر استدعاء الدجاج، جاري إعادة المحاولة...')
        return false
    end

    return true
end

local function pickupLiveChicken(chicken)
    if Mission.carriedChicken or not chicken or not DoesEntityExist(chicken) then return false end
    ClearPedTasksImmediately(chicken)
    TaskStandStill(chicken, -1)
    SetEntityInvincible(chicken, true)
    SetBlockingOfNonTemporaryEvents(chicken, true)
    removeEntityFromList(Mission.chickens, chicken)
    removeChickenBlip(chicken)

    if not JRSChickenAnim.PickupAndCarry(chicken, 'liveChicken') then
        return false
    end

    Mission.carriedChicken = chicken
    Mission.carriedChickenDead = false
    return true
end

local function attachChickenToWagon()
    local ped = PlayerPedId()
    local ent = Mission.carriedChicken
    if not ent or not DoesEntityExist(ent) then
        local carriedEnt = Citizen.InvokeNative(0xD806CD2A4F2C2996, ped, Citizen.ResultAsInteger())
        if carriedEnt and carriedEnt ~= 0 and DoesEntityExist(carriedEnt) then
            ent = carriedEnt
            Mission.carriedChicken = ent
        end
    end
    if not ent or not DoesEntityExist(ent) or not Mission.wagon or not DoesEntityExist(Mission.wagon) then return false end
    if #Mission.wagonChickens >= Config.Wagon.maxChickens then return false end

    ClearPedTasks(ped)
    DetachEntity(ent, true, true)

    JRSChickenAnim.StowChicken(ent, Mission.wagon)
    local slot = #Mission.wagonChickens + 1
    local o = getWagonChickenOffset(slot)
    local parent = getWagonChickenParent(slot)

    ClearPedTasksImmediately(ent)
    SetEntityInvincible(ent, true)
    pcall(SetEntityCanBeDamaged, ent, false)
    pcall(SetEntityProofs, ent, true, true, true, true, true, true, true, true)
    SetEntityCollision(ent, false, false)
    pcall(SetEntityCompletelyDisableCollision, ent, false, false)
    pcall(SetEntityDynamic, ent, false)
    SetEntityHasGravity(ent, false)
    FreezeEntityPosition(ent, false)

    AttachEntityToEntity(ent, parent, 0,
        o.x, o.y, o.z, o.rx, o.ry, o.rz,
        false, false, false, false, 2, true, false, false)

    Mission.wagonChickens[#Mission.wagonChickens + 1] = ent
    Mission.carriedChicken = nil
    Mission.carriedChickenDead = false
    Mission.caught = Mission.caught + 1
    return true
end

local function takeChickenFromWagon()
    if #Mission.wagonChickens <= 0 or Mission.carriedChicken then return false end
    local ent = table.remove(Mission.wagonChickens, #Mission.wagonChickens)
    if not ent or not DoesEntityExist(ent) then return false end

    DetachEntity(ent, true, true)
    SetEntityCollision(ent, false, false)
    Entity(ent).state:set('isChickenJob', true, true)
    Entity(ent).state:set('chickenMission', true, true)
    pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, ent, 21, true) end)
    if not JRSChickenAnim.UnstowChicken(ent, Mission.wagon, 'liveChicken') then return false end

    Mission.carriedChicken = ent
    Mission.carriedChickenDead = false
    return true
end

local function setEntityAtTable(entity, baseCoords, attach)
    attach = attach or { x = 0.0, y = 0.0, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0 }

    -- Table props must not be allowed to physics-resolve against the static
    -- butcher table. If collision is enabled before freezing, RDR2 can shove
    -- the chicken sideways/upwards when its mesh slightly intersects the top.
    DetachEntity(entity, true, true)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, false)

    SetEntityCoordsNoOffset(entity,
        baseCoords.x + (attach.x or 0.0),
        baseCoords.y + (attach.y or 0.0),
        baseCoords.z + (attach.z or 0.0),
        false, false, false)
    SetEntityRotation(entity, attach.rx or 0.0, attach.ry or 0.0, attach.rz or 0.0, 2, true)

    -- Re-apply after a frame, then freeze with collision disabled. This keeps
    -- the exact configured pose until the player picks the chicken up.
    Wait(0)
    SetEntityCoordsNoOffset(entity,
        baseCoords.x + (attach.x or 0.0),
        baseCoords.y + (attach.y or 0.0),
        baseCoords.z + (attach.z or 0.0),
        false, false, false)
    SetEntityRotation(entity, attach.rx or 0.0, attach.ry or 0.0, attach.rz or 0.0, 2, true)
    FreezeEntityPosition(entity, true)
end

local function killCarriedChickenOnGround(site)
    local ent = Mission.carriedChicken
    if not ent or ent == 0 or not DoesEntityExist(ent) or Mission.carriedChickenDead then return false end

    local ped = PlayerPedId()
    local killCfg = (Config.Animations and Config.Animations.kill) or {}

    -- The live chicken stays the SAME entity throughout the full sequence.
    -- First calculate a stable point in front of the player, then visibly put
    -- the chicken there before the knife animation begins.
    local groundPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, killCfg.chickenForwardOffset or 0.45, 0.0)
    local ok, found, groundZ = pcall(function()
        return GetGroundZFor_3dCoord(groundPos.x, groundPos.y, groundPos.z + 5.0, false)
    end)
    if ok and found and groundZ then
        groundPos = vector3(groundPos.x, groundPos.y, groundZ + (killCfg.chickenGroundOffset or 0.08))
    end

    SetEntityInvincible(ent, true)
    SetBlockingOfNonTemporaryEvents(ent, true)
    if not JRSChickenAnim.PlaceChickenForSlaughter(ent, groundPos, GetEntityHeading(ped) + 180.0) then
        return false
    end
    Mission.carriedChicken = nil

    local killed = false
    local function killAtKnifeStrike()
        if killed or not DoesEntityExist(ent) then return end
        killed = true
        FreezeEntityPosition(ent, false)
        SetEntityInvincible(ent, false)
        SetEntityCollision(ent, true, true)
        pcall(function() SetEntityHealth(ent, 0, 0) end)
        if not IsEntityDead(ent) then pcall(function() SetEntityHealth(ent, 0) end) end
        if not IsEntityDead(ent) then
            pcall(function() ApplyDamageToPed(ent, 1000, false, true, 0) end)
        end
        if not IsEntityDead(ent) then
            -- Native fallback for builds where the Lua health wrapper has a different signature.
            pcall(function() Citizen.InvokeNative(0x697157CED63F18D4, ent, 1000, false, true, true) end)
        end
    end

    -- The knife prop is drawn first, then the player drops to the grounded
    -- attack. The chicken dies exactly at the configured contact frame.
    JRSChickenAnim.PlayKnifeSlaughter(ent, groundPos, killAtKnifeStrike)
    killAtKnifeStrike()

    Wait(killCfg.corpseSettleMs or 900)
    pcall(function() PlaceEntityOnGroundProperly(ent) end)
    pcall(function() PlaceEntityOnGroundProperly(ped) end)
    FreezeEntityPosition(ent, false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ent, true, true)

    local optimal = 0
    pcall(function()
        optimal = Citizen.InvokeNative(0x34F008A7E48C496B, ent, 0, Citizen.ResultAsInteger()) or 0
    end)
    if not optimal or optimal == 0 then
        optimal = GetHashKey('GENERIC_DEAD_CARRIABLE_SMALL_ANIMAL')
    end
    pcall(function()
        Citizen.InvokeNative(0xF0B4F759F35CC7F5, ent, optimal, ped, 0, 0)
    end)
    pcall(function() Citizen.InvokeNative(0x18FF3110CF47115D, ent, 21, true) end)
    Entity(ent).state:set('isChickenJob', true, true)
    Entity(ent).state:set('chickenMission', true, true)

    Mission.groundDeadChicken = ent
    Mission.carriedChickenDead = false
    Mission.tableChicken = nil
    Mission.tableDead = false
    if not Mission.testMode then
        TriggerServerEvent('jrs_chicken_job:server:chickenKilled')
    end
    return true
end

local function pickupDeadChickenFromGround()
    local ent = Mission.groundDeadChicken
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end

    FreezeEntityPosition(ent, false)
    SetEntityCollision(ent, false, false)
    if not JRSChickenAnim.PickupAndCarry(ent, 'deadChicken') then return false end

    Mission.groundDeadChicken = nil
    Mission.carriedChicken = ent
    Mission.carriedChickenDead = true
    return true
end

local function setDeadChickenOnCutTable(entity, site, spot)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if not site or not site.table or not site.table.coords then return false end

    spawnCutStationObject(site)

    spot = spot or getCutWorkspot(site, GetEntityCoords(PlayerPedId()))
    if spot then
        DetachEntity(entity, true, true)
        SetEntityCollision(entity, false, false)
        FreezeEntityPosition(entity, false)
        SetEntityCoordsNoOffset(entity, spot.chicken.x, spot.chicken.y, spot.chicken.z, false, false, false)
        SetEntityHeading(entity, spot.chickenHeading)
        Wait(0)
        FreezeEntityPosition(entity, true)
        return true
    end

    local t = site.table
    local cfgCoords = t.coords
    local tableEnt = CutStationObjects[site.id] and CutStationObjects[site.id].table or nil
    local pose = t.deadChickenOffset or { x = -0.05, y = -0.52, z = 0.92, headingOffset = 90.0 }
    local place = nil
    local heading = (cfgCoords.w or 0.0)

    if tableEnt and DoesEntityExist(tableEnt) then
        place = GetOffsetFromEntityInWorldCoords(tableEnt, pose.x or -0.05, pose.y or -0.52, pose.z or 0.92)
        heading = GetEntityHeading(tableEnt)
    else
        local tablePos = vector3(cfgCoords.x, cfgCoords.y, cfgCoords.z)
        place = offsetFromHeading(tablePos, heading, pose.x or -0.05, pose.y or -0.52, pose.z or 0.92)
    end

    DetachEntity(entity, true, true)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, false)

    -- Preserve the dead ped itself. Only move it onto the independent chicken
    -- cutting table; do not replace it with a prop.
    SetEntityCoordsNoOffset(entity, place.x, place.y, place.z, false, false, false)
    SetEntityHeading(entity, heading + (pose.headingOffset or 0.0))
    Wait(0)
    FreezeEntityPosition(entity, true)
    return true
end

local function placeDeadChickenForCut(site)
    local ped = PlayerPedId()
    local ent = Mission.carriedChicken
    if not ent or ent == 0 or not DoesEntityExist(ent) then
        local carriedEnt = Citizen.InvokeNative(0xD806CD2A4F2C2996, ped, Citizen.ResultAsInteger())
        if carriedEnt and carriedEnt ~= 0 and DoesEntityExist(carriedEnt) then
            ent = carriedEnt
        end
    end
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if not site or not site.table then return false end

    local tablePos = getCutTableCoords(site)
    if not tablePos then return false end

    spawnCutStationObject(site)
    local spot = getCutWorkspot(site, GetEntityCoords(ped))
    if spot then
        -- Stand at the long edge first so the place task never walks the
        -- player into/onto the table, and hands release over the table top.
        moveToCutWorkspot(ped, spot, true)
    end

    ClearPedTasks(ped)
    DetachEntity(ent, true, true)

    JRSChickenAnim.PutDown(ent, spot and spot.chicken or tablePos)
    if not setDeadChickenOnCutTable(ent, site, spot) then return false end

    Mission.carriedChicken = nil
    Mission.carriedChickenDead = false
    Mission.tableChicken = ent
    Mission.tableDead = true
    return true
end

-- Native scenario-point helpers ported from jrs_butcher_scenario.
-- The important difference from TaskStartScenarioInPlace is that this uses the
-- REAL butcher scenario point placed at the RDR2 butcher table. That makes the
-- player line up with the table and use the native chopping sequence.
local function getScenarioPointType(pointId)
    return Citizen.InvokeNative(0xA92450B5AE687AAF, pointId)
end

local function scenarioTypeAllowed(typeHash)
    local cfg = Config.ButcherScenario or {}
    local list = cfg.ScenarioTypes or {}
    for i = 1, #list do
        if hash(list[i]) == typeHash then
            return true
        end
    end
    return false
end

local function findButcherScenarioPoint(coords)
    local cfg = Config.ButcherScenario or {}
    if cfg.UseNativeScenarioPoint == false then return nil end

    -- The original butcher resource uses DataView + 0x345EC3B7EBDE1CB5 to
    -- enumerate scenario points around the player. Keep a safe fallback for
    -- RedM builds where DataView is unavailable.
    if not DataView or not DataView.ArrayBuffer then
        if Config.Debug then print('[jrs_chicken_job] DataView unavailable; using fallback cut scenario') end
        return nil
    end

    local ok, point = pcall(function()
        local data = DataView.ArrayBuffer(256 * 4)
        local radius = cfg.SearchRadius or cfg.ScenarioRadius or 1.5
        local count = Citizen.InvokeNative(0x345EC3B7EBDE1CB5, coords, radius, data:Buffer(), 10)
        if not count or count == false or count <= 0 then return nil end

        for i = 1, count do
            local scenarioPoint = data:GetInt32(8 * i)
            if scenarioPoint and scenarioPoint ~= 0 then
                local scenarioHash = getScenarioPointType(scenarioPoint)
                if scenarioTypeAllowed(scenarioHash) then
                    return scenarioPoint
                end
            end
        end
        return nil
    end)

    if not ok then
        if Config.Debug then print(('[jrs_chicken_job] scenario scan failed: %s'):format(tostring(point))) end
        return nil
    end
    return point
end

local function startNativeButcherScenario(ped, scenarioPoint)
    if not scenarioPointExists(scenarioPoint) then return false end

    ClearPedTasksImmediately(ped)
    local ok = pcall(function()
        Citizen.InvokeNative(
            0xCCDAE6324B6A821C, -- TASK_USE_SCENARIO_POINT
            ped, scenarioPoint, '', -1.0, true, false, 0, false, -1.0, true
        )
    end)
    if not ok then return false end

    -- Quick check if ped actually entered the scenario (max 1000ms)
    local timeout = GetGameTimer() + 1000
    while GetGameTimer() < timeout do
        if IsPedActiveInScenario(ped) then return true end
        Wait(50)
    end
    return IsPedActiveInScenario(ped)
end

local function startFallbackButcherScenario(ped, scenarioName)
    if not scenarioName or scenarioName == '' then return false end
    ClearPedTasksImmediately(ped)
    local ok = pcall(function()
        TaskStartScenarioInPlace(ped, hash(scenarioName), -1, true, false, false, false)
    end)
    if not ok then return false end

    local timeout = GetGameTimer() + 3000
    while GetGameTimer() < timeout do
        if IsPedActiveInScenario(ped) then return true end
        Wait(50)
    end
    return IsPedActiveInScenario(ped)
end

local function cutTableChicken(site)
    if not Mission.tableChicken or not DoesEntityExist(Mission.tableChicken) or not Mission.tableDead then return false end
    if not site or not site.table then return false end

    local ped = PlayerPedId()
    local step = Config.ProcessStation.steps.cut
    local cfg = Config.ButcherScenario or {}
    spawnCutStationObject(site)

    local tableCoords = getCutTableCoords(site)
    if not tableCoords then return false end

    local chickenCoords = GetEntityCoords(Mission.tableChicken)
    local spot = getCutWorkspot(site, chickenCoords)
    if spot then
        -- Measured workspot: on the ground at the long edge, facing the bird.
        moveToCutWorkspot(ped, spot)
    else
        local tableEnt = CutStationObjects[site.id] and CutStationObjects[site.id].table or nil
        local sc = site.scenario or {}
        local o = sc.offset or { x = -0.15, y = -1.22, z = 0.0 }

        local standCoords = nil
        if tableEnt and DoesEntityExist(tableEnt) then
            standCoords = GetOffsetFromEntityInWorldCoords(tableEnt, o.x or -0.15, o.y or -1.22, o.z or 0.0)
        else
            standCoords = getCutScenarioCoords(site)
        end
        if not standCoords then return false end

        -- Position player firmly on the ground in front of the table
        ClearPedTasksImmediately(ped)
        FreezeEntityPosition(ped, false)

        local curPos = GetEntityCoords(ped)
        -- Probe ground height at the player's stand location outside the table
        local foundPedGround, pedGroundZ = GetGroundZFor_3dCoord(
            standCoords.x, standCoords.y, tableCoords.z + 1.5, false)
        if not foundPedGround or not pedGroundZ or pedGroundZ <= 0.0 or pedGroundZ > (tableCoords.z + 0.35) then
            foundPedGround, pedGroundZ = GetGroundZFor_3dCoord(
                standCoords.x, standCoords.y, tableCoords.z + 0.5, false)
        end
        if not foundPedGround or not pedGroundZ or pedGroundZ <= 0.0 or pedGroundZ > (tableCoords.z + 0.35) then
            pedGroundZ = tableCoords.z
        end

        -- In RDR2, a ped's center-of-mass (root) is ~0.98m above its feet/ground level.
        local standZ = pedGroundZ + 0.98
        if curPos.z >= (pedGroundZ + 0.6) and curPos.z <= (pedGroundZ + 1.3) then
            standZ = curPos.z
        end

        if sc.standZOffset then
            standZ = standZ + sc.standZOffset
        elseif sc.offset and sc.offset.z and sc.offset.z ~= 0.0 then
            standZ = standZ + sc.offset.z
        end

        local targetHeading = GetHeadingFromVector_2d(
            chickenCoords.x - standCoords.x, chickenCoords.y - standCoords.y)

        SetEntityCoordsNoOffset(ped, standCoords.x, standCoords.y, standZ, false, false, false)
        SetEntityHeading(ped, targetHeading)
        -- NEVER call PlaceEntityOnGroundProperly here: it snaps the player up onto the table collision!
        Wait(50)
    end
    FreezeEntityPosition(ped, true)
    local preWait = step.preScenarioWait or cfg.PreScenarioWait or 300
    if preWait > 0 then Wait(preWait) end

    local total = step.time or cfg.ScenarioWait or 7000
    notify(Config.Text.cuttingChicken or 'جاري تقطيع وتجهيز لحم الدجاج...', total)

    -- Play authentic butcher knife cutting animation at the table
    -- v3.3.0: the bird on the table is visibly cut (whole -> plucked -> pieces).
    JRSChickenAnim.PlayTableCut(chickenCoords, total, Mission.tableChicken, spot and spot.chickenHeading)

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    deleteEntitySafe(Mission.tableChicken)
    Mission.tableChicken = nil
    Mission.tableDead = false
    if Mission.testMode then
        local nextProcessed = math.min((Mission.processed or 0) + 1, Config.ChickensRequired)
        CreateThread(function()
            Wait(50)
            TriggerEvent('jrs_chicken_job:client:productsGranted', nextProcessed, true)
        end)
    else
        TriggerServerEvent('jrs_chicken_job:server:grantProducts')
    end
    return true
end

local function spawnBasinGround(site)
    if Mission.chestProp and DoesEntityExist(Mission.chestProp) then return true end
    local basin = Config.Basin or {}
    local ok, model = requestModel(basin.model or 'p_washbasin01x')
    if not ok then return false end

    local spawnZ = site.chest.z
    local foundGround, groundZ = GetGroundZFor_3dCoord(site.chest.x, site.chest.y, site.chest.z + 10.0, false)
    if not foundGround or not groundZ or groundZ <= 0.0 then
        foundGround, groundZ = GetGroundZFor_3dCoord(site.chest.x, site.chest.y, site.chest.z + 2.0, false)
    end
    if foundGround and groundZ and groundZ > 0.0 then
        spawnZ = groundZ
    end

    Mission.chestProp = CreateObject(model, site.chest.x, site.chest.y, spawnZ, true, true, false)
    SetEntityAsMissionEntity(Mission.chestProp, true, true)
    SetEntityHeading(Mission.chestProp, basin.groundHeading or 0.0)
    SetEntityCoordsNoOffset(Mission.chestProp, site.chest.x, site.chest.y, spawnZ, false, false, false)
    pcall(function() PlaceObjectOnGroundProperly(Mission.chestProp) end)
    FreezeEntityPosition(Mission.chestProp, true)
    SetModelAsNoLongerNeeded(model)
    return true
end

local function pickupBasin()
    if not Mission.chestProp or not DoesEntityExist(Mission.chestProp) or Mission.carryingChest then return false end
    FreezeEntityPosition(Mission.chestProp, false)
    SetEntityCollision(Mission.chestProp, false, false)
    if not JRSChickenAnim.PickupAndCarry(Mission.chestProp, 'basin') then return false end
    Mission.carryingChest = true
    Mission.chestOnWagon = false
    return true
end

local function loadBasinOnWagon()
    if not Mission.carryingChest or not Mission.chestProp or not DoesEntityExist(Mission.chestProp) then return false end
    if not Mission.wagon or not DoesEntityExist(Mission.wagon) then return false end

    local ent = Mission.chestProp
    JRSChickenAnim.PutDown(ent, GetEntityCoords(Mission.wagon))
    local o = (Config.Basin and Config.Basin.wagonAttach) or { x = 0.0, y = -1.35, z = 1.05, rx = 0.0, ry = 0.0, rz = 0.0 }
    SetEntityInvincible(ent, true)
    pcall(SetEntityCanBeDamaged, ent, false)
    pcall(SetEntityProofs, ent, true, true, true, true, true, true, true, true)
    SetEntityCollision(ent, false, false)
    pcall(SetEntityCompletelyDisableCollision, ent, false, false)
    pcall(SetEntityDynamic, ent, false)
    SetEntityHasGravity(ent, false)
    FreezeEntityPosition(ent, false)

    AttachEntityToEntity(ent, Mission.wagon, 0,
        o.x or 0.0, o.y or -1.35, o.z or 1.05,
        o.rx or 0.0, o.ry or 0.0, o.rz or 0.0,
        false, false, false, false, 2, true, false, false)

    Mission.carryingChest = false
    Mission.chestOnWagon = true
    if not Mission.testMode then TriggerServerEvent('jrs_chicken_job:server:chestOnWagon') end
    return true
end

local function unloadBasinFromWagon()
    if not Mission.chestOnWagon then return false end
    if not Mission.wagon or not DoesEntityExist(Mission.wagon) then return false end

    -- Re-create chestProp if it was culled or lost during long travel
    if not Mission.chestProp or not DoesEntityExist(Mission.chestProp) then
        local basin = Config.Basin or {}
        local ok, model = requestModel(basin.model or 'p_washbasin01x')
        if ok then
            local pos = GetEntityCoords(Mission.wagon)
            Mission.chestProp = CreateObject(model, pos.x, pos.y, pos.z, true, true, false)
            SetEntityAsMissionEntity(Mission.chestProp, true, true)
            SetModelAsNoLongerNeeded(model)
        end
    end

    local ent = Mission.chestProp
    if ent and DoesEntityExist(ent) then
        DetachEntity(ent, true, true)
        SetEntityCollision(ent, false, false)
        if not JRSChickenAnim.PickupAndCarry(ent, 'basin') then return false end
    end
    Mission.carryingChest = true
    Mission.chestOnWagon = false
    return true
end

local function deliverBasin(fromWagon)
    if fromWagon then
        -- Direct drop/delivery at drop point from wagon or on foot
        if Mission.chestProp and DoesEntityExist(Mission.chestProp) then
            deleteEntitySafe(Mission.chestProp)
            Mission.chestProp = nil
        end
        Mission.chestOnWagon = false
        Mission.carryingChest = false
        if Mission.testMode then
            notify('TEST MODE: delivery stage completed.', 6000)
        else
            TriggerServerEvent('jrs_chicken_job:server:complete')
        end
        return true
    end

    if not Mission.carryingChest then return false end
    if Mission.chestProp and DoesEntityExist(Mission.chestProp) then
        JRSChickenAnim.PutDown(Mission.chestProp, Mission.delivery)
        FreezeEntityPosition(Mission.chestProp, true)
    end
    Mission.carryingChest = false
    if Mission.testMode then
        notify('TEST MODE: delivery stage completed.', 6000)
    else
        TriggerServerEvent('jrs_chicken_job:server:complete')
    end
    return true
end

local function cleanupMission()
    -- Prompts are persistent UI handles in RedM. Hide them first so a mission
    -- cancel/restart can never leave the last interaction prompt on screen.
    hideAllPrompts()
    clearObjectiveBlip()
    clearWagonBlip()
    LocalPlayer.state:set('isChickenJob', false, false)
    if JRSChickenAnim and JRSChickenAnim.carrying then JRSChickenAnim.ReleaseCarry(JRSChickenAnim.carrying) end
    if JRSChickenAnim and JRSChickenAnim.ClearSlaughterKnife then JRSChickenAnim.ClearSlaughterKnife() end
    if JRSChickenAnim and JRSChickenAnim.ClearCutProps then JRSChickenAnim.ClearCutProps() end
    clearChickenBlips()
    for _, e in ipairs(Mission.chickens) do deleteEntitySafe(e) end
    for _, e in ipairs(Mission.wagonChickens) do deleteEntitySafe(e) end
    deleteEntitySafe(Mission.carriedChicken)
    deleteEntitySafe(Mission.groundDeadChicken)
    deleteEntitySafe(Mission.tableChicken)
    deleteEntitySafe(Mission.chestProp)
    if Mission.wagonTraps then
        for _, t in ipairs(Mission.wagonTraps) do
            local ent = type(t) == 'table' and t.entity or t
            deleteEntitySafe(ent)
        end
    end
    deleteEntitySafe(Mission.wagonTrap)
    deleteEntitySafe(Mission.wagon)
    ClearPedTasksImmediately(PlayerPedId())

    Mission = {
        active = false, stage = 'idle', hub = nil, catchZone = nil, delivery = nil,
        wagon = nil, wagonTrap = nil, wagonTraps = {}, chickens = {}, chickenBlips = {}, wagonChickens = {}, carriedChicken = nil,
        carriedChickenDead = false, tableChicken = nil, groundDeadChicken = nil, tableDead = false,
        caught = 0, processed = 0, chestProp = nil, chestOnWagon = false,
        carryingChest = false, objectiveBlip = nil, wagonBlip = nil, testMode = false,
        waitProductStart = nil, waitCompleteStart = nil,
    }
end

local TEST_STAGE_ALIASES = {
    wagon = 'wagon',
    catch_travel = 'catch_travel',
    catch = 'catching',
    catching = 'catching',
    butcher_travel = 'butcher_travel',
    butcher = 'butcher_unload',
    butcher_unload = 'butcher_unload',
    -- /chicken_test kill starts at the wagon cage with all 5 chickens.
    -- The player removes each chicken manually, then the normal flow advances
    -- to kill_carried -> pickup_dead -> cutting.
    kill = 'butcher_unload',
    kill_carried = 'kill_carried',
    pickup_dead = 'pickup_dead_ground',
    pickup_dead_ground = 'pickup_dead_ground',
    carry_dead = 'dead_to_cut',
    dead_to_cut = 'dead_to_cut',
    cut = 'cut',
    basin = 'pickup_chest',
    pickup_chest = 'pickup_chest',
    load_basin = 'load_chest',
    load_chest = 'load_chest',
    delivery = 'delivery',
    delivery_carry = 'delivery_carry',
}

local TEST_STAGE_LIST = {
    'wagon', 'catch_travel', 'catch', 'butcher_travel', 'butcher',
    'kill', 'pickup_dead', 'carry_dead', 'cut', 'basin',
    'load_basin', 'delivery', 'delivery_carry'
}

local function testTeleport(coords, heading)
    if not Config.TestMode or Config.TestMode.teleportPlayer == false or not coords then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        TaskLeaveAnyVehicle(ped, 0, 0)
        Wait(500)
    end
    SetEntityCoordsNoOffset(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.15, false, false, false)
    if heading then SetEntityHeading(ped, heading + 0.0) end
end

local function testSpawnChicken(coords, heading, dead)
    local ok, model = requestModel(Config.Chicken.model)
    if not ok then return nil end
    local z = findGroundZ(coords.x, coords.y, coords.z)
    local chicken = CreatePed(model, coords.x, coords.y, z, heading or 0.0, true, true, false, false)
    if not chicken or chicken == 0 or not DoesEntityExist(chicken) then
        SetModelAsNoLongerNeeded(model)
        return nil
    end

    SetEntityAsMissionEntity(chicken, true, true)
    pcall(function() Citizen.InvokeNative(0x283978A15512B2FE, chicken, true) end)
    SetEntityVisible(chicken, true)
    SetEntityAlpha(chicken, 255, false)
    SetBlockingOfNonTemporaryEvents(chicken, true)
    SetEntityCoordsNoOffset(chicken, coords.x, coords.y, z, false, false, false)
    pcall(function() PlaceEntityOnGroundProperly(chicken) end)

    if dead then
        SetEntityInvincible(chicken, false)
        pcall(function() SetEntityHealth(chicken, 0, 0) end)
        Wait(50)
        if not IsEntityDead(chicken) then pcall(function() ApplyDamageToPed(chicken, 1000, false, true, 0) end) end
        Wait(100)
    else
        SetEntityInvincible(chicken, true)
        TaskStandStill(chicken, -1)
    end

    SetModelAsNoLongerNeeded(model)
    return chicken
end

local function testSpawnWagonChickens(count)
    if not Mission.wagon or not DoesEntityExist(Mission.wagon) then return false end
    count = math.max(1, math.min(tonumber(count) or 1, Config.Wagon.maxChickens or Config.ChickensRequired))
    for i = 1, count do
        local wpos = GetEntityCoords(Mission.wagon)
        local chicken = testSpawnChicken(vector3(wpos.x, wpos.y, wpos.z + 0.5), GetEntityHeading(Mission.wagon), false)
        if chicken then
            local o = getWagonChickenOffset(i)
            local parent = getWagonChickenParent(i)
            SetEntityInvincible(chicken, true)
            pcall(SetEntityCanBeDamaged, chicken, false)
            pcall(SetEntityProofs, chicken, true, true, true, true, true, true, true, true)
            SetEntityCollision(chicken, false, false)
            pcall(SetEntityCompletelyDisableCollision, chicken, false, false)
            pcall(SetEntityDynamic, chicken, false)
            SetEntityHasGravity(chicken, false)
            FreezeEntityPosition(chicken, false)
            AttachEntityToEntity(chicken, parent, 0,
                o.x, o.y, o.z, o.rx, o.ry, o.rz,
                false, false, false, false, 2, true, false, false)
            Mission.wagonChickens[#Mission.wagonChickens + 1] = chicken
        end
    end
    Mission.caught = #Mission.wagonChickens
    return #Mission.wagonChickens > 0
end

local function testCarryChicken(dead)
    local ped = PlayerPedId()
    local p = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.9, 0.0)
    local chicken = testSpawnChicken(p, GetEntityHeading(ped), dead == true)
    if not chicken then return false end

    SetEntityCollision(chicken, false, false)
    FreezeEntityPosition(chicken, false)
    local carryType = dead and 'deadChicken' or 'liveChicken'
    if not JRSChickenAnim.PickupAndCarry(chicken, carryType) then
        deleteEntitySafe(chicken)
        return false
    end
    Mission.carriedChicken = chicken
    Mission.carriedChickenDead = dead == true
    return true
end

local function setupTestMission(requestedStage, hubId)
    local cfg = Config.TestMode or {}
    if cfg.enabled ~= true then
        notify('Chicken Test Mode is disabled. Set Config.TestMode.enabled = true.', 8000)
        return false
    end

    local stage = TEST_STAGE_ALIASES[string.lower(tostring(requestedStage or ''))]
    if not stage then
        notify('Unknown test stage. Use /chicken_test list', 7000)
        print('[jrs_chicken_job] Test stages: ' .. table.concat(TEST_STAGE_LIST, ', '))
        return false
    end

    local hub = Config.GetJobHub(hubId or cfg.defaultHub or 'valentine')
    if not hub then
        notify(('Unknown chicken hub: %s'):format(tostring(hubId)), 7000)
        return false
    end

    -- If a real mission is active, tell the server before switching into the
    -- completely local/no-reward test session.
    if Mission.active and not Mission.testMode then
        TriggerServerEvent('jrs_chicken_job:server:cancel')
    end
    cleanupMission()

    Mission.active = true
    Mission.testMode = true
    LocalPlayer.state:set('isChickenJob', true, false)
    Mission.hub = hub
    Mission.catchZone = hub.catchZones[1]
    Mission.delivery = hub.deliveryPoints[1]
    Mission.stage = stage

    local site = getButcherSite(hub.butcherSiteId)
    local cutSite = getCutSite(hub.cutSiteId or hub.butcherSiteId)
    if not site or not cutSite then
        notify('TEST MODE: processing site is missing.', 7000)
        cleanupMission()
        return false
    end
    spawnCutStationObject(cutSite)

    local function getTestWagonHeading(fallbackHeading)
        local headings = cfg.wagonHeadings or {}
        local configured = headings[hub.id]
        if configured ~= nil then return configured + 0.0 end
        if fallbackHeading ~= nil then return fallbackHeading + 0.0 end
        if hub.wagonSpawn and hub.wagonSpawn.w then return hub.wagonSpawn.w + 0.0 end
        return 0.0
    end

    local function spawnTestWagonAt(coords, heading)
        local finalHeading = getTestWagonHeading(heading)
        local c = vector4(coords.x, coords.y, coords.z, finalHeading)
        return spawnWagon(c)
    end

    if stage == 'wagon' then
        if not spawnWagon() then cleanupMission() return false end
        local wp = GetEntityCoords(Mission.wagon)
        setObjective(Config.ObjectiveBlips.wagon, wp, 'TEST: Chicken Wagon')
        testTeleport(vector3(wp.x + 2.0, wp.y + 2.0, wp.z), GetEntityHeading(Mission.wagon))

    elseif stage == 'catch_travel' then
        if not spawnWagon() then cleanupMission() return false end
        setObjective(Config.ObjectiveBlips.catch, Mission.catchZone, 'TEST: Catch Chickens')
        local wp = GetEntityCoords(Mission.wagon)
        testTeleport(vector3(wp.x + 2.0, wp.y + 2.0, wp.z), GetEntityHeading(Mission.wagon))

    elseif stage == 'catching' then
        local wc = vector3(Mission.catchZone.x + 5.0, Mission.catchZone.y + 2.0, Mission.catchZone.z)
        spawnTestWagonAt(wc, Mission.catchZone.w or 0.0)
        testTeleport(vector3(Mission.catchZone.x, Mission.catchZone.y, Mission.catchZone.z), Mission.catchZone.w or 0.0)
        if not spawnChickens() then cleanupMission() return false end
        clearGpsObjective()

    elseif stage == 'butcher_travel' then
        local wc = vector3(site.wagonStation.x + 18.0, site.wagonStation.y, site.wagonStation.z)
        if not spawnTestWagonAt(wc, nil) then cleanupMission() return false end
        testSpawnWagonChickens(Config.ChickensRequired)
        Mission.caught = Config.ChickensRequired
        setObjective(Config.ObjectiveBlips.process, site.wagonStation, 'TEST: Butcher')
        testTeleport(vector3(wc.x + 2.0, wc.y + 2.0, wc.z), GetEntityHeading(Mission.wagon))

    elseif stage == 'butcher_unload' then
        if not spawnTestWagonAt(site.wagonStation, nil) then cleanupMission() return false end
        -- Test the real slaughter loop: all five chickens start inside the
        -- p_trap01x cage and the player must take them out one at a time.
        testSpawnWagonChickens(Config.ChickensRequired)
        Mission.caught = Config.ChickensRequired
        Mission.processed = math.max(0, Config.ChickensRequired - 1)
        local wp = GetEntityCoords(Mission.wagon)
        testTeleport(vector3(wp.x + 1.5, wp.y + 1.5, wp.z), GetEntityHeading(Mission.wagon))

    elseif stage == 'kill_carried' then
        if not spawnTestWagonAt(site.wagonStation, nil) then cleanupMission() return false end
        Mission.caught = Config.ChickensRequired
        Mission.processed = math.max(0, Config.ChickensRequired - 1)
        local wp = GetEntityCoords(Mission.wagon)
        testTeleport(vector3(wp.x + 2.0, wp.y + 1.0, wp.z), GetEntityHeading(Mission.wagon))
        if not testCarryChicken(false) then cleanupMission() return false end

    elseif stage == 'pickup_dead_ground' then
        Mission.caught = Config.ChickensRequired
        Mission.processed = math.max(0, Config.ChickensRequired - 1)
        local cp = getCutTableCoords(cutSite) or site.wagonStation
        testTeleport(vector3(cp.x + 2.0, cp.y + 2.0, cp.z), cutSite.table.coords.w or 0.0)
        local ped = PlayerPedId()
        local p = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, 0.0)
        Mission.groundDeadChicken = testSpawnChicken(p, GetEntityHeading(ped), true)
        if Mission.groundDeadChicken then FreezeEntityPosition(Mission.groundDeadChicken, true) end

    elseif stage == 'dead_to_cut' then
        Mission.caught = Config.ChickensRequired
        Mission.processed = math.max(0, Config.ChickensRequired - 1)
        local cp = getCutTableCoords(cutSite)
        testTeleport(vector3(cp.x + 2.0, cp.y + 2.0, cp.z), cutSite.table.coords.w or 0.0)
        if not testCarryChicken(true) then cleanupMission() return false end
        setObjective(Config.ObjectiveBlips.process, cp, 'TEST: Chicken Cutting Table')

    elseif stage == 'cut' then
        Mission.caught = Config.ChickensRequired
        Mission.processed = math.max(0, Config.ChickensRequired - 1)
        spawnCutStationObject(cutSite)
        local cp = getCutTableCoords(cutSite)
        local spot = getCutWorkspot(cutSite, GetEntityCoords(PlayerPedId()))
        if spot then
            testTeleport(spot.stand, spot.heading)
        else
            local scp = getCutScenarioCoords(cutSite) or cp
            testTeleport(scp, (cutSite.table.coords.w or 0.0) + ((cutSite.scenario and cutSite.scenario.headingOffset) or 0.0))
        end
        local chicken = testSpawnChicken(vector3(cp.x, cp.y, cp.z + 0.5), cutSite.table.coords.w or 0.0, true)
        if not chicken or not setDeadChickenOnCutTable(chicken, cutSite) then cleanupMission() return false end
        Mission.tableChicken = chicken
        Mission.tableDead = true

    elseif stage == 'pickup_chest' then
        Mission.caught = Config.ChickensRequired
        Mission.processed = Config.ChickensRequired
        spawnBasinGround(site)
        setObjective(Config.ObjectiveBlips.chest, site.chest, 'TEST: Products')
        testTeleport(vector3(site.chest.x + 1.0, site.chest.y + 1.0, site.chest.z), 0.0)

    elseif stage == 'load_chest' then
        Mission.caught = Config.ChickensRequired
        Mission.processed = Config.ChickensRequired
        local wc = vector3(site.chest.x + 2.0, site.chest.y, site.chest.z)
        if not spawnTestWagonAt(wc, nil) then cleanupMission() return false end
        spawnBasinGround(site)
        testTeleport(vector3(site.chest.x + 0.5, site.chest.y + 0.5, site.chest.z), 0.0)
        if not pickupBasin() then cleanupMission() return false end

    elseif stage == 'delivery' then
        Mission.caught = Config.ChickensRequired
        Mission.processed = Config.ChickensRequired
        local wc = vector3(Mission.delivery.x + 8.0, Mission.delivery.y, Mission.delivery.z)
        if not spawnTestWagonAt(wc, nil) then cleanupMission() return false end
        local fakeSite = { chest = wc }
        if not spawnBasinGround(fakeSite) then cleanupMission() return false end
        local ent = Mission.chestProp
        local o = (Config.Basin and Config.Basin.wagonAttach) or { x = 0.0, y = -1.35, z = 1.05, rx = 0.0, ry = 0.0, rz = 0.0 }
        AttachEntityToEntity(ent, Mission.wagon, 0,
            o.x or 0.0, o.y or -1.35, o.z or 1.05,
            o.rx or 0.0, o.ry or 0.0, o.rz or 0.0,
            false, false, false, false, 2, true, false, false)
        SetEntityCollision(ent, false, false)
        FreezeEntityPosition(ent, false)
        Mission.chestOnWagon = true
        Mission.carryingChest = false
        setObjective(Config.ObjectiveBlips.delivery, Mission.delivery, 'TEST: Delivery')
        testTeleport(vector3(wc.x + 1.5, wc.y + 1.5, wc.z), 0.0)

    elseif stage == 'delivery_carry' then
        Mission.caught = Config.ChickensRequired
        Mission.processed = Config.ChickensRequired
        local bp = vector3(Mission.delivery.x + 2.0, Mission.delivery.y, Mission.delivery.z)
        local fakeSite = { chest = bp }
        if not spawnBasinGround(fakeSite) then cleanupMission() return false end
        testTeleport(vector3(bp.x, bp.y, bp.z), 0.0)
        if not pickupBasin() then cleanupMission() return false end
        setObjective(Config.ObjectiveBlips.delivery, Mission.delivery, 'TEST: Delivery')
    end

    notify(('TEST MODE: %s [%s]'):format(tostring(requestedStage), hub.id), 7000)
    print(('[jrs_chicken_job] TEST stage=%s hub=%s'):format(stage, hub.id))
    return true
end

local function failMission(reason)
    if not Mission.active then return end
    if not Mission.testMode then TriggerServerEvent('jrs_chicken_job:server:fail', reason) end
    if reason == 'wagon_destroyed' then
        notify(Config.Text.wagonDestroyed or 'تم تدمير العربة! فشلت مهمة الدجاج.')
    elseif reason == 'draft_horse_dead' then
        notify(Config.Text.horseDead or 'مات حصان العربة! فشلت مهمة الدجاج.')
    else
        notify(Config.Text.missionFailed or 'فشلت مهمة الدجاج.')
    end
    cleanupMission()
end

RegisterNetEvent('jrs_chicken_job:client:startDenied', function(reason, arg1, arg2)
    if reason == 'job' then
        notify(Config.Text.noJob or 'يجب أن تعمل بوظيفة عامل دواجن (chicken) للبدء.')
    elseif reason == 'level' then
        local required = arg2 or (Config.JobCheck and Config.JobCheck.minLevel) or 25
        local current = arg1 or 1
        local msg = (Config.Text.levelRequired and Config.Text.levelRequired:format(tostring(required), tostring(current)))
            or ('مستواك غير كافٍ. يتطلب هذا العمل المستوى %s فما فوق (مستواك الحالي: %s)'):format(tostring(required), tostring(current))
        notify(msg, 7000)
    elseif reason == 'cooldown' then
        local mins = math.max(1, math.ceil((tonumber(arg1) or 0) / 60000))
        local msg = (Config.Text.cooldownTime and Config.Text.cooldownTime:format(mins))
            or (('%s (%d دقيقة)'):format(Config.Text.cooldown or 'يجب عليك الانتظار قبل بدء مهمة أخرى', mins))
        notify(msg, 6000)
    else
        notify(Config.Text.activeMission or 'لديك مهمة دجاج نشطة بالفعل.')
    end
end)

RegisterNetEvent('jrs_chicken_job:client:startApproved', function(hubId, catchIndex, deliveryIndex)
    if Mission.active then return end
    Mission.active = true
    LocalPlayer.state:set('isChickenJob', true, false)
    Mission.hub = Config.GetJobHub(hubId)
    Mission.catchZone = Mission.hub.catchZones[catchIndex]
    Mission.delivery = Mission.hub.deliveryPoints[deliveryIndex]
    Mission.stage = 'wagon'
    if not spawnWagon() then
        failMission('wagon_spawn_failed')
        return
    end
    setObjective(Config.ObjectiveBlips.wagon, GetEntityCoords(Mission.wagon), 'Chicken Wagon')
    notify(Config.Text.goWagon)
end)

RegisterNetEvent('jrs_chicken_job:client:productsGranted', function(processed, ok)
    if not Mission.active then return end
    Mission.waitProductStart = nil
    Mission.processed = processed
    if not ok then notify(Config.Text.inventoryError) end

    if Mission.processed >= Config.ChickensRequired then
        local site = getButcherSite(Mission.hub.butcherSiteId)
        spawnBasinGround(site)
        Mission.stage = 'pickup_chest'
        setObjective(Config.ObjectiveBlips.chest, site.chest, 'Products')
        notify(Config.Text.pickupChest or Config.Text.loadChest)
    else
        local site = getButcherSite(Mission.hub.butcherSiteId)
        Mission.stage = 'butcher_unload'
        if site then setObjective(Config.ObjectiveBlips.process, site.wagonStation, 'Chicken Wagon') end
        notify(Config.Text.nextChicken or 'عد إلى العربة وأنزل الدجاجة التالية.')
    end
end)

RegisterNetEvent('jrs_chicken_job:client:completed', function(payment)
    Mission.waitCompleteStart = nil
    local formatted = type(payment) == 'number' and string.format('%.2f', payment) or tostring(payment or 0)
    notify(('%s $%s'):format(Config.Text.complete, formatted))
    cleanupMission()
end)

RegisterNetEvent('jrs_chicken_job:client:completeDenied', function()
    Mission.waitCompleteStart = nil
    notify(Config.Text.missionFailed or 'فشلت مهمة الدجاج.')
    cleanupMission()
end)

local function updateClientJob(newJob)
    if type(newJob) == 'table' then
        newJob = newJob.job or newJob.name
    end
    CurrentJob = normalizeJob(newJob)

    if Mission.active and not hasRequiredJob() then
        notify(Config.Text.jobChanged or 'تم إلغاء مهمة الدجاج لتغيير وظيفتك.', 6000)
        TriggerServerEvent('jrs_chicken_job:server:cancel')
        cleanupMission()
    end

    updateHubBlips()
end

CreateThread(function()
    local startLabel = (Config.Prompts and Config.Prompts.start) or 'Start Chicken Job'
    local interactLabel = (Config.Prompts and Config.Prompts.interact) or 'Interact'
    StartPrompt = promptCreate(startLabel)
    InteractPrompt = promptCreate(interactLabel)
    promptShow(StartPrompt, startLabel, false)
    promptShow(InteractPrompt, interactLabel, false)

    for _, hub in ipairs(Config.JobHubs or {}) do spawnHubNPC(hub) end
    spawnAllCutStations()

    Wait(500)
    TriggerServerEvent('jrs_chicken_job:server:requestJob')
    Wait(500)
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.Job then
        updateClientJob(LocalPlayer.state.Job)
    else
        updateHubBlips()
    end
end)

RegisterNetEvent('jrs_chicken_job:client:setJob', function(job)
    updateClientJob(job)
end)

RegisterNetEvent('jrs_chicken_job:client:cancelMission', function()
    if Mission.active then
        notify(Config.Text.jobChanged or 'تم إلغاء مهمة الدجاج لتغيير وظيفتك.', 6000)
        cleanupMission()
    end
end)

RegisterNetEvent('jrs_core:client:jobChanged', function(job, grade)
    updateClientJob(job)
end)

RegisterNetEvent('jrs_core:client:setJob', function(data)
    updateClientJob(data)
end)

RegisterNetEvent('jrs_core:getPlayerJob', function(data)
    updateClientJob(data)
end)

RegisterNetEvent('jrs_core:client:characterLoaded', function()
    CreateThread(function()
        Wait(1000)
        TriggerServerEvent('jrs_chicken_job:server:requestJob')
    end)
end)

AddStateBagChangeHandler('Job', nil, function(bagName, key, value)
    local myServerId = GetPlayerServerId(PlayerId())
    local isMe = (bagName == ('player:%s'):format(myServerId))
    if not isMe and GetPlayerFromStateBagName then
        local p = GetPlayerFromStateBagName(bagName)
        if p == PlayerId() then isMe = true end
    end
    if isMe then
        updateClientJob(value)
    end
end)

-- Dynamic Hub NPC streaming watchdog: ensures NPCs spawn when player is near and despawn cleanly when far
CreateThread(function()
    while true do
        Wait(1000)
        if Config.Features.npc then
            local player = PlayerPedId()
            if player and player ~= 0 and DoesEntityExist(player) then
                local p = GetEntityCoords(player)
                local streamDist = 80.0
                local despawnDist = 120.0
                for _, hub in ipairs(Config.JobHubs or {}) do
                    if hub.npc and hub.npc.coords then
                        local d = dist(p, hub.npc.coords)
                        if d <= streamDist then
                            if not HubNPCs[hub.id] or not DoesEntityExist(HubNPCs[hub.id]) or IsEntityDead(HubNPCs[hub.id]) then
                                spawnHubNPC(hub)
                            end
                        elseif d > despawnDist then
                            if HubNPCs[hub.id] and DoesEntityExist(HubNPCs[hub.id]) then
                                despawnHubNPC(hub.id)
                            end
                        end
                    end
                end

                for _, site in ipairs(Config.CutStations or {}) do
                    if site.table and site.table.spawn ~= false and site.table.coords then
                        local sc = site.table.coords
                        local sd = dist(p, sc)
                        if sd <= 120.0 then
                            local current = CutStationObjects[site.id]
                            if not current or not current.table or not DoesEntityExist(current.table) then
                                spawnCutStationObject(site)
                            else
                                -- Verify table is resting on the real ground once upon spawn
                                if not current.groundSettled then
                                    local tbl = current.table
                                    local curZ = GetEntityCoords(tbl).z
                                    local fGround, realGroundZ = GetGroundZFor_3dCoord(sc.x, sc.y, curZ + 5.0, false)
                                    if fGround and realGroundZ and realGroundZ > 0.0 then
                                        local targetZ = realGroundZ - 0.05
                                        if math.abs(curZ - targetZ) > 0.10 then
                                            SetEntityCoordsNoOffset(tbl, sc.x, sc.y, targetZ, false, false, false)
                                            if current.board and DoesEntityExist(current.board) then
                                                local o = (site.table.cuttingBoard and site.table.cuttingBoard.offset) or { x = 0.0, y = 0.0, z = 0.82, headingOffset = 0.0 }
                                                local bp = offsetFromHeading(vector3(sc.x, sc.y, targetZ), GetEntityHeading(tbl), o.x, o.y, o.z)
                                                SetEntityCoordsNoOffset(current.board, bp.x, bp.y, bp.z, false, false, false)
                                            end
                                        end
                                        current.groundSettled = true
                                    end
                                end
                            end
                        elseif sd > 160.0 then
                            local current = CutStationObjects[site.id]
                            if current and current.table and DoesEntityExist(current.table) then
                                if current.board and DoesEntityExist(current.board) then deleteEntitySafe(current.board) end
                                deleteEntitySafe(current.table)
                                CutStationObjects[site.id] = nil
                            end
                        end
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1200
        local shown = false
        if not Mission.active then
            local p = GetEntityCoords(PlayerPedId())
            for _, hub in ipairs(Config.JobHubs or {}) do
                if dist(p, hub.npc.coords) <= 2.5 then
                    sleep = 0
                    if not HubNPCs[hub.id] or not DoesEntityExist(HubNPCs[hub.id]) or IsEntityDead(HubNPCs[hub.id]) then
                        spawnHubNPC(hub)
                    end
                    if hasRequiredJob() then
                        shown = true
                        promptShow(StartPrompt, (Config.Prompts and Config.Prompts.start) or 'Start Chicken Job', true)
                        if pressed(StartPrompt) then
                            TriggerServerEvent('jrs_chicken_job:server:requestStart', hub.id)
                            Wait(500)
                        end
                    else
                        shown = false
                        local now = GetGameTimer()
                        if now - lastJobWarn > 6000 then
                            lastJobWarn = now
                            notify(Config.Text.noJob or 'يجب أن تعمل بوظيفة عامل دواجن (chicken) للبدء.', 5000)
                        end
                    end
                    break
                end
            end
        end
        if not shown then promptShow(StartPrompt, (Config.Prompts and Config.Prompts.start) or 'Start Chicken Job', false) end
        Wait(sleep)
    end
end)

-- Dedicated protection watchdog: ensures all 3 cages and all wagon chickens stay attached no matter what happens
CreateThread(function()
    while true do
        Wait(500)
        if Mission.active and Mission.wagon and DoesEntityExist(Mission.wagon) then
            ensureWagonTrapsAttached()
            ensureWagonChickensAttached()
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 500

        if Mission.active then
            sleep = 0
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local shown = false
            local site = Mission.hub and getButcherSite(Mission.hub.butcherSiteId) or nil
            local cutSite = Mission.hub and getCutSite(Mission.hub.cutSiteId or Mission.hub.butcherSiteId) or nil
            local failed = false

            if not site or not cutSite then
                failMission('missing_processing_site')
                failed = true
            end

            if Config.JobCheck and Config.JobCheck.enabled and not hasRequiredJob() then
                notify(Config.Text.jobChanged or 'تم إلغاء مهمة الدجاج بسبب تغيير وظيفتك.', 6000)
                failMission('no_job')
                failed = true
            end

            if Config.Wagon.failMission.enabled and Mission.wagon and DoesEntityExist(Mission.wagon) then
                if IsEntityDead(Mission.wagon) or GetEntityHealth(Mission.wagon) < Config.Wagon.failMission.minBodyHealth then
                    failMission('wagon_destroyed')
                    failed = true
                elseif GetPedInDraftHarness then
                    local harnessSlots = Config.Wagon.failMission.harnessSlots or 4
                    for slot = 0, harnessSlots - 1 do
                        local horse = GetPedInDraftHarness(Mission.wagon, slot)
                        if horse and horse ~= 0 and DoesEntityExist(horse) and IsEntityDead(horse) then
                            failMission('draft_horse_dead')
                            failed = true
                            break
                        end
                    end
                end
            end

            if not failed and site and cutSite then
                if Mission.stage == 'wagon' then
                    drawMarker(GetEntityCoords(Mission.wagon))
                    if dist(pos, GetEntityCoords(Mission.wagon)) <= Config.Wagon.pickupDistance then
                        Mission.stage = 'catch_travel'
                        setObjective(Config.ObjectiveBlips.catch, vector3(Mission.catchZone.x, Mission.catchZone.y, Mission.catchZone.z), 'Catch Zone')
                        notify(Config.Text.goCatch)
                    end

                elseif Mission.stage == 'catch_travel' then
                    drawMarker(Mission.catchZone)
                    if dist(pos, Mission.catchZone) <= Config.Chicken.zoneTriggerRadius then
                        spawnChickens()
                    end
                    if dist(pos, Mission.catchZone) <= Config.Chicken.arrivalRadius then
                        if spawnChickens() then
                            Mission.stage = 'catching'
                            -- Clear the long-range map waypoint, but keep the objective blip so
                            -- the player still knows this is the active work area.
                            clearGpsObjective()
                            notify(Config.Text.catchStarted and Config.Text.catchStarted:format(Config.ChickensRequired) or ('أمسك بـ %d دجاجات. ترجل من العربة واقترب من الدجاج المحدد.'):format(Config.ChickensRequired), 7000)
                        end
                    end

                elseif Mission.stage == 'catching' then
                    for _, c in ipairs(Mission.chickens) do
                        if DoesEntityExist(c) then drawChickenMarker(c, pos) end
                    end

                    local carriedEnt = Citizen.InvokeNative(0xD806CD2A4F2C2996, ped, Citizen.ResultAsInteger())
                    if not Mission.carriedChicken and carriedEnt and carriedEnt ~= 0 and DoesEntityExist(carriedEnt) then
                        for _, c in ipairs(Mission.chickens) do
                            if c == carriedEnt then
                                Mission.carriedChicken = carriedEnt
                                Mission.carriedChickenDead = false
                                removeEntityFromList(Mission.chickens, carriedEnt)
                                removeChickenBlip(carriedEnt)
                                break
                            end
                        end
                    end

                    if Mission.carriedChicken or (carriedEnt and carriedEnt ~= 0) then
                        if Mission.wagon and dist(pos, GetEntityCoords(Mission.wagon)) <= Config.Wagon.loadDistance then
                            shown = true
                            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.loadChicken) or 'Load Chicken', true)
                            if pressed(InteractPrompt) then
                                if attachChickenToWagon() then
                                    if not Mission.testMode then TriggerServerEvent('jrs_chicken_job:server:chickenLoaded') end
                                    if Mission.caught >= Config.ChickensRequired then
                                        if not Mission.testMode then TriggerServerEvent('jrs_chicken_job:server:catchComplete') end
                                        Mission.stage = 'butcher_travel'
                                        setObjective(Config.ObjectiveBlips.process, site.wagonStation, 'Butcher')
                                        notify(Config.Text.goButcher)
                                    end
                                end
                                Wait(300)
                            end
                        end
                    else
                        local nearest, nearestD
                        for _, c in ipairs(Mission.chickens) do
                            if DoesEntityExist(c) then
                                local d = dist(pos, GetEntityCoords(c))
                                if not nearestD or d < nearestD then nearest, nearestD = c, d end
                            end
                        end
                        if nearest and nearestD <= Config.Chicken.catchDistance then
                            shown = true
                            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.catchChicken) or 'Catch Chicken', true)
                            if pressed(InteractPrompt) then
                                pickupLiveChicken(nearest)
                                Wait(300)
                            end
                        end
                    end

                elseif Mission.stage == 'butcher_travel' then
                    drawMarker(site.wagonStation)
                    local wcoords = Mission.wagon and DoesEntityExist(Mission.wagon) and GetEntityCoords(Mission.wagon)
                    local arrRadius = math.max(site.radius or 8.0, 7.0)
                    if (wcoords and dist(wcoords, site.wagonStation) <= arrRadius) or dist(pos, site.wagonStation) <= arrRadius then
                        Mission.stage = 'butcher_unload'
                        clearObjectiveBlip()
                    end

                elseif Mission.stage == 'butcher_unload' then
                    if Mission.processed >= Config.ChickensRequired then
                        spawnBasinGround(site)
                        Mission.stage = 'pickup_chest'
                    elseif #Mission.wagonChickens > 0 and Mission.wagon and dist(pos, GetEntityCoords(Mission.wagon)) <= ((Config.Wagon.unloadDistance or 4.0) + 1.0) then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.unloadChicken) or 'Unload Chicken', true)
                        if pressed(InteractPrompt) then
                            if takeChickenFromWagon() then
                                clearObjectiveBlip()
                                Mission.stage = 'kill_carried'
                                notify(Config.Text.killReady or 'احمل الدجاجة واذبحها أولاً قبل نقلها إلى طاولة التقطيع.')
                            end
                            Wait(300)
                        end
                    end

                elseif Mission.stage == 'kill_carried' then
                    -- Immediately after removing a LIVE chicken from the wagon,
                    -- G becomes the slaughter action. No table placement first.
                    if Mission.carriedChicken and not Mission.carriedChickenDead then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.killChicken) or 'Slaughter Chicken', true)
                        if pressed(InteractPrompt) then
                            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.killChicken) or 'Slaughter Chicken', false)
                            if killCarriedChickenOnGround(site) then
                                Mission.stage = 'pickup_dead_ground'
                                notify(Config.Text.pickupDeadReady or 'تم ذبح الدجاجة بنجاح! التقطها واحملها إلى طاولة التقطيع.')
                            end
                            Wait(300)
                        end
                    end

                elseif Mission.stage == 'pickup_dead_ground' then
                    local corpse = Mission.groundDeadChicken
                    local carriedEnt = Citizen.InvokeNative(0xD806CD2A4F2C2996, ped, Citizen.ResultAsInteger())
                    if carriedEnt and carriedEnt ~= 0 and (carriedEnt == corpse or (corpse and DoesEntityExist(corpse) and IsEntityAttachedToEntity(corpse, ped))) then
                        Mission.carriedChicken = corpse or carriedEnt
                        Mission.carriedChickenDead = true
                        Mission.groundDeadChicken = nil
                        Mission.stage = 'dead_to_cut'
                        local cutPos = getCutTableCoords(cutSite)
                        if cutPos then setObjective(Config.ObjectiveBlips.process, cutPos, cutSite.label or 'Chicken Cutting Table') end
                        notify(Config.Text.carryToCut or 'احمل الدجاجة المذبوحة إلى طاولة التقطيع.')
                    elseif corpse and DoesEntityExist(corpse) and dist(pos, GetEntityCoords(corpse)) <= 2.5 then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.pickupDeadChicken) or 'Pick Up Chicken', true)
                        if pressed(InteractPrompt) then
                            if pickupDeadChickenFromGround() then
                                Mission.stage = 'dead_to_cut'
                                local cutPos = getCutTableCoords(cutSite)
                                if cutPos then setObjective(Config.ObjectiveBlips.process, cutPos, cutSite.label or 'Chicken Cutting Table') end
                                notify(Config.Text.carryToCut or 'احمل الدجاجة المذبوحة إلى طاولة التقطيع.')
                            end
                            Wait(300)
                        end
                    end

                elseif Mission.stage == 'dead_to_cut' then
                    local carriedEnt = Citizen.InvokeNative(0xD806CD2A4F2C2996, ped, Citizen.ResultAsInteger())
                    if carriedEnt and carriedEnt ~= 0 and DoesEntityExist(carriedEnt) and not Mission.carriedChicken then
                        Mission.carriedChicken = carriedEnt
                        Mission.carriedChickenDead = true
                    end

                    local cutPos = getCutTableCoords(cutSite)
                    if cutPos then drawMarker(cutPos) end
                    if cutPos and (Mission.carriedChicken or (carriedEnt and carriedEnt ~= 0)) and dist(pos, cutPos) <= (cutSite.tablePlaceRadius or 2.5) then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.placeDeadChicken) or 'Place on Table', true)
                        if pressed(InteractPrompt) then
                            if placeDeadChickenForCut(cutSite) then
                                Mission.stage = 'cut'
                                clearObjectiveBlip()
                            end
                            Wait(300)
                        end
                    elseif not Mission.carriedChicken and (not carriedEnt or carriedEnt == 0) then
                        local corpse = Mission.groundDeadChicken or Mission.tableChicken
                        if corpse and DoesEntityExist(corpse) and dist(pos, GetEntityCoords(corpse)) <= 2.5 then
                            shown = true
                            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.pickupDeadChicken) or 'Pick Up Chicken', true)
                            if pressed(InteractPrompt) then
                                pickupDeadChickenFromGround()
                                Wait(300)
                            end
                        end
                    end

                elseif Mission.stage == 'cut' then
                    -- Trigger cutting while the player is near the actual table.
                    -- Do not require standing on an exact hidden scenario-point offset.
                    local tablePos = getCutTableCoords(cutSite)
                    local scenarioPos = getCutScenarioCoords(cutSite)
                    local scenarioDistance = (cutSite.scenario and cutSite.scenario.distance) or Config.ButcherScenario.DistanceThreshold or 2.5
                    local triggerDistance = math.max(scenarioDistance, cutSite.tablePlaceRadius or 2.5, 3.0)
                    local nearTable = tablePos and dist(pos, tablePos) <= triggerDistance
                    local nearScenario = scenarioPos and dist(pos, scenarioPos) <= triggerDistance
                    if Mission.tableChicken and Mission.tableDead and (nearTable or nearScenario) then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.cutChicken) or 'Cut Chicken', true)
                        if pressed(InteractPrompt) then
                            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.cutChicken) or 'Cut Chicken', false)
                            dbg(('G cut pressed at site=%s tableDist=%.2f scenarioDist=%.2f'):format(
                                tostring(cutSite.id),
                                tablePos and dist(pos, tablePos) or -1.0,
                                scenarioPos and dist(pos, scenarioPos) or -1.0
                            ))
                            if cutTableChicken(cutSite) then Mission.stage = 'waiting_products' end
                            Wait(300)
                        end
                    end

                elseif Mission.stage == 'pickup_chest' then
                    drawMarker(site.chest)
                    spawnBasinGround(site)
                    if Mission.chestProp and dist(pos, GetEntityCoords(Mission.chestProp)) <= site.chestRadius then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.pickupChest) or 'Pick Up Products', true)
                        if pressed(InteractPrompt) then
                            if pickupBasin() then Mission.stage = 'load_chest' end
                            Wait(300)
                        end
                    end

                elseif Mission.stage == 'load_chest' then
                    if Mission.carryingChest and Mission.wagon and dist(pos, GetEntityCoords(Mission.wagon)) <= Config.Wagon.chestLoadDistance then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.loadChest) or 'Load Products', true)
                        if pressed(InteractPrompt) then
                            if loadBasinOnWagon() then
                                Mission.stage = 'delivery'
                                setObjective(Config.ObjectiveBlips.delivery, Mission.delivery, 'Delivery')
                                notify(Config.Text.goDelivery)
                            end
                            Wait(300)
                        end
                    end

                elseif Mission.stage == 'delivery' then
                    drawMarker(Mission.delivery)
                    local wagonCoords = (Mission.wagon and DoesEntityExist(Mission.wagon)) and GetEntityCoords(Mission.wagon) or nil
                    local wagonDist = wagonCoords and dist(wagonCoords, Mission.delivery) or 999.0
                    local playerDist = dist(pos, Mission.delivery)
                    local playerWagonDist = wagonCoords and dist(pos, wagonCoords) or 999.0
                    local inWagon = Mission.wagon and IsPedInVehicle(ped, Mission.wagon, false)

                    if wagonDist <= (Config.Delivery.areaRadius or 35.0) then
                        -- Method A: Player in wagon near delivery point, OR on foot at delivery point -> Deliver directly!
                        if (inWagon and (wagonDist <= 15.0 or playerDist <= 15.0)) or (not inWagon and playerDist <= (Config.Delivery.dropRadius or 8.0)) then
                            shown = true
                            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.deliverChest) or 'Deliver Products', true)
                            if pressed(InteractPrompt) then
                                promptShow(InteractPrompt, '', false)
                                if deliverBasin(true) then Mission.stage = 'complete_wait' end
                                Wait(500)
                            end
                        -- Method B: Player on foot near wagon bed -> Unload basin to carry manually
                        elseif not inWagon and Mission.chestOnWagon and playerWagonDist <= (Config.Wagon.chestLoadDistance + 2.5) then
                            shown = true
                            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.unloadChest) or 'Unload Products', true)
                            if pressed(InteractPrompt) then
                                promptShow(InteractPrompt, '', false)
                                if unloadBasinFromWagon() then
                                    Mission.stage = 'delivery_carry'
                                    notify(Config.Text.carryDelivery or 'احمل المنتجات إلى نقطة التسليم.')
                                end
                                Wait(300)
                            end
                        end
                    elseif playerDist <= (Config.Delivery.dropRadius or 8.0) and not inWagon then
                        -- Wagon parked further away, but player reached drop point
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.deliverChest) or 'Deliver Products', true)
                        if pressed(InteractPrompt) then
                            promptShow(InteractPrompt, '', false)
                            if deliverBasin(true) then Mission.stage = 'complete_wait' end
                            Wait(500)
                        end
                    end

                elseif Mission.stage == 'delivery_carry' then
                    drawMarker(Mission.delivery)
                    local playerDist = dist(pos, Mission.delivery)
                    if (Mission.carryingChest or (Mission.chestProp and DoesEntityExist(Mission.chestProp) and dist(pos, GetEntityCoords(Mission.chestProp)) <= 3.0)) and playerDist <= (Config.Delivery.dropRadius or 8.0) then
                        shown = true
                        promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.deliverChest) or 'Deliver Products', true)
                        if pressed(InteractPrompt) then
                            promptShow(InteractPrompt, '', false)
                            if deliverBasin(false) then Mission.stage = 'complete_wait' end
                            Wait(500)
                        end
                    end

                elseif Mission.stage == 'waiting_products' then
                    -- v3.3.0: ask the server again instead of counting the
                    -- chicken locally. The old local +1 desynced the count, so
                    -- the final delivery was rejected and never paid.
                    if not Mission.waitProductStart then
                        Mission.waitProductStart = GetGameTimer()
                    elseif GetGameTimer() - Mission.waitProductStart > 6000 then
                        Mission.waitProductStart = GetGameTimer()
                        if Mission.testMode then
                            local nextP = math.min((Mission.processed or 0) + 1, Config.ChickensRequired)
                            TriggerEvent('jrs_chicken_job:client:productsGranted', nextP, true)
                        else
                            TriggerServerEvent('jrs_chicken_job:server:grantProducts')
                        end
                    end

                elseif Mission.stage == 'complete_wait' then
                    -- Retry once; never claim success without the server's reply.
                    if not Mission.waitCompleteStart then
                        Mission.waitCompleteStart = GetGameTimer()
                        Mission.completeRetried = false
                    elseif not Mission.completeRetried and GetGameTimer() - Mission.waitCompleteStart > 8000 then
                        Mission.completeRetried = true
                        if not Mission.testMode then TriggerServerEvent('jrs_chicken_job:server:complete') end
                    elseif GetGameTimer() - Mission.waitCompleteStart > 20000 then
                        Mission.waitCompleteStart = nil
                        if Mission.testMode then notify(Config.Text.complete or 'اكتملت مهمة الدجاج بنجاح!') end
                        cleanupMission()
                    end
                end

                if not shown then promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.interact) or 'Interact', false) end
            end
        else
            promptShow(InteractPrompt, (Config.Prompts and Config.Prompts.interact) or 'Interact', false)
        end

        Wait(sleep)
    end
end)

RegisterCommand((Config.TestMode and Config.TestMode.command) or 'chicken_test', function(_, args)
    local stage = args and args[1] or nil
    local hubId = args and args[2] or nil

    if not stage or stage == '' or string.lower(stage) == 'list' then
        local stages = table.concat(TEST_STAGE_LIST, ', ')
        print('[jrs_chicken_job] Test stages: ' .. stages)
        notify('TEST stages printed in F8. Example: /chicken_test kill valentine', 8000)
        return
    end

    setupTestMission(stage, hubId)
end, false)

RegisterCommand((Config.TestMode and Config.TestMode.stopCommand) or 'chicken_test_stop', function()
    if not Mission.active or not Mission.testMode then
        notify(Config.Text.noActiveMission or 'لا يوجد اختبار دجاج نشط حالياً.')
        return
    end
    cleanupMission()
    notify(Config.Text.testModeStopped or 'تم إيقاف وضع اختبار الدجاج.')
end, false)

RegisterCommand('chicken_cancel', function()
    if not Mission.active then
        notify(Config.Text.noActiveMission or 'لا توجد مهمة دجاج نشطة حالياً.')
        return
    end
    if not Mission.testMode then TriggerServerEvent('jrs_chicken_job:server:cancel') end
    notify(Mission.testMode and (Config.Text.testModeStopped or 'تم إيقاف اختبار عمل الدجاج.') or (Config.Text.missionCancelled or 'تم إلغاء مهمة الدجاج.'))
    cleanupMission()
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- IMPORTANT: registered prompts survive visually if the resource stops
    -- while one is enabled. Disable/hide and delete both handles explicitly.
    hideAllPrompts()
    StartPrompt = promptDeleteSafe(StartPrompt)
    InteractPrompt = promptDeleteSafe(InteractPrompt)

    cleanupMission()
    for _, ped in pairs(HubNPCs) do deleteEntitySafe(ped) end
    for _, objects in pairs(CutStationObjects) do
        if objects.board then deleteEntitySafe(objects.board) end
        if objects.table then deleteEntitySafe(objects.table) end
    end
    HubNPCs = {}
    CutStationObjects = {}
    for _, b in pairs(HubBlips) do
        if b and DoesBlipExist(b) then RemoveBlip(b) end
    end
    HubBlips = {}
end)

RegisterCommand('chicken_status', function()
    if not Mission.active then
        notify(Config.Text.noActiveMission or 'عمل الدجاج: لا توجد مهمة نشطة.')
        return
    end
    local msg = (Config.Text.jobStatus and Config.Text.jobStatus:format(tostring(Mission.stage), Mission.testMode and ' [تجريبي]' or ''))
        or ('حالة عمل الدجاج: %s%s'):format(tostring(Mission.stage), Mission.testMode and ' [تجريبي]' or '')
    notify(msg, 7000)
    print(('[jrs_chicken_job] stage=%s hub=%s caught=%s live=%s wagon=%s processed=%s'):format(
        tostring(Mission.stage),
        tostring(Mission.hub and Mission.hub.id),
        tostring(Mission.caught),
        tostring(#Mission.chickens),
        tostring(#Mission.wagonChickens),
        tostring(Mission.processed)
    ))
end, false)
