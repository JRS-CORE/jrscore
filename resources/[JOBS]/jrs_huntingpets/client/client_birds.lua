-- jrs_huntingpets | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_huntingpets | client: the hunting bird
-- The bird sits on the shoulder or circles above the player. From the shoulder it can be sent hunting
-- (it flies off, comes back with prey or a scavenged item and the server pays xp), sent home, watched through
-- its own camera, made to talk (parrots) or put up for sale to another player.

local nativeFlyCircle = 0x72997893BFB8ECCC
local nativeFlyTo = 0xD6CFC2D59DA72042
local nativeFlyAway = 0xE86A537B5A3C297C

local function flyCircle(ped, speed, at, a, b) return Citizen.InvokeNative(nativeFlyCircle, ped, speed, at, a, b) end
local function flyTo(ped, speed, x, y, z, p1, p2) return Citizen.InvokeNative(nativeFlyTo, ped, speed, x, y, z, p1, p2) end
local function flyAway(ped, from) return Citizen.InvokeNative(nativeFlyAway, ped, from) end
local function isFrozen(ped) return Citizen.InvokeNative(0x083D497D57B7400F, ped) end
local function onLadder(ped) return Citizen.InvokeNative(0x59643424B68D52B5, ped) end
local function hogtying(ped) return Citizen.InvokeNative(0x42429C674B61238B, ped) end
local function hogtied(ped) return Citizen.InvokeNative(0x3AA24CCC0D451379, ped) end
local function isHorse(model) return Citizen.InvokeNative(0x772A1969F649E902, model) end

-- ------------------------------------------------------------------ state

CalledBird = nil                      -- the bird ped (global: the shop script sends it home when it is sold)
local bird = { data = {}, name = nil }                 -- row data of the bird that is out
local mode = {
    shoulder = false, following = false, coming = false, leaving = false, hunting = false,
    menu = false, nearCorpse = false, selling = false, talking = false,
}
local prey, preyXp, scavenged                          -- what the bird is bringing back
local cam
local here, dead                                       -- player position and state, refreshed twice a second
local corpses = {}                                     -- entities near the player while a bird is out
local listings = {}                                    -- bird listings of other players (and ours)

local sphere = Citizen.InvokeNative(0xB3FB80A32BAE3065, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0)
local itemSet = CreateItemset(1)

-- ------------------------------------------------------------------ prompts

local groups = { shoulder = GetRandomIntInRange(0, 0xffffff), follow = GetRandomIntInRange(0, 0xffffff),
                 sell = GetRandomIntInRange(0, 0xffffff), buy = GetRandomIntInRange(0, 0xffffff) }
local prompt = {}

local function makePrompt(name, group, spec)
    local p = PromptRegisterBegin()
    PromptSetControlAction(p, spec[1])
    PromptSetText(p, CreateVarString(10, 'LITERAL_STRING', spec[2]))
    PromptSetEnabled(p, 1)
    PromptSetVisible(p, 1)
    PromptSetStandardMode(p, 1)
    PromptSetGroup(p, group)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, p, true)
    PromptRegisterEnd(p)
    prompt[name] = p
end

local function makePrompts()
    local P = Config.Prompts
    makePrompt('stopSell', groups.sell, P.StopSell)
    makePrompt('buy', groups.buy, P.BuyBird)
    makePrompt('talk', groups.shoulder, P.Talk)
    makePrompt('home', groups.shoulder, P.Home)
    makePrompt('follow', groups.shoulder, P.Follow)
    makePrompt('hunt', groups.shoulder, P.Hunt)
    makePrompt('flyBack', groups.follow, P.FlyBack)
    makePrompt('camera', groups.follow, P.Camera)
    makePrompt('sell', groups.shoulder, P.Sell)
end

local function pressed(name) return Citizen.InvokeNative(0xC92AC953F0A982AE, prompt[name]) end

-- ------------------------------------------------------------------ where the player is and which birds fit

-- the area at the player's position from one of the three area lists (zone type 12, 11 or 10)
local function areaIn(list, zoneType)
    local hash = Citizen.InvokeNative(0x43AD8FC02B429D33, here.x, here.y, here.z, zoneType)
    for _, v in pairs(list) do
        if hash == v[3] then return { name = v[6], hash = v[3], list = v[5], activity = v[4] } end
    end
end

function PlayerArea()
    return areaIn(Config.Areas, 12) or areaIn(Config.Districts, 11) or areaIn(Config.Districts2, 10) or { name = 'None', activity = false, list = {} }
end

local function modelIn(entity, list)
    local model = GetEntityModel(entity)
    for _, m in pairs(list) do
        if m == model then return true end
    end
    return false
end

function IsBirdOfPrey(entity) return modelIn(entity, Config.BirdOfPreys) end
function IsBirdScavenger(entity) return modelIn(entity, Config.Scavengers) end
function IsBirdFisher(entity) return modelIn(entity, Config.FishingBirds) end

-- ------------------------------------------------------------------ the bird's own movement

local function stopCam()
    if not cam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam)
    cam = nil
end

local function toggleCam()
    if cam then return stopCam() end
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', GetEntityCoords(PlayerPedId()), -90.0, 0.0, 0.0, GetGameplayCamFov())
    ShakeCam(cam, 'DRUNK_SHAKE', 0.1)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 1000, true, false)
    AttachCamToEntity(cam, CalledBird, 0.0, 0.0, 0.0, true)
end

local function letGo()
    if IsEntityAttached(CalledBird) then
        DetachEntity(CalledBird, 1, 1)
        mode.shoulder = false
    end
    if isFrozen(CalledBird) then FreezeEntityPosition(CalledBird, false) end
end

local function removeBird()
    DeleteEntity(CalledBird)
    SetEntityAsNoLongerNeeded(CalledBird)
    CalledBird = nil
end

-- up in the air, circling around the player
function FollowPlayer()
    if isFrozen(CalledBird) then FreezeEntityPosition(CalledBird, false) end
    SetEntityCollision(CalledBird, false, false)
    if IsEntityAttached(CalledBird) then
        DetachEntity(CalledBird, 1, 1)
        mode.shoulder = false
    end
    flyAway(CalledBird, PlayerPedId())
    Wait(2000)
    mode.following = true
    flyCircle(CalledBird, 4.0, GetEntityCoords(CalledBird), 3.1, 4.1)
end

function SendBirdHome(slow)
    Notify(Config.Texts.Bird, Config.Texts.GoingHome, 'TIP')
    mode.leaving = true
    if prey then
        DetachEntity(prey, 1, 1)
        prey = nil
    end
    letGo()
    if IsPedStill(PlayerPedId()) == 1 then ClearPedTasksImmediately(PlayerPedId()) end
    scavenged = nil

    SetEntityCollision(CalledBird, false, false)
    flyAway(CalledBird, PlayerPedId())
    Wait(slow == 0 and 7000 or 500)
    stopCam()
    removeBird()

    bird.data = {}
    mode.following, mode.coming, mode.shoulder, mode.leaving, mode.hunting = false, false, false, false, false
    if ActivePetType == 'bird' then ActivePetType = nil end
end

-- lands on the shoulder; brings what it caught and asks the server to pay for it
local function land()
    local me = PlayerPedId()
    if prey then
        FreezeEntityPosition(prey, false)
        DetachEntity(prey, 1, 1)
        prey = nil
        TriggerServerEvent('jrs_huntingpets:addxp', preyXp, bird.data.id)
        bird.data.xp = bird.data.xp + preyXp
        preyXp = nil
    end
    if scavenged then
        TriggerServerEvent('jrs_huntingpets:addxp', scavenged.xp, bird.data.id)
        TriggerServerEvent('jrs_huntingpets:addscavengeditem', scavenged.name, scavenged.amount)
        bird.data.xp = bird.data.xp + scavenged.xp
        scavenged = nil
    end
    stopCam()

    local spot = Config.BirdAttach[GetEntityModel(CalledBird)]
    local a = IsPedMale(me) and spot.Male or spot.Female
    AttachEntityToEntity(CalledBird, me, a[1], a[2], a[3], a[4], a[5], a[6], a[7], false, false, true, false, 0, true, false, false)
    ClearPedTasksImmediately(CalledBird)
    SetBlockingOfNonTemporaryEvents(CalledBird, true)
    FreezeEntityPosition(CalledBird, true)
    ClearPedTasksImmediately(me)
    mode.coming, mode.shoulder, mode.hunting = false, true, false
end

local function flyToPlayer()
    mode.coming, mode.following = true, false
    local spot = GetEntityCoords(PlayerPedId())
    TaskStandStill(PlayerPedId(), -1)
    Notify(Config.Texts.Bird, Config.Texts.WaitBird, 'TIP')
    ClearPedTasks(CalledBird)
    Wait(100)
    flyTo(CalledBird, 1.0, spot.x, spot.y, spot.z + 0.5, 1, 0)

    CreateThread(function()
        while true do
            Wait(500)
            if #(spot - GetEntityCoords(CalledBird)) < 5.0 then
                local now = GetEntityCoords(PlayerPedId())
                local away = #(GetEntityCoords(CalledBird) - now)
                if away > 1.2 then
                    ClearPedTasks(CalledBird)
                    flyTo(CalledBird, 1.0, now.x, now.y, now.z + 0.5, 1, 0)
                end
                while away > 1.5 do
                    away = #(GetEntityCoords(CalledBird) - now)
                    Wait(100)
                end
                return land()
            end
        end
    end)
end

-- ------------------------------------------------------------------ making the bird and its catch

-- a ped that is not alive in any real sense: it is only a model to carry or to fly
local function puppet(model, at, preset, networked)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(1) end
    local ped = CreatePed(model, at.x, at.y, at.z, GetEntityHeading(PlayerPedId()) + 180, 1, networked)
    while not IsEntityAPed(ped) do Wait(1) end

    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    Citizen.InvokeNative(0x77FF8D35EEC6BBC4, ped, preset)
    while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) do Wait(0) end
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, 1)
    Wait(500)
    SetModelAsNoLongerNeeded(model)
    return ped
end

local function ahead(distance, lift)
    local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, distance, 0.1))
    return { x = x, y = y, z = z + lift }
end

local function makeBird(model, preset, name, xp, id)
    bird.data = { model = model, preset = preset, name = name, xp = xp, id = id }
    bird.name = name
    if CalledBird then removeBird() end

    CalledBird = puppet(model, ahead(20.0, 20.0), preset, 1)
    SetBlockingOfNonTemporaryEvents(CalledBird, true)
    SetEntityInvincible(CalledBird, true)
    SetEntityCollision(CalledBird, false, false)
    FreezeEntityPosition(CalledBird, true)
    FollowPlayer()
end

-- something for the bird to carry back: a ped hanging from its feet
local function carry(model, preset, xp)
    prey = puppet(model, ahead(70.0, 40.0), preset, 0)
    preyXp = xp
    FreezeEntityPosition(prey, true)
    Citizen.InvokeNative(0x1CE875505D45338A, prey, 0, 0)
    AttachEntityToEntity(prey, CalledBird, 7, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 0, true, false, false)
    FreezeEntityPosition(prey, false)
end

-- the entries of `list` the bird is experienced enough for, one at random (nil with a notice when none)
local function pickFrom(list)
    local fit = {}
    for _, entry in pairs(list) do
        if bird.data.xp >= entry.xpreq then fit[#fit + 1] = entry end
    end
    if #fit == 0 then
        Notify(Config.Texts.Bird, Config.Texts.NoHunt, 'TIP')
        return nil
    end
    return fit[math.random(1, #fit)]
end

-- the bird that comes back from a hunt
local function makeBirdFromHunt(model, preset, name, catch)
    bird.name = name
    if CalledBird then removeBird() end

    CalledBird = puppet(model, ahead(70.0, 40.0), preset, 0)
    SetBlockingOfNonTemporaryEvents(CalledBird, true)
    SetEntityInvincible(CalledBird, true)
    SetEntityCollision(CalledBird, false, false)

    if IsBirdOfPrey(CalledBird) then
        carry(catch.model, catch.preset, catch.xp)
    elseif IsBirdScavenger(CalledBird) then
        scavenged = pickFrom(Config.ScavengerItems)
    elseif IsBirdFisher(CalledBird) then
        local fish = pickFrom(Config.FishItems)
        if fish then carry(fish.model, 0, fish.xp) end
    end
    flyToPlayer()
end

-- ------------------------------------------------------------------ sending it hunting

RegisterNetEvent('jrs_huntingpets:starthunt', function()
    local area = PlayerArea()
    if area.activity ~= true then return Notify(Config.Texts.Bird, Config.Texts.NoHunt, 'TIP') end

    local catch = pickFrom(area.list)
    if not catch then return end

    Notify(Config.Texts.Bird, Config.Texts.GoingHunt .. ' ' .. area.name, 'TIP')
    mode.hunting = true
    letGo()
    SetEntityCollision(CalledBird, false, false)
    flyAway(CalledBird, PlayerPedId())
    stopCam()

    -- waits `seconds`; false when the player died meanwhile
    local function wait(seconds)
        for _ = 1, seconds do
            Wait(1000)
            if IsEntityDead(PlayerPedId()) then
                mode.hunting = false
                return false
            end
        end
        return true
    end

    wait(Config.BirdGoForHuntTimer)
    removeBird()
    mode.following, mode.coming, mode.leaving = false, false, false

    if mode.hunting and wait(Config.HuntingTimer) then
        makeBirdFromHunt(bird.data.model, bird.data.preset, bird.data.name, catch)
    end
end)

-- ------------------------------------------------------------------ selling to another player

local function sell()
    AddTextEntry('FMMC_KEY_TIP8', 'Add Price')
    DisplayOnscreenKeyboard(3, 'FMMC_KEY_TIP8', '', '', '', '', '', 5)
    while UpdateOnscreenKeyboard() == 0 do Wait(1) end

    local typed = GetOnscreenKeyboardResult()
    if not typed then return end
    local price = tonumber(typed)
    if not price or price < 1 then price = 0 end

    mode.selling = true
    SetEntityInvincible(PlayerPedId(), true)
    TaskStandStill(PlayerPedId(), -1)
    TriggerServerEvent('jrs_huntingpets:sell:create', bird.data.id, price, GetEntityCoords(PlayerPedId()), GetPlayerServerId(PlayerId()), PedToNet(CalledBird))
end

function StartSellBird() sell() end

function StopSellBird()
    mode.selling = false
    SetEntityInvincible(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
    TriggerServerEvent('jrs_huntingpets:sell:stop', bird.data.id)
end

RegisterNetEvent('jrs_huntingpets:start_sell', function()
    if not mode.selling then sell() end
end)

RegisterNetEvent('jrs_huntingpets:sell:gotpoints_c', function(all) listings = all end)

RegisterNetEvent('jrs_huntingpets:sell:updatepoints', function(listing, id, pedNetId)
    listings[tonumber(id)] = listing
    if pedNetId ~= nil then
        local ped = NetToPed(pedNetId)
        DeleteEntity(ped)
        SetEntityAsNoLongerNeeded(ped)
    end
end)

RegisterNetEvent('jrs_huntingpets:sell:updatepoints1', function(id) listings[tonumber(id)] = nil end)

-- our bird was bought
RegisterNetEvent('jrs_huntingpets:sell:finishsell', function()
    if mode.selling then
        mode.selling = false
        removeBird()
    end
    CalledBird, bird.data = nil, {}
    mode.selling, mode.shoulder, mode.following, mode.coming, mode.leaving, mode.hunting = false, false, false, false, false, false
    ClearPedTasks(PlayerPedId())
    SetEntityInvincible(PlayerPedId(), false)
end)

-- ------------------------------------------------------------------ talking (parrots)

RegisterNetEvent('jrs_huntingpets:checktalk', function()
    if bird.data.xp < Config.ParrotTalkingXPReq then return Notify(Config.Texts.Bird, Config.Texts.NoTalkSkill, 'TIP') end

    local model = GetEntityModel(CalledBird)
    if model ~= `a_c_carolinaparakeet_01` and model ~= `a_c_parrot_01` then
        return Notify(Config.Texts.Bird, Config.Texts.NotParrot, 'TIP')
    end
    if mode.talking then return Notify(Config.Texts.Bird, Config.Texts.WaitTalk, 'TIP') end

    mode.talking = true
    Citizen.InvokeNative(0xB8BEC0CA6F0EDB0F, 8, 400)
    Citizen.InvokeNative(0x79D2F0E66F81D90D, 8, 200)
    Wait(1000)
    mode.talking = false
end)

-- ------------------------------------------------------------------ calling and dismissing

RegisterNetEvent('jrs_huntingpets:client:spawnBird', function(id, model, preset, xp)
    if CalledBird then return Notify(L('notif_title_birds'), L('notif_send_bird_home_first'), 'ERROR') end
    if HasActivePet() and ActivePetType ~= 'bird' then return Notify(L('notif_title_pets_short'), L('notif_send_pet_home_first2'), 'ERROR') end
    ActivePetType = 'bird'
    makeBird(model, preset, 'Bird', xp, id)
end)

RegisterCommand('callbird', function() TriggerServerEvent('jrs_huntingpets:server:loadBird') end)

RegisterCommand('fleebird', function()
    if CalledBird then SendBirdHome(0) end
    if ActivePetType == 'bird' then ActivePetType = nil end
end)

-- ------------------------------------------------------------------ threads

-- player position, and corpses next to the player while a bird is out
CreateThread(function()
    TriggerServerEvent('jrs_huntingpets:sell:getpoints')
    makePrompts()
    while true do
        Wait(500)
        local me = PlayerPedId()
        here, dead = GetEntityCoords(me), IsEntityDead(me)

        if dead and CalledBird and not mode.leaving then SendBirdHome(1) end

        if CalledBird then
            corpses = {}
            if sphere then
                Citizen.InvokeNative(0x541B8576615C33DE, sphere, here.x, here.y, here.z)
                local count = Citizen.InvokeNative(0x886171A12F400B89, sphere, itemSet, 1)
                for i = 0, (count or 0) - 1 do corpses[GetIndexedItemInItemset(i, itemSet)] = true end
                Citizen.InvokeNative(0x20A4BF0E09BEE146, itemSet)
            end
        end
    end
end)

-- the prompts are hidden while the player stands over a corpse (so they can skin it)
CreateThread(function()
    while true do
        Wait(100)
        if CalledBird and GetMount(PlayerPedId()) == 0 then
            for entity in pairs(corpses) do
                if DoesEntityExist(entity) and not isHorse(GetEntityModel(entity)) and IsEntityDead(entity) then
                    while #(here - GetEntityCoords(entity)) < 1.5 do
                        Wait(200)
                        mode.nearCorpse = true
                    end
                    mode.nearCorpse = false
                end
            end
        end
    end
end)

-- when the player cannot hold a bird (climbing, falling, swimming ...) it takes off
CreateThread(function()
    while true do
        Wait(500)
        if mode.shoulder then
            local me = PlayerPedId()
            if IsPedClimbing(me) or onLadder(me) or IsPedFalling(me) or hogtied(me) or hogtying(me) or IsPedRagdoll(me) or IsPedSwimming(me) then
                FollowPlayer()
            end
        end
    end
end)

local function free() return not mode.menu and not mode.leaving and not mode.nearCorpse and not mode.hunting end

CreateThread(function()
    while true do
        Wait(mode.shoulder and 1 or 500)

        if mode.shoulder and free() and not mode.selling then
            PromptSetActiveGroupThisFrame(groups.shoulder, CreateVarString(10, 'LITERAL_STRING', bird.name))
            if pressed('home') then SendBirdHome(0) end
            if pressed('follow') then FollowPlayer() end
            if pressed('hunt') then TriggerServerEvent('jrs_huntingpets:checkhunt') end
            if pressed('talk') then TriggerEvent('jrs_huntingpets:checktalk') end
            if pressed('sell') and not mode.selling then TriggerServerEvent('jrs_huntingpets:check_sell') end
        end

        if mode.following and free() then
            PromptSetActiveGroupThisFrame(groups.follow, CreateVarString(10, 'LITERAL_STRING', bird.name))
            if pressed('flyBack') then flyToPlayer() end
            if pressed('camera') then toggleCam() end
        end
    end
end)

-- the circling bird keeps circling over the player
CreateThread(function()
    while true do
        Wait(2000)
        if CalledBird and not isFrozen(CalledBird) and not mode.shoulder and not mode.coming and mode.following and not mode.leaving then
            local me, b = GetEntityCoords(PlayerPedId()), GetEntityCoords(CalledBird)
            flyCircle(CalledBird, 4.0, vector3(me.x, me.y, b.z), 3.1, 4.1)
        end
    end
end)

-- sell points: a marker, and a buy prompt for sales of other players
local MARKER <const> = 0x6903B113
local function drawMarker(at)
    local c = Config.Checkpoints.shop
    Citizen.InvokeNative(0x2A32FAA57B937173, MARKER, at.x, at.y, at.z - 0.9, 0, 0, 0, 0, 0, 0, 2.0, 2.0, 0.3, c[1], c[2], c[3], 100, 0, 0, 2, 0, 0, 0, 0)
end

CreateThread(function()
    while true do
        local any = type(listings) == 'table' and next(listings) ~= nil
        Wait(any and 1 or 1000)
        if any and here then
            local mine = GetPlayerServerId(PlayerId())
            for _, l in pairs(listings) do
                local away = #(here - l.sellcoords)
                if tonumber(l.owner) ~= mine then
                    if away < 10.0 then drawMarker(l.sellcoords) end
                    if away < 2.0 then
                        PromptSetActiveGroupThisFrame(groups.buy, CreateVarString(10, 'LITERAL_STRING', '$' .. l.sellprice))
                        if pressed('buy') then TriggerServerEvent('jrs_huntingpets:sell:buyoffer', l.owner, l.sellprice, l.id) end
                    end
                elseif away < 2.0 then
                    drawMarker(l.sellcoords)
                end
            end
        end
    end
end)

-- while our own bird is for sale the player stands still and can stop the sale
CreateThread(function()
    while true do
        Wait(mode.selling and 1 or 500)
        if mode.selling then
            DisableControlAction(0, 0xF8982F00, true)
            while not listings[bird.data.id] do Wait(1) end
            PromptSetActiveGroupThisFrame(groups.sell, CreateVarString(10, 'LITERAL_STRING', 'Sell$' .. listings[bird.data.id].sellprice))
            if pressed('stopSell') then StopSellBird() end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if CalledBird then removeBird() end
    stopCam()
end)
