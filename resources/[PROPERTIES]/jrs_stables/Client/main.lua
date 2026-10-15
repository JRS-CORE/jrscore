local Core = exports.jrs_core:GetCore()

-- Prompts
local OpenShops
local ShopGroup = GetRandomIntInRange(0, 0xffffff)

local KeepTame, SellTame
local TameGroup = GetRandomIntInRange(0, 0xffffff)

local TradeHorse
local TradeGroup = GetRandomIntInRange(0, 0xffffff)

local LootHorse
local LootGroup = GetRandomIntInRange(0, 0xffffff)

-- Target Prompts
local HorseDrink, HorseRest, HorseSleep, HorseWallow = 0, 0, 0, 0

-- Horse Tack
local TackState, TackExtras, TackRemoved = {}, {}, {}
local TackSaving = false

-- Horse Training
local LastLoc, TamedModel = nil, nil
local IsTrainer, IsNaming, MaxBonding, HorseBreed = false, false, false, false

-- Misc.
MyHorse = 0
MyModel, MyHorseBreed, MyHorseColor = nil, nil, nil
local ShopEntity, MyEntity = 0, 0
local StableName, Site
local MyEntityID, MyHorseId
local InMenu, HasJob, UsingLantern, PromptsStarted, IsFleeing = false, false, false, false, false
local Drinking, Spawning, Sending, Cam, InWrithe, Activated = false, false, false, false, false, false
local DevModeActive = Config.devMode

function DebugPrint(message)
    if DevModeActive then
        print('^1[DEV MODE] ^4' .. message)
    end
end

local function isShopClosed(shopCfg)
    local hour = GetClockHours()
    local hoursActive = shopCfg.shop.hours.active

    if not hoursActive then
        return false
    end

    local openHour = shopCfg.shop.hours.open
    local closeHour = shopCfg.shop.hours.close

    if openHour < closeHour then
        -- Normal: shop opens and closes on the same day
        return hour < openHour or hour >= closeHour
    else
        -- Overnight: shop closes on the next day
        return hour < openHour and hour >= closeHour
    end
end

local function ManageStableBlip(site, closed)
    local siteCfg = Stables[site]

    if (closed and not siteCfg.blip.showClosed) or (not siteCfg.blip.show) then
        if siteCfg.Blip then
            RemoveBlip(siteCfg.Blip)
            siteCfg.Blip = nil
        end
        return
    end

    if not siteCfg.Blip then
        siteCfg.Blip = Citizen.InvokeNative(0x554d9d53f696d002, 1664425300, siteCfg.npc.coords) -- BlipAddForCoords
        SetBlipSprite(siteCfg.Blip, siteCfg.blip.sprite, true)
        Citizen.InvokeNative(0x9CB1A1623062F402, siteCfg.Blip, siteCfg.blip.name) -- SetBlipName
    end

    local color = siteCfg.blip.color.open
    if siteCfg.shop.jobsEnabled then color = siteCfg.blip.color.job end
    if closed then color = siteCfg.blip.color.closed end

    if Config.BlipColors[color] then
        Citizen.InvokeNative(0x662D364ABF16DE2F, siteCfg.Blip, joaat(Config.BlipColors[color])) -- BlipAddModifier
    else
        print('Error: Blip color not defined for color: ' .. tostring(color))
    end
end

local function AddStableNPC(site)
    local siteCfg = Stables[site]

    if not siteCfg.NPC then
        local modelName = siteCfg.npc.model
        local model = joaat(modelName)
        LoadModel(model, modelName)

        siteCfg.NPC = CreatePed(model, siteCfg.npc.coords.x, siteCfg.npc.coords.y, siteCfg.npc.coords.z - 1.0, siteCfg.npc.heading, false, true, true, true)
        Citizen.InvokeNative(0x283978A15512B2FE, siteCfg.NPC, true) -- SetRandomOutfitVariation

        TaskStartScenarioInPlace(siteCfg.NPC, `WORLD_HUMAN_WRITE_NOTEBOOK`, -1, true)
        SetEntityCanBeDamaged(siteCfg.NPC, false)
        SetEntityInvincible(siteCfg.NPC, true)
        Wait(500)
        FreezeEntityPosition(siteCfg.NPC, true)
        SetBlockingOfNonTemporaryEvents(siteCfg.NPC, true)
    end
end

local function RemoveStableNPC(site)
    local siteCfg = Stables[site]

    if siteCfg.NPC then
        DeleteEntity(siteCfg.NPC)
        siteCfg.NPC = nil
    end
end

local function RemoveHorsePrompts()
    local player = PlayerId()
    Citizen.InvokeNative(0xA3DB37EDF9A74635, player, MyHorse, 35, 1, true) -- Hide TARGET_INFO
    Citizen.InvokeNative(0xA3DB37EDF9A74635, player, MyHorse, 33, 1, true) -- Hide HORSE_FLEE
    UiPromptDelete(HorseDrink)
    UiPromptDelete(HorseRest)
    UiPromptDelete(HorseSleep)
    UiPromptDelete(HorseWallow)
    PromptsStarted = false
end

CreateThread(function()
    StartPrompts()

    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local sleep = 1000

        if InMenu or IsEntityDead(playerPed) then goto END end

        for site, siteCfg in pairs(Stables) do
            local distance = #(playerCoords - siteCfg.npc.coords)
            local isClosed = isShopClosed(siteCfg)

            if siteCfg.blip.show then
                ManageStableBlip(site, isClosed)
            end

            if distance > siteCfg.npc.distance or isClosed then
                RemoveStableNPC(site)
            elseif siteCfg.npc.active then
                AddStableNPC(site)
            end

            if distance <= siteCfg.shop.distance then
                sleep = 0
                if isClosed then
                    local promptText = string.format("%s%s%s%s%s%s", siteCfg.shop.name, _U('hours'), siteCfg.shop.hours.open, _U('to'), siteCfg.shop.hours.close, _U('hundred'))
                    UiPromptSetActiveGroupThisFrame(ShopGroup, CreateVarString(10, 'LITERAL_STRING', promptText), 1, 0, 0, 0)
                    UiPromptSetEnabled(OpenShops, false)
                else
                    UiPromptSetActiveGroupThisFrame(ShopGroup, CreateVarString(10, 'LITERAL_STRING', siteCfg.shop.prompt), 1, 0, 0, 0)
                    UiPromptSetEnabled(OpenShops, true)
                end

                if not isClosed and UiPromptHasStandardModeCompleted(OpenShops, 0) then
                    if siteCfg.shop.jobsEnabled then
                        CheckPlayerJob(false, site)
                        if not HasJob then goto END end
                    end
                    OpenStable(site)
                    break
                end
            end
        end
        ::END::
        Wait(sleep)
    end
end)

function OpenStable(site)
    if not exports.jrs_core:AcquireUI('jrs_stables', { focus=true, cursor=true, manageFocus=false, kind='stable' }) then return end
    StableWagonUI.SetStableContext(site)
    CheckPlayerJob(false, site)
    DisplayRadar(false)
    InMenu = true
    Site = site
    StableName = Stables[Site].shop.name
    CreateCamera()

    local horseData = Core.Callback.TriggerAwait('jrs_stables:GetMyHorses')
    if horseData then
        SendNUIMessage({
            action = 'show',
            shopData = JobMatchedHorses,
            compData = HorseComp,
            family = 'horse',
            language = StableLanguage(),
            translations = StableTranslations('horse'),
            location = StableTitle(Site),
            currencyType = Config.currencyType,
            myHorsesData = horseData
        })
        SetNuiFocus(true, true)
    else
        print('No horse data received!')
        if StableMenuBridge then StableMenuBridge.Close() end
    end
end

local function ClearShopHorse()
    MyEntityID = nil
    TackState, TackExtras, TackRemoved = {}, {}, {}
    if ShopEntity ~= 0 then
        DeleteEntity(ShopEntity)
        ShopEntity = 0
    end

    if MyEntity ~=0 then
        DeleteEntity(MyEntity)
        MyEntity = 0
    end
end

local function CheckEntityExists(entity)
    local timeout = 10000
    local startTime = GetGameTimer()

    while not DoesEntityExist(entity) do
        if GetGameTimer() - startTime > timeout then
            print('Failed to create entity:', entity)
            return false
        end
        Wait(10)
    end
    return true
end

-- View Horses for Purchase
RegisterNUICallback('loadHorse', function(data, cb)
    if StableWagonUI.IsActive() then return StableWagonUI.Handle('loadHorse', data, cb) end
    cb('ok')
    ClearShopHorse()

    local modelName = data.horseModel
    local model = joaat(modelName)
    LoadModel(model, modelName)

    local siteCfg = Stables[Site]
    local coords = siteCfg.horse.coords
    ShopEntity = CreatePed(model, coords.x, coords.y, coords.z - 1.0, siteCfg.horse.heading, false, false, false, false)

    local entityExists = CheckEntityExists(ShopEntity)
    if not entityExists then
        return
    end

    Citizen.InvokeNative(0x283978A15512B2FE, ShopEntity, true) -- SetRandomOutfitVariation
    Citizen.InvokeNative(0x58A850EAEE20FAA3, ShopEntity) -- PlaceObjectOnGroundProperly
    Citizen.InvokeNative(0x7D9EFB7AD6B19754, ShopEntity, true) -- FreezeEntityPosition

    if not Cam then
        Cam = true
        CameraLighting()
    end

    SetBlockingOfNonTemporaryEvents(ShopEntity, true)
    SetPedConfigFlag(ShopEntity, 113, true) -- DisableShockingEvents
    Wait(300)
    Citizen.InvokeNative(0x6585D955A68452A5, ShopEntity) -- ClearPedEnvDirt
end)

RegisterNUICallback('BuyHorse', function(data, cb)
    if StableWagonUI.IsActive() then return StableWagonUI.Handle('BuyHorse', data, cb) end
    cb('ok')
    CheckPlayerJob(true, nil)

    if Stables[Site].trainerBuy and not IsTrainer then
        Core.NotifyRightTip(_U('trainerBuyHorse'), 4000)
        StableMenu()
        return
    end

    data.isTrainer = IsTrainer
    data.origin = 'buyHorse'

    local canBuy = Core.Callback.TriggerAwait('jrs_stables:BuyHorse', data)
    if canBuy then
        SetHorseName(data)
    else
        StableMenu()
    end
end)

function SetHorseName(data)
    IsNaming = true

    if data.origin ~= 'tameHorse' then
        SendNUIMessage({ action = 'hide' })
        SetNuiFocus(false, false)
        Wait(200)
    end

    AddTextEntry('FMMC_MPM_NA', _U('nameHorse'))
    DisplayOnscreenKeyboard(1, 'FMMC_MPM_NA', '', '', '', '', '', 30)

    while UpdateOnscreenKeyboard() == 0 do
        DisableAllControlActions(0)
        Wait(0)
    end

    if GetOnscreenKeyboardResult() then
        local horseName = GetOnscreenKeyboardResult()
        if string.len(horseName) > 0 then
            data.name = horseName
            if data.origin == 'updateHorse' then
                local nameSaved = Core.Callback.TriggerAwait('jrs_stables:UpdateHorseName', data)
                if nameSaved then
                    StableMenu()
                end
                IsNaming = false
                return
            elseif data.origin == 'buyHorse' then
                data.captured = 0
                local horseSaved = Core.Callback.TriggerAwait('jrs_stables:SaveNewHorse', data)
                if horseSaved then
                    StableMenu()
                end
                IsNaming = false
                return
            elseif data.origin == 'tameHorse' then
                data.captured = 1
                local playerPed = PlayerPedId()
                Citizen.InvokeNative(0x48E92D3DDE23C23A, playerPed, 0, 0, 0, 0, data.mount) -- TaskDismountAnimal
                while not Citizen.InvokeNative(0x01FEE67DB37F59B2, playerPed) do -- IsPedOnFoot
                    Wait(10)
                end
                local horseSaved = Core.Callback.TriggerAwait('jrs_stables:SaveTamedHorse', data)
                if horseSaved then
                    DeleteEntity(data.mount)
                    HorseBreed = false
                end
                IsNaming = false
                return
            end
        else
            SetHorseName(data)
            return
        end
    end

    if data.origin ~= 'tameHorse' then
        local horseData = Core.Callback.TriggerAwait('jrs_stables:GetMyHorses')
        if horseData then
            SendNUIMessage({
                action = 'show',
                shopData = JobMatchedHorses,
                compData = HorseComp,
                family = 'horse',
            language = StableLanguage(),
            translations = StableTranslations('horse'),
                location = StableTitle(Site),
                currencyType = Config.currencyType,
                myHorsesData = horseData
            })
            SetNuiFocus(true, true)
        end
    end
    IsNaming = false
end

RegisterNUICallback('RenameHorse', function(data, cb)
    if StableWagonUI.IsActive() then return StableWagonUI.Handle('RenameHorse', data, cb) end
    cb('ok')
    data.origin = 'updateHorse'
    SetHorseName(data)
end)

-- View Owned Horse in Stable Menu
RegisterNUICallback('loadMyHorse', function(data, cb)
    if StableWagonUI.IsActive() then return StableWagonUI.Handle('loadMyHorse', data, cb) end
    cb('ok')
    ClearShopHorse()
    MyEntityID = data.HorseId
    TackState, TackExtras = StableTack.State(data.HorseComp)
    TackRemoved = {}

    local modelName = data.HorseModel
    local model = joaat(modelName)
    LoadModel(model, modelName)

    local siteCfg = Stables[Site]
    local coords = siteCfg.horse.coords
    MyEntity = CreatePed(model, coords.x, coords.y, coords.z - 1.0, siteCfg.horse.heading, false, false, false, false)

    local entityExists = CheckEntityExists(MyEntity)
    if not entityExists then
        return
    end

    Citizen.InvokeNative(0x283978A15512B2FE, MyEntity, true) -- SetRandomOutfitVariation
    Citizen.InvokeNative(0x58A850EAEE20FAA3, MyEntity) -- PlaceObjectOnGroundProperly
    Citizen.InvokeNative(0x7D9EFB7AD6B19754, MyEntity, true) -- FreezeEntityPosition

    if data.HorseGender == 'female' then
        Citizen.InvokeNative(0x5653AB26C82938CF, MyEntity, 41611, 1.0) -- SetCharExpression
        Citizen.InvokeNative(0xCC8CA3E88256E58F, MyEntity, false, true, true, true, false) -- UpdatePedVariation
    end

    if not Cam then
        Cam = true
        CameraLighting()
    end

    SetBlockingOfNonTemporaryEvents(MyEntity, true)
    SetPedConfigFlag(MyEntity, 113, true) -- PCF_DisableShockingEvents
    Wait(300)
    Citizen.InvokeNative(0x6585D955A68452A5, MyEntity) -- ClearPedEnvDirt

    if MyEntity ~= 0 then ApplyHorseTack(MyEntity, StableTack.Pack(TackState, TackExtras)) end
end)

RegisterNUICallback('selectHorse', function(data, cb)
    if StableWagonUI.IsActive() then return StableWagonUI.Handle('selectHorse', data, cb) end
    cb('ok')
    if Config.HorseTraining.enabled then
        local result = Core.Callback.TriggerAwait('jrs_stables:horse:select', {id=data.horseId,site=Site})
        if not result or not result.ok then Core.NotifyRightTip(HorseText(result and result.code or 'horseUnavailable'),4000) end
    else TriggerServerEvent('jrs_stables:SelectHorse', data) end
end)

function GetSelectedHorse()
    local data = Core.Callback.TriggerAwait('jrs_stables:GetHorseData')

    if data == false then
        return print('No selected-horse data returned!')
    end

    SpawnHorse(data)
end

local function CloseStableMenu(data)
    local wasWagon = StableWagonUI.IsActive()
    if data.MenuAction == 'save' and not wasWagon then
        if TackSaving then return end
        TackSaving = true
        local result = SaveComps(data)
        TackSaving = false
        if not result then return end
        if not InMenu then return end
    end
    StableWagonUI.Close()

    SendNUIMessage({ action = 'hide' })
    SetNuiFocus(false, false)


    ClearShopHorse()

    Cam = false
    DestroyAllCams(true)
    DisplayRadar(true)
    InMenu = false
    ClearPedTasksImmediately(PlayerPedId())

end
RegisterNUICallback('CloseStable', function(data, cb)
    cb('ok')
    if InMenu then CloseStableMenu(data) end
end)

-- Payment and persistence complete before deleting the preview or closing the menu.
function SaveComps(data)
    if not MyEntityID then return false end
    local id = MyEntityID
    local components = StableTack.Pack(TackState, TackExtras)
    local removed = {}
    for category in pairs(TackRemoved) do removed[category]=true end
    local result = Core.Callback.TriggerAwait('jrs_stables:BuyTack', {
        horseId=id, site=Site, currencyType=data and data.currencyType or 0, components=components,
    })
    if result and tonumber(MyHorseId)==tonumber(id) and DoesEntityExist(MyHorse) then
        for category in pairs(removed) do RemoveComponent(StableTack.categories[category], MyHorse) end
        ApplyHorseTack(MyHorse, components)
    end
    return result == true
end

-- Reopen Menu After Sell or Failed Purchase
function StableMenu()
    if not InMenu then return end
    if StableWagonUI.IsActive() then return StableWagonUI.Show() end
    ClearShopHorse()

    local horseData = Core.Callback.TriggerAwait('jrs_stables:GetMyHorses')
        if horseData then
            SendNUIMessage({
            action = 'show',
            shopData = JobMatchedHorses,
            compData = HorseComp,
            family = 'horse',
            language = StableLanguage(),
            translations = StableTranslations('horse'),
            location = StableTitle(Site),
            currencyType = Config.currencyType,
            myHorsesData = horseData
        })
        SetNuiFocus(true, true)
    end
end

function SpawnHorse(data)
    if data.needsRevive or tonumber(data.dead)==1 or tonumber(data.writhe)==1 then
        return Core.NotifyRightTip(HorseText('horseNeedRevive'),4000)
    end
    if Spawning then
        return
    end
    Spawning = true

    if MyHorse ~= 0 then
        DeleteEntity(MyHorse)
        MyHorse = 0
    end

    MyHorseId = data.id
    HorseName = data.name
    local xp = tonumber(data.xp) or 0
    local components = StableTack.List(data.components)

    local horseModel = data.model
    MyModel = joaat(horseModel)
    LoadModel(MyModel, horseModel)

    for _, horseCfg in pairs(Horses) do
        for model, modelCfg in pairs(horseCfg.colors) do
            local horseHash = joaat(model)
            if horseHash == MyModel then
                MyHorseBreed = horseCfg.breed
                MyHorseColor = modelCfg.color
                break
            end
        end
    end

    local player = PlayerId()
    local playerPed = PlayerPedId()
    local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(playerPed, 0.0, -10.0, 0.0))
    local spawnPosition = nil
    for height = 1, 1000 do
        local groundCheck, ground = GetGroundZAndNormalFor_3dCoord(x, y, height + 0.0)
        if groundCheck then
            spawnPosition = vector3(x, y, ground)
            break
        end
    end

    local index = 0
    while index < 25 do
        local nodeCheck, node = GetNthClosestVehicleNode(x, y, z, index, 1, 1077936128, 0)
        if nodeCheck then
            spawnPosition = node
            break
        else
            index = index + 3
        end
    end

    if not spawnPosition then
        return print('No spawn position found!')
    end

    MyHorse = CreatePed(MyModel, spawnPosition.x, spawnPosition.y, spawnPosition.z, GetEntityHeading(playerPed), true, false, false, false)
    local entityExists = CheckEntityExists(MyHorse)
    if not entityExists then
        return
    end

    SetModelAsNoLongerNeeded(MyModel)

    LocalPlayer.state.HorseData = {
        MyHorse = NetworkGetNetworkIdFromEntity(MyHorse)
    }

    Citizen.InvokeNative(0x9587913B9E772D29, MyHorse, 0) -- PlaceEntityOnGroundProperly
    Citizen.InvokeNative(0x283978A15512B2FE, MyHorse, true) -- SetRandomOutfitVariation
    if data.gender == 'female' then
        Citizen.InvokeNative(0x5653AB26C82938CF, MyHorse, 41611, 1.0) -- SetCharExpression
        Citizen.InvokeNative(0xCC8CA3E88256E58F, MyHorse, false, true, true, true, false) -- UpdatePedVariation
    end
    Citizen.InvokeNative(0xD2CB0FB0FDCB473D, playerPed, MyHorse) -- SetPedAsSaddleHorseForPlayer
    Citizen.InvokeNative(0x931B241409216C1F, playerPed, MyHorse, false) -- SetPedOwnsAnimal
    Citizen.InvokeNative(0xB8B6430EAD2D2437, MyHorse, `PLAYER_HORSE`) -- SetPedPersonality
    Citizen.InvokeNative(0xE6D4E435B56D5BD0, player, MyHorse) -- SetPlayerOwnsMount

    -- ModifyPlayerUiPromptForPed / Horse Prompts / (Block = 0, Hide = 1, Grey Out = 2)
    Citizen.InvokeNative(0xA3DB37EDF9A74635, player, MyHorse, 49, 1, true) -- HORSE_BRUSH
    Citizen.InvokeNative(0xA3DB37EDF9A74635, player, MyHorse, 50, 1, true) -- HORSE_FEED
    if not Config.fleeEnabled then
        Citizen.InvokeNative(0xA3DB37EDF9A74635, player, MyHorse, 33, 1, true) -- HORSE_FLEE
    end

    -- Set Horse Health and Stamina
    local health = data.health or 100
    if health == 0 then
        health = 100
    end
    Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 0, health)  -- SetAttributeCoreValue

    local stamina = data.stamina or 100
    if stamina == 0 then
        stamina = 100
    end
    Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 1, stamina) -- SetAttributeCoreValue

    -- Bonding
    Citizen.InvokeNative(0x09A59688C26D88DF, MyHorse, 7, xp) -- SetAttributePoints
    local maxXp = Citizen.InvokeNative(0x223BF310F854871C, MyHorse, 7) -- GetMaxAttributePoints
    MaxBonding = false
    if xp >= maxXp then
        MaxBonding = true
    end

    if Config.trainerOnly then
        CheckPlayerJob(true, nil)
        if IsTrainer then
            TriggerEvent('jrs_stables:HorseBonding')
        end
    else
        TriggerEvent('jrs_stables:HorseBonding')
    end

    if StableHorseTraining and Config.HorseTraining.enabled then StableHorseTraining.Apply(MyHorse, data.training) end
    local currentLevel = Citizen.InvokeNative(0x147149F2E909323C, MyHorse, 7, Citizen.ResultAsInteger()) -- GetAttributeBaseRank

    -- SetPedConfigFlag
    if currentLevel >= 2 then
        Citizen.InvokeNative(0x1913FE4CBF41C463, MyHorse, 113, true) -- DisableShockingEvents
    end
    if currentLevel >= 3 then
        Citizen.InvokeNative(0x1913FE4CBF41C463, MyHorse, 312, true) -- DisableHorseGunshotFleeResponse
    end
    Citizen.InvokeNative(0x1913FE4CBF41C463, MyHorse, 297, true) -- ForceInteractionLockonOnTargetPed / Allow to Lead Horse
    Citizen.InvokeNative(0x1913FE4CBF41C463, MyHorse, 471, Config.disableKick) -- DisableHorseKick

    Citizen.InvokeNative(0xE2487779957FE897, MyHorse, 528) -- SetTransportUsageFlags

    local horseBlip = Citizen.InvokeNative(0x23f74c2fda6e7c61, -1230993421, MyHorse) -- BlipAddForEntity
    Citizen.InvokeNative(0x9CB1A1623062F402, horseBlip, HorseName) -- SetBlipName
    SetPedPromptName(MyHorse, HorseName)

    TriggerServerEvent('jrs_stables:RegisterInventory', MyHorseId, horseModel)

    if Config.shareInventory then
        Entity(MyHorse).state:set('myHorseId', MyHorseId, true)
    end
    if StableHorseTraining and Config.HorseTraining.enabled then StableHorseTraining.Register(MyHorse, data) end

    if Config.horseTag then
        TriggerEvent('jrs_stables:HorseTag')
    end

    TriggerEvent('jrs_stables:TradeHorse')

    PromptsStarted = false
    TriggerEvent('jrs_stables:HorsePrompts')

    if Config.saveInterval > 0 then
        TriggerEvent('jrs_stables:HorseMonitor')
    end

    ApplyHorseTack(MyHorse, components)

    InWrithe = false
    Activated = false
    LastLoc = nil
    UsingLantern = false
    Spawning = false

    if data.writhe == 1 then
        TriggerEvent('jrs_stables:ManageHorseDeath')
        return
    end

    Sending = true
    SendHorse()
end

-- Loot Players Horse Inventory
CreateThread(function()
    if Config.shareInventory then
        while true do
            local horse, horseId, isLeading, owner = nil, nil, nil, nil
            local playerPed = PlayerPedId()
            local sleep = 1000

            if (IsEntityDead(playerPed)) or (not IsPedOnFoot(playerPed)) then goto END end

            horse = Citizen.InvokeNative(0x0501D52D24EA8934, 1, Citizen.ResultAsInteger()) -- Get HorsePedId in Range
            if (horse == 0) or (horse == MyHorse) then goto END end

            owner = Citizen.InvokeNative(0xAD03B03737CE6810, horse) -- GetPlayerOwnerOfMount
            isLeading = Citizen.InvokeNative(0xEFC4303DDC6E60D3, playerPed) -- IsPedLeadingHorse
            if (owner == 255) or isLeading then goto END end

            sleep = 0
            UiPromptSetActiveGroupThisFrame(LootGroup, CreateVarString(10, 'LITERAL_STRING', _U('lootInventory')), 1, 0, 0, 0)
            if UiPromptHasStandardModeCompleted(LootHorse, 0) then
                horseId = Entity(horse).state.myHorseId
                OpenInventory(horse, horseId, true)
            end
            ::END::
            Wait(sleep)
        end
    end
end)

-- Set Horse Name and Health Bar Above Horse
AddEventHandler('jrs_stables:HorseTag', function()
    if not Config.horseTag or MyHorse == 0 then return end
    local tagDistance = Config.tagDistance
    local gamerTagId = Citizen.InvokeNative(0xE961BF23EAB76B12, MyHorse, HorseName) -- CreateMpGamerTagOnEntity
    Citizen.InvokeNative(0x5F57522BC1EB9D9D, gamerTagId, `PLAYER_HORSE`) -- SetMpGamerTagTopIcon

    while MyHorse ~= 0 and Config.horseTag do
        Wait(1000)

        if MyHorse == 0 or not Config.horseTag then break end

        local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(MyHorse))
        if dist < tagDistance and Citizen.InvokeNative(0xAAB0FE202E9FC9F0, MyHorse, -1) then -- IsMountSeatFree
            Citizen.InvokeNative(0x93171DDDAB274EB8, gamerTagId, 3) -- SetMpGamerTagVisibility
        else
            if Citizen.InvokeNative(0x502E1591A504F843, gamerTagId, MyHorse) then -- IsMpGamerTagActiveOnEntity
                Citizen.InvokeNative(0x93171DDDAB274EB8, gamerTagId, 0) -- SetMpGamerTagVisibility
            end
        end
    end

    Citizen.InvokeNative(0x839BFD7D7E49FE09, Citizen.PointerValueIntInitialized(gamerTagId)) -- RemoveMpGamerTag
end)

-- Manage Horse Lockon Prompts
local function HandleHorseAction(key, action)
    if Citizen.InvokeNative(0x580417101DDB492F, 0, key) and not Drinking then
        action()
    end
end

AddEventHandler('jrs_stables:HorsePrompts', function()
    local player = PlayerId()
    local fleeEnabled = Config.fleeEnabled
    local distanceCheckEnabled = Config.horseDistance.enabled
    local horseRadius = Config.horseDistance.radius
    local drinkKey = Config.keys.drink
    local restKey = Config.keys.rest
    local sleepKey = Config.keys.sleep
    local wallowKey = Config.keys.wallow

    while MyHorse ~= 0 do
        local playerPed = PlayerPedId()
        local sleep = 1000
        local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(MyHorse))

        if distanceCheckEnabled and distance > horseRadius then
            SaveHorseStats(InWrithe)
            DeleteEntity(MyHorse)
            MyHorse = 0
            goto END
        end

        if (IsPlayerFreeAiming(player)) or (distance > 2.8) or (IsEntityDead(playerPed)) then
            RemoveHorsePrompts()
            goto END
        end

        sleep = 0

        if Citizen.InvokeNative(0x91AEF906BCA88877, 0, `INPUT_OPEN_SATCHEL_HORSE_MENU`) then -- IsDisabledControlJustPressed
            OpenInventory(MyHorse, MyHorseId, false)
        end

        if InWrithe and Citizen.InvokeNative(0x91AEF906BCA88877, 0, `INPUT_REVIVE`) then  -- IsDisabledControlJustPressed
            TriggerEvent('jrs_stables:ReviveHorse')
            goto END
        end

        Citizen.InvokeNative(0xA3DB37EDF9A74635, player, MyHorse, 35, 1, false) -- Show TARGET_INFO
        Citizen.InvokeNative(0xA3DB37EDF9A74635, player, MyHorse, 33, 1, false) -- Show HORSE_FLEE

        if Citizen.InvokeNative(0x27F89FDC16688A7A, player, MyHorse, false) then -- IsPlayerTargettingEntity
            sleep = 0
            local menuGroup = Citizen.InvokeNative(0xB796970BD125FCE8, MyHorse) -- PromptGetGroupIdForTargetEntity
            HorseTargetPrompts(menuGroup)

            HandleHorseAction(drinkKey, HorseDrinking)
            HandleHorseAction(restKey, HorseResting)
            HandleHorseAction(sleepKey, HorseSleeping)
            HandleHorseAction(wallowKey, HorseWallowing)

            if fleeEnabled and Citizen.InvokeNative(0x580417101DDB492F, 0, `INPUT_HORSE_COMMAND_FLEE`) then -- IsControlJustPressed
                FleeHorse()
            end
        end
        ::END::
        Wait(sleep)
    end
end)

function HorseDrinking()
    if not IsEntityInWater(MyHorse) then
        Core.NotifyRightTip(HorseName .. _U('needWater'), 4000)
        return
    end

    Drinking = true
    local drinkTime = Config.drinkLength * 1000
    local dict = 'amb_creature_mammal@world_horse_drink_ground@idle'

    if LoadAnim(dict) then
        TaskPlayAnim(MyHorse, dict, 'idle_a', 1.0, 1.0, drinkTime, 3, 1.0, false, false, false)
    end

    Wait(drinkTime)

    local health = Citizen.InvokeNative(0x36731AC041289BB1, MyHorse, 0, Citizen.ResultAsInteger()) -- GetAttributeCoreValue
    local stamina = Citizen.InvokeNative(0x36731AC041289BB1, MyHorse, 1, Citizen.ResultAsInteger()) -- GetAttributeCoreValue

    if health < 100 or stamina < 100 then
        local healthBoost = Config.boost.drinkHealth
        local staminaBoost = Config.boost.drinkStamina

        if healthBoost > 0 then
            local newHealth = math.min(health + healthBoost, 100)
            Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 0, newHealth) -- SetAttributeCoreValue
        end

        if staminaBoost > 0 then
            local newStamina = math.min(stamina + staminaBoost, 100)
            Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 1, newStamina) -- SetAttributeCoreValue
        end

        if Config.horseXpPerDrink > 0 and not MaxBonding then
            if not Config.trainerOnly or (Config.trainerOnly and IsTrainer) then
                SaveXp('drink')
            end
        end

        Citizen.InvokeNative(0x67C540AA08E4A6F5, 'Core_Fill_Up', 'Consumption_Sounds', true, 0) -- PlaySoundFrontend
    end

    Drinking = false
end

function HorseResting()
    if not Citizen.InvokeNative(0xAAB0FE202E9FC9F0, MyHorse, -1) then -- IsMountSeatFree
        return
    end

    local dict = 'amb_creature_mammal@world_horse_resting@idle'

    if LoadAnim(dict) then
        TaskPlayAnim(MyHorse, dict, 'idle_a', 1.0, 1.0, -1, 3, 1.0, false, false, false)
    end
end

function HorseSleeping()
    if not Citizen.InvokeNative(0xAAB0FE202E9FC9F0, MyHorse, -1) then -- IsMountSeatFree
        return
    end

    local dict = 'amb_creature_mammal@world_horse_sleeping@base'

    if LoadAnim(dict) then
        TaskPlayAnim(MyHorse, dict, 'base', 1.0, 1.0, -1, 3, 1.0, false, false, false)
    end
end

function HorseWallowing()
    if not Citizen.InvokeNative(0xAAB0FE202E9FC9F0, MyHorse, -1) then -- IsMountSeatFree
        return
    end

    local dict = 'amb_creature_mammal@world_horse_wallow_shake@idle'

    if LoadAnim(dict) then
        TaskPlayAnim(MyHorse, dict, 'idle_a', 1.0, 1.0, -1, 3, 1.0, false, false, false)
    end
end

function LoadAnim(dict)
    RequestAnimDict(dict)
    local startTime = GetGameTimer()
    local timeout = 5000

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - startTime > timeout then
            print("Failed to load animation dictionary " .. dict)
            return false
        end
        Wait(10)
    end
    return true
end

-- Event Listener
CreateThread(function()
    local writheEnabled = Config.death.writheEnabled
    while true do
        Wait(0)

        local size = GetNumberOfEvents(0)
        if size > 0 then
            for i = 0, size - 1 do
                local event = Citizen.InvokeNative(0xA85E614430EFF816, 0, i) -- GetEventAtIndex

                if event == 1327216456 then -- EVENT_PED_WHISTLE
                    local eventDataSize = 2
                    local eventDataStruct = DataView.ArrayBuffer(128)
                    eventDataStruct:SetInt32(0, 0) -- whistler ped id
                    eventDataStruct:SetInt32(8, 0) -- whistle type

                    local data = Citizen.InvokeNative(0x57EC5FA4D4D6AFCA, 0, i, eventDataStruct:Buffer(), eventDataSize) -- GetEventData
                    if data then
                        if eventDataStruct:GetInt32(0) == PlayerPedId() then
                            if eventDataStruct:GetInt32(8) ~= 869278708 then -- WHISTLEHORSELONG
                                TriggerEvent('jrs_stables:WhistleHorse')
                            else
                                TriggerEvent('jrs_stables:LongWhistleHorse')
                            end
                        end
                    end

                elseif event == 218595333 then -- EVENT_HORSE_BROKEN
                    local eventDataSize = 3
                    local eventDataStruct = DataView.ArrayBuffer(128)
                    eventDataStruct:SetInt32(0, 0)  -- Rider Ped Id
                    eventDataStruct:SetInt32(8, 0)  -- Horse Ped Id
                    eventDataStruct:SetInt32(16, 0) -- Broken Type Id

                    local data = Citizen.InvokeNative(0x57EC5FA4D4D6AFCA, 0, i, eventDataStruct:Buffer(), eventDataSize) -- GetEventData
                    if data then
                        if eventDataStruct:GetInt32(16) == 2 then -- Horse Taming Successful
                            local tamedPedId = eventDataStruct:GetInt32(8)
                            local tamedNetId = NetworkGetNetworkIdFromEntity(tamedPedId)
                            Entity(tamedPedId).state:set('netId', tamedNetId, true)
                        end
                    end

                elseif event == 2145012826 then -- EVENT_ENTITY_DESTROYED 
                    local eventDataSize = 9
                    local eventDataStruct = DataView.ArrayBuffer(128)
                    eventDataStruct:SetInt32(0, 0)  -- Destroyed Entity Id
                    eventDataStruct:SetInt32(8, 0)  -- Object/Ped Id that Damaged Entity
                    eventDataStruct:SetInt32(16, 0) -- Weapon Hash that Damaged Entity
                    eventDataStruct:SetInt32(24, 0) -- Ammo Hash that Damaged Entity
                    eventDataStruct:SetInt32(32, 0) -- (float) Damage Amount
                    eventDataStruct:SetInt32(40, 0) -- Unknown
                    eventDataStruct:SetInt32(48, 0) -- (float) Entity Coord x
                    eventDataStruct:SetInt32(56, 0) -- (float) Entity Coord y
                    eventDataStruct:SetInt32(64, 0) -- (float) Entity Coord z

                    local data = Citizen.InvokeNative(0x57EC5FA4D4D6AFCA, 0, i, eventDataStruct:Buffer(), eventDataSize) -- GetEventData
                    local entity = eventDataStruct:GetInt32(0)
                    if data then
                        if entity == MyHorse then
                            if writheEnabled then
                                TriggerEvent('jrs_stables:ManageHorseDeath')
                            else
                                if Config.HorseTraining.enabled then TriggerServerEvent('jrs_stables:UpdateHorseStatus',MyHorseId,'dead') end
                                Wait(5000)
                                if MyHorse==entity then
                                    SaveHorseStats(true)
                                    if MyHorse==entity then DeleteEntity(MyHorse); MyHorse=0 end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('jrs_stables:ManageHorseDeath', function()
    local horse, id = MyHorse, MyHorseId
    if horse==0 or not DoesEntityExist(horse) then return end
    if not InWrithe then
        InWrithe = true
        Citizen.InvokeNative(0x71BC8E838B9C6035, MyHorse) -- ResurrectPed
        Citizen.InvokeNative(0x1913FE4CBF41C463, MyHorse, 136, false)-- SetPedConfigFlag / CannotBeMounted
        Citizen.InvokeNative(0x8C038A39C4A4B6D6, MyHorse, 0, 0) -- TaskAnimalWrithe
        Wait(100)
        if MyHorse~=horse or MyHorseId~=id then return end
        Citizen.InvokeNative(0x925A160133003AC6, MyHorse, true) -- SetPausePedWritheBleedout
        RemoveHorsePrompts()

        Core.NotifyRightTip(_U('horseWrithe'), 4000)

        if Config.death.persistentWrithe or Config.HorseTraining.enabled then
            TriggerServerEvent('jrs_stables:SetHorseWrithe', MyHorseId)
        end

        SaveHorseStats(true)
    else
        local action = (Config.HorseTraining.enabled and 'dead') or (Config.death.permanent and 'dead') or (Config.death.deselect and 'deselect') or nil
        if action then
            Core.NotifyRightTip(_U('horseDied'), 4000)
        end
        TriggerServerEvent('jrs_stables:UpdateHorseStatus', MyHorseId, action)

        Wait(5000)
        if MyHorse~=horse or MyHorseId~=id then return end
        SaveHorseStats(true)
        if MyHorse~=horse or MyHorseId~=id then return end
        DeleteEntity(MyHorse)
        MyHorse = 0
        InWrithe = false
    end
end)

-- Call Horse to Player
AddEventHandler('jrs_stables:WhistleHorse', function()
    if MyHorse == 0 then
        WhistleSpawn()
        return
    end

    if Citizen.InvokeNative(0x77F1BEB8863288D5, MyHorse, 0x4924437D, false) ~= 0 then -- GetScriptTaskStatus / SCRIPT_TASK_GO_TO_ENTITY
        local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(MyHorse))

        if dist >= 100 then
            DeleteEntity(MyHorse)
            MyHorse = 0
            GetSelectedHorse()
        else
            Sending = true
            SendHorse()
        end
    end
end)

-- Call Horse or have Horse Follow Player
AddEventHandler('jrs_stables:LongWhistleHorse', function()
    local playerPed = PlayerPedId()

    if MyHorse == 0 then
        WhistleSpawn()
        return
    end

    if Citizen.InvokeNative(0x77F1BEB8863288D5, MyHorse, 0x4924437D, 0) ~= 0 then -- GetScriptTaskStatus
        local dist = #(GetEntityCoords(playerPed) - GetEntityCoords(MyHorse))

        if dist <= 45 then
            if Citizen.InvokeNative(0x77F1BEB8863288D5, MyHorse, 0x3EF867F4, 0) ~= 1 then -- GetScriptTaskStatus
                Citizen.InvokeNative(0x304AE42E357B8C7E, MyHorse, playerPed, math.random(1.0, 4.0), math.random(5.0, 8.0), 0.0, 0.7, -1, 3.0, true) -- TaskFollowToOffsetOfEntity
            else
                ClearPedTasks(MyHorse)
            end
        end
    end
end)

function WhistleSpawn()
    if Config.whistleSpawn then
        GetSelectedHorse()
    else
        Core.NotifyRightTip(_U('stableSpawn'), 4000)
    end
end

-- Move horse to Player
function SendHorse()
    local playerPed = PlayerPedId()

    TaskGoToEntity(MyHorse, playerPed, -1, 10.2, 2.0, 0.0, 0)

    while Sending do
        Wait(0)
        local dist = #(GetEntityCoords(playerPed) - GetEntityCoords(MyHorse))
        if dist <= 10.0 then
            ClearPedTasks(MyHorse)
            Sending = false
        end
    end
end

-- Wild Horse Taming
CreateThread(function()
    local horseModel

    while true do
        local mount = Citizen.InvokeNative(0xE7E11B8DCBED1058, PlayerPedId()) -- GetMount
        if not mount or mount == MyHorse then
            goto END
        end

        horseModel = GetEntityModel(mount)

        for _, horseCfg in pairs(Horses) do
            for model, modelCfg in pairs(horseCfg.colors) do
                local horseHash = joaat(model)
                if horseHash == horseModel then
                    TamedModel = model
                    if Config.displayHorseBreed and not HorseBreed then
                        if horseCfg.breed == 'Other' then
                            Core.NotifyBottomRight(modelCfg.color, 1000)
                        else
                            Core.NotifyBottomRight(horseCfg.breed, 1000)
                        end
                        HorseBreed = true
                    end
                end
            end
        end
        ::END::
        Wait(1000)
    end
end)

CreateThread(function()
    local mount = 0
    local mountNetId, tamedNetId
    local allowSale = Config.allowSale
    local allowKeep = Config.allowKeep
    local trainerOnly = Config.trainerOnly

    while true do
        local playerPed = PlayerPedId()
        local sleep = 1000

        if IsEntityDead(playerPed) then goto END end

        mount = Citizen.InvokeNative(0xE7E11B8DCBED1058, playerPed) -- GetMount
        if mount and mount ~= 0 then
            mountNetId = NetworkGetNetworkIdFromEntity(mount)
            tamedNetId = Entity(mount).state.netId
        end

        for site, siteCfg in pairs(Trainers) do
            local distance = #(GetEntityCoords(playerPed) - siteCfg.npc.coords)

            if siteCfg.blip.show and not siteCfg.TrainerBlip then
                AddTrainerBlip(site)
                Citizen.InvokeNative(0x662D364ABF16DE2F, siteCfg.TrainerBlip, joaat(Config.BlipColors[siteCfg.blip.color])) -- BlipAddModifier
            end

            if siteCfg.npc.active then
                if distance <= siteCfg.npc.distance then
                    if not siteCfg.TrainerNPC then
                        AddTrainerNPC(site)
                    end
                elseif siteCfg.TrainerNPC then
                    DeleteEntity(siteCfg.TrainerNPC)
                    siteCfg.TrainerNPC = nil
                end
            end

            if (distance <= siteCfg.shop.distance) and (IsPedOnMount(playerPed)) and (mountNetId == tamedNetId) and (not IsNaming) then
                sleep = 0
                UiPromptSetActiveGroupThisFrame(TameGroup, CreateVarString(10, 'LITERAL_STRING', siteCfg.shop.prompt), 1, 0, 0, 0)

                UiPromptSetVisible(SellTame, allowSale)
                UiPromptSetEnabled(SellTame, allowSale)

                UiPromptSetVisible(KeepTame, allowKeep)
                UiPromptSetEnabled(KeepTame, allowKeep)

                if Citizen.InvokeNative(0xE0F65F0640EF0617, SellTame) then  -- PromptHasHoldModeCompleted
                    local onCooldown = Core.Callback.TriggerAwait('jrs_stables:CheckPlayerCooldown', 'sellTame')
                    if onCooldown then
                        Core.NotifyRightTip(_U('sellCooldown'), 4000)
                        HorseBreed = false
                        goto END
                    end

                    if trainerOnly then
                        CheckPlayerJob(true, nil)
                        if not IsTrainer then
                            Core.NotifyRightTip(_U('trainerSellHorse'), 4000)
                            HorseBreed = false
                            goto END
                        end
                    end

                    TriggerServerEvent('jrs_stables:SellTamedHorse', GetEntityModel(mount))

                    if mount ~= 0 then
                        Citizen.InvokeNative(0x48E92D3DDE23C23A, playerPed, 0, 0, 0, 0, mount) -- TaskDismountAnimal

                        while not Citizen.InvokeNative(0x01FEE67DB37F59B2, playerPed) do -- IsPedOnFoot
                            Wait(10)
                        end

                        Core.NotifyRightTip(_U('tamedCooldown') .. Config.cooldown.sellTame .. _U('minutes'), 4000)
                        DeleteEntity(mount)
                        mount = 0
                        Wait(200)
                        HorseBreed = false
                    end
                end

                if Citizen.InvokeNative(0xE0F65F0640EF0617, KeepTame) then  -- PromptHasHoldModeCompleted
                    CheckPlayerJob(true, nil)
                    if trainerOnly then
                        if not IsTrainer then
                            Core.NotifyRightTip(_U('trainerRegHorse'), 4000)
                            HorseBreed = false
                            goto END
                        end
                    end

                    local tameData = {
                        isTrainer = IsTrainer,
                        ModelH = TamedModel,
                        origin = 'tameHorse',
                        IsCash = true,
                        gender = IsPedMale(mount) and 'male' or 'female',
                        mount = mount
                    }

                    local canKeep = Core.Callback.TriggerAwait('jrs_stables:RegisterHorse', tameData)
                    if canKeep then
                        SetHorseName(tameData)
                    else
                        HorseBreed = false
                    end
                end
            end
        end
        ::END::
        Wait(sleep)
    end
end)

AddEventHandler('jrs_stables:HorseMonitor', function()
    local intervalValue = Config.saveInterval * 1000
    local interval = intervalValue
    local checkInterval = 1000

    while MyHorse ~= 0 do
        Wait(checkInterval)

        interval = interval - checkInterval

        if interval <= 0 and not IsFleeing then
            SaveHorseStats(InWrithe)
            interval = intervalValue
        end
    end
end)


AddEventHandler('jrs_stables:ReviveHorse', function()
    local hasItem = Core.Callback.TriggerAwait('jrs_stables:HorseReviveItem')

    if not hasItem then
        Core.NotifyRightTip(_U('noReviver'), 4000)
        return
    end

    if not IsEntityDead(MyHorse) then
        Citizen.InvokeNative(0x356088527D9EBAAD, PlayerPedId(), MyHorse, `s_inv_horsereviver01x`) -- TaskReviveTarget
        TriggerServerEvent('jrs_stables:UpdateHorseStatus', MyHorseId, nil)
        SetEntityHealth(MyHorse, GetEntityMaxHealth(MyHorse), 0)
        SaveHorseStats(true)
        InWrithe = false
    end
end)

function OpenInventory(horsePedId, horseId, isLooting)
    local hasSaddlebags = Citizen.InvokeNative(0xFB4891BD7578CDC1, horsePedId, -2142954459) -- IsMetaPedUsingComponent

    if not isLooting and Config.useSaddlebags and not hasSaddlebags then
        Core.NotifyRightTip(_U('noSaddlebags'), 4000)
        return
    end

    if hasSaddlebags then
        Citizen.InvokeNative(0xCD181A959CFDD7F4, PlayerPedId(), horsePedId, `Interaction_LootSaddleBags`, 0, true) -- TaskAnimalInteraction
    end

    TriggerServerEvent('jrs_stables:OpenInventory', horseId)
end

function FleeHorse()
    IsFleeing = true
    SaveHorseStats(false)

    GetControlOfHorse()

    Citizen.InvokeNative(0x22B0D0E37CCB840D, MyHorse, PlayerPedId(), 150.0, 10000, 6, 3.0) -- TaskSmartFleePed
    Wait(10000)
    DeleteEntity(MyHorse)
    MyHorse = 0
    IsFleeing = false
end

function ReturnHorse()
    local playerPed = PlayerPedId()

    if not MyHorse or MyHorse == 0 then
        Core.NotifyRightTip(_U('noHorse'), 4000)
        return
    end

    if Citizen.InvokeNative(0x460BC76A0E10655E, playerPed) then -- IsPedOnMount
        Citizen.InvokeNative(0x48E92D3DDE23C23A, playerPed, 0, 0, 0, 0, MyHorse) -- TaskDismountAnimal
        while not Citizen.InvokeNative(0x01FEE67DB37F59B2, playerPed) do -- IsPedOnFoot
            Wait(10)
        end
    end

    SaveHorseStats(InWrithe)
    GetControlOfHorse()
    DeleteEntity(MyHorse)
    MyHorse = 0
    Core.NotifyRightTip(_U('horseReturned'), 4000)
end

function GetControlOfHorse()
    while not NetworkHasControlOfEntity(MyHorse) do
        NetworkRequestControlOfEntity(MyHorse)
        Wait(100)
    end
end

AddEventHandler('jrs_stables:HorseBonding', function()
    if Config.HorseTraining.enabled then return end
    local trainingDistance = Config.trainingDistance

    while not MaxBonding do
        Wait(5000)

        local playerPed = PlayerPedId()
        local lastLed = Citizen.InvokeNative(0x693126B5D0457D0D, playerPed)   -- GetLastLedMount
        local isLeading = Citizen.InvokeNative(0xEFC4303DDC6E60D3, playerPed) -- IsPedLeadingHorse
        local currentMount = Citizen.InvokeNative(0x4C8B59171957BCF7, playerPed) -- GetLastMount
        local isMounted = Citizen.InvokeNative(0x460BC76A0E10655E, playerPed) -- IsPedOnMount

        if ((lastLed == MyHorse and isLeading) or (MyHorse == currentMount and isMounted)) then
            local currentCoords = GetEntityCoords(MyHorse)

            if LastLoc == nil then
                LastLoc = currentCoords
            else
                local dist = #(LastLoc - currentCoords)
                if dist >= trainingDistance then
                    LastLoc = currentCoords
                    SaveXp('travel')
                end
            end
        end
    end
end)

function SaveXp(xpSource)
    if Config.HorseTraining.enabled then return end
    local horseXp = nil
    local updateXp = {
        ['travel'] = Config.horseXpPerCheck,
        ['brush'] = Config.horseXpPerBrush,
        ['feed'] = Config.horseXpPerFeed,
        ['drink'] = Config.horseXpPerDrink
    }

    horseXp = updateXp[xpSource]
    if not horseXp then
        return print('No xpSource Data!')
    end

    Citizen.InvokeNative(0x75415EE0CB583760, MyHorse, 7, horseXp) -- AddAttributePoints

    if Config.showXpMessage then
        Core.NotifyRightTip('+ ' .. horseXp .. ' XP', 2000)
    end

    local maxXp = Citizen.InvokeNative(0x223BF310F854871C, MyHorse, 7) -- GetMaxAttributePoints
    local newXp = Citizen.InvokeNative(0x219DA04BAA9CB065, MyHorse, 7, Citizen.ResultAsInteger()) -- GetAttributePoints

    MaxBonding = newXp >= maxXp

    TriggerServerEvent('jrs_stables:UpdateHorseXp', newXp, MyHorseId)
end

RegisterNetEvent('jrs_stables:BrushHorse', function()
    if not MyHorse or MyHorse == 0 then
        return Core.NotifyRightTip(_U('noHorse'), 4000)
    end

    local playerPed = PlayerPedId()
    local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(MyHorse))

    if distance > 3.5 then
        return Core.NotifyRightTip(_U('tooFar'), 4000)
    end

    ClearPedTasks(playerPed)

    if Config.horsebrush.durability then
        TriggerServerEvent('jrs_stables:HorseBrushDurability')
    end

    Citizen.InvokeNative(0xCD181A959CFDD7F4, playerPed, MyHorse, `Interaction_Brush`, `p_brushHorse02x`, true) -- TaskAnimalInteraction
    Wait(5000)
    Citizen.InvokeNative(0x6585D955A68452A5, MyHorse) -- ClearPedEnvDirt
    Citizen.InvokeNative(0x523C79AEEFCC4A2A, MyHorse, 10, 'ALL') -- ClearPedDamageDecalByZone
    Citizen.InvokeNative(0x8FE22675A5A45817, MyHorse) -- ClearPedBloodDamage

    local health = Citizen.InvokeNative(0x36731AC041289BB1, MyHorse, 0, Citizen.ResultAsInteger()) -- GetAttributeCoreValue
    local stamina = Citizen.InvokeNative(0x36731AC041289BB1, MyHorse, 1, Citizen.ResultAsInteger()) -- GetAttributeCoreValue

    local healthBoost = Config.boost.brushHealth
    local staminaBoost = Config.boost.brushStamina

    if healthBoost > 0 then
        local newHealth = math.min(health + healthBoost, 100)
        Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 0, newHealth) -- SetAttributeCoreValue
    end

    if staminaBoost > 0 then
        local newStamina = math.min(stamina + staminaBoost, 100)
        Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 1, newStamina) -- SetAttributeCoreValue
    end

    if (Config.horseXpPerBrush > 0) and (not MaxBonding) then
        if not Config.trainerOnly or IsTrainer then
            SaveXp('brush')
        end
    end

    Citizen.InvokeNative(0x67C540AA08E4A6F5, 'Core_Fill_Up', 'Consumption_Sounds', true, 0) -- PlaySoundFrontend
end)

RegisterNetEvent('jrs_stables:FeedHorse', function(item)
    if not MyHorse or MyHorse == 0 then
        return Core.NotifyRightTip(_U('noHorse'), 4000)
    end

    local playerPed = PlayerPedId()
    local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(MyHorse))

    if distance > 3.5 then
        Core.NotifyRightTip(_U('tooFar'), 4000)
        return
    end

    ClearPedTasks(playerPed)
    Citizen.InvokeNative(0xCD181A959CFDD7F4, playerPed, MyHorse, `Interaction_Food`, `s_horsnack_haycube01x`, true) -- TaskAnimalInteraction
    TriggerServerEvent('jrs_stables:RemoveItem', item)
    Wait(5000)

    local health = Citizen.InvokeNative(0x36731AC041289BB1, MyHorse, 0, Citizen.ResultAsInteger()) -- GetAttributeCoreValue
    local stamina = Citizen.InvokeNative(0x36731AC041289BB1, MyHorse, 1, Citizen.ResultAsInteger()) -- GetAttributeCoreValue

    local healthBoost = Config.boost.feedHealth
    local staminaBoost = Config.boost.feedStamina

    if healthBoost > 0 then
        local newHealth = math.min(health + healthBoost, 100)
        Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 0, newHealth) -- SetAttributeCoreValue
    end

    if staminaBoost > 0 then
        local newStamina = math.min(stamina + staminaBoost, 100)
        Citizen.InvokeNative(0xC6258F41D86676E0, MyHorse, 1, newStamina) -- SetAttributeCoreValue
    end

    if (Config.horseXpPerFeed > 0) and (not MaxBonding) then
        if not Config.trainerOnly or IsTrainer then
            SaveXp('feed')
        end
    end

    Citizen.InvokeNative(0x67C540AA08E4A6F5, 'Core_Fill_Up', 'Consumption_Sounds', true, 0) -- PlaySoundFrontend
end)

RegisterNetEvent('jrs_stables:FlamingHooves', function()
    if not MyHorse or MyHorse == 0 then
        return Core.NotifyRightTip(_U('noHorse'), 4000)
    end

    if Activated then return end

    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local horseCoords = GetEntityCoords(MyHorse)

    if #(playerCoords - horseCoords) > 3.5 then
        return Core.NotifyRightTip(_U('tooFar'), 4000)
    end

    ClearPedTasks(playerPed)

    Citizen.InvokeNative(0x1913FE4CBF41C463, MyHorse, 207, true) -- SetPedConfigFlag / PCF_FlamingHoovesActive
    Core.NotifyRightTip(_U('flameHoovesActivated'), 4000)
    Activated = true

    -- Check if durability system is enabled before adjusting durability
    if Config.flamingHooves.durability then
        TriggerServerEvent('jrs_stables:FlamingHoovesDurability')
    end

    -- Set a timer to deactivate the flaming hooves effect after the specified duration
    local duration = Config.flamingHooves.duration * 60000 -- Convert minutes to milliseconds
    Citizen.SetTimeout(duration, function()
        if DoesEntityExist(MyHorse) then
            Citizen.InvokeNative(0x1913FE4CBF41C463, MyHorse, 207, false)
            Core.NotifyRightTip(_U('flameHoovesDeactivated'), 4000)
            Activated = false
        end
    end)
end)

RegisterNetEvent('jrs_stables:UseLantern', function()
    if not MyHorse or MyHorse == 0 then
        return Core.NotifyRightTip(_U('noHorse'), 4000)
    end

    local playerPed = PlayerPedId()
    local distance = #(GetEntityCoords(playerPed) - GetEntityCoords(MyHorse))

    if distance > 3.5 then
        return Core.NotifyRightTip(_U('tooFar'), 4000)
    end

    ClearPedTasks(playerPed)

    if not UsingLantern then
        SetComponent(MyHorse, 0x635E387C)
        UsingLantern = true

        if Config.lantern.durability then
            TriggerServerEvent('jrs_stables:LanternDurability')
        end
    else
        Citizen.InvokeNative(0x0D7FFA1B2F69ED82, MyHorse, 0x635E387C, 0, 0) -- RemoveShopItemFromPed
        Citizen.InvokeNative(0xCC8CA3E88256E58F, MyHorse, false, true, true, true, false)    -- UpdatePedVariation
        UsingLantern = false
    end
end)

AddEventHandler('jrs_stables:TradeHorse', function()
    while MyHorse ~= 0 do
        local playerPed = PlayerPedId()
        local sleep = 1000
        local lastLed = Citizen.InvokeNative(0x693126B5D0457D0D, playerPed) -- GetLastLedMount
        local isLeading = Citizen.InvokeNative(0xEFC4303DDC6E60D3, playerPed) -- IsPedLeadingHorse

        if not IsEntityDead(playerPed) and lastLed == MyHorse and isLeading then
            local closestPlayer, closestDistance = GetClosestPlayer()
            if closestPlayer and closestDistance <= 2.0 then
                sleep = 0
                UiPromptSetActiveGroupThisFrame(TradeGroup, CreateVarString(10, 'LITERAL_STRING', HorseName), 1, 0, 0, 0)
                if Citizen.InvokeNative(0xE0F65F0640EF0617, TradeHorse) then  -- PromptHasHoldModeCompleted
                    local serverId = GetPlayerServerId(closestPlayer)
                    TriggerServerEvent('jrs_stables:SaveHorseTrade', serverId, MyHorseId)
                    FleeHorse()
                    break
                end
            end
        end
        Wait(sleep)
    end
end)

function GetClosestPlayer()
    local players = GetActivePlayers()
    local player = PlayerId()
    local coords = GetEntityCoords(PlayerPedId())
    local closestDistance = math.huge
    local closestPlayer = -1

    for _, playerId in ipairs(players) do
        if playerId ~= player then
            local targetCoords = GetEntityCoords(GetPlayerPed(playerId))
            local distance = #(coords - targetCoords)
            if distance < closestDistance then
                closestPlayer = playerId
                closestDistance = distance
            end
        end
    end

    return closestPlayer, closestDistance
end

-- Store the selection before any native wait; every horse starts with its own saved tack.
for category, categoryHash in pairs(StableTack.categories) do
    local label, removalHash = category, categoryHash
    RegisterNUICallback(label, function(data, cb)
        if not InMenu or StableWagonUI.IsActive() or not MyEntityID or TackSaving then return cb('ok') end
        local preview = MyEntity
        if tonumber(data.id) == -1 then
            TackState[label] = nil
            TackRemoved[label] = true
            cb('ok')
            RemoveComponent(removalHash, preview)
        else
            local item = StableTack.items[StableTack.Hash(data.hash)]
            if not item or item.category ~= label then return cb('ok') end
            TackState[label] = item.item.hash
            TackRemoved[label] = nil
            cb('ok')
            SetComponent(preview, item.item.hash)
        end
    end)
end

local function TackPedReady(entity)
    local deadline = GetGameTimer() + 5000
    while DoesEntityExist(entity) do
        if Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, entity) then return true end -- IsPedReadyToRender
        if GetGameTimer() >= deadline then return false end
        Wait(10)
    end
    return false
end

function ApplyHorseTack(entity, components)
    if not TackPedReady(entity) then return false end
    for _, hash in ipairs(StableTack.List(components)) do
        Citizen.InvokeNative(0xD3A7B003ED343FD9, entity, StableTack.Hash(hash), true, true, true)
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, entity, false, true, true, true, false)
    return true
end

function SetComponent(entity, hash)
    local component = StableTack.Hash(hash)
    if not component or not TackPedReady(entity) then return false end
    Citizen.InvokeNative(0xD3A7B003ED343FD9, entity, component, true, true, true)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, entity, false, true, true, true, false)
    return true
end

function RemoveComponent(category, entity)
    entity = entity or MyEntity
    if not category or not TackPedReady(entity) then return false end
    Citizen.InvokeNative(0xD710A5007C2AC539, entity, category, 0)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, entity, false, true, true, true, false)
    return true
end

RegisterNUICallback('sellHorse', function(data, cb)
    if StableWagonUI.IsActive() then return StableWagonUI.Handle('sellHorse', data, cb) end
    cb('ok')
    DeleteEntity(MyEntity)
    MyEntity = 0
    Cam = false

    local horseSold = Core.Callback.TriggerAwait('jrs_stables:SellMyHorse', data)
    if horseSold then
        StableMenu()
    end
end)

function SaveHorseStats(dead)
    local horse, id = MyHorse, MyHorseId
    if horse==0 or not id or not DoesEntityExist(horse) then return end
    local healthCore, staminaCore

    if not dead then
        healthCore = Citizen.InvokeNative(0x36731AC041289BB1, horse, 0, Citizen.ResultAsInteger())  -- GetAttributeCoreValue
        staminaCore = Citizen.InvokeNative(0x36731AC041289BB1, horse, 1, Citizen.ResultAsInteger()) -- GetAttributeCoreValue
    else
        healthCore = Config.death.health
        staminaCore = Config.death.stamina
        Citizen.InvokeNative(0xC6258F41D86676E0, horse, 0, healthCore)  -- SetAttributeCoreValue
        Citizen.InvokeNative(0xC6258F41D86676E0, horse, 1, staminaCore) -- SetAttributeCoreValue
    end

    Wait(100) -- Wait for the values to be set before saving

    if MyHorse==horse and MyHorseId==id then
        TriggerServerEvent('jrs_stables:SaveHorseStatsToDb', healthCore, staminaCore, id)
    end
end

-- View Horses While in Menu
function CreateCamera()
    local siteCfg = Stables[Site]
    local horseCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    SetCamCoord(horseCam, siteCfg.horse.camera.x, siteCfg.horse.camera.y, siteCfg.horse.camera.z + 1.2)
    SetCamActive(horseCam, true)
    PointCamAtCoord(horseCam, siteCfg.horse.coords.x - 0.5, siteCfg.horse.coords.y, siteCfg.horse.coords.z)

    DoScreenFadeOut(500)
    Wait(500)
    DoScreenFadeIn(500)

    RenderScriptCams(true, false, 0, false, false, 0)
end

function CameraLighting()
    CreateThread(function()
        local siteCfg = Stables[Site]
        local coords = siteCfg.horse.coords

        while Cam do
            Wait(0)
            Citizen.InvokeNative(0xD2D9E04C0DF927F4, coords.x, coords.y, coords.z + 3, 130, 130, 85, 4.0, 15.0) -- DrawLightWithRange
        end
    end)
end

-- -- Rotate Horses while Viewing
local function Rotation(dir)
    local entity = MyEntity ~= 0 and MyEntity or ShopEntity

    if entity ~= 0 then
        local currentHeading = GetEntityHeading(entity)
        SetEntityHeading(entity, (currentHeading + dir) % 360)
    end
end

RegisterNUICallback('rotate', function(data, cb)
    if StableWagonUI.IsActive() then return StableWagonUI.Handle('rotate', data, cb) end
    cb('ok')
    local direction = data.RotateHorse
    local dir = direction == 'left' and 1 or -1

    Rotation(dir)
end)

RegisterCommand(Config.commands.horseRespawn, function(source, args, rawCommand)
    Spawning = false
    WhistleSpawn()
end, false)

RegisterCommand(Config.commands.horseSetWild, function(source, args, rawCommand)
    if Config.devMode then
        local mount = Citizen.InvokeNative(0xE7E11B8DCBED1058, PlayerPedId()) -- GetMount

        Citizen.InvokeNative(0xAEB97D84CDF3C00B, mount, true) -- SetAnimalIsWild
        Citizen.InvokeNative(0xBCC76708E5677E1D, mount, true) -- ClearActiveAnimalOwner
        Citizen.InvokeNative(0x9FF1E042FA597187, mount, 97, false) -- SetAnimalTuningBoolParam
    else
        print('Command used in Developer Mode Only!') -- Not for use on live server
    end
end, false)

RegisterCommand(Config.commands.horseWrithe, function(source, args, rawCommand)
    if Config.devMode then
        Citizen.InvokeNative(0x8C038A39C4A4B6D6, MyHorse, 0, 0) -- TaskAnimalWrithe
    else
        print('Command used in Developer Mode Only!') -- Not for use on live server
    end
end, false)


function StartPrompts()
    OpenShops = UiPromptRegisterBegin()
    UiPromptSetControlAction(OpenShops, Config.keys.shop)
    UiPromptSetText(OpenShops, CreateVarString(10, 'LITERAL_STRING', _U('shopPrompt')))
    UiPromptSetVisible(OpenShops, true)
    UiPromptSetStandardMode(OpenShops, true)
    UiPromptSetGroup(OpenShops, ShopGroup, 0)
    UiPromptRegisterEnd(OpenShops)

    LootHorse = UiPromptRegisterBegin()
    UiPromptSetControlAction(LootHorse, Config.keys.loot)
    UiPromptSetText(LootHorse, CreateVarString(10, 'LITERAL_STRING', _U('lootHorsePrompt')))
    UiPromptSetVisible(LootHorse, true)
    UiPromptSetEnabled(LootHorse, true)
    UiPromptSetStandardMode(LootHorse, true)
    UiPromptSetGroup(LootHorse, LootGroup, 0)
    UiPromptRegisterEnd(LootHorse)
end

function HorseTargetPrompts(menuGroup)
    local currentLevel = Citizen.InvokeNative(0x147149F2E909323C, MyHorse, 7, Citizen.ResultAsInteger()) -- GetAttributeBaseRank

    if not PromptsStarted then
        HorseDrink = UiPromptRegisterBegin()
        UiPromptSetControlAction(HorseDrink, Config.keys.drink)
        UiPromptSetText(HorseDrink, CreateVarString(10, 'LITERAL_STRING', _U('drinkPrompt')))
        UiPromptSetVisible(HorseDrink, true)
        UiPromptSetStandardMode(HorseDrink, true)
        UiPromptSetGroup(HorseDrink, menuGroup, 0)
        UiPromptRegisterEnd(HorseDrink)

        HorseRest = UiPromptRegisterBegin()
        UiPromptSetControlAction(HorseRest, Config.keys.rest)
        UiPromptSetText(HorseRest, CreateVarString(10, 'LITERAL_STRING', _U('restPrompt')))
        UiPromptSetVisible(HorseRest, true)
        UiPromptSetStandardMode(HorseRest, true)
        UiPromptSetGroup(HorseRest, menuGroup, 0)
        UiPromptRegisterEnd(HorseRest)

        HorseSleep = UiPromptRegisterBegin()
        UiPromptSetControlAction(HorseSleep, Config.keys.sleep)
        UiPromptSetText(HorseSleep, CreateVarString(10, 'LITERAL_STRING', _U('sleepPrompt')))
        UiPromptSetVisible(HorseSleep, true)
        UiPromptSetStandardMode(HorseSleep, true)
        UiPromptSetGroup(HorseSleep, menuGroup, 0)
        UiPromptRegisterEnd(HorseSleep)

        HorseWallow = UiPromptRegisterBegin()
        UiPromptSetControlAction(HorseWallow, Config.keys.wallow)
        UiPromptSetText(HorseWallow, CreateVarString(10, 'LITERAL_STRING', _U('wallowPrompt')))
        UiPromptSetVisible(HorseWallow, true)
        UiPromptSetStandardMode(HorseWallow, true)
        UiPromptSetGroup(HorseWallow, menuGroup, 0)
        UiPromptRegisterEnd(HorseWallow)

        PromptsStarted = true
    end

    local prompts = {
        {level = 1, prompt = HorseDrink},
        {level = 2, prompt = HorseRest},
        {level = 3, prompt = HorseSleep},
        {level = 4, prompt = HorseWallow}
    }

    for _, item in ipairs(prompts) do
        UiPromptSetEnabled(item.prompt, currentLevel >= item.level)
    end
end

function CheckPlayerJob(trainer, site)
    local result = Core.Callback.TriggerAwait('jrs_stables:CheckJob', trainer, site)

    IsTrainer = false
    HasJob = false

    if result then
        if trainer and result[1] then
            IsTrainer = true
        elseif result[1] then
            HasJob = true
        end

        if not trainer and result[2] then
            JobMatchedHorses = FindHorsesByJob(result[2])
            for _, breed in pairs(JobMatchedHorses) do
                for model, color in pairs(breed.colors) do color.training = HorseAbilities.Stats(model,0,0) end
            end
        end

        if not trainer and not result[1] and Stables[site].shop.jobsEnabled then
            Core.NotifyRightTip(_U('needJob'), 4000)
        end
    end
end

function AddTrainerBlip(site)
    local siteCfg = Trainers[site]

    siteCfg.TrainerBlip = Citizen.InvokeNative(0x554d9d53f696d002, 1664425300, siteCfg.npc.coords) -- BlipAddForCoords
    SetBlipSprite(siteCfg.TrainerBlip, siteCfg.blip.sprite, true)
    Citizen.InvokeNative(0x9CB1A1623062F402, siteCfg.TrainerBlip,  siteCfg.blip.name) -- SetBlipName
end

function AddTrainerNPC(site)
    local siteCfg = Trainers[site]
    local coords = siteCfg.npc.coords

    local modelName = siteCfg.npc.model
    local model = joaat(modelName)
    LoadModel(model, modelName)

    siteCfg.TrainerNPC = CreatePed(model, coords.x, coords.y, coords.z - 1.0, siteCfg.npc.heading, false, false, false, false)
    Citizen.InvokeNative(0x283978A15512B2FE, siteCfg.TrainerNPC, true) -- SetRandomOutfitVariation
    SetEntityCanBeDamaged(siteCfg.TrainerNPC, false)
    SetEntityInvincible(siteCfg.TrainerNPC, true)
    Wait(500)
    FreezeEntityPosition(siteCfg.TrainerNPC, true)
    SetBlockingOfNonTemporaryEvents(siteCfg.TrainerNPC, true)
end

function LoadModel(model, modelName)
    if not IsModelValid(model) then
        return print('Invalid model:', modelName)
    end

    if not HasModelLoaded(model) then
        RequestModel(model, false)

        local timeout = 10000
        local startTime = GetGameTimer()

        while not HasModelLoaded(model) do
            if GetGameTimer() - startTime > timeout then
                print('Failed to load model:', modelName)
                return
            end
            Wait(10)
        end
    end
end

 -- Update Global Horse Entity after session change
RegisterNetEvent('jrs_stables:UpdateMyHorseEntity', function()
    if MyHorse ~= 0 then
        MyHorse = NetworkGetEntityFromNetworkId(LocalPlayer.state.HorseData.MyHorse)
    end
end)

-- to count length of maps
local function len(t)
    local counter = 0
    for _ in pairs(t) do
        counter = counter + 1
    end
    return counter
end

-- to generate ordered index
local function __genOrderedIndex( t )
    local orderedIndex = {}
    for key in pairs(t) do
        table.insert(orderedIndex, key)
    end
    table.sort(orderedIndex)
    return orderedIndex
end

-- to get the next ordered pair
local function orderedNext(t, state)
    if state == nil then
        t.__orderedIndex = __genOrderedIndex(t)
        t.__index = 1
    else
        t.__index = t.__index + 1
    end

    local key = t.__orderedIndex[t.__index]
    if key then
        return key, t[key]
    end

    t.__orderedIndex = nil
    t.__index = nil
    return
end

-- to get ordered pairs
local function orderedPairs(t)
    return orderedNext, t, nil
end

function FindHorsesByJob(job)
    local matchingHorses = {}
    for _, horseType in ipairs(Horses) do
        local matchingColors = {}

        for horseColor, horseColorData in orderedPairs(horseType.colors) do
            local horseJobs = {}
            for _, horseJob in pairs(horseColorData.job) do
                horseJobs[horseJob] = true
            end

            if horseJobs[job] then
                matchingColors[horseColor] = {
                    color = horseColorData.color,
                    cashPrice = horseColorData.cashPrice,
                    goldPrice = horseColorData.goldPrice,
                    invLimit = horseColorData.invLimit,
                    job = horseColorData.job
                }
            end

            if len(horseJobs) == 0 then
                matchingColors[horseColor] = {
                    color = horseColorData.color,
                    cashPrice = horseColorData.cashPrice,
                    goldPrice = horseColorData.goldPrice,
                    invLimit = horseColorData.invLimit,
                    job = nil
                }
            end
        end

        if len(matchingColors) > 0 then
            table.insert(matchingHorses, {
                breed = horseType.breed,
                colors = matchingColors
            })
        end
    end
    return matchingHorses
end

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    if InMenu then
        SendNUIMessage({ action = 'hide' })
        SetNuiFocus(false, false)
    end

    ClearPedTasksImmediately(PlayerPedId())
    DestroyAllCams(true)
    DisplayRadar(true)

    if ShopEntity ~= 0 then
        DeleteEntity(ShopEntity)
        ShopEntity = 0
    end

    if MyEntity ~= 0 then
        DeleteEntity(MyEntity)
        MyEntity = 0
    end

    if MyHorse ~= 0 then
        DeleteEntity(MyHorse)
        MyHorse = 0
    end

    for _, siteCfg in pairs(Stables) do
        if siteCfg.Blip then
            RemoveBlip(siteCfg.Blip)
            siteCfg.Blip = nil
        end
        if siteCfg.NPC then
            DeleteEntity(siteCfg.NPC)
            siteCfg.NPC = nil
        end
    end

    for _, siteCfg in pairs(Trainers) do
        if siteCfg.TrainerBlip then
            RemoveBlip(siteCfg.TrainerBlip)
            siteCfg.TrainerBlip = nil
        end
        if siteCfg.TrainerNPC then
            DeleteEntity(siteCfg.TrainerNPC)
            siteCfg.TrainerNPC = nil
        end
    end

    CleanupAnimalInfoHud()
end)


-- Narrow bridge to the existing horse menu; the wagon module owns its own entities.
StableMenuBridge = {
    ClearPreview = function()
        ClearShopHorse()
        Cam = false
        DestroyAllCams(true)
    end,
    Close = function() if InMenu then CloseStableMenu({ MenuAction='cancel' }) end end,
    BeginWagon = function() InMenu=true; DisplayRadar(false) end,
    ShowHorses = function()
        if not InMenu or not Site then return end
        StableWagonUI.SetStableContext(Site)
        ClearShopHorse()
        Cam = false
        DestroyAllCams(true)
        CreateCamera()
        SendNUIMessage({ action='hide' })
        Wait(30)
        if InMenu then StableMenu() end
    end,
}
RegisterNetEvent('jrs_core:client:characterUnloaded', function()
    if InMenu then CloseStableMenu({MenuAction='cancel'}) end
    if MyHorse ~= 0 then DeleteEntity(MyHorse); MyHorse=0 end
    CleanupAnimalInfoHud()
end)


-- Local horse state shared with the JRS mouse actions and training adapter.
StableHorseBridge = {
    Context=function() return InMenu and not StableWagonUI.IsActive(), Site end,
    Current=function() return MyHorse, MyHorseId, InWrithe end,
    Refresh=function() StableMenu() end,
    Close=function() CloseStableMenu({MenuAction='cancel'}) end,
    Return=function(id)
        if MyHorse~=0 and (not id or tonumber(MyHorseId)==tonumber(id)) then
            if DoesEntityExist(MyHorse) and not IsEntityDead(MyHorse) and not InWrithe then SaveHorseStats(false) end
            DeleteEntity(MyHorse); MyHorse=0; MyHorseId=nil; InWrithe=false; PromptsStarted=false
            TriggerServerEvent('jrs_stables:horse:cleanup')
        end
    end,
}
