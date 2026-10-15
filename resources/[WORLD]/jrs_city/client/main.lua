local RESOURCE_NAME = GetCurrentResourceName()
local MAP_ZONE_NATIVE = 0x43AD8FC02B429D33

local zoneIndex = {}
local lastSignature = nil
local currentLocation = nil
local uiSerial = 0
local started = false

local TYPE_NAMES = {
    [0] = 'STATE',
    [1] = 'TOWN',
    [2] = 'LAKE',
    [3] = 'RIVER',
    [4] = 'OIL_SPILL',
    [5] = 'SWAMP',
    [6] = 'OCEAN',
    [7] = 'CREEK',
    [8] = 'POND',
    [9] = 'GLACIER',
    [10] = 'DISTRICT',
    [11] = 'TEXT_PRINTED',
    [12] = 'TEXT_WRITTEN',
}

local WATER_TYPES = { 2, 3, 4, 5, 6, 7, 8, 9 }

local function debugPrint(message)
    if Config.Debug then
-- REMOVED-PRINT:         print(('[%s] %s'):format(RESOURCE_NAME, tostring(message)))
    end
end

local function normalizeHash(value)
    local hash = tonumber(value) or 0
    if hash > 2147483647 then
        hash = hash - 4294967296
    end
    return hash
end

local function humanize(value)
    local text = tostring(value or '')
    if text == '' then return '' end

    text = text:gsub('^[Pp]_%d+_', '')
    text = text:gsub('^[Ww]_%d+_', '')
    text = text:gsub('^TOWN_', '')
    text = text:gsub('^SETTLEMENT_', '')
    text = text:gsub('^LANDMARK_', '')
    text = text:gsub('^HIDEOUT_', '')
    text = text:gsub('^DISTRICT_', '')
    text = text:gsub('^STATE_', '')
    text = text:gsub('^WATER_', '')
    text = text:gsub('_', ' ')
    text = text:gsub('(%l)(%u)', '%1 %2')
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')

    return text
end

local function buildZoneIndex()
    zoneIndex = {}

    local function addTable(source)
        for rawHash, data in pairs(source or {}) do
            local hash = normalizeHash(rawHash)
            if not Config.DisabledZoneHashes[hash] then
                zoneIndex[hash] = {
                    hash = hash,
                    name = Config.NameOverrides[hash] or data.ZoneName or tostring(hash),
                    typeId = tonumber(data.ZoneTypeId),
                    typeName = data.ZoneTypeName or TYPE_NAMES[tonumber(data.ZoneTypeId)] or 'UNKNOWN',
                }
            end
        end
    end

    addTable(Config.NativeZoneData)
    addTable(Config.CustomNativeZones)

    debugPrint(('Loaded %s native zone definitions'):format(tostring((function()
        local count = 0
        for _ in pairs(zoneIndex) do count = count + 1 end
        return count
    end)())))
end

local function getNativeHash(coords, typeId)
    local ok, value = pcall(Citizen.InvokeNative, MAP_ZONE_NATIVE, coords.x, coords.y, coords.z, typeId)
    if not ok or not value then return 0 end
    return normalizeHash(value)
end

local function resolveByType(coords, typeId)
    local hash = getNativeHash(coords, typeId)
    if hash == 0 then return nil end

    local zone = zoneIndex[hash]
    if not zone then
        if Config.Debug then
            debugPrint(_U('unmapped_zone', hash, TYPE_NAMES[typeId] or typeId))
        end
        return nil
    end

    return zone
end

local function firstWater(coords)
    for _, typeId in ipairs(WATER_TYPES) do
        local zone = resolveByType(coords, typeId)
        if zone then return zone end
    end
    return nil
end

local function resolveLocation(coords)
    local state = resolveByType(coords, 0)
    local district = resolveByType(coords, 10)
    local town = resolveByType(coords, 1)
    local printed = resolveByType(coords, 11)
    local written = resolveByType(coords, 12)
    local water = firstWater(coords)

    local byType = {
        [0] = state,
        [1] = town,
        [10] = district,
        [11] = printed,
        [12] = written,
    }
    if water then byType[water.typeId] = water end

    local primary = nil
    for _, typeId in ipairs(Config.Detection.Priority or {}) do
        local candidate = byType[typeId]
        if not candidate and typeId >= 2 and typeId <= 9 and water and water.typeId == typeId then
            candidate = water
        end
        if candidate then
            primary = candidate
            break
        end
    end

    if not primary then return nil end

    local signature = table.concat({
        tostring(primary.hash or 0),
        tostring(district and district.hash or 0),
        tostring(state and state.hash or 0),
    }, ':')

    return {
        primary = primary,
        town = town,
        printed = printed,
        written = written,
        water = water,
        district = district,
        state = state,
        signature = signature,
    }
end

local function formatTime()
    local hour = GetClockHours()
    local minute = GetClockMinutes()

    if Config.Details.Use24Hour then
        return ('%02d:%02d'):format(hour, minute)
    end

    local periodKey = hour >= 12 and 'time_pm' or 'time_am'
    local defaultPeriod = hour >= 12 and 'PM' or 'AM'
    local period = _U(periodKey)
    if not period or period == periodKey then period = defaultPeriod end

    local displayHour = hour % 12
    if displayHour == 0 then displayHour = 12 end
    return ('%02d:%02d %s'):format(displayHour, minute, period)
end

local function getTemperature(coords)
    local value = GetTemperatureAtCoords(coords.x, coords.y, coords.z)
    if Config.Details.TemperatureUnit == 'F' then
        value = (value * 9.0 / 5.0) + 32.0
        return ('%d°F'):format(math.floor(value + 0.5))
    end
    return ('%d°C'):format(math.floor(value + 0.5))
end

local function getWind()
    local speed = GetWindSpeed()
    local unit = Config.Details.WindUnit

    if unit == 'auto' then
        unit = ShouldUseMetricTemperature() and 'kph' or 'mph'
    end

    if unit == 'mph' then
        speed = speed * 0.621371
        local mphLabel = _U('unit_mph')
        if not mphLabel or mphLabel == 'unit_mph' then mphLabel = 'MPH' end
        return ('%d %s'):format(math.floor(speed + 0.5), mphLabel)
    end

    local kphLabel = _U('unit_kph')
    if not kphLabel or kphLabel == 'unit_kph' then kphLabel = 'KPH' end
    return ('%d %s'):format(math.floor(speed + 0.5), kphLabel)
end

local function getDay()
    local day = GetClockDayOfWeek()
    local dayKey = 'day_' .. tostring(day)
    local trans = _U(dayKey)
    if trans and trans ~= dayKey then return trans end
    return Config.Days[day] or tostring(day)
end

local function buildDetails(coords)
    local parts = {}
    if Config.Details.ShowDay then parts[#parts + 1] = getDay() end
    if Config.Details.ShowTime then parts[#parts + 1] = formatTime() end
    if Config.Details.ShowTemperature then parts[#parts + 1] = getTemperature(coords) end
    if Config.Details.ShowWind then parts[#parts + 1] = getWind() end
    return table.concat(parts, '  |  ')
end

local function displayName(zone)
    if not zone then return '' end
    local base = humanize(zone.name)
    if base == '' then return '' end

    local cleanKey = 'zone_' .. base:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    local trans = _U(cleanKey)
    if trans and trans ~= cleanKey then
        return trans
    end

    local rawKey = 'zone_' .. tostring(zone.name or ''):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if rawKey ~= cleanKey then
        local rawTrans = _U(rawKey)
        if rawTrans and rawTrans ~= rawKey then
            return rawTrans
        end
    end

    return base
end

local function showLocation(location, coords)
    if not Config.Notification.UI.Enabled or not location or not location.primary then return end

    local title = displayName(location.primary)
    local district = Config.Details.ShowDistrict and displayName(location.district) or ''
    local state = Config.Details.ShowState and displayName(location.state) or ''

    if district:lower() == title:lower() then district = '' end
    if state:lower() == title:lower() then state = '' end

    uiSerial = uiSerial + 1
    SendNUIMessage({
        action = 'showZone',
        serial = uiSerial,
        title = title,
        district = district,
        state = state,
        details = buildDetails(coords),
        duration = tonumber(Config.Notification.Duration) or 4000,
        top = Config.Notification.UI.Top or '1.8vh',
        width = Config.Notification.UI.Width or '340px',
        maxWidth = Config.Notification.UI.MaxWidth or '82vw',
        fadeIn = tonumber(Config.Notification.UI.FadeInMs) or 180,
        fadeOut = tonumber(Config.Notification.UI.FadeOutMs) or 260,
        soundEnabled = Config.Notification.Sound == nil or Config.Notification.Sound.Enabled ~= false,
        soundFile = (Config.Notification.Sound and Config.Notification.Sound.File) or 'assets/zone_open.mp3',
        soundVolume = tonumber(Config.Notification.Sound and Config.Notification.Sound.Volume) or 0.35,
    })
end

local function hideLocation()
    uiSerial = uiSerial + 1
    SendNUIMessage({ action = 'hideZone', serial = uiSerial })
end

-- A generic banner on the same card: any resource can borrow the zone-name
-- presentation for a short server-wide message (jrs_admin's broadcast is the
-- first caller). This does not touch currentLocation/lastSignature, so the
-- zone banner keeps working normally the next time the player's zone changes.
local function showMessage(message, author, duration, customState, details, width)
    local title, district, state, zoneDetails, showDuration, uiWidth
    if type(message) == 'table' then
        title = tostring(message.title or message.message or '')
        district = tostring(message.district or message.subtitle or message.author or '')
        state = message.state
        zoneDetails = tostring(message.details or '')
        showDuration = tonumber(message.duration) or tonumber(duration) or 7000
        uiWidth = message.width or width
    else
        title = tostring(message or '')
        district = tostring(author or '')
        state = customState
        zoneDetails = tostring(details or '')
        showDuration = tonumber(duration) or 7000
        uiWidth = width
    end

    title = title:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    if title == '' then return false end

    district = district:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    zoneDetails = zoneDetails:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''

    -- Backward-compatible parser: if legacy callers pass raw property string
    if not state or state == '' then
        local propEn, ownEn = title:match("^[Yy]ou entered private property:%s*(.-)%s*|%s*[Oo]wner:%s*(.-)$")
        if not propEn then
            propEn, ownEn = title:match("^لقد دخلت ملكية خاصة:%s*(.-)%s*|%s*المالك:%s*(.-)$")
        end
        if not propEn then
            propEn, ownEn = title:match("^دخلت عقاراً خاصاً:%s*(.-)%s*|%s*المالك:%s*(.-)$")
        end

        if propEn and ownEn then
            title = propEn
            district = _U('owner_label', ownEn)
            state = _U('private_property')
        else
            local singleProp = title:match("^[Yy]ou entered private property:%s*(.-)$")
                or title:match("^لقد دخلت ملكية خاصة:%s*(.-)$")
                or title:match("^دخلت عقاراً خاصاً:%s*(.-)$")
            if singleProp then
                title = singleProp
                state = _U('private_property')
            else
                if district ~= '' and not district:find('^—') and not district:find(':') and not district:find('^المالك') and not district:find('^Owner') then
                    district = '— ' .. district
                end
                state = _U('server_message')
            end
        end
    else
        state = tostring(state):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    end

    uiSerial = uiSerial + 1
    SendNUIMessage({
        action = 'showZone',
        serial = uiSerial,
        title = title,
        district = district,
        state = state,
        details = zoneDetails,
        duration = showDuration,
        top = Config.Notification.UI.Top or '1.8vh',
        width = uiWidth or Config.Notification.UI.Width or '380px',
        maxWidth = Config.Notification.UI.MaxWidth or '82vw',
        fadeIn = tonumber(Config.Notification.UI.FadeInMs) or 180,
        fadeOut = tonumber(Config.Notification.UI.FadeOutMs) or 260,
        soundEnabled = Config.Notification.Sound == nil or Config.Notification.Sound.Enabled ~= false,
        soundFile = (Config.Notification.Sound and Config.Notification.Sound.File) or 'assets/zone_open.mp3',
        soundVolume = tonumber(Config.Notification.Sound and Config.Notification.Sound.Volume) or 0.35,
    })
    return true
end

exports('ShowMessage', showMessage)
exports('ShowZoneCard', showMessage)

local function characterReady()
    if not Config.Detection.WaitForCharacter then return true end
    if GetResourceState(Config.CoreResource) ~= 'started' then return false end

    local ok, ready = pcall(function()
        return exports[Config.CoreResource]:IsCharacterReady()
    end)
    return ok and ready == true
end

local function waitForCharacter()
    if not Config.Detection.WaitForCharacter then return end

    while GetResourceState(Config.CoreResource) ~= 'started' do
        Wait(250)
    end

    while true do
        local ok, ready = pcall(function()
            return exports[Config.CoreResource]:WaitForCharacterReady(Config.Detection.CharacterReadyTimeout or 10000)
        end)
        if ok and ready then return end
        Wait(500)
    end
end

local function shouldPause()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return true end
    if Config.Detection.PauseWhenDead and IsEntityDead(ped) then return true end
    if Config.Detection.PauseWhenPauseMenuOpen and IsPauseMenuActive() then return true end
    return false
end

local function processLocation(force)
    if not characterReady() or shouldPause() then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local location = resolveLocation(coords)
    local signature = location and location.signature or 'outside'

    if force or signature ~= lastSignature then
        local oldLocation = currentLocation
        lastSignature = signature
        currentLocation = location

        if location then
            showLocation(location, coords)
            debugPrint(('Location: %s [%s]'):format(displayName(location.primary), tostring(location.primary.hash)))
        else
            hideLocation()
            debugPrint(_U('outside_location'))
        end

        TriggerEvent('jrs_city:client:zoneChanged', oldLocation, currentLocation)
    end
end

CreateThread(function()
    buildZoneIndex()
    waitForCharacter()
    started = true

    if Config.Detection.NotifyOnInitialDetection then
        processLocation(true)
    else
        local ped = PlayerPedId()
        if ped ~= 0 and DoesEntityExist(ped) then
            local location = resolveLocation(GetEntityCoords(ped))
            currentLocation = location
            lastSignature = location and location.signature or 'outside'
        end
    end

    while true do
        Wait(math.max(250, tonumber(Config.Detection.Interval) or 500))
        processLocation(false)
    end
end)

RegisterNetEvent('jrs_core:client:characterReady', function()
    if not started then return end
    lastSignature = nil
    SetTimeout(300, function()
        processLocation(true)
    end)
end)

RegisterNetEvent('jrs_core:client:characterUnloaded', function()
    lastSignature = nil
    currentLocation = nil
    hideLocation()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE_NAME then
        hideLocation()
    end
end)

exports('GetCurrentZone', function()
    if not currentLocation or not currentLocation.primary then return nil end
    return {
        hash = currentLocation.primary.hash,
        name = displayName(currentLocation.primary),
        typeId = currentLocation.primary.typeId,
        typeName = currentLocation.primary.typeName,
        district = displayName(currentLocation.district),
        state = displayName(currentLocation.state),
    }
end)

-- Kept for compatibility with scripts already using jrs_city.
exports('GetCurrentCity', function()
    if not currentLocation or not currentLocation.primary then return nil end
    return {
        id = tostring(currentLocation.primary.hash),
        hash = currentLocation.primary.hash,
        name = displayName(currentLocation.primary),
        key = currentLocation.primary.name,
        typeId = currentLocation.primary.typeId,
        typeName = currentLocation.primary.typeName,
    }
end)

exports('IsInCity', function(value)
    if not currentLocation or not currentLocation.primary then return false end
    if value == nil then return currentLocation.primary.typeId == 1 end

    local wanted = tostring(value):lower()
    return tostring(currentLocation.primary.hash) == wanted
        or displayName(currentLocation.primary):lower() == wanted
        or tostring(currentLocation.primary.name):lower() == wanted
end)

--[[
RegisterCommand('jrscitytest', function()
    uiSerial = uiSerial + 1
    SendNUIMessage({
        action = 'showZone',
        serial = uiSerial,
        title = 'Valentine',
        district = 'The Heartlands',
        state = 'New Hanover',
        details = '03:34 PM  |  9°C  |  7 kph',
        duration = tonumber(Config.Notification.Duration) or 4000,
        top = Config.Notification.UI.Top or '1.8vh',
        width = Config.Notification.UI.Width or '340px',
        maxWidth = Config.Notification.UI.MaxWidth or '82vw',
        fadeIn = tonumber(Config.Notification.UI.FadeInMs) or 180,
        fadeOut = tonumber(Config.Notification.UI.FadeOutMs) or 260,
        soundEnabled = Config.Notification.Sound == nil or Config.Notification.Sound.Enabled ~= false,
        soundFile = (Config.Notification.Sound and Config.Notification.Sound.File) or 'assets/zone_open.mp3',
        soundVolume = tonumber(Config.Notification.Sound and Config.Notification.Sound.Volume) or 0.35,
    })
end, false)

if Config.Debug then
    RegisterCommand('jrscitydebug', function()
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
-- REMOVED-PRINT:         print(('[%s] coords %.2f %.2f %.2f'):format(RESOURCE_NAME, coords.x, coords.y, coords.z))
        for typeId = 0, 12 do
            local hash = getNativeHash(coords, typeId)
            if hash ~= 0 then
                local mapped = zoneIndex[hash]
-- REMOVED-PRINT:                 print((' type=%s (%s) hash=%s name=%s'):format(typeId, TYPE_NAMES[typeId] or '?', hash, mapped and displayName(mapped) or 'UNMAPPED'))
            end
        end
    end, false)
end
]]
