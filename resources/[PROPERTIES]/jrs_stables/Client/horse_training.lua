-- jrs_stables | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
local Core = exports.jrs_core:GetCore()
local Settings = Config.HorseTraining
local busy, training, generation = false, nil, 0
local abilityPed, abilityStats
StableHorseTraining = {}
local function notify(key) Core.NotifyRightTip(HorseText(key), 4000) end
local function request(action, data)
    local success, result = pcall(Core.Callback.TriggerAwait, 'jrs_stables:horse:'..action, data)
    return success and type(result)=='table' and result or {ok=false,code='horseUnavailable'}
end
function StableHorseTraining.Apply(ped, stats)
    if not Settings.enabled or not stats or not DoesEntityExist(ped) then return end
    abilityPed,abilityStats = ped,stats
    local health = GetEntityHealth(ped)
    Citizen.InvokeNative(0x5DA12E025D47D4E5,ped,0,stats.health.value) -- SET_ATTRIBUTE_BASE_RANK / health
    Citizen.InvokeNative(0x5DA12E025D47D4E5,ped,1,stats.stamina.value) -- stamina
    local points = Citizen.InvokeNative(0x94A7F191DB49A44D,GetEntityModel(ped),7,stats.level) -- rank threshold
    Citizen.InvokeNative(0x09A59688C26D88DF,ped,7,points) -- SET_ATTRIBUTE_POINTS / bonding
    Citizen.InvokeNative(0x5DA12E025D47D4E5,ped,7,stats.level)
    if health > 0 then SetEntityHealth(ped,math.min(health,GetEntityMaxHealth(ped)),0) end
    SetPedConfigFlag(ped,113,stats.level>=2)
    SetPedConfigFlag(ped,312,stats.level>=3)
end
function StableHorseTraining.Register(ped, row)
    CreateThread(function()
        for _=1,5 do
            local current,id = StableHorseBridge.Current()
            if current~=ped or tonumber(id)~=tonumber(row.id) or not DoesEntityExist(ped) then return end
            local result = request('register',{id=row.id,netId=NetworkGetNetworkIdFromEntity(ped)})
            if result.ok then StableHorseTraining.Apply(ped,result.data.training); return end
            Wait(250)
        end
        notify('horseCallFirst')
    end)
end
local function endTraining(success)
    if not training then return end
    if training.stat=='health' then ClearPedTasks(PlayerPedId()) end
    training = nil
    notify(success and 'horseTrainingComplete' or 'horseTrainingCancelled')
end
RegisterNUICallback('horseAction',function(data,cb)
    local inMenu,site = StableHorseBridge.Context()
    if not inMenu or busy or training or type(data)~='table' then return cb({ok=false,code='horseBusy'}) end
    local action = data.action
    if action~='select' and action~='call' and action~='revive' and action~='trainHealth' and action~='trainStamina' then
        return cb({ok=false,code='horseInvalid'})
    end
    busy = true
    local actionGeneration = generation
    local name = (action=='call' and 'select') or (action=='trainHealth' or action=='trainStamina') and 'train' or action
    local result = request(name,{id=data.id,site=site,stat=action=='trainHealth' and 'health' or 'stamina'})
    if actionGeneration~=generation then return cb({ok=false,code='horseBusy'}) end
    if result.ok then
        local stillOpen,currentSite = StableHorseBridge.Context()
        if action=='select' or action=='call' then
            local ped,id = StableHorseBridge.Current()
            if ped~=0 and tonumber(id)~=tonumber(result.data.id) then StableHorseBridge.Return() end
            SendNUIMessage({action='horse:selected',row=result.data})
            if action=='call' and stillOpen and currentSite==site then
                StableHorseBridge.Close()
                SpawnHorse(result.data)
            elseif action=='select' then notify('horseSelectedNotice') end
        elseif action=='revive' then
            StableHorseBridge.Return(result.data.id)
            SendNUIMessage({action='horse:status',row=result.data})
            notify('horseRevivedNotice')
        else
            if not stillOpen or currentSite~=site then
                TriggerServerEvent('jrs_stables:horse:cancel')
                busy=false
                return cb({ok=false,code='horseBusy'})
            end
            training = result.data
            StableHorseBridge.Close()
            notify(training.stat=='health' and 'horseHealthStarted' or 'horseStaminaStarted')
            if training.stat=='health' then
                local horse = StableHorseBridge.Current()
                Citizen.InvokeNative(0xCD181A959CFDD7F4,PlayerPedId(),horse,`Interaction_Brush`,`p_brushHorse02x`,true)
            end
        end
    else notify(result.code or 'horseUnavailable') end
    busy = false
    cb(result)
end)
RegisterNetEvent('jrs_stables:horse:progress',function(row)
    local ped,id = StableHorseBridge.Current()
    if tonumber(id)==tonumber(row.id) then
        StableHorseTraining.Apply(ped,row.training)
        TriggerEvent('jrs_stables:HorsePrompts')
    end
    SendNUIMessage({action='horse:status',row=row})
end)
RegisterNetEvent('jrs_stables:horse:trainingEnded',function(success) endTraining(success) end)
RegisterNetEvent('jrs_stables:horse:revived',function(id) StableHorseBridge.Return(id) end)
-- Native bonding can grow from ordinary riding; keep the configured training level authoritative.
CreateThread(function()
    while true do
        Wait(2000)
        local ped = StableHorseBridge.Current()
        if ped~=0 and ped==abilityPed and abilityStats and DoesEntityExist(ped) then
            local level = Citizen.InvokeNative(0x147149F2E909323C,ped,7,Citizen.ResultAsInteger())
            if level~=abilityStats.level then StableHorseTraining.Apply(ped,abilityStats) end
        end
    end
end)
CreateThread(function()
    while true do
        local sleep = training and 0 or 500
        if training and IsControlJustPressed(0,Settings.cancelKey) then
            TriggerServerEvent('jrs_stables:horse:cancel')
            endTraining(false)
        end
        Wait(sleep)
    end
end)
local function cleanup()
    generation = generation + 1
    abilityPed,abilityStats = nil,nil
    endTraining(false)
    StableHorseBridge.Return()
    TriggerServerEvent('jrs_stables:horse:cleanup')
    busy = false
end
RegisterNetEvent('jrs_core:client:characterUnloaded',cleanup)
AddEventHandler('onResourceStop',function(resource) if resource==GetCurrentResourceName() then cleanup() end end)
