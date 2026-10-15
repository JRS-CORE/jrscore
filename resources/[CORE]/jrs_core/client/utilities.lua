JRSUtils = JRSUtils or {}

local noSpamTimers = {}

local function normalizeHash(value)
    if type(value) == 'number' then return value end
    return GetHashKey(tostring(value))
end

function JRSUtils.WaitUntil(predicate, timeoutMs, intervalMs)
    if type(predicate) ~= 'function' then return false end

    local timeout = tonumber(timeoutMs) or 10000
    local interval = math.max(0, tonumber(intervalMs) or 10)
    local started = GetGameTimer()

    while not predicate() do
        if timeout >= 0 and (GetGameTimer() - started) >= timeout then
            return false
        end
        Wait(interval)
    end

    return true
end

function JRSUtils.LoadModel(model, timeoutMs)
    local hash = normalizeHash(model)
    if not IsModelValid(hash) then
        return false, hash
    end

    if HasModelLoaded(hash) then
        return true, hash
    end

    RequestModel(hash)
    local loaded = JRSUtils.WaitUntil(function()
        if not HasModelLoaded(hash) then
            RequestModel(hash)
            return false
        end
        return true
    end, timeoutMs or 10000, 10)

    return loaded, hash
end

function JRSUtils.LoadAnimDict(dict, timeoutMs)
    dict = tostring(dict or '')
    if dict == '' or not DoesAnimDictExist(dict) then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    return JRSUtils.WaitUntil(function()
        if not HasAnimDictLoaded(dict) then
            RequestAnimDict(dict)
            return false
        end
        return true
    end, timeoutMs or 10000, 10)
end

function JRSUtils.LoadTextureDict(dict, timeoutMs)
    dict = tostring(dict or '')
    if dict == '' then return false end
    if HasStreamedTextureDictLoaded(dict) then return true end

    RequestStreamedTextureDict(dict, true)
    return JRSUtils.WaitUntil(function()
        if not HasStreamedTextureDictLoaded(dict) then
            RequestStreamedTextureDict(dict, true)
            return false
        end
        return true
    end, timeoutMs or 10000, 10)
end

function JRSUtils.PlayAnimation(ped, anim, timeoutMs)
    ped = tonumber(ped) or PlayerPedId()
    if type(anim) ~= 'table' or not anim.dict or not anim.name then return false end
    if not JRSUtils.LoadAnimDict(anim.dict, timeoutMs) then return false end

    TaskPlayAnim(
        ped,
        anim.dict,
        anim.name,
        tonumber(anim.blendInSpeed) or 1.0,
        tonumber(anim.blendOutSpeed) or 1.0,
        tonumber(anim.duration) or -1,
        tonumber(anim.flag) or 0,
        tonumber(anim.playbackRate) or 1.0,
        false, false, false, '', false
    )

    if anim.keepDict ~= true then
        RemoveAnimDict(anim.dict)
    end

    return true
end

function JRSUtils.GetNearbyPlayers(maxDistance, includeSelf)
    local distanceLimit = tonumber(maxDistance) or 5.0
    local myPlayer = PlayerId()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local result = {}

    for _, playerId in ipairs(GetActivePlayers()) do
        if includeSelf or playerId ~= myPlayer then
            local ped = GetPlayerPed(playerId)
            if ped ~= 0 and DoesEntityExist(ped) then
                local distance = #(GetEntityCoords(ped) - myCoords)
                if distance <= distanceLimit then
                    result[#result + 1] = {
                        playerId = playerId,
                        serverId = GetPlayerServerId(playerId),
                        ped = ped,
                        distance = distance,
                    }
                end
            end
        end
    end

    table.sort(result, function(a, b)
        return a.distance < b.distance
    end)

    return result
end

function JRSUtils.GetClosestPlayer(maxDistance)
    local players = JRSUtils.GetNearbyPlayers(maxDistance, false)
    return players[1]
end

function JRSUtils.RemoveEntity(entity, releaseModel)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    local model = GetEntityModel(entity)
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)

    if DoesEntityExist(entity) then
        DeletePed(entity)
    end

    if DoesEntityExist(entity) then
        DeleteObject(entity)
    end

    if releaseModel and model and model ~= 0 then
        SetModelAsNoLongerNeeded(model)
    end

    return not DoesEntityExist(entity)
end

function JRSUtils.NoSpam(key, cooldownMs)
    key = tostring(key or 'default')
    local now = GetGameTimer()
    local cooldown = math.max(0, tonumber(cooldownMs) or 1000)
    local expires = noSpamTimers[key] or 0

    if now < expires then
        return false, expires - now
    end

    noSpamTimers[key] = now + cooldown
    return true, 0
end

function JRSUtils.SetTimeout(delayMs, callback, ...)
    if type(callback) ~= 'function' then return false end
    local args = { ... }
    SetTimeout(math.max(0, tonumber(delayMs) or 0), function()
        callback(table.unpack(args))
    end)
    return true
end

function JRSUtils.Round(number, decimals)
    local value = tonumber(number) or 0
    local mult = 10 ^ (tonumber(decimals) or 0)
    return math.floor(value * mult + 0.5) / mult
end

function JRSUtils.Lerp(a, b, t)
    return (tonumber(a) or 0) + ((tonumber(b) or 0) - (tonumber(a) or 0)) * (tonumber(t) or 0)
end

function JRSUtils.TableLength(value)
    if type(value) ~= 'table' then return 0 end
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count
end

function JRSUtils.StartsWith(value, prefix)
    value, prefix = tostring(value or ''), tostring(prefix or '')
    return value:sub(1, #prefix) == prefix
end

function JRSUtils.Split(value, separator)
    value = tostring(value or '')
    separator = tostring(separator or ' ')
    if separator == '' then return { value } end

    local result = {}
    local startAt = 1
    while true do
        local from, to = string.find(value, separator, startAt, true)
        if not from then
            result[#result + 1] = string.sub(value, startAt)
            break
        end
        result[#result + 1] = string.sub(value, startAt, from - 1)
        startAt = to + 1
    end
    return result
end

exports('GetUtilities', function()
    return JRSUtils
end)
