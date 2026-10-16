-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_huntingpets | client: the shop clerks (and an optional display pet) that appear when the player is near

local clerks, display = {}, {}      -- shop index -> ped

local function fade(ped, from, to)
    local step = from < to and 51 or -51
    for alpha = from, to, step do
        Wait(50)
        SetEntityAlpha(ped, alpha, false)
    end
end

-- a frozen, harmless ped that fades in; `scenario` is optional
local function makePed(model, at, scenario)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(50) end

    local ped = CreatePed(model, at.x, at.y, at.z - 1.0, at.w, false, false, 0, 0)
    SetEntityAlpha(ped, 0, false)
    SetRandomOutfitVariation(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    local group = GetPedRelationshipGroupHash(ped)
    SetPedRelationshipGroupHash(ped, group)
    SetRelationshipBetweenGroups(1, group, `PLAYER`)
    if scenario then TaskStartScenarioInPlace(ped, joaat(scenario), -1, true) end
    if Config.FadeIn then fade(ped, 0, 255) end
    return ped
end

function SpawnShopNPC(model, at, scenario)
    local ped = makePed(model, at, scenario)
    JRS.AddEntityTarget(ped, { {
        name = 'jrs_huntingpets_shop', label = L('label_petshop'), icon = 'fa-solid fa-paw', distance = 3.0,
        onSelect = function() TriggerEvent('jrs_huntingpets:client:openShop') end,
    } })
    return ped
end

function SpawnDecoPet(model, at) return makePed(model, at) end

local function remove(list, key)
    local ped = list[key]
    if Config.FadeIn then fade(ped, 255, 0) end
    DeletePed(ped)
    list[key] = nil
end

-- keeps one ped per shop while the player is within Config.DistanceSpawn
local function keep(list, key, at, spawn)
    local close = #(GetEntityCoords(PlayerPedId()) - at.xyz) < Config.DistanceSpawn
    if close and not list[key] then list[key] = spawn()
    elseif not close and list[key] then remove(list, key) end
end

CreateThread(function()
    while true do
        Wait(500)
        for index, shop in pairs(Config.Shops) do
            keep(clerks, index, shop.npccoords, function() return SpawnShopNPC(shop.npcmodel, shop.npccoords, shop.scenario) end)
            -- a display pet only for shops that define one
            if shop.npcpetcoords and shop.npcpetmodel then
                keep(display, index, shop.npcpetcoords, function() return SpawnDecoPet(shop.npcpetmodel, shop.npcpetcoords) end)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, list in ipairs({ clerks, display }) do
        for key, ped in pairs(list) do
            DeletePed(ped)
            list[key] = nil
        end
    end
end)
