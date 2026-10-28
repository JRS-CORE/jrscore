-- JRS - player disconnect marker
-- Stores recent player positions in memory and broadcasts a temporary marker on disconnect.

local lastPlayerData = {}
local activeSigns = {}
local signSequence = 0
local lastUpdateAt = {}

local function cfg()
    return Config and Config.PlayerDropped or nil
end

local function enabled()
    local c = cfg()
    return c and c.Enabled == true
end

local function clampString(value, maxLen)
    value = tostring(value or ''):gsub('[\r\n]', ' ')
    if #value > maxLen then
        value = value:sub(1, maxLen)
    end
    return value
end

local function validCoords(coords)
    if type(coords) ~= 'table' then return nil end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return nil end
    if math.abs(x) > 20000.0 or math.abs(y) > 20000.0 or z < -2000.0 or z > 5000.0 then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function getCharacterIdentity(src)
    local data = PlayerData and PlayerData[src] or nil
    local first = data and data.firstname or nil
    local last = data and data.lastname or nil
    local charId = data and data.charIdentifier or nil

    if (not first or first == '') and jrsCore and jrsCore.getUser then
        local user = jrsCore.getUser(src)
        local character = user and (user.character or user.getUsedCharacter) or nil
        if type(character) == 'table' then
            first = character.firstname or first
            last = character.lastname or last
            charId = character.charIdentifier or charId
        end
    end

    local fullName = ((tostring(first or '') .. ' ' .. tostring(last or '')):gsub('^%s+', ''):gsub('%s+$', ''))
    if fullName == '' then
        fullName = GetPlayerName(src) or ('Player %s'):format(src)
    end

    return fullName, charId
end

RegisterNetEvent('jrs_core:playerDropped:update', function(payload)
    if not enabled() or type(payload) ~= 'table' then return end

    local src = tonumber(source)
    if not src or src <= 0 then return end

    local nowMs = GetGameTimer()
    local previous = lastUpdateAt[src] or 0
    if nowMs - previous < 500 then return end
    lastUpdateAt[src] = nowMs

    local coords = validCoords(payload.coords)
    if not coords then return end

    lastPlayerData[src] = {
        coords = coords,
        heading = tonumber(payload.heading) or 0.0,
        model = tonumber(payload.model),
        updatedAt = os.time()
    }
end)

RegisterNetEvent('jrs_core:playerDropped:requestSync', function()
    if not enabled() then return end
    local src = tonumber(source)
    if not src then return end

    local now = os.time()
    local list = {}
    for signId, data in pairs(activeSigns) do
        if tonumber(data.expiresUnix) and data.expiresUnix > now then
            local entry = {}
            for key, value in pairs(data) do entry[key] = value end
            entry.remaining = math.max(1, data.expiresUnix - now)
            list[#list + 1] = entry
        else
            activeSigns[signId] = nil
        end
    end

    TriggerClientEvent('jrs_core:playerDropped:sync', src, list)
end)

AddEventHandler('playerDropped', function(reason)
    if not enabled() then return end

    local src = tonumber(source)
    if not src then return end

    local pData = lastPlayerData[src]
    if not pData or not pData.coords then
        lastPlayerData[src] = nil
        lastUpdateAt[src] = nil
        return
    end

    local c = cfg() or {}
    local lifetime = math.max(5, math.floor(tonumber(c.Lifetime) or 300))
    local name, charId = getCharacterIdentity(src)

    signSequence = signSequence + 1
    if signSequence > 2147483000 then signSequence = 1 end

    local signId = signSequence
    local now = os.time()
    local data = {
        id = signId,
        serverId = src,
        charId = charId,
        name = clampString(name, 80),
        reason = clampString(reason, 90),
        timeText = os.date(c.TimeFormat or '%H:%M', now),
        coords = pData.coords,
        heading = pData.heading,
        model = pData.model,
        createdUnix = now,
        expiresUnix = now + lifetime,
        lifetime = lifetime,
        remaining = lifetime
    }

    activeSigns[signId] = data
    TriggerClientEvent('jrs_core:playerDropped:add', -1, data)

    local maxActive = math.max(1, math.floor(tonumber(c.MaxActiveSigns) or 50))
    local count = 0
    local oldestId, oldestTime
    for id, entry in pairs(activeSigns) do
        count = count + 1
        local created = tonumber(entry.createdUnix) or now
        if not oldestTime or created < oldestTime then
            oldestTime = created
            oldestId = id
        end
    end
    if count > maxActive and oldestId then
        activeSigns[oldestId] = nil
        TriggerClientEvent('jrs_core:playerDropped:remove', -1, oldestId)
    end

    lastPlayerData[src] = nil
    lastUpdateAt[src] = nil
end)

CreateThread(function()
    while true do
        Wait(5000)
        if enabled() then
            local now = os.time()
            for signId, data in pairs(activeSigns) do
                if not data.expiresUnix or data.expiresUnix <= now then
                    activeSigns[signId] = nil
                    TriggerClientEvent('jrs_core:playerDropped:remove', -1, signId)
                end
            end
        elseif next(activeSigns) ~= nil then
            for signId in pairs(activeSigns) do
                TriggerClientEvent('jrs_core:playerDropped:remove', -1, signId)
            end
            activeSigns = {}
        end
    end
end)
