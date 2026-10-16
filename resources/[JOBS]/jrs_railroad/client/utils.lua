-- jrs_railroad | client: small helpers shared by the other client files
-- Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

-- the whole active locale file, handed to the page so it can translate itself
local localeCache
function GetLocaleTable()
    if localeCache then return localeCache end
    local resource = GetCurrentResourceName()
    local text = LoadResourceFile(resource, ('locales/%s.json'):format(Config.Language or 'en'))
        or LoadResourceFile(resource, 'locales/en.json')
    localeCache = text and json.decode(text) or {}
    return localeCache
end

function Notify(message, kind, duration)
    JRS.NotifyT({ title = L('notify_title'), description = message, type = kind or 'inform', duration = duration or 5000 })
end

function LoadModel(model)
    if type(model) == 'string' then model = joaat(model) end
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(100) end
end

-- streams in every carriage model a train needs
function LoadTrainCars(trainHash)
    local count = Citizen.InvokeNative(0x635423D55CA84FC8, trainHash)
    for i = 0, count - 1 do
        local car = Citizen.InvokeNative(0x8DF5F6A19F99F0D5, trainHash, i)
        while not HasModelLoaded(car) do
            Citizen.InvokeNative(0xFA28FE3A6246FC30, car, 1)
            Wait(100)
        end
    end
end

function GetDistanceBetween(a, b) return #(a - b) end

function DebugPrint(message)
    if Config.Debug then print('[jrs_railroad] ' .. tostring(message)) end
end

-- closest station to a point, and how far it is
function GetNearestStation(at)
    local best, bestAway = nil, 9999
    for _, station in ipairs(Config.Stations) do
        local away = GetDistanceBetween(at, station.coords)
        if away < bestAway then best, bestAway = station, away end
    end
    return best, bestAway
end

-- the train entry for a model, preferably of that company
function FindTrainConfig(model, company)
    local anyOwner
    for _, train in ipairs(Config.Trains) do
        if train.model == model then
            if train.company == company then return train end
            anyOwner = anyOwner or train
        end
    end
    return anyOwner
end
