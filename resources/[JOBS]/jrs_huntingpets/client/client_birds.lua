-- jrs_huntingpets: Bird Client (rewritten)
----------------------------NATIVES----------------------------
function TaskFlyingCircle(ped, f1, v3,f2,f3)
    return Citizen.InvokeNative(0x72997893BFB8ECCC,ped, f1, v3,f2,f3)
end
--------------------------------------------------------
function TaskFlyToCoord(ped, f1, x, y, z, p1, p2)
    return Citizen.InvokeNative(0xD6CFC2D59DA72042, ped, f1, x, y, z, p1, p2)
end
--------------------------------------------------------
function IsEntityFrozen(ped)
    return Citizen.InvokeNative(0x083D497D57B7400F, ped)
end
--------------------------------------------------------
function SetBlockingOfNonTemporaryEvents(ped, toggle)
    return Citizen.InvokeNative(0x9F8AA94D6D97DBF4, ped, toggle)
end
--------------------------------------------------------
function TaskFlyAway(ped, ped2)
    return Citizen.InvokeNative(0xE86A537B5A3C297C, ped, ped2)
end
--------------------------------------------------------
function IsPedClimbingLadder(ped)
    return Citizen.InvokeNative(0x59643424B68D52B5,ped)
end
--------------------------------------------------------
function IsPedHogtying(ped)
    return Citizen.InvokeNative(0x42429C674B61238B,ped)
end
--------------------------------------------------------
function IsPedHogtied(ped)
    return Citizen.InvokeNative(0x3AA24CCC0D451379,ped)
end
--------------------------------------------------------
function IsThisModelAHorse(model)
    return Citizen.InvokeNative(0x772A1969F649E902, model)
end
--------------------------------------------------------
function StopCurrentPlayingAmbientSpeech()
    return Citizen.InvokeNative(0xB8BEC0CA6F0EDB0F, 8, 400)
end
--------------------------------------------------------
function StopCurrentPlayingSpeech()
    return Citizen.InvokeNative(0x79D2F0E66F81D90D, 8, 200) 
end
----------------------------VARIABLES----------------------------
local playerCoords = nil
local playerDead = nil
local menuOpen = false

local CalledBird = nil
local attachConfig = nil
local BirdName = nil

local birdOnShoulder = false
local birdIsFollowing = false
local birdIsFlytoPed = false
local birdisFlyingHome = false
local birdisHunting = false

local preyID = nil
local preyXP

local tempBird = nil

local Camera = nil
local MENUTEXTS = Config.Texts.Menu
local TEXTURES = Config.Textures

local CalledBirdData = {}

local selectedScavItem = nil

local AreaC = Citizen.InvokeNative(0xB3FB80A32BAE3065, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0)
local itemS = CreateItemset(1)
local nearby = false
local deathEntities = {}

local selling = false
local SellPointsC = {}

local talking = false
----------------------------PROMPTS----------------------------
local OnShoulderPrompts = GetRandomIntInRange(0, 0xffffff)
local SendHomePrompt
local FollowPrompt
local BirdSellPrompt
local HuntPrompt
local TalkPrompt
--------------------------------------------------------
local OnFollowPrompts = GetRandomIntInRange(0, 0xffffff)
local FlyBackPrompt
local CameraPrompt 
--------------------------------------------------------
local StopSellPrompt
local SellPrompts = GetRandomIntInRange(0, 0xffffff)
--------------------------------------------------------
local BuyBirdPrompt
local BuyBirdPrompts = GetRandomIntInRange(0, 0xffffff)
--------------------------------------------------------
function SetupBirdPrompts()

    local strt = Config.Prompts.Talk[2]
    TalkPrompt = PromptRegisterBegin()
    PromptSetControlAction(TalkPrompt, Config.Prompts.Talk[1])
    strt = CreateVarString(10, 'LITERAL_STRING', strt)
    PromptSetText(TalkPrompt, strt)
    PromptSetEnabled(TalkPrompt, 1)
    PromptSetVisible(TalkPrompt, 1)
	PromptSetStandardMode(TalkPrompt,1)
	PromptSetGroup(TalkPrompt, OnShoulderPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,TalkPrompt,true)
	PromptRegisterEnd(TalkPrompt)

    local str = Config.Prompts.Home[2]
    SendHomePrompt = PromptRegisterBegin()
    PromptSetControlAction(SendHomePrompt, Config.Prompts.Home[1])
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(SendHomePrompt, str)
    PromptSetEnabled(SendHomePrompt, 1)
    PromptSetVisible(SendHomePrompt, 1)
	PromptSetStandardMode(SendHomePrompt,1)
	PromptSetGroup(SendHomePrompt, OnShoulderPrompts)
	PromptRegisterEnd(SendHomePrompt)

    Citizen.Wait(1)

    local str2 = Config.Prompts.Follow[2]
    FollowPrompt = PromptRegisterBegin()
    PromptSetControlAction(FollowPrompt, Config.Prompts.Follow[1])
    str2 = CreateVarString(10, 'LITERAL_STRING', str2)
    PromptSetText(FollowPrompt, str2)
    PromptSetEnabled(FollowPrompt, 1)
    PromptSetVisible(FollowPrompt, 1)
	PromptSetStandardMode(FollowPrompt,1)
	PromptSetGroup(FollowPrompt, OnShoulderPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,FollowPrompt,true)
	PromptRegisterEnd(FollowPrompt)

    Citizen.Wait(1)

    local str3 = Config.Prompts.Hunt[2]
    HuntPrompt = PromptRegisterBegin()
    PromptSetControlAction(HuntPrompt, Config.Prompts.Hunt[1])
    str3 = CreateVarString(10, 'LITERAL_STRING', str3)
    PromptSetText(HuntPrompt, str3)
    PromptSetEnabled(HuntPrompt, 1)
    PromptSetVisible(HuntPrompt, 1)
	PromptSetStandardMode(HuntPrompt,1)
	PromptSetGroup(HuntPrompt, OnShoulderPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,HuntPrompt,true)
	PromptRegisterEnd(HuntPrompt)

    Citizen.Wait(1)

    local str4 = Config.Prompts.FlyBack[2]
    FlyBackPrompt = PromptRegisterBegin()
    PromptSetControlAction(FlyBackPrompt, Config.Prompts.FlyBack[1])
    str4 = CreateVarString(10, 'LITERAL_STRING', str4)
    PromptSetText(FlyBackPrompt, str4)
    PromptSetEnabled(FlyBackPrompt, 1)
    PromptSetVisible(FlyBackPrompt, 1)
	PromptSetStandardMode(FlyBackPrompt,1)
	PromptSetGroup(FlyBackPrompt, OnFollowPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,FlyBackPrompt,true)
	PromptRegisterEnd(FlyBackPrompt)

    Citizen.Wait(1)

    local str5 = Config.Prompts.Camera[2]
    CameraPrompt = PromptRegisterBegin()
    PromptSetControlAction(CameraPrompt, Config.Prompts.Camera[1])
    str5 = CreateVarString(10, 'LITERAL_STRING', str5)
    PromptSetText(CameraPrompt, str5)
    PromptSetEnabled(CameraPrompt, 1)
    PromptSetVisible(CameraPrompt, 1)
	PromptSetStandardMode(CameraPrompt,1)
	PromptSetGroup(CameraPrompt, OnFollowPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,CameraPrompt,true)
	PromptRegisterEnd(CameraPrompt)

    Citizen.Wait(1)

    local str7 = Config.Prompts.Sell[2]
    BirdSellPrompt = PromptRegisterBegin()
    PromptSetControlAction(BirdSellPrompt,Config.Prompts.Sell[1])
    str7 = CreateVarString(10, 'LITERAL_STRING', str7)
    PromptSetText(BirdSellPrompt, str7)
    PromptSetEnabled(BirdSellPrompt, 1)
    PromptSetVisible(BirdSellPrompt, 1)
    PromptSetStandardMode(BirdSellPrompt,1)
    PromptSetGroup(BirdSellPrompt, OnShoulderPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,BirdSellPrompt,true)
    PromptRegisterEnd(BirdSellPrompt)
end

function SetupSellPrompt()
    local strst = Config.Prompts.StopSell[2]
    StopSellPrompt = PromptRegisterBegin()
    PromptSetControlAction(StopSellPrompt, Config.Prompts.StopSell[1])
    strst = CreateVarString(10, 'LITERAL_STRING', strst)
    PromptSetText(StopSellPrompt, strst)
    PromptSetEnabled(StopSellPrompt, 1)
    PromptSetVisible(StopSellPrompt, 1)
    PromptSetStandardMode(StopSellPrompt,1)
    PromptSetGroup(StopSellPrompt, SellPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,StopSellPrompt,true)
    PromptRegisterEnd(StopSellPrompt)

    -- "Buy" prompt shown when standing near another player's bird sell point.
    -- (Was referenced elsewhere but never actually registered.)
    local strbuy = Config.Prompts.BuyBird[2]
    BuyBirdPrompt = PromptRegisterBegin()
    PromptSetControlAction(BuyBirdPrompt, Config.Prompts.BuyBird[1])
    strbuy = CreateVarString(10, 'LITERAL_STRING', strbuy)
    PromptSetText(BuyBirdPrompt, strbuy)
    PromptSetEnabled(BuyBirdPrompt, 1)
    PromptSetVisible(BuyBirdPrompt, 1)
    PromptSetStandardMode(BuyBirdPrompt, 1)
    PromptSetGroup(BuyBirdPrompt, BuyBirdPrompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C,BuyBirdPrompt,true)
    PromptRegisterEnd(BuyBirdPrompt)
end
----------------------------BASIC----------------------------
function GetAreaInfo(cc)
    local area = Citizen.InvokeNative(0x43AD8FC02B429D33 ,cc.x,cc.y,cc.z,12)
  for i,v in pairs(Config.Areas) do
      if area == v[3] then
          local infoa = {
              name = v[6],
              hash = v[3],
              list = v[5],
              activity = v[4],
          }
          return infoa
      end
  end
  return nil
end
--------------------------------------------------------
function GetAreaInfo2(cc)
    local area = Citizen.InvokeNative(0x43AD8FC02B429D33 ,cc.x,cc.y,cc.z,11)
  for i,v in pairs(Config.Districts) do
      if area == v[3] then
          local infoa = {
              name = v[6],
              hash = v[3],
              list = v[5],
              activity = v[4],
          }
          return infoa
      end
  end
  return nil
end
--------------------------------------------------------
function GetAreaInfo3(cc)
    local area = Citizen.InvokeNative(0x43AD8FC02B429D33 ,cc.x,cc.y,cc.z,10)
  for i,v in pairs(Config.Districts2) do
      if area == v[3] then
          local infoa = {
              name = v[6],
              hash = v[3],
              list = v[5],
              activity = v[4],
          }
          return infoa
      end
  end
  return nil
end
--------------------------------------------------------
function PlayerArea()
    local a1, a2, a3 = GetAreaInfo(playerCoords), GetAreaInfo2(playerCoords), GetAreaInfo3(playerCoords)
    local an1 = "none"
    local an2 = "none"
    local an3 = "none"
    if a1 ~= nil then
        an1 = a1.name
    end
    if a2 ~= nil then
        an2 = a2.name
    end
    if a3 ~= nil then
        an3 = a3.name
    end
    local area = GetAreaInfo(playerCoords) or GetAreaInfo2(playerCoords) or GetAreaInfo3(playerCoords)
    return area or { name = "None", activity = false, list = {} }
end
--------------------------------------------------------
function IsBirdOfPrey(entity)
    local model = GetEntityModel(entity)
    for i,v in pairs(Config.BirdOfPreys) do
        if v == model then
            return true
        end
    end
    return false
end
--------------------------------------------------------
function IsBirdScavenger(entity)
    local model = GetEntityModel(entity)
    for i,v in pairs(Config.Scavengers) do
        if v == model then
            return true
        end
    end
    return false
end
--------------------------------------------------------
function IsBirdFisher(entity)
    local model = GetEntityModel(entity)
    for i,v in pairs(Config.FishingBirds) do
        if v == model then
            return true
        end
    end
    return false
end
----------------------------THREADS----------------------------
Citizen.CreateThread(function()
    TriggerServerEvent("jrs_huntingpets:sell:getpoints")
    SetupSellPrompt()
    SetupBirdPrompts()
    while true do
        Citizen.Wait(500)
        if PlayerPedId() then
            playerCoords = GetEntityCoords(PlayerPedId())
            playerDead = IsEntityDead(PlayerPedId())
        end
        if playerDead == 1 and CalledBird ~= nil and birdisFlyingHome == false then
            SendBirdHome(1)
        end
        if CalledBird ~= nil then
            deathEntities = {}
            if AreaC then
                Citizen.InvokeNative(0x541B8576615C33DE, AreaC, playerCoords.x, playerCoords.y, playerCoords.z)
                local found = Citizen.InvokeNative(0x886171A12F400B89, AreaC, itemS, 1)
                if found then
                    local n = 0
                    while n < found do
                        deathEntities[(GetIndexedItemInItemset(n, itemS))] = true
                        n = n + 1
                    end
                end
                Citizen.InvokeNative(0x20A4BF0E09BEE146, itemS) 
            end
        end
    end
end)
--------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)
        if CalledBird ~= nil then
            CheckEntities()
        end
    end
end)

--------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if birdOnShoulder == true then
            if IsPedClimbing(PlayerPedId()) 
            or IsPedClimbingLadder(PlayerPedId())
            or IsPedFalling(PlayerPedId())
            or IsPedHogtied(PlayerPedId())
            or IsPedHogtying(PlayerPedId())
            or IsPedRagdoll(PlayerPedId())
            or IsPedSwimming(PlayerPedId()) then
                FollowPlayer()
            end
        end
    end
end)
--------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(birdOnShoulder == true and 1 or 500)
        if birdOnShoulder == true and menuOpen == false and birdisFlyingHome == false and nearby == false and birdisHunting == false and selling == false then
            local label  = CreateVarString(10, 'LITERAL_STRING', BirdName)
            PromptSetActiveGroupThisFrame(OnShoulderPrompts, label)
            if Citizen.InvokeNative(0xC92AC953F0A982AE,SendHomePrompt) then
                SendBirdHome(0)
            end
            if Citizen.InvokeNative(0xC92AC953F0A982AE,FollowPrompt) then
                FollowPlayer()
            end
            if Citizen.InvokeNative(0xC92AC953F0A982AE,HuntPrompt) then
                TriggerServerEvent("jrs_huntingpets:checkhunt")
            end
            if Citizen.InvokeNative(0xC92AC953F0A982AE,TalkPrompt) then
                TriggerEvent("jrs_huntingpets:checktalk")
            end
            if Citizen.InvokeNative(0xC92AC953F0A982AE,BirdSellPrompt) then
                if selling == false then
                    --StartSellBird()
                    TriggerServerEvent("jrs_huntingpets:check_sell")
                end
            end
        end
        if birdIsFollowing == true and menuOpen == false and birdisFlyingHome == false and nearby == false and birdisHunting == false then
            local label  = CreateVarString(10, 'LITERAL_STRING', BirdName)
            PromptSetActiveGroupThisFrame(OnFollowPrompts, label)
            if Citizen.InvokeNative(0xC92AC953F0A982AE,FlyBackPrompt) then
                FlyToPlayer()
            end
            if Citizen.InvokeNative(0xC92AC953F0A982AE,CameraPrompt) then
                BirdCamera()
            end
        end
    end
end)
--------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000)
        if PlayerPedId() and CalledBird ~= nil and not IsEntityFrozen(CalledBird) and birdOnShoulder == false and birdIsFlytoPed == false and birdIsFollowing == true and birdisFlyingHome == false then
            local ccc = GetEntityCoords(PlayerPedId())
            local ccp = GetEntityCoords(CalledBird)
            local cca = vector3(ccc.x,ccc.y, ccp.z)
            TaskFlyingCircle(CalledBird, 4.0, cca, 3.1, 4.1)
        end
    end
end)
--------------------------------------------------------
------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        local hasPoints = type(SellPointsC) == 'table' and next(SellPointsC) ~= nil
        Citizen.Wait(hasPoints and 1 or 1000)
        if hasPoints and playerCoords ~= nil then
            for i, v in pairs(SellPointsC) do
                if tonumber(v.owner) ~= GetPlayerServerId(PlayerId()) then
                    local dist = GetDistanceBetweenCoords(playerCoords, v.sellcoords, true)
                    if dist < 10.0 then
                        Citizen.InvokeNative(0x2A32FAA57B937173, 0x6903B113, v.sellcoords.x, v.sellcoords.y, v.sellcoords.z-0.9 , 0, 0, 0, 0, 0, 0, 2.0, 2.0, 0.3, Config.Checkpoints.shop[1], Config.Checkpoints.shop[2], Config.Checkpoints.shop[3], 100, 0, 0, 2, 0, 0, 0, 0)
                    end
                    if dist < 2.0 then
                        local label  = CreateVarString(10, 'LITERAL_STRING', "$"..v.sellprice)
                        PromptSetActiveGroupThisFrame(BuyBirdPrompts, label)
                        if Citizen.InvokeNative(0xC92AC953F0A982AE,BuyBirdPrompt) then
                            TriggerServerEvent("jrs_huntingpets:sell:buyoffer", v.owner, v.sellprice, v.id)
                        end
                    end
                end
                if tonumber(v.owner) == GetPlayerServerId(PlayerId()) then
                    local dist = GetDistanceBetweenCoords(playerCoords, v.sellcoords, true)
                    if dist < 2.0 then
                        Citizen.InvokeNative(0x2A32FAA57B937173, 0x6903B113, v.sellcoords.x, v.sellcoords.y, v.sellcoords.z-0.9 , 0, 0, 0, 0, 0, 0, 2.0, 2.0, 0.3,  Config.Checkpoints.shop[1], Config.Checkpoints.shop[2], Config.Checkpoints.shop[3], 100, 0, 0, 2, 0, 0, 0, 0)
                    end
                end
            end
        end
    end
end)
------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(selling == true and 1 or 500)
        if selling == true then
            DisableControlAction(0, 0xF8982F00, true)
            while SellPointsC[CalledBirdData.id] == nil do
                Citizen.Wait(1)
            end
            local label  = CreateVarString(10, 'LITERAL_STRING', "Sell".."$"..SellPointsC[CalledBirdData.id].sellprice)
            PromptSetActiveGroupThisFrame(SellPrompts, label)
            if Citizen.InvokeNative(0xC92AC953F0A982AE,StopSellPrompt) then
                StopSellBird()
            end
        end
    end
end)
----------------------------FUNCTIONS----------------------------
function StartSellBird()
    local result = nil

    AddTextEntry("FMMC_KEY_TIP8", "Add Price")
    DisplayOnscreenKeyboard(3, "FMMC_KEY_TIP8", "", "", "", "", "", 5)
    while (UpdateOnscreenKeyboard() == 0) do
        Citizen.Wait(1);
    end
        if (GetOnscreenKeyboardResult()) then
            result = GetOnscreenKeyboardResult()
            if result then
                if tonumber(result) == nil then
                    result = 0
                end
                if tonumber(result) < 1 then
                    result = 0
                end
                SellBirdPriceAdded(tonumber(result))
            end
        end
end
----------------------------------------------------------------------------
function SellBirdPriceAdded(result)
    selling = true
    SetEntityInvincible(PlayerPedId(), true)
    TaskStandStill(PlayerPedId(), -1)
    local sc = GetEntityCoords(PlayerPedId())
    TriggerServerEvent("jrs_huntingpets:sell:create", CalledBirdData.id, result, sc, GetPlayerServerId(PlayerId()), PedToNet(CalledBird))
end
--------------------------------------------------------
function StopSellBird()
    selling = false
    SetEntityInvincible(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
    TriggerServerEvent("jrs_huntingpets:sell:stop",CalledBirdData.id)
end
--------------------------------------------------------
function CheckEntities()
    if CalledBird ~= nil and GetMount(PlayerPedId()) == 0 then
        for i, v in pairs(deathEntities) do
            if DoesEntityExist(i) and not IsThisModelAHorse(GetEntityModel(i)) then
                if IsEntityDead(i) then
                    local dist = GetDistanceBetweenCoords(playerCoords, GetEntityCoords(i), true)
                    while dist < 1.5 do
                        Citizen.Wait(200)
                        dist = GetDistanceBetweenCoords(playerCoords, GetEntityCoords(i), true)
                        if nearby == false then
                            nearby = true
                        end
                    end
                    if nearby == true then
                        nearby = false
                    end
                end
            end
        end
    end
end
--------------------------------------------------------
function FollowPlayer()
    local bc = GetEntityCoords(CalledBird)
    if IsEntityFrozen(CalledBird) then
        FreezeEntityPosition(CalledBird, false)
    end
    SetEntityCollision(CalledBird, false, false)
    if IsEntityAttached(CalledBird) then
        DetachEntity(CalledBird, 1, 1)
        birdOnShoulder = false
    end
    TaskFlyAway(CalledBird, PlayerPedId())
    Citizen.Wait(2000)
    birdIsFollowing = true
    TaskFlyingCircle(CalledBird, 4.0, GetEntityCoords(CalledBird), 3.1, 4.1)
end
--------------------------------------------------------
function SendBirdHome(id)
    Notify(Config.Texts.Bird, Config.Texts.GoingHome, 'TIP')
    birdisFlyingHome = true
    if preyID ~= nil then
        DetachEntity(preyID, 1, 1)
        preyID = nil
    end
    if IsEntityAttached(CalledBird) then
        DetachEntity(CalledBird, 1, 1)
        birdOnShoulder = false
    end
    if IsEntityFrozen(CalledBird) then
        FreezeEntityPosition(CalledBird, false)
    end
    if IsPedStill(PlayerPedId()) == 1 then
        ClearPedTasksImmediately(PlayerPedId())
    end
    if selectedScavItem ~= nil then
        selectedScavItem = nil
    end
    SetEntityCollision(CalledBird, false, false)
    TaskFlyAway(CalledBird, PlayerPedId())
    if id == 0 then
        Citizen.Wait(7000)
    else
        Citizen.Wait(500)
    end
    if Camera ~= nil then
        DeleteBirdCam()
    end
    DeleteEntity(CalledBird)
    SetEntityAsNoLongerNeeded(CalledBird)
    CalledBird = nil
    CalledBirdData = {}
    birdIsFollowing = false
    birdIsFlytoPed = false
    birdOnShoulder = false
    birdisFlyingHome = false
    birdisHunting = false
    if ActivePetType == 'bird' then ActivePetType = nil end
end
--------------------------------------------------------
function FlyToPlayer()
    birdIsFlytoPed = true
    birdIsFollowing = false
    local pc = GetEntityCoords(PlayerPedId())
    TaskStandStill(PlayerPedId(),-1)
    Notify(Config.Texts.Bird, Config.Texts.WaitBird, 'TIP')
    ClearPedTasks(CalledBird)
    Citizen.Wait(100)
    TaskFlyToCoord(CalledBird, 1.0, pc.x, pc.y, pc.z+0.5, 1, 0)
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(500)
            local dist = GetDistanceBetweenCoords(pc, GetEntityCoords(CalledBird), true)
            if dist < 5.0 then
                local pc2 = GetEntityCoords(PlayerPedId())
                local dist2 = GetDistanceBetweenCoords(GetEntityCoords(CalledBird), pc2, true)
                if dist2 > 1.2 then
                    ClearPedTasks(CalledBird)
                    TaskFlyToCoord(CalledBird, 1.0, pc2.x, pc2.y, pc2.z+0.5, 1, 0)
                end
                while dist2 > 1.5 do
                    dist2 = GetDistanceBetweenCoords(GetEntityCoords(CalledBird), pc2, true)
                    Citizen.Wait(100)
                end
                if preyID ~= nil then
                    FreezeEntityPosition(preyID, false)
                    DetachEntity(preyID, 1, 1)
                    preyID = nil
                    birdisHunting = false
                    TriggerServerEvent("jrs_huntingpets:addxp",preyXP, CalledBirdData.id)
                    CalledBirdData.xp = CalledBirdData.xp + preyXP
                    preyXP = nil
                end
                if selectedScavItem ~= nil then
                    TriggerServerEvent("jrs_huntingpets:addxp",selectedScavItem.xp, CalledBirdData.id)
                    TriggerServerEvent("jrs_huntingpets:addscavengeditem",selectedScavItem.name, selectedScavItem.amount)
                    CalledBirdData.xp = CalledBirdData.xp + selectedScavItem.xp
                    birdisHunting = false
                    selectedScavItem = nil
                end
                if Camera ~= nil then
                    DeleteBirdCam()
                end
                local model = GetEntityModel(CalledBird)
                local Attach
                if IsPedMale(PlayerPedId()) then
                    Attach = Config.BirdAttach[model].Male
                else
                    Attach = Config.BirdAttach[model].Female
                end
                AttachEntityToEntity(CalledBird, PlayerPedId(), Attach[1], Attach[2], Attach[3], Attach[4], Attach[5], Attach[6], Attach[7], false, false, true, false, 0, true, false, false)
                ClearPedTasksImmediately(CalledBird)
                SetBlockingOfNonTemporaryEvents(CalledBird, true)
                FreezeEntityPosition(CalledBird, true)
                ClearPedTasksImmediately(PlayerPedId())
                birdIsFlytoPed = false
                birdOnShoulder = true
                birdisHunting = false
                break
            end
        end
    end)
end
--------------------------------------------------------
function CreateBird(model, preset, name, xp, id)
    local playerPed = PlayerPedId()
    CalledBirdData = {
        model = model,
        preset = preset,
        name = name,
        xp = xp,
        id = id,
    }
    BirdName = name
    if CalledBird ~= nil then
        DeleteEntity(CalledBird)
        SetEntityAsNoLongerNeeded(CalledBird)
        CalledBird = nil
    end
    local x,y,z = table.unpack(GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 20.0, 0.1))

    RequestModel(model)
    while not HasModelLoaded(model) do
        Citizen.Wait(1)
    end

    CalledBird = CreatePed(model, x, y, z+20.0, GetEntityHeading(playerPed)+180, 1, 1)

    while not IsEntityAPed(CalledBird) do
        Citizen.Wait(1)
    end
    SetBlockingOfNonTemporaryEvents(CalledBird, true)
    SetEntityInvincible(CalledBird, true)
    SetEntityCollision(CalledBird, false, false)

    Citizen.InvokeNative(0x283978A15512B2FE, CalledBird, true)
	Citizen.InvokeNative(0x77FF8D35EEC6BBC4,CalledBird, preset)
	while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C,CalledBird) do
		Citizen.Wait(0)
	end

	Citizen.InvokeNative(0x704C908E9C405136, CalledBird)
	Citizen.InvokeNative(0xAAB86462966168CE, CalledBird, 1)
    Citizen.Wait(500)
    FreezeEntityPosition(CalledBird, true)
    SetModelAsNoLongerNeeded(model)
    FollowPlayer()
end
--------------------------------------------------------
function CreateBirdFromHunt(model, preset, name, preydata)
    local playerPed = PlayerPedId()
    BirdName = name
    if CalledBird ~= nil then
        DeleteEntity(CalledBird)
        SetEntityAsNoLongerNeeded(CalledBird)
        CalledBird = nil
    end
    local x,y,z = table.unpack(GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 70.0, 0.1))

    RequestModel(model)
    while not HasModelLoaded(model) do
        Citizen.Wait(1)
    end

    CalledBird = CreatePed(model, x, y, z+40.0, GetEntityHeading(playerPed)+180, 1, 0)
    while not IsEntityAPed(CalledBird) do
        Citizen.Wait(1)
    end
    SetBlockingOfNonTemporaryEvents(CalledBird, true)
    SetEntityInvincible(CalledBird, true)
    SetEntityCollision(CalledBird, false, false)

    Citizen.InvokeNative(0x283978A15512B2FE, CalledBird, true)
	Citizen.InvokeNative(0x77FF8D35EEC6BBC4,CalledBird, preset)
	while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C,CalledBird) do
		Citizen.Wait(0)
	end

	Citizen.InvokeNative(0x704C908E9C405136, CalledBird)
	Citizen.InvokeNative(0xAAB86462966168CE, CalledBird, 1)
    Citizen.Wait(500)
    SetModelAsNoLongerNeeded(model)
    if IsBirdOfPrey(CalledBird) == true then
        CreatePrey(preydata)
    elseif IsBirdScavenger(CalledBird) == true then
        selectedScavItem = CreateScavengedItem()
    elseif IsBirdFisher(CalledBird) == true then
        CreateFishPrey()
    end
    FlyToPlayer()
end
--------------------------------------------------------
function CreatePrey(preydata)
    RequestModel(preydata.model)
    while not HasModelLoaded(preydata.model) do
        Citizen.Wait(1)
    end
    local x,y,z = table.unpack(GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 70.0, 0.1))
    preyID = CreatePed(preydata.model, x, y, z+40.0, GetEntityHeading(PlayerPedId())+180, 1, 0)
    preyXP = preydata.xp
    while not IsEntityAPed(preyID) do
        Citizen.Wait(1)
    end

    Citizen.InvokeNative(0x283978A15512B2FE, preyID, true)
	Citizen.InvokeNative(0x77FF8D35EEC6BBC4,preyID, preydata.preset)
	while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C,preyID) do
		Citizen.Wait(0)
	end

	Citizen.InvokeNative(0x704C908E9C405136, preyID)
	Citizen.InvokeNative(0xAAB86462966168CE, preyID, 1)
    Citizen.Wait(500)
    FreezeEntityPosition(preyID, true)
    Citizen.InvokeNative(0x1CE875505D45338A, preyID, 0, 0) 
    SetModelAsNoLongerNeeded(preydata.model)
    AttachEntityToEntity(preyID, CalledBird, 7, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 0, true, false, false)
    FreezeEntityPosition(preyID, false)
end
--------------------------------------------------------
function CreateScavengedItem()
    local scavitem = {}
    for i,v in pairs(Config.ScavengerItems) do
        if CalledBirdData.xp >= v.xpreq then
            table.insert( scavitem, v)
        end
    end
    if #scavitem < 1 then
        Notify(Config.Texts.Bird, Config.Texts.NoHunt, 'TIP')
        return nil
    end
    local nr = math.random(1,#scavitem)
    return scavitem[nr]
end
--------------------------------------------------------
function CreateFishPrey()
    local preydata = {}
    local preys = {}
    for i,v in pairs(Config.FishItems) do
        if CalledBirdData.xp >= v.xpreq then
            table.insert( preys, v)
        end
    end
    if #preys < 1 then
        Notify(Config.Texts.Bird, Config.Texts.NoHunt, 'TIP')
        return
    end
    local nr = math.random(1,#preys)
    preydata = preys[nr]

    RequestModel(preydata.model)
    while not HasModelLoaded(preydata.model) do
        Citizen.Wait(1)
    end
    local x,y,z = table.unpack(GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 70.0, 0.1))
    preyID = CreatePed(preydata.model, x, y, z+40.0, GetEntityHeading(PlayerPedId())+180, 1, 0)
    preyXP = preydata.xp
    while not IsEntityAPed(preyID) do
        Citizen.Wait(1)
    end

    Citizen.InvokeNative(0x283978A15512B2FE, preyID, true)
	Citizen.InvokeNative(0x77FF8D35EEC6BBC4,preyID, 0)
	while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C,preyID) do
		Citizen.Wait(0)
	end

	Citizen.InvokeNative(0x704C908E9C405136, preyID)
	Citizen.InvokeNative(0xAAB86462966168CE, preyID, 1)
    Citizen.Wait(500)
    FreezeEntityPosition(preyID, true)
    Citizen.InvokeNative(0x1CE875505D45338A, preyID, 0, 0) 
    SetModelAsNoLongerNeeded(preydata.model)
    AttachEntityToEntity(preyID, CalledBird, 7, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 0, true, false, false)
    FreezeEntityPosition(preyID, false)
end
--------------------------------------------------------
function BirdCamera()
    if Camera == nil then
        Camera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", GetEntityCoords(PlayerPedId()), -90.0, 0.0, 0.0, GetGameplayCamFov())
        ShakeCam(Camera, "DRUNK_SHAKE", 0.1)
        SetCamActive(Camera, true)
        RenderScriptCams(true, true, 1000, true, false)
        AttachCamToEntity(Camera, CalledBird, 0.0, 0.0, 0.0, true)
    else
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(Camera)
        Camera = nil
    end
end
--------------------------------------------------------
function DeleteBirdCam()
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(Camera)
    Camera = nil
end

----------------------------------------------------------------------------
RegisterNetEvent('jrs_huntingpets:start_sell', function()
    if selling == false then
        StartSellBird()
    end
end)
----------------------------------------------------------------------------


-- SPAWN BIRD (from NUI via server or loadBird)
RegisterNetEvent('jrs_huntingpets:client:spawnBird')
AddEventHandler('jrs_huntingpets:client:spawnBird', function(id, model, preset, xp)
    if CalledBird ~= nil then Notify(L('notif_title_birds'), L('notif_send_bird_home_first'), 'ERROR') return end
    if HasActivePet() and ActivePetType ~= 'bird' then Notify(L('notif_title_pets_short'), L('notif_send_pet_home_first2'), 'ERROR') return end
    ActivePetType = 'bird'
    CreateBird(model, preset, 'Bird', xp, id)
end)

RegisterCommand('callbird', function()
    TriggerServerEvent('jrs_huntingpets:server:loadBird')
end)

RegisterCommand('fleebird', function()
    if CalledBird ~= nil then SendBirdHome(0) end
    if ActivePetType == 'bird' then ActivePetType = nil end
end)
----------------------------------------------------------------------------

RegisterNetEvent('jrs_huntingpets:starthunt')
AddEventHandler('jrs_huntingpets:starthunt', function()
    local ar = PlayerArea()
    local selectedprey
    if ar.activity == true then
        --print("Hunt", ar.name)
        local preys = {}
        for i,v in pairs(ar.list) do
            if CalledBirdData.xp >= v.xpreq then
                table.insert( preys, v)
            end
        end
        if #preys < 1 then
            Notify(Config.Texts.Bird, Config.Texts.NoHunt, 'TIP')
            return
        end
        local nr = math.random(1,#preys)
        selectedprey = preys[nr]
    else
        Notify(Config.Texts.Bird, Config.Texts.NoHunt, 'TIP')
        return
    end
    
    Notify(Config.Texts.Bird, Config.Texts.GoingHunt.." "..ar.name, 'TIP')
    birdisHunting = true
    if IsEntityAttached(CalledBird) then
        DetachEntity(CalledBird, 1, 1)
        birdOnShoulder = false
    end
    if IsEntityFrozen(CalledBird) then
        FreezeEntityPosition(CalledBird, false)
    end
    SetEntityCollision(CalledBird, false, false)
    TaskFlyAway(CalledBird, PlayerPedId())
    if Camera ~= nil then
        DeleteBirdCam()
    end
    local t = 0
    while t < Config.BirdGoForHuntTimer do
        Citizen.Wait(1000)
        if IsEntityDead(PlayerPedId()) then
            birdisHunting = false
            break
        end
        t = t+1
    end
    DeleteEntity(CalledBird)
        SetEntityAsNoLongerNeeded(CalledBird)
    CalledBird = nil
    birdIsFollowing = false
    birdIsFlytoPed = false
    birdisFlyingHome = false
    if birdisHunting == true then
        local b = 0
        while b < Config.HuntingTimer do
            Citizen.Wait(1000)
            if IsEntityDead(PlayerPedId()) then
                birdisHunting = false
                break
            end
            b = b + 1
        end
    end
    if birdisHunting == true then
        CreateBirdFromHunt(CalledBirdData.model, CalledBirdData.preset, CalledBirdData.name, selectedprey)
        return
    end
end)
----------------------------------------------------------------------------
RegisterNetEvent('jrs_huntingpets:sell:gotpoints_c')
AddEventHandler('jrs_huntingpets:sell:gotpoints_c', function(selldata)
    SellPointsC = selldata
end)
--------------------------------------------------------
RegisterNetEvent('jrs_huntingpets:sell:updatepoints')
AddEventHandler('jrs_huntingpets:sell:updatepoints', function(selldata, id, pedid)
    local _id = tonumber(id)
    SellPointsC[_id] = selldata
    if pedid ~= nil then
        local _pedid = NetToPed(pedid)
        DeleteEntity(_pedid)
        SetEntityAsNoLongerNeeded(_pedid)
    end
end)
--------------------------------------------------------
RegisterNetEvent('jrs_huntingpets:sell:updatepoints1')
AddEventHandler('jrs_huntingpets:sell:updatepoints1', function(id)
    SellPointsC[tonumber(id)] = nil
end)
--------------------------------------------------------
RegisterNetEvent('jrs_huntingpets:sell:finishsell')
AddEventHandler('jrs_huntingpets:sell:finishsell', function()
    if selling == true then
        selling = false
        DeleteEntity(CalledBird)
        SetEntityAsNoLongerNeeded(CalledBird)
    end
    CalledBird = nil
    CalledBirdData = {}
    selling = false
    birdOnShoulder = false
    birdIsFollowing = false
    birdIsFlytoPed = false
    birdisFlyingHome = false
    birdisHunting = false
    ClearPedTasks(PlayerPedId())
    SetEntityInvincible(PlayerPedId(), false)
end)
--------------------------------------------------------
RegisterNetEvent('jrs_huntingpets:checktalk')
AddEventHandler('jrs_huntingpets:checktalk', function()
    local model = GetEntityModel(CalledBird)
    local random1 = math.random(1, #Config.AudioBank)
    local aname = Config.AudioBank[random1].Name
    local random2 = math.random(1,#Config.AudioBank[random1].Variants)
    local sname = Config.AudioBank[random1].Variants[random2]

    if CalledBirdData.xp >= Config.ParrotTalkingXPReq then
        if (model == `a_c_carolinaparakeet_01` or model == `a_c_parrot_01`) then
            if talking == false then
                StopCurrentPlayingAmbientSpeech()
                StopCurrentPlayingSpeech()
                talking = true
                local c = GetEntityCoords(CalledBird)
                local x,y,z = c.x, c.y, c.z
    -- (old export removed)
                Citizen.Wait(1000)
                talking = false
            else
                Notify(Config.Texts.Bird, Config.Texts.WaitTalk, 'TIP')
            end
        else
            Notify(Config.Texts.Bird, Config.Texts.NotParrot, 'TIP')
        end
    else
        Notify(Config.Texts.Bird, Config.Texts.NoTalkSkill, 'TIP')
    end
end)
--------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
	if (GetCurrentResourceName() ~= resourceName) then
	  return
    end
    if CalledBird ~= nil then
        DeleteEntity(CalledBird)
        SetEntityAsNoLongerNeeded(CalledBird)
        CalledBird = nil
    end
    if Camera ~= nil then
        DeleteBirdCam()
    end
    if tempBird ~= nil then
        DeleteEntity(tempBird)
        SetEntityAsNoLongerNeeded(tempBird)
        tempBird = nil
    end
end)

