local RESOURCE = GetCurrentResourceName()
local PERF = Config.Performance or {}

local currentMode = 'normal'
local nearbyPlayers = 1
local candidateMode = nil
local candidateSince = 0
local debugEnabled = false

local LEVEL_BY_NAME = {}
for i = 1, #(PERF.Levels or {}) do
    local level = PERF.Levels[i]
    if type(level) == 'table' and type(level.name) == 'string' then
        LEVEL_BY_NAME[level.name] = level
    end
end

-- RDR2 density natives. Raw hashes keep this independent from runtime aliases.
local NATIVE = {
    AMBIENT_HUMAN_DENSITY = 0xBA0980B5C0A11924,
    SCENARIO_HUMAN_DENSITY = 0x28CB6391ACEDD9DB,
    VEHICLE_DENSITY = 0x606374EBFC27B133,
    RANDOM_VEHICLE_DENSITY = 0x1F91D44490E1EA0C,
    PARKED_VEHICLE_DENSITY = 0xFEDFA97638D61D4A,
}

local function clamp01(value)
    value = tonumber(value) or 1.0
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function notify(message)
    message = tostring(message or '')
    print(('[%s][performance] %s'):format(RESOURCE, message))
    TriggerEvent('jrsCore:notify', 'PERFORMANCE', message, 'placeholder', 5000)
end

local function isInsideExcludedArea(coords)
    local areas = PERF.ExcludedAreas or {}
    for i = 1, #areas do
        local area = areas[i]
        if area.coords and area.radius then
            local radius = tonumber(area.radius)
            if radius then
                local distance = #(coords - area.coords)
                if distance <= radius then
                    return true
                end
            end
        end
    end
    return false
end

local function countNearbyPlayers()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return 1, nil
    end

    local coords = GetEntityCoords(ped)
    local radius = tonumber(PERF.DensityRadius) or 125.0
    local count = 0
    local players = GetActivePlayers()

    for i = 1, #players do
        local player = players[i]
        local otherPed = GetPlayerPed(player)
        if otherPed and otherPed ~= 0 and DoesEntityExist(otherPed) then
            local otherCoords = GetEntityCoords(otherPed)
            if #(coords - otherCoords) <= radius then
                count = count + 1
            end
        end
    end

    return math.max(count, 1), coords
end

local function getAutomaticMode(playerCount)
    local levels = PERF.Levels or {}
    local selected = levels[1]
    if not selected then return 'normal' end

    for i = 1, #levels do
        local level = levels[i]
        if playerCount >= (tonumber(level.minimumPlayers) or 1) then
            selected = level
        else
            break
        end
    end

    return selected.name or 'normal'
end

local function getRequestedMode(coords)
    if coords and isInsideExcludedArea(coords) then
        return 'normal'
    end

    local override = GlobalState.jrsPerformanceMode
    if type(override) == 'string' and override ~= '' and override ~= 'auto' and LEVEL_BY_NAME[override] then
        return override
    end

    return getAutomaticMode(nearbyPlayers)
end

local function updateMode(targetMode)
    if targetMode == currentMode then
        candidateMode = nil
        candidateSince = 0
        return
    end

    local now = GetGameTimer()
    if candidateMode ~= targetMode then
        candidateMode = targetMode
        candidateSince = now
        return
    end

    if now - candidateSince >= (tonumber(PERF.ModeChangeHoldMs) or 4000) then
        currentMode = targetMode
        candidateMode = nil
        candidateSince = 0
    end
end

-- Only jrs_safezone zones flagged isCity = true suppress ambient human
-- ("bot") spawning. Scripted job NPCs are created by their own resources and
-- are not part of this ambient population system, so they are unaffected.
local inCityZone = false

CreateThread(function()
    while true do
        if LocalPlayer and LocalPlayer.state and LocalPlayer.state.safezoneIsCity ~= nil then
            inCityZone = LocalPlayer.state.safezoneIsCity == true
        elseif GetResourceState('jrs_safezone') == 'started' then
            local ok, zone = pcall(function() return exports['jrs_safezone']:GetCurrentSafeZone() end)
            inCityZone = ok and type(zone) == 'table' and zone.isCity == true
        else
            inCityZone = false
        end
        Wait(1000)
    end
end)

local function applyProfile(profile)
    -- Only humans and vehicles are adaptive. Generic ped/range and animal
    -- multipliers are deliberately untouched so hunting remains independent.
    local ambientHumans = inCityZone and clamp01(PERF.CityAmbientHumans or 0.0) or clamp01(profile.ambientHumans)
    local scenarioHumans = inCityZone and clamp01(PERF.CityScenarioHumans or 0.0) or clamp01(profile.scenarioHumans)
    Citizen.InvokeNative(NATIVE.AMBIENT_HUMAN_DENSITY, ambientHumans)
    Citizen.InvokeNative(NATIVE.SCENARIO_HUMAN_DENSITY, scenarioHumans)
    Citizen.InvokeNative(NATIVE.VEHICLE_DENSITY, clamp01(profile.vehicleDensity))
    Citizen.InvokeNative(NATIVE.RANDOM_VEHICLE_DENSITY, clamp01(profile.randomVehicleDensity))
    Citizen.InvokeNative(NATIVE.PARKED_VEHICLE_DENSITY, clamp01(profile.parkedVehicleDensity))
end

local function isProtected(entity)
    local stateKey = PERF.ProtectionStateKey or 'jrsProtected'
    local ok, value = pcall(function()
        return Entity(entity).state[stateKey] == true
    end)
    return ok and value == true
end

local function countPoolNear(poolName, coords, radius)
    local ok, pool = pcall(GetGamePool, poolName)
    if not ok or type(pool) ~= 'table' then
        return 0, 0
    end

    local count = 0
    local protected = 0
    for i = 1, #pool do
        local entity = pool[i]
        if DoesEntityExist(entity) then
            local entityCoords = GetEntityCoords(entity)
            if #(coords - entityCoords) <= radius then
                count = count + 1
                if isProtected(entity) then
                    protected = protected + 1
                end
            end
        end
    end

    return count, protected
end

local function collectDebugStats()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil
    end

    local coords = GetEntityCoords(ped)
    local radius = tonumber(PERF.DebugEntityRadius) or 125.0
    local peds, protectedPeds = countPoolNear('CPed', coords, radius)
    local vehicles, protectedVehicles = countPoolNear('CVehicle', coords, radius)
    local objects, protectedObjects = countPoolNear('CObject', coords, radius)

    return {
        players = nearbyPlayers,
        peds = peds,
        vehicles = vehicles,
        objects = objects,
        protected = protectedPeds + protectedVehicles + protectedObjects,
        mode = currentMode,
        override = GlobalState.jrsPerformanceMode or 'auto',
        radius = radius,
    }
end

local function printStats(stats)
    if not stats then
        notify(_U('core_character_entity_is_not_ready_yet'))
        return
    end

    notify((_U('core_mode_override_nearby_players_peds_vehicles'))
        :format(stats.mode, stats.override, stats.players, stats.peds, stats.vehicles, stats.objects, stats.protected, stats.radius))
end

CreateThread(function()
    while true do
        if PERF.Enabled ~= true then
            currentMode = 'normal'
            candidateMode = nil
            candidateSince = 0
            Wait(2000)
        else
            local count, coords = countNearbyPlayers()
            nearbyPlayers = count
            updateMode(getRequestedMode(coords))
            Wait(tonumber(PERF.SampleIntervalMs) or 2000)
        end
    end
end)

CreateThread(function()
    while true do
        if PERF.Enabled == true then
            -- Human/vehicle density multipliers are per-frame natives, including
            -- the normal profile. Animals are handled independently.
            local profile = LEVEL_BY_NAME[currentMode] or LEVEL_BY_NAME.normal
            if profile then
                applyProfile(profile)
                Wait(0)
            else
                Wait(500)
            end
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        if debugEnabled then
            printStats(collectDebugStats())
            Wait(tonumber(PERF.DebugRefreshMs) or 3000)
        else
            Wait(1000)
        end
    end
end)

RegisterNetEvent('jrs_core:performance:showStats', function()
    printStats(collectDebugStats())
end)

RegisterNetEvent('jrs_core:performance:setDebug', function(enabled)
    debugEnabled = enabled == true
    notify(debugEnabled and _U('core_performance_debug_enabled') or _U('core_performance_debug_disabled'))
    if debugEnabled then
        printStats(collectDebugStats())
    end
end)

RegisterNetEvent('jrs_core:performance:message', function(message)
    notify(message)
end)

local function setEntityProtected(entity, protected)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    local stateKey = PERF.ProtectionStateKey or 'jrsProtected'
    local ok = pcall(function()
        Entity(entity).state:set(stateKey, protected == true, true)
    end)
    return ok
end

exports('GetPerformanceMode', function()
    return currentMode
end)

exports('GetNearbyPlayerCount', function()
    return nearbyPlayers
end)

exports('IsEntityProtected', function(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end
    return isProtected(entity)
end)

exports('SetEntityProtected', setEntityProtected)

-- Compatibility aliases for migrated performance integrations.
exports('GetMode', function()
    return currentMode
end)
