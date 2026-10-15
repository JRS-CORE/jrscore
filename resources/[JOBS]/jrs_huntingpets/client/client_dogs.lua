-- jrs_huntingpets: Dog Client
local keys = Config.DogKeys
local pressTime = 0
local recentlySpawned = 0
local currentDogPed = nil
local currentDogId = nil
local dogXP = 0
local fetchedObj = nil
local Retrieving = false
local RetrievedEntities = {}
local FeedTimer = 0
local recentlyCombat = 0
local isDogHungry = false
local notifyHungry = false
local HuntMode = false
local isTracking = false
local AddedFeedPrompts = false

-- Prompt tables
local HuntModePrompt = {}
local FeedPrompt = {}
local AttackPrompt = {}
local TrackPrompt = {}
local StayPrompt = {}
local FollowPrompt = {}
local AddedAttackPrompt = {}
local AddedTrackPrompt = {}
local SearchDatabasePrompt = {}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════
local function getJob()
    local me = JRS.Me()
    return me and me.job or nil
end

local function CanTrackDatabase()
    return getJob() == Config.DogTrackingJob
end

function GetCurrentDogPed()
    return currentDogPed
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════
local function AnimationPet(entity, dict, name)
    local waiting = 0
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        waiting = waiting + 100
        Wait(100)
        if waiting > 5000 then break end
    end
    TaskPlayAnim(entity, dict, name, 1.0, 1.0, -1, 1, 0, false, false, false)
end

local function DogEatAnimation()
    AnimationPet(currentDogPed, "amb_creature_mammal@world_dog_eating_ground@base", "base")
end

local function DogSitAnimation()
    AnimationPet(currentDogPed, "amb_creature_mammal@world_dog_sitting@base", "base")
end

-- ═══════════════════════════════════════════════════════════
-- DOG ANIMATIONS MENU (NUI - matches RDR2 leather & gold UI)
-- ═══════════════════════════════════════════════════════════
local function DogCompanionAnims()
    return {
        { animname = L('anim_dog_rollground'), dict = 'amb_creature_mammal@world_dog_roll_ground@idle', dictname = 'idle_c' },
        { animname = L('anim_dog_begging'), dict = 'amb_creature_mammal@world_dog_begging@idle', dictname = 'idle_a' },
        { animname = L('anim_dog_resting'), dict = 'amb_creature_mammal@world_dog_resting@base', dictname = 'base' },
        { animname = L('anim_dog_sleeping'), dict = 'amb_creature_mammal@world_dog_sleeping@base', dictname = 'base' },
        { animname = L('anim_dog_digging'), dict = 'amb_creature_mammal@world_dog_digging@base', dictname = 'base' },
        { animname = L('anim_dog_barkingup'), dict = 'amb_creature_mammal@world_dog_barking_up@base', dictname = 'base' },
        { animname = L('anim_dog_barkingvicious'), dict = 'amb_creature_mammal@world_dog_barking_vicious@base', dictname = 'base' },
        { animname = L('anim_dog_barkgrowl'), dict = 'amb_creature_mammal@world_dog_bark_growl@base', dictname = 'base' },
        { animname = L('anim_dog_guardgrowl'), dict = 'amb_creature_mammal@world_dog_guard_growl@base', dictname = 'base' },
        { animname = L('anim_dog_howlingsitting'), dict = 'amb_creature_mammal@world_dog_howling_sitting@base', dictname = 'base' },
        { animname = L('anim_dog_sniffingground'), dict = 'amb_creature_mammal@world_dog_sniffing_ground@base', dictname = 'base' },
        { animname = L('anim_dog_pooping'), dict = 'amb_creature_mammal@world_dog_pooping@base', dictname = 'base' },
    }
end

DogAnimActive = false

local RegisterDogTarget
local StopDogAnimation

RegisterDogTarget = function()
    if not currentDogPed then return end
    local options = {
        {
            name = 'dog_animations',
            label = L('ui_dog_actions_title'),
            icon = 'fa-solid fa-paw',
            onSelect = function()
                TriggerEvent('jrs_huntingpets:client:dogAnimations')
            end,
            distance = 2.5,
        },
    }
    if DogAnimActive then
        options[#options + 1] = {
            name = 'dog_stop_anim',
            label = L('ui_stop_animation'),
            icon = 'fa-solid fa-pause',
            onSelect = function()
                StopDogAnimation()
            end,
            distance = 2.5,
        }
    end
    options[#options + 1] = {
        name = 'dog_hunt_mode',
        label = L('ui_huntmode_label', HuntMode and L('ui_on') or L('ui_off')),
        icon = 'fa-solid fa-crosshairs',
        onSelect = function()
            HuntMode = not HuntMode
            if HuntMode then
                Notify(L('info_dog_huntmode_on'), '', 'SUCCESS')
            else
                Notify(L('info_dog_huntmode_off'), '', 'TIP')
            end
            RegisterDogTarget()
        end,
        distance = 2.5,
    }
    JRS.RemoveEntityTarget(currentDogPed)
    JRS.AddEntityTarget(currentDogPed, options)
end

StopDogAnimation = function()
    if not currentDogPed then return end
    ClearPedTasks(currentDogPed)
    ClearPedSecondaryTask(currentDogPed)
    FreezeEntityPosition(currentDogPed, false)
    followOwner(currentDogPed, PlayerPedId(), false)
    DogAnimActive = false
    RegisterDogTarget()
end

local function PlayDogAnimation(dict, dictname)
    if not currentDogPed then return end
    ClearPedTasks(currentDogPed)
    ClearPedSecondaryTask(currentDogPed)
    AnimationPet(currentDogPed, dict, dictname)
    FreezeEntityPosition(currentDogPed, true)
    DogAnimActive = true
    RegisterDogTarget()
end

RegisterNetEvent('jrs_huntingpets:client:dogAnimations', function()
    if not currentDogPed then return end

    local animations = {
        { label = L('prompt_dog_follow'), action = 'follow' },
        { label = L('prompt_dog_stay'), action = 'stay' },
        { label = L('prompt_dog_huntmode'), action = 'huntmode' },
    }
    if DogAnimActive then
        animations[#animations + 1] = { label = L('ui_stop_animation'), action = 'stop' }
    end
    for _, v in ipairs(DogCompanionAnims()) do
        animations[#animations + 1] = {
            label = v.animname,
            action = 'anim',
            dict = v.dict,
            dictname = v.dictname,
        }
    end

    SendNUIMessage({ action = 'openDogAnims', title = L('ui_dog_actions_title'), animations = animations, ui = GetUiLocale() })
    SetNuiFocus(true, true)
end)

RegisterNUICallback('dogAnimSelect', function(data, cb)
    cb('ok')
    if not currentDogPed then
        SetNuiFocus(false, false)
        return
    end
    SetNuiFocus(false, false)
    if data.action == 'stop' then
        StopDogAnimation()
    elseif data.action == 'putaway' then
        TriggerEvent('jrs_huntingpets:client:putawayDog')
    elseif data.action == 'follow' then
        FreezeEntityPosition(currentDogPed, false)
        followOwner(currentDogPed, PlayerPedId(), false)
    elseif data.action == 'stay' then
        ClearPedTasks(currentDogPed)
        ClearPedSecondaryTask(currentDogPed)
        DogSitAnimation()
        FreezeEntityPosition(currentDogPed, true)
    elseif data.action == 'huntmode' then
        HuntMode = not HuntMode
        if HuntMode then
            Notify(L('info_dog_huntmode_on'), '', 'SUCCESS')
        else
            Notify(L('info_dog_huntmode_off'), '', 'TIP')
        end
    elseif data.action == 'anim' and data.dict and data.dictname then
        PlayDogAnimation(data.dict, data.dictname)
    end
end)

-- ═══════════════════════════════════════════════════════════
-- DOG BEHAVIOR & ATTRIBUTES
-- ═══════════════════════════════════════════════════════════
local function SetDogAttributes(entity)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 0, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 1, 1100)
    Citizen.InvokeNative(0x09A59688C26D88DF, entity, 2, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 0, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 1, 1100)
    Citizen.InvokeNative(0x75415EE0CB583760, entity, 2, 1100)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 0, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 1, 10)
    Citizen.InvokeNative(0x5DA12E025D47D4E5, entity, 2, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 0, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 1, 10)
    Citizen.InvokeNative(0x920F9488BD115EFB, entity, 2, 10)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 0, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 1, 5000.0, false)
    Citizen.InvokeNative(0xF6A7C08DF2E28B28, entity, 2, 5000.0, false)
end

local function setDogBehavior(petPed)
    local dogGroup = GetPedRelationshipGroupHash(petPed)
    local groups = {
        GetHashKey('PLAYER'), 143493179, -2040077242, 1222652248, 1077299173,
        -887307738, -1998572072, -661858713, 1232372459, -1836932466,
        1878159675, 1078461828, -1535431934, 1862763509, -1663301869,
        -1448293989, -1201903818, -886193798, -1996978098, 555364152,
        -2020052692, 707888648, 378397108, -350651841, -1538724068,
        1030835986, -1919885972, -1976316465, 841021282, 889541022,
        -1329647920, -319516747, -767591988, -989642646, 1986610512, -1683752762
    }
    for _, g in ipairs(groups) do
        SetRelationshipBetweenGroups(1, dogGroup, g)
    end
end

function followOwner(dogPed, playerPed, isInShop)
    FreezeEntityPosition(dogPed, false)
    ClearPedTasks(dogPed)
    ClearPedSecondaryTask(dogPed)
    TaskFollowToOffsetOfEntity(dogPed, playerPed, 0.0, -1.5, 0.0, 1.0, -1, Config.DogPetAttributes.FollowDistance * 100000000, 1, 1, 0, 0, 1)
    if isInShop then
        Citizen.InvokeNative(0x489FFCCCE7392B55, dogPed, playerPed)
    end
end

local function petStay(dogPed)
    ClearPedTasks(dogPed)
    ClearPedSecondaryTask(dogPed)
    DogSitAnimation()
    FreezeEntityPosition(dogPed, true)
end

local function SET_BLIP_TYPE(animal)
    return Citizen.InvokeNative(0x23f74c2FDA6E7C61, -1749618580, animal)
end

local function SET_PED_OUTFIT_PRESET(dog, preset)
    return Citizen.InvokeNative(0x77FF8D35EEC6BBC4, dog, preset, 0)
end

-- ═══════════════════════════════════════════════════════════
-- PROMPTS
-- ═══════════════════════════════════════════════════════════
local function AddPrompt(promptTable, entity, controlAction, label)
    local group = Citizen.InvokeNative(0xB796970BD125FCE8, entity, Citizen.ResultAsLong())
    promptTable[entity] = PromptRegisterBegin()
    PromptSetControlAction(promptTable[entity], controlAction)
    local str = CreateVarString(10, 'LITERAL_STRING', label)
    PromptSetText(promptTable[entity], str)
    PromptSetEnabled(promptTable[entity], true)
    PromptSetVisible(promptTable[entity], true)
    PromptSetStandardMode(promptTable[entity], true)
    PromptSetGroup(promptTable[entity], group)
    PromptRegisterEnd(promptTable[entity])
end

-- ═══════════════════════════════════════════════════════════
-- SPAWN DOG
-- ═══════════════════════════════════════════════════════════
local function spawnDog(model, player, x, y, z, h, skin, playerPed, isdead, isshop, xp)
    local EntityPedCoord = GetEntityCoords(player)
    local EntitydogCoord = currentDogPed and GetEntityCoords(currentDogPed) or EntityPedCoord

    if #(EntityPedCoord - EntitydogCoord) > 100.0 or isshop or isdead or currentDogPed == nil then
        if currentDogPed ~= nil then
            JRS.RemoveEntityTarget(currentDogPed)
            DeleteEntity(currentDogPed)
        end

        dogXP = xp
        local hash = GetHashKey(model)
        RequestModel(hash)
        while not HasModelLoaded(hash) do Wait(500) end

        currentDogPed = CreatePed(hash, x, y, z, h, true, true)
        NetworkRegisterEntityAsNetworked(currentDogPed)
        local netId = NetworkGetNetworkIdFromEntity(currentDogPed)
        SetNetworkIdExistsOnAllMachines(netId, true)

        SetEntityAsMissionEntity(currentDogPed, true, true)
        SET_PED_OUTFIT_PRESET(currentDogPed, skin)
        SET_BLIP_TYPE(currentDogPed)

        if Config.DogPetAttributes.Invincible then
            SetEntityInvincible(currentDogPed, true)
        end

        -- Add prompts
        AddPrompt(FollowPrompt, currentDogPed, 0x63A38F2C, L('prompt_dog_follow'))

        if Config.NoFear then
            Citizen.InvokeNative(0x013A7BA5015C1372, currentDogPed, true)
            Citizen.InvokeNative(0x3B005FF0538ED2A9, currentDogPed)
            Citizen.InvokeNative(0xAEB97D84CDF3C00B, currentDogPed, false)
            Citizen.InvokeNative(0x9F52AD32D5AA413D, currentDogPed, false)
            Citizen.InvokeNative(0xC1B1E9A034A63A62, currentDogPed, 0)
            Citizen.InvokeNative(0xB8B6430EAD2D2437, currentDogPed, false)
        end

        SetDogAttributes(currentDogPed)
        setDogBehavior(currentDogPed)
        SetPedAsGroupMember(currentDogPed, GetPedGroupIndex(playerPed))

        -- Growth system
        if Config.RaiseAnimal then
            local halfGrowth = Config.DogFullGrownXp / 2
            if dogXP >= Config.DogFullGrownXp then
                SetPedScale(currentDogPed, 1.0)
                AddPrompt(StayPrompt, currentDogPed, 0x9959A6F0, L('prompt_dog_stay'))
                AddPrompt(HuntModePrompt, currentDogPed, 0xB2F377E8, L('prompt_dog_huntmode'))
            elseif dogXP >= halfGrowth then
                SetPedScale(currentDogPed, 0.8)
                AddPrompt(StayPrompt, currentDogPed, 0x9959A6F0, L('prompt_dog_stay'))
            else
                SetPedScale(currentDogPed, 0.6)
            end
        else
            dogXP = Config.DogFullGrownXp
            AddPrompt(StayPrompt, currentDogPed, 0x9959A6F0, L('prompt_dog_stay'))
            AddPrompt(HuntModePrompt, currentDogPed, 0xB2F377E8, L('prompt_dog_huntmode'))
        end

        -- the JRS interaction prompt: Dog Actions + Stop Animation (only while posed)
        DogAnimActive = false
        RegisterDogTarget()

        ActivePetType = 'dog'

        while (GetScriptTaskStatus(currentDogPed, 0x4924437d) ~= 8) do Wait(1000) end
        followOwner(currentDogPed, player, isshop)

    end
end

-- ═══════════════════════════════════════════════════════════
-- SPAWN DOG EVENT (from server)
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('jrs_huntingpets:client:spawnDog')
AddEventHandler('jrs_huntingpets:client:spawnDog', function(dogId, dog, skin, isInShop, xp)
    currentDogId = dogId
    if currentDogPed then return end
    if HasActivePet() and ActivePetType ~= 'dog' then
        Notify(L('error_one_pet_only'), '', 'ERROR')
        return
    end

    if recentlySpawned > 0 then return end
    recentlySpawned = Config.DogPetAttributes.SpawnLimiter

    isDogHungry = false
    FeedTimer = 0
    notifyHungry = false
    AddedFeedPrompts = false

    local player = PlayerPedId()
    local x, y, z, heading

    if not isInShop then
        x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(player, 0.0, -5.0, 0.3))
        local _, b = GetGroundZAndNormalFor_3dCoord(x, y, z + 10)
        z = b
    end

    if isInShop then
        for _, v in pairs(Config.Shops) do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - v.npccoords.xyz)
            if distance < Config.DistanceSpawn then
                local sx, sy, sz, sw = v.Spawndog.x, v.Spawndog.y, v.Spawndog.z, v.Spawndog.w
                spawnDog(dog, player, sx, sy, sz, sw, skin, PlayerPedId(), false, true, xp)
                return
            end
        end
    else
        local EntityIsDead = currentDogPed ~= nil and IsEntityDead(currentDogPed)
        spawnDog(dog, player, x, y, z, heading, skin, PlayerPedId(), EntityIsDead, false, xp)
    end
end)

-- ═══════════════════════════════════════════════════════════
-- PUT AWAY / SELL DOG
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('jrs_huntingpets:client:putawayDog')
AddEventHandler('jrs_huntingpets:client:putawayDog', function()
    if currentDogPed then
        DogAnimActive = false
        JRS.RemoveEntityTarget(currentDogPed)
        DeleteEntity(currentDogPed)
        currentDogPed = nil
        currentDogId = nil
        if ActivePetType == 'dog' then ActivePetType = nil end
    end
end)

RegisterNetEvent('jrs_huntingpets:client:sellDogConfirm')
AddEventHandler('jrs_huntingpets:client:sellDogConfirm', function()
    if currentDogPed then
        JRS.RemoveEntityTarget(currentDogPed)
        DeleteEntity(currentDogPed)
        currentDogPed = nil
        currentDogId = nil
        recentlySpawned = 0
        if ActivePetType == 'dog' then ActivePetType = nil end
    end
end)

-- ═══════════════════════════════════════════════════════════
-- COMMANDS
-- ═══════════════════════════════════════════════════════════
RegisterCommand("calldog", function()
    TriggerServerEvent('jrs_huntingpets:server:loadDog')
end)

RegisterCommand("fleedog", function()
    TriggerEvent('jrs_huntingpets:client:putawayDog')
end)

-- Hotkey
Citizen.CreateThread(function()
    while true do
        if Config.CallDogKey then
            if IsControlJustPressed(0, keys[Config.DogTriggerKeys.CallDog]) then
                TriggerServerEvent('jrs_huntingpets:server:loadDog')
            end
        end
        Citizen.Wait(1)
    end
end)

-- ═══════════════════════════════════════════════════════════
-- HUNT MODE & RETRIEVAL
-- ═══════════════════════════════════════════════════════════
function GetClosestAnimalPed(playerPed, radius)
    local playerCoords = GetEntityCoords(playerPed)
    local itemset = CreateItemset(true)
    local size = Citizen.InvokeNative(0x59B57C4B06531E1E, playerCoords, radius, itemset, 1, Citizen.ResultAsInteger())
    local closestPed
    local minDist = radius
    if size > 0 then
        for i = 0, size - 1 do
            local ped = GetIndexedItemInItemset(i, itemset)
            if playerPed ~= ped then
                local pedType = GetPedType(ped)
                local model = GetEntityModel(ped)
                if pedType == 28 and IsEntityDead(ped) and not RetrievedEntities[ped] and Config.DogRetrievableAnimals[model] then
                    local pedCoords = GetEntityCoords(ped)
                    local distance = #(playerCoords - pedCoords)
                    if distance < minDist then
                        closestPed = ped
                        minDist = distance
                    end
                end
            end
        end
    end
    if IsItemsetValid(itemset) then DestroyItemset(itemset) end
    return closestPed
end

function RetrieveKill(ClosestPed)
    fetchedObj = ClosestPed
    local ped = PlayerPedId()
    local coords = GetEntityCoords(fetchedObj)
    TaskGoToCoordAnyMeans(currentDogPed, coords, 2.0, 0, 0, 786603, 0xbf800000)
    Retrieving = true
    while true do
        Citizen.Wait(2000)
        TaskGoToCoordAnyMeans(currentDogPed, coords, 2.0, 0, 0, 786603, 0xbf800000)
        local petCoords = GetEntityCoords(currentDogPed)
        coords = GetEntityCoords(fetchedObj)
        if GetDistanceBetweenCoords(coords, petCoords, true) <= 2.5 then
            AttachEntityToEntity(fetchedObj, currentDogPed, GetPedBoneIndex(currentDogPed, 21030), 0.14, 0.14, 0.09798, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
            RetrievedEntities[fetchedObj] = true
            ReturnKillToPlayer(fetchedObj, ped)
            break
        end
    end
end

function ReturnKillToPlayer(fetchedKill, playerPed)
    local coords = GetEntityCoords(playerPed)
    TaskGoToCoordAnyMeans(currentDogPed, coords, 1.5, 0, 0, 786603, 0xbf800000)
    while true do
        Citizen.Wait(2000)
        coords = GetEntityCoords(playerPed)
        local coords2 = GetEntityCoords(currentDogPed)
        TaskGoToCoordAnyMeans(currentDogPed, coords, 1.5, 0, 0, 786603, 0xbf800000)
        if GetDistanceBetweenCoords(coords, coords2, true) <= 2.0 then
            DetachEntity(fetchedObj)
            Wait(100)
            PlaceObjectOnGroundProperly(fetchedObj, true)
            Retrieving = false
            followOwner(currentDogPed, playerPed, false)
            break
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- MAIN DOG LOOP (hunt mode, feeding, death, combat)
-- ═══════════════════════════════════════════════════════════
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        -- Hunt mode retrieval
        if currentDogPed and not Retrieving and not isDogHungry and HuntMode then
            local canHunt = not Config.RaiseAnimal or dogXP >= Config.DogFullGrownXp
            if canHunt then
                local ped = PlayerPedId()
                local ClosestPed = GetClosestAnimalPed(ped, Config.DogSearchRadius)
                if ClosestPed then
                    local pedType = GetPedType(ClosestPed)
                    if pedType == 28 and IsEntityDead(ClosestPed) and not RetrievedEntities[ClosestPed] then
                        local whoKilledPed = GetPedSourceOfDeath(ClosestPed)
                        if ped == whoKilledPed then
                            local model = GetEntityModel(ClosestPed)
                            if Config.DogRetrievableAnimals[model] then
                                RetrieveKill(ClosestPed)
                            end
                        else
                            RetrievedEntities[ClosestPed] = true
                        end
                    end
                end
            end
        end

        -- Defensive mode
        if currentDogPed and Config.DefensiveMode and recentlyCombat <= 0 then
            local ped = PlayerPedId()
            local enemyPed = GetClosestFightingPed(ped, 50.0)
            if enemyPed then
                ClearPedTasks(currentDogPed)
                TaskCombatPed(currentDogPed, enemyPed, 0, 16)
                recentlyCombat = 15
            end
        end

        -- Feed timer
        if currentDogPed then
            FeedTimer = FeedTimer + 1
            if Config.DogFeedInterval <= FeedTimer then
                isDogHungry = true
                if not AddedFeedPrompts then
                    AddPrompt(FeedPrompt, currentDogPed, 0xCEFD9220, L('prompt_dog_feed'))
                    AddedFeedPrompts = true
                end
                if not notifyHungry and Config.NotifyWhenHungry then
                    Notify(L('info_hungry'), '', 'TIP')
                    notifyHungry = true
                end
            end

            -- Death check
            if IsEntityDead(currentDogPed) then
                recentlySpawned = Config.DogPetAttributes.DeathCooldown
                Notify(L('error_petdead'), '', 'ERROR')
                Wait(3000)
                JRS.RemoveEntityTarget(currentDogPed)
                DeleteEntity(currentDogPed)
                currentDogPed = nil
                currentDogId = nil
                if ActivePetType == 'dog' then ActivePetType = nil end
            end
        end

        if recentlySpawned > 0 then recentlySpawned = recentlySpawned - 1 end
        if recentlyCombat > 0 then recentlyCombat = recentlyCombat - 1 end
    end
end)

function GetClosestFightingPed(playerPed, radius)
    local playerCoords = GetEntityCoords(playerPed)
    local itemset = CreateItemset(true)
    local size = Citizen.InvokeNative(0x59B57C4B06531E1E, playerCoords, radius, itemset, 1, Citizen.ResultAsInteger())
    local closestPed
    local minDist = radius
    if size > 0 then
        for i = 0, size - 1 do
            local ped = GetIndexedItemInItemset(i, itemset)
            if playerPed ~= ped and ped ~= currentDogPed then
                if IsPedInCombat(playerPed, ped) then
                    local pedCoords = GetEntityCoords(ped)
                    closestPed = ped
                    minDist = #(playerCoords - pedCoords)
                end
            end
        end
    end
    if IsItemsetValid(itemset) then DestroyItemset(itemset) end
    return closestPed
end

-- ═══════════════════════════════════════════════════════════
-- PROMPT HANDLING LOOP
-- ═══════════════════════════════════════════════════════════
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local id = PlayerId()
        if IsPlayerTargettingAnything(id) then
            local result, entity = GetPlayerTargetEntity(id)

            -- Feed
            if FeedPrompt[entity] and PromptHasStandardModeCompleted(FeedPrompt[entity]) then
                if entity == currentDogPed and Config.DogFeedInterval <= FeedTimer then
                    local ped = PlayerPedId()
                    TaskTurnPedToFaceEntity(ped, currentDogPed, 5000)
                    TaskTurnPedToFaceEntity(currentDogPed, ped, 5000)
                    TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_CROUCH_INSPECT'), 60000, true, false, false, false)
                    Wait(2000)
                    DogEatAnimation()
                    Wait(4000)
                    ClearPedTasks(ped)
                    Wait(4000)
                    ClearPedTasks(currentDogPed)
                    followOwner(currentDogPed, ped, false)
                    TriggerServerEvent('jrs_huntingpets:server:feedDog', currentDogId)
                end
                Wait(2000)
            end

            -- Follow
            if FollowPrompt[entity] and PromptHasStandardModeCompleted(FollowPrompt[entity]) then
                if isTracking then
                    isTracking = false
                    ClearPedTasks(currentDogPed)
                end
                followOwner(currentDogPed, PlayerPedId(), false)
                Wait(2000)
            end

            -- Stay
            if StayPrompt[entity] and PromptHasStandardModeCompleted(StayPrompt[entity]) then
                petStay(currentDogPed)
                Wait(2000)
            end

            -- Attack
            if AttackPrompt[entity] and PromptHasStandardModeCompleted(AttackPrompt[entity]) then
                local retval, group = AddRelationshipGroup("attackedPeds")
                SetPedRelationshipGroupHash(entity, group)
                SetRelationshipBetweenGroups(5, GetPedRelationshipGroupHash(currentDogPed), GetPedRelationshipGroupHash(entity))
                TaskCombatPed(currentDogPed, entity, 0, 16)
            end

            -- Track
            if TrackPrompt[entity] and PromptHasStandardModeCompleted(TrackPrompt[entity]) then
                TaskFollowToOffsetOfEntity(currentDogPed, entity, 0.0, -1.5, 0.0, 1.0, -1, 2 * 100000000, 1, 1, 0, 0, 1)
            end

            -- Hunt Mode
            if HuntModePrompt[entity] and PromptHasStandardModeCompleted(HuntModePrompt[entity]) then
                HuntMode = not HuntMode
                if HuntMode then
                    Notify(L('info_dog_huntmode_on'), '', 'SUCCESS')
                else
                    Notify(L('info_dog_huntmode_off'), '', 'TIP')
                end
            end

            -- Add attack/track prompts for targets
            if Config.AttackCommand and currentDogPed then
                if not AddedAttackPrompt[entity] and entity ~= currentDogPed then
                    local shouldAdd = false
                    if Config.AttackOnlyAnimals and GetPedType(entity) == 28 then shouldAdd = true
                    elseif Config.AttackOnlyNPC and not IsPedAPlayer(entity) then shouldAdd = true
                    elseif Config.AttackOnlyPlayers and IsPedAPlayer(entity) then shouldAdd = true
                    elseif not Config.AttackOnlyAnimals and not Config.AttackOnlyNPC and not Config.AttackOnlyPlayers then shouldAdd = true end
                    if shouldAdd then
                        AddPrompt(AttackPrompt, entity, 0x63A38F2C, L('prompt_dog_attack'))
                        AddedAttackPrompt[entity] = true
                    end
                end
            end

            if Config.TrackCommand and currentDogPed then
                if not AddedTrackPrompt[entity] and entity ~= currentDogPed then
                    local shouldAdd = false
                    if Config.TrackOnlyAnimals and GetPedType(entity) == 28 then shouldAdd = true
                    elseif Config.TrackOnlyNPC and not IsPedAPlayer(entity) then shouldAdd = true
                    elseif Config.TrackOnlyPlayers and IsPedAPlayer(entity) then shouldAdd = true
                    elseif not Config.TrackOnlyAnimals and not Config.TrackOnlyNPC and not Config.TrackOnlyPlayers then shouldAdd = true end
                    if shouldAdd then
                        AddPrompt(TrackPrompt, entity, 0x9959A6F0, L('prompt_dog_track'))
                        AddedTrackPrompt[entity] = true
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
-- DOG FED EVENT (from server)
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('jrs_huntingpets:client:dogFed')
AddEventHandler('jrs_huntingpets:client:dogFed', function(newXP)
    if Config.RaiseAnimal then
        dogXP = newXP
        local halfGrowth = Config.DogFullGrownXp / 2
        if dogXP >= Config.DogFullGrownXp then
            SetPedScale(currentDogPed, 1.0)
            AddPrompt(StayPrompt, currentDogPed, 0x9959A6F0, L('prompt_dog_stay'))
            AddPrompt(HuntModePrompt, currentDogPed, 0xB2F377E8, L('prompt_dog_huntmode'))
        elseif dogXP >= halfGrowth then
            SetPedScale(currentDogPed, 0.8)
            AddPrompt(StayPrompt, currentDogPed, 0x9959A6F0, L('prompt_dog_stay'))
        else
            SetPedScale(currentDogPed, 0.6)
        end
    end
    isDogHungry = false
    FeedTimer = 0
    notifyHungry = false
end)

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        TriggerEvent('jrs_huntingpets:client:putawayDog')
    end
end)
