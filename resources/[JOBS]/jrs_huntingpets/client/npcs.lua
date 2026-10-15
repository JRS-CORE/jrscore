-- jrs_huntingpets: NPC Spawning
local spawnedPeds = {}
local spawnedPetPeds = {}

--------------------------------------
-- SHOP NPC SPAWN
--------------------------------------
CreateThread(function()
    while true do
        Wait(500)
        for k, v in pairs(Config.Shops) do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - v.npccoords.xyz)

            if distance < Config.DistanceSpawn and not spawnedPeds[k] then
                local spawnedPed = SpawnShopNPC(v.npcmodel, v.npccoords, v.scenario)
                spawnedPeds[k] = { spawnedPed = spawnedPed }
            end

            if distance >= Config.DistanceSpawn and spawnedPeds[k] then
                if Config.FadeIn then
                    for i = 255, 0, -51 do
                        Wait(50)
                        SetEntityAlpha(spawnedPeds[k].spawnedPed, i, false)
                    end
                end
                DeletePed(spawnedPeds[k].spawnedPed)
                spawnedPeds[k] = nil
            end
        end
    end
end)

function SpawnShopNPC(npcmodel, npccoords, scenario)
    RequestModel(npcmodel)
    while not HasModelLoaded(npcmodel) do
        Wait(50)
    end
    local spawnedPed = CreatePed(npcmodel, npccoords.x, npccoords.y, npccoords.z - 1.0, npccoords.w, false, false, 0, 0)
    SetEntityAlpha(spawnedPed, 0, false)
    SetRandomOutfitVariation(spawnedPed, true)
    SetEntityCanBeDamaged(spawnedPed, false)
    SetEntityInvincible(spawnedPed, true)
    FreezeEntityPosition(spawnedPed, true)
    SetBlockingOfNonTemporaryEvents(spawnedPed, true)
    -- Relationship
    SetPedRelationshipGroupHash(spawnedPed, GetPedRelationshipGroupHash(spawnedPed))
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(spawnedPed), `PLAYER`)
    -- Scenario
    if scenario then
        TaskStartScenarioInPlace(spawnedPed, joaat(scenario), -1, true)
    end
    -- Fade in
    if Config.FadeIn then
        for i = 0, 255, 51 do
            Wait(50)
            SetEntityAlpha(spawnedPed, i, false)
        end
    end
    -- the JRS interaction prompt
    JRS.AddEntityTarget(spawnedPed, {
        {
            name = 'jrs_huntingpets_shop',
            label = L('label_petshop'),
            icon = 'fa-solid fa-paw',
            onSelect = function()
                TriggerEvent('jrs_huntingpets:client:openShop')
            end,
            distance = 3.0
        },
    })
    return spawnedPed
end

--------------------------------------
-- SHOP PET NPC SPAWN (decoration)
--------------------------------------
CreateThread(function()
    while true do
        Wait(500)
        for k2, v2 in pairs(Config.Shops) do
            -- Decorative display pet: skip shops that don't define one (no
            -- shop in config_shared.lua currently sets npcpetmodel/npcpetcoords,
            -- which previously errored every 500ms trying to index a nil value).
            if not v2.npcpetcoords or not v2.npcpetmodel then goto continue end

            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - v2.npcpetcoords.xyz)

            if distance < Config.DistanceSpawn and not spawnedPetPeds[k2] then
                local spawnedPed2 = SpawnDecoPet(v2.npcpetmodel, v2.npcpetcoords)
                spawnedPetPeds[k2] = { spawnedPed2 = spawnedPed2 }
            end

            if distance >= Config.DistanceSpawn and spawnedPetPeds[k2] then
                if Config.FadeIn then
                    for i2 = 255, 0, -51 do
                        Wait(50)
                        SetEntityAlpha(spawnedPetPeds[k2].spawnedPed2, i2, false)
                    end
                end
                DeletePed(spawnedPetPeds[k2].spawnedPed2)
                spawnedPetPeds[k2] = nil
            end

            ::continue::
        end
    end
end)

function SpawnDecoPet(npcpetmodel, npcpetcoords)
    RequestModel(npcpetmodel)
    while not HasModelLoaded(npcpetmodel) do
        Wait(50)
    end
    local spawnedPed2 = CreatePed(npcpetmodel, npcpetcoords.x, npcpetcoords.y, npcpetcoords.z - 1.0, npcpetcoords.w, false, false, 0, 0)
    SetEntityAlpha(spawnedPed2, 0, false)
    SetRandomOutfitVariation(spawnedPed2, true)
    SetEntityCanBeDamaged(spawnedPed2, false)
    SetEntityInvincible(spawnedPed2, true)
    FreezeEntityPosition(spawnedPed2, true)
    SetBlockingOfNonTemporaryEvents(spawnedPed2, true)
    SetPedRelationshipGroupHash(spawnedPed2, GetPedRelationshipGroupHash(spawnedPed2))
    SetRelationshipBetweenGroups(1, GetPedRelationshipGroupHash(spawnedPed2), `PLAYER`)
    if Config.FadeIn then
        for i2 = 0, 255, 51 do
            Wait(50)
            SetEntityAlpha(spawnedPed2, i2, false)
        end
    end
    return spawnedPed2
end

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for k, v in pairs(spawnedPeds) do
        if v.spawnedPed then DeletePed(v.spawnedPed) end
        spawnedPeds[k] = nil
    end
    for k2, v2 in pairs(spawnedPetPeds) do
        if v2.spawnedPed2 then DeletePed(v2.spawnedPed2) end
        spawnedPetPeds[k2] = nil
    end
end)
