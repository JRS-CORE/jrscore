-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_huntingpets | client: the hunting dog
-- The dog follows the player, can sit, play poses, retrieve animals the player shot (hunt mode), defend
-- against whoever the player fights and gets hungry. Pups grow with xp (fed with Config.AnimalFood).

local dog = nil                 -- the dog ped
local dogId = nil               -- its row id
local dogXp = 0
local spawnCooldown = 0         -- seconds until a dog can be called again
local combatCooldown = 0
local feedTimer = 0             -- seconds since the last meal
local hungry, hungryTold, feedPromptsAdded = false, false, false
local huntMode, fetching, tracking = false, false, false
local fetched = {}              -- animal -> true once retrieved or ignored
local anim = false              -- a pose is playing

-- prompts that exist per ped (the dog or a target): kind -> ped -> prompt handle
local prompts = { follow = {}, stay = {}, hunt = {}, feed = {}, attack = {}, track = {} }
local offered = { attack = {}, track = {} }          -- target ped -> true once its prompt was made

function GetCurrentDogPed() return dog end
DogAnimActive = false

-- ------------------------------------------------------------------ small helpers

local function forgetDog()
    if dog then
        JRS.RemoveEntityTarget(dog)
        DeleteEntity(dog)
    end
    dog, dogId = nil, nil
    if ActivePetType == 'dog' then ActivePetType = nil end
end

local function playOn(ped, dict, name)
    RequestAnimDict(dict)
    local waited = 0
    while not HasAnimDictLoaded(dict) and waited <= 5000 do
        waited = waited + 100
        Wait(100)
    end
    TaskPlayAnim(ped, dict, name, 1.0, 1.0, -1, 1, 0, false, false, false)
end

local function sit() playOn(dog, 'amb_creature_mammal@world_dog_sitting@base', 'base') end
local function eat() playOn(dog, 'amb_creature_mammal@world_dog_eating_ground@base', 'base') end

local function addPrompt(kind, entity, control, label)
    local group = Citizen.InvokeNative(0xB796970BD125FCE8, entity, Citizen.ResultAsLong())
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, control)
    PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', label))
    PromptSetEnabled(prompt, true)
    PromptSetVisible(prompt, true)
    PromptSetStandardMode(prompt, true)
    PromptSetGroup(prompt, group)
    PromptRegisterEnd(prompt)
    prompts[kind][entity] = prompt
end

local function pressed(kind, entity)
    local prompt = prompts[kind][entity]
    return prompt and PromptHasStandardModeCompleted(prompt)
end

local function toggleHunt()
    huntMode = not huntMode
    if huntMode then Notify(L('info_dog_huntmode_on'), '', 'SUCCESS') else Notify(L('info_dog_huntmode_off'), '', 'TIP') end
end

-- ------------------------------------------------------------------ following and staying

function followOwner(ped, owner, inShop)
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    TaskFollowToOffsetOfEntity(ped, owner, 0.0, -1.5, 0.0, 1.0, -1, Config.DogPetAttributes.FollowDistance * 100000000, 1, 1, 0, 0, 1)
    if inShop then Citizen.InvokeNative(0x489FFCCCE7392B55, ped, owner) end
end

local function stay(ped)
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    sit()
    FreezeEntityPosition(ped, true)
end

-- ------------------------------------------------------------------ poses and the look-at menu

local POSES <const> = {
    { 'anim_dog_rollground', 'amb_creature_mammal@world_dog_roll_ground@idle', 'idle_c' },
    { 'anim_dog_begging', 'amb_creature_mammal@world_dog_begging@idle', 'idle_a' },
    { 'anim_dog_resting', 'amb_creature_mammal@world_dog_resting@base', 'base' },
    { 'anim_dog_sleeping', 'amb_creature_mammal@world_dog_sleeping@base', 'base' },
    { 'anim_dog_digging', 'amb_creature_mammal@world_dog_digging@base', 'base' },
    { 'anim_dog_barkingup', 'amb_creature_mammal@world_dog_barking_up@base', 'base' },
    { 'anim_dog_barkingvicious', 'amb_creature_mammal@world_dog_barking_vicious@base', 'base' },
    { 'anim_dog_barkgrowl', 'amb_creature_mammal@world_dog_bark_growl@base', 'base' },
    { 'anim_dog_guardgrowl', 'amb_creature_mammal@world_dog_guard_growl@base', 'base' },
    { 'anim_dog_howlingsitting', 'amb_creature_mammal@world_dog_howling_sitting@base', 'base' },
    { 'anim_dog_sniffingground', 'amb_creature_mammal@world_dog_sniffing_ground@base', 'base' },
    { 'anim_dog_pooping', 'amb_creature_mammal@world_dog_pooping@base', 'base' },
}

local setTargets

local function stopPose()
    if not dog then return end
    ClearPedTasks(dog)
    ClearPedSecondaryTask(dog)
    FreezeEntityPosition(dog, false)
    followOwner(dog, PlayerPedId(), false)
    DogAnimActive, anim = false, false
    setTargets()
end

local function startPose(dict, name)
    if not dog then return end
    ClearPedTasks(dog)
    ClearPedSecondaryTask(dog)
    playOn(dog, dict, name)
    FreezeEntityPosition(dog, true)
    DogAnimActive, anim = true, true
    setTargets()
end

-- what the player can pick when looking at the dog
setTargets = function()
    if not dog then return end
    local function option(name, label, icon, onSelect) return { name = name, label = label, icon = icon, onSelect = onSelect, distance = 2.5 } end

    local list = { option('dog_animations', L('ui_dog_actions_title'), 'fa-solid fa-paw', function() TriggerEvent('jrs_huntingpets:client:dogAnimations') end) }
    if DogAnimActive then list[#list + 1] = option('dog_stop_anim', L('ui_stop_animation'), 'fa-solid fa-pause', stopPose) end
    list[#list + 1] = option('dog_hunt_mode', L('ui_huntmode_label', huntMode and L('ui_on') or L('ui_off')), 'fa-solid fa-crosshairs', function()
        toggleHunt()
        setTargets()
    end)

    JRS.RemoveEntityTarget(dog)
    JRS.AddEntityTarget(dog, list)
end

RegisterNetEvent('jrs_huntingpets:client:dogAnimations', function()
    if not dog then return end

    local rows = {
        { label = L('prompt_dog_follow'), action = 'follow' },
        { label = L('prompt_dog_stay'), action = 'stay' },
        { label = L('prompt_dog_huntmode'), action = 'huntmode' },
    }
    if DogAnimActive then rows[#rows + 1] = { label = L('ui_stop_animation'), action = 'stop' } end
    for _, pose in ipairs(POSES) do rows[#rows + 1] = { label = L(pose[1]), action = 'anim', dict = pose[2], dictname = pose[3] } end

    SendNUIMessage({ action = 'openDogAnims', title = L('ui_dog_actions_title'), animations = rows, ui = GetUiLocale() })
    SetNuiFocus(true, true)
end)

RegisterNUICallback('dogAnimSelect', function(data, done)
    done('ok')
    SetNuiFocus(false, false)
    if not dog then return end

    local act = data.action
    if act == 'stop' then stopPose()
    elseif act == 'putaway' then TriggerEvent('jrs_huntingpets:client:putawayDog')
    elseif act == 'follow' then followOwner(dog, PlayerPedId(), false)
    elseif act == 'stay' then stay(dog)
    elseif act == 'huntmode' then toggleHunt()
    elseif act == 'anim' and data.dict and data.dictname then startPose(data.dict, data.dictname) end
end)

-- ------------------------------------------------------------------ the dog itself

-- rewards the dog cannot be spoiled by pain or fear: levels for health, stamina, attack and defence
local function toughen(ped)
    for core = 0, 2 do
        Citizen.InvokeNative(0x09A59688C26D88DF, ped, core, 1100)
        Citizen.InvokeNative(0x75415EE0CB583760, ped, core, 1100)
        Citizen.InvokeNative(0x5DA12E025D47D4E5, ped, core, 10)
        Citizen.InvokeNative(0x920F9488BD115EFB, ped, core, 10)
        Citizen.InvokeNative(0xF6A7C08DF2E28B28, ped, core, 5000.0, false)
    end
end

local FRIENDS <const> = {
    `PLAYER`, 143493179, -2040077242, 1222652248, 1077299173, -887307738, -1998572072, -661858713, 1232372459, -1836932466,
    1878159675, 1078461828, -1535431934, 1862763509, -1663301869, -1448293989, -1201903818, -886193798, -1996978098, 555364152,
    -2020052692, 707888648, 378397108, -350651841, -1538724068, 1030835986, -1919885972, -1976316465, 841021282, 889541022,
    -1329647920, -319516747, -767591988, -989642646, 1986610512, -1683752762,
}

local function befriend(ped)
    local mine = GetPedRelationshipGroupHash(ped)
    for _, other in ipairs(FRIENDS) do SetRelationshipBetweenGroups(1, mine, other) end
end

-- size and abilities follow the growth stage: pup, half grown, full grown
local function applyGrowth(ped)
    if not Config.RaiseAnimal then
        dogXp = Config.DogFullGrownXp
        addPrompt('stay', ped, 0x9959A6F0, L('prompt_dog_stay'))
        addPrompt('hunt', ped, 0xB2F377E8, L('prompt_dog_huntmode'))
        return
    end

    if dogXp >= Config.DogFullGrownXp then
        SetPedScale(ped, 1.0)
        addPrompt('stay', ped, 0x9959A6F0, L('prompt_dog_stay'))
        addPrompt('hunt', ped, 0xB2F377E8, L('prompt_dog_huntmode'))
    elseif dogXp >= Config.DogFullGrownXp / 2 then
        SetPedScale(ped, 0.8)
        addPrompt('stay', ped, 0x9959A6F0, L('prompt_dog_stay'))
    else
        SetPedScale(ped, 0.6)
    end
end

local function makeDog(model, owner, at, skin, inShop, xp)
    if dog then
        JRS.RemoveEntityTarget(dog)
        DeleteEntity(dog)
    end
    dogXp = xp

    local hash = joaat(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(500) end

    dog = CreatePed(hash, at.x, at.y, at.z, at.h, true, true)
    NetworkRegisterEntityAsNetworked(dog)
    SetNetworkIdExistsOnAllMachines(NetworkGetNetworkIdFromEntity(dog), true)
    SetEntityAsMissionEntity(dog, true, true)
    Citizen.InvokeNative(0x77FF8D35EEC6BBC4, dog, skin, 0)                 -- outfit preset
    Citizen.InvokeNative(0x23f74c2FDA6E7C61, -1749618580, dog)             -- map blip
    if Config.DogPetAttributes.Invincible then SetEntityInvincible(dog, true) end

    addPrompt('follow', dog, 0x63A38F2C, L('prompt_dog_follow'))

    if Config.NoFear then
        Citizen.InvokeNative(0x013A7BA5015C1372, dog, true)
        Citizen.InvokeNative(0x3B005FF0538ED2A9, dog)
        Citizen.InvokeNative(0xAEB97D84CDF3C00B, dog, false)
        Citizen.InvokeNative(0x9F52AD32D5AA413D, dog, false)
        Citizen.InvokeNative(0xC1B1E9A034A63A62, dog, 0)
        Citizen.InvokeNative(0xB8B6430EAD2D2437, dog, false)
    end

    toughen(dog)
    befriend(dog)
    SetPedAsGroupMember(dog, GetPedGroupIndex(owner))
    applyGrowth(dog)

    DogAnimActive = false
    setTargets()
    ActivePetType = 'dog'

    while GetScriptTaskStatus(dog, 0x4924437d) ~= 8 do Wait(1000) end
    followOwner(dog, owner, inShop)
end

RegisterNetEvent('jrs_huntingpets:client:spawnDog', function(id, model, skin, inShop, xp)
    dogId = id
    if dog then return end
    if HasActivePet() and ActivePetType ~= 'dog' then return Notify(L('error_one_pet_only'), '', 'ERROR') end
    if spawnCooldown > 0 then return end
    spawnCooldown = Config.DogPetAttributes.SpawnLimiter

    hungry, feedTimer, hungryTold, feedPromptsAdded = false, 0, false, false

    local me = PlayerPedId()
    if not inShop then
        local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(me, 0.0, -5.0, 0.3))
        local _, ground = GetGroundZAndNormalFor_3dCoord(x, y, z + 10)
        return makeDog(model, me, { x = x, y = y, z = ground }, skin, false, xp)
    end

    -- from the shop: the dog appears at the shop that is close
    for _, shop in pairs(Config.Shops) do
        if #(GetEntityCoords(me) - shop.npccoords.xyz) < Config.DistanceSpawn then
            local s = shop.Spawndog
            return makeDog(model, me, { x = s.x, y = s.y, z = s.z, h = s.w }, skin, true, xp)
        end
    end
end)

RegisterNetEvent('jrs_huntingpets:client:putawayDog', function()
    if not dog then return end
    DogAnimActive = false
    forgetDog()
end)

RegisterNetEvent('jrs_huntingpets:client:sellDogConfirm', function()
    if not dog then return end
    forgetDog()
    spawnCooldown = 0
end)

RegisterCommand('calldog', function() TriggerServerEvent('jrs_huntingpets:server:loadDog') end)
RegisterCommand('fleedog', function() TriggerEvent('jrs_huntingpets:client:putawayDog') end)

CreateThread(function()
    while true do
        if Config.CallDogKey and IsControlJustPressed(0, Config.DogKeys[Config.DogTriggerKeys.CallDog]) then
            TriggerServerEvent('jrs_huntingpets:server:loadDog')
        end
        Wait(1)
    end
end)

-- ------------------------------------------------------------------ retrieving what the player shot

-- animals in `radius` of `ped` that satisfy `want(entity)`; the closest one
local function closestNear(ped, radius, want)
    local at = GetEntityCoords(ped)
    local set = CreateItemset(true)
    local count = Citizen.InvokeNative(0x59B57C4B06531E1E, at, radius, set, 1, Citizen.ResultAsInteger())
    local best, bestAway = nil, radius
    for i = 0, count - 1 do
        local entity = GetIndexedItemInItemset(i, set)
        if entity ~= ped and want(entity) then
            local away = #(at - GetEntityCoords(entity))
            if away < bestAway then best, bestAway = entity, away end
        end
    end
    if IsItemsetValid(set) then DestroyItemset(set) end
    return best
end

function GetClosestAnimalPed(ped, radius)
    return closestNear(ped, radius, function(e)
        return GetPedType(e) == 28 and IsEntityDead(e) and not fetched[e] and Config.DogRetrievableAnimals[GetEntityModel(e)]
    end)
end

-- note: like the original this returns the LAST ped in combat with the player, not the nearest
function GetClosestFightingPed(ped, radius)
    local found
    local at = GetEntityCoords(ped)
    local set = CreateItemset(true)
    local count = Citizen.InvokeNative(0x59B57C4B06531E1E, at, radius, set, 1, Citizen.ResultAsInteger())
    for i = 0, count - 1 do
        local entity = GetIndexedItemInItemset(i, set)
        if entity ~= ped and entity ~= dog and IsPedInCombat(ped, entity) then found = entity end
    end
    if IsItemsetValid(set) then DestroyItemset(set) end
    return found
end

-- walk to `where()` until close; true when reached
local function goTo(where, closeEnough, speed)
    while true do
        Wait(2000)
        local at = where()
        TaskGoToCoordAnyMeans(dog, at, speed, 0, 0, 786603, 0xbf800000)
        if #(at - GetEntityCoords(dog)) <= closeEnough then return end
    end
end

function RetrieveKill(prey)
    local me = PlayerPedId()
    fetching = true
    TaskGoToCoordAnyMeans(dog, GetEntityCoords(prey), 2.0, 0, 0, 786603, 0xbf800000)
    goTo(function() return GetEntityCoords(prey) end, 2.5, 2.0)

    AttachEntityToEntity(prey, dog, GetPedBoneIndex(dog, 21030), 0.14, 0.14, 0.09798, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    fetched[prey] = true
    ReturnKillToPlayer(prey, me)
end

function ReturnKillToPlayer(prey, me)
    TaskGoToCoordAnyMeans(dog, GetEntityCoords(me), 1.5, 0, 0, 786603, 0xbf800000)
    goTo(function() return GetEntityCoords(me) end, 2.0, 1.5)

    DetachEntity(prey)
    Wait(100)
    PlaceObjectOnGroundProperly(prey, true)
    fetching = false
    followOwner(dog, me, false)
end

-- ------------------------------------------------------------------ the dog's day: hunt, defend, hunger, death

CreateThread(function()
    while true do
        Wait(1000)

        if dog and not fetching and not hungry and huntMode and (not Config.RaiseAnimal or dogXp >= Config.DogFullGrownXp) then
            local me = PlayerPedId()
            local prey = GetClosestAnimalPed(me, Config.DogSearchRadius)
            if prey and GetPedType(prey) == 28 and IsEntityDead(prey) and not fetched[prey] then
                if GetPedSourceOfDeath(prey) == me then
                    if Config.DogRetrievableAnimals[GetEntityModel(prey)] then RetrieveKill(prey) end
                else
                    fetched[prey] = true                          -- not the player's kill: never fetch it
                end
            end
        end

        if dog and Config.DefensiveMode and combatCooldown <= 0 then
            local enemy = GetClosestFightingPed(PlayerPedId(), 50.0)
            if enemy then
                ClearPedTasks(dog)
                TaskCombatPed(dog, enemy, 0, 16)
                combatCooldown = 15
            end
        end

        if dog then
            feedTimer = feedTimer + 1
            if feedTimer >= Config.DogFeedInterval then
                hungry = true
                if not feedPromptsAdded then
                    addPrompt('feed', dog, 0xCEFD9220, L('prompt_dog_feed'))
                    feedPromptsAdded = true
                end
                if not hungryTold and Config.NotifyWhenHungry then
                    Notify(L('info_hungry'), '', 'TIP')
                    hungryTold = true
                end
            end

            if IsEntityDead(dog) then
                spawnCooldown = Config.DogPetAttributes.DeathCooldown
                Notify(L('error_petdead'), '', 'ERROR')
                Wait(3000)
                forgetDog()
            end
        end

        if spawnCooldown > 0 then spawnCooldown = spawnCooldown - 1 end
        if combatCooldown > 0 then combatCooldown = combatCooldown - 1 end
    end
end)

-- ------------------------------------------------------------------ prompts on what the player aims at

-- should a prompt be made for `target`, given the Only* settings of that kind?
local function wanted(target, onlyAnimals, onlyNpc, onlyPlayers)
    if onlyAnimals and GetPedType(target) == 28 then return true end
    if onlyNpc and not IsPedAPlayer(target) then return true end
    if onlyPlayers and IsPedAPlayer(target) then return true end
    return not onlyAnimals and not onlyNpc and not onlyPlayers
end

local function feedNow(me)
    TaskTurnPedToFaceEntity(me, dog, 5000)
    TaskTurnPedToFaceEntity(dog, me, 5000)
    TaskStartScenarioInPlace(me, joaat('WORLD_HUMAN_CROUCH_INSPECT'), 60000, true, false, false, false)
    Wait(2000)
    eat()
    Wait(4000)
    ClearPedTasks(me)
    Wait(4000)
    ClearPedTasks(dog)
    followOwner(dog, me, false)
    TriggerServerEvent('jrs_huntingpets:server:feedDog', dogId)
end

CreateThread(function()
    while true do
        Wait(0)
        local id = PlayerId()
        if not IsPlayerTargettingAnything(id) then
            Wait(500)
        else
            local _, entity = GetPlayerTargetEntity(id)

            if pressed('feed', entity) then
                if entity == dog and feedTimer >= Config.DogFeedInterval then feedNow(PlayerPedId()) end
                Wait(2000)
            end
            if pressed('follow', entity) then
                if tracking then
                    tracking = false
                    ClearPedTasks(dog)
                end
                followOwner(dog, PlayerPedId(), false)
                Wait(2000)
            end
            if pressed('stay', entity) then
                stay(dog)
                Wait(2000)
            end
            if pressed('attack', entity) then
                local _, group = AddRelationshipGroup('attackedPeds')
                SetPedRelationshipGroupHash(entity, group)
                SetRelationshipBetweenGroups(5, GetPedRelationshipGroupHash(dog), GetPedRelationshipGroupHash(entity))
                TaskCombatPed(dog, entity, 0, 16)
            end
            if pressed('track', entity) then
                TaskFollowToOffsetOfEntity(dog, entity, 0.0, -1.5, 0.0, 1.0, -1, 2 * 100000000, 1, 1, 0, 0, 1)
            end
            if pressed('hunt', entity) then toggleHunt() end

            -- the target gets attack / track prompts once, when the settings allow
            if dog and entity ~= dog then
                if Config.AttackCommand and not offered.attack[entity]
                    and wanted(entity, Config.AttackOnlyAnimals, Config.AttackOnlyNPC, Config.AttackOnlyPlayers) then
                    addPrompt('attack', entity, 0x63A38F2C, L('prompt_dog_attack'))
                    offered.attack[entity] = true
                end
                if Config.TrackCommand and not offered.track[entity]
                    and wanted(entity, Config.TrackOnlyAnimals, Config.TrackOnlyNPC, Config.TrackOnlyPlayers) then
                    addPrompt('track', entity, 0x9959A6F0, L('prompt_dog_track'))
                    offered.track[entity] = true
                end
            end
        end
    end
end)

-- the server fed the dog: it may grow
RegisterNetEvent('jrs_huntingpets:client:dogFed', function(xp)
    if Config.RaiseAnimal and dog then
        dogXp = xp
        applyGrowth(dog)
    end
    hungry, feedTimer, hungryTold = false, 0, false
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then TriggerEvent('jrs_huntingpets:client:putawayDog') end
end)
