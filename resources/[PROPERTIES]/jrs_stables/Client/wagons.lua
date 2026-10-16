-- jrs_stables | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- The wagon family reuses the existing stable Vue menu and its mouse controls.
local Core = exports.jrs_core:GetCore()
local Settings = Config.Wagons
local family, site, visible, busy, preview, camera = 'horse', nil, false, false, 0, nil
local myWagon, myData, selected, pending, previewGeneration = 0, nil, nil, nil, 0
local brakeSet, brakeApplied, wagonBlip, wagonTag = false, nil, nil, nil
local ownedRows = {}
local menuGeneration = 0
local models = {}
for _,category in ipairs(StableWagons) do for model,cfg in pairs(category.types) do models[model] = cfg end end
StableWagonUI = {}

local function notify(key) Core.NotifyRightTip(WagonText(key), 4000) end
local function request(name, data)
    local success,result = pcall(Core.Callback.TriggerAwait, 'jrs_stables:wagon:' .. name, data or {})
    if not success or type(result) ~= 'table' then return { ok=false, code='unavailable' } end
    return result
end
local function report(result, successKey)
    if result.ok then if successKey then notify(successKey) end
    else notify(result.code or 'invalid') end
    return result.ok == true
end
local function status(row)
    row = row or selected
    SendNUIMessage({ action='wagon:status', id=row and row.id,
        condition=row and row.condition, maxCondition=row and row.maxCondition,
        activeId=myData and myData.id })
end
local function clearPreview()
    previewGeneration = previewGeneration + 1
    if preview ~= 0 then DeleteEntity(preview); preview = 0 end
end
local function clearCamera()
    if camera then RenderScriptCams(false, false, 0, true, true, 0); DestroyCam(camera, false); camera = nil end
end
local function load(model)
    local hash, started = joaat(model), GetGameTimer()
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        if GetGameTimer()-started > 5000 then return nil end
        Wait(10)
    end
    return hash
end
local function clearActive(remove)
    if wagonBlip then RemoveBlip(wagonBlip); wagonBlip = nil end
    if wagonTag then Citizen.InvokeNative(0x839BFD7D7E49FE09, Citizen.PointerValueIntInitialized(wagonTag)); wagonTag = nil end
    if remove and myWagon ~= 0 and DoesEntityExist(myWagon) then DeleteEntity(myWagon) end
    myWagon, myData, brakeSet, brakeApplied = 0, nil, false, nil
    if visible then status() end
end
-- Parking is a player choice; damage temporarily prevents movement separately.
local function applyBrake()
    if myWagon == 0 or not myData or not DoesEntityExist(myWagon) then return end
    local shouldBrake = brakeSet or myData.condition <= 0
    if brakeApplied == shouldBrake then return end
    if shouldBrake then Citizen.InvokeNative(0x260BE8F09E326A20, myWagon, 0.0, 2000, true)
    else Citizen.InvokeNative(0x7C06330BFDDA182E, myWagon) end
    brakeApplied = shouldBrake
end
local function updateCondition(id, value, max)
    if myData and myData.id == id then
        myData.condition, myData.maxCondition = value, max
        applyBrake()
    end
    if selected and selected.id == id then selected.condition, selected.maxCondition = value, max end
    if visible then status() end
end
local function position()
    local cfg = site and WagonSites[site]
    if cfg then return cfg.wagon.coords, cfg.wagon.heading, cfg.wagon.camera end
    if site and Stables[site] then
        local horse = Stables[site].horse
        return horse.coords, horse.heading, horse.camera
    end
    if myWagon ~= 0 and DoesEntityExist(myWagon) then
        return GetEntityCoords(myWagon), GetEntityHeading(myWagon), GetOffsetFromEntityInWorldCoords(myWagon, 6.0, -7.0, 3.0)
    end
end
local function makeCamera()
    clearCamera()
    local coords,_,camCoords = position()
    if not coords then return end
    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camera, camCoords.x, camCoords.y, camCoords.z + 1.0)
    PointCamAtCoord(camera, coords.x, coords.y, coords.z + 0.8)
    SetCamFov(camera, 55.0)
    RenderScriptCams(true, false, 0, true, true, 0)
end
local function showPreview(model)
    if not models[model] or not visible or family ~= 'wagon' then return end
    if not site then return end -- The active wagon itself is visible in a roadside menu.
    clearPreview()
    local generation = previewGeneration
    local hash = load(model)
    if not hash then return notify('spawnFailed') end
    if generation ~= previewGeneration or not visible or family ~= 'wagon' then SetModelAsNoLongerNeeded(hash); return end
    local coords,heading = position()
    if not coords then SetModelAsNoLongerNeeded(hash); return end
    preview = CreateVehicle(hash, coords, heading, false, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if preview == 0 then return notify('spawnFailed') end
    Citizen.InvokeNative(0x7263332501E07F52, preview, true)
    SetEntityCollision(preview, false, false)
    FreezeEntityPosition(preview, true)
    SetEntityInvincible(preview, true)
end
function StableWagonUI.IsActive() return family == 'wagon' and visible end
function StableWagonUI.Translations() return StableTranslations(family) end
function StableWagonUI.SetStableContext(value)
    menuGeneration = menuGeneration + 1
    site, family, visible = value, 'horse', true
    clearPreview(); clearCamera()
end
function StableWagonUI.Close()
    menuGeneration = menuGeneration + 1
    clearPreview(); clearCamera()
    visible, pending, family, site = false, nil, 'horse', nil
    exports.jrs_core:ReleaseUI('jrs_stables', { manageFocus=false })
end
function StableWagonUI.Show()
    local generation = menuGeneration
    local result = request('menu', { site=site })
    if generation ~= menuGeneration then return false end
    if not report(result) then return false end
    local payload = result.data
    ownedRows = {}
    for _,row in ipairs(payload.owned) do ownedRows[tonumber(row.id)] = row end
    if StableMenuBridge then StableMenuBridge.ClearPreview() end
    family,visible = 'wagon',true
    selected = nil
    for _,row in ipairs(payload.owned) do if tonumber(row.selected) == 1 then selected = row; break end end
    clearPreview(); makeCamera()
    SendNUIMessage({ action='hide' })
    Wait(30)
    if generation ~= menuGeneration or not visible or family ~= 'wagon' then return false end
    SendNUIMessage({ action='show', family='wagon', language=StableLanguage(),
        shopData=payload.catalog, compData={}, translations=StableTranslations('wagon'),
        location=site and StableTitle(site) or WagonText('menuPrompt'), currencyType=Settings.currencyType,
        myHorsesData=payload.owned, canSwitch=site ~= nil, canTrade=site ~= nil })
    SetNuiFocus(true, true)
    status()
    return true
end
local function closeMenu()
    if StableMenuBridge then StableMenuBridge.Close() end
end
local function callWagon()
    if myWagon ~= 0 and DoesEntityExist(myWagon) then return notify('alreadyOut') end
    local result = request('prepare', { id=selected and selected.id, site=site })
    if not report(result) then return end
    local spawn = result.data
    local hash = load(spawn.row.model)
    if not hash then request('cancelSpawn', { token=spawn.token }); return notify('spawnFailed') end
    local coords,heading
    if site then coords,heading = position() end
    if not coords then
        local current = GetEntityCoords(PlayerPedId())
        local found,node,dir = GetClosestVehicleNodeWithHeading(current.x, current.y, current.z, 1, 3.0, 0)
        if found and #(node-current) < 80 then coords,heading = node,dir
        else coords,heading = GetOffsetFromEntityInWorldCoords(PlayerPedId(),0.0,-7.0,0.0),GetEntityHeading(PlayerPedId()) end
    end
    clearPreview()
    local entity = CreateVehicle(hash, coords, heading, true, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if entity == 0 then request('cancelSpawn', { token=spawn.token }); return notify('spawnFailed') end
    Citizen.InvokeNative(0x7263332501E07F52, entity, true)
    local netId,started = NetworkGetNetworkIdFromEntity(entity),GetGameTimer()
    while netId == 0 and GetGameTimer()-started < 4000 do Wait(50); netId = NetworkGetNetworkIdFromEntity(entity) end
    Wait(150) -- Allow network creation to reach the server before validation.
    local committed = request('commit', { token=spawn.token, netId=netId })
    if not report(committed) then DeleteEntity(entity); request('cancelSpawn',{ token=spawn.token }); return end
    myWagon,myData = entity,spawn.row
    myData.condition,myData.maxCondition = committed.data.condition,committed.data.maxCondition
    Citizen.InvokeNative(0xD0E02AA618020D17, PlayerId(), myWagon)
    Citizen.InvokeNative(0xE2487779957FE897, myWagon, 528)
    local cfg = models[myData.model]
    if cfg.blip.enabled then
        wagonBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, -1749618580, myWagon)
        SetBlipSprite(wagonBlip, joaat(cfg.blip.sprite), true)
        Citizen.InvokeNative(0x9CB1A1623062F402, wagonBlip, myData.name)
    end
    if Settings.showNames and cfg.gamerTag.enabled then
        wagonTag = Citizen.InvokeNative(0xE961BF23EAB76B12, myWagon, myData.name)
    end
    brakeSet, brakeApplied = cfg.brakeSet == true, nil
    applyBrake()
    local wasMenu = visible
    closeMenu()
    if wasMenu and Settings.seated then SetPedIntoVehicle(PlayerPedId(),myWagon,-1) end
end
local function returnWagon()
    local result = request('return', { site=site })
    if report(result,'returned') then clearActive(true); if visible then StableWagonUI.Show() end end
end
local function cargo(id)
    local result = request('cargo', { id=id or selected and selected.id or myData and myData.id })
    if report(result) then closeMenu(); Wait(100); TriggerServerEvent('jrs_stables:wagon:openCargo', result.data.id) end
end
local function startName(kind,data)
    pending = { kind=kind, model=data.ModelH, cash=data.IsCash, id=data.horseId, token=GetGameTimer() }
    SendNUIMessage({ action='wagon:name', token=pending.token, title=WagonText('name'),
        confirm=WagonText('confirm'), cancel=WagonText('cancel') })
end
function StableWagonUI.Handle(action,data,cb)
    cb('ok')
    if not StableWagonUI.IsActive() then return end
    if action == 'rotate' then
        if preview ~= 0 then SetEntityHeading(preview,(GetEntityHeading(preview)+(data.RotateHorse == 'left' and 1 or -1))%360) end
    elseif action == 'loadHorse' then showPreview(data.horseModel)
    elseif action == 'loadMyHorse' then
        local row = ownedRows[tonumber(data.HorseId)]
        if row then selected = row; status(row); showPreview(row.model) end
    elseif action == 'BuyHorse' then startName('buy',data)
    elseif action == 'RenameHorse' then startName('rename',data)
    elseif action == 'selectHorse' then
        local result = request('select',{ id=data.horseId })
        if report(result) then status(result.data) end
    elseif action == 'sellHorse' then
        local result = request('sell',{ id=data.horseId, site=site })
        if report(result,'sold') then StableWagonUI.Show() end
    end
end
RegisterNUICallback('stableFamily', function(data,cb)
    cb('ok')
    if not visible or not site or not Settings.enabled or busy then return end
    busy = true
    if data.family == 'wagon' then StableWagonUI.Show()
    elseif data.family == 'horse' then
        family = 'horse'; clearPreview(); clearCamera()
        if StableMenuBridge then StableMenuBridge.ShowHorses() end
    end
    busy = false
end)
RegisterNUICallback('wagonSubmitName',function(data,cb)
    cb('ok')
    if not pending or data.token ~= pending.token or not StableWagonUI.IsActive() or busy then return end
    if data.cancel then pending = nil; return end
    local operation = pending
    pending,busy = nil,true
    local result = request(operation.kind,{ site=site, name=data.name, model=operation.model, cash=operation.cash, id=operation.id })
    if report(result,operation.kind == 'buy' and 'purchased' or 'renamed') then StableWagonUI.Show() end
    busy = false
end)
RegisterNUICallback('wagonAction',function(data,cb)
    cb('ok')
    if not StableWagonUI.IsActive() or busy then return end
    busy = true
    if data.action == 'call' then callWagon()
    elseif data.action == 'returnWagon' then returnWagon()
    elseif data.action == 'cargo' then cargo()
    elseif data.action == 'repair' then
        local id = selected and selected.id or myData and myData.id
        local result = request('repair',{ id=id })
        if report(result,'repaired') then updateCondition(id, result.data.condition, result.data.maxCondition) end
    elseif data.action == 'trade' then
        local result = request('trade',{ id=selected and selected.id, target=data.target })
        if report(result,'traded') then StableWagonUI.Show() end
    end
    busy = false
end)
RegisterNetEvent('jrs_stables:wagon:condition',function(id,value,max)
    updateCondition(id, value, max)
end)
RegisterNetEvent('jrs_stables:wagon:removed',function() clearActive(true) end)
RegisterNetEvent('jrs_stables:wagon:refresh',function() if StableWagonUI.IsActive() then StableWagonUI.Show() end end)
AddEventHandler('jrs_core:language:changed',function()
    if visible then
        if family == 'wagon' then StableWagonUI.Show()
        elseif StableMenuBridge then StableMenuBridge.ShowHorses() end
    end
end)
RegisterCommand(Settings.commands.call,function() if not busy then busy=true; callWagon(); busy=false end end,false)
RegisterCommand(Settings.commands.returnWagon,function() if not busy then busy=true; returnWagon(); busy=false end end,false)
RegisterCommand(Settings.commands.cargo,function() if not busy then busy=true; cargo(); busy=false end end,false)

local function cleanup()
    closeMenu(); clearActive(true); clearPreview(); clearCamera()
    busy,pending,site,selected,ownedRows = false,nil,nil,nil,{}
    TriggerServerEvent('jrs_stables:wagon:cleanup')
end
RegisterNetEvent('jrs_core:client:characterUnloaded',cleanup)
AddEventHandler('onResourceStop',function(resource) if resource == GetCurrentResourceName() then cleanup() end end)
-- Controls must be sampled every frame while playing so a short J press is not missed.
CreateThread(function()
    while true do
        local sleep = 250
        if Settings.enabled and Settings.callEnabled and Settings.keys.call
            and LocalPlayer.state.CharacterReady == true
            and not visible and not busy and not IsEntityDead(PlayerPedId())
            and not IsPauseMenuActive() and not IsNuiFocused() and UpdateOnscreenKeyboard() ~= 0
            and not exports.jrs_core:IsUIBusy('jrs_stables') then
            sleep = 0
            if IsControlJustReleased(0, Settings.keys.call) then
                busy = true
                callWagon()
                busy = false
            end
        end
        Wait(sleep)
    end
end)
CreateThread(function()
    local group = GetRandomIntInRange(1,0xFFFFFF)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt,Settings.keys.menu)
    PromptSetText(prompt,CreateVarString(10,'LITERAL_STRING',WagonText('menuPrompt')))
    PromptSetEnabled(prompt,true); PromptSetVisible(prompt,true); PromptSetStandardMode(prompt,true)
    PromptSetGroup(prompt,group,0); PromptRegisterEnd(prompt)
    while true do
        local sleep,ped = 1000,PlayerPedId()
        if not visible and not IsEntityDead(ped) then
            local coords = GetEntityCoords(ped)
            local vehicle = Citizen.InvokeNative(0x52F45D033645181B,coords.x,coords.y,coords.z,5.0,0,70,Citizen.ResultAsInteger())
            local wagonId = vehicle ~= 0 and Entity(vehicle).state.jrsStableWagonId
            if wagonId then
                sleep = 0
                PromptSetText(prompt,CreateVarString(10,'LITERAL_STRING',WagonText(vehicle == myWagon and 'menuPrompt' or 'cargo')))
                PromptSetActiveGroupThisFrame(group,CreateVarString(10,'LITERAL_STRING',myData and vehicle == myWagon and myData.name or WagonText('wagons')),1,0,0,0)
                if Citizen.InvokeNative(0xC92AC953F0A982AE,prompt) and not busy then
                    busy = true
                    if vehicle == myWagon then
                        if exports.jrs_core:AcquireUI('jrs_stables',{ focus=true,cursor=true,manageFocus=false,kind='stable' }) then
                            site = nil
                            if StableMenuBridge then StableMenuBridge.BeginWagon() end
                            if not StableWagonUI.Show() then closeMenu() end
                        end
                    else cargo(wagonId) end
                    busy = false
                end
            end
        end
        if myWagon ~= 0 and DoesEntityExist(myWagon) and myData then
            local cfg = models[myData.model]
            if wagonTag and (not Settings.showNames or not cfg.gamerTag.enabled) then
                Citizen.InvokeNative(0x839BFD7D7E49FE09, Citizen.PointerValueIntInitialized(wagonTag))
                wagonTag = nil
            elseif wagonTag then
                local distance = #(GetEntityCoords(ped)-GetEntityCoords(myWagon))
                Citizen.InvokeNative(0x93171DDDAB274EB8,wagonTag,distance < cfg.gamerTag.distance and GetVehiclePedIsIn(ped,false) ~= myWagon and 3 or 0)
            end
            applyBrake()
            if GetPedInVehicleSeat(myWagon,-1) == ped and not visible then
                sleep = 0
                if IsControlJustReleased(0,Settings.keys.brake) then
                    if myData.condition <= 0 then notify('broken')
                    else
                        brakeSet = not brakeSet
                        applyBrake()
                        notify(brakeSet and 'brakeOn' or 'brakeOff')
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
