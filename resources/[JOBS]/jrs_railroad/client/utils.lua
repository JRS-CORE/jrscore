---------------------------------------------------------------
-- FULL LOCALE TABLE (for the NUI)
-- script.js localizes its own UI text from a full key->string
-- dictionary rather than one key at a time, so we hand it the
-- active locales/<lang>.json file directly (falling back to
-- en.json), matching Config.Language.
---------------------------------------------------------------
local cachedLocaleTable = nil
function GetLocaleTable()
    if cachedLocaleTable then return cachedLocaleTable end
    local lang = Config.Language or 'en'
    local raw = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(lang))
    if not raw then
        raw = LoadResourceFile(GetCurrentResourceName(), 'locales/en.json')
    end
    cachedLocaleTable = raw and json.decode(raw) or {}
    return cachedLocaleTable
end

---------------------------------------------------------------
-- NOTIFICATIONS (JRS)
---------------------------------------------------------------
function Notify(msg, nType, duration)
    JRS.NotifyT({
        title = L('notify_title'),
        description = msg,
        type = nType or 'inform',
        duration = duration or 5000,
    })
end

-- NOTE: server-side notifications must use TriggerClientEvent(GetCurrentResourceName() .. ':notify', ...)
-- from a server file so L() resolves on the server. Do NOT call
-- TriggerClientEvent from the client (it silently does nothing, which looks
-- like "notifications not working").

---------------------------------------------------------------
-- MODEL LOADING
---------------------------------------------------------------
function LoadModel(model)
    if type(model) == 'string' then model = joaat(model) end
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(100)
    end
end

function LoadTrainCars(trainHash)
    local wagonCount = Citizen.InvokeNative(0x635423D55CA84FC8, trainHash)
    for i = 0, wagonCount - 1 do
        local wagonModel = Citizen.InvokeNative(0x8DF5F6A19F99F0D5, trainHash, i)
        while not HasModelLoaded(wagonModel) do
            Citizen.InvokeNative(0xFA28FE3A6246FC30, wagonModel, 1)
            Wait(100)
        end
    end
end

---------------------------------------------------------------
-- DISTANCE HELPER
---------------------------------------------------------------
function GetDistanceBetween(v1, v2)
    return #(v1 - v2)
end

---------------------------------------------------------------
-- DEBUG PRINT
---------------------------------------------------------------
function DebugPrint(msg)
    if Config.Debug then
        print('[jrs_railroad] ' .. tostring(msg))
    end
end

---------------------------------------------------------------
-- FIND NEAREST STATION
---------------------------------------------------------------
function GetNearestStation(coords)
    local nearest, nearestDist = nil, 9999
    for _, station in ipairs(Config.Stations) do
        local dist = GetDistanceBetween(coords, station.coords)
        if dist < nearestDist then
            nearest = station
            nearestDist = dist
        end
    end
    return nearest, nearestDist
end

---------------------------------------------------------------
-- FIND TRAIN CONFIG BY MODEL+COMPANY
---------------------------------------------------------------
function FindTrainConfig(model, company)
    for _, train in ipairs(Config.Trains) do
        if train.model == model and train.company == company then
            return train
        end
    end
    -- fallback: just match model
    for _, train in ipairs(Config.Trains) do
        if train.model == model then
            return train
        end
    end
    return nil
end

